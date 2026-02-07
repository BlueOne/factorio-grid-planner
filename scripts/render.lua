-- Renderer for Zone Planner
-- Draws per-cell overlays using Factorio rendering API, tinted by zone color.

local render = {}

local backend = require("scripts/backend")

---@class ZP.RenderStorageRoot
---@field forces table<uint, ZP.RenderForceState>  -- by force_index

---@class ZP.RenderCellVariant
---@field game LuaRenderObject|nil
---@field chart LuaRenderObject|nil

---@class ZP.RenderCell
---@field zone_id uint|nil
---@field x_scale number|nil
---@field y_scale number|nil
---@field variants {[1]: ZP.RenderCellVariant|nil, [2]: ZP.RenderCellVariant|nil, [3]: ZP.RenderCellVariant|nil}

---@class ZP.RenderSurfaceState
---@field cells table<string, ZP.RenderCell>  -- cells stored per-force/per-surface

---@class ZP.RenderForceState
---@field surfaces table<uint, ZP.RenderSurfaceState>  -- surface_index -> surface state

local function ensure_state()
  storage.zp_render = storage.zp_render or { forces = {} }
  return storage.zp_render
end

local function ensure_force_state(force_index)
  local s = ensure_state()
  local f = s.forces[force_index]
  if not f then
    f = { surfaces = {} }
    s.forces[force_index] = f
  end
  return f
end

local function ensure_surface_state(force_index, surface_index)
  local f = ensure_force_state(force_index)
  local surf = f.surfaces[surface_index]
  if not surf then
    surf = { cells = {} }
    f.surfaces[surface_index] = surf
  end
  return surf
end

local function parse_cell_key(key)
  local sx, sy = key:match("^(-?%d+):(-?%d+)$")
  return tonumber(sx), tonumber(sy)
end

local function cell_bounds(g, cx, cy)
  local left = cx * g.width + g.x_offset
  local top = cy * g.height + g.y_offset
  local right = left + g.width
  local bottom = top + g.height
  return {x = left, y = top}, {x = right, y = bottom}
end

-- Note: zone_color_with_alpha was unused; removed for clarity.


local function destroy_cell_render(cell)
  if not cell then return end
  for _, variant in pairs(cell.variants or {}) do
    if variant.game and variant.game.valid then variant.game.destroy() end
    if variant.chart and variant.chart.valid then variant.chart.destroy() end
  end
end

local SPRITES = {
  [1] = "zp-empty-square-10",
  [2] = "zp-empty-square-25",
  [3] = "zp-empty-square-40",
}

---Draw or update a cell with all three visibility variants
---@param force_index uint
---@param surface_index uint
---@param key string
---@param zone_id uint|nil
local function draw_cell(force_index, surface_index, key, zone_id)
  local surf = ensure_surface_state(force_index, surface_index)
  local cell = surf.cells[key]

  local surface = game.get_surface(surface_index) --[[@as LuaSurface]]
  local g = backend.get_grid(force_index)
  local zones = backend.get_zones(force_index)
  local zone = zone_id and zones[zone_id] or nil
  local cx, cy = parse_cell_key(key)
  local lt, rb = cell_bounds(g, cx, cy)
  local center_pos = { x = (lt.x + rb.x) / 2, y = (lt.y + rb.y) / 2 }

  if not zone then
    if cell then
      destroy_cell_render(cell)
      surf.cells[key] = nil
    end
    return
  end

  local color = zone.color
  local x_scale = g.width / 16
  local y_scale = g.height / 16

  -- Optimization: if cell exists with same geometry, just update color
  if cell and cell.x_scale == x_scale and cell.y_scale == y_scale and cell.zone_id == zone_id then
    -- Only update colors on all variants
    for idx = 1, 3 do
      local variant = cell.variants[idx]
      if variant then
        if variant.game and variant.game.valid then variant.game.color = color end
        if variant.chart and variant.chart.valid then variant.chart.color = color end
      end
    end
    return
  end

  -- Cell geometry changed or zone changed, destroy and recreate
  if cell then
    destroy_cell_render(cell)
  end

  local function draw_floor(sprite, target_pos, tint, x_scale, y_scale)
    return rendering.draw_sprite{
      sprite = sprite,
      surface = surface,
      tint = tint,
      target = target_pos,
      orientation = 0,
      render_layer = "floor",
      only_in_alt_mode = true,
      visible = false,
      x_scale = x_scale or 1.0,
      y_scale = y_scale or 1.0,
    }
  end

  local function draw_chart(sprite, target_pos, tint, x_scale, y_scale)
    return rendering.draw_sprite{
      sprite = sprite,
      surface = surface,
      tint = tint,
      target = target_pos,
      orientation = 0,
      only_in_alt_mode = true,
      render_mode = "chart",
      visible = false,
      x_scale = x_scale or 1.0,
      y_scale = y_scale or 1.0,
    }
  end

  -- Create all three variants initially invisible; visibility will be updated by update_cell_visibility
  local variants = {}
  for idx = 1, 3 do
    variants[idx] = {
      game = draw_floor(SPRITES[idx], center_pos, color, x_scale, y_scale),
      chart = draw_chart(SPRITES[idx], center_pos, color, x_scale, y_scale),
    }
  end

  surf.cells[key] = {
    zone_id = zone_id,
    x_scale = x_scale,
    y_scale = y_scale,
    variants = variants,
  }
end

---Build lists of players grouped by their visibility level preference
---@param force_index uint
---@return table<uint, LuaPlayer[]> players_by_level Array of player lists indexed 1-3
local function build_player_visibility_lists(force_index)
  local force = game.forces[force_index]
  if not force then return { {}, {}, {} } end

  local players_by_level = { {}, {}, {} }
  for _, player in pairs(force.players) do
    local idx = backend.get_boundary_opacity_index(player.index)
    -- Level 0 means "don't render" - those players are excluded from all lists
    if idx > 0 and idx <= 3 then
      table.insert(players_by_level[idx], player)
    end
  end
  return players_by_level
end

---Update which players can see each visibility variant of a cell
---@param force_index uint
---@param surface_index uint
---@param key string
---@param players_by_level table<uint, LuaPlayer[]> Pre-built player lists by visibility level
local function update_cell_visibility(force_index, surface_index, key, players_by_level)
  local surf = ensure_surface_state(force_index, surface_index)
  local cell = surf.cells[key]
  if not cell then return end

  -- Update the visibility and players field for each variant
  for idx = 1, 3 do
    local variant = cell.variants[idx]
    local player_list = players_by_level[idx]
    
    if variant.game then
      if #player_list > 0 then
        variant.game.visible = true
        variant.game.players = player_list
      else
        variant.game.visible = false
      end
    end
    
    if variant.chart then
      if #player_list > 0 then
        variant.chart.visible = true
        variant.chart.players = player_list
      else
        variant.chart.visible = false
      end
    end
  end
end

local function rebuild_surface(force_index, surface_index)
  local surf = ensure_surface_state(force_index, surface_index)
  
  -- Destroy all existing cells
  for key, cell in pairs(surf.cells) do
    destroy_cell_render(cell)
    surf.cells[key] = nil
  end

  local f = storage.zp.forces[force_index]
  if not f then return end
  local img = f.images[surface_index]
  
  -- Build player visibility lists once for all cells
  local players_by_level = build_player_visibility_lists(force_index)
  
  -- Redraw all cells with all variants
  for key, zone_id in pairs(img.cells or {}) do
    if zone_id then
      draw_cell(force_index, surface_index, key, zone_id)
      update_cell_visibility(force_index, surface_index, key, players_by_level)
    end
  end
end

---Notify renderer that a set of cells changed for a surface.
---@param force_index uint
---@param surface_index uint
---@param changed table<string, boolean>|nil  -- set of cell keys affected; nil implies unknown/many
---@param new_zone_id uint|nil               -- new zone id if uniform, or nil for eraser/mixed
function render.on_cells_changed(force_index, surface_index, changed, new_zone_id)
  if not storage or not storage.zp then return end
  if not changed then
    -- Full refresh (e.g., zone delete remap or reproject)
    rebuild_surface(force_index, surface_index)
    return
  end
  local f = backend.get_force(force_index)
  local img = f and f.images and f.images[surface_index]

  -- Build player visibility lists once for all changed cells
  local players_by_level = build_player_visibility_lists(force_index)

  for key, _ in pairs(changed) do
    local zone_id = img.cells[key]
    draw_cell(force_index, surface_index, key, zone_id)
    update_cell_visibility(force_index, surface_index, key, players_by_level)
  end
end

---Notify renderer that zone definitions changed for a force.
---@param force_index uint
function render.on_zones_changed(force_index)
  -- Update colors for all existing cells across all variants
  local fstate = ensure_force_state(force_index)
  local zones = backend.get_zones(force_index)
  for surface_index, surf in pairs(fstate.surfaces) do
    for key, cell in pairs(surf.cells) do
      local zone = cell.zone_id and zones[cell.zone_id]
      if zone then
        local color = zone.color
        for idx = 1, 3 do
          local variant = cell.variants[idx]
          if variant then
            if variant.game and variant.game.valid then variant.game.color = color end
            if variant.chart and variant.chart.valid then variant.chart.color = color end
          end
        end
      end
    end
  end
end

---Notify renderer that grid properties changed (may imply reprojection/full redraw).
---@param force_index uint
function render.on_grid_changed(force_index)
  -- Grid size/offset or visibility/opacity changes: rebuild all surfaces
  local images = backend.get_force_images(force_index)
  for surface_index, _ in pairs(images) do
    rebuild_surface(force_index, surface_index)
  end
end

---Per-player visibility flags changed.
---@param player_index uint
function render.on_player_visibility_changed(player_index)
  local player = game.get_player(player_index)
  if not player then return end
  local force_index = player.force.index
  
  -- Build player visibility lists once for all cells
  local players_by_level = build_player_visibility_lists(force_index)
  
  -- Update visibility for all cells on all surfaces for this player's force
  local fstate = ensure_force_state(force_index)
  for surface_index, surf in pairs(fstate.surfaces) do
    for key, _ in pairs(surf.cells) do
      update_cell_visibility(force_index, surface_index, key, players_by_level)
    end
  end
end

return render

-- Renderer for Zone Planner
-- Draws per-cell overlays using Factorio rendering API, tinted by zone color.

local render = {}

local backend = require("scripts/backend")

---@class ZP.RenderStorageRoot
---@field forces table<uint, ZP.RenderForceState>  -- by force_index

---@class ZP.RenderObject
---@field game LuaRenderObject|nil
---@field chart LuaRenderObject|nil

---@class ZP.RenderCorner
---@field quadrants_mask uint  -- bitmask of covered quadrants: 1=top-left, 2=top-right, 4=bottom-left, 8=bottom-right
---@field zone_id uint  -- zone ID for coloring
---@field orientation number
---@field sprite_index uint
---@field variants {[1]: ZP.RenderObject|nil, [2]: ZP.RenderObject|nil, [3]: ZP.RenderObject|nil}

---@class ZP.RenderCell
---@field zone_id uint|nil
---@field x_scale number|nil
---@field y_scale number|nil
---@field variants {[1]: ZP.RenderObject|nil, [2]: ZP.RenderObject|nil, [3]: ZP.RenderObject|nil}

---@class ZP.RenderSurfaceState
---@field cells table<string, ZP.RenderCell>
---@field corners table<string, ZP.RenderCorner[]>

---@class ZP.RenderForceState
---@field surfaces table<uint, ZP.RenderSurfaceState>  -- surface_index -> surface state

local CENTER_SPRITES = {
  [1] = "zp-empty-square-0",
  [2] = "zp-empty-square-1",
  [3] = "zp-empty-square-2",
}

local CORNER_SPRITES = {
  [1] = { "zp-corner-0-0", "zp-corner-0-1", "zp-corner-0-2", "zp-corner-0-3" },
  [2] = { "zp-corner-1-0", "zp-corner-1-1", "zp-corner-1-2", "zp-corner-1-3" },
  [3] = { "zp-corner-2-0", "zp-corner-2-1", "zp-corner-2-2", "zp-corner-2-3" },
}

local function get_cell_key(cx, cy)
  return ("%d:%d"):format(cx, cy)
end

local function parse_cell_key(key)
  local sx, sy = key:match("^(-?%d+):(-?%d+)$")
  return tonumber(sx), tonumber(sy)
end

-- Bitwise operations for Lua versions that don't support bitwise operators
local function bit_and(a, b)
  local result = 0
  local power = 1
  while a > 0 or b > 0 do
    if (a % 2 == 1) and (b % 2 == 1) then
      result = result + power
    end
    a = math.floor(a / 2)
    b = math.floor(b / 2)
    power = power * 2
  end
  return result
end

local function bit_or(a, b)
  local result = 0
  local power = 1
  while a > 0 or b > 0 do
    if (a % 2 == 1) or (b % 2 == 1) then
      result = result + power
    end
    a = math.floor(a / 2)
    b = math.floor(b / 2)
    power = power * 2
  end
  return result
end

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
    surf = { cells = {}, corners = {} }
    f.surfaces[surface_index] = surf
  end
  return surf
end

local function quadrants_mask_to_sprite_and_rotation(mask) 
  local top_left = bit_and(mask, 1) > 0 and 1 or 0
  local top_right = bit_and(mask, 2) > 0 and 1 or 0
  local bottom_left = bit_and(mask, 4) > 0 and 1 or 0
  local bottom_right = bit_and(mask, 8) > 0 and 1 or 0
  local count = top_left + top_right + bottom_left + bottom_right
  if count == 0 or count == 4 then
    return nil, nil  -- no corner needed for empty or full coverage
  end
  if count == 1 then
    if top_left == 1 then return 0, 0 end  -- top-left
    if top_right == 1 then return 0, 0.25 end  -- top-right
    if bottom_left == 1 then return 0, 0.75 end  -- bottom-left
    if bottom_right == 1 then return 0, 0.5 end  -- bottom-right
  end

  if count == 2 then
    if top_left == 1 and top_right == 1 then return 1, 0 end  -- top edge
    if bottom_left == 1 and bottom_right == 1 then return 1, 0.5 end  -- bottom edge
    if top_left == 1 and bottom_left == 1 then return 1, 0.75 end  -- left edge
    if top_right == 1 and bottom_right == 1 then return 1, 0.25 end  -- right edge
    if top_left == 1 and bottom_right == 1 then return 3, 0 end  -- diagonal
    if top_right == 1 and bottom_left == 1 then return 3, 0.25 end  -- diagonal
  end

  if count == 3 then
    if top_left == 0 then return 2, 0.5 end  -- missing top-left
    if top_right == 0 then return 2, 0.75 end  -- missing top-right
    if bottom_left == 0 then return 2, 0.25 end  -- missing bottom-left
    if bottom_right == 0 then return 2, 0 end  -- missing bottom-right
  end
end

-- Corner Mapping: (x, y) corresponds to the corner between the following cells:
-- (x, y)     (x+1, y)
-- (x, y+1)   (x+1, y+1)
local function quadrant_mask_to_adjacents(x, y, mask)
  local offsets = {}
  if bit_and(mask, 1) > 0 then table.insert(offsets, {x = x, y = y}) end  -- top-left
  if bit_and(mask, 2) > 0 then table.insert(offsets, {x = x + 1, y = y}) end  -- top-right
  if bit_and(mask, 4) > 0 then table.insert(offsets, {x = x, y = y + 1}) end  -- bottom-left
  if bit_and(mask, 8) > 0 then table.insert(offsets, {x = x + 1, y = y + 1}) end  -- bottom-right
  return offsets
end


local mask_scratch = {}
local current_mask_scratch = {}

-- Corner Mapping: (x, y) corresponds to the corner between the following cells:
-- (x, y)     (x+1, y)
-- (x, y+1)   (x+1, y+1)
--- Ensure all corner sprites at this coordinate are correct and there are no additional corners. Otherwise, scrap all corners and recreate from scratch based on current adjacency.
local function fix_corners(surface_index, force_index, image, x, y, corner_key, visibility_list)
  for k in pairs(mask_scratch) do mask_scratch[k] = nil end
  for k in pairs(current_mask_scratch) do current_mask_scratch[k] = nil end

  -- Create map zone_id -> bitmask of quadrants for new data
  local top_left_cell = backend.get_from_image(image, x, y)
  local top_right_cell = backend.get_from_image(image, x + 1, y)
  local bottom_left_cell = backend.get_from_image(image, x, y + 1)
  local bottom_right_cell = backend.get_from_image(image, x + 1, y + 1)

  if top_left_cell then mask_scratch[top_left_cell] = (mask_scratch[top_left_cell] or 0) + 1 end
  if top_right_cell then mask_scratch[top_right_cell] = (mask_scratch[top_right_cell] or 0) + 2 end
  if bottom_left_cell then mask_scratch[bottom_left_cell] = (mask_scratch[bottom_left_cell] or 0) + 4 end
  if bottom_right_cell then mask_scratch[bottom_right_cell] = (mask_scratch[bottom_right_cell] or 0) + 8 end

  local surface_render_state = ensure_surface_state(force_index, surface_index)
  local cell_key = corner_key
  local existing_corners = surface_render_state.corners[cell_key]
  
  -- Quick exit: if both the new adjacency mask and existing renderer have nothing to draw, skip work
  local new_empty = not next(mask_scratch)
  local old_empty = true
  if existing_corners and next(existing_corners) then old_empty = false end
  if new_empty and old_empty then return end

  -- Check if existing corners in renderer match the new adjacency; if so, no need to update
  local count_existing = 0
  local match = true

  if existing_corners then
    for _, c in pairs(existing_corners) do
      current_mask_scratch[c.zone_id] = c.quadrants_mask
      count_existing = count_existing + 1
      if mask_scratch[c.zone_id] ~= c.quadrants_mask then
        match = false; break
      end
    end
  else
    match = not next(mask_scratch)
  end


  -- Check if there are new zones that weren't there before
  if match then
    for zone_id, mask in pairs(mask_scratch) do
      if current_mask_scratch[zone_id] ~= mask then
        match = false; break
      end
    end
  end

  if match then return end

  if existing_corners then
    for _, zone in pairs(existing_corners or {}) do
      for _, variant in pairs(zone.variants or {}) do
        if variant.game and variant.game.valid then variant.game.destroy() end
        if variant.chart and variant.chart.valid then variant.chart.destroy() end
      end
    end
  end

  surface_render_state.corners[cell_key] = nil

  -- recreate corners based on current adjacency
  local grid = backend.get_grid(force_index)
  local world_x = (x + 1) * grid.width + grid.x_offset
  local world_y = (y + 1) * grid.height + grid.y_offset
  local target_position = { x = world_x, y = world_y }
  local x_scale = grid.width / 8
  local y_scale = grid.height / 8
  local zones = backend.get_zones(force_index)
  for zone_id, mask in pairs(mask_scratch) do
    local sprite_index, orientation = quadrants_mask_to_sprite_and_rotation(mask)
    if sprite_index then
      local corner = {
        quadrants_mask = mask,
        zone_id = zone_id,
        orientation = orientation,
        sprite_index = sprite_index,
        variants = {},
      }
      for idx = 1, 3 do
        local visible = true
        if visibility_list and visibility_list[idx] and #visibility_list[idx] == 0 then
          visible = false
        end
        corner.variants[idx] = {
          game = rendering.draw_sprite{
            sprite = CORNER_SPRITES[idx][sprite_index + 1],
            surface = surface_index,
            tint = zones[zone_id].color,
            target = target_position,
            x_scale = x_scale,
            y_scale = y_scale,
            orientation = orientation,
            render_layer = "floor",
            only_in_alt_mode = true,
            visible = visible,
            players = visibility_list[idx],
          },
          chart = rendering.draw_sprite{
            sprite = CORNER_SPRITES[idx][sprite_index + 1],
            surface = surface_index,
            tint = zones[zone_id].color,
            target = target_position,
            x_scale = x_scale,
            y_scale = y_scale,
            orientation = orientation,
            only_in_alt_mode = true,
            render_mode = "chart",
            visible = visible,
            players = visibility_list[idx],
          },
        }
      end

      surface_render_state.corners[get_cell_key(x, y)] = surface_render_state.corners[get_cell_key(x, y)] or {}
      table.insert(surface_render_state.corners[get_cell_key(x, y)], corner)
    end
  end
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
      game = draw_floor(CENTER_SPRITES[idx], center_pos, color, x_scale, y_scale),
      chart = draw_chart(CENTER_SPRITES[idx], center_pos, color, x_scale, y_scale),
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

-- Update visibility for corner render objects for a single corner key
local function update_corner_visibility(force_index, surface_index, corner_key, players_by_level)
  local surf = ensure_surface_state(force_index, surface_index)
  local corners = surf.corners[corner_key]
  if not corners then return end

  for _, corner in pairs(corners) do
    for idx = 1, 3 do
      local variant = corner.variants[idx]
      local player_list = players_by_level[idx]

      if variant and variant.game then
        if #player_list > 0 then
          variant.game.visible = true
          variant.game.players = player_list
        else
          variant.game.visible = false
        end
      end

      if variant and variant.chart then
        if #player_list > 0 then
          variant.chart.visible = true
          variant.chart.players = player_list
        else
          variant.chart.visible = false
        end
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
  local cells = (img and img.cells) or {}
  for key, zone_id in pairs(cells) do
    if zone_id then
      draw_cell(force_index, surface_index, key, zone_id)
      update_cell_visibility(force_index, surface_index, key, players_by_level)
    end
  end

  -- If there is no image data yet, there are no corners to rebuild
  if img and img.cells then
    -- Rebuild corner sprites for all corners adjacent to any cell
    local corners_to_fix = {}
    local function mark_corner_for_fix(cx, cy)
      local key = get_cell_key(cx, cy)
      corners_to_fix[key] = { x = cx, y = cy }
    end
    for key, _ in pairs(cells) do
      local cx, cy = parse_cell_key(key)
      mark_corner_for_fix(cx - 1, cy - 1)
      mark_corner_for_fix(cx,     cy - 1)
      mark_corner_for_fix(cx - 1, cy)
      mark_corner_for_fix(cx,     cy)
    end
    for corner_key, p in pairs(corners_to_fix) do
      fix_corners(surface_index, force_index, img, p.x, p.y, corner_key, players_by_level)
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

  -- Collect all corners that need updating (each corner may be touched by up to 4 cells)
  local corners_to_fix = {}
  local function mark_corner_for_fix(cx, cy)
    local key = get_cell_key(cx, cy)
    corners_to_fix[key] = { x = cx, y = cy }
  end

  for key, p in pairs(changed) do
    local cx, cy = parse_cell_key(key)
    local zone_id = img.cells[key]
    draw_cell(force_index, surface_index, key, zone_id)
    update_cell_visibility(force_index, surface_index, key, players_by_level)
    
    -- Mark the four corners adjacent to this cell
    mark_corner_for_fix(cx - 1, cy - 1)
    mark_corner_for_fix(cx, cy - 1)
    mark_corner_for_fix(cx - 1, cy)
    mark_corner_for_fix(cx, cy)
  end

  -- Fix all affected corners
  for corner_key, p in pairs(corners_to_fix) do
    local cx, cy = p.x, p.y
    fix_corners(surface_index, force_index, img, cx, cy, corner_key, players_by_level)
  end
end

---Notify renderer that zone definitions changed for a force.
---@param force_index uint
---@param event ZP.ZoneChangeEvent|nil
function render.on_zones_changed(force_index, event)
  -- If no event provided, do a full update for backwards compatibility
  if not event then
    -- Full update: update colors for all existing cells across all variants
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
    return
  end

  -- Handle specific event types
  local event_type = event.type
  
  -- Events we ignore (no rendering updates needed)
  if event_type == "zone-name-modified" or 
     event_type == "zone-order-changed" or 
     event_type == "zone-added" then
    return
  end
  
  -- Zone deleted: destroy all render objects for this zone
  if event_type == "zone-deleted" then
    local fstate = ensure_force_state(force_index)
    local deleted_zone_id = event.zone_id
    for surface_index, surf in pairs(fstate.surfaces) do
      for key, cell in pairs(surf.cells) do
        if cell.zone_id == deleted_zone_id then
          destroy_cell_render(cell)
          surf.cells[key] = nil
        end
      end
      -- Also remove any corner renderers that belonged to the deleted zone
      for corner_key, corner_list in pairs(surf.corners) do
        local i = 1
        while corner_list and i <= #corner_list do
          local corner = corner_list[i]
          if corner and corner.zone_id == deleted_zone_id then
            for _, variant in pairs(corner.variants or {}) do
              if variant.game and variant.game.valid then variant.game.destroy() end
              if variant.chart and variant.chart.valid then variant.chart.destroy() end
            end
            table.remove(corner_list, i)
          else
            i = i + 1
          end
        end
        if not corner_list or #corner_list == 0 then
          surf.corners[corner_key] = nil
        end
      end
    end
    return
  end
  
  -- Zone modified: update colors for cells using this zone
  if event_type == "zone-modified" then
    local fstate = ensure_force_state(force_index)
    local zones = backend.get_zones(force_index)
    local modified_zone_id = event.zone_id
    local zone = zones[modified_zone_id]
    
    if zone then
      local color = zone.color
      for surface_index, surf in pairs(fstate.surfaces) do
        -- Update colors for all cells using this zone
        for key, cell in pairs(surf.cells) do
          if cell.zone_id == modified_zone_id then
            for idx = 1, 3 do
              local variant = cell.variants[idx]
              if variant then
                if variant.game and variant.game.valid then variant.game.color = color end
                if variant.chart and variant.chart.valid then variant.chart.color = color end
              end
            end
          end
        end

        -- Update colors for all corner sprites using this zone
        for corner_key, corner_list in pairs(surf.corners) do
          for _, corner in pairs(corner_list) do
            if corner.zone_id == modified_zone_id then
              for idx = 1, 3 do
                local variant = corner.variants[idx]
                if variant then
                  if variant.game and variant.game.valid then variant.game.color = color end
                  if variant.chart and variant.chart.valid then variant.chart.color = color end
                end
              end
            end
          end
        end
      end
    end
    return
  end
  
  -- Unknown event type: fall back to full update
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
    for corner_key, _ in pairs(surf.corners) do
      update_corner_visibility(force_index, surface_index, corner_key, players_by_level)
    end
  end
end

return render

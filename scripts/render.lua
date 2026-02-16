-- Draws per-cell overlays using Factorio rendering API, tinted by region color.

local render = {}

local backend = require("scripts/backend")


local CENTER_SPRITES = {
  [1] = "gp-empty-square-0",
  [2] = "gp-empty-square-1",
  [3] = "gp-empty-square-2",
}

local CORNER_SPRITES = {
  [1] = { "gp-corner-0-0", "gp-corner-0-1", "gp-corner-0-2", "gp-corner-0-3" },
  [2] = { "gp-corner-1-0", "gp-corner-1-1", "gp-corner-1-2", "gp-corner-1-3" },
  [3] = { "gp-corner-2-0", "gp-corner-2-1", "gp-corner-2-2", "gp-corner-2-3" },
}

-- Data Layout
-------------------------------------------------------------------------------

---@class GP.RenderStorageRoot
---@field forces table<uint, GP.RenderForceState>  -- by force_index

---@class GP.RenderObject
---@field game LuaRenderObject|nil
---@field chart LuaRenderObject|nil

---@class GP.RenderCorner
---@field quadrants_mask uint  -- bitmask of covered quadrants: 1=top-left, 2=top-right, 4=bottom-left, 8=bottom-right
---@field region_id uint  -- region ID for coloring
---@field orientation number
---@field sprite_index uint
---@field variants {[1]: GP.RenderObject|nil, [2]: GP.RenderObject|nil, [3]: GP.RenderObject|nil}

---@class GP.RenderCell
---@field region_id uint|nil
---@field x_scale number|nil
---@field y_scale number|nil
---@field variants {[1]: GP.RenderObject|nil, [2]: GP.RenderObject|nil, [3]: GP.RenderObject|nil}

---@class GP.RenderSurfaceState
---@field cells table<string, GP.RenderCell>
---@field corners table<string, GP.RenderCorner[]>

---@class GP.RenderForceState
---@field surfaces table<uint, GP.RenderSurfaceState>  -- surface_index -> surface state

local function ensure_state()
  storage.gp_render = storage.gp_render or { forces = {} }
  return storage.gp_render
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



-- Cell Drawing and Updating
-------------------------------------------------------------------------------

local function destroy_cell_render(cell)
  if not cell then return end
  for _, variant in pairs(cell.variants or {}) do
    if variant.game and variant.game.valid then variant.game.destroy() end
    if variant.chart and variant.chart.valid then variant.chart.destroy() end
  end
end

local function cell_bounds(g, cx, cy)
  local left = cx * g.width + g.x_offset
  local top = cy * g.height + g.y_offset
  local right = left + g.width
  local bottom = top + g.height
  return {x = left, y = top}, {x = right, y = bottom}
end

---Draw or update a cell with all three visibility variants
---@param force_index uint
---@param surface_index uint
---@param key string
---@param region_id uint|nil
local function draw_cell(force_index, surface_index, key, region_id, grid, regions, surface)
  local surf = ensure_surface_state(force_index, surface_index)
  local cell = surf.cells[key]

  local surface = surface or game.get_surface(surface_index) --[[@as LuaSurface]]
  local g = grid or backend.get_grid(force_index)
  local regions = regions or backend.get_regions(force_index)
  local region = region_id and regions[region_id] or nil
  local cx, cy = shared.parse_cell_key(key)
  local lt, rb = cell_bounds(g, cx, cy)
  local center_pos = { x = (lt.x + rb.x) / 2, y = (lt.y + rb.y) / 2 }

  if not region then
    if cell then
      destroy_cell_render(cell)
      surf.cells[key] = nil
    end
    return
  end

  local color = region.color
  local x_scale = g.width / 16
  local y_scale = g.height / 16

  -- Optimization: if cell exists with same geometry, just update color
  if cell and cell.x_scale == x_scale and cell.y_scale == y_scale and cell.region_id == region_id then
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

  -- Cell geometry changed or region changed, destroy and recreate
  if cell then
    destroy_cell_render(cell)
  end


  -- Create all three variants initially invisible; visibility will be updated by update_cell_visibility
  local variants = {}
  for idx = 1, 3 do
    local sprite = CENTER_SPRITES[idx]
    local target_pos = center_pos
    local tint = color
    local game_render = rendering.draw_sprite{
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
    local chart_render = rendering.draw_sprite{
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
    variants[idx] = {
       game = game_render,
       chart = chart_render,
    }
  end

  surf.cells[key] = {
    region_id = region_id,
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


-- Corner Drawing and Updating
-------------------------------------------------------------------------------

-- Precomputed lookup table for quadrants_mask_to_sprite_and_rotation
-- Maps mask value (0-15) to {sprite_index, orientation}
-- nil entry means no corner sprite needed
local QUADRANT_SPRITE_LOOKUP = {
  [0] = nil,  -- 0000: empty, no corner
  [1] = {0, 0},  -- 0001: top-left only
  [2] = {0, 0.25},  -- 0010: top-right only
  [3] = {1, 0},  -- 0011: top edge
  [4] = {0, 0.75},  -- 0100: bottom-left only
  [5] = {1, 0.75},  -- 0101: left edge
  [6] = {3, 0.25},  -- 0110: diagonal (top-right + bottom-left)
  [7] = {2, 0},  -- 0111: missing bottom-right
  [8] = {0, 0.5},  -- 1000: bottom-right only
  [9] = {3, 0},  -- 1001: diagonal (top-left + bottom-right)
  [10] = {1, 0.25},  -- 1010: right edge
  [11] = {2, 0.25},  -- 1011: missing bottom-left
  [12] = {1, 0.5},  -- 1100: bottom edge
  [13] = {2, 0.75},  -- 1101: missing top-right
  [14] = {2, 0.5},  -- 1110: missing top-left
  [15] = nil,  -- 1111: full coverage, no corner
}

local function quadrants_mask_to_sprite_and_rotation(mask)
  local result = QUADRANT_SPRITE_LOOKUP[mask]
  if result then
    return result[1], result[2]
  end
  return nil, nil
end


local function destroy_corner_render(corner)
  if not corner then return end
  for _, variant in pairs(corner.variants or {}) do
    if variant.game and variant.game.valid then variant.game.destroy() end
    if variant.chart and variant.chart.valid then variant.chart.destroy() end
  end
end


-- Corner Mapping: (x, y) corresponds to the corner between the following cells:
-- (x, y)     (x+1, y)
-- (x, y+1)   (x+1, y+1)
--- Ensure all corner sprites at this coordinate are correct and there are no additional corners. Otherwise, scrap all corners and recreate from scratch based on current adjacency.
local function draw_corner(surface_index, force_index, image, x, y, corner_key, visibility_list, grid, regions)
  local mask = {}
  local mask_active_render = {}

  -- Create map region_id -> bitmask of quadrants for new data
  local top_left_cell = backend.get_from_image(image, x, y)
  local top_right_cell = backend.get_from_image(image, x + 1, y)
  local bottom_left_cell = backend.get_from_image(image, x, y + 1)
  local bottom_right_cell = backend.get_from_image(image, x + 1, y + 1)

  if top_left_cell then mask[top_left_cell] = (mask[top_left_cell] or 0) + 1 end
  if top_right_cell then mask[top_right_cell] = (mask[top_right_cell] or 0) + 2 end
  if bottom_left_cell then mask[bottom_left_cell] = (mask[bottom_left_cell] or 0) + 4 end
  if bottom_right_cell then mask[bottom_right_cell] = (mask[bottom_right_cell] or 0) + 8 end

  local surface_render_state = ensure_surface_state(force_index, surface_index)
  local cell_key = corner_key
  local existing_corners = surface_render_state.corners[cell_key]
  
  -- Quick exit: if both the new adjacency mask and existing renderer have nothing to draw, skip work
  local new_empty = not next(mask)
  local old_empty = true
  if existing_corners and next(existing_corners) then old_empty = false end
  if new_empty and old_empty then return end

  -- Check if existing corners in renderer match the new adjacency; if so, no need to update
  local count_existing = 0
  local match = true

  if existing_corners then
    for _, c in pairs(existing_corners) do
      mask_active_render[c.region_id] = c.quadrants_mask
      count_existing = count_existing + 1
      if mask[c.region_id] ~= c.quadrants_mask then
        match = false; break
      end
    end
  else
    match = not next(mask)
  end


  -- Check if there are new regions that weren't there before
  if match then
    for region_id, mask in pairs(mask) do
      if mask_active_render[region_id] ~= mask then
        match = false; break
      end
    end
  end

  if match then return end

  if existing_corners then
    for _, corner in pairs(existing_corners) do
      destroy_corner_render(corner)
    end
  end

  surface_render_state.corners[cell_key] = nil

  -- recreate corners based on current adjacency
  local grid = grid or backend.get_grid(force_index)
  local world_x = (x + 1) * grid.width + grid.x_offset
  local world_y = (y + 1) * grid.height + grid.y_offset
  local x_scale = grid.width / 8
  local y_scale = grid.height / 8
  local target_position = { x = world_x, y = world_y }
  local regions = regions or backend.get_regions(force_index)
  for region_id, mask in pairs(mask) do
    local lookup_result = QUADRANT_SPRITE_LOOKUP[mask]

    if lookup_result then
      local sprite_index, orientation = lookup_result and lookup_result[1], lookup_result and lookup_result[2] or nil
      local corner = {
        quadrants_mask = mask,
        region_id = region_id,
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
            tint = regions[region_id].color,
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
            tint = regions[region_id].color,
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

      surface_render_state.corners[corner_key] = surface_render_state.corners[corner_key] or {}
      table.insert(surface_render_state.corners[corner_key], corner)
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

-- Handlers for external events to trigger rendering updates
-------------------------------------------------------------------------------

local function rebuild_surface(force_index, surface_index)
  local surf = ensure_surface_state(force_index, surface_index)
  
  -- Destroy all existing cells
  for key, cell in pairs(surf.cells) do
    destroy_cell_render(cell)
    surf.cells[key] = nil
  end

  for key, corner_list in pairs(surf.corners) do
    for _, corner in pairs(corner_list) do
      destroy_corner_render(corner)
    end
    surf.corners[key] = nil
  end

  local f = storage.gp.forces[force_index]
  if not f then return end
  local img = f.images[surface_index]
  
  -- Build player visibility lists once for all cells
  local players_by_level = build_player_visibility_lists(force_index)
  local surface = game.get_surface(surface_index) --[[@as LuaSurface]]
  local grid = backend.get_grid(force_index)
  local regions = backend.get_regions(force_index)
  
  -- Redraw all cells with all variants
  local cells = (img and img.cells) or {}
  for key, region_id in pairs(cells) do
    if region_id then
      draw_cell(force_index, surface_index, key, region_id, grid, regions, surface)
      update_cell_visibility(force_index, surface_index, key, players_by_level)
    end
  end

  -- If there is no image data yet, there are no corners to rebuild
  if img and img.cells then
    -- Rebuild corner sprites for all corners adjacent to any cell
    local corners_to_fix = {}
    local function mark_corner_for_fix(cx, cy)
      local key = shared.get_cell_key(cx, cy)
      corners_to_fix[key] = { x = cx, y = cy }
    end
    for key, _ in pairs(cells) do
      local cx, cy = shared.parse_cell_key(key)
      mark_corner_for_fix(cx - 1, cy - 1)
      mark_corner_for_fix(cx,     cy - 1)
      mark_corner_for_fix(cx - 1, cy)
      mark_corner_for_fix(cx,     cy)
    end
    for corner_key, p in pairs(corners_to_fix) do
      draw_corner(surface_index, force_index, img, p.x, p.y, corner_key, players_by_level, grid, regions)
    end
  end
end

---Notify renderer that a set of cells changed for a surface.
---@param force_index uint
---@param surface_index uint
---@param changed table<string, boolean>|nil  -- set of cell keys affected; nil implies unknown/many
---@param new_region_id uint|nil               -- new region id if uniform, or nil for eraser/mixed
function render.on_cells_changed(force_index, surface_index, changed, new_region_id)
  if not storage or not storage.gp then return end
  if not changed then
    -- Full refresh (e.g., region delete remap or reproject)
    rebuild_surface(force_index, surface_index)
    return
  end
  local f = backend.get_force(force_index)
  local img = f and f.images and f.images[surface_index]

  -- Build player visibility lists once for all changed cells
  local players_by_level = build_player_visibility_lists(force_index)
  local surface = game.get_surface(surface_index) --[[@as LuaSurface]]
  local grid = backend.get_grid(force_index)
  local regions = backend.get_regions(force_index)

  -- Collect all corners that need updating (each corner may be touched by up to 4 cells)
  local corners_to_fix = {}
  local function mark_corner_for_fix(cx, cy)
    local key = shared.get_cell_key(cx, cy)
    corners_to_fix[key] = { x = cx, y = cy }
  end

  for key, p in pairs(changed) do
    local cx, cy = shared.parse_cell_key(key)
    local region_id = img.cells[key]
    draw_cell(force_index, surface_index, key, region_id, grid, regions, surface)
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
    draw_corner(surface_index, force_index, img, cx, cy, corner_key, players_by_level, grid, regions)
  end
end

---Notify renderer that region definitions changed for a force.
---@param force_index uint
---@param event GP.RegionChangeEvent|nil
function render.on_regions_changed(force_index, event)
  -- If no event provided, do a full update for backwards compatibility
  if not event then
    -- Full update: update colors for all existing cells across all variants
    local fstate = ensure_force_state(force_index)
    local regions = backend.get_regions(force_index)
    for surface_index, surf in pairs(fstate.surfaces) do
      for key, cell in pairs(surf.cells) do
        local region = cell.region_id and regions[cell.region_id]
        if region then
          local color = region.color
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
  if event_type == "region-name-modified" or 
     event_type == "region-order-changed" or 
     event_type == "region-added" then
    return
  end
  
  -- region deleted: destroy all render objects for this region
  if event_type == "region-deleted" then
    local fstate = ensure_force_state(force_index)
    local deleted_region_id = event.region_id
    for surface_index, surf in pairs(fstate.surfaces) do
      for key, cell in pairs(surf.cells) do
        if cell.region_id == deleted_region_id then
          destroy_cell_render(cell)
          surf.cells[key] = nil
        end
      end
      -- Also remove any corner renderers that belonged to the deleted region
      for corner_key, corner_list in pairs(surf.corners) do
        local i = 1
        while corner_list and i <= #corner_list do
          local corner = corner_list[i]
          if corner and corner.region_id == deleted_region_id then
            destroy_corner_render(corner)
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
  
  -- region modified: update colors for cells using this region
  if event_type == "region-modified" then
    local fstate = ensure_force_state(force_index)
    local regions = backend.get_regions(force_index)
    local modified_region_id = event.region_id
    local region = regions[modified_region_id]
    
    if region then
      local color = region.color
      for surface_index, surf in pairs(fstate.surfaces) do
        -- Update colors for all cells using this region
        for key, cell in pairs(surf.cells) do
          if cell.region_id == modified_region_id then
            for idx = 1, 3 do
              local variant = cell.variants[idx]
              if variant then
                if variant.game and variant.game.valid then variant.game.color = color end
                if variant.chart and variant.chart.valid then variant.chart.color = color end
              end
            end
          end
        end

        -- Update colors for all corner sprites using this region
        for corner_key, corner_list in pairs(surf.corners) do
          for _, corner in pairs(corner_list) do
            if corner.region_id == modified_region_id then
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
  local regions = backend.get_regions(force_index)
  for surface_index, surf in pairs(fstate.surfaces) do
    for key, cell in pairs(surf.cells) do
      local region = cell.region_id and regions[cell.region_id]
      if region then
        local color = region.color
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

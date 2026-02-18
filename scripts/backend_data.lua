local backend_data = {}

--[[
Persistent state layout (storage.gp)

storage.gp :: GP.StorageRoot = {
  version: uint,                       -- schema/version marker for migrations
  forces: table<uint, GP.ForceState>,  -- by force_index
  players: table<uint, GP.PlayerState>,-- by player_index
  undo_capacity: uint,                 -- max undo entries per player
}
]]

---@class GP.StorageRoot
---@field version uint
---@field forces table<uint, GP.ForceState>
---@field players table<uint, GP.PlayerState>
---@field undo_capacity uint

---@class GP.Region
---@field id uint
---@field name string
---@field color Color
---@field order uint

---@class GP.Grid
---@field width uint
---@field height uint
---@field x_offset int
---@field y_offset int

---@class GP.ForceState
---@field next_region_id uint
---@field regions table<uint, GP.Region>
---@field grids table<uint, GP.Grid>
---@field images table<uint, {cells: table<string, uint?>}>

---@class GP.PlayerState
---@field selected_region_id uint
---@field selected_tool string|nil
---@field undo table[]
---@field redo table[]
---@field boundary_opacity_index uint  -- 0..3 discrete setting for boundary visibility

backend_data.EMPTY_REGION_ID = 0
backend_data.DEFAULT_GRID = {
  width = 8,
  height = 8,
  x_offset = 0,
  y_offset = 0,
}

-- Region change event types
backend_data.REGION_CHANGE_TYPE = {
  ADDED = "region-added",           -- Region was added
  DELETED = "region-deleted",       -- Region was deleted
  MODIFIED = "region-modified",     -- Region properties changed (name or color)
  NAME_MODIFIED = "region-name-modified",  -- Region name changed specifically
  ORDER_CHANGED = "region-order-changed",  -- Region order changed (renderer can skip rebuild)
}

---@class GP.RegionChangeEvent
---@field type string One of REGION_CHANGE_TYPE values
---@field region_id uint The region ID affected
---@field region_name string The region name
---@field before table|nil Previous state (for modified/deleted)
---@field after table|nil New state (for modified)

-- Default discrete visibility index for boundaries (0=off, 1..3 = variant levels)
local DEFAULT_OPACITY_INDEX = 2

DEFAULT_REGIONS = {
  { name = "Belts", color = {r=1,g=0.8,b=0} },
  { name = "Trains", color = {r=0.9,g=0.8,b=0.7} },
  { name = "Stations", color = {r=0.7,g=0.6,b=0.5} },
  { name = "Primary Products", color = {r=0.5,g=0.5,b=1.0} },
  { name = "Intermediate Products", color = {r=0.4,g=1.0,b=0.4} },
  { name = "End Products", color = {r=1,g=0.5,b=0.33} },
  { name = "Research", color = {r=0.5,g=0.75,b=1.0} },
  { name = "Power", color = {r=1.0,g=1.0,b=0.5} },
  { name = "Military", color = {r=0.8,g=0.2,b=0.2} },
  { name = "Utility", color = {r=0.9, g=0.4, b=0.8} },
}

---@return GP.StorageRoot
function backend_data.ensure_storage()
  if not storage.gp then
    storage.gp = {
      version = 1,
      forces = {}, ---@type table<uint, GP.ForceState>
      players = {}, ---@type table<uint, GP.PlayerState>
    } ---@type GP.StorageRoot
  end
  return storage.gp
end

---@param force_index uint
---@return GP.ForceState
function backend_data.ensure_force(force_index)
  backend_data.ensure_storage()
  local forces = storage.gp.forces
  local f = forces[force_index]
  if not f then
    f = {
      next_region_id = 1, -- 0 reserved for Empty
      regions = {
        [backend_data.EMPTY_REGION_ID] = { id = backend_data.EMPTY_REGION_ID, name = "(Empty)", color = {r=0,g=0,b=0,a=0}, order = 0 },
      },
      grids = {},
      images = {},
    }
    forces[force_index] = f
      for _, def in pairs(DEFAULT_REGIONS) do
      backend_data.add_region(force_index, 1, def.name, def.color)
    end

  end

  return f
end

---@param force_index uint
---@param surface_index uint
---@return GP.Grid
function backend_data.ensure_grid(force_index, surface_index)
  local f = backend_data.ensure_force(force_index)
  if not f.grids[surface_index] then
    f.grids[surface_index] = {
      width = backend_data.DEFAULT_GRID.width,
      height = backend_data.DEFAULT_GRID.height,
      x_offset = backend_data.DEFAULT_GRID.x_offset,
      y_offset = backend_data.DEFAULT_GRID.y_offset,
    }
  end
  return f.grids[surface_index]
end

---@param force_index uint
---@param surface_index uint
---@return {cells: table<string, uint?>}
function backend_data.get_surface_image(force_index, surface_index)
  local f = backend_data.ensure_force(force_index)
  local images = f.images
  if not images[surface_index] then
    images[surface_index] = { cells = {} }
  end
  return images[surface_index]
end

---@param player_index uint
---@return GP.PlayerState
function backend_data.ensure_player(player_index)
  backend_data.ensure_storage()
  local players = storage.gp.players
  local p = players[player_index]
  if not p then
    p = {
      selected_region_id = backend_data.EMPTY_REGION_ID,
      selected_tool = nil,
      undo = {},
      redo = {},
      boundary_opacity_index = DEFAULT_OPACITY_INDEX,
    }
    players[player_index] = p
  end
  return p
end

---Update per-player boundary visibility index (0..3).
---@param player_index uint
---@param flags { boundary_opacity_index: uint|nil, index: uint|nil }
function backend_data.set_player_visibility(player_index, flags)
  local p = backend_data.ensure_player(player_index)
  local idx = flags and (flags.boundary_opacity_index or flags.index)
  if idx ~= nil then
    local n = math.floor(tonumber(idx) or 0)
    if n < 0 then n = 0 end
    if n > 3 then n = 3 end
    p.boundary_opacity_index = n
  end
  -- notify renderer/UI to update per-player visibility
  render.on_player_visibility_changed(player_index)
  ui.on_backend_changed({ kind = "player-visibility-changed", player_index = player_index })
end

---Expose the discrete boundary opacity index for the renderer.
---@param player_index uint
---@return uint
function backend_data.get_boundary_opacity_index(player_index)
  local p = backend_data.ensure_player(player_index)
  return p.boundary_opacity_index
end

---Get the grid for a force on a specific surface
---@param force_index uint
---@param surface_index uint
---@return GP.Grid
function backend_data.get_grid(force_index, surface_index)
  return backend_data.ensure_grid(force_index, surface_index)
end

---Get the selected region ID for a player
---@param player_index uint
---@return uint
function backend_data.get_selected_region_id(player_index)
  local p = backend_data.ensure_player(player_index)
  return p.selected_region_id
end

---Set the selected region ID for a player
---@param player_index uint
---@param region_id uint
function backend_data.set_selected_region_id(player_index, region_id)
  local p = backend_data.ensure_player(player_index)
  p.selected_region_id = region_id
end

---Get the selected tool for a player
---@param player_index uint
---@return string|nil
function backend_data.get_selected_tool(player_index)
  local p = backend_data.ensure_player(player_index)
  return p.selected_tool
end

---Set the selected tool for a player
---@param player_index uint
---@param tool string|nil
function backend_data.set_selected_tool(player_index, tool)
  local p = backend_data.ensure_player(player_index)
  p.selected_tool = tool
end

-- Reset helpers --------------------------------------------------------------
---Reset backend_data state for a single force.
---@param force_index uint
---@param default_regions boolean|nil  -- if true, backend_data.ensure_force will re-add defaults on next access
function backend_data.reset_force(force_index, default_regions)
  backend_data.ensure_storage()
  storage.gp.forces[force_index] = nil -- reset
end

---Reset all backend_data state (forces, players, undo capacity).
function backend_data.reset_all()
  storage.gp = nil
end

---Reset a single player state (undo/redo stacks, selections).
---@param player_index uint
function backend_data.reset_player(player_index)
  backend_data.ensure_storage()
  storage.gp.players[player_index] = nil
end

---Reset a single surface image map for a force.
---@param force_index uint
---@param surface_index uint
function backend_data.reset_surface(force_index, surface_index)
  local f = backend_data.ensure_force(force_index)
  f.images[surface_index] = { cells = {} }
end


function backend_data.get_from_image(image, x, y)
  local cell_key = tostring(x) .. ":" .. tostring(y)
  return image.cells[cell_key]
end

function backend_data.cell_key(cx, cy)
  return tostring(cx) .. ":" .. tostring(cy)
end

function backend_data.parse_cell_key(key)
  local sx, sy = key:match("^(-?%d+):(-?%d+)$")
  return tonumber(sx), tonumber(sy)
end

-- Normalize any region id to internal storage semantics (nil = Empty)
---@param region_id uint|nil
---@return uint|nil
function backend_data.normalize_region_id(region_id)
  if region_id == nil or region_id == backend_data.EMPTY_REGION_ID then return nil end
  return region_id
end

-- Notifications --------------------------------------------------------------
function backend_data.notify_cells_changed(force_index, surface_index, changed_set, new_region_id)
  if render and render.on_cells_changed then
    render.on_cells_changed(force_index, surface_index, changed_set, new_region_id)
    -- pcall(render.on_cells_changed, force_index, surface_index, changed_set, new_region_id)
  end
  if ui and ui.on_backend_changed then
    pcall(ui.on_backend_changed, { kind = "cells-changed", force_index = force_index, surface_index = surface_index })
  end
end

function backend_data.notify_regions_changed(force_index, event)
  -- event is a GP.RegionChangeEvent table with structure: { type = "...", region_id = ..., region_name = ..., before = ..., after = ... }
  -- If no event provided, default to generic STRUCTURE type (for backwards compatibility)
  if not event then
    event = { type = backend_data.REGION_CHANGE_TYPE.MODIFIED, region_id = 0, region_name = "" }
  end
  
  if render and render.on_regions_changed then
    pcall(render.on_regions_changed, force_index, event)
  end
  if ui and ui.on_backend_changed then
    pcall(ui.on_backend_changed, { kind = "regions-changed", force_index = force_index, event = event })
  end
end

function backend_data.notify_grid_changed(force_index)
  if render and render.on_grid_changed then
    pcall(render.on_grid_changed, force_index)
  end
  if ui and ui.on_backend_changed then
    pcall(ui.on_backend_changed, { kind = "grid-changed", force_index = force_index })
  end
end


---@param force_index uint
function backend_data.get_force(force_index)
  return backend_data.ensure_force(force_index)
end

---Get all regions for a force
---@param force_index uint
---@return table<uint, GP.Region>
function backend_data.get_regions(force_index)
  return backend_data.ensure_force(force_index).regions
end

---Get a specific region by id
---@param force_index uint
---@param region_id uint
---@return GP.Region|nil
function backend_data.get_region(force_index, region_id)
  local regions = backend_data.get_regions(force_index)
  return regions[region_id]
end

---@param force_index uint
---@return table<uint, {cells: table<string, uint?>}>
function backend_data.get_force_images(force_index)
  local f = backend_data.ensure_force(force_index)
  return f.images
end

---@param force_index uint
---@param surface_index uint
---@param x double
---@param y double
---@return integer, integer
function backend_data.tile_to_cell(force_index, surface_index, x, y)
  local g = backend_data.get_grid(force_index, surface_index)
  local cx = math.floor((x - g.x_offset) / g.width)
  local cy = math.floor((y - g.y_offset) / g.height)
  return cx, cy
end


return backend_data
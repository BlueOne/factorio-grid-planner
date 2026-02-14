
-- Backend module
-- Persistence follows Factorio's storage table conventions.
-- Types are annotated for linter assistance.

local backend = {}

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
---@field grid GP.Grid
---@field images table<uint, {cells: table<string, uint?>}>

---@class GP.PlayerState
---@field selected_region_id uint
---@field selected_tool string|nil
---@field undo table[]
---@field redo table[]
---@field boundary_opacity_index uint  -- 0..3 discrete setting for boundary visibility

local EMPTY_REGION_ID = 0
local DEFAULT_GRID = {
  width = 8,
  height = 8,
  x_offset = 0,
  y_offset = 0,
}

-- Region change event types
local REGION_CHANGE_TYPE = {
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
local UNDO_CAPACITY = 100

DEFAULT_REGIONS = {
  { name = "Belts", color = {r=1,g=0.8,b=0} },
  { name = "Trains", color = {r=0.9,g=0.8,b=0.7} },
  { name = "Stations", color = {r=0.7,g=0.6,b=0.5} },
  { name = "Primary Products", color = {r=0.5,g=0.5,b=1.0} },
  { name = "Intermediate Products", color = {r=0.4,g=1.0,b=0.4} },
  { name = "End Products", color = {r=1,g=0.66,b=0.33} },
  { name = "Research", color = {r=0.5,g=0.75,b=1.0} },
  { name = "Power", color = {r=1.0,g=1.0,b=0.5} },
  { name = "Military", color = {r=0.8,g=0.2,b=0.2} },
  { name = "Utility", color = {r=0.9, g=0.4, b=0.8} },
}

---@return GP.StorageRoot
local function ensure_storage()
  if not storage.gp then
    storage.gp = {
      version = 1,
      forces = {}, ---@type table<uint, GP.ForceState>
      players = {}, ---@type table<uint, GP.PlayerState>
      undo_capacity = UNDO_CAPACITY 
    } ---@type GP.StorageRoot
  end
  return storage.gp
end

---@param force_index uint
---@return GP.ForceState
local function ensure_force(force_index)
  ensure_storage()
  local forces = storage.gp.forces
  local f = forces[force_index]
  if not f then
    f = {
      next_region_id = 1, -- 0 reserved for Empty
      regions = {
        [EMPTY_REGION_ID] = { id = EMPTY_REGION_ID, name = "(Empty)", color = {r=0,g=0,b=0,a=0}, order = 0 },
      },
      grid = {
        width = DEFAULT_GRID.width,
        height = DEFAULT_GRID.height,
        x_offset = DEFAULT_GRID.x_offset,
        y_offset = DEFAULT_GRID.y_offset,
      },
      images = {},
    }
    forces[force_index] = f
      for _, def in pairs(DEFAULT_REGIONS) do
      backend.add_region(force_index, 1, def.name, def.color)
    end

  end

  return f
end

---@param force_index uint
---@param surface_index uint
---@return {cells: table<string, uint?>}
function backend.get_surface_image(force_index, surface_index)
  local f = ensure_force(force_index)
  local images = f.images
  if not images[surface_index] then
    images[surface_index] = { cells = {} }
  end
  return images[surface_index]
end

---@param player_index uint
---@return GP.PlayerState
local function ensure_player(player_index)
  ensure_storage()
  local players = storage.gp.players
  local p = players[player_index]
  if not p then
    local g = ensure_force(player_index and game.get_player(player_index) and game.get_player(player_index).force.index or 1).grid
    p = {
      selected_region_id = EMPTY_REGION_ID,
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
function backend.set_player_visibility(player_index, flags)
  local p = ensure_player(player_index)
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
function backend.get_boundary_opacity_index(player_index)
  local p = ensure_player(player_index)
  return p.boundary_opacity_index
end

---Get the selected region ID for a player
---@param player_index uint
---@return uint
function backend.get_selected_region_id(player_index)
  local p = ensure_player(player_index)
  return p.selected_region_id
end

---Set the selected region ID for a player
---@param player_index uint
---@param region_id uint
function backend.set_selected_region_id(player_index, region_id)
  local p = ensure_player(player_index)
  p.selected_region_id = region_id
end

---Get the selected tool for a player
---@param player_index uint
---@return string|nil
function backend.get_selected_tool(player_index)
  local p = ensure_player(player_index)
  return p.selected_tool
end

---Set the selected tool for a player
---@param player_index uint
---@param tool string|nil
function backend.set_selected_tool(player_index, tool)
  local p = ensure_player(player_index)
  p.selected_tool = tool
end

-- Reset helpers --------------------------------------------------------------
---Reset backend state for a single force.
---@param force_index uint
---@param default_regions boolean|nil  -- if true, ensure_force will re-add defaults on next access
function backend.reset_force(force_index, default_regions)
  ensure_storage()
  storage.gp.forces[force_index] = nil -- reset
end

---Reset all backend state (forces, players, undo capacity).
function backend.reset_all()
  storage.gp = nil
end

---Reset a single player state (undo/redo stacks, selections).
---@param player_index uint
function backend.reset_player(player_index)
  ensure_storage()
  storage.gp.players[player_index] = nil
end

---Reset a single surface image map for a force.
---@param force_index uint
---@param surface_index uint
function backend.reset_surface(force_index, surface_index)
  local f = ensure_force(force_index)
  f.images[surface_index] = { cells = {} }
end


function backend.get_from_image(image, x, y)
  local cell_key = tostring(x) .. ":" .. tostring(y)
  return image.cells[cell_key]
end

local function cell_key(cx, cy)
  return tostring(cx) .. ":" .. tostring(cy)
end

local function parse_cell_key(key)
  local sx, sy = key:match("^(-?%d+):(-?%d+)$")
  return tonumber(sx), tonumber(sy)
end

-- Normalize any region id to internal storage semantics (nil = Empty)
---@param region_id uint|nil
---@return uint|nil
local function normalize_region_id(region_id)
  if region_id == nil or region_id == EMPTY_REGION_ID then return nil end
  return region_id
end

-- Notifications --------------------------------------------------------------
local function notify_cells_changed(force_index, surface_index, changed_set, new_region_id)
  if render and render.on_cells_changed then
    render.on_cells_changed(force_index, surface_index, changed_set, new_region_id)
    -- pcall(render.on_cells_changed, force_index, surface_index, changed_set, new_region_id)
  end
  if ui and ui.on_backend_changed then
    pcall(ui.on_backend_changed, { kind = "cells-changed", force_index = force_index, surface_index = surface_index })
  end
end

local function notify_regions_changed(force_index, event)
  -- event is a GP.RegionChangeEvent table with structure: { type = "...", region_id = ..., region_name = ..., before = ..., after = ... }
  -- If no event provided, default to generic STRUCTURE type (for backwards compatibility)
  if not event then
    event = { type = REGION_CHANGE_TYPE.MODIFIED, region_id = 0, region_name = "" }
  end
  
  if render and render.on_regions_changed then
    pcall(render.on_regions_changed, force_index, event)
  end
  if ui and ui.on_backend_changed then
    pcall(ui.on_backend_changed, { kind = "regions-changed", force_index = force_index, event = event })
  end
end

local function notify_grid_changed(force_index)
  if render and render.on_grid_changed then
    pcall(render.on_grid_changed, force_index)
  end
  if ui and ui.on_backend_changed then
    pcall(ui.on_backend_changed, { kind = "grid-changed", force_index = force_index })
  end
end

---@param force_index uint
function backend.get_force(force_index)
  return ensure_force(force_index)
end

---@param force_index uint
---@return GP.Grid
function backend.get_grid(force_index)
  return ensure_force(force_index).grid
end

---Get all regions for a force
---@param force_index uint
---@return table<uint, GP.Region>
function backend.get_regions(force_index)
  return ensure_force(force_index).regions
end

---Get a specific region by id
---@param force_index uint
---@param region_id uint
---@return GP.Region|nil
function backend.get_region(force_index, region_id)
  local regions = backend.get_regions(force_index)
  return regions[region_id]
end

---@param force_index uint
---@return table<uint, {cells: table<string, uint?>}>
function backend.get_force_images(force_index)
  local f = ensure_force(force_index)
  return f.images
end

---@param force_index uint
---@param x double
---@param y double
---@return integer, integer
function backend.tile_to_cell(force_index, x, y)
  local g = backend.get_grid(force_index)
  local cx = math.floor((x - g.x_offset) / g.width)
  local cy = math.floor((y - g.y_offset) / g.height)
  return cx, cy
end

---@param player_index uint
---@param action table
local function push_undo(player_index, action)
  local p = ensure_player(player_index)
  local stack = p.undo
  stack[#stack+1] = action
  -- capacity
  local cap = storage.gp.undo_capacity or UNDO_CAPACITY
  if #stack > cap then
    table.remove(stack, 1)
  end
  -- clear redo on new action
  p.redo = {}
end


---@param force_index uint
---@param name string
---@param color Color
---@return GP.Region, string description
function backend.add_region(force_index, player_index, name, color)
  local f = ensure_force(force_index)

  local id = f.next_region_id
  f.next_region_id = id + 1
  local region = { id = id, name = name, color = { r = color.r or 0, g = color.g or 0, b = color.b or 0, a = color.a or 1 }, order = id }
  f.regions[id] = region
  
  -- If this is the first non-empty region, auto-select it for players without a selection
  local region_count = 0
  for zid, _ in pairs(f.regions) do
    if zid ~= EMPTY_REGION_ID then
      region_count = region_count + 1
    end
  end
  if region_count == 1 then
    storage.gp_ui = storage.gp_ui or {}
    storage.gp_ui.players = storage.gp_ui.players or {}
    for _, player in pairs(game.players) do
      if player.force.index == force_index then
        local pui = storage.gp_ui.players[player.index] or {}
        storage.gp_ui.players[player.index] = pui
        if not pui.selected_region_id or pui.selected_region_id == EMPTY_REGION_ID then
          pui.selected_region_id = id
        end
      end
    end
  end
  
  -- Record undo action
  push_undo(player_index, {
    type = "region-add",
    description = ("Add region '%s'"):format(name),
    force_index = force_index,
    region_id = id,
    region_data = region,
    timestamp = (game and game.tick) or 0,
  })
  
  notify_regions_changed(force_index, {
    type = REGION_CHANGE_TYPE.ADDED,
    region_id = id,
    region_name = name
  })
  return region, ("Add region '%s'"):format(name)
end


---@param force_index uint
---@param player_index uint
---@param id uint
---@param name string
---@param color Color|nil
---@return GP.Region, string description
function backend.edit_region(force_index, player_index, id, name, color)
  local f = ensure_force(force_index)
  if id == EMPTY_REGION_ID then error("Cannot edit Empty region") end
  local z = f.regions[id]
  if not z then error("Region does not exist") end
  local prev = { name = z.name, color = {r=z.color.r,g=z.color.g,b=z.color.b,a=z.color.a} }
  z.name = name
  if color then
    z.color = { r = color.r or 0, g = color.g or 0, b = color.b or 0, a = color.a or 1 }
  end
  
  -- Record undo action (only if something actually changed)
  if (name and name ~= prev.name) or (color and (color.r ~= prev.color.r or color.g ~= prev.color.g or color.b ~= prev.color.b)) then
    local name_only_changed = (name and name ~= prev.name) and not (color and (color.r ~= prev.color.r or color.g ~= prev.color.g or color.b ~= prev.color.b))
    local change_type = name_only_changed and REGION_CHANGE_TYPE.NAME_MODIFIED or REGION_CHANGE_TYPE.MODIFIED
    
    push_undo(player_index, {
      type = "region-edit",
      description = ("Edit region '%s'"):format(prev.name),
      force_index = force_index,
      region_id = id,
      before = prev,
      after = { name = z.name, color = {r=z.color.r,g=z.color.g,b=z.color.b,a=z.color.a} },
      timestamp = (game and game.tick) or 0,
    })
    
    notify_regions_changed(force_index, {
      type = change_type,
      region_id = id,
      region_name = z.name,
      before = prev,
      after = { name = z.name, color = {r=z.color.r,g=z.color.g,b=z.color.b,a=z.color.a} }
    })
  end
  
  return z, ("Edit region '%s'"):format(prev.name)
end

function sorted(t, cmp)
  local copy = {}
  for _, v in pairs(t) do
    table.insert(copy, v)
  end
  table.sort(copy, cmp)
  return copy
end

---Move a region's order up or down by a delta amount.
---Adjusts region orders between source and target to maintain contiguity.
---@param force_index uint
---@param player_index uint
---@param id uint Region ID to move
---@param delta int Number of positions to move (negative = up, positive = down)
---@return string description
function backend.move_region(force_index, player_index, id, delta)
  local f = ensure_force(force_index)
  if id == EMPTY_REGION_ID then error("Cannot move Empty region") end
  local z = f.regions[id]
  if not z then error("Region does not exist") end
  if delta == 0 then return "No movement" end


  -- Collect all non-empty regions sorted by order
  local sorted_regions = sorted(f.regions, function(a, b) if a.id == EMPTY_REGION_ID then return true else if b.id == EMPTY_REGION_ID then return false else return a.order < b.order end end end)
  for i, region in pairs(sorted_regions) do
    region.order = i
  end

  -- Record before state
  local before_orders = {}
  for zid, region in pairs(f.regions) do
    if zid ~= EMPTY_REGION_ID then
      before_orders[zid] = region.order
    end
  end

  if delta > 0 then
    z.order = z.order + delta + 0.5
  end
  if delta < 0 then
    z.order = z.order + delta - 0.5
  end

  -- Re-sort regions by new order and reassign contiguous orders
  sorted_regions = sorted(sorted_regions, function(a, b) return a.order < b.order end)
  for i, region in pairs(sorted_regions) do
    region.order = i
  end

  -- Record after state
  local after_orders = {}
  for zid, region in pairs(f.regions) do
    if zid ~= EMPTY_REGION_ID then
      after_orders[zid] = region.order
    end
  end

  local desc = delta < 0 and "Move region up" or "Move region down"
  push_undo(player_index, {
    type = "region-move",
    description = desc,
    force_index = force_index,
    region_id = id,
    before_orders = before_orders,
    after_orders = after_orders,
    timestamp = (game and game.tick) or 0,
  })

  notify_regions_changed(force_index, {
    type = REGION_CHANGE_TYPE.ORDER_CHANGED,
    region_id = id,
    region_name = z.name
  })
  return desc
end

---@param force_index uint
---@param player_index uint
---@param id uint
---@param replacement_id uint|nil
---@return string description
function backend.delete_region(force_index, player_index, id, replacement_id)
  local f = ensure_force(force_index)
  if id == EMPTY_REGION_ID then error("Cannot delete Empty region") end
  local z = f.regions[id]
  if not z then error("Region does not exist") end
  local replace = replacement_id
  if replace == EMPTY_REGION_ID then replace = nil end
  if replace ~= nil and not f.regions[replace] then error("Replacement region does not exist") end

  -- Store region data before deletion for undo
  local deleted_region = { id = z.id, name = z.name, color = {r=z.color.r,g=z.color.g,b=z.color.b,a=z.color.a}, order = z.order }

  -- Capture affected cells per surface for undo
  local affected_cells = {}
  
  -- Remap assignments across all surfaces
  for surface_index, surface in pairs(f.images) do
    affected_cells[surface_index] = {}
    for key, value in pairs(surface.cells) do
      if value == id then
        affected_cells[surface_index][key] = value  -- Store the original region_id
        surface.cells[key] = replace
      end
    end
    -- Request refresh for surface since many cells may have changed
    notify_cells_changed(force_index, surface_index, nil, nil)
  end
  f.regions[id] = nil
  
  -- Record undo action
  local target_name = (replace == nil) and "(Empty)" or (f.regions[replace] and f.regions[replace].name or tostring(replace))
  push_undo(player_index, {
    type = "region-delete",
    description = ("Delete region '%s' -> %s"):format(z.name, target_name),
    force_index = force_index,
    region_id = id,
    region_data = deleted_region,
    replacement_id = replace,
    affected_cells = affected_cells,
    timestamp = (game and game.tick) or 0,
  })
  
  notify_regions_changed(force_index, {
    type = REGION_CHANGE_TYPE.DELETED,
    region_id = id,
    region_name = z.name,
    before = deleted_region
  })
  return ("Delete region '%s' -> %s" ):format(z.name, target_name)
end

---@param player_index uint
---@param action table
local function push_undo(player_index, action)
  local p = ensure_player(player_index)
  local stack = p.undo
  stack[#stack+1] = action
  -- capacity
  local cap = storage.gp.undo_capacity or UNDO_CAPACITY
  if #stack > cap then
    table.remove(stack, 1)
  end
  -- clear redo on new action
  p.redo = {}
end

---@param player_index uint
---@return string|nil
function backend.peek_undo_description(player_index)
  local p = ensure_player(player_index)
  local last = p.undo[#p.undo]
  return last and last.description or nil
end

---@param player_index uint
---@return string|nil
function backend.peek_redo_description(player_index)
  local p = ensure_player(player_index)
  local last = p.redo[#p.redo]
  return last and last.description or nil
end

---Return whether there is at least one undo action available for the player.
---@param player_index uint
---@return boolean
function backend.can_undo(player_index)
  local p = ensure_player(player_index)
  return (p.undo and #p.undo or 0) > 0
end

---Return whether there is at least one redo action available for the player.
---@param player_index uint
---@return boolean
function backend.can_redo(player_index)
  local p = ensure_player(player_index)
  return (p.redo and #p.redo or 0) > 0
end

---@param player_index uint
---@param force_index uint
---@param surface_index uint
---@param region_id uint|nil
---@param left_top MapPosition
---@param right_bottom MapPosition
---@return number affected_count
function backend.fill_rectangle(player_index, force_index, surface_index, region_id, left_top, right_bottom)
  local f = ensure_force(force_index)
  local surf = backend.get_surface_image(force_index, surface_index)
  local g = f.grid

  local cx1 = math.floor((left_top.x - g.x_offset) / g.width)
  local cy1 = math.floor((left_top.y - g.y_offset) / g.height)
  local cx2 = math.floor((right_bottom.x - g.x_offset) / g.width)
  local cy2 = math.floor((right_bottom.y - g.y_offset) / g.height)

  local minx, maxx = math.min(cx1, cx2), math.max(cx1, cx2)
  local miny, maxy = math.min(cy1, cy2), math.max(cy1, cy2)

  local affected = {}
  local changed_set = {}
  local assign_id = normalize_region_id(region_id)

  local count = 0

  for x = minx, maxx do
    for y = miny, maxy do
      local key = cell_key(x, y)
      local prev = surf.cells[key]
      if prev == EMPTY_REGION_ID then prev = nil end -- sanitize stray 0s to nil
      if prev ~= assign_id then
        affected[key] = { prev = prev }
        surf.cells[key] = assign_id
        changed_set[key] = true
        count = count + 1
      end
    end
  end

  local desc
  if assign_id == nil then
    desc = "Erase rectangle"
  else
    local z = f.regions[assign_id]
    desc = ("Fill rectangle with '%s'" ):format(z and z.name or tostring(assign_id))
  end

  if count > 0 then
    push_undo(player_index, { type = "rect", force_index = force_index, surface_index = surface_index, description = desc, affected = affected, new_region_id = assign_id, timestamp = (game and game.tick) or 0 })
  end
  notify_cells_changed(force_index, surface_index, changed_set, assign_id)
  return count
end

---@param action table
function backend.undo_rect(action)
  local surf = backend.get_surface_image(action.force_index, action.surface_index)
  local changed_set = {}
  for key, info in pairs(action.affected or {}) do
    surf.cells[key] = info.prev
    changed_set[key] = true
  end
  notify_cells_changed(action.force_index, action.surface_index, changed_set, nil)
end

---@param action table
function backend.redo_rect(action)
  local surf = backend.get_surface_image(action.force_index, action.surface_index)
  local changed_set = {}
  for key, _ in pairs(action.affected or {}) do
    surf.cells[key] = action.new_region_id
    changed_set[key] = true
  end
  notify_cells_changed(action.force_index, action.surface_index, changed_set, action.new_region_id)
end


---@param player_index uint
function backend.undo(player_index)
  local p = ensure_player(player_index)
  local action = table.remove(p.undo)
  if not action then return false end

  if action.type == "rect" then
    backend.undo_rect(action)
  elseif action.type == "region-add" then
    local f = ensure_force(action.force_index)
    local region_name = action.region_data and action.region_data.name or "unknown"
    f.regions[action.region_id] = nil
    notify_regions_changed(action.force_index, {
      type = REGION_CHANGE_TYPE.DELETED,
      region_id = action.region_id,
      region_name = region_name,
      before = action.region_data
    })
  elseif action.type == "region-edit" then
    local f = ensure_force(action.force_index)
    local z = f.regions[action.region_id]
    if z and action.before then
      local name_only_changed = (action.before.name ~= action.after.name) and (action.before.color.r == action.after.color.r and action.before.color.g == action.after.color.g and action.before.color.b == action.after.color.b)
      local change_type = name_only_changed and REGION_CHANGE_TYPE.NAME_MODIFIED or REGION_CHANGE_TYPE.MODIFIED
      
      z.name = action.before.name
      z.color = { r = action.before.color.r, g = action.before.color.g, b = action.before.color.b, a = action.before.color.a }
      notify_regions_changed(action.force_index, {
        type = change_type,
        region_id = action.region_id,
        region_name = z.name,
        before = action.after,
        after = action.before
      })
    end
  elseif action.type == "region-delete" then
    local f = ensure_force(action.force_index)
    if action.region_data then
      f.regions[action.region_id] = action.region_data
      -- Restore next_region_id if needed
      if action.region_id >= f.next_region_id then
        f.next_region_id = action.region_id + 1
      end
      -- Restore affected cells
      if action.affected_cells then
        for surface_index, cells in pairs(action.affected_cells) do
          local surf = backend.get_surface_image(action.force_index, surface_index)
          for key, region_id in pairs(cells) do
            surf.cells[key] = region_id
          end
          notify_cells_changed(action.force_index, surface_index, nil, nil)
        end
      end
      notify_regions_changed(action.force_index, {
        type = REGION_CHANGE_TYPE.ADDED,
        region_id = action.region_id,
        region_name = action.region_data.name
      })
    end
  elseif action.type == "region-move" then
    local f = ensure_force(action.force_index)
    if action.before_orders then
      local region_name = "unknown"
      for zid, order in pairs(action.before_orders) do
        if f.regions[zid] then
          f.regions[zid].order = order
          if zid == action.region_id then
            region_name = f.regions[zid].name
          end
        end
      end
      notify_regions_changed(action.force_index, {
        type = REGION_CHANGE_TYPE.ORDER_CHANGED,
        region_id = action.region_id,
        region_name = region_name
      })
    end
  elseif action.type == "grid" then
    local f = ensure_force(action.force_index)
    if action.before_grid then
      f.grid = action.before_grid
      notify_grid_changed(action.force_index)
    end
  elseif action.type == "reproject" then
    local f = ensure_force(action.force_index)
    local surf = backend.get_surface_image(action.force_index, action.surface_index)
    if surf and action.before_map then
      surf.cells = action.before_map
      notify_cells_changed(action.force_index, action.surface_index, nil, nil)
    end
    if action.before_grid then
      f.grid = action.before_grid
      notify_grid_changed(action.force_index)
    end
  end

  p.redo[#p.redo+1] = action
  if ui and ui.on_backend_changed then
    pcall(ui.on_backend_changed, { kind = "undo-redo-changed", player_index = player_index })
  end
  return true
end

---@param player_index uint
function backend.redo(player_index)
  local p = ensure_player(player_index)
  local action = table.remove(p.redo)
  if not action then return false end
  local f = action.force_index and ensure_force(action.force_index) or nil

  if action.type == "rect" then
    backend.redo_rect(action)
  elseif action.type == "region-add" then
    if action.region_data then
      f.regions[action.region_id] = action.region_data
      notify_regions_changed(action.force_index, {
        type = REGION_CHANGE_TYPE.ADDED,
        region_id = action.region_id,
        region_name = action.region_data.name
      })
    end
  elseif action.type == "region-edit" then
    local z = f.regions[action.region_id]
    if z and action.after then
      local name_only_changed = (action.before.name ~= action.after.name) and (action.before.color.r == action.after.color.r and action.before.color.g == action.after.color.g and action.before.color.b == action.after.color.b)
      local change_type = name_only_changed and REGION_CHANGE_TYPE.NAME_MODIFIED or REGION_CHANGE_TYPE.MODIFIED
      
      z.name = action.after.name
      z.color = { r = action.after.color.r, g = action.after.color.g, b = action.after.color.b, a = action.after.color.a }
      notify_regions_changed(action.force_index, {
        type = change_type,
        region_id = action.region_id,
        region_name = z.name,
        before = action.before,
        after = action.after
      })
    end
  elseif action.type == "region-delete" then
    local replace = action.replacement_id
    -- Remap assignments across all surfaces
    if action.affected_cells then
      for surface_index, cells in pairs(action.affected_cells) do
        local surf = backend.get_surface_image(action.force_index, surface_index)
        for key, _ in pairs(cells) do
          surf.cells[key] = replace
        end
        notify_cells_changed(action.force_index, surface_index, nil, nil)
      end
    end
    local region_name = "unknown"
    if action.region_data then
      region_name = action.region_data.name
    end
    f.regions[action.region_id] = nil
    notify_regions_changed(action.force_index, {
      type = REGION_CHANGE_TYPE.DELETED,
      region_id = action.region_id,
      region_name = region_name,
      before = action.region_data
    })
  elseif action.type == "region-move" then
    if action.after_orders then
      local region_name = "unknown"
      for zid, order in pairs(action.after_orders) do
        if f.regions[zid] then
          f.regions[zid].order = order
          if zid == action.region_id then
            region_name = f.regions[zid].name
          end
        end
      end
      notify_regions_changed(action.force_index, {
        type = REGION_CHANGE_TYPE.ORDER_CHANGED,
        region_id = action.region_id,
        region_name = region_name
      })
    end
  elseif action.type == "grid" then
    if action.after_grid then
      f.grid = action.after_grid
      notify_grid_changed(action.force_index)
    end
  elseif action.type == "reproject" then
    local surf = backend.get_surface_image(action.force_index, action.surface_index)
    if surf and action.after_map then
      surf.cells = action.after_map
      notify_cells_changed(action.force_index, action.surface_index, nil, nil)
    end
    if action.after_grid then
      f.grid = action.after_grid
      notify_grid_changed(action.force_index)
    end
  end

  p.undo[#p.undo+1] = action
  if ui and ui.on_backend_changed then
    pcall(ui.on_backend_changed, { kind = "undo-redo-changed", player_index = player_index })
  end
  return true
end

---@param force_index uint
---@param player_index uint
---@param new_props GP.Grid
---@param opts {reproject: boolean}|nil
function backend.set_grid(force_index, player_index, new_props, opts)
  local f = ensure_force(force_index)
  local old = f.grid
  local reproject = opts and opts.reproject
  if not reproject then
    local new_grid = {
      width = new_props.width or old.width,
      height = new_props.height or old.height,
      x_offset = new_props.x_offset or old.x_offset,
      y_offset = new_props.y_offset or old.y_offset,
    }
    f.grid = new_grid
    push_undo(player_index, {
      type = "grid",
      description = "Update grid properties",
      force_index = force_index,
      before_grid = old,
      after_grid = new_grid,
      timestamp = (game and game.tick) or 0,
    })
    notify_grid_changed(force_index)
    return "Update grid properties"
  end

  -- Reproject cells per surface: map old cell areas to new grid cell ranges
  local new_width = new_props.width or old.width
  local new_height = new_props.height or old.height
  local new_x_offset = new_props.x_offset or old.x_offset
  local new_y_offset = new_props.y_offset or old.y_offset
  local epsilon = 0.0001
  
  for surface_index, surface in pairs(f.images) do
    local before_map = surface.cells
    local after_map = {}
    for key, region_id in pairs(before_map) do
      local ocx, ocy = parse_cell_key(key)
      local x0 = ocx * old.width + old.x_offset
      local y0 = ocy * old.height + old.y_offset
      local x1 = x0 + old.width
      local y1 = y0 + old.height

      local nx0 = math.floor((x0 - new_x_offset) / new_width)
      local ny0 = math.floor((y0 - new_y_offset) / new_height)
      local nx1 = math.floor(((x1 - epsilon) - new_x_offset) / new_width)
      local ny1 = math.floor(((y1 - epsilon) - new_y_offset) / new_height)

      local normalized = normalize_region_id(region_id)
      for ncx = nx0, nx1 do
        for ncy = ny0, ny1 do
          local nkey = cell_key(ncx, ncy)
          after_map[nkey] = normalized
        end
      end
    end
    surface.cells = after_map
    -- record action per surface; UI can choose to aggregate
    push_undo(player_index, { -- player_index from caller
      type = "reproject",
      description = "Reproject grid assignments",
      force_index = force_index,
      surface_index = surface_index,
      before_map = before_map,
      after_map = after_map,
      before_grid = old,
      after_grid = {
        width = new_props.width or old.width,
        height = new_props.height or old.height,
        x_offset = new_props.x_offset or old.x_offset,
        y_offset = new_props.y_offset or old.y_offset,
      },
      timestamp = (game and game.tick) or 0,
    })
    notify_cells_changed(force_index, surface_index, nil, nil)
  end
  -- Finally set the new grid
  f.grid = {
    width = new_props.width or old.width,
    height = new_props.height or old.height,
    x_offset = new_props.x_offset or old.x_offset,
    y_offset = new_props.y_offset or old.y_offset,
  }
  notify_grid_changed(force_index)
  return "Reproject and update grid properties"
end


return backend


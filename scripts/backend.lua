
-- Backend module

local backend = require("scripts/backend_data")

local UNDO_CAPACITY = 100

---@param player_index uint
---@param action table
local function push_undo(player_index, action)
  local p = backend.ensure_player(player_index)
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
---@return GP.Region
function backend.add_region(force_index, player_index, name, color)
  local cmd = backend.commands["region-add"].create(force_index, player_index, name, color)
  backend.run_command(player_index, cmd)
  local f = backend.ensure_force(force_index)
  return f.regions[cmd.region_id]
end


-- Base command interface
---@class GP.Command
---@field type string                                    -- Command type identifier
---@field force_index uint
---@field player_index uint
---@field timestamp uint
---@field description string|nil                         -- Human-readable description (set by run_command)

-- Command handler interface
---@class GP.CommandHandler
---@field create fun(...): GP.Command                    -- Factory function
---@field perform fun(cmd: GP.Command): boolean          -- Execute command
---@field undo fun(cmd: GP.Command): boolean|nil         -- Undo command (nil = not undoable)
---@field description fun(cmd: GP.Command): string       -- UI description

backend.commands = require("scripts/commands")


---@param force_index uint
---@param id uint
---@param name string
---@param color Color|nil
function backend.edit_region_internal(force_index, id, name, color)
  local f = backend.ensure_force(force_index)
  if id == backend.EMPTY_REGION_ID then error("Cannot edit Empty region") end
  local z = f.regions[id]
  if not z then error("Region does not exist") end
  local prev = { name = z.name, color = {r=z.color.r,g=z.color.g,b=z.color.b,a=z.color.a} }
  z.name = name

  if color then
    z.color = { r = color.r or 0, g = color.g or 0, b = color.b or 0, a = color.a or 1 }
  end
  if (name and name ~= prev.name) or (color and (color.r ~= prev.color.r or color.g ~= prev.color.g or color.b ~= prev.color.b)) then
    local name_only_changed = (name and name ~= prev.name) and not (color and (color.r ~= prev.color.r or color.g ~= prev.color.g or color.b ~= prev.color.b))
    local change_type = name_only_changed and backend.REGION_CHANGE_TYPE.NAME_MODIFIED or backend.REGION_CHANGE_TYPE.MODIFIED
        
    backend.notify_regions_changed(force_index, {
      type = change_type,
      region_id = id,
      region_name = z.name,
      before = prev,
      after = { name = z.name, color = {r=z.color.r,g=z.color.g,b=z.color.b,a=z.color.a} }
    })
  end
end


---Central command execution function.
---Creates command, executes it, and adds to undo queue if successful and undoable.
---@param player_index uint
---@param cmd GP.Command
---@return boolean success
function backend.run_command(player_index, cmd)
  if not cmd or not cmd.type then
    error("Invalid command: missing type")
    return false
  end
  
  local handler = backend.commands[cmd.type]
  if not handler then
    error("Unknown command type: " .. tostring(cmd.type))
    return false
  end
  
  local success = handler.perform(cmd)
  if success and handler.undo then
    -- Add description to command
    cmd.description = handler.description(cmd)
    push_undo(player_index, cmd)
  end
  
  return success
end

---Migration helper: clear old-format undo/redo queues for a player.
---Call this to purge queues when migrating from old action format to new command format.
---@param player_index uint
function backend.clear_undo_redo(player_index)
  local p = backend.ensure_player(player_index)
  p.undo = {}
  p.redo = {}
  if ui and ui.on_backend_changed then
    pcall(ui.on_backend_changed, { kind = "undo-redo-changed", player_index = player_index })
  end
end


---@param force_index uint
---@param player_index uint
---@param id uint
---@param name string
---@param color Color|nil
function backend.edit_region(force_index, player_index, id, name, color)
  local cmd = backend.commands["region-edit"].create(force_index, player_index, id, name, color)
  backend.run_command(player_index, cmd)
end


---Move a region's order up or down by a delta amount.
---Adjusts region orders between source and target to maintain contiguity.
---@param force_index uint
---@param player_index uint
---@param id uint Region ID to move
---@param delta int Number of positions to move (negative = up, positive = down)
---@return string description
function backend.move_region(force_index, player_index, id, delta)
  if delta == 0 then return "No movement" end
  local cmd = backend.commands["region-move"].create(force_index, player_index, id, delta)
  backend.run_command(player_index, cmd)
  return cmd.description
end

---@param force_index uint
---@param player_index uint
---@param id uint
---@param replacement_id uint|nil
function backend.delete_region(force_index, player_index, id, replacement_id)
  local cmd = backend.commands["region-delete"].create(force_index, player_index, id, replacement_id)
  backend.run_command(player_index, cmd)
end


---@param player_index uint
---@return string|nil
function backend.peek_undo_description(player_index)
  local p = backend.ensure_player(player_index)
  local last = p.undo[#p.undo]
  return last and last.description or nil
end

---@param player_index uint
---@return string|nil
function backend.peek_redo_description(player_index)
  local p = backend.ensure_player(player_index)
  local last = p.redo[#p.redo]
  return last and last.description or nil
end

---Return whether there is at least one undo action available for the player.
---@param player_index uint
---@return boolean
function backend.can_undo(player_index)
  local p = backend.ensure_player(player_index)
  return (p.undo and #p.undo or 0) > 0
end

---Return whether there is at least one redo action available for the player.
---@param player_index uint
---@return boolean
function backend.can_redo(player_index)
  local p = backend.ensure_player(player_index)
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
  local f = backend.ensure_force(force_index)
  local surf = backend.get_surface_image(force_index, surface_index)
  local g = backend.get_grid(force_index, surface_index)

  local cx1 = math.floor((left_top.x - g.x_offset) / g.width)
  local cy1 = math.floor((left_top.y - g.y_offset) / g.height)
  local cx2 = math.floor((right_bottom.x - g.x_offset) / g.width)
  local cy2 = math.floor((right_bottom.y - g.y_offset) / g.height)

  local minx, maxx = math.min(cx1, cx2), math.max(cx1, cx2)
  local miny, maxy = math.min(cy1, cy2), math.max(cy1, cy2)

  local affected = {}
  local assign_id = backend.normalize_region_id(region_id)
  local count = 0

  for x = minx, maxx do
    for y = miny, maxy do
      local key = backend.cell_key(x, y)
      local prev = surf.cells[key]
      if prev == backend.EMPTY_REGION_ID then prev = nil end
      if prev ~= assign_id then
        affected[key] = { prev = prev }
        count = count + 1
      end
    end
  end

  if count > 0 then
    local cmd = backend.commands["draw_cells"].create(force_index, player_index, surface_index, affected, assign_id)
    backend.run_command(player_index, cmd)
  end
  
  return count
end


---@param player_index uint
function backend.undo(player_index)
  local p = backend.ensure_player(player_index)
  local cmd = table.remove(p.undo)
  if not cmd then return false end
  
  -- Handle both old action format and new command format
  local handler = backend.commands[cmd.type]
  if handler and handler.undo then
    handler.undo(cmd)
  else
    -- Unknown command type, log warning and skip
    log("Warning: Cannot undo unknown command type: " .. tostring(cmd.type))
  end
  
  p.redo[#p.redo+1] = cmd
  if ui and ui.on_backend_changed then
    pcall(ui.on_backend_changed, { kind = "undo-redo-changed", player_index = player_index })
  end
  return true
end

---@param player_index uint
function backend.redo(player_index)
  local p = backend.ensure_player(player_index)
  local cmd = table.remove(p.redo)
  if not cmd then return false end
  
  -- Handle both old action format and new command format
  local handler = backend.commands[cmd.type]
  if handler and handler.perform then
    handler.perform(cmd)
  else
    -- Unknown command type, log warning and skip
    log("Warning: Cannot redo unknown command type: " .. tostring(cmd.type))
  end
  
  p.undo[#p.undo+1] = cmd
  if ui and ui.on_backend_changed then
    pcall(ui.on_backend_changed, { kind = "undo-redo-changed", player_index = player_index })
  end
  return true
end

---@param force_index uint
---@param surface_index uint
---@param player_index uint
---@param new_props GP.Grid
---@param opts {reproject: boolean}|nil
function backend.set_grid(force_index, surface_index, player_index, new_props, opts)
  local f = backend.ensure_force(force_index)
  local old = backend.ensure_grid(force_index, surface_index)
  local reproject = opts and opts.reproject
  
  local new_grid = {
    width = new_props.width or old.width,
    height = new_props.height or old.height,
    x_offset = new_props.x_offset or old.x_offset,
    y_offset = new_props.y_offset or old.y_offset,
  }
  
  if not reproject then
    local cmd = backend.commands["grid"].create(force_index, player_index, surface_index, old, new_grid)
    backend.run_command(player_index, cmd)
    return "Update grid properties"
  end

  -- Reproject cells: map old cell areas to new grid cells
  local new_width = new_grid.width
  local new_height = new_grid.height
  local new_x_offset = new_grid.x_offset
  local new_y_offset = new_grid.y_offset
  local epsilon = 0.0001
  
  local surface = backend.get_surface_image(force_index, surface_index)
  local before_map = surface.cells
  local after_map = {}
  
  for key, region_id in pairs(before_map) do
    local ocx, ocy = backend.parse_cell_key(key)
    local x0 = ocx * old.width + old.x_offset
    local y0 = ocy * old.height + old.y_offset
    local x1 = x0 + old.width
    local y1 = y0 + old.height

    local nx0 = math.floor((x0 - new_x_offset) / new_width)
    local ny0 = math.floor((y0 - new_y_offset) / new_height)
    local nx1 = math.floor(((x1 - epsilon) - new_x_offset) / new_width)
    local ny1 = math.floor(((y1 - epsilon) - new_y_offset) / new_height)

    local normalized = backend.normalize_region_id(region_id)
    for ncx = nx0, nx1 do
      for ncy = ny0, ny1 do
        local nkey = backend.cell_key(ncx, ncy)
        after_map[nkey] = normalized
      end
    end
  end
  
  local cmd = backend.commands["reproject"].create(force_index, player_index, surface_index, old, new_grid, before_map, after_map)
  backend.run_command(player_index, cmd)
  return "Reproject and update grid properties"
end


return backend


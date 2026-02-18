
commands = {}

-- region-add command
---@class GP.AddRegionCommand : GP.Command
---@field type "region-add"
---@field region_id uint
---@field region_data GP.Region
commands["region-add"] = {
  ---@param force_index uint
  ---@param player_index uint
  ---@param name string
  ---@param color Color
  ---@return GP.AddRegionCommand
  create = function(force_index, player_index, name, color)
    local f = backend.ensure_force(force_index)
    local id = f.next_region_id
    f.next_region_id = id + 1
    local region = { id = id, name = name, color = { r = color.r or 0, g = color.g or 0, b = color.b or 0, a = color.a or 1 }, order = id }
    return {
      type = "region-add",
      force_index = force_index,
      player_index = player_index,
      region_id = id,
      region_data = region,
      timestamp = (game and game.tick) or 0,
    }
  end,
  ---@param cmd GP.AddRegionCommand
  perform = function(cmd)
    local f = backend.ensure_force(cmd.force_index)
    f.regions[cmd.region_id] = cmd.region_data
    
    -- Auto-select first region for players without a selection
    local region_count = 0
    for zid, _ in pairs(f.regions) do
      if zid ~= backend.EMPTY_REGION_ID then
        region_count = region_count + 1
      end
    end
    if region_count == 1 then
      storage.gp_ui = storage.gp_ui or {}
      storage.gp_ui.players = storage.gp_ui.players or {}
      for _, player in pairs(game.players) do
        if player.force.index == cmd.force_index then
          local pui = storage.gp_ui.players[player.index] or {}
          storage.gp_ui.players[player.index] = pui
          if not pui.selected_region_id or pui.selected_region_id == backend.EMPTY_REGION_ID then
            pui.selected_region_id = cmd.region_id
          end
        end
      end
    end
    
    backend.notify_regions_changed(cmd.force_index, {
      type = backend.REGION_CHANGE_TYPE.ADDED,
      region_id = cmd.region_id,
      region_name = cmd.region_data.name
    })
    return true
  end,
  ---@param cmd GP.AddRegionCommand
  undo = function(cmd)
    local f = backend.ensure_force(cmd.force_index)
    f.regions[cmd.region_id] = nil
    backend.notify_regions_changed(cmd.force_index, {
      type = backend.REGION_CHANGE_TYPE.DELETED,
      region_id = cmd.region_id,
      region_name = cmd.region_data.name,
      before = cmd.region_data
    })
    return true
  end,
  ---@param cmd GP.AddRegionCommand
  description = function(cmd)
    return ("Add region '%s'"):format(cmd.region_data.name)
  end,
}

-- region-edit command
---@class GP.EditRegionCommand : GP.Command
---@field type "region-edit"
---@field region_id uint
---@field name string
---@field color Color
---@field before { name: string, color: Color }
commands["region-edit"] = {
  ---@param force_index uint
  ---@param player_index uint
  ---@param region_id uint
  ---@param name string|nil
  ---@param color Color|nil
  ---@return GP.EditRegionCommand
  create = function(force_index, player_index, region_id, name, color)
    local previous = backend.get_region(force_index, region_id)
    if not previous then error("Region does not exist") end
    return {
      type = "region-edit",
      force_index = force_index,
      player_index = player_index,
      region_id = region_id,
      name = name,
      color = color,
      before = { name = previous.name, color = {r=previous.color.r, g=previous.color.g, b=previous.color.b, a=previous.color.a} },
      timestamp = (game and game.tick) or 0,
    }
  end,
  ---@param cmd GP.EditRegionCommand
  perform = function(cmd)
    local success, err = pcall(function()
      return backend.edit_region_internal(cmd.force_index, cmd.region_id, cmd.name, cmd.color)
    end)
    if not success then
      log("Error performing edit-region command: " .. tostring(err))
      return false
    end
    return true
  end,
  ---@param cmd GP.EditRegionCommand
  undo = function(cmd)
    local success, err = pcall(function()
      return backend.edit_region_internal(cmd.force_index, cmd.region_id, cmd.before.name, cmd.before.color)
    end)
    if not success then
      log("Error undoing edit-region command: " .. tostring(err))
      return false
    end
    return true
  end,
  ---@param cmd GP.EditRegionCommand
  description = function(cmd)
    return ("Edit region '%s'"):format(cmd.name or ("ID " .. tostring(cmd.region_id)))
  end,
}

-- region-delete command
---@class GP.DeleteRegionCommand : GP.Command
---@field type "region-delete"
---@field region_id uint
---@field region_data GP.Region
---@field replacement_id uint|nil
---@field affected_cells table<uint, table<string, uint>>
commands["region-delete"] = {
  ---@param force_index uint
  ---@param player_index uint
  ---@param region_id uint
  ---@param replacement_id uint|nil
  ---@return GP.DeleteRegionCommand
  create = function(force_index, player_index, region_id, replacement_id)
    local f = backend.ensure_force(force_index)
    if region_id == backend.EMPTY_REGION_ID then error("Cannot delete Empty region") end
    local z = f.regions[region_id]
    if not z then error("Region does not exist") end
    local replace = replacement_id
    if replace == backend.EMPTY_REGION_ID then replace = nil end
    if replace ~= nil and not f.regions[replace] then error("Replacement region does not exist") end
    
    local deleted_region = { id = z.id, name = z.name, color = {r=z.color.r,g=z.color.g,b=z.color.b,a=z.color.a}, order = z.order }
    local affected_cells = {}
    
    for surface_index, surface in pairs(f.images) do
      affected_cells[surface_index] = {}
      for key, value in pairs(surface.cells) do
        if value == region_id then
          affected_cells[surface_index][key] = value
        end
      end
    end
    
    return {
      type = "region-delete",
      force_index = force_index,
      player_index = player_index,
      region_id = region_id,
      region_data = deleted_region,
      replacement_id = replace,
      affected_cells = affected_cells,
      timestamp = (game and game.tick) or 0,
    }
  end,
  ---@param cmd GP.DeleteRegionCommand
  perform = function(cmd)
    local f = backend.ensure_force(cmd.force_index)
    f.regions[cmd.region_id] = nil
    
    for surface_index, cells in pairs(cmd.affected_cells) do
      local surf = backend.get_surface_image(cmd.force_index, surface_index)
      for key, _ in pairs(cells) do
        surf.cells[key] = cmd.replacement_id
      end
      backend.notify_cells_changed(cmd.force_index, surface_index, nil, nil)
    end
    
    backend.notify_regions_changed(cmd.force_index, {
      type = backend.REGION_CHANGE_TYPE.DELETED,
      region_id = cmd.region_id,
      region_name = cmd.region_data.name,
      before = cmd.region_data
    })
    return true
  end,
  ---@param cmd GP.DeleteRegionCommand
  undo = function(cmd)
    local f = backend.ensure_force(cmd.force_index)
    f.regions[cmd.region_id] = cmd.region_data
    
    if cmd.region_id >= f.next_region_id then
      f.next_region_id = cmd.region_id + 1
    end
    
    for surface_index, cells in pairs(cmd.affected_cells) do
      local surf = backend.get_surface_image(cmd.force_index, surface_index)
      for key, region_id in pairs(cells) do
        surf.cells[key] = region_id
      end
      backend.notify_cells_changed(cmd.force_index, surface_index, nil, nil)
    end
    
    backend.notify_regions_changed(cmd.force_index, {
      type = backend.REGION_CHANGE_TYPE.ADDED,
      region_id = cmd.region_id,
      region_name = cmd.region_data.name
    })
    return true
  end,
  ---@param cmd GP.DeleteRegionCommand
  description = function(cmd)
    local target_name = (cmd.replacement_id == nil) and "(Empty)" or tostring(cmd.replacement_id)
    return ("Delete region '%s' -> %s"):format(cmd.region_data.name, target_name)
  end,
}


---@class GP.MoveRegionCommand : GP.Command
---@field type "region-move"
---@field region_id uint
---@field before_orders table<uint, uint>  -- region_id -> order before move
---@field after_orders table<uint, uint>   -- region_id -> order after move

function sorted(t, cmp)
  local copy = {}
  for _, v in pairs(t) do
    table.insert(copy, v)
  end
  table.sort(copy, cmp)
  return copy
end

commands["region-move"] = {
  ---@param force_index uint
  ---@param player_index uint
  ---@param region_id uint
  ---@param delta  int
  ---@return GP.MoveRegionCommand
  create = function(force_index, player_index, region_id, delta)
    local f = backend.ensure_force(force_index)
    if region_id == backend.EMPTY_REGION_ID then error("Cannot move Empty region") end
      local z = f.regions[region_id]
      if not z then error("Region does not exist") end
      if delta == 0 then error("No movement") end
      
      local sorted_regions = sorted(f.regions, function(a, b)
        if a.id == backend.EMPTY_REGION_ID then 
          return true
        else if b.id == backend.EMPTY_REGION_ID then return false
        else return a.order < b.order end end
      end)
      for i, region in pairs(sorted_regions) do
        region.order = i
    end
    
    local before_orders = {}
    for zid, region in pairs(f.regions) do
      if zid ~= backend.EMPTY_REGION_ID then
        before_orders[zid] = region.order
      end
    end
    
    if delta > 0 then
      z.order = z.order + delta + 0.5
    else
      z.order = z.order + delta - 0.5
    end
    
    sorted_regions = sorted(sorted_regions, function(a, b) return a.order < b.order end)
    for i, region in pairs(sorted_regions) do
      region.order = i
    end
    
    local after_orders = {}
    for zid, region in pairs(f.regions) do
      if zid ~= backend.EMPTY_REGION_ID then
        after_orders[zid] = region.order
      end
    end
    
    return {
      type = "region-move",
      force_index = force_index,
      player_index = player_index,
      region_id = region_id,
      before_orders = before_orders,
      after_orders = after_orders,
      timestamp = (game and game.tick) or 0,
    }
  end,
  ---@param cmd GP.MoveRegionCommand
  perform = function(cmd)
    local f = backend.ensure_force(cmd.force_index)
    for zid, order in pairs(cmd.after_orders) do
      if f.regions[zid] then
        f.regions[zid].order = order
      end
    end
    backend.notify_regions_changed(cmd.force_index, {
      type = backend.REGION_CHANGE_TYPE.ORDER_CHANGED,
      region_id = cmd.region_id,
      region_name = f.regions[cmd.region_id] and f.regions[cmd.region_id].name or "unknown"
    })
    return true
  end,
  ---@param cmd GP.MoveRegionCommand
  undo = function(cmd)
    local f = backend.ensure_force(cmd.force_index)
    for zid, order in pairs(cmd.before_orders) do
      if f.regions[zid] then
        f.regions[zid].order = order
      end
    end
    backend.notify_regions_changed(cmd.force_index, {
      type = backend.REGION_CHANGE_TYPE.ORDER_CHANGED,
      region_id = cmd.region_id,
      region_name = f.regions[cmd.region_id] and f.regions[cmd.region_id].name or "unknown"
    })
    return true
  end,
  ---@param cmd GP.MoveRegionCommand
  description = function(cmd)
    local region = backend.get_region(cmd.force_index, cmd.region_id)
    return "Move region '" .. (region and region.name or tostring(cmd.region_id)) .. "'"
  end,
}


---@class GP.FillRectCommand : GP.Command
---@field type "rect"
---@field affected table<string, {prev: uint|nil}>  -- cell_key -> { prev = region_id or nil }
---@field new_region_id uint|nil
---@field surface_index uint

-- set cells command
commands["draw_cells"] = {
  ---@param force_index uint
  ---@param player_index uint
  ---@param surface_index uint
  ---@param affected table<string, {prev: uint|nil}>
  ---@param new_region_id uint|nil
  ---@return GP.FillRectCommand
  create = function(force_index, player_index, surface_index, affected, new_region_id)
    return {
      type = "draw_cells",
      force_index = force_index,
      player_index = player_index,
      surface_index = surface_index,
      affected = affected,
      new_region_id = new_region_id,
      timestamp = (game and game.tick) or 0,
    }
  end,
  ---@param cmd GP.FillRectCommand
  perform = function(cmd)
    local surf = backend.get_surface_image(cmd.force_index, cmd.surface_index)
    local changed_set = {}
    for key, _ in pairs(cmd.affected) do
      surf.cells[key] = cmd.new_region_id
      changed_set[key] = true
    end
    backend.notify_cells_changed(cmd.force_index, cmd.surface_index, changed_set, cmd.new_region_id)
    return true
  end,
  ---@param cmd GP.FillRectCommand
  undo = function(cmd)
    local surf = backend.get_surface_image(cmd.force_index, cmd.surface_index)
    local changed_set = {}
    for key, info in pairs(cmd.affected) do
      surf.cells[key] = info.prev
      changed_set[key] = true
    end
    backend.notify_cells_changed(cmd.force_index, cmd.surface_index, changed_set, nil)
    return true
  end,
  ---@param cmd GP.FillRectCommand
  description = function(cmd)
    if cmd.new_region_id == nil then
      return "Erase"
    else
      local f = backend.ensure_force(cmd.force_index)
      local z = f.regions[cmd.new_region_id]
      return ("Draw '%s'"):format(z and z.name or tostring(cmd.new_region_id))
    end
  end,
}


---@class GP.GridCommand : GP.Command
---@field type "grid"
---@field surface_index uint
---@field before_grid GP.Grid
---@field after_grid GP.Grid
-- grid command
commands["grid"] = {
  ---@param force_index uint
  ---@param player_index uint
  ---@param surface_index uint
  ---@param before_grid GP.Grid
  ---@param after_grid GP.Grid
  ---@return GP.GridCommand
  create = function(force_index, player_index, surface_index, before_grid, after_grid)
    return {
      type = "grid",
      force_index = force_index,
      player_index = player_index,
      surface_index = surface_index,
      before_grid = before_grid,
      after_grid = after_grid,
      timestamp = (game and game.tick) or 0,
    }
  end,
  ---@param cmd GP.GridCommand
  perform = function(cmd)
    local f = backend.ensure_force(cmd.force_index)
    f.grids[cmd.surface_index] = cmd.after_grid
    backend.notify_grid_changed(cmd.force_index)
    return true
  end,
  ---@param cmd GP.GridCommand
  undo = function(cmd)
    local f = backend.ensure_force(cmd.force_index)
    f.grids[cmd.surface_index] = cmd.before_grid
    backend.notify_grid_changed(cmd.force_index)
    return true
  end,
  ---@param cmd GP.GridCommand
  description = function(cmd)
    return "Update grid properties"
  end,
}


---@class GP.ReprojectCommand : GP.Command
---@field type "reproject"
---@field surface_index uint
---@field before_grid GP.Grid
---@field after_grid GP.Grid
---@field before_map table<string, uint|nil>
---@field after_map table<string, uint|nil>
-- reproject command
commands["reproject"] = {
  ---@param force_index uint
  ---@param player_index uint
  ---@param surface_index uint
  ---@param before_grid GP.Grid
  ---@param after_grid GP.Grid
  ---@param before_map table<string, uint|nil>
  ---@param after_map table<string, uint|nil>
  ---@return GP.ReprojectCommand
  create = function(force_index, player_index, surface_index, before_grid, after_grid, before_map, after_map)
    return {
      type = "reproject",
      force_index = force_index,
      player_index = player_index,
      surface_index = surface_index,
      before_grid = before_grid,
      after_grid = after_grid,
      before_map = before_map,
      after_map = after_map,
      timestamp = (game and game.tick) or 0,
    }
  end,
  ---@param cmd GP.ReprojectCommand
  perform = function(cmd)
    local f = backend.ensure_force(cmd.force_index)
    local surf = backend.get_surface_image(cmd.force_index, cmd.surface_index)
    surf.cells = cmd.after_map
    f.grids[cmd.surface_index] = cmd.after_grid
    backend.notify_cells_changed(cmd.force_index, cmd.surface_index, nil, nil)
    backend.notify_grid_changed(cmd.force_index)
    return true
  end,
  ---@param cmd GP.ReprojectCommand
  undo = function(cmd)
    local f = backend.ensure_force(cmd.force_index)
    local surf = backend.get_surface_image(cmd.force_index, cmd.surface_index)
    surf.cells = cmd.before_map
    f.grids[cmd.surface_index] = cmd.before_grid
    backend.notify_cells_changed(cmd.force_index, cmd.surface_index, nil, nil)
    backend.notify_grid_changed(cmd.force_index)
    return true
  end,
  ---@param cmd GP.ReprojectCommand
  description = function(cmd)
    return "Reproject grid assignments"
  end,
}

return commands
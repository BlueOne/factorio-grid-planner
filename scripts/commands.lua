
commands = {}

-- We could move this to metatables instead of a registry, but the current system works.

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
---@field affected_cells table<uint, table<uint, table<string, uint>>>  -- surface_index -> layer_id -> cell_key -> region_id
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

    for surface_index, surf in pairs(f.surfaces) do
      for layer_id, layer in pairs(surf.layers) do
        for key, value in pairs(layer.cells) do
          if value == region_id then
            affected_cells[surface_index] = affected_cells[surface_index] or {}
            affected_cells[surface_index][layer_id] = affected_cells[surface_index][layer_id] or {}
            affected_cells[surface_index][layer_id][key] = value
          end
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

    for surface_index, layers_map in pairs(cmd.affected_cells) do
      for layer_id, cells in pairs(layers_map) do
        local layer = backend.get_layer(cmd.force_index, surface_index, layer_id)
        if layer then
          for key, _ in pairs(cells) do
            layer.cells[key] = cmd.replacement_id
          end
          backend.notify_cells_changed(cmd.force_index, surface_index, layer_id, nil)
        end
      end
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

    for surface_index, layers_map in pairs(cmd.affected_cells) do
      for layer_id, cells in pairs(layers_map) do
        local layer = backend.get_layer(cmd.force_index, surface_index, layer_id)
        if layer then
          for key, region_id in pairs(cells) do
            layer.cells[key] = region_id
          end
          backend.notify_cells_changed(cmd.force_index, surface_index, layer_id, nil)
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
---@field type "draw_cells"
---@field affected table<string, {prev: uint|nil}>  -- cell_key -> { prev = region_id or nil }
---@field new_region_id uint|nil
---@field surface_index uint
---@field layer_id uint

-- set cells command
commands["draw_cells"] = {
  ---@param force_index uint
  ---@param player_index uint
  ---@param surface_index uint
  ---@param layer_id uint
  ---@param affected table<string, {prev: uint|nil}>
  ---@param new_region_id uint|nil
  ---@return GP.FillRectCommand
  create = function(force_index, player_index, surface_index, layer_id, affected, new_region_id)
    return {
      type = "draw_cells",
      force_index = force_index,
      player_index = player_index,
      surface_index = surface_index,
      layer_id = layer_id,
      affected = affected,
      new_region_id = new_region_id,
      timestamp = (game and game.tick) or 0,
    }
  end,
  ---@param cmd GP.FillRectCommand
  perform = function(cmd)
    local layer = backend.get_layer(cmd.force_index, cmd.surface_index, cmd.layer_id)
    if not layer then return false end
    local changed_set = {}
    for key, _ in pairs(cmd.affected) do
      layer.cells[key] = cmd.new_region_id
      changed_set[key] = true
    end
    backend.notify_cells_changed(cmd.force_index, cmd.surface_index, cmd.layer_id, changed_set)
    return true
  end,
  ---@param cmd GP.FillRectCommand
  undo = function(cmd)
    local layer = backend.get_layer(cmd.force_index, cmd.surface_index, cmd.layer_id)
    if not layer then return false end
    local changed_set = {}
    for key, info in pairs(cmd.affected) do
      layer.cells[key] = info.prev
      changed_set[key] = true
    end
    backend.notify_cells_changed(cmd.force_index, cmd.surface_index, cmd.layer_id, changed_set)
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
---@field layer_id uint
---@field before_grid GP.Grid
---@field after_grid GP.Grid
-- grid command
commands["grid"] = {
  ---@param force_index uint
  ---@param player_index uint
  ---@param surface_index uint
  ---@param layer_id uint
  ---@param before_grid GP.Grid
  ---@param after_grid GP.Grid
  ---@return GP.GridCommand
  create = function(force_index, player_index, surface_index, layer_id, before_grid, after_grid)
    return {
      type = "grid",
      force_index = force_index,
      player_index = player_index,
      surface_index = surface_index,
      layer_id = layer_id,
      before_grid = before_grid,
      after_grid = after_grid,
      timestamp = (game and game.tick) or 0,
    }
  end,
  ---@param cmd GP.GridCommand
  perform = function(cmd)
    local layer = backend.get_layer(cmd.force_index, cmd.surface_index, cmd.layer_id)
    if not layer then return false end
    layer.grid = cmd.after_grid
    backend.notify_grid_changed(cmd.force_index, cmd.surface_index)
    return true
  end,
  ---@param cmd GP.GridCommand
  undo = function(cmd)
    local layer = backend.get_layer(cmd.force_index, cmd.surface_index, cmd.layer_id)
    if not layer then return false end
    layer.grid = cmd.before_grid
    backend.notify_grid_changed(cmd.force_index, cmd.surface_index)
    return true
  end,
  description = function(_)
    return "Update grid properties"
  end,
}


---@class GP.ReprojectCommand : GP.Command
---@field type "reproject"
---@field surface_index uint
---@field layer_id uint
---@field before_grid GP.Grid
---@field after_grid GP.Grid
---@field before_map table<string, uint|nil>
---@field after_map table<string, uint|nil>
-- reproject command
commands["reproject"] = {
  ---@param force_index uint
  ---@param player_index uint
  ---@param surface_index uint
  ---@param layer_id uint
  ---@param before_grid GP.Grid
  ---@param after_grid GP.Grid
  ---@param before_map table<string, uint|nil>
  ---@param after_map table<string, uint|nil>
  ---@return GP.ReprojectCommand
  create = function(force_index, player_index, surface_index, layer_id, before_grid, after_grid, before_map, after_map)
    return {
      type = "reproject",
      force_index = force_index,
      player_index = player_index,
      surface_index = surface_index,
      layer_id = layer_id,
      before_grid = before_grid,
      after_grid = after_grid,
      before_map = before_map,
      after_map = after_map,
      timestamp = (game and game.tick) or 0,
    }
  end,
  ---@param cmd GP.ReprojectCommand
  perform = function(cmd)
    local layer = backend.get_layer(cmd.force_index, cmd.surface_index, cmd.layer_id)
    if not layer then return false end
    layer.cells = cmd.after_map
    layer.grid = cmd.after_grid
    backend.notify_cells_changed(cmd.force_index, cmd.surface_index, cmd.layer_id, nil)
    backend.notify_grid_changed(cmd.force_index, cmd.surface_index)
    return true
  end,
  ---@param cmd GP.ReprojectCommand
  undo = function(cmd)
    local layer = backend.get_layer(cmd.force_index, cmd.surface_index, cmd.layer_id)
    if not layer then return false end
    layer.cells = cmd.before_map
    layer.grid = cmd.before_grid
    backend.notify_cells_changed(cmd.force_index, cmd.surface_index, cmd.layer_id, nil)
    backend.notify_grid_changed(cmd.force_index, cmd.surface_index)
    return true
  end,
  description = function(_)
    return "Reproject grid assignments"
  end,
}


-- layer-add command
---@class GP.AddLayerCommand : GP.Command
---@field type "layer-add"
---@field surface_index uint
---@field layer_id uint
---@field layer_data GP.Layer
commands["layer-add"] = {
  ---@param force_index uint
  ---@param player_index uint
  ---@param surface_index uint
  ---@param name string
  ---@param grid GP.Grid
  ---@return GP.AddLayerCommand
  create = function(force_index, player_index, surface_index, name, grid)
    local surf = backend.ensure_surface(force_index, surface_index)
    local id = surf.next_layer_id
    surf.next_layer_id = id + 1
    local max_order = 0
    for _, l in pairs(surf.layers) do
      if l.order > max_order then max_order = l.order end
    end
    local layer = {
      id = id,
      name = name,
      order = max_order + 1,
      visible = true,
      grid = { width = grid.width, height = grid.height, x_offset = grid.x_offset, y_offset = grid.y_offset },
      cells = {},
    }
    return {
      type = "layer-add",
      force_index = force_index,
      player_index = player_index,
      surface_index = surface_index,
      layer_id = id,
      layer_data = layer,
      timestamp = (game and game.tick) or 0,
    }
  end,
  ---@param cmd GP.AddLayerCommand
  perform = function(cmd)
    local surf = backend.ensure_surface(cmd.force_index, cmd.surface_index)
    surf.layers[cmd.layer_id] = cmd.layer_data
    backend.notify_layer_changed(cmd.force_index, cmd.surface_index, {
      type = backend.LAYER_CHANGE_TYPE.ADDED,
      layer_id = cmd.layer_id,
    })
    return true
  end,
  ---@param cmd GP.AddLayerCommand
  undo = function(cmd)
    local surf = backend.ensure_surface(cmd.force_index, cmd.surface_index)
    surf.layers[cmd.layer_id] = nil
    backend.notify_layer_changed(cmd.force_index, cmd.surface_index, {
      type = backend.LAYER_CHANGE_TYPE.DELETED,
      layer_id = cmd.layer_id,
    })
    return true
  end,
  ---@param cmd GP.AddLayerCommand
  description = function(cmd)
    return ("Add layer '%s'"):format(cmd.layer_data.name)
  end,
}


-- layer-delete command
---@class GP.DeleteLayerCommand : GP.Command
---@field type "layer-delete"
---@field surface_index uint
---@field layer_id uint
---@field layer_data GP.Layer
commands["layer-delete"] = {
  ---@param force_index uint
  ---@param player_index uint
  ---@param surface_index uint
  ---@param layer_id uint
  ---@return GP.DeleteLayerCommand
  create = function(force_index, player_index, surface_index, layer_id)
    local surf = backend.ensure_surface(force_index, surface_index)
    if not surf.layers[layer_id] then error("Layer does not exist") end
    local layer_count = 0
    for _ in pairs(surf.layers) do layer_count = layer_count + 1 end
    if layer_count <= 1 then error("Cannot delete the last layer") end
    -- deep-copy layer for undo (including cells table)
    local src = surf.layers[layer_id]
    local cells_copy = {}
    for k, v in pairs(src.cells) do cells_copy[k] = v end
    local snap = {
      id = src.id, name = src.name, order = src.order, visible = src.visible,
      grid = { width = src.grid.width, height = src.grid.height, x_offset = src.grid.x_offset, y_offset = src.grid.y_offset },
      cells = cells_copy,
    }
    return {
      type = "layer-delete",
      force_index = force_index,
      player_index = player_index,
      surface_index = surface_index,
      layer_id = layer_id,
      layer_data = snap,
      timestamp = (game and game.tick) or 0,
    }
  end,
  ---@param cmd GP.DeleteLayerCommand
  perform = function(cmd)
    local surf = backend.ensure_surface(cmd.force_index, cmd.surface_index)
    surf.layers[cmd.layer_id] = nil
    backend.notify_layer_changed(cmd.force_index, cmd.surface_index, {
      type = backend.LAYER_CHANGE_TYPE.DELETED,
      layer_id = cmd.layer_id,
    })
    return true
  end,
  ---@param cmd GP.DeleteLayerCommand
  undo = function(cmd)
    local surf = backend.ensure_surface(cmd.force_index, cmd.surface_index)
    surf.layers[cmd.layer_id] = cmd.layer_data
    backend.notify_layer_changed(cmd.force_index, cmd.surface_index, {
      type = backend.LAYER_CHANGE_TYPE.ADDED,
      layer_id = cmd.layer_id,
    })
    return true
  end,
  ---@param cmd GP.DeleteLayerCommand
  description = function(cmd)
    return ("Delete layer '%s'"):format(cmd.layer_data.name)
  end,
}


-- layer-edit command (rename)
---@class GP.EditLayerCommand : GP.Command
---@field type "layer-edit"
---@field surface_index uint
---@field layer_id uint
---@field name string
---@field before_name string
commands["layer-edit"] = {
  ---@param force_index uint
  ---@param player_index uint
  ---@param surface_index uint
  ---@param layer_id uint
  ---@param name string
  ---@return GP.EditLayerCommand
  create = function(force_index, player_index, surface_index, layer_id, name)
    local layer = backend.get_layer(force_index, surface_index, layer_id)
    if not layer then error("Layer does not exist") end
    return {
      type = "layer-edit",
      force_index = force_index,
      player_index = player_index,
      surface_index = surface_index,
      layer_id = layer_id,
      name = name,
      before_name = layer.name,
      timestamp = (game and game.tick) or 0,
    }
  end,
  ---@param cmd GP.EditLayerCommand
  perform = function(cmd)
    local layer = backend.get_layer(cmd.force_index, cmd.surface_index, cmd.layer_id)
    if not layer then return false end
    layer.name = cmd.name
    backend.notify_layer_changed(cmd.force_index, cmd.surface_index, {
      type = backend.LAYER_CHANGE_TYPE.MODIFIED,
      layer_id = cmd.layer_id,
    })
    return true
  end,
  ---@param cmd GP.EditLayerCommand
  undo = function(cmd)
    local layer = backend.get_layer(cmd.force_index, cmd.surface_index, cmd.layer_id)
    if not layer then return false end
    layer.name = cmd.before_name
    backend.notify_layer_changed(cmd.force_index, cmd.surface_index, {
      type = backend.LAYER_CHANGE_TYPE.MODIFIED,
      layer_id = cmd.layer_id,
    })
    return true
  end,
  ---@param cmd GP.EditLayerCommand
  description = function(cmd)
    return ("Rename layer to '%s'"):format(cmd.name)
  end,
}


-- layer-move command
---@class GP.MoveLayerCommand : GP.Command
---@field type "layer-move"
---@field surface_index uint
---@field layer_id uint
---@field before_orders table<uint, uint>
---@field after_orders table<uint, uint>
commands["layer-move"] = {
  ---@param force_index uint
  ---@param player_index uint
  ---@param surface_index uint
  ---@param layer_id uint
  ---@param delta int
  ---@return GP.MoveLayerCommand
  create = function(force_index, player_index, surface_index, layer_id, delta)
    local surf = backend.ensure_surface(force_index, surface_index)
    if not surf.layers[layer_id] then error("Layer does not exist") end
    if delta == 0 then error("No movement") end

    local sorted_layers = sorted(surf.layers, function(a, b) return a.order < b.order end)
    for i, layer in ipairs(sorted_layers) do layer.order = i end

    local before_orders = {}
    for lid, layer in pairs(surf.layers) do before_orders[lid] = layer.order end

    local z = surf.layers[layer_id]
    if delta > 0 then
      z.order = z.order + delta + 0.5
    else
      z.order = z.order + delta - 0.5
    end

    sorted_layers = sorted(sorted_layers, function(a, b) return a.order < b.order end)
    for i, layer in ipairs(sorted_layers) do layer.order = i end

    local after_orders = {}
    for lid, layer in pairs(surf.layers) do after_orders[lid] = layer.order end

    return {
      type = "layer-move",
      force_index = force_index,
      player_index = player_index,
      surface_index = surface_index,
      layer_id = layer_id,
      before_orders = before_orders,
      after_orders = after_orders,
      timestamp = (game and game.tick) or 0,
    }
  end,
  ---@param cmd GP.MoveLayerCommand
  perform = function(cmd)
    local surf = backend.ensure_surface(cmd.force_index, cmd.surface_index)
    for lid, order in pairs(cmd.after_orders) do
      if surf.layers[lid] then surf.layers[lid].order = order end
    end
    backend.notify_layer_changed(cmd.force_index, cmd.surface_index, {
      type = backend.LAYER_CHANGE_TYPE.ORDER_CHANGED,
      layer_id = cmd.layer_id,
    })
    return true
  end,
  ---@param cmd GP.MoveLayerCommand
  undo = function(cmd)
    local surf = backend.ensure_surface(cmd.force_index, cmd.surface_index)
    for lid, order in pairs(cmd.before_orders) do
      if surf.layers[lid] then surf.layers[lid].order = order end
    end
    backend.notify_layer_changed(cmd.force_index, cmd.surface_index, {
      type = backend.LAYER_CHANGE_TYPE.ORDER_CHANGED,
      layer_id = cmd.layer_id,
    })
    return true
  end,
  ---@param cmd GP.MoveLayerCommand
  description = function(cmd)
    local layer = backend.get_layer(cmd.force_index, cmd.surface_index, cmd.layer_id)
    return "Move layer '" .. (layer and layer.name or tostring(cmd.layer_id)) .. "'"
  end,
}


-- layer-visibility command
---@class GP.LayerVisibilityCommand : GP.Command
---@field type "layer-visibility"
---@field surface_index uint
---@field layer_id uint
---@field before_visible boolean
---@field after_visible boolean
commands["layer-visibility"] = {
  ---@param force_index uint
  ---@param player_index uint
  ---@param surface_index uint
  ---@param layer_id uint
  ---@param visible boolean
  ---@return GP.LayerVisibilityCommand
  create = function(force_index, player_index, surface_index, layer_id, visible)
    local layer = backend.get_layer(force_index, surface_index, layer_id)
    if not layer then error("Layer does not exist") end
    return {
      type = "layer-visibility",
      force_index = force_index,
      player_index = player_index,
      surface_index = surface_index,
      layer_id = layer_id,
      before_visible = layer.visible,
      after_visible = visible,
      timestamp = (game and game.tick) or 0,
    }
  end,
  ---@param cmd GP.LayerVisibilityCommand
  perform = function(cmd)
    local layer = backend.get_layer(cmd.force_index, cmd.surface_index, cmd.layer_id)
    if not layer then return false end
    layer.visible = cmd.after_visible
    backend.notify_layer_changed(cmd.force_index, cmd.surface_index, {
      type = backend.LAYER_CHANGE_TYPE.VISIBILITY_CHANGED,
      layer_id = cmd.layer_id,
    })
    return true
  end,
  ---@param cmd GP.LayerVisibilityCommand
  undo = function(cmd)
    local layer = backend.get_layer(cmd.force_index, cmd.surface_index, cmd.layer_id)
    if not layer then return false end
    layer.visible = cmd.before_visible
    backend.notify_layer_changed(cmd.force_index, cmd.surface_index, {
      type = backend.LAYER_CHANGE_TYPE.VISIBILITY_CHANGED,
      layer_id = cmd.layer_id,
    })
    return true
  end,
  ---@param cmd GP.LayerVisibilityCommand
  description = function(cmd)
    return cmd.after_visible and "Show layer" or "Hide layer"
  end,
}

return commands

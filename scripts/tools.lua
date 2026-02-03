-- Tool usage event handlers for Zone Planner

local tools = {}

-- Alt mode erases instead of drawing (zone_id = nil)


local function handle_rect(event, erase)
  if not event or not event.area then return end
  local player_index = event.player_index
  local player = game.get_player(player_index)
  if not player then return end
  local force_index = player.force.index
  local surface_index = event.surface.index
  local zone_id = nil
  if erase ~= true then zone_id = ui.get_selected_zone_id(player_index) end
  backend.fill_rectangle(player_index, force_index, surface_index, zone_id, event.area.left_top, event.area.right_bottom)
end


-- Events table for EventHandler
tools.events = {
  [defines.events.on_player_selected_area] = function(event)
    if event.item == "zone-planner-rectangle-tool" then
      handle_rect(event, false)
    end
  end,
  [defines.events.on_player_alt_selected_area] = function(event)
    if event.item == "zone-planner-rectangle-tool" then
      handle_rect(event, true) -- alt erases
    end
  end,
  [defines.events.on_player_reverse_selected_area] = function(event)
    if event.item == "zone-planner-rectangle-tool" then
      handle_rect(event, true)
    end
  end,
}

return tools

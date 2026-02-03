-- UI module for Zone Planner
-- Builds a mod-gui button and a main panel; toggles visibility on click.

local ui = {}
local backend = require("scripts/backend")

local mod_gui = require("mod-gui")

-- Element names
local TOGGLE_BUTTON_NAME = "zone_planner_toggle_button"
local MAIN_FRAME_NAME = "zone_planner_main_frame"

local function ensure_button(player)
  local flow = mod_gui.get_button_flow(player)
  local btn = flow[TOGGLE_BUTTON_NAME]
  if not btn then
    btn = flow.add{
      type = "button",
      name = TOGGLE_BUTTON_NAME,
      caption = {"zone-planner.mod-name"},
      tooltip = {"zone-planner.mod-name"},
    }
  end
  -- Stretch vertically to fill the toolbar space
  if btn and btn.valid and btn.style then
    btn.style.vertically_stretchable = true
  end
  return btn
end

local function ensure_main_frame(player)
  local frame_flow = mod_gui.get_frame_flow(player)
  local frame = frame_flow[MAIN_FRAME_NAME]
  if not frame then
    frame = frame_flow.add{
      type = "frame",
      name = MAIN_FRAME_NAME,
      caption = {"zone-planner.mod-name"},
      direction = "vertical",
    }
    frame.visible = false
  end
  return frame
end

local function toggle_main_frame(player)
  local frame = ensure_main_frame(player)
  frame.visible = not frame.visible
end

---Return the currently selected zone id for the player (UI state preferred).
---@param player_index uint
---@return uint|nil
function ui.get_selected_zone_id(player_index)
  storage.zp_ui = storage.zp_ui or {}
  local pui = storage.zp_ui.players and storage.zp_ui.players[player_index]
  local id = pui and pui.selected_zone_id
  if id == nil then
    local p = storage.zp and storage.zp.players and storage.zp.players[player_index]
    id = p and p.selected_zone_id or 0
  end
  return id
end

-- Module-local map from button name -> last button element created
local last_dialog_button = {}

-- Create a standard dialog with header (title + close), content, and bottom confirm button.
-- opts: { name, title, confirm_name, cancel_name, parent, content_fn }
local function create_dialog(player, opts)
  local parent = opts.parent or player.gui.screen
  -- destroy any existing
  local existing = parent[opts.name]
  if existing and existing.valid then existing.destroy() end
  -- create frame (no caption)
  local dlg = parent.add{ type = "frame", name = opts.name, direction = "vertical" }
  -- Header: title + spacer + close
  local header = dlg.add{ type = "flow", direction = "horizontal" }
  local title = header.add{ type = "label", caption = opts.title or "" }
  title.style = "frame_title"
  local spacer = header.add{ type = "empty-widget" }
  spacer.style.horizontally_stretchable = true
  header.add{ type = "sprite-button", name = opts.cancel_name, sprite = "utility/close", style = "frame_action_button" }
  -- Content
  if opts.content_fn then opts.content_fn(dlg) end
  -- Bottom confirm row: spacer + confirm (right)
  local buttons = dlg.add{ type = "flow", direction = "horizontal" }
  local spacer2 = buttons.add{ type = "empty-widget" }
  spacer2.style.horizontally_stretchable = true
  buttons.add{ type = "sprite-button", name = opts.confirm_name, sprite = "utility/check_mark", style = "zp_icon_button_green" }
  -- screen dialogs: center and set opened
  if parent == player.gui.screen then
    dlg.auto_center = true
    dlg.force_auto_center()
    player.opened = dlg
  end
  return dlg
end

---@class ZP.UiChange
---@field kind string
---@field force_index uint|nil
---@field surface_index uint|nil
---@field player_index uint|nil
---@field payload table|nil

---Called by backend when data changes; UI can rebuild or update selectively.
---@param change ZP.UiChange
function ui.on_backend_changed(change)
  -- Rebuild all players' UI to reflect changes.
  if storage and storage.zp_ui and storage.zp_ui.is_building then
    -- Skip rebuild while UI is mid-build to avoid invalidating elements.
    return
  end
  if game and game.players then
    for _, p in pairs(game.players) do
      ui.rebuild_player(p.index, change and change.kind or "backend-changed")
    end
  end
end

---Rebuild the UI for a single player.
---@param player_index uint
---@param reason string|nil
function ui.rebuild_player(player_index, reason)
  -- Prevent re-entrant rebuild (e.g., backend default zone init triggering ui.on_backend_changed while building).
  storage.zp_ui = storage.zp_ui or {}
  if storage.zp_ui.is_building then
    return
  end
  storage.zp_ui.is_building = true
  local player = game.get_player(player_index)
  if not player then storage.zp_ui.is_building = false; return end
  ensure_button(player)
  local frame = ensure_main_frame(player)
  -- Rebuild panel contents while preserving visibility state
  local was_visible = frame.visible
  frame.clear()

  -- Top row: Properties, Undo, Redo
  local top = frame.add{ type = "flow", direction = "horizontal" }
  local btn_props = top.add{ type = "button", name = "zp_properties_open", caption = "Properties" }
  last_dialog_button["zp_properties_open"] = btn_props
    local btn_undo = top.add{ type = "sprite-button", name = "zp_undo", sprite = "zp_undo_icon", style = "zp_icon_button" }
    local btn_redo = top.add{ type = "sprite-button", name = "zp_redo", sprite = "zp_redo_icon", style = "zp_icon_button" }
  -- Tooltips from last actions
  btn_undo.enabled = backend.can_undo(player_index)
  btn_redo.enabled = backend.can_redo(player_index)
  btn_undo.tooltip = backend.peek_undo_description(player_index) and ("Undo: " .. backend.peek_undo_description(player_index)) or "Undo: None"
  btn_redo.tooltip = backend.peek_redo_description(player_index) and ("Redo: " .. backend.peek_redo_description(player_index)) or "Redo: None"

  -- Tools row: Rectangle
  local tools = frame.add{ type = "flow", direction = "horizontal" }
  tools.add{ type = "button", name = "zp_tool_rect", caption = "Rectangle" }

  -- Zones table in a scroll-pane
  local zones_header = frame.add{ type = "flow", direction = "horizontal" }
  local header = zones_header.add{ type = "label", caption = "Zones" }
  header.style = "frame_title"

  local scroll = frame.add{ type = "scroll-pane", name = "zp_zones_scroll", horizontal_scroll_policy = "never", vertical_scroll_policy = "auto"}
  scroll.style.minimal_height = 100
  scroll.style.maximal_height = 600
  scroll.style.horizontally_stretchable = true
  -- scroll.style.vertically_stretchable = true
  local list = scroll.add{ type = "table", name = "zp_zones_table", column_count = 6 }
  if list and list.valid and list.style then
    list.style.minimal_width = 300
  end
  if not list or not list.valid then
    storage.zp_ui.is_building = false
    return
  end
  local force_index = player.force.index
  local f = backend.get_force(force_index)
  local selected_id = (storage and storage.zp_ui and storage.zp_ui.players and storage.zp_ui.players[player_index] and storage.zp_ui.players[player_index].selected_zone_id) or 0

  -- Helper to render a single zone row
  local function add_zone_row(id, name, color, editable)
    local select_name = "zp_zone_radio_" .. tostring(id)
    local edit_name = "zp_zone_edit_" .. tostring(id)
    local delete_name = "zp_zone_delete_" .. tostring(id)
    -- Column 1: radio selection
    list.add{ type = "radiobutton", name = select_name, state = (selected_id == id), caption = "" }
    -- Column 2: name
    local name_lbl = list.add{ type = "label", caption = name }
    name_lbl.style = "bold_label"
    name_lbl.style.horizontally_stretchable = true
    if selected_id == id then
      name_lbl.style.font_color = { r = 1, g = 0.75, b = 0.25 }
    end
    if editable then
      -- Column 3: edit name (pencil)
      local name_btn = list.add{ type = "sprite-button", name = ("zp_zone_name_%s"):format(id), sprite = "utility/rename_icon", style = "zp_icon_button" }
      last_dialog_button[name_btn.name] = name_btn
      -- Column 4: color patch
      local patch = list.add{ type = "label", caption = "■" }
      patch.style = "zp_color_patch_label"
      patch.style.font_color = { r = color.r or 1, g = color.g or 1, b = color.b or 1 }
      -- Column 5: color edit (pipette)
      local color_btn = list.add{ type = "sprite-button", name = ("zp_zone_color_%s"):format(id), sprite = "utility/color_picker", style = "zp_icon_button" }
      last_dialog_button[color_btn.name] = color_btn
      -- Column 6: delete sprite-button (red)
      local btn_delete = list.add{ type = "sprite-button", name = delete_name, sprite = "utility/trash", style = "zp_icon_button_red" }
      btn_delete.enabled = true
    else
      -- Fill cells to keep table alignment (columns 3-6)
      list.add{ type = "empty-widget" }
      list.add{ type = "empty-widget" }
      list.add{ type = "empty-widget" }
      list.add{ type = "empty-widget" }
    end
  end

  -- Empty zone special
  add_zone_row(0, "(Empty)", {r=0,g=0,b=0,a=0}, false)
  -- Other zones
  if f and f.zones then
    for id, z in pairs(f.zones) do
      if id ~= 0 then
        add_zone_row(id, z.name, z.color or {r=1,g=1,b=1,a=1}, true)
      end
    end
  end

  -- Add Zone button below table, full-width
  local add_flow = frame.add{ type = "flow", direction = "horizontal" }
  local add_btn = add_flow.add{ type = "button", name = "zp_zone_add", caption = "Add Zone" }
  add_btn.style.horizontally_stretchable = true
  last_dialog_button["zp_zone_add"] = add_btn

  frame.visible = was_visible
  storage.zp_ui.is_building = false
end

-- Event handlers
ui.events = {}

---Build UI for all current players on init.
function ui.on_init(event)
  for _, p in pairs(game.players) do
    ui.rebuild_player(p.index, "init")
  end
end

---Create per-player UI on player creation.
function ui.events.on_player_created(event)
  ui.rebuild_player(event.player_index, "player-created")
end

---Handle button clicks to toggle the main frame.
function ui.events.on_gui_click(event)
  local element = event.element
  if not element or not element.valid then return end
  if element.name == TOGGLE_BUTTON_NAME then
    local player = game.get_player(event.player_index)
    if player then
      toggle_main_frame(player)
    end
    return
  end

  local player = game.get_player(event.player_index)
  if not player then return end

  -- Properties open
  if element.name == "zp_properties_open" then
    local frame = ensure_main_frame(player)
    local g = backend.get_grid(player.force.index)
    create_dialog(player, {
      name = "zp_properties_dialog",
      title = "Properties",
      confirm_name = "zp_prop_confirm",
      cancel_name = "zp_prop_cancel",
      parent = frame,
      content_fn = function(dlg)
        local flow1 = dlg.add{ type = "flow", direction = "horizontal" }
        flow1.add{ type = "label", caption = "Width" }
        flow1.add{ type = "textfield", name = "zp_prop_width", text = tostring(g.width or 32) }
        local flow2 = dlg.add{ type = "flow", direction = "horizontal" }
        flow2.add{ type = "label", caption = "Height" }
        flow2.add{ type = "textfield", name = "zp_prop_height", text = tostring(g.height or 32) }
        local flow3 = dlg.add{ type = "flow", direction = "horizontal" }
        flow3.add{ type = "label", caption = "X offset" }
        flow3.add{ type = "textfield", name = "zp_prop_x_offset", text = tostring(g.x_offset or 0) }
        local flow4 = dlg.add{ type = "flow", direction = "horizontal" }
        flow4.add{ type = "label", caption = "Y offset" }
        flow4.add{ type = "textfield", name = "zp_prop_y_offset", text = tostring(g.y_offset or 0) }
        dlg.add{ type = "checkbox", name = "zp_prop_reproject", state = false, caption = "Reproject existing cells" }
      end
    })
    return
  end

  -- Properties confirm/cancel
  if element.name == "zp_prop_cancel" then
    local frame = ensure_main_frame(player)
    local dlg = frame["zp_properties_dialog"]
    if dlg and dlg.valid then dlg.destroy() end
    return
  elseif element.name == "zp_prop_confirm" then
    local frame = ensure_main_frame(player)
    local dlg = frame["zp_properties_dialog"]
    if not dlg or not dlg.valid then return end
    local g = backend.get_grid(player.force.index)
    local function get_text(name)
      local e = dlg[name]
      return e and e.text or ""
    end
    local function to_number(s, default)
      local n = tonumber(s)
      if not n then return default end
      return n
    end
    local new_props = {
      width = to_number(get_text("zp_prop_width"), g.width or 32),
      height = to_number(get_text("zp_prop_height"), g.height or 32),
      x_offset = to_number(get_text("zp_prop_x_offset"), g.x_offset or 0),
      y_offset = to_number(get_text("zp_prop_y_offset"), g.y_offset or 0),
    }
    local reproject = (dlg["zp_prop_reproject"] and dlg["zp_prop_reproject"].state) or false
    backend.set_grid(player.force.index, new_props, { reproject = reproject })
    dlg.destroy()
    return
  end

  -- Undo/Redo
  if element.name == "zp_undo" then
    backend.undo(player.index)
    ui.rebuild_player(player.index, "undo")
    return
  elseif element.name == "zp_redo" then
    backend.redo(player.index)
    ui.rebuild_player(player.index, "redo")
    return
  end

  -- Tool selection
  if element.name == "zp_tool_rect" then
    local ok = player.clear_cursor()
    if not ok then
      player.create_local_flying_text{ text = "Clear your cursor first", create_at_cursor = true, color = {r=1,g=0.3,b=0} }
      return
    end
  local tool_name = "zone-planner-rectangle-tool"
    if player.cursor_stack and player.cursor_stack.valid_for_read then
      -- If still something in cursor, abort
      player.create_local_flying_text{ text = "Unable to set tool in cursor", create_at_cursor = true, color = {r=1,g=0.3,b=0} }
      return
    end
    if player.cursor_stack then
      player.cursor_stack.set_stack({ name = tool_name, count = 1 })
      -- Track selection in per-player UI state
      storage.zp_ui = storage.zp_ui or {}
      storage.zp_ui.players = storage.zp_ui.players or {}
      local pstate = storage.zp_ui.players[player.index] or {}
  pstate.selected_tool = "rect"
      storage.zp_ui.players[player.index] = pstate
    end
    return
  end

  -- Zone operations (radio selection handled in on_gui_checked_state_changed)

  -- Name edit dialog
  local name_id = element.name:match("^zp_zone_name_(%d+)$")
  if name_id then
    local id = tonumber(name_id)
    if not id then return end
    local screen = player.gui.screen
    local f = backend.get_force(player.force.index)
    local z = f.zones[id]
    local dlg = create_dialog(player, {
      name = "zp_zone_name_dialog",
      title = "Edit Zone Name",
      confirm_name = "zp_name_confirm",
      cancel_name = "zp_name_cancel",
      parent = screen,
      content_fn = function(dlg)
        dlg.tags = { zone_id = id }
        local flowN = dlg.add{ type = "flow", direction = "horizontal" }
        flowN.add{ type = "label", caption = "Name" }
        flowN.add{ type = "textfield", name = "zp_zone_name_field", text = z and z.name or "" }
      end
    })
    return
  end

  -- Color edit dialog
  local color_id = element.name:match("^zp_zone_color_(%d+)$")
  if color_id then
    local id = tonumber(color_id)
    if not id then return end
    local screen = player.gui.screen
    local f = backend.get_force(player.force.index)
    local z = f.zones[id]
    create_dialog(player, {
      name = "zp_zone_color_dialog",
      title = "Edit Zone Color",
      confirm_name = "zp_color_confirm",
      cancel_name = "zp_color_cancel",
      parent = screen,
      content_fn = function(dlg)
        dlg.tags = { zone_id = id }
        local function add_color_slider(label, name, value)
          local fl = dlg.add{ type = "flow", direction = "horizontal" }
          fl.add{ type = "label", caption = label }
          fl.add{ type = "slider", name = name, minimum_value = 0, maximum_value = 255, value = value }
        end
        local col = z and z.color or {r=1,g=1,b=1,a=1}
        add_color_slider("Red", "zp_color_r", math.floor((col.r or 1) * 255))
        add_color_slider("Green", "zp_color_g", math.floor((col.g or 1) * 255))
        add_color_slider("Blue", "zp_color_b", math.floor((col.b or 1) * 255))
  local preview = dlg.add{ type = "label", name = "zp_color_preview", caption = "■" }
  preview.style = "zp_color_patch_label"
  ---@type any
  local ps = preview.style
  ps.font_color = { r = col.r or 1, g = col.g or 1, b = col.b or 1 }
      end
    })
    return
  end

  if element.name == "zp_zone_add" then
    local frame = ensure_main_frame(player)
    create_dialog(player, {
      name = "zp_zone_dialog",
      title = "Add Zone",
      confirm_name = "zp_zone_confirm",
      cancel_name = "zp_zone_cancel",
      parent = frame,
      content_fn = function(dlg)
        dlg.tags = { mode = "add" }
        local flowN = dlg.add{ type = "flow", direction = "horizontal" }
        flowN.add{ type = "label", caption = "Name" }
        flowN.add{ type = "textfield", name = "zp_zone_name", text = "" }
        local function add_color_slider(label, name, value)
          local fl = dlg.add{ type = "flow", direction = "horizontal" }
          fl.add{ type = "label", caption = label }
          fl.add{ type = "slider", name = name, minimum_value = 0, maximum_value = 255, value = value }
        end
        add_color_slider("Red", "zp_zone_r", 255)
        add_color_slider("Green", "zp_zone_g", 255)
        add_color_slider("Blue", "zp_zone_b", 255)
  local preview = dlg.add{ type = "label", name = "zp_zone_preview", caption = "■" }
  preview.style = "zp_color_patch_label"
  ---@type any
  local ps = preview.style
  ps.font_color = { r = 1, g = 1, b = 1 }
      end
    })
    return
  end

  -- Zone dialog confirm/cancel
  if element.name == "zp_zone_cancel" or element.name == "zp_zone_confirm" then
    local frame = ensure_main_frame(player)
    local dlg = frame["zp_zone_dialog"]
    if not dlg or not dlg.valid then return end
    if element.name == "zp_zone_cancel" then
      dlg.destroy(); return
    end
    -- confirm add
    local name = dlg["zp_zone_name"].text
    local r = (dlg["zp_zone_r"] and dlg["zp_zone_r"].slider_value) or 255
    local g = (dlg["zp_zone_g"] and dlg["zp_zone_g"].slider_value) or 255
    local b = (dlg["zp_zone_b"] and dlg["zp_zone_b"].slider_value) or 255
    local color = { r = r/255, g = g/255, b = b/255, a = 1 }
    backend.add_zone(player.force.index, name, color)
    dlg.destroy()
    ui.rebuild_player(player.index, "zone-added")
    return
  end
  if element.name == "zp_name_cancel" or element.name == "zp_name_confirm" then
    local screen = player.gui.screen
    local dlg = screen["zp_zone_name_dialog"]
    if not dlg or not dlg.valid then return end
    if element.name == "zp_name_cancel" then
      dlg.destroy(); player.opened = nil; return
    end
    local zone_id = dlg.tags and tonumber(dlg.tags.zone_id)
    if not zone_id then dlg.destroy(); player.opened = nil; return end
    local f = backend.get_force(player.force.index)
    local z = f.zones[zone_id]
    local new_name = (dlg["zp_zone_name_field"] and dlg["zp_zone_name_field"].text) or (z and z.name) or ""
    local col = z and z.color or {r=1,g=1,b=1,a=1}
    backend.edit_zone(player.force.index, zone_id, new_name, col)
    dlg.destroy(); player.opened = nil
    ui.rebuild_player(player.index, "zone-name-updated")
    return
  end

  if element.name == "zp_color_cancel" or element.name == "zp_color_confirm" then
    local screen = player.gui.screen
    local dlg = screen["zp_zone_color_dialog"]
    if not dlg or not dlg.valid then return end
    if element.name == "zp_color_cancel" then
      dlg.destroy(); player.opened = nil; return
    end
    local zone_id = dlg.tags and tonumber(dlg.tags.zone_id)
    if not zone_id then dlg.destroy(); player.opened = nil; return end
    local f = backend.get_force(player.force.index)
    local z = f.zones[zone_id]
    local r = (dlg["zp_color_r"] and dlg["zp_color_r"].slider_value) or 255
    local g = (dlg["zp_color_g"] and dlg["zp_color_g"].slider_value) or 255
    local b = (dlg["zp_color_b"] and dlg["zp_color_b"].slider_value) or 255
    local color = { r = r/255, g = g/255, b = b/255, a = (z and z.color and z.color.a) or 1 }
    local name = z and z.name or ""
    backend.edit_zone(player.force.index, zone_id, name, color)
    dlg.destroy(); player.opened = nil
    ui.rebuild_player(player.index, "zone-color-updated")
    return
  end

  -- Zone delete
  local delete_id = element.name:match("^zp_zone_delete_(%d+)$")
  if delete_id then
    local id = tonumber(delete_id)
    if not id then return end
    -- For now, delete to Empty (eraser) semantics
    backend.delete_zone(player.force.index, id, 0)
    ui.rebuild_player(player.index, "zone-delete")
    return
  end
end

-- Update color preview when sliders change
function ui.events.on_gui_value_changed(event)
  local element = event.element
  if not element or not element.valid then return end
  local player = game.get_player(event.player_index)
  if not player then return end
  if element.name == "zp_color_r" or element.name == "zp_color_g" or element.name == "zp_color_b" then
    local screen = player.gui.screen
    local dlg = screen["zp_zone_color_dialog"]
    if not dlg or not dlg.valid then return end
    local r = dlg["zp_color_r"] and dlg["zp_color_r"].slider_value or 255
    local g = dlg["zp_color_g"] and dlg["zp_color_g"].slider_value or 255
    local b = dlg["zp_color_b"] and dlg["zp_color_b"].slider_value or 255
    local preview = dlg["zp_color_preview"]
    if preview then
      preview.style.font_color = { r = r/255, g = g/255, b = b/255 }
    end
    return
  end
  -- Add Zone dialog sliders
  if element.name == "zp_zone_r" or element.name == "zp_zone_g" or element.name == "zp_zone_b" then
    local frame = ensure_main_frame(player)
    local dlg = frame["zp_zone_dialog"]
    if not dlg or not dlg.valid then return end
    local r = dlg["zp_zone_r"] and dlg["zp_zone_r"].slider_value or 255
    local g = dlg["zp_zone_g"] and dlg["zp_zone_g"].slider_value or 255
    local b = dlg["zp_zone_b"] and dlg["zp_zone_b"].slider_value or 255
    local preview = dlg["zp_zone_preview"]
    if preview then
      preview.style.font_color = { r = r/255, g = g/255, b = b/255 }
    end
  end
end

-- Radio selection for zone rows
function ui.events.on_gui_checked_state_changed(event)
  local element = event.element
  if not element or not element.valid then return end
  local player = game.get_player(event.player_index)
  if not player then return end
  local id_str = element.name and element.name:match("^zp_zone_radio_(%d+)$")
  if not id_str then return end
  if not element.state then return end -- only act when checked on
  local id = tonumber(id_str)
  if not id then return end
  storage.zp_ui = storage.zp_ui or {}
  storage.zp_ui.players = storage.zp_ui.players or {}
  local pstate = storage.zp_ui.players[player.index] or {}
  pstate.selected_zone_id = id
  storage.zp_ui.players[player.index] = pstate
  ui.rebuild_player(player.index, "zone-radio-select")
end

-- Confirm/cancel for zone dialog
function ui.events.on_gui_confirmed(event)
  -- Not used; we use click on confirm
end

-- (No second handler; on_gui_click already defined above)

return ui

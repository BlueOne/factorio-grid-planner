-- UI module for Zone Planner

local ui = {}
local backend = require("scripts/backend")
local flib_gui = require("__flib__.gui")
local dialog = require("scripts/dialog")

local mod_gui = require("mod-gui")

---@class ZP.UiState
---@field is_building boolean

-- Element names
local TOGGLE_BUTTON_NAME = "zone_planner_toggle_button"
local MAIN_FRAME_NAME = "zone_planner_main_frame"

local function ensure_main_frame(player)
  local frame_flow = mod_gui.get_frame_flow(player)
  local frame = frame_flow[MAIN_FRAME_NAME]
  if not frame then
    frame = frame_flow.add{
      type = "frame",
      name = MAIN_FRAME_NAME,
      direction = "vertical",
    }
    frame.visible = false
  end
  return frame
end


---Return the currently selected zone id for the player (from backend).
---@param player_index uint
---@return uint|nil
function ui.get_selected_zone_id(player_index)
  return backend.get_selected_zone_id(player_index)
end

-- Helper: build color picker (sliders + preview) for dialog
---@param r number Normalized red (0-1)
---@param g number Normalized green (0-1)
---@param b number Normalized blue (0-1)
---@param handler function Event handler for slider changes
---@return table Flow definition containing the sliders and preview
local function build_color_picker(r, g, b, handler)
  -- Helper: create a color slider row
  local function color_slider_row(label, name, value)
    return {
      type = "flow", direction = "horizontal",
      style_mods = { horizontally_stretchable = true },
      children = {
        { type = "label", caption = label, style_mods = { minimal_width = 50 } },
        { type = "slider", name = name, minimum_value = 0, maximum_value = 255, value = math.floor(value * 255), handler = handler, style_mods = { horizontally_stretchable = true, minimal_width = 120 } }
      }
    }
  end
  
  return {
    type = "flow",
    direction = "vertical",
    name = "zp_color_picker",
    style_mods = { horizontally_stretchable = true, top_padding = 4, vertical_spacing = 6 },
    children = {
      {
        type = "flow",
        direction = "vertical",
        name = "zp_color_sliders",
        style_mods = { horizontally_stretchable = true, vertical_spacing = 2 },
        children = {
          color_slider_row("Red", "zp_color_r", r or 1),
          color_slider_row("Green", "zp_color_g", g or 1),
          color_slider_row("Blue", "zp_color_b", b or 1),
        }
      },
      {
        type = "progressbar",
        name = "zp_color_preview",
        value = 1,
        style_mods = {
          color = { r = r or 1, g = g or 1, b = b or 1 },
          horizontally_stretchable = true,
        }
      }
    }
  }
end

-- Helper: find a named child anywhere under a parent
---@param parent LuaGuiElement
---@param name string
---@return LuaGuiElement|nil
local function find_child(parent, name)
  if not parent or not parent.valid then return nil end
  local direct = parent[name]
  if direct and direct.valid then return direct end
  if parent.children and #parent.children > 0 then
    for _, child in pairs(parent.children) do
      if child and child.valid then
        if child.name == name then return child end
        local found = find_child(child, name)
        if found then return found end
      end
    end
  end
  return nil
end

-- Helper: create a labeled textfield row for dialogs
---@param label string Label text
---@param name string Element name
---@param value number|string Initial value
---@return table Flow definition
local function labeled_textfield(label, name, value)
  return {
    type = "flow", direction = "horizontal",
    children = {
      { type = "label", caption = label },
      { type = "empty-widget", style_mods = { minimal_width = 8, horizontally_stretchable = true } },
      { type = "textfield", name = name, text = tostring(value), style_mods = { width = 100} }
    }
  }
end

-- Helper: visibility caption for level 0..3
---@param idx number
---@return string
local function visibility_caption(idx)
  local n = tonumber(idx) or 0
  if n <= 0 then
    return "Visibility: Off"
  end
  return ("Visibility: %d"):format(n)
end

-- Helper: update visibility label caption in dialog
---@param dlg LuaGuiElement
---@param idx number
local function update_visibility_label(dlg, idx)
  local label = find_child(dlg, "zp_visibility_level_label")
  if label and label.valid then
    label.caption = visibility_caption(idx)
  end
end

-- Helper: update color preview progressbar from current slider values
---@param dlg LuaGuiElement Dialog frame
---@param preview_name string Element name of color preview progressbar
---@param r_name string Element name of red slider
---@param g_name string Element name of green slider
---@param b_name string Element name of blue slider
local function update_color_preview(dlg, preview_name, r_name, g_name, b_name)
  local r_elem = find_child(dlg, r_name)
  local g_elem = find_child(dlg, g_name)
  local b_elem = find_child(dlg, b_name)
  local r = r_elem and r_elem.slider_value or 255
  local g = g_elem and g_elem.slider_value or 255
  local b = b_elem and b_elem.slider_value or 255
  local preview = find_child(dlg, preview_name)
  if preview and preview.valid then
    preview.style.color = { r = r/255, g = g/255, b = b/255 }
  end
end

-- UI event handlers
local handlers = {}

-- Pipette handler: select zone under cursor if any
function handlers.pipette(e)
  if e.in_gui then return end
  local player = game.get_player(e.player_index)
  if not player or not player.valid then return end
  local pos = e.cursor_position
  if not pos then return end
  local force_index = player.force.index
  local surface_index = player.surface.index
  local img = backend.get_surface_image(force_index, surface_index)
  local cx, cy = backend.tile_to_cell(force_index, pos.x, pos.y)
  local zone_id = backend.get_from_image(img, cx, cy)
  if zone_id and zone_id ~= 0 then
    backend.set_selected_zone_id(player.index, zone_id)
    ui.rebuild_player(player.index, "pipette")
  end
end

-- Register dialogs with their handlers
dialog.register("zp_properties_dialog", {
  on_confirm = function(dlg, player)
    local g = backend.get_grid(player.force.index)
    local size_elem = find_child(dlg, "zp_prop_size")
    local x_offset_elem = find_child(dlg, "zp_prop_x_offset")
    local y_offset_elem = find_child(dlg, "zp_prop_y_offset")
    local size = tonumber(size_elem and size_elem.text) or g.width or g.height or 32
    local reproject_elem = find_child(dlg, "zp_prop_reproject")
    local new_props = {
      width = size,
      height = size,
      x_offset = tonumber(x_offset_elem and x_offset_elem.text) or g.x_offset or 0,
      y_offset = tonumber(y_offset_elem and y_offset_elem.text) or g.y_offset or 0,
    }
    local reproject = (reproject_elem and reproject_elem.state) or false
    backend.set_grid(player.force.index, player.index, new_props, { reproject = reproject })
  end
})

dialog.register("zp_visibility_dialog", {
  on_confirm = function(dlg, player)
    local idx = dlg.tags and tonumber(dlg.tags.visibility_index)
    backend.set_player_visibility(player.index, { index = idx })
  end
})

dialog.register("zp_zone_dialog", {
  on_confirm = function(dlg, player)
    local name_elem = find_child(dlg, "zp_zone_name")
    local name = name_elem and name_elem.text or ""
    local tags = dlg.tags or {}
    local r = tags.color_r or 255
    local g = tags.color_g or 255
    local b = tags.color_b or 255
    local color = { r = r/255, g = g/255, b = b/255, a = 1 }
    
    local zone_id = tonumber(tags.zone_id)
    if zone_id then
      backend.edit_zone(player.force.index, player.index, zone_id, name, color)
    else
      backend.add_zone(player.force.index, player.index, name, color)
    end
  end
})

---@class ZP.UiChange
---@field kind string Change kind (e.g. "backend-changed", "player-created", "init")
---@field force_index uint|nil
---@field surface_index uint|nil
---@field player_index uint|nil
---@field payload table|nil Additional change data

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
---@param reason string|nil Reason for rebuild ("backend-changed", "init", "player-created", etc.)
function ui.rebuild_player(player_index, reason)
  -- Prevent re-entrant rebuild (e.g., backend default zone init triggering ui.on_backend_changed while building).
  storage.zp_ui = storage.zp_ui or {}
  if storage.zp_ui.is_building then
    return
  end
  storage.zp_ui.is_building = true
  local player = game.get_player(player_index)
  if not player then storage.zp_ui.is_building = false; return end
  local frame = ensure_main_frame(player)
  -- Rebuild panel contents while preserving visibility state
  local was_visible = frame.visible
  frame.clear()

  -- Create toggle button in mod-gui button flow
  local button_flow = mod_gui.get_button_flow(player)
  local existing_btn = button_flow[TOGGLE_BUTTON_NAME]
  if not existing_btn then
    flib_gui.add(button_flow, {
      type = "sprite-button",
      name = TOGGLE_BUTTON_NAME,
      sprite = "zp-mod-icon",
      style = "mod_gui_button",
      tooltip = {"zone-planner.mod-name"},
      handler = handlers.toggle_main_frame,
      style_mods = { vertically_stretchable = true }
    })
  end

  -- Custom header: title + spacer + Properties, Undo, Redo buttons
  flib_gui.add(frame, {
    type = "flow",
    direction = "horizontal",
    style_mods = { horizontal_spacing = 8 },
    children = {
      { type = "label", caption = {"zone-planner.mod-name"}, style = "frame_title", style_mods = { top_padding = -3 }},
      { type = "empty-widget", style_mods = { horizontally_stretchable = true, height = 24 }, style = "draggable_space" },
      { 
        type = "sprite-button", 
        name = "zp_undo", 
        sprite = "zp-undo-icon-light", 
        style = "frame_action_button",
        handler = handlers.undo,
        elem_mods = {
          enabled = backend.can_undo(player_index),
          tooltip = {"tooltips.tooltip-undo", backend.peek_undo_description(player_index) or "None"}
        }
      },
      { 
        type = "sprite-button",
        name = "zp_redo",
        sprite = "zp-redo-icon-light",
        style = "frame_action_button",
        handler = handlers.redo,
        elem_mods = {
          enabled = backend.can_redo(player_index),
          tooltip = {"tooltips.tooltip-redo", backend.peek_redo_description(player_index) or "None"}
        }
      },
      {
        type = "sprite-button",
        name = "zp_visibility_open",
        sprite = "zp-visibility-light-16",
        style = "frame_action_button",
        handler = handlers.visibility_open,
        tooltip = "Visibility settings"
      },
      {
        type = "sprite-button",
        name = "zp_properties_open",
        sprite = "zp-edit-light-16",
        style = "frame_action_button",
        handler = handlers.properties_open,
        tooltip = "Grid properties"
      },
      {
        type = "sprite-button",
        name = "zp_close_main_frame",
        sprite = "utility/close",
        style = "frame_action_button",
        handler = handlers.close_main_frame,
        tooltip = "Close panel"
      },
    }
  })

  -- Tools row: Rectangle
  flib_gui.add(frame, {
    type = "flow",
    direction = "horizontal",
    children = {
      {
        type = "sprite-button",
        name = "zp_tool_rect",
        sprite = "utility/brush_square_shape",
        style = "tool_button",
        handler = handlers.select_tool_rect,
        tooltip = {"tooltips.tooltip-rect"}
      },
      {
        type = "sprite-button",
        name = "zp_tool_pipette",
        sprite = "utility/color_picker",
        style = "tool_button",
        handler = handlers.pipette,
        enabled = false,
        tooltip = {"tooltips.tooltip-pipette"}
      }
    }
  })

  -- Zones list
  flib_gui.add(frame, {
    type = "label",
    caption = "Zones",
    style = "frame_title",
  })

  local _, scroll = flib_gui.add(frame, {
    type = "scroll-pane",
    name = "zp_zones_scroll",
    style = "flib_naked_scroll_pane",
    horizontal_scroll_policy = "never",
    vertical_scroll_policy = "auto",
    style_mods = {
      minimal_height = 100,
      maximal_height = 600,
      horizontally_stretchable = true,
      padding = 4,
    }
  })
  
  local _, frame_list = flib_gui.add(scroll, {
    type = "frame",
    name = "zp_zones_frame",
    direction = "vertical",
    style = "inside_deep_frame",
    style_mods = { minimal_width = 300, padding = 8 }
  })

  local _, list = flib_gui.add(frame_list, {
    type = "flow",
    name = "zp_zones_flow",
    direction = "vertical",
    style_mods = { vertical_spacing = 0 }
  })
  
  if not list or not list.valid then
    storage.zp_ui.is_building = false
    return
  end
  local force_index = player.force.index
  local f = backend.get_force(force_index)
  local selected_id = backend.get_selected_zone_id(player_index) or 0

  -- Ensure a valid selection if any zones exist
  if selected_id == 0 or not (f and f.zones and f.zones[selected_id]) then
    local first_id = nil
    if f and f.zones then
      for id, _ in pairs(f.zones) do
        if id ~= 0 and (not first_id or id < first_id) then
          first_id = id
        end
      end
    end
    if first_id then
      backend.set_selected_zone_id(player_index, first_id)
      selected_id = first_id
    end
  end

  -- Helper to render a single zone row
  local function add_zone_row(id, name, color, is_first, is_last)
    local select_name = "zp_zone_select_" .. tostring(id)
    local delete_name = "zp_zone_delete_" .. tostring(id)
    -- Row: selectable button
    local name_style_mods = { horizontally_stretchable = true, minimal_width = 250 }
    if selected_id == id then
      name_style_mods.selected_font_color = { r = 0, g = 0, b = 0 }
    end
    flib_gui.add(list, {
      type = "flow",
      direction = "horizontal",
      children = {
        {
          type = "button",
          name = select_name,
          style = "zp_zone_row_button",
          style_mods = name_style_mods,
          toggled = selected_id == id,
          handler = handlers.zone_row_select,
          tags = { zone_id = id },
          children = {
            {
              type = "flow",
              direction = "horizontal",
              style_mods = { horizontal_spacing = 4, vertically_stretchable = false, vertical_align = "center" },
              children = {
                {
                  type = "label",
                  caption = "■",
                  style = "zp_color_patch_label",
                  style_mods = { font_color = { r = color.r or 1, g = color.g or 1, b = color.b or 1 } }
                },
                {
                  type = "label",
                  caption = name or ("Zone " .. tostring(id)),
                  style = "zp_heading_label",
                  style_mods = { single_line = true },
                },
              }
            }
          },
        },
        {
          type = "frame",
          style = "zp_zone_row_frame",
          children = {
            {
              type = "flow",
              direction = "horizontal",
              
              style_mods = { horizontal_spacing = 4 },
              children = {
                {
                  type = "sprite-button",
                  name = ("zp_zone_up_%s"):format(id),
                  sprite = "zp-up-dark-32",
                  style = "zp_icon_button",
                  tooltip = "Move up. Shift: Move up 5, Control: 50.",
                  handler = handlers.zone_move_up,
                  tags = { zone_id = id },
                  elem_mods = { enabled = not is_first }
                },
                {
                  type = "sprite-button",
                  name = ("zp_zone_down_%s"):format(id),
                  sprite = "zp-down-dark-32",
                  tooltip = "Move down. Shift: Move down 5, Control: 50.",
                  style = "zp_icon_button",
                  handler = handlers.zone_move_down,
                  tags = { zone_id = id },
                  elem_mods = { enabled = not is_last }
                },
                {
                  type = "sprite-button",
                  name = ("zp_zone_name_%s"):format(id),
                  sprite = "zp-edit-dark-32",
                  style = "zp_icon_button",
                  handler = handlers.zone_edit_open,
                  tags = { zone_id = id },
                  tooltip = "Edit zone"
                },
                {
                  type = "sprite-button",
                  name = delete_name,
                  sprite = "utility/trash",
                  style = "zp_icon_button_red",
                  handler = handlers.zone_delete,
                  elem_mods = { enabled = true },
                  tags = { zone_id = id },
                  tooltip = "Delete zone"
                }
              }
            }
          }
        }
      },
    })
  end

  -- Zones
  if f and f.zones then
    -- Collect and sort non-empty zones by order
    local zones_list = {}
    for id, z in pairs(f.zones) do
      if id ~= 0 then
        table.insert(zones_list, { id = id, zone = z })
      end
    end
    table.sort(zones_list, function(a, b) return a.zone.order < b.zone.order end)
    
    for idx, entry in ipairs(zones_list) do
      local id = entry.id
      local z = entry.zone
      local is_first = (idx == 1)
      local is_last = (idx == #zones_list)
      add_zone_row(id, z.name, z.color or {r=1,g=1,b=1,a=1}, is_first, is_last)
    end
  end

  -- Add Zone button below table, full-width
  flib_gui.add(list, {
    type = "frame",
    name = "zp_zone_add_outer",
    style = "zp_zone_row_frame",
    style_mods = { horizontally_stretchable = true },
    children = {
      {
        type = "button",
        name = "zp_zone_add",
        caption = "Add Zone",
        handler = handlers.zone_add,
        style_mods = { horizontally_stretchable = true, vertically_stretchable = true }
      }
    }
  })

  frame.visible = was_visible
  storage.zp_ui.is_building = false
end


-- Handler function implementations
function handlers.toggle_main_frame(e)
  local player = game.get_player(e.player_index)
  if player then
    local frame = ensure_main_frame(player)
    frame.visible = not frame.visible
    -- Enable alt mode when opening UI
    if frame.visible then
      player.game_view_settings.show_entity_info = true
    end
  end
end

function handlers.properties_open(e)
  local player = game.get_player(e.player_index)
  if not player then return end
  local g = backend.get_grid(player.force.index)
  dialog.create(player, {
    name = "zp_properties_dialog",
    title = "Properties",
    location = e.cursor_display_location,
    children = {
      labeled_textfield("Size", "zp_prop_size", g.width or g.height or 32),
      labeled_textfield("X offset", "zp_prop_x_offset", g.x_offset or 0),
      labeled_textfield("Y offset", "zp_prop_y_offset", g.y_offset or 0),
      { type = "checkbox", name = "zp_prop_reproject", state = true, caption = "Reproject existing cells" }
    }
  })
end

function handlers.visibility_open(e)
  local player = game.get_player(e.player_index)
  if not player then return end
  local idx = backend.get_boundary_opacity_index and backend.get_boundary_opacity_index(player.index) or 0
  local dlg = dialog.create(player, {
    name = "zp_visibility_dialog",
    title = "Visibility",
    location = e.cursor_display_location,
    children = {
      {
        type = "flow",
        direction = "horizontal",
        style_mods = { horizontal_spacing = 8, vertical_align = "center" },
        children = {
          {
            type = "sprite-button",
            name = "zp_visibility_lower",
            sprite = "utility/backward_arrow",
            style = "zp_icon_button",
            handler = handlers.visibility_lower,
            tooltip = {"tooltips.tooltip-visibility-decrease"}
          },
          {
            type = "label",
            name = "zp_visibility_level_label",
            caption = visibility_caption(idx),
            style_mods = { minimal_width = 60, horizontal_align = "center" }
          },
          {
            type = "sprite-button",
            name = "zp_visibility_higher",
            sprite = "utility/forward_arrow",
            style = "zp_icon_button",
            handler = handlers.visibility_higher,
            tooltip = {"tooltips.tooltip-visibility-increase"}
          }
        }
      }
    }
  })
  dlg.tags = { visibility_index = idx }
  update_visibility_label(dlg, idx)
end

local function adjust_visibility_level(player_index, delta)
  local idx = backend.get_boundary_opacity_index and backend.get_boundary_opacity_index(player_index) or 0
  local new_idx = idx + delta
  if new_idx < 0 then new_idx = 0 end
  if new_idx > 3 then new_idx = 3 end
  if new_idx ~= idx then
    backend.set_player_visibility(player_index, { index = new_idx })
  end
  local player = game.get_player(player_index)
  if not player then return end
  local dlg = player.gui.screen["zp_visibility_dialog"]
  if dlg and dlg.valid then
    dlg.tags = { visibility_index = new_idx }
    update_visibility_label(dlg, new_idx)
  end
end

function handlers.visibility_lower(e)
  adjust_visibility_level(e.player_index, -1)
end

function handlers.visibility_higher(e)
  adjust_visibility_level(e.player_index, 1)
end

function handlers.undo(e)
  local player = game.get_player(e.player_index)
  if player then
    backend.undo(player.index)
    -- UI rebuild triggered by backend notification
  end
end

function handlers.redo(e)
  local player = game.get_player(e.player_index)
  if player then
    backend.redo(player.index)
    -- UI rebuild triggered by backend notification
  end
end

function handlers.close_main_frame(e)
  local player = game.get_player(e.player_index)
  if player then
    local frame = ensure_main_frame(player)
    frame.visible = false
  end
end

function handlers.select_tool_rect(e)
  local player = game.get_player(e.player_index)
  if not player then return end
  local ok = player.clear_cursor()
  if not ok then
    player.create_local_flying_text{ text = "Clear your cursor first", create_at_cursor = true, color = {r=1,g=0.3,b=0} }
    return
  end
  local tool_name = "zone-planner-rectangle-tool"
  if player.cursor_stack and player.cursor_stack.valid_for_read then
    player.create_local_flying_text{ text = "Unable to set tool in cursor", create_at_cursor = true, color = {r=1,g=0.3,b=0} }
    return
  end
  if player.cursor_stack then
    player.cursor_stack.set_stack({ name = tool_name, count = 1 })
    backend.set_selected_tool(player.index, "rect")
  end
end

function handlers.zone_add(e)
  local player = game.get_player(e.player_index)
  if not player then return end
  local dlg = dialog.create(player, {
    name = "zp_zone_dialog",
    title = "Add Zone",
    location = e.cursor_display_location,
    children = {
      {
        type = "flow", direction = "horizontal",
        children = {
          { type = "label", caption = "Name", style_mods = { top_padding = 4}},
          { type = "textfield", name = "zp_zone_name", text = "", icon_selector = true }
        }
      },
      build_color_picker(1, 1, 1, handlers.color_slider_changed)
    }
  })
  dlg.tags = { color_r = 255, color_g = 255, color_b = 255 }
end

function handlers.zone_edit_open(e)
  local player = game.get_player(e.player_index)
  if not player then return end
  local id = e.element.tags and tonumber(e.element.tags.zone_id)
  if not id then return end
  local f = backend.get_force(player.force.index)
  local z = f.zones[id]
  if not z then return end
  local col = z.color or {r=1,g=1,b=1,a=1}
  local dlg = dialog.create(player, {
    name = "zp_zone_dialog",
    title = "Edit Zone",
    location = e.cursor_display_location,
    children = {
      {
        type = "flow", direction = "horizontal",
        children = {
          { type = "label", caption = "Name", style_mods = { top_padding = 4}},
          { type = "textfield", name = "zp_zone_name", text = z.name or "", icon_selector = true }
        }
      },
      build_color_picker(col.r, col.g, col.b, handlers.color_slider_changed)
    }
  })
  dlg.tags = { zone_id = id, color_r = math.floor(col.r * 255), color_g = math.floor(col.g * 255), color_b = math.floor(col.b * 255) }
end

function handlers.zone_delete(e)
  local player = game.get_player(e.player_index)
  if not player then return end
  local id = e.element.tags and tonumber(e.element.tags.zone_id)
  if not id then return end
  backend.delete_zone(player.force.index, player.index, id, 0)
  -- UI rebuild triggered by backend notification
end

function handlers.color_slider_changed(e)
  local player = game.get_player(e.player_index)
  if not player then return end
  local element = e.element
  if not element or not element.valid then return end
  local dlg = player.gui.screen["zp_zone_dialog"]
  if not dlg or not dlg.valid then return end
  
  -- Update tags based on which slider changed
  local tags = dlg.tags or {}
  if element.name == "zp_color_r" then
    tags.color_r = element.slider_value
  elseif element.name == "zp_color_g" then
    tags.color_g = element.slider_value
  elseif element.name == "zp_color_b" then
    tags.color_b = element.slider_value
  else
    return
  end
  dlg.tags = tags
  
  -- Update preview
  update_color_preview(dlg, "zp_color_preview", "zp_color_r", "zp_color_g", "zp_color_b")
end

function handlers.zone_row_select(e)
  local player = game.get_player(e.player_index)
  if not player then return end
  local id = e.element.tags and tonumber(e.element.tags.zone_id)
  if not id then return end
  backend.set_selected_zone_id(player.index, id)
  -- Rebuild to update selection highlight immediately
  ui.rebuild_player(player.index, "zone-selected")
end

function handlers.zone_move_up(e)
  local player = game.get_player(e.player_index)
  if not player then return end
  local id = e.element.tags and tonumber(e.element.tags.zone_id)
  if not id then return end
    local value = 1
  if e.shift then
    value = 5
  end
  if e.control then
    value = 50
  end

  backend.move_zone(player.force.index, player.index, id, -value)
  -- UI rebuild triggered by backend notification
end

function handlers.zone_move_down(e)
  local player = game.get_player(e.player_index)
  if not player then return end
  local id = e.element.tags and tonumber(e.element.tags.zone_id)
  if not id then return end
  local value = 1
  if e.shift then
    value = 5
  end
  if e.control then
    value = 50
  end
  backend.move_zone(player.force.index, player.index, id, value)
  -- UI rebuild triggered by backend notification
end

-- Register all handlers with flib
flib_gui.add_handlers(handlers)

---Build UI for all current players on init.
function ui.on_init(event)
  for _, p in pairs(game.players) do
    ui.rebuild_player(p.index, "init")
  end
end

-- Event handlers
ui.events = {}

---Create per-player UI on player creation.
function ui.events.on_player_created(event)
  ui.rebuild_player(event.player_index, "player-created")
end

-- Hotkey handlers
ui.events["zp-select-rect-tool"] = handlers.select_tool_rect
ui.events["zp-visibility-increase"] = handlers.visibility_higher
ui.events["zp-visibility-decrease"] = handlers.visibility_lower
ui.events["zp-undo"] = handlers.undo
ui.events["zp-redo"] = handlers.redo
ui.events["zp-pipette"] = handlers.pipette

-- Handle escape key on dialogs
function ui.events.on_gui_closed(event)
  local player = game.get_player(event.player_index)
  if not player or not player.valid then return end
  
  -- When player presses escape on a dialog, close it
  local parent = player.gui.screen
  for _, name in ipairs(dialog.get_all_names()) do
    local dlg = parent[name]
    if dlg and dlg.valid then
      dlg.destroy()
    end
  end
end

-- Handle enter key on dialogs
function ui.events.on_gui_confirmed(event)
  local player = game.get_player(event.player_index)
  if not player or not player.valid then return end
  
  -- When player presses enter on a dialog, call its confirm handler and close it
  local parent = player.gui.screen
  for _, name in ipairs(dialog.get_all_names()) do
    local dlg = parent[name]
    if dlg and dlg.valid then
      local registry_entry = dialog.get_registry(name)
      if registry_entry and registry_entry.on_confirm then
        registry_entry.on_confirm(dlg, player)
        dlg.destroy()
      end
      return
    end
  end
end

-- All value_changed and checked_state_changed events are handled by flib via tags

return ui

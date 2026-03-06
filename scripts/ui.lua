-- UI module

local ui = {}
local backend = require("scripts/backend")
local flib_gui = require("__flib__.gui")
local dialog = require("scripts/dialog")

local mod_gui = require("mod-gui")

---@class GP.UiState
---@field is_building boolean

-- Element names
local TOGGLE_BUTTON_NAME = "region_planner_toggle_button"
local MAIN_FRAME_NAME = "region_planner_main_frame"

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


---Return the currently selected region id for the player (from backend).
---@param player_index uint
---@return uint|nil
function ui.get_selected_region_id(player_index)
  return backend.get_selected_region_id(player_index)
end

-- Helper: build color picker (sliders + preview) for dialog
---@param r number Normalized red (0-1)
---@param g number Normalized green (0-1)
---@param b number Normalized blue (0-1)
---@param handler function Event handler for slider changes
---@return table Flow definition containing the sliders and preview
local function build_color_picker(r, g, b, handler)
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
    name = "gp_color_picker",
    style_mods = { horizontally_stretchable = true, top_padding = 4, vertical_spacing = 6 },
    children = {
      {
        type = "flow",
        direction = "vertical",
        name = "gp_color_sliders",
        style_mods = { horizontally_stretchable = true, vertical_spacing = 2 },
        children = {
          color_slider_row("Red", "gp_color_r", r or 1),
          color_slider_row("Green", "gp_color_g", g or 1),
          color_slider_row("Blue", "gp_color_b", b or 1),
        }
      },
      {
        type = "progressbar",
        name = "gp_color_preview",
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
  local label = find_child(dlg, "gp_visibility_level_label")
  if label and label.valid then
    label.caption = visibility_caption(idx)
  end
end

-- Helper: update color preview progressbar from current slider values
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

-- Pipette handler: sample all visible layers (topmost = highest order wins)
function handlers.pipette(e)
  if e.in_gui then return end
  local player = game.get_player(e.player_index)
  if not player or not player.valid then return end
  local pos = e.cursor_position
  if not pos then return end
  local force_index = player.force.index
  local surface_index = player.surface.index
  local sorted_layers = backend.get_sorted_layers(force_index, surface_index)
  local found_region_id = nil
  for i = #sorted_layers, 1, -1 do
    local layer = sorted_layers[i]
    if layer.visible then
      local cx, cy = backend.tile_to_cell_layer(layer, pos.x, pos.y)
      local region_id = backend.get_from_layer(layer, cx, cy)
      if region_id and region_id ~= 0 then
        found_region_id = region_id
        break
      end
    end
  end
  if found_region_id then
    backend.set_selected_region_id(player.index, found_region_id)
    ui.rebuild_player(player.index, "pipette")
  end
end

-- Register dialogs with their handlers
dialog.register("gp_visibility_dialog", {
  on_confirm = function(dlg, player)
    local idx = dlg.tags and tonumber(dlg.tags.visibility_index)
    backend.set_player_visibility(player.index, { index = idx })
  end
})

dialog.register("gp_region_dialog", {
  on_confirm = function(dlg, player)
    local name_elem = find_child(dlg, "gp_region_name")
    local name = name_elem and name_elem.text or ""
    local tags = dlg.tags or {}
    local r = tags.color_r or 255
    local g = tags.color_g or 255
    local b = tags.color_b or 255
    local color = { r = r/255, g = g/255, b = b/255, a = 1 }

    local region_id = tonumber(tags.region_id)
    if region_id then
      backend.edit_region(player.force.index, player.index, region_id, name, color)
    else
      backend.add_region(player.force.index, player.index, name, color)
    end
  end
})

-- Layer edit dialog: handles rename + grid properties for a specific layer
dialog.register("gp_layer_dialog", {
  on_confirm = function(dlg, player)
    local tags = dlg.tags or {}
    local layer_id = tonumber(tags.layer_id)
    local surface_index = tonumber(tags.surface_index) or player.surface.index
    if not layer_id then return end
    local layer = backend.get_layer(player.force.index, surface_index, layer_id)
    if not layer then return end

    -- Rename if name changed
    local name_elem = find_child(dlg, "gp_layer_name")
    local name = name_elem and name_elem.text or ""
    if name ~= "" and name ~= layer.name then
      backend.rename_layer(player.force.index, player.index, surface_index, layer_id, name)
    end

    -- Update grid if values changed
    local size_elem = find_child(dlg, "gp_layer_prop_size")
    local x_offset_elem = find_child(dlg, "gp_layer_prop_x_offset")
    local y_offset_elem = find_child(dlg, "gp_layer_prop_y_offset")
    local reproject_elem = find_child(dlg, "gp_layer_prop_reproject")
    local size = tonumber(size_elem and size_elem.text) or layer.grid.width
    local new_props = {
      width = size,
      height = size,
      x_offset = tonumber(x_offset_elem and x_offset_elem.text) or layer.grid.x_offset,
      y_offset = tonumber(y_offset_elem and y_offset_elem.text) or layer.grid.y_offset,
    }
    local reproject = (reproject_elem and reproject_elem.state) or false
    local grid_changed = new_props.width ~= layer.grid.width
      or new_props.x_offset ~= layer.grid.x_offset
      or new_props.y_offset ~= layer.grid.y_offset
    if grid_changed then
      backend.set_grid(player.force.index, surface_index, layer_id, player.index, new_props, { reproject = reproject })
    end
  end
})

---@class GP.UiChange
---@field kind string Change kind (e.g. "backend-changed", "player-created", "init")
---@field force_index uint|nil
---@field surface_index uint|nil
---@field player_index uint|nil
---@field payload table|nil Additional change data

---Called by backend when data changes; UI can rebuild or update selectively.
---@param change GP.UiChange
function ui.on_backend_changed(change)
  if storage and storage.gp_ui and storage.gp_ui.is_building then
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
---@param reason string|nil Reason for rebuild (informational only)
function ui.rebuild_player(player_index, reason)
  local _ = reason
  storage.gp_ui = storage.gp_ui or {}
  if storage.gp_ui.is_building then
    return
  end
  storage.gp_ui.is_building = true
  local player = game.get_player(player_index)
  if not player then storage.gp_ui.is_building = false; return end
  local frame = ensure_main_frame(player)
  local was_visible = frame.visible
  frame.clear()

  -- Create toggle button in mod-gui button flow
  local button_flow = mod_gui.get_button_flow(player)
  local existing_btn = button_flow[TOGGLE_BUTTON_NAME]
  if not existing_btn then
    flib_gui.add(button_flow, {
      type = "sprite-button",
      name = TOGGLE_BUTTON_NAME,
      sprite = "gp-mod-icon",
      style = "mod_gui_button",
      tooltip = {"grid-planner.mod-name"},
      handler = handlers.toggle_main_frame,
      style_mods = { vertically_stretchable = true }
    })
  end

  -- Edit mode state (shared for both layers and regions panels)
  local show_edit = true
  if storage.gp_ui and storage.gp_ui.players and storage.gp_ui.players[player_index] then
    local se = storage.gp_ui.players[player_index].show_edit_buttons
    if se ~= nil then show_edit = se end
  end

  -- Header: title + spacer + Undo, Redo, Edit, Visibility, Close buttons
  flib_gui.add(frame, {
    type = "flow",
    direction = "horizontal",
    style_mods = { horizontal_spacing = 8 },
    children = {
      { type = "label", caption = {"grid-planner.mod-name"}, style = "frame_title", style_mods = { top_padding = -3 }},
      { type = "empty-widget", style_mods = { horizontally_stretchable = true, height = 24 }, style = "draggable_space" },
      {
        type = "sprite-button",
        name = "gp_undo",
        sprite = "gp-undo-icon-light",
        style = "frame_action_button",
        handler = handlers.undo,
        elem_mods = {
          enabled = backend.can_undo(player_index),
          tooltip = {"tooltips.tooltip-undo", backend.peek_undo_description(player_index) or "None"}
        }
      },
      {
        type = "sprite-button",
        name = "gp_redo",
        sprite = "gp-redo-icon-light",
        style = "frame_action_button",
        handler = handlers.redo,
        elem_mods = {
          enabled = backend.can_redo(player_index),
          tooltip = {"tooltips.tooltip-redo", backend.peek_redo_description(player_index) or "None"}
        }
      },
      {
        type = "sprite-button",
        name = "gp_visibility_open",
        sprite = "gp-visibility-light-16",
        style = "frame_action_button",
        handler = handlers.visibility_open,
        tooltip = "Visibility settings"
      },
      {
        type = "sprite-button",
        name = "gp_edit_toggle",
        sprite = "gp-edit-light-16",
        style = "frame_action_button",
        handler = handlers.regions_edit_toggle,
        tooltip = "Show edit buttons",
        elem_mods = { toggled = show_edit },
      },
      {
        type = "sprite-button",
        name = "gp_close_main_frame",
        sprite = "utility/close",
        style = "frame_action_button",
        handler = handlers.close_main_frame,
        tooltip = "Close panel"
      },
    }
  })

  -- Tools row
  flib_gui.add(frame, {
    type = "flow",
    direction = "horizontal",
    children = {
      {
        type = "sprite-button",
        name = "gp_tool_rect",
        sprite = "utility/brush_square_shape",
        style = "tool_button",
        handler = handlers.select_tool_rect,
        tooltip = {"tooltips.tooltip-rect"}
      },
      {
        type = "sprite-button",
        name = "gp_tool_pipette",
        sprite = "utility/color_picker",
        style = "tool_button",
        handler = handlers.pipette,
        enabled = false,
        tooltip = {"tooltips.tooltip-pipette"}
      }
    }
  })

  local force_index = player.force.index
  local surface_index = player.surface.index

  -- =========================================================================
  -- Layers panel
  -- =========================================================================
  flib_gui.add(frame, { type = "label", caption = "Layers", style = "frame_title" })

  local _, layers_scroll = flib_gui.add(frame, {
    type = "scroll-pane",
    name = "gp_layers_scroll",
    style = "flib_naked_scroll_pane",
    horizontal_scroll_policy = "never",
    vertical_scroll_policy = "auto",
    style_mods = {
      minimal_height = 60,
      maximal_height = 200,
      horizontally_stretchable = true,
      padding = 4,
    }
  })

  local _, layers_frame = flib_gui.add(layers_scroll, {
    type = "frame",
    name = "gp_layers_frame",
    direction = "vertical",
    style = "inside_deep_frame",
    style_mods = { minimal_width = 300, padding = 8 }
  })

  local _, layers_list = flib_gui.add(layers_frame, {
    type = "flow",
    name = "gp_layers_flow",
    direction = "vertical",
    style_mods = { vertical_spacing = 0 }
  })

  local sorted_layers = backend.get_sorted_layers(force_index, surface_index)
  local active_layer_id = backend.get_active_layer_id(player_index, surface_index)
  -- If no active layer set, default to first
  if not active_layer_id and sorted_layers[1] then
    active_layer_id = sorted_layers[1].id
    backend.set_active_layer_id(player_index, surface_index, active_layer_id)
  end
  local layer_count = #sorted_layers

  local function add_layer_row(layer, is_active, is_first, is_last)
    local vis_sprite = layer.visible and "gp-visibility-light-16" or "gp-visibility-dark-16"
    flib_gui.add(layers_list, {
      type = "flow",
      direction = "horizontal",
      style_mods = { horizontally_stretchable = true },
      children = {
        {
          type = "frame",
          style = "gp_region_row_frame",
          style_mods = { top_padding = 3, bottom_padding = 1, left_padding = 0, right_padding = 0, minimal_width = 0 },
          children = {
            {
              type = "sprite-button",
              name = ("gp_layer_vis_%d"):format(layer.id),
              sprite = vis_sprite,
              style = "gp_icon_button",
              handler = handlers.layer_toggle_visibility,
              tags = { layer_id = layer.id, surface_index = surface_index },
              tooltip = layer.visible and "Hide layer" or "Show layer",
            },
          }
        },
        {
          type = "button",
          name = ("gp_layer_select_%d"):format(layer.id),
          style = "gp_region_row_button",
          style_mods = { horizontally_stretchable = true },
          toggled = is_active,
          caption = layer.name,
          handler = handlers.layer_select,
          tags = { layer_id = layer.id, surface_index = surface_index },
          tooltip = layer.name,
        },
        {
          type = "frame",
          name = ("gp_layer_edit_frame_%d"):format(layer.id),
          style = "gp_region_row_frame",
          elem_mods = { visible = show_edit },
          children = {
            {
              type = "flow",
              direction = "horizontal",
              style_mods = { horizontal_spacing = 4 },
              children = {
                { type = "sprite-button", name = ("gp_layer_up_%d"):format(layer.id),   sprite = "gp-up-dark-32",   style = "gp_icon_button", tooltip = "Move up",   handler = handlers.layer_move_up,   tags = { layer_id = layer.id, surface_index = surface_index }, elem_mods = { enabled = not is_first } },
                { type = "sprite-button", name = ("gp_layer_down_%d"):format(layer.id), sprite = "gp-down-dark-32", style = "gp_icon_button", tooltip = "Move down", handler = handlers.layer_move_down, tags = { layer_id = layer.id, surface_index = surface_index }, elem_mods = { enabled = not is_last } },
                { type = "sprite-button", name = ("gp_layer_edit_%d"):format(layer.id), sprite = "gp-edit-dark-32", style = "gp_icon_button", tooltip = "Edit layer (name, grid size, offset)", handler = handlers.layer_edit_open, tags = { layer_id = layer.id, surface_index = surface_index } },
                { type = "sprite-button", name = ("gp_layer_del_%d"):format(layer.id),  sprite = "utility/trash",   style = "gp_icon_button_red", tooltip = "Delete layer", handler = handlers.layer_delete, tags = { layer_id = layer.id, surface_index = surface_index }, elem_mods = { enabled = layer_count > 1 } },
              }
            }
          }
        }
      }
    })
  end

  for idx, layer in ipairs(sorted_layers) do
    add_layer_row(layer, layer.id == active_layer_id, idx == 1, idx == layer_count)
  end

  if show_edit then
    flib_gui.add(layers_list, {
      type = "frame",
      name = "gp_layer_add_outer",
      style = "gp_region_row_frame",
      style_mods = { horizontally_stretchable = true },
      children = {
        {
          type = "button",
          name = "gp_layer_add",
          caption = "＋ Add Layer",
          handler = handlers.layer_add,
          style_mods = { horizontally_stretchable = true, vertically_stretchable = true }
        }
      }
    })
  end

  -- =========================================================================
  -- Regions panel
  -- =========================================================================
  flib_gui.add(frame, {
    type = "flow",
    direction = "horizontal",
    style_mods = { vertical_align = "center" },
    children = {
      { type = "label", caption = "Regions", style = "frame_title" },
    }
  })

  local _, scroll = flib_gui.add(frame, {
    type = "scroll-pane",
    name = "gp_regions_scroll",
    style = "flib_naked_scroll_pane",
    horizontal_scroll_policy = "never",
    vertical_scroll_policy = "auto",
    style_mods = {
      minimal_height = 100,
      maximal_height = 400,
      horizontally_stretchable = true,
      padding = 4,
    }
  })

  local _, frame_list = flib_gui.add(scroll, {
    type = "frame",
    name = "gp_regions_frame",
    direction = "vertical",
    style = "inside_deep_frame",
    style_mods = { minimal_width = 300, padding = 8 }
  })

  local _, list = flib_gui.add(frame_list, {
    type = "flow",
    name = "gp_regions_flow",
    direction = "vertical",
    style_mods = { vertical_spacing = 0 }
  })

  if not list or not list.valid then
    storage.gp_ui.is_building = false
    return
  end

  local f = backend.get_force(force_index)
  local selected_id = backend.get_selected_region_id(player_index) or 0

  if selected_id == 0 or not (f and f.regions and f.regions[selected_id]) then
    local first_id = nil
    if f and f.regions then
      for id, _ in pairs(f.regions) do
        if id ~= 0 and (not first_id or id < first_id) then
          first_id = id
        end
      end
    end
    if first_id then
      backend.set_selected_region_id(player_index, first_id)
      selected_id = first_id
    end
  end

  local function add_region_row(id, name, color, is_first, is_last)
    local select_name = "gp_region_select_" .. tostring(id)
    local delete_name = "gp_region_delete_" .. tostring(id)

    flib_gui.add(list, {
      type = "flow",
      direction = "horizontal",
      style_mods = { horizontally_stretchable = true },
      children = {
        {
          type = "button",
          name = select_name,
          style = "gp_region_row_button",
          style_mods = { horizontally_stretchable = true, width = 280 },
          toggled = selected_id == id,
          handler = handlers.region_row_select,
          tags = { region_id = id },
          tooltip = name or ("Region " .. tostring(id)),
          children = {
            {
              type = "flow",
              direction = "horizontal",
              style_mods = { horizontal_spacing = 4, vertically_stretchable = false, vertical_align = "center" },
              children = {
                {
                  type = "label",
                  caption = "■",
                  style = "gp_color_patch_label",
                  style_mods = { font_color = { r = color.r or 1, g = color.g or 1, b = color.b or 1 } }
                },
                {
                  type = "label",
                  caption = name or ("Region " .. tostring(id)),
                  style = "gp_heading_label",
                  style_mods = { single_line = true, maximal_width = 230 },
                },
              }
            }
          },
        },
        {
          type = "frame",
          name = "gp_edit_frame_" .. tostring(id),
          style = "gp_region_row_frame",
          elem_mods = { visible = show_edit },
          children = {
            {
              type = "flow",
              direction = "horizontal",
              style_mods = { horizontal_spacing = 4 },
              children = {
                {
                  type = "sprite-button",
                  name = ("gp_region_up_%s"):format(id),
                  sprite = "gp-up-dark-32",
                  style = "gp_icon_button",
                  tooltip = "Move up. Shift: Move up 5, Control: 50.",
                  handler = handlers.region_move_up,
                  tags = { region_id = id },
                  elem_mods = { enabled = not is_first }
                },
                {
                  type = "sprite-button",
                  name = ("gp_region_down_%s"):format(id),
                  sprite = "gp-down-dark-32",
                  tooltip = "Move down. Shift: Move down 5, Control: 50.",
                  style = "gp_icon_button",
                  handler = handlers.region_move_down,
                  tags = { region_id = id },
                  elem_mods = { enabled = not is_last }
                },
                {
                  type = "sprite-button",
                  name = ("gp_region_name_%s"):format(id),
                  sprite = "gp-edit-dark-32",
                  style = "gp_icon_button",
                  handler = handlers.region_edit_open,
                  tags = { region_id = id },
                  tooltip = "Edit region"
                },
                {
                  type = "sprite-button",
                  name = delete_name,
                  sprite = "utility/trash",
                  style = "gp_icon_button_red",
                  handler = handlers.region_delete,
                  elem_mods = { enabled = true },
                  tags = { region_id = id },
                  tooltip = "Delete region"
                }
              }
            }
          }
        }
      },
    })
  end

  if f and f.regions then
    local regions_list = {}
    for id, z in pairs(f.regions) do
      if id ~= 0 then
        table.insert(regions_list, { id = id, region = z })
      end
    end
    table.sort(regions_list, function(a, b) return a.region.order < b.region.order end)

    for idx, entry in ipairs(regions_list) do
      local id = entry.id
      local z = entry.region
      local is_first = (idx == 1)
      local is_last = (idx == #regions_list)
      add_region_row(id, z.name, z.color or {r=1,g=1,b=1,a=1}, is_first, is_last)
    end
  end

  if show_edit then
    flib_gui.add(list, {
      type = "frame",
      name = "gp_region_add_outer",
      style = "gp_region_row_frame",
      style_mods = { horizontally_stretchable = true },
      children = {
        {
          type = "button",
          name = "gp_region_add",
          caption = "＋ Add Region",
          handler = handlers.region_add,
          style_mods = { horizontally_stretchable = true, vertically_stretchable = true }
        }
      }
    })
  end

  frame.visible = was_visible
  storage.gp_ui.is_building = false
end


-- Handler function implementations
function handlers.toggle_main_frame(e)
  local player = game.get_player(e.player_index)
  if player then
    local frame = ensure_main_frame(player)
    frame.visible = not frame.visible
    if frame.visible then
      player.game_view_settings.show_entity_info = true
    end
  end
end

function handlers.visibility_open(e)
  local player = game.get_player(e.player_index)
  if not player then return end
  local idx = backend.get_boundary_opacity_index and backend.get_boundary_opacity_index(player.index) or 0
  local dlg = dialog.create(player, {
    name = "gp_visibility_dialog",
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
            name = "gp_visibility_lower",
            sprite = "utility/backward_arrow",
            style = "gp_icon_button",
            handler = handlers.visibility_lower,
            tooltip = {"tooltips.tooltip-visibility-decrease"}
          },
          {
            type = "label",
            name = "gp_visibility_level_label",
            caption = visibility_caption(idx),
            style_mods = { minimal_width = 60, horizontal_align = "center" }
          },
          {
            type = "sprite-button",
            name = "gp_visibility_higher",
            sprite = "utility/forward_arrow",
            style = "gp_icon_button",
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
  local dlg = player.gui.screen["gp_visibility_dialog"]
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
  end
end

function handlers.redo(e)
  local player = game.get_player(e.player_index)
  if player then
    backend.redo(player.index)
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
  local tool_name = "grid-planner-rectangle-tool"
  if player.cursor_stack and player.cursor_stack.valid_for_read then
    player.create_local_flying_text{ text = "Unable to set tool in cursor", create_at_cursor = true, color = {r=1,g=0.3,b=0} }
    return
  end
  if player.cursor_stack then
    player.cursor_stack.set_stack({ name = tool_name, count = 1 })
    backend.set_selected_tool(player.index, "rect")
  end
end

-- Layer handlers -------------------------------------------------------------

function handlers.layer_select(e)
  local player = game.get_player(e.player_index)
  if not player then return end
  local tags = e.element.tags or {}
  local layer_id = tonumber(tags.layer_id)
  local surface_index = tonumber(tags.surface_index) or player.surface.index
  if not layer_id then return end
  backend.set_active_layer_id(player.index, surface_index, layer_id)
  ui.rebuild_player(player.index, "layer-selected")
end

function handlers.layer_toggle_visibility(e)
  local player = game.get_player(e.player_index)
  if not player then return end
  local tags = e.element.tags or {}
  local layer_id = tonumber(tags.layer_id)
  local surface_index = tonumber(tags.surface_index) or player.surface.index
  if not layer_id then return end
  local layer = backend.get_layer(player.force.index, surface_index, layer_id)
  if not layer then return end
  backend.set_layer_visibility(player.force.index, player.index, surface_index, layer_id, not layer.visible)
end

function handlers.layer_add(e)
  local player = game.get_player(e.player_index)
  if not player then return end
  local surface_index = player.surface.index
  local layer_id = backend.add_layer(player.force.index, player.index, surface_index, "New Layer")
  backend.set_active_layer_id(player.index, surface_index, layer_id)
  ui.rebuild_player(player.index, "layer-added")
end

function handlers.layer_delete(e)
  local player = game.get_player(e.player_index)
  if not player then return end
  local tags = e.element.tags or {}
  local layer_id = tonumber(tags.layer_id)
  local surface_index = tonumber(tags.surface_index) or player.surface.index
  if not layer_id then return end
  backend.delete_layer(player.force.index, player.index, surface_index, layer_id)
end

function handlers.layer_move_up(e)
  local player = game.get_player(e.player_index)
  if not player then return end
  local tags = e.element.tags or {}
  local layer_id = tonumber(tags.layer_id)
  local surface_index = tonumber(tags.surface_index) or player.surface.index
  if not layer_id then return end
  backend.move_layer(player.force.index, player.index, surface_index, layer_id, -1)
end

function handlers.layer_move_down(e)
  local player = game.get_player(e.player_index)
  if not player then return end
  local tags = e.element.tags or {}
  local layer_id = tonumber(tags.layer_id)
  local surface_index = tonumber(tags.surface_index) or player.surface.index
  if not layer_id then return end
  backend.move_layer(player.force.index, player.index, surface_index, layer_id, 1)
end

function handlers.layer_edit_open(e)
  local player = game.get_player(e.player_index)
  if not player then return end
  local tags = e.element.tags or {}
  local layer_id = tonumber(tags.layer_id)
  local surface_index = tonumber(tags.surface_index) or player.surface.index
  if not layer_id then return end
  local layer = backend.get_layer(player.force.index, surface_index, layer_id)
  if not layer then return end
  local dlg = dialog.create(player, {
    name = "gp_layer_dialog",
    title = "Edit Layer",
    location = e.cursor_display_location,
    children = {
      labeled_textfield("Name", "gp_layer_name", layer.name),
      labeled_textfield("Size", "gp_layer_prop_size", layer.grid.width),
      labeled_textfield("X offset", "gp_layer_prop_x_offset", layer.grid.x_offset),
      labeled_textfield("Y offset", "gp_layer_prop_y_offset", layer.grid.y_offset),
      { type = "checkbox", name = "gp_layer_prop_reproject", state = true, caption = "Reproject existing cells" }
    }
  })
  dlg.tags = { layer_id = layer_id, surface_index = surface_index }
end

-- Region handlers ------------------------------------------------------------

function handlers.region_add(e)
  local player = game.get_player(e.player_index)
  if not player then return end
  local dlg = dialog.create(player, {
    name = "gp_region_dialog",
    title = "Add Region",
    location = e.cursor_display_location,
    children = {
      {
        type = "flow", direction = "horizontal",
        children = {
          { type = "label", caption = "Name", style_mods = { top_padding = 4}},
          { type = "textfield", name = "gp_region_name", text = "", icon_selector = true }
        }
      },
      build_color_picker(1, 1, 1, handlers.color_slider_changed)
    }
  })
  dlg.tags = { color_r = 255, color_g = 255, color_b = 255 }
end

function handlers.region_edit_open(e)
  local player = game.get_player(e.player_index)
  if not player then return end
  local id = e.element.tags and tonumber(e.element.tags.region_id)
  if not id then return end
  local f = backend.get_force(player.force.index)
  local z = f.regions[id]
  if not z then return end
  local col = z.color or {r=1,g=1,b=1,a=1}
  local dlg = dialog.create(player, {
    name = "gp_region_dialog",
    title = "Edit Region",
    location = e.cursor_display_location,
    children = {
      {
        type = "flow", direction = "horizontal",
        children = {
          { type = "label", caption = "Name", style_mods = { top_padding = 4}},
          { type = "textfield", name = "gp_region_name", text = z.name or "", icon_selector = true }
        }
      },
      build_color_picker(col.r, col.g, col.b, handlers.color_slider_changed)
    }
  })
  dlg.tags = { region_id = id, color_r = math.floor(col.r * 255), color_g = math.floor(col.g * 255), color_b = math.floor(col.b * 255) }
end

function handlers.region_delete(e)
  local player = game.get_player(e.player_index)
  if not player then return end
  local id = e.element.tags and tonumber(e.element.tags.region_id)
  if not id then return end
  backend.delete_region(player.force.index, player.index, id, 0)
end

function handlers.color_slider_changed(e)
  local player = game.get_player(e.player_index)
  if not player then return end
  local element = e.element
  if not element or not element.valid then return end
  local dlg = player.gui.screen["gp_region_dialog"]
  if not dlg or not dlg.valid then return end

  local tags = dlg.tags or {}
  if element.name == "gp_color_r" then
    tags.color_r = element.slider_value
  elseif element.name == "gp_color_g" then
    tags.color_g = element.slider_value
  elseif element.name == "gp_color_b" then
    tags.color_b = element.slider_value
  else
    return
  end
  dlg.tags = tags

  update_color_preview(dlg, "gp_color_preview", "gp_color_r", "gp_color_g", "gp_color_b")
end

function handlers.region_row_select(e)
  local player = game.get_player(e.player_index)
  if not player then return end
  local id = e.element.tags and tonumber(e.element.tags.region_id)
  if not id then return end
  backend.set_selected_region_id(player.index, id)
  ui.rebuild_player(player.index, "region-selected")
end

function handlers.region_move_up(e)
  local player = game.get_player(e.player_index)
  if not player then return end
  local id = e.element.tags and tonumber(e.element.tags.region_id)
  if not id then return end
  local value = 1
  if e.shift then value = 5 end
  if e.control then value = 50 end
  backend.move_region(player.force.index, player.index, id, -value)
end

function handlers.region_move_down(e)
  local player = game.get_player(e.player_index)
  if not player then return end
  local id = e.element.tags and tonumber(e.element.tags.region_id)
  if not id then return end
  local value = 1
  if e.shift then value = 5 end
  if e.control then value = 50 end
  backend.move_region(player.force.index, player.index, id, value)
end

function handlers.regions_edit_toggle(e)
  local player = game.get_player(e.player_index)
  if not player then return end

  storage.gp_ui = storage.gp_ui or {}
  storage.gp_ui.players = storage.gp_ui.players or {}
  storage.gp_ui.players[e.player_index] = storage.gp_ui.players[e.player_index] or {}
  local current = storage.gp_ui.players[e.player_index].show_edit_buttons
  if current == nil then current = true end
  storage.gp_ui.players[e.player_index].show_edit_buttons = not current

  ui.rebuild_player(e.player_index, "edit-toggle")
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
ui.events["gp-select-rect-tool"] = handlers.select_tool_rect
ui.events["gp-visibility-increase"] = handlers.visibility_higher
ui.events["gp-visibility-decrease"] = handlers.visibility_lower
ui.events["gp-undo"] = handlers.undo
ui.events["gp-redo"] = handlers.redo
ui.events["gp-pipette"] = handlers.pipette

-- Handle escape key on dialogs
function ui.events.on_gui_closed(event)
  local player = game.get_player(event.player_index)
  if not player or not player.valid then return end

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

return ui

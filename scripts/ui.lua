-- UI module for Zone Planner
-- Builds a mod-gui button and a main panel; toggles visibility on click.

local ui = {}
local backend = require("scripts/backend")
local flib_gui = require("__flib__.gui")

local mod_gui = require("mod-gui")

---@class ZP.UiState
---@field is_building boolean
---@field players table<uint, ZP.PlayerUiState>

---@class ZP.PlayerUiState
---@field selected_zone_id uint
---@field selected_tool string|nil

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
      direction = "vertical",
    }
    frame.visible = false
  end
  return frame
end

local function toggle_main_frame(player)
  local frame = ensure_main_frame(player)
  frame.visible = not frame.visible
  -- Enable alt mode when opening UI
  if frame.visible then
    player.game_view_settings.show_entity_info = true
  end
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

-- Helper: ensure player UI state exists
---@param player_index uint
---@return ZP.PlayerUiState
local function ensure_player_ui_state(player_index)
  storage.zp_ui = storage.zp_ui or {}
  storage.zp_ui.players = storage.zp_ui.players or {}
  local pstate = storage.zp_ui.players[player_index] or {}
  storage.zp_ui.players[player_index] = pstate
  return pstate
end

-- Helper: extract text from textfield
---@param element LuaGuiElement|nil
---@return string
local function get_text(element)
  return element and element.text or ""
end

-- Helper: parse number with fallback
---@param s string|nil
---@param default number
---@return number
local function to_number(s, default)
  local n = tonumber(s)
  return n or default
end

-- Helper: extract zone id from element name pattern
---@param element_name string
---@param pattern string
---@return uint|nil
local function extract_zone_id(element_name, pattern)
  local id_str = element_name:match(pattern or "^zp_zone_(%d+)$")
  if not id_str then return nil end
  return tonumber(id_str)
end

-- Helper: build color picker (sliders + preview) for dialog
---@param r number Normalized red (0-1)
---@param g number Normalized green (0-1)
---@param b number Normalized blue (0-1)
---@param handler function Event handler for slider changes
---@return table Flow definition containing the sliders and preview
local function build_color_picker(r, g, b, handler)
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
          {
            type = "flow", direction = "horizontal",
            style_mods = { horizontally_stretchable = true },
            children = {
              { type = "label", caption = "Red", style_mods = { minimal_width = 50 } },
              { type = "slider", name = "zp_color_r", minimum_value = 0, maximum_value = 255, value = math.floor((r or 1) * 255), handler = handler, style_mods = { horizontally_stretchable = true, minimal_width = 120 } }
            }
          },
          {
            type = "flow", direction = "horizontal",
            style_mods = { horizontally_stretchable = true },
            children = {
              { type = "label", caption = "Green", style_mods = { minimal_width = 50 } },
              { type = "slider", name = "zp_color_g", minimum_value = 0, maximum_value = 255, value = math.floor((g or 1) * 255), handler = handler, style_mods = { horizontally_stretchable = true, minimal_width = 120 } }
            }
          },
          {
            type = "flow", direction = "horizontal",
            style_mods = { horizontally_stretchable = true },
            children = {
              { type = "label", caption = "Blue", style_mods = { minimal_width = 50 } },
              { type = "slider", name = "zp_color_b", minimum_value = 0, maximum_value = 255, value = math.floor((b or 1) * 255), handler = handler, style_mods = { horizontally_stretchable = true, minimal_width = 120 } }
            }
          }
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

-- Helper: update color preview for dialog
---@param dlg LuaGuiElement
local function update_color_preview_for_dialog(dlg)
  update_color_preview(dlg, "zp_color_preview", "zp_color_r", "zp_color_g", "zp_color_b")
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

-- Helper: close any open Zone Planner dialogs except the one being opened
---@param parent LuaGuiElement
---@param keep_name string|nil
local function close_other_dialogs(parent, keep_name)
  if not parent or not parent.valid then return end
  local dialog_names = {
    "zp_properties_dialog",
    "zp_zone_dialog",
    "zp_zone_name_dialog",
    "zp_zone_color_dialog",
    "zp_visibility_dialog",
  }
  for _, name in pairs(dialog_names) do
    if name ~= keep_name then
      local dlg = parent[name]
      if dlg and dlg.valid then
        dlg.destroy()
      end
    end
  end
end

-- Helper factory: create a dialog cancel handler
---@class ZP.CancelHandlerOpts
---@field dialog_name string
---@field get_parent fun(player: LuaPlayer): LuaGuiElement
---@field clear_opened boolean|nil

---@param opts ZP.CancelHandlerOpts
---@return function
local function make_cancel_handler(opts)
  return function(e)
    local player = game.get_player(e.player_index)
    if not player then return end
    local parent = opts.get_parent(player)
    local dlg = parent[opts.dialog_name]
    if dlg and dlg.valid then dlg.destroy() end
    if opts.clear_opened then player.opened = nil end
  end
end

-- Helper factory: create a dialog confirm handler
---@class ZP.ConfirmHandlerOpts
---@field dialog_name string
---@field get_parent fun(player: LuaPlayer): LuaGuiElement
---@field on_confirm fun(e: any, dlg: LuaGuiElement, player: LuaPlayer)

---@param opts ZP.ConfirmHandlerOpts
---@return function
local function make_confirm_handler(opts)
  return function(e)
    local player = game.get_player(e.player_index)
    if not player then return end
    local parent = opts.get_parent(player)
    local dlg = parent[opts.dialog_name]
    if not dlg or not dlg.valid then return end
    opts.on_confirm(e, dlg, player)
    dlg.destroy()
  end
end

-- Create a standard dialog with header (title + close), content, and bottom confirm button.
---@class ZP.DialogOpts
---@field name string Dialog element name
---@field title string Dialog title
---@field confirm_name string Name of confirm button
---@field cancel_name string Name of cancel button
---@field confirm_handler function Confirm button event handler
---@field cancel_handler function Close/cancel button event handler
---@field parent LuaGuiElement Parent GUI element
---@field children table[] Child element definitions

---@param player LuaPlayer
---@param opts ZP.DialogOpts
---@return LuaGuiElement dialog, table elements
local function create_dialog(player, opts)
  local parent = opts.parent
  close_other_dialogs(parent, opts.name)
  -- destroy any existing
  local existing = parent[opts.name]
  if existing and existing.valid then existing.destroy() end

  local children = {
    -- Header: title + spacer + close
    {
      type = "flow",
      direction = "horizontal",
      children = {
        { type = "label", caption = opts.title or "", style = "frame_title" },
        { type = "empty-widget", style_mods = { horizontally_stretchable = true } },
        {
          type = "sprite-button",
          name = opts.cancel_name,
          sprite = "utility/close",
          style = "frame_action_button",
          handler = opts.cancel_handler
        }
      }
    }
  }

  -- Content (added by caller)
  for _, child in ipairs(opts.children or {}) do
    table.insert(children, child)
  end

  -- Spacer between content and confirm row
  table.insert(children, {
    type = "empty-widget",
    style_mods = { minimal_height = 4, maximal_height = 4 }
  })

  -- Bottom confirm row
  table.insert(children, {
    type = "flow",
    direction = "horizontal",
    children = {
      { type = "empty-widget", style_mods = { horizontally_stretchable = true } },
      {
        type = "sprite-button",
        name = opts.confirm_name,
        sprite = "utility/check_mark",
        style = "zp_icon_button_green",
        handler = opts.confirm_handler
      }
    }
  })

  -- Build dialog using flib_gui.add
  local elems, dlg = flib_gui.add(parent, {
    type = "frame",
    name = opts.name,
    direction = "vertical",
    children = children
  })

  player.opened = dlg
  return dlg, elems
end

-- Handler functions for flib dispatch - defined early so they can be used in rebuild_player
local handlers = {}

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
  ensure_button(player)
  local frame = ensure_main_frame(player)
  -- Rebuild panel contents while preserving visibility state
  local was_visible = frame.visible
  frame.clear()

  -- Custom header: title + spacer + Properties, Undo, Redo buttons
  local elems = flib_gui.add(frame, {
    type = "flow",
    direction = "horizontal",
    style_mods = { horizontal_spacing = 8 },
    children = {
      { type = "label", caption = {"zone-planner.mod-name"}, style = "frame_title", style_mods = { top_padding = -3 }},
      { type = "empty-widget", style_mods = { horizontally_stretchable = true, height = 24 }, style = "draggable_space" },
      { 
        type = "sprite-button", 
        name = "zp_undo", 
        sprite = "zp_undo_icon", 
        style = "frame_action_button",
        handler = handlers.undo,
        elem_mods = {
          enabled = backend.can_undo(player_index),
          tooltip = backend.peek_undo_description(player_index) and ("Undo: " .. backend.peek_undo_description(player_index)) or "Undo: None"
        }
      },
      { 
        type = "sprite-button",
        name = "zp_redo",
        sprite = "zp_redo_icon",
        style = "frame_action_button",
        handler = handlers.redo,
        elem_mods = {
          enabled = backend.can_redo(player_index),
          tooltip = backend.peek_redo_description(player_index) and ("Redo: " .. backend.peek_redo_description(player_index)) or "Redo: None"
        }
      },
      {
        type = "sprite-button",
        name = "zp_visibility_open",
        sprite = "zp_visibility_icon",
        style = "frame_action_button",
        handler = handlers.visibility_open,
        tooltip = "Visibility settings"
      },
      {
        type = "sprite-button",
        name = "zp_properties_open",
        sprite = "utility/rename_icon",
        style = "frame_action_button",
        handler = handlers.properties_open
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
        tooltip = "Rectangle tool - Use reverse/alt selection to erase zones."
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
  local selected_id = (storage and storage.zp_ui and storage.zp_ui.players and storage.zp_ui.players[player_index] and storage.zp_ui.players[player_index].selected_zone_id) or 0

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
      local pstate = ensure_player_ui_state(player_index)
      pstate.selected_zone_id = first_id
      selected_id = first_id
    end
  end

  -- Helper to render a single zone row
  local function add_zone_row(id, name, color)
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
                  name = ("zp_zone_name_%s"):format(id),
                  sprite = "utility/rename_icon",
                  style = "zp_icon_button",
                  handler = handlers.zone_name_open
                },
                {
                  type = "sprite-button",
                  name = ("zp_zone_color_%s"):format(id),
                  sprite = "utility/color_picker",
                  style = "zp_icon_button",
                  handler = handlers.zone_color_open
                },
                {
                  type = "sprite-button",
                  name = delete_name,
                  sprite = "utility/trash",
                  style = "zp_icon_button_red",
                  handler = handlers.zone_delete,
                  elem_mods = { enabled = true }
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
    for id, z in pairs(f.zones) do
      if id ~= 0 then
        add_zone_row(id, z.name, z.color or {r=1,g=1,b=1,a=1})
      end
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

-- Event handlers
ui.events = {}

-- Handler function implementations
function handlers.toggle_main_frame(e)
  local player = game.get_player(e.player_index)
  if player then
    toggle_main_frame(player)
  end
end

function handlers.properties_open(e)
  local player = game.get_player(e.player_index)
  if not player then return end
  local g = backend.get_grid(player.force.index)
  create_dialog(player, {
    name = "zp_properties_dialog",
    title = "Properties",
    confirm_name = "zp_prop_confirm",
    cancel_name = "zp_prop_cancel",
    confirm_handler = handlers.prop_confirm,
    cancel_handler = handlers.prop_cancel,
    parent = player.gui.center,
    children = {
      {
        type = "flow", direction = "horizontal",
        children = {
          { type = "label", caption = "Width" },
          { type = "empty-widget", style_mods = { minimal_width = 8, horizontally_stretchable = true } },
          { type = "textfield", name = "zp_prop_width", text = tostring(g.width or 32), style_mods = { width = 100} }
        }
      },
      {
        type = "flow", direction = "horizontal",
        children = {
          { type = "label", caption = "Height" },
          { type = "empty-widget", style_mods = { minimal_width = 8, horizontally_stretchable = true } },
          { type = "textfield", name = "zp_prop_height", text = tostring(g.height or 32), style_mods = { width = 100} }
        }
      },
      {
        type = "flow", direction = "horizontal",
        children = {
          { type = "label", caption = "X offset" },
          { type = "empty-widget", style_mods = { minimal_width = 8, horizontally_stretchable = true } },
          { type = "textfield", name = "zp_prop_x_offset", text = tostring(g.x_offset or 0), style_mods = { width = 100} }
        }
      },
      {
        type = "flow", direction = "horizontal",
        children = {
          { type = "label", caption = "Y offset" },
          { type = "empty-widget", style_mods = { minimal_width = 8, horizontally_stretchable = true } },
          { type = "textfield", name = "zp_prop_y_offset", text = tostring(g.y_offset or 0), style_mods = { width = 100} }
        }
      },
      { type = "checkbox", name = "zp_prop_reproject", state = false, caption = "Reproject existing cells" }
    }
  })
end

function handlers.visibility_open(e)
  local player = game.get_player(e.player_index)
  if not player then return end
  local idx = backend.get_boundary_opacity_index and backend.get_boundary_opacity_index(player.index) or 0
  local dlg = create_dialog(player, {
    name = "zp_visibility_dialog",
    title = "Visibility",
    confirm_name = "zp_visibility_confirm",
    cancel_name = "zp_visibility_cancel",
    confirm_handler = handlers.visibility_confirm,
    cancel_handler = handlers.visibility_cancel,
    parent = player.gui.center,
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
            tooltip = "[font=default-bold]Decrease visibility[/font]\n[img=utility/enter] Ctrl+Shift+S"
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
            tooltip = "[font=default-bold]Increase visibility[/font]\n[img=utility/enter] Ctrl+Shift+W"
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
  local dlg = player.gui.center["zp_visibility_dialog"]
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

handlers.visibility_cancel = make_cancel_handler({ dialog_name = "zp_visibility_dialog", get_parent = function(p) return p.gui.center end })

handlers.visibility_confirm = make_confirm_handler({
  dialog_name = "zp_visibility_dialog",
  get_parent = function(p) return p.gui.center end,
  on_confirm = function(e, dlg, player)
    local idx = dlg.tags and tonumber(dlg.tags.visibility_index)
    backend.set_player_visibility(player.index, { index = idx })
  end
})

handlers.prop_cancel = make_cancel_handler({ dialog_name = "zp_properties_dialog", get_parent = function(p) return p.gui.center end })

handlers.prop_confirm = make_confirm_handler({
  dialog_name = "zp_properties_dialog",
  get_parent = function(p) return p.gui.center end,
  on_confirm = function(e, dlg, player)
    local g = backend.get_grid(player.force.index)
    local width_elem = find_child(dlg, "zp_prop_width")
    local height_elem = find_child(dlg, "zp_prop_height")
    local x_offset_elem = find_child(dlg, "zp_prop_x_offset")
    local y_offset_elem = find_child(dlg, "zp_prop_y_offset")
    local reproject_elem = find_child(dlg, "zp_prop_reproject")
    local new_props = {
      width = to_number(width_elem and width_elem.text or "", g.width or 32),
      height = to_number(height_elem and height_elem.text or "", g.height or 32),
      x_offset = to_number(x_offset_elem and x_offset_elem.text or "", g.x_offset or 0),
      y_offset = to_number(y_offset_elem and y_offset_elem.text or "", g.y_offset or 0),
    }
    local reproject = (reproject_elem and reproject_elem.state) or false
    backend.set_grid(player.force.index, player.index, new_props, { reproject = reproject })
  end
})

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
    local pstate = ensure_player_ui_state(player.index)
    pstate.selected_tool = "rect"
  end
end

function handlers.zone_add(e)
  local player = game.get_player(e.player_index)
  if not player then return end
  local dlg = create_dialog(player, {
    name = "zp_zone_dialog",
    title = "Add Zone",
    confirm_name = "zp_zone_confirm",
    cancel_name = "zp_zone_cancel",
    confirm_handler = handlers.zone_confirm,
    cancel_handler = handlers.zone_cancel,
    parent = player.gui.center,
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
  dlg.tags = { mode = "add" }
end

handlers.zone_cancel = make_cancel_handler({ dialog_name = "zp_zone_dialog", get_parent = function(p) return p.gui.center end })

handlers.zone_confirm = make_confirm_handler({
  dialog_name = "zp_zone_dialog",
  get_parent = function(p) return p.gui.center end,
  on_confirm = function(e, dlg, player)
    local name_elem = find_child(dlg, "zp_zone_name")
    local name = name_elem and name_elem.text or ""
    local r_elem = find_child(dlg, "zp_color_r")
    local g_elem = find_child(dlg, "zp_color_g")
    local b_elem = find_child(dlg, "zp_color_b")
    local r = (r_elem and r_elem.slider_value)
    local g = (g_elem and g_elem.slider_value)
    local b = (b_elem and b_elem.slider_value)
    local color = { r = r/255, g = g/255, b = b/255, a = 1 }
    backend.add_zone(player.force.index, player.index, name, color)
  end
})

function handlers.zone_name_open(e)
  local player = game.get_player(e.player_index)
  if not player then return end
  local id = extract_zone_id(e.element.name, "^zp_zone_name_(%d+)$")
  if not id then return end
  local f = backend.get_force(player.force.index)
  local z = f.zones[id]
  local dlg = create_dialog(player, {
    name = "zp_zone_name_dialog",
    title = "Edit Zone Name",
    confirm_name = "zp_name_confirm",
    cancel_name = "zp_name_cancel",
    confirm_handler = handlers.name_confirm,
    cancel_handler = handlers.name_cancel,
    parent = player.gui.center,
    children = {
      {
        type = "flow", direction = "horizontal",
        children = {
          { type = "label", caption = "Name" },
          { type = "textfield", name = "zp_zone_name_field", text = z and z.name or "", icon_selector = true }
        }
      }
    }
  })
  dlg.tags = { zone_id = id }
end

function handlers.zone_color_open(e)
  local player = game.get_player(e.player_index)
  if not player then return end
  local id = extract_zone_id(e.element.name, "^zp_zone_color_(%d+)$")
  if not id then return end
  local f = backend.get_force(player.force.index)
  local z = f.zones[id]
  local col = z and z.color or {r=1,g=1,b=1,a=1}
  local dlg = create_dialog(player, {
    name = "zp_zone_color_dialog",
    title = "Edit Zone Color",
    confirm_name = "zp_color_confirm",
    cancel_name = "zp_color_cancel",
    confirm_handler = handlers.color_confirm,
    cancel_handler = handlers.color_cancel,
    parent = player.gui.center,
    children = {
      build_color_picker(col.r, col.g, col.b, handlers.color_slider_changed)
    }
  })
  dlg.tags = { zone_id = id }
end

function handlers.zone_delete(e)
  local player = game.get_player(e.player_index)
  if not player then return end
  local id = extract_zone_id(e.element.name, "^zp_zone_delete_(%d+)$")
  if not id then return end
  backend.delete_zone(player.force.index, player.index, id, 0)
  -- UI rebuild triggered by backend notification
end

handlers.name_cancel = make_cancel_handler({ dialog_name = "zp_zone_name_dialog", get_parent = function(p) return p.gui.center end })

handlers.name_confirm = make_confirm_handler({
  dialog_name = "zp_zone_name_dialog",
  get_parent = function(p) return p.gui.center end,
  on_confirm = function(e, dlg, player)
    local zone_id = dlg.tags and tonumber(dlg.tags.zone_id)
    if not zone_id then 
      return
    end
    local f = backend.get_force(player.force.index)
    local z = f.zones[zone_id]
    local name_elem = find_child(dlg, "zp_zone_name_field")
    local new_name = name_elem and name_elem.text or (z and z.name) or ""
    local col = z and z.color or {r=1,g=1,b=1,a=1}
    backend.edit_zone(player.force.index, player.index, zone_id, new_name, col)
  end
})

handlers.color_cancel = make_cancel_handler({ dialog_name = "zp_zone_color_dialog", get_parent = function(p) return p.gui.center end })

handlers.color_confirm = make_confirm_handler({
  dialog_name = "zp_zone_color_dialog",
  get_parent = function(p) return p.gui.center end,
  on_confirm = function(e, dlg, player)
    local zone_id = dlg.tags and tonumber(dlg.tags.zone_id)
    if not zone_id then 
      return
    end
    local f = backend.get_force(player.force.index)
    local z = f.zones[zone_id]
    local r_elem = find_child(dlg, "zp_color_r")
    local g_elem = find_child(dlg, "zp_color_g")
    local b_elem = find_child(dlg, "zp_color_b")
    local r = (r_elem and r_elem.slider_value) or 255
    local g = (g_elem and g_elem.slider_value) or 255
    local b = (b_elem and b_elem.slider_value) or 255
    local color = { r = r/255, g = g/255, b = b/255, a = (z and z.color and z.color.a) or 1 }
    local name = z and z.name or ""
    backend.edit_zone(player.force.index, player.index, zone_id, name, color)
  end
})

function handlers.color_slider_changed(e)
  local player = game.get_player(e.player_index)
  if not player then return end
  local element = e.element
  if not element or not element.valid then return end
  if element.name ~= "zp_color_r" and element.name ~= "zp_color_g" and element.name ~= "zp_color_b" then
    return
  end
  local center = player.gui.center
  local dlg = center["zp_zone_dialog"]
  if dlg and dlg.valid then
    update_color_preview_for_dialog(dlg)
    return
  end
  dlg = center["zp_zone_color_dialog"]
  if dlg and dlg.valid then
    update_color_preview_for_dialog(dlg)
  end
end

function handlers.zone_row_select(e)
  local player = game.get_player(e.player_index)
  if not player then return end
  local id = extract_zone_id(e.element.name, "^zp_zone_select_(%d+)$")
  if not id then return end
  local pstate = ensure_player_ui_state(player.index)
  pstate.selected_zone_id = id
  -- Rebuild to update selection highlight immediately
  ui.rebuild_player(player.index, "zone-selected")
end

-- Register all handlers with flib (for future use with flib_gui.add)
flib_gui.add_handlers(handlers)

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

-- Hotkey handlers
ui.events["zp-select-rect-tool"] = handlers.select_tool_rect
ui.events["zp-visibility-increase"] = handlers.visibility_higher
ui.events["zp-visibility-decrease"] = handlers.visibility_lower

-- GUI event routing - flib handles almost everything via tags
-- We only need to route the toggle button (created by mod-gui, not flib)
function ui.events.on_gui_click(event)
  local element = event.element
  if not element or not element.valid then return end
  
  -- Toggle button (created by mod-gui, not flib)
  if element.name == TOGGLE_BUTTON_NAME then
    handlers.toggle_main_frame(event)
  end
  -- All other buttons are handled by flib via tags
end

-- Handle escape key on dialogs
function ui.events.on_gui_closed(event)
  local player = game.get_player(event.player_index)
  if not player or not player.valid then return end
  
  -- When player presses escape on a dialog, close it
  local parent = player.gui.center
  local dialog_names = {
    "zp_properties_dialog",
    "zp_zone_dialog",
    "zp_zone_name_dialog",
    "zp_zone_color_dialog",
    "zp_visibility_dialog",
  }
  for _, name in pairs(dialog_names) do
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
  
  -- When player presses enter on a dialog, confirm it
  local parent = player.gui.center
  
  -- Map dialog names to their confirm handlers
  local dialog_handlers = {
    zp_properties_dialog = handlers.prop_confirm,
    zp_zone_dialog = handlers.zone_confirm,
    zp_zone_name_dialog = handlers.name_confirm,
    zp_zone_color_dialog = handlers.color_confirm,
    zp_visibility_dialog = handlers.visibility_confirm,
  }
  
  for dialog_name, confirm_handler in pairs(dialog_handlers) do
    local dlg = parent[dialog_name]
    if dlg and dlg.valid then
      -- Call the confirm handler
      confirm_handler({ player_index = event.player_index, element = dlg })
      return
    end
  end
end

-- All value_changed and checked_state_changed events are handled by flib via tags

return ui

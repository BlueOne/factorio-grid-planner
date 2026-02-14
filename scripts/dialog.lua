-- Dialog system module
--- Provides a centralized dialog registry and generic handler system to simplify creating and managing dialogs across the mod. Dialogs are defined by registering a name and handlers, then created with a standard structure (header, content, confirm button) using the registered name to link them together. The system handles confirming and canceling dialogs and ensuring only one dialog can be open at a time. As usual in factorio gui, you can pass custom data (primitive types) through tags.
---
--- Usage Example:
--- In your mod's control.lua:
--- local dialog = require("scripts.dialog")
--- dialog.register("my_dialog", {
---   on_confirm = function(dlg, player)
---    -- Handle confirm action
---    local textfield = dlg.input
---    game.print(dlg.tags.some_value .. ", " .. textfield.text)
---  end
--- })
--- Then create the dialog from anywhere:
--- dialog.create(player, {
---   name = "my_dialog",
---   title = "My Dialog",
---   tags = { some_value = "Hello" },
---  children = {
---   { type = "label", caption = "This is a dialog" },
---  { type = "textfield", name = "input", text = "World" },
---  }
--- })
--- 

local dialog = {}
local flib_gui = require("__flib__.gui")

-- Dialog registry - stores dialog names and their handlers
local DIALOG_REGISTRY = {}

---Register a dialog with its handlers
---@param name string Dialog element name
---@param handlers { on_confirm: fun(dlg: LuaGuiElement, player: LuaPlayer)|nil, on_cancel: fun(dlg: LuaGuiElement, player: LuaPlayer)|nil }
function dialog.register(name, handlers)
  if DIALOG_REGISTRY[name] then
    error("Dialog '" .. name .. "' is already registered. Use a unique dialog name.")
  end
  DIALOG_REGISTRY[name] = handlers or {}
end

---Get a registered dialog's handlers
---@param name string Dialog element name
---@return table|nil
function dialog.get_registry(name)
  return DIALOG_REGISTRY[name]
end

---Get all registered dialog names
---@return table
function dialog.get_all_names()
  local names = {}
  for name, _ in pairs(DIALOG_REGISTRY) do
    table.insert(names, name)
  end
  return names
end

-- Handler functions for flib dispatch
local handlers = {}

-- Generic handler for dialog cancel buttons
function handlers.dialog_cancel(e)
  local player = game.get_player(e.player_index)
  if not player then return end
  local dialog_name = e.element.tags and e.element.tags.dialog_name
  if not dialog_name then return end
  local registry_entry = DIALOG_REGISTRY[dialog_name] or {}
  local dlg = player.gui.screen[dialog_name]
  if dlg and dlg.valid then
    if registry_entry.on_cancel then
      registry_entry.on_cancel(dlg, player)
    end
    dlg.destroy()
  end
end

-- Generic handler for dialog confirm buttons
function handlers.dialog_confirm(e)
  local player = game.get_player(e.player_index)
  if not player then return end
  local dialog_name = e.element.tags and e.element.tags.dialog_name
  if not dialog_name then return end
  local registry_entry = DIALOG_REGISTRY[dialog_name] or {}
  local dlg = player.gui.screen[dialog_name]
  if dlg and dlg.valid then
    if registry_entry.on_confirm then
      registry_entry.on_confirm(dlg, player)
    end
    dlg.destroy()
  end
end

-- Helper: close any open dialogs except the one being opened
---@param parent LuaGuiElement
---@param keep_name string|nil
local function close_other_dialogs(parent, keep_name)
  if not parent or not parent.valid then return end
  for name, _ in pairs(DIALOG_REGISTRY) do
    if name ~= keep_name then
      local dlg = parent[name]
      if dlg and dlg.valid then
        dlg.destroy()
      end
    end
  end
end


---Create a standard dialog with header (title + close), content, and bottom confirm button.
---@class ZP.DialogOpts
---@field name string Dialog element name
---@field title string Dialog title
---@field parent LuaGuiElement|nil Parent GUI element (defaults to player.gui.screen)
---@field children table[] Child element definitions
---@field location GuiLocation|nil Optional location to display the dialog (from on_gui_click.event.cursor_display_location)
---@param player LuaPlayer
---@param opts ZP.DialogOpts
---@return LuaGuiElement dialog, table elements
function dialog.create(player, opts)
  local parent = opts.parent or player.gui.screen
  -- Get handlers from registry
  local registry_entry = DIALOG_REGISTRY[opts.name] or {}

  close_other_dialogs(parent, opts.name)
  -- destroy any existing
  local existing = parent[opts.name]
  if existing and existing.valid then
    if registry_entry.on_cancel then
      registry_entry.on_cancel(existing, player)
    end
    existing.destroy()
  end
  
  
  local children = {
    -- Header: title + spacer + close
    {
      type = "flow",
      direction = "horizontal",
      children = {
        { type = "label", caption = opts.title or "", style = "frame_title" },
        { type = "empty-widget", name = "drag_bar", style_mods = { horizontally_stretchable = true }, style="flib_titlebar_drag_handle" },
        {
          type = "sprite-button",
          name = opts.name .. "_cancel",
          sprite = "utility/close",
          style = "frame_action_button",
          handler = handlers.dialog_cancel,
          tags = { dialog_name = opts.name }
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

  -- Bottom confirm row (only if on_confirm provided)
  if registry_entry.on_confirm then
    table.insert(children, {
      type = "flow",
      direction = "horizontal",
      children = {
        { type = "empty-widget", style_mods = { horizontally_stretchable = true } },
        {
          type = "sprite-button",
          name = opts.name .. "_confirm",
          sprite = "utility/check_mark",
          style = "gp_icon_button_green",
          handler = handlers.dialog_confirm,
          tags = { dialog_name = opts.name }
        }
      }
    })
  end

  -- Build dialog using flib_gui.add
  local elems, dlg = flib_gui.add(parent, {
    type = "frame",
    name = opts.name,
    direction = "vertical",
    auto_center = true,
    children = children
  })
  dlg.children[1].drag_bar.drag_target = dlg
    -- If the caller provided a display location (from on_gui_click.event.cursor_display_location), apply it
    if opts.location then
      dlg.location = opts.location
    end

  player.opened = dlg
  return dlg, elems
end

flib_gui.add_handlers(handlers)

return dialog

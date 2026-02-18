

-- Utils
EventHandler = require("__core__/lualib/event_handler")
flib_gui = require("__flib__.gui")
EventHandler.add_lib(flib_gui)

Util = require("__core__/lualib/util") util = Util
Shared = require("scripts/shared") shared = Shared

-- Util = require("scripts/util") util = Util
-- EventHandler.add_lib(Util)

Backend = require("scripts/backend") backend = Backend
EventHandler.add_lib(Backend)

Ui = require("scripts/ui") ui = Ui
EventHandler.add_lib(Ui)

Render = require("scripts/render") render = Render

Tools = require("scripts/tools") tools = Tools
EventHandler.add_lib(Tools)

Migrations = require("scripts/migrations") migrations = Migrations
EventHandler.add_lib(Migrations)


pcall(require, "scripts/tests")

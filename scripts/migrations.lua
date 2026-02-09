
local Migrations = {}

render = require("scripts/render")

Migrations.migration_functions = {
    -- example
    -- ["0.1.0"] = function()
    --   -- do migration stuff here
    -- end,
    ["0.1.0"] = function()
      -- Migration to 0.1.1: destroy all existing render objects and force a full redraw.
      if storage and storage.zp_render and storage.zp_render.forces then
        for _, fstate in pairs(storage.zp_render.forces) do
          for _, surf in pairs(fstate.surfaces or {}) do
            for _, cell in pairs(surf.cells or {}) do
              for _, variant in pairs(cell.variants or {}) do
                if variant.game and variant.game.valid then variant.game.destroy() end
                if variant.chart and variant.chart.valid then variant.chart.destroy() end
              end
            end
            for _, corner_list in pairs(surf.corners or {}) do
              for _, corner in pairs(corner_list or {}) do
                for _, variant in pairs(corner.variants or {}) do
                  if variant.game and variant.game.valid then variant.game.destroy() end
                  if variant.chart and variant.chart.valid then variant.chart.destroy() end
                end
              end
            end
          end
        end
        -- clear render storage so renderer recreates clean state
        storage.zp_render = nil
      end
      

      -- Trigger renderer to rebuild for all forces
      if storage.zp and storage.zp.forces then
        for force_index, _ in pairs(storage.zp.forces) do
          render.on_grid_changed(force_index)
        end
      end
    end,
}

local function version_greater(v1, v2)
  local function parse_version(v)
    local major, minor, patch = v:match("^(%d+)%.(%d+)%.(%d+)$")
    return tonumber(major), tonumber(minor), tonumber(patch)
  end
  local major1, minor1, patch1 = parse_version(v1)
  local major2, minor2, patch2 = parse_version(v2)
  if major1 ~= major2 then
    return major1 > major2
  elseif minor1 ~= minor2 then
    return minor1 > minor2
  else
    return patch1 > patch2
  end
end

function Migrations.on_configuration_changed(event)
  if not event or not event.mod_changes or not event.mod_changes["zone-planner"] then return end
  local old_version = event.mod_changes["zone-planner"].old_version or "0.0.0"
  local new_version = event.mod_changes["zone-planner"].new_version
  if new_version == old_version or new_version == nil then return end

  -- run all migration functions between old_version (exclusive) and new_version (inclusive)
  for v, f in pairs(Migrations.migration_functions) do
    if (not version_greater(old_version, v)) and version_greater(new_version, v) then
      log("Running migration for version " .. v)
      game.print("[Zone-Planner]: Running migration for version " .. v)
      f()
    end
  end
end

return Migrations

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
    ["0.1.1"] = function()
      -- Migration to 0.1.2: convert grid (per-force) to grids (per-force-per-surface)
      if storage and storage.gp and storage.gp.forces then
        for force_index, fstate in pairs(storage.gp.forces) do
          if fstate.grid then
            -- Old structure has a single grid per force
            local old_grid = fstate.grid
            fstate.grids = {}
            
            -- Copy grid to all surfaces that have data
            if fstate.images then
              for surface_index, _ in pairs(fstate.images) do
                fstate.grids[surface_index] = {
                  width = old_grid.width,
                  height = old_grid.height,
                  x_offset = old_grid.x_offset,
                  y_offset = old_grid.y_offset,
                }
              end
            end
            
            -- If no surfaces have data, create a default grid for surface 1 (nauvis)
            if not next(fstate.grids) then
              fstate.grids[1] = {
                width = old_grid.width,
                height = old_grid.height,
                x_offset = old_grid.x_offset,
                y_offset = old_grid.y_offset,
              }
            end
            
            -- Remove old grid property
            fstate.grid = nil
          end
        end
        log("[Grid-Planner] Migration 0.1.1->0.1.2: Converted grid structure to per-surface grids")

        -- Rebuild all player uis
        for _, player in pairs(game.players) do
          ui.rebuild_player(player.index, "migration")
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
  if not event or not event.mod_changes or not event.mod_changes["grid-planner"] then return end
  local old_version = event.mod_changes["grid-planner"].old_version or "0.0.0"
  local new_version = event.mod_changes["grid-planner"].new_version
  if new_version == old_version or new_version == nil then return end

  -- run all migration functions between old_version (exclusive) and new_version (inclusive)
  for v, f in pairs(Migrations.migration_functions) do
    if (not version_greater(old_version, v)) and version_greater(new_version, v) then
      log("Running migration for version " .. v)
      game.print("[Grid-Planner]: Running migration for version " .. v)
      f()
    end
  end
end

return Migrations

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
          ---@diagnostic disable-next-line: inject-field
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
  ["0.1.2"] = function()
    -- Clear undo queue as it was completely changed.
    if storage.gp and storage.gp.players then
      for _, pdata in pairs(storage.gp.players) do
        pdata.undo = {}
        pdata.redo = {}
      end
      for _, player in pairs(game.players) do
        ui.rebuild_player(player.index, "migration")
      end
    end
  end,
  ["0.1.3"] = function()
    -- Migration to 0.2.0: convert grids + images per surface into layers per surface.
    if not (storage and storage.gp and storage.gp.forces) then return end

    for force_index, fstate in pairs(storage.gp.forces) do
      if fstate.grids or fstate.images then
        local old_grids  = fstate.grids  or {}
        local old_images = fstate.images or {}

        -- Collect all surface indices mentioned in grids or images
        local all_surfaces = {}
        for si, _ in pairs(old_grids)  do all_surfaces[si] = true end
        for si, _ in pairs(old_images) do all_surfaces[si] = true end

        fstate.surfaces = {}
        for surface_index, _ in pairs(all_surfaces) do
          local g = old_grids[surface_index] or {
            width = 8, height = 8, x_offset = 0, y_offset = 0
          }
          local img = old_images[surface_index]
          local cells = (img and img.cells) or {}

          fstate.surfaces[surface_index] = {
            next_layer_id = 2,
            layers = {
              [1] = {
                id = 1,
                name = "Layer 1",
                order = 1,
                visible = true,
                grid = { width = g.width, height = g.height, x_offset = g.x_offset, y_offset = g.y_offset },
                cells = cells,
              }
            }
          }
        end

        -- If no surfaces had data, create a default empty surface 1
        if not next(fstate.surfaces) then
          fstate.surfaces[1] = {
            next_layer_id = 2,
            layers = {
              [1] = {
                id = 1, name = "Layer 1", order = 1, visible = true,
                grid = { width = 8, height = 8, x_offset = 0, y_offset = 0 },
                cells = {},
              }
            }
          }
        end

        ---@diagnostic disable-next-line: inject-field
        fstate.grids  = nil
        ---@diagnostic disable-next-line: inject-field
        fstate.images = nil
        log(("[Grid-Planner] Migration 0.1.3->0.2.0: Converted force %d to layers structure"):format(force_index))
      end
    end

    -- Reset player active layer tracking and clear undo/redo (command format changed)
    if storage.gp.players then
      for _, pdata in pairs(storage.gp.players) do
        pdata.active_layer_ids = {}
        pdata.undo = {}
        pdata.redo = {}
      end
    end

    -- Migrate render storage from flat structure (surfaces -> cells + corners)
    -- to layered structure (surfaces -> layers -> cells + corners).
    -- All existing render objects are moved into layer 1 to match the data migration above.
    if storage.gp_render and storage.gp_render.forces then
      for _, old_fstate in pairs(storage.gp_render.forces) do
        for _, surf in pairs(old_fstate.surfaces or {}) do
          surf.layers = {
            [1] = {
              cells   = surf.cells   or {},
              corners = surf.corners or {},
            }
          }
          ---@diagnostic disable-next-line: inject-field
          surf.cells   = nil
          ---@diagnostic disable-next-line: inject-field
          surf.corners = nil
        end
      end
    end

    -- Rebuild UI for all players
    for _, player in pairs(game.players) do
      ui.rebuild_player(player.index, "migration")
    end

    game.print("[Grid-Planner]: Migration 0.1.3->0.2.0: Layers feature added. Existing data converted to Layer 1.")
  end
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

  -- collect and sort migration keys ascending so they always run in version order
  local versions = {}
  for v in pairs(Migrations.migration_functions) do versions[#versions+1] = v end
  table.sort(versions, function(a, b) return version_greater(b, a) end)

  -- run all migration functions between old_version (inclusive) and new_version (exclusive)
  for _, v in ipairs(versions) do
    if (not version_greater(old_version, v)) and version_greater(new_version, v) then
      log("Running migration for version " .. v)
      game.print("[Grid-Planner]: Running migration for version " .. v)
      Migrations.migration_functions[v]()
    end
  end
end

return Migrations
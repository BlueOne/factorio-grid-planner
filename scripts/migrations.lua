
local Migrations = {}
Migrations.migration_functions = {
    -- example
    -- ["0.1.0"] = function()
    --   -- do migration stuff here
    -- end,
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

Migrations.events = {
  on_configuration_changed = function()
    local old_version = storage.migrations and storage.migrations.version or Version
    storage.migrations = storage.migrations or {}
    storage.migrations.version = Version

    -- run all migration functions between old_version and Version, in order
    for v, f in pairs(Migrations.migration_functions) do
      if version_greater(v, old_version) and version_greater(Version, v) then
        log("Running migration for version " .. v)
        game.print("[Zone-Planner]: Running migration for version " .. v)
        f()
      end
    end
  end,
}
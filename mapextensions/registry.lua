
--- Contains all handlers for all extensions
---@type table<string, SerializationCallbacks>
local registry = require("mapextensions.sections")

return {
  registry = registry,
}
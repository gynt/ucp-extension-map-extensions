
local constants = require("mapextensions.constants")

local memory = require("mapextensions.memory")

local game = require('mapextensions.game')

local registry = require("mapextensions.registry").registry

local callbacks = require("mapextensions.callbacks")

--- The api we return from this extension
---@class mapextensions
local api = {}

api = {

  enable = function(self, config)
    game.enlargeMemoryAllocation(constants.MAP_MEMORY_SIZE)

    memory.initialize()

    game.registerReadWriteSavHooks(memory.customMapSectionInfoArray, constants.CUSTOM_SECTION_ID, callbacks)

  end,

  disable = function(self, config)
    
  end,
}

---Register custom section in .sav files
---@param self table this module
---@param extensionName string extension name of the extension registering the section
---@param serializationCallbacks table functions for (de)serialization of data
---@return void
function api.registerSection(self, extensionName, serializationCallbacks)
  if registry[extensionName] ~= nil then 
    error(debug.traceback(string.format("callbacks already registered for: %s", extensionName))) 
  end

  registry[extensionName] = serializationCallbacks
end

return api
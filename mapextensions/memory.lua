---@module "memory"
local memory = {}

local constants = require("mapextensions.constants")
local helpers = require("mapextensions.helpers")
local game = require("mapextensions.game")

--- Variable to hold the address of the custom section
memory.customSectionAddress = nil

--- Lua object containing the descriptive info of the map parsing entry object
memory.customSectionInfoObject = nil

--- Variable to hold the address of our custom array
memory.customMapSectionInfoArray = nil

function memory.initialize() 
  memory.customSectionAddress = core.allocate(constants.CUSTOM_SECTION_SIZE, true)

  memory.customSectionInfoObject = helpers.MapSectionAddress:new(memory.customSectionAddress, constants.CUSTOM_SECTION_SIZE, true, constants.CUSTOM_SECTION_ID)
  
  memory.customMapSectionInfoArray = game.createCustomSectionInfoArray(memory.customSectionInfoObject)
end

return memory
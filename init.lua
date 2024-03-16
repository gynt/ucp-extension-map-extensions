
--- When starting to read or write a map/sav file, set maximum length to 128 MB
local MAP_MEMORY_SIZE = 128 * 1000 * 1000
--- Max 100 MB
local CUSTOM_SECTION_SIZE = 100 * 1000 * 1000

local customSectionAddress
local customSectionInfoObject

--- Claim a section id not used by the game
local CUSTOM_SECTION_ID = 1337

--- Variable to hold the address of our custom array
local customMapSectionInfoArray

local helpers = require('helpers')

local game = require('game')

local luamemzip = require("luamemzip.dll")

local originalMapSectionInfoArray = core.AOBScan("? ? ? ? 00 00 00 00 20 74 02 00 01 00 e9 03 ? ? ? ? 00 00 00 00 20 74 02 00 01 00 09 04 ? ? ? ? 00 00 00 00 20 74 02 00 01 00 ea 03 ? ? ? ? 00 00 00 00 40 e8 04 00 01 00 eb 03")



local registry = {}

local api

-- If the game saves the map state
local function onSerialize()
  for extensionName, callbacks in pairs(registry) do
    callbacks:serialize(some_handle)
  end

  -- Now the zip is complete, so we need to write the address and size, or a byte stream,
  -- to the memory location the game will process the bytes from to store it in the file
end

-- An object of this type is supplied by the extension
local SerializationCallbacks = {

  -- When called, the extension should use the handle to serialize all information
  serialize = function(self, handle) end,

  -- When called, the extension should use the handle to deserialize all information
  -- The handle can be stored somewhere? Or is the data really handed over?
  deserialize = function(self, handle) end,

}

-- This is backed by the library https://github.com/kuba--/zip
local createWriteHandle = function(memoryZip)

  return {
    
    putContents = function(self, relativePath, data) 
      local status, code, message = memoryZip:open_entry(relativePath)
      status, code, message = memoryZip:write_entry(data)
      status, code, message = memoryZip:close_entry()
    end,

  }

end

local createReadHandle = function(memoryZip)
  
  return {
    
    getContents = function(self, relativePath) 
      local result

      local status, code, message = memoryZip:open_entry(relativePath)
      result, code, message = memoryZip:read_entry()
      status, code, message = memoryZip:close_entry()

      return result
    end,

  }

end

local wrapHandle = function(handle, prefix)

  return {

    putContents = function(self, relativePath, data)
      return handle:putContents(prefix .. '/' .. relativePath, data)
    end,

    getContents = function(self, relativePath)
      return handle:getContents(prefix .. '/' .. relativePath)
    end,

  }

end

local Deproxy = extensions.proxies.Deproxy

local interface = {

  beforeReadSav = function()
    log(DEBUG, "before read sav")
  end,
  
  afterReadSav = function()
    log(DEBUG, "after read sav")
  end,
  
  beforeWriteSav = function()
    log(DEBUG, "before write sav")
    
    local zipHandle = luamemzip:MemoryZip(nil, nil, 'w')

    for extensionName, callbacks in pairs(registry) do
      callbacks:serialize(wrapHandle(createWriteHandle(zipHandle), extensionName))
    end

    local handle = createWriteHandle(zipHandle)
    handle:putContents("framework/ucp-config.yml", yaml.dump(Deproxy(USER_CONFIG)))
    
    local data, length = zipHandle:serialize()

    if data == nil or data == false then
      error("could not serialize zip")
    end

    if length > CUSTOM_SECTION_SIZE then
      error(string.format("data too long to store in file: %s", length))
    end

    customSectionInfoObject.size = length
    game.updateCustomSectionInfoObject(customMapSectionInfoArray, customSectionInfoObject)

    core.writeBytes(customSectionAddress, table.pack(string.byte(data, 1, length)))    

    local f = io.open("sav-custom-section-on-write.zip", 'wb')
    f:write(data)
    f:close()

  end,
  
  afterWriteSav = function()
    log(DEBUG, "after write sav")
  end,

}

api = {

  -- Returns a handle to the section, which is a zip in memory!
  registerSection = function(self, extensionName, serializationCallbacks)
    registry[extensionName] = serializationCallbacks
  end,

  enable = function(self, config)
    game.enlargeMemoryAllocation(MAP_MEMORY_SIZE)

    customSectionAddress = core.allocate(CUSTOM_SECTION_SIZE, true)

    customSectionInfoObject = helpers.MapSectionAddress:new(customSectionAddress, CUSTOM_SECTION_SIZE, true, CUSTOM_SECTION_ID)

    customMapSectionInfoArray = game.createCustomSectionInfoArray(originalMapSectionInfoArray, customSectionInfoObject)

    game.registerReadWriteSavHooks(originalMapSectionInfoArray, customMapSectionInfoArray, interface)

  end,
  disable = function(self, config)
    
  end,
}

return api
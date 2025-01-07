
--- When starting to read or write a map/sav file, set maximum length to 128 MB
local MAP_MEMORY_SIZE = 128 * 1000 * 1000

--- Max 100 MB
local CUSTOM_SECTION_SIZE = 100 * 1000 * 1000

--- Claim a section id not used by the game
local CUSTOM_SECTION_ID = 1337

--- No compression for now, let the game compress
local CUSTOM_SECTION_ZIP_COMPRESSION = nil

--- Variable to hold the address of the custom section
local customSectionAddress

--- Lua object containing the descriptive info of the map parsing entry object
local customSectionInfoObject

--- Variable to hold the address of our custom array
local customMapSectionInfoArray

local helpers = require('helpers')

local game = require('game')

---@class MemoryZip
---@field open_entry fun(self: MemoryZip, entryname: string):boolean, number, err
---@field read_entry fun(self: MemoryZip):boolean, number, err
---@field write_entry fun(self: MemoryZip, contents: string):boolean, number, err
---@field close_entry fun(self: MemoryZip):boolean, number, err
---@field close fun(self: MemoryZip):boolean, number, err
---@field serialize fun(self: MemoryZip):string, number Serialize and return data, length

---@class luamemzip
---@field MemoryZip fun(lib: luamemzip, data: string, compression: number|nil, mode:string):MemoryZip
local luamemzip = require("luamemzip.dll")

--- The api we return from this extension
---@class mapextensions
local api = {}



--- An object of this type should be supplied by the extension
---@class SerializationCallbacks
local SerializationCallbacks = {}

--- When called, the extension should use the handle to serialize all information
---@param self SerializationCallbacks this
---@param handle Handle the handle to serialize data
---@return void
function SerializationCallbacks.serialize(self, handle) end

--- When called, the extension should use the handle to deserialize all information
---@param self SerializationCallbacks this
---@param handle Handle the handle to deserialize data
---@return void
function SerializationCallbacks.deserialize(self, handle) end

local Deproxy = extensions.proxies.Deproxy

--- Contains all handlers for all extensions
---@type table<string, SerializationCallbacks>
local registry = {
  meta = {
    serialize = function(self, handle)
      handle:put("ucp-config.yml", yaml.dump(Deproxy(USER_CONFIG)))
      handle:put("extensions.yml", yaml.dump(Deproxy(USER_CONFIG['config-full']['load-order'])))

      local f = io.open("ucp/ucp-version.yml")
      local versionInfo = yaml.parse(f:read("*all"))
      handle:put("meta.yml", yaml.dump({
        version = '1.0.0',
        framework = versionInfo,
      }))
    end,

    deserialize = function(self, handle)
      local meta = yaml.parse(handle:get("meta.yml"))

      if meta == nil then
        error(debug.traceback("map file is missing meta information"))
      elseif meta.version ~= "1.0.0" then
        error(debug.traceback(string.format("map file was made using an unsupported version: %s", meta.version)))
      end

      local receivedConfig = handle:get("ucp-config.yml")
      local extensions = handle:get("extensions.yml")

      log(INFO, "map file was made using the following extensions:")
      log(INFO, '\n' .. extensions)

      log(INFO, "map file contained the following config:")
      log(INFO, '\n' .. receivedConfig)
    end,
  }
}

---Handle to serialize data
---@class WriteHandle
local WriteHandle = {}

---Put data into the .sav file
---@param self WriteHandle this
---@param path string path in the zip file to write to. Will be relative to the extension name
---@param data string the data to write
---@return void
function WriteHandle.put(self, path , data ) end

--- This is backed by the library https://github.com/gynt/luamemzip
---@param memoryZip table
---@param prefix string
---@return WriteHandle
local function createWriteHandle(memoryZip, prefix)

  if prefix == nil then prefix = "" else prefix = prefix .. "/" end

  return {
    
    put = function(self, path, data) 
      local status, code, message = memoryZip:open_entry(prefix .. path)
      if not status then error(debug.traceback(string.format("error in put('%s') open_entry(): %s %s", tostring(prefix .. path), tostring(code), tostring(message)))) end
      status, code, message = memoryZip:write_entry(data)
      if not status then error(debug.traceback(string.format("error in get('%s') write_entry(): %s %s", tostring(prefix .. path), tostring(code), tostring(message)))) end
      status, code, message = memoryZip:close_entry()
      if not status then error(debug.traceback(string.format("error in get('%s') close_entry(): %s %s", tostring(prefix .. path), tostring(code), tostring(message)))) end
    end,

  }

end


---Handle to serialize data
---@class ReadHandle
local ReadHandle = {}

---Get data from the .sav file
---@param self ReadHandle this
---@param path string path in the zip file to read from. Will be relative to the extension name
---@return void
function ReadHandle.get(self, path ) end

--- This is backed by the library https://github.com/gynt/luamemzip
---@param memoryZip MemoryZip
---@param prefix string
---@return ReadHandle
local function createReadHandle(memoryZip, prefix)

  if prefix == nil then prefix = "" else prefix = prefix .. "/" end
  
  return {
    
    get = function(self, path) 
      local result

      local status, code, message = memoryZip:open_entry(prefix .. path)
      if not status then error(debug.traceback(string.format("error in get('%s') open_entry(): %s %s", tostring(prefix .. path), tostring(code), tostring(message)))) end
      result, code, message = memoryZip:read_entry()
      if not result then error(debug.traceback(string.format("error in get('%s') read_entry(): %s %s", tostring(prefix .. path), tostring(code), tostring(message)))) end
      status, code, message = memoryZip:close_entry()
      if not status then error(debug.traceback(string.format("error in get('%s') close_entry(): %s %s", tostring(prefix .. path), tostring(code), tostring(message)))) end

      return result
    end,

  }

end

--- The interface from the low level game logic to the higher level
local interface

interface = {

  beforeReadSav = function()
    log(DEBUG, "before read sav")

    -- wipe it! Maybe not necessary because zip procedure simply stops reading?
    -- core.setMemory(customSectionAddress, 0, CUSTOM_SECTION_SIZE)
  end,
  
  afterReadDirectoryOfSav = function(info)
    log(DEBUG, "after read directory of sav file")

    -- At this point, the directory section of the sav file has been read, containing meta info about the file
    local length = info.size

    if length == 0 then
      log(DEBUG, "no custom section present")
    end

    if length > CUSTOM_SECTION_SIZE then
      error(debug.traceback(string.format("map/sav file contains more data than we have room for")))
    end

    customSectionInfoObject.size = length
    -- The size of the custom section is updated in memory to make the process quicker (not process 100MB)
    game.updateCustomSectionInfoObject(customMapSectionInfoArray, customSectionInfoObject)
  end,
  
  afterReadSav = function()
    log(DEBUG, "after read sav")

    if customSectionInfoObject.size <= 0 then
      log(DEBUG, "no custom section present")
      return
    end

    -- At this point, readSav has processed (decompressed) all sections, including the custom section
    local data = core.readString(customSectionAddress, customSectionInfoObject.size)

    local f = io.open("sav-custom-section-on-read.zip", 'wb')
    f:write(data)
    f:close()

    local zipHandle = luamemzip:MemoryZip(data, CUSTOM_SECTION_ZIP_COMPRESSION, 'r')

    for extensionName, callbacks in pairs(registry) do
      callbacks:deserialize(createReadHandle(zipHandle, extensionName))
    end
    
    zipHandle:close()
    
  end,
  
  beforeWriteSav = function()
    log(DEBUG, "before write sav")
    
    local zipHandle = luamemzip:MemoryZip(nil, CUSTOM_SECTION_ZIP_COMPRESSION, 'w')

    for extensionName, callbacks in pairs(registry) do
      callbacks:serialize(createWriteHandle(zipHandle, extensionName))
    end
    
    local data, length = zipHandle:serialize()
    zipHandle:close()

    if data == nil or data == false then
      error("could not serialize zip")
    end

    if length > CUSTOM_SECTION_SIZE then
      error(string.format("data too long to store in file: %s", length))
    end

    customSectionInfoObject.size = length
    -- The size of the custom section is updated in memory to make the process quicker (not process 100MB)
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

  enable = function(self, config)
    game.enlargeMemoryAllocation(MAP_MEMORY_SIZE)

    customSectionAddress = core.allocate(CUSTOM_SECTION_SIZE, true)

    customSectionInfoObject = helpers.MapSectionAddress:new(customSectionAddress, CUSTOM_SECTION_SIZE, true, CUSTOM_SECTION_ID)

    customMapSectionInfoArray = game.createCustomSectionInfoArray(customSectionInfoObject)

    game.registerReadWriteSavHooks(customMapSectionInfoArray, CUSTOM_SECTION_ID, interface)

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

local ptr_codeReadSavMallocSize = core.AOBScan("68 ? ? ? ? 89 44 24 14") + 1
local ptr_codeWriteSavMallocSize = core.AOBScan("68 ? ? ? ? 89 44 24 1C") + 1

core.writeCodeInteger(ptr_codeReadSavMallocSize, 100 * 1000 * 1000)
core.writeCodeInteger(ptr_codeWriteSavMallocSize, 100 * 1000 * 1000)

local function boolToNumber(b)
  if type(b) == "number" then
    if b == 0 or b == 1 then
      return b
    else
      error(debug.traceback(string.format("Not a bool: %s", b)))
    end
  end

  if b == false then 
    return 0 
  elseif b == true then
    return 1 
  else 
    error(debug.traceback(string.format("Not a bool: %s", b)))
  end
end

local MapSectionAddress = {

  sizeof = 16,

  new = function(self, address, size, compressed, id)
    local o = {
      address = address,
      size = size,
      compressed = compressed,
      id = id,
    }
    
    self.__index = self
    
    return setmetatable(o, self)
  end,

  serialize = function(self) 
    local bytes = {}

    for _, data in ipairs({
      core.itob(self.address),
      core.itob(0),
      core.itob(self.size),
      core.stob(boolToNumber(self.compressed)),
      core.stob(self.id),
    }) do
      for k, v in ipairs(data) do
        table.insert(bytes, v)
      end
    end

    return bytes
  end,

}

local DAT_mapSectionAddressArray = core.AOBScan("? ? ? ? 00 00 00 00 20 74 02 00 01 00 e9 03 ? ? ? ? 00 00 00 00 20 74 02 00 01 00 09 04 ? ? ? ? 00 00 00 00 20 74 02 00 01 00 ea 03 ? ? ? ? 00 00 00 00 40 e8 04 00 01 00 eb 03")
local mapSectionAddressArraySize = 1968
local entriesCount = 1968 / 123 -- of which the last is all 0s


local ptr_copyOfMapSectionAddressArray = core.allocate(mapSectionAddressArraySize + MapSectionAddress.sizeof, true)
local DAT_MapName = core.readInteger(core.AOBScan("8D 54 24 08 52 68 ? ? ? ? B9 ? ? ? ? E8 ? ? ? ? 83 3C 24 00") + 6)

-- Install the special thing such that our information is put in a .sav file
core.writeBytes(ptr_copyOfMapSectionAddressArray, core.readBytes(DAT_mapSectionAddressArray, mapSectionAddressArraySize))
core.writeBytes(ptr_copyOfMapSectionAddressArray + (122 * MapSectionAddress.sizeof), MapSectionAddress:new(DAT_MapName, 1000, false, 1337):serialize())

-- Hooks
-- read map or sav
core.detourCode(function(registers)
  if DAT_mapSectionAddressArray ~= core.readInteger(registers.ESP + 4) then error("argument is not what we expected") end
  
  print("readSav", string.format("%X", ptr_copyOfMapSectionAddressArray))
  core.writeInteger(registers.ESP + 4, ptr_copyOfMapSectionAddressArray)
  
  return registers
end, core.AOBScan("83 EC 0C 53 56 8B F1 8B 46 20"), 5)

-- write map or sav
core.detourCode(function(registers)
  if DAT_mapSectionAddressArray ~= core.readInteger(registers.ESP + 4) then error("argument is not what we expected") end
  
  print("writeSav", string.format("%X", ptr_copyOfMapSectionAddressArray))
  core.writeInteger(registers.ESP + 4, ptr_copyOfMapSectionAddressArray)
  
  print("writeSav", string.format("%X", core.readInteger(registers.ESP + 4)))
  
  return registers
end, core.AOBScan("83 EC 10 53 55 56 8B F1 8B 46 20"), 5)

-- on clear map sections before read map or sav
core.detourCode(function(registers)
  
  return registers
end, core.AOBScan("53 55 56 8B F1 57 33 FF 89 ? ? ? ? ? 89 ? ? ? ? ? 89 ? ? ? ? ? 89 ? ? ? ? ? E8 ? ? ? ?"), 5)



local registry = {}

local api

-- If the game saves the map state
function onSerialize()
  for extensionName, callbacks in pairs(registry) do
    callbacks:serialize(some_handle)
  end

  -- Now the zip is complete, so we need to write the address and size, or a byte stream,
  -- to the memory location the game will process the bytes from to store it in the file
end

-- An object of this type is supplied by the extension
SerializationCallbacks = {

  -- When called, the extension should use the handle to serialize all information
  serialize = function(self, handle) end,

  -- When called, the extension should use the handle to deserialize all information
  -- The handle can be stored somewhere? Or is the data really handed over?
  deserialize = function(self, handle) end,

}

-- This is backed by the library https://github.com/kuba--/zip
Handle = {
  putContents = function(self, relativePath, data) end,
  getContents = function(self, relativePath) end,
}

api = {

  -- Returns a handle to the section, which is a zip in memory!
  function registerSection(self, extensionName, serializationCallbacks)
    registry[extensionName] = serializationCallbacks
  end,

}

return api
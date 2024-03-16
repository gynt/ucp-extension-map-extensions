---@module game

local helpers = require('helpers')

local function enlargeMemoryAllocation(memorySize) 
    
  local ptr_codeReadSavMallocSize = core.AOBScan("68 ? ? ? ? 89 44 24 14") + 1
  local ptr_codeWriteSavMallocSize = core.AOBScan("68 ? ? ? ? 89 44 24 1C") + 1

  core.writeCodeInteger(ptr_codeReadSavMallocSize, memorySize)
  core.writeCodeInteger(ptr_codeWriteSavMallocSize, memorySize)
end

local function createCustomSectionInfoArray(originalArray, customSectionInfoObject)
  local mapSectionAddressArraySize = 1968
  local entriesCount = 1968 / 123 -- of which the last is all 0s


  local ptr_copyOfMapSectionAddressArray = core.allocate(mapSectionAddressArraySize + helpers.MapSectionAddress.sizeof, true)

  -- Install the special thing such that our information is put in a .sav file
  core.writeBytes(ptr_copyOfMapSectionAddressArray, core.readBytes(originalArray, mapSectionAddressArraySize))
  core.writeBytes(ptr_copyOfMapSectionAddressArray + (122 * helpers.MapSectionAddress.sizeof), customSectionInfoObject:serialize())

  return ptr_copyOfMapSectionAddressArray
end

local function updateCustomSectionInfoObject(ptr_copyOfMapSectionAddressArray, customSectionInfoObject)
  core.writeBytes(ptr_copyOfMapSectionAddressArray + (122 * helpers.MapSectionAddress.sizeof), customSectionInfoObject:serialize())
end

local function registerReadWriteSavHooks(originalMapSectionInfoArray, customMapSectionInfoArray, callbacks)
    
  -- Hooks
  -- read map or sav
  local ptr_FilePackagerObj = core.readInteger(core.AOBScan("B9 ? ? ? ? E8 ? ? ? ? B9 ? ? ? ? E8 ? ? ? ? 8B 44 24 14 ") + 1)

  local originalReadSav
  originalReadSav = core.hookCode(function(this, ptrMapSectionAddressArray)
    if originalMapSectionInfoArray ~= ptrMapSectionAddressArray then error("argument is not what we expected") end

    callbacks.beforeReadSav()
    
    local result = originalReadSav(this, customMapSectionInfoArray)

    callbacks.afterReadSav()

    return result

  end, core.AOBScan("83 EC 0C 53 56 8B F1 8B 46 20"), 2, CallingConvention.THISCALL, 5)

  -- write map or sav
  local originalWriteSav
  originalWriteSav = core.hookCode(function(this, ptrMapSectionAddressArray)
    if originalMapSectionInfoArray ~= ptrMapSectionAddressArray then error("argument is not what we expected") end

    callbacks.beforeWriteSav()
    
    local result = originalWriteSav(this, customMapSectionInfoArray)

    callbacks.afterWriteSav()

    return result

  end, core.AOBScan("83 EC 10 53 55 56 8B F1 8B 46 20"), 2, CallingConvention.THISCALL, 5)

  -- -- on clear map sections before read map or sav
  -- core.detourCode(function(registers)
    
  --   return registers
  -- end, core.AOBScan("53 55 56 8B F1 57 33 FF 89 ? ? ? ? ? 89 ? ? ? ? ? 89 ? ? ? ? ? 89 ? ? ? ? ? E8 ? ? ? ?"), 5)


  core.detourCode(function(registers) 

    local directoryDataAddress = ptr_FilePackagerObj + 36

    local uncompressedSizesArray = directoryDataAddress + 28

    local sectionIDArray = directoryDataAddress + 28 + (4*150) + (4*150)

    local sectionIDs = string.unpack("i", string.char(table.unpack(core.readBytes(sectionIDArray, 4*150))))



    callbacks.afterReadSavDirectory({
      
    })

    return registers 
  end, core.AOBScan("89 5E 24 89 54 24 20"), 7)
end

return {
  enlargeMemoryAllocation = enlargeMemoryAllocation,
  createCustomSectionInfoArray = createCustomSectionInfoArray,
  updateCustomSectionInfoObject = updateCustomSectionInfoObject,
  registerReadWriteSavHooks = registerReadWriteSavHooks,
}
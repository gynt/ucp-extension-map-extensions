local helpers = require('mapextensions.helpers')

local originalMapSectionInfoArray = core.AOBScan("? ? ? ? 00 00 00 00 20 74 02 00 01 00 e9 03 ? ? ? ? 00 00 00 00 20 74 02 00 01 00 09 04 ? ? ? ? 00 00 00 00 20 74 02 00 01 00 ea 03 ? ? ? ? 00 00 00 00 40 e8 04 00 01 00 eb 03")

local function enlargeMemoryAllocation(memorySize) 
    
  local ptr_codeReadSavMallocSize = core.AOBScan("68 ? ? ? ? 89 44 24 14") + 1
  local ptr_codeWriteSavMallocSize = core.AOBScan("68 ? ? ? ? 89 44 24 1C") + 1

  core.writeCodeInteger(ptr_codeReadSavMallocSize, memorySize)
  core.writeCodeInteger(ptr_codeWriteSavMallocSize, memorySize)
end

local function createCustomSectionInfoArray(customSectionInfoObject)
  local mapSectionAddressArraySize = 1968
  local entriesCount = 1968 / 123 -- of which the last is all 0s


  local ptr_copyOfMapSectionAddressArray = core.allocate(mapSectionAddressArraySize + helpers.MapSectionAddress.sizeof, true)

  -- Install the special thing such that our information is put in a .sav file
  core.writeBytes(ptr_copyOfMapSectionAddressArray, core.readBytes(originalMapSectionInfoArray, mapSectionAddressArraySize))
  core.writeBytes(ptr_copyOfMapSectionAddressArray + (122 * helpers.MapSectionAddress.sizeof), customSectionInfoObject:serialize())

  return ptr_copyOfMapSectionAddressArray
end

local function updateCustomSectionInfoObject(ptr_copyOfMapSectionAddressArray, customSectionInfoObject)
  core.writeBytes(ptr_copyOfMapSectionAddressArray + (122 * helpers.MapSectionAddress.sizeof), customSectionInfoObject:serialize())
end

local function registerReadWriteSavHooks(customMapSectionInfoArray, customSectionID, callbacks)
    
  -- Hooks
  -- read map or sav
  local ptr_FilePackagerObj = core.readInteger(core.AOBScan("B9 ? ? ? ? E8 ? ? ? ? B9 ? ? ? ? E8 ? ? ? ? 8B 44 24 14 ") + 1)

  local originalReadSav
  originalReadSav = core.hookCode(function(this, ptrMapSectionAddressArray)
    if originalMapSectionInfoArray ~= ptrMapSectionAddressArray then error("argument is not what we expected") end

    log(3, "readSavHook: beforeReadSav()")
    callbacks.beforeReadSav()
    
    log(3, "readSavHook: originalReadSav()")
    local result = originalReadSav(this, customMapSectionInfoArray)

    log(3, "readSavHook: afterReadSav()")
    callbacks.afterReadSav()

    return result

  end, core.AOBScan("83 EC 0C 53 56 8B F1 8B 46 20"), 2, CallingConvention.THISCALL, 5)

  -- write map or sav
  local originalWriteSav
  originalWriteSav = core.hookCode(function(this, ptrMapSectionAddressArray)
    if originalMapSectionInfoArray ~= ptrMapSectionAddressArray then error("argument is not what we expected") end

    log(3, "writeSavHook: beforeWriteSav()")
    callbacks.beforeWriteSav()
    
    log(3, "writeSavHook: originalWriteSav()")
    local result = originalWriteSav(this, customMapSectionInfoArray)

    log(3, "writeSavHook: afterWriteSav()")
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

    local sectionIDs = utils.unpack("<i", core.readString(sectionIDArray, 4*150))

    local i = -1
    for index, sid in ipairs(sectionIDs) do
      if sid == customSectionID then
        i = index - 1 -- lua is 1 based
        break
      end
    end

    if i == -1 then

      log(3, "afterReadDirectoryOfSav({size = 0})")
      callbacks.afterReadDirectoryOfSav({
        size = 0,
      })

      return registers
    end

    local customSectionSizeOfSav = core.readInteger(uncompressedSizesArray + (4 * i))

    log(3, "afterReadDirectoryOfSav({size = ...})")
    callbacks.afterReadDirectoryOfSav({
      size = customSectionSizeOfSav,
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
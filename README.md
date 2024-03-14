# UCP Extension: map-extensions
UCP Extension that enables storing extra information in .map and .sav files

## Idea
A .map file has sections. How to read these sections and where to store the data is stored in the .exe file.
Currently that array is 123 entries long. I think it can be expanded to 145 entries.
Technically, we only need a 124th section since section sizes can be of max size of a signed integer 2,147,483,647 bytes, which is 2.14 Gb.
We set the flag to compressed so we can zero initialize a large space (which will be compressed to almost nothing if it stays as 0's).

Maybe it is easiest to also hook into the save and load functions so we can prepare this section for serialization.
I think it is easiest to organize it as a .zip file itself (without compression).

### Structure
```yml
#contains meta information such as the framework version it can run on
meta.yml:
  version: 1.0.0
  framework: ^3.0.0
  extensions: # which extensions have an entry in the section, including which version of an extension created it.
    maploader: 0.0.1
  config: {} # The full config of the user that was used to create the .map file
framework: # folder used by the framework itself, not sure what the use is if we have meta.yml
extensions:
  maploader: # folder used by the extension named maploader
  whatever: # plugin folder data
```

### Interface
```lua
local registry = {}

api = {
  -- Returns a handle to the section, which is a zip in memory!
  function registerSection(self, extensionName, serializationCallbacks)
    registry[extensionName] = serializationCallbacks
  end,
}

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

Buffer = {
  readInteger = function(self) end,
  writeInteger = function(self) end,
  readBytes = function(self) end,
  writeBytes = function(self) end,
}

-- This is backed by the library https://github.com/kuba--/zip
Handle = {
  putContents = function(self, relativePath, data) end,
  getContents = function(self, relativePath) end,
}
```

### Usage
```lua

local databytes = {}

return {

  enable = function(self, config)
    modules['map-extensions']:registerSection("plugin name", {
      check = function(s, handle)
        -- Check version compatibility with a .map or .sav file
      end,
      serialize = function(s, handle)
        databytes = handle:getContents('data.txt') -- will be 'extensions/plugin name/mydata.txt' in the zip file
      end,
      deserialize = function(s, handle)
        handle:putContents('mydata.txt', databytes)
      end,
    })
  end,

}

```

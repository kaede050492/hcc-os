-- Run with Lua 5.2+ from the repository root:
--   lua tests/config_spec.lua

local function copyTable(source)
    local copy={}
    for key,value in pairs(source or {}) do copy[key]=value end
    return copy
end

local function makeFixture()
    local state={files={},directories={['/']=true,['/config']=true,['/legacy']=true},serialized={},serial=0,
        failMoveToMain=false,warnings={}}
    local function canonical(path)
        local parts={}
        for part in tostring(path or ""):gsub("\\","/"):gmatch("[^/]+") do
            if part==".." then if #parts>0 then table.remove(parts) end
            elseif part~="." then parts[#parts+1]=part end
        end
        return "/"..table.concat(parts,"/")
    end
    local api={}
    api.combine=function(base,path) return canonical(tostring(base or "").."/"..tostring(path or "")) end
    api.exists=function(path) path=canonical(path); return state.files[path]~=nil or state.directories[path]==true end
    api.isDir=function(path) return state.directories[canonical(path)]==true end
    api.getSize=function(path)
        local value=state.files[canonical(path)]
        if value==nil then error("file does not exist") end
        return #value
    end
    api.open=function(path,mode)
        path=canonical(path)
        if mode=="rb" then
            local contents=state.files[path]
            if contents==nil then return nil,"file does not exist" end
            return {readAll=function() return contents end,close=function() end}
        end
        if mode~="wb" then return nil,"unsupported mode" end
        local chunks={}
        return {write=function(value) chunks[#chunks+1]=value end,
            close=function() state.files[path]=table.concat(chunks) end}
    end
    api.move=function(source,destination)
        source,destination=canonical(source),canonical(destination)
        if state.failMoveToMain and destination=="/config/settings" then
            state.failMoveToMain=false
            error("injected settings commit failure")
        end
        if state.files[source]==nil then error("source does not exist") end
        if state.files[destination]~=nil or state.directories[destination] then error("destination exists") end
        state.files[destination]=state.files[source]
        state.files[source]=nil
    end
    api.copy=function(source,destination)
        source,destination=canonical(source),canonical(destination)
        if state.files[source]==nil then error("source does not exist") end
        state.files[destination]=state.files[source]
    end
    api.delete=function(path)
        path=canonical(path)
        if state.directories[path] then error("cannot delete directory") end
        state.files[path]=nil
    end
    local textutils={}
    textutils.serialize=function(value)
        state.serial=state.serial+1
        local token="serialized-settings-"..tostring(state.serial)
        state.serialized[token]=copyTable(value)
        return token
    end
    textutils.unserialize=function(value)
        local parsed=state.serialized[value]
        if not parsed then error("invalid serialized settings") end
        return copyTable(parsed)
    end
    local environment=setmetatable({fs=api,textutils=textutils,os={
        getComputerID=function() return 42 end,
        epoch=function() return 1700000000000 end,
        clock=function() return 1 end
    }},{__index=_G})
    return state,api,textutils,environment
end

local paths={settings="/config/settings",legacySettings="/legacy/settings"}

do
    local state,api,textutils,environment=makeFixture()
    local initial={theme="midnight",wallpaperMode="stretch",fpsMax=30,fpsMin=60,
        computerLabel="Workbench",customToggle=true,customTable={discard=true}}
    state.files[paths.settings]=textutils.serialize(initial)
    local moduleChunk,moduleError=loadfile("system/core/config.lua","t",environment)
    assert(moduleChunk,moduleError)
    local Config=moduleChunk()
    local config=Config.new(paths,{warn=function(_,message) state.warnings[#state.warnings+1]=message end})
    config:load()

    assert(config.primaryValid and config.data.theme=="midnight" and config.data.wallpaperMode=="stretch",
        "valid settings should load and preserve supported options")
    assert(config.data.fpsMax==30 and config.data.fpsMin==30,
        "inverted fps limits should be normalized into a valid range")
    assert(config.data.customToggle==true and config.data.customTable==nil,
        "simple extension settings should survive while complex values are ignored")
    assert(config.data.computerId=="42" and config.data.configVersion==3,
        "runtime identity and current schema version should be applied")

    config.data.computerLabel="Control Room"
    local saved,saveError=config:save()
    assert(saved,saveError)
    assert(state.files[paths.settings]~=nil and state.files[paths.settings..".bak"]~=nil,
        "a successful save should install the new settings and keep a verified backup")
    assert(state.files[paths.settings..".tmp"]==nil and state.files[paths.settings..".prev"]==nil,
        "successful saves should remove transaction files")
    local current=textutils.unserialize(state.files[paths.settings])
    assert(current.computerLabel=="Control Room","the saved settings should contain the updated value")

    local before=state.files[paths.settings]
    config.data.computerLabel="failed replacement"
    state.failMoveToMain=true
    local committed=config:save()
    assert(not committed,"a failed settings commit should be reported")
    assert(state.files[paths.settings]==before,
        "a failed replacement should restore the previously active settings")
    assert(state.files[paths.settings..".tmp"]==nil and state.files[paths.settings..".prev"]==nil,
        "a rolled back settings save should not leave temporary files")
end

do
    local state,_,textutils,environment=makeFixture()
    state.files[paths.settings]="corrupt settings payload"
    state.files[paths.settings..".bak"]=textutils.serialize({theme="midnight",computerLabel="Recovered"})
    local moduleChunk,moduleError=loadfile("system/core/config.lua","t",environment)
    assert(moduleChunk,moduleError)
    local Config=moduleChunk()
    local config=Config.new(paths)
    config:load()
    assert(config.recovered and config.data.theme=="midnight" and config.data.computerLabel=="Recovered",
        "a corrupt primary settings file should recover from the backup")
    assert(config.recoveredFrom==paths.settings..".bak" and config.notice~=nil,
        "the recovery source and a user-visible recovery notice should be recorded")
    local quarantined=false
    for path in pairs(state.files) do
        if path:find(paths.settings..".corrupt.",1,true)==1 then quarantined=true end
    end
    assert(state.files[paths.settings]==nil and quarantined,
        "the invalid primary should be quarantined rather than overwritten")
end

print("config specs passed")

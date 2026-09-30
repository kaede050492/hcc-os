-- Run with Lua 5.2+ from the repository root:
--   lua tests/file_service_spec.lua

local moduleChunk,moduleError=loadfile("system/core/file_service.lua")
assert(moduleChunk,moduleError)
local FileService=moduleChunk()

local function makeFixture()
    local state={files={},directories={['/']=true,['/docs']=true,['/system']=true,
        ['/system/config']=true},failCommit=false}
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
    api.getDir=function(path)
        local parent=canonical(path):match("^(.*)/[^/]+$")
        return parent=="" and "/" or parent or "/"
    end
    api.getSize=function(path)
        local contents=state.files[canonical(path)]
        if contents==nil then error("file does not exist") end
        return #contents
    end
    api.isReadOnly=function() return false end
    api.open=function(path,mode)
        path=canonical(path)
        if mode=="rb" then
            local contents=state.files[path]
            if contents==nil then return nil,"file does not exist" end
            local offset=1
            return {
                readAll=function() return contents end,
                read=function(count)
                    if offset>#contents then return nil end
                    local chunk=contents:sub(offset,offset+count-1)
                    offset=offset+#chunk
                    return chunk
                end,
                close=function() end
            }
        end
        if mode~="wb" then return nil,"unsupported mode" end
        local chunks={}
        return {
            write=function(contents) chunks[#chunks+1]=contents end,
            close=function() state.files[path]=table.concat(chunks) end
        }
    end
    api.delete=function(path)
        path=canonical(path)
        if state.directories[path] then error("cannot delete directory") end
        state.files[path]=nil
    end
    api.move=function(source,destination)
        source,destination=canonical(source),canonical(destination)
        if state.failCommit and destination=="/docs/notes.txt" then
            state.failCommit=false
            error("injected commit failure")
        end
        if state.files[source]==nil then error("source does not exist") end
        if state.files[destination]~=nil or state.directories[destination] then error("destination exists") end
        state.files[destination]=state.files[source]
        state.files[source]=nil
    end
    return state,api
end

local function newService(api)
    return FileService.new({fs=api,paths={
        system="/system",config="/system/config",legacySettings="/system/legacy",
        startup="/startup.lua",backups="/system/backups",temp="/system/tmp",
        updateTemp="/system/update",cache="/system/cache",logs="/system/logs",
        backupRoots={},updateTemps={},currency="/docs/currency.dat"
    }})
end

do
    local state,api=makeFixture()
    local service=newService(api)
    local saved,saveError=service:writeAtomic("/docs/notes.txt","first version",64)
    assert(saved,saveError)
    assert(service:readText("/docs/notes.txt",64)=="first version",
        "atomic writes should create readable files")

    saved,saveError=service:writeAtomic("/docs/notes.txt","second version",64)
    assert(saved,saveError)
    assert(service:readText("/docs/notes.txt",64)=="second version",
        "atomic overwrites should replace the contents")
    assert(not api.exists("/docs/notes.txt.hccos-tmp") and
        not api.exists("/docs/notes.txt.hccos-prev"),
        "successful saves should remove temporary recovery files")

    local before=state.files["/docs/notes.txt"]
    local rejected=service:writeAtomic("/docs/notes.txt","oversized",3)
    assert(not rejected and state.files["/docs/notes.txt"]==before,
        "oversized writes should leave the destination untouched")
    assert(not service:writeAtomic("/system/config/settings.lua","user data",64),
        "OS-managed paths must reject application writes")
    assert(not service:writeAtomic("../../boot.lua","user data",64),
        "normalized traversal paths must not reach protected boot files")
    assert(not service:writeAtomic("/docs/currency.dat","application data",64),
        "applications must not overwrite service-managed files")
    local managed=service:writeManagedAtomic("/docs/currency.dat","service data",64)
    assert(managed and service:readText("/docs/currency.dat",64)=="service data",
        "the owning service should be able to update its managed file")
    assert(not service:writeAtomic("/docs/missing/note.txt","data",64),
        "writes must reject nonexistent parent directories")

    state.failCommit=true
    local committed=service:writeAtomic("/docs/notes.txt","uncommitted",64)
    assert(not committed,"a failed commit should be reported")
    assert(service:readText("/docs/notes.txt",64)==before,
        "a failed replacement must restore the previous file")
    assert(not api.exists("/docs/notes.txt.hccos-tmp") and
        not api.exists("/docs/notes.txt.hccos-prev"),
        "rollback should clean staged and previous files")
end

do
    local state,api=makeFixture()
    local service=newService(api)
    state.files["/docs/recovered.txt.hccos-prev"]="last known good"
    state.files["/docs/recovered.txt.hccos-tmp"]="partial write"
    assert(service:readText("/docs/recovered.txt",64)=="last known good",
        "reads should restore the previous file after an interrupted save")
    assert(not api.exists("/docs/recovered.txt.hccos-prev") and
        not api.exists("/docs/recovered.txt.hccos-tmp"),
        "recovery should clean stale save artifacts")
end

print("file service specs passed")

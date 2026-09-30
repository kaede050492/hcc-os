-- Run with Lua 5.2+ from the repository root:
--   lua tests/startup_spec.lua

local function environmentWith(files)
    local directories={ ["/"]=true }
    local output={}
    local function combine(...)
        local path=""
        for index,part in ipairs({...}) do
            part=tostring(part or "")
            if index==1 and part:sub(1,1)=="/" then path=part:gsub("/$","")
            elseif part~="" then path=path.."/"..part:gsub("^/+","") end
        end
        if path=="" then return "/" end
        return path
    end
    local fs={
        exists=function(path) return files[path]~=nil or directories[path]==true end,
        isDir=function(path) return directories[path]==true end,
        list=function(path) if path=="/" then return {"disk0"} end; return {} end,
        combine=combine,
        getDir=function(path) return path:match("^(.*)/[^/]+$") or "" end,
        makeDir=function(path) directories[path]=true end,
        open=function(path,mode)
            if mode=="r" then
                if files[path]==nil then return nil,"missing file: "..path end
                local content=files[path]
                return {readAll=function() return content end,close=function() end}
            elseif mode=="w" then
                return {write=function(content) files[path]=tostring(content or "") end,close=function() end}
            end
            return nil,"unsupported mode"
        end
    }
    local env={fs=fs,output=output}
    env._G=env
    env.print=function(...) output[#output+1]=table.concat({...}," ") end
    return setmetatable(env,{__index=_G}),files
end

local ok,reason=pcall(function()
    local files={
        ["/.hccos/system/core/bootstrap.lua"]='return {run=function(args) _G.bootCount=(_G.bootCount or 0)+1; _G.bootArgs=args end}'
    }
    local env=environmentWith(files)
    local startup,loadError=loadfile("startup.lua","t",env)
    assert(startup,loadError)
    startup("--safe","argument")
    assert(env.bootCount==1 and env.bootArgs[1]=="--safe" and env.bootArgs[2]=="argument",
        "startup should load the installed bootstrap once and forward arguments")
    assert(files["/.hccos/logs/boot.log"]==nil,
        "a successful boot should not create a failure log")

    files["/.hccos/system/core/bootstrap.lua"]='return {run=function() error("injected boot failure") end}'
    files["/.hccos/system/core/recovery.lua"]='return {runStandalone=function(message) _G.recoveryReason=message; return true end}'
    env.recoveryReason=nil
    startup("normal")
    assert(type(env.recoveryReason)=="string" and env.recoveryReason:find("injected boot failure",1,true),
        "a boot failure should be passed to standalone recovery")
    local bootLog=files["/.hccos/logs/boot.log"]
    assert(type(bootLog)=="string" and bootLog:find("[ERROR] Boot failure:",1,true) and
        bootLog:find("injected boot failure",1,true),
        "startup should persist a bounded boot failure log before recovery")
end)
assert(ok,reason)

print("startup and recovery specs passed")

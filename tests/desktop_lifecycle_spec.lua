-- Run with Lua 5.2+ from the repository root:
--   lua tests/desktop_lifecycle_spec.lua

local chunk,loadError=loadfile("system/ui/desktop.lua")
assert(chunk,loadError)
local Desktop=chunk()

local function runScenario(mode)
    local cleanupCount=0
    local context={
        modules={},
        paths={},
        config={isFirstBoot=function() return false end},
        appRegistry={},
        updater={},
        httpService={requests={}},
        ui={widgets={},icons={},taskbar={},startMenu={}}
    }
    function context.modules:loadPath(path)
        if path=="/.hccos/system/core/runtime.lua" then
            return {new=function()
                local E={OS={recoveryRequested=mode=="recovery"},P={},Widget={}}
                function E.run()
                    if mode=="failure" then error("injected desktop loop failure") end
                    return "desktop result"
                end
                function E.cleanup() cleanupCount=cleanupCount+1 end
                return E
            end}
        elseif path=="/.hccos/system/core/app_manager.lua" then
            return {install=function() end,installBoot=function() end}
        elseif path=="/.hccos/system/ui/icons.lua" then
            return function(E) E.icons={app=function() end} end
        end
        return function() end
    end

    local ok,result=Desktop.run(context)
    assert(cleanupCount==1,"desktop resources should be cleaned exactly once after "..mode)
    assert(context.updater.httpAvailable==nil,
        "temporary updater HTTP ownership should be released after "..mode)
    return ok,result
end

local ok,result=runScenario("normal")
assert(ok and result=="desktop result","normal desktop shutdown should return its result")

ok,result=runScenario("failure")
assert(ok==false and tostring(result):find("injected desktop loop failure",1,true),
    "desktop loop exceptions should become a recoverable failure result")

ok,result=runScenario("recovery")
assert(ok==false and result=="manual recovery request",
    "manual recovery requests should exit the desktop loop for recovery")

print("desktop lifecycle specs passed (normal/failure/recovery cleanup)")

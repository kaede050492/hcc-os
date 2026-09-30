-- Run with Lua 5.2+ from the repository root:
--   lua tests/scheduler_spec.lua

local chunk,loadError=loadfile("system/core/scheduler.lua")
assert(chunk,loadError)
local SchedulerFactory=chunk()

local requests,cancelled,consumed={}, {}, {}
local activeTimers={}
local events={{"timer",1},{"timer",2}}
local pulls,updates,renders=0,0,0
local targetUpdates=500
local failPump=false
local E={
    context={config={isFirstBoot=function() return false end}},
    OS={running=true,windows={},appTimers={},systemTimers=activeTimers,damage={},renderCount=0,taskDirty=false,
        pointer={visible=false,lastMove=0}},
    Driver={w=576,h=320,syncs=0,clear=function() end,text=function() end,sync=function() end},
    devices={gpuName="mock GPU",keyboards={},list={}},
    cfg={cursorIdle=6},P={accent=1,textPrimary=2,warning=3},
    HCC_VERSION_LABEL="HCC OS test",HCC_CPU="test CPU",TASK=32,
    configPath="/.hccos/settings",currencyPath="/.hccos/currency",
    fs={exists=function() return true end},
    keys={f5=63},
    floor=math.floor,min=math.min,max=math.max,
    clamp=function(value,minimum,maximum) return math.max(minimum,math.min(maximum,value)) end,
    finite=function(value) return type(value)=="number" and value==value and math.abs(value)<1e12 end,
    now=function() return 100 end,
    box=function(x,y,w,h) return {x=x,y=y,w=w,h=h} end,
    print=function() end,
    scanDevices=function() return true end,
    canvas=function() return {text=function() end} end,
    saveConfig=function() return true end,currencySave=function() return true end,
    allDirty=function() end,openApp=function() end,notify=function() end,
    render=function() renders=renders+1 end,
    shutdownDisplay=function() end,cancelWindowTimers=function() end,
    cancelWindowHttpRequests=function() end,
    gpuAvailable=function() return true end,
    invalidate=function() end,
    appCall=function(win,method)
        if method=="interval" then return 0.5 end
        if method=="update" then updates=updates+1 end
    end,
    startSystemTimer=function(delay,category)
        local id=#requests+1
        requests[#requests+1]={id=id,delay=delay,category=category}
        activeTimers[id]=category
        return id
    end,
    cancelSystemTimer=function(id) cancelled[id]=true; activeTimers[id]=nil end,
    consumeSystemTimer=function(id) consumed[id]=true; activeTimers[id]=nil end,
    consumeIgnoredTimer=function() return false end,
    fireOwnedTimer=function() return false end,
    os={
        startTimer=function() return 900 end,
        cancelTimer=function() end,
        pullEventRaw=function()
            pulls=pulls+1
            assert(#requests>0,"scheduler should arm a timer before blocking for events")
            if failPump then error("injected event pump failure") end
            local event=table.remove(events,1)
            if event then return table.unpack(event) end
            if updates>=targetUpdates then return "key",30 end
            for index=#requests,1,-1 do
                local request=requests[index]
                if request.category=="app-update" and
                    not consumed[request.id] and not cancelled[request.id] then
                    return "timer",request.id
                end
            end
            error("scheduler blocked without an owned app timer")
        end
    }
}
E.context.api=nil
E.handleEvent=function(event)
    assert(event[1]=="key","expected a non-timer event after the app update")
    E.OS.running=false
end
E.OS.windows[1]={id="clock",minimized=false,crash=false,app={update=function() end}}
setmetatable(E,{__index=_G})
SchedulerFactory(E)
E.run()

assert(updates==targetUpdates,"repeated owned app timers should update without losing scheduler state")
assert(pulls==targetUpdates+2,"the scheduler should block for events rather than spin")
assert(renders==1,"boot should render once and idle event handling should not redraw")
assert(requests[1].category=="app-update" and requests[1].delay==0.5,
    "app timers should retain their requested interval")
assert(requests[2].category=="scheduler" and requests[2].delay==1 and
    requests[4].category=="scheduler" and requests[4].delay==1,
    "the system heartbeat should rearm after its one-second event")
assert(#requests==targetUpdates+3 and consumed[1] and consumed[2] and
    cancelled[4] and cancelled[#requests],
    "consumed and outstanding timer ownership should be released on shutdown")

E.OS.running=true
E.OS.windows={}
E.OS.appTimers={}
events={}
failPump=true
local runOk,runError=pcall(E.run)
assert(not runOk and tostring(runError):find("injected event pump failure",1,true),
    "the scheduler should report event pump failures to desktop recovery")
local leakedTimer=requests[#requests].id
assert(activeTimers[leakedTimer],"failure injection should leave an owned timer for cleanup")
E.cleanup()
assert(cancelled[leakedTimer] and next(activeTimers)==nil,
    "desktop cleanup should release system timers left by scheduler failures")

print("scheduler specs passed (500 updates, event blocking, failure cleanup)")

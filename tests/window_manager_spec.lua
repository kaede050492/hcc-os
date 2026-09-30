-- Run with Lua 5.2+ from the repository root:
--   lua tests/window_manager_spec.lua

local geometryChunk,geometryError=loadfile("system/lib/hcc/geometry.lua")
assert(geometryChunk,geometryError)
local geometry=geometryChunk()
local nextTimer=0
local cancelledTimers={}
local ticks=100
local logger={info=function() end,warn=function() end,error=function() end}
local E=setmetatable({
    context={httpRequests={},logger=logger},
    Driver={w=576,h=320},
    cfg={logLimit=400,snapEnabled=true,snapDistance=10},
    P={accent=1,warning=2,error=3,success=4,border=5,panelBackground=6,textPrimary=7},
    HCC_MAX_WINDOWS=24,HCC_MAX_LOGS=400,
    floor=math.floor,min=math.min,max=math.max,unpack=table.unpack,
    now=function() ticks=ticks+0.01; return ticks end,
    finite=function(value) return type(value)=="number" and value==value and math.abs(value)<1e12 end,
    box=geometry.rect,intersect=geometry.intersect,union=geometry.union,
    clamp=function(value,low,high) return math.max(low,math.min(high,value)) end,
    ascii=function(value) return tostring(value or "") end,
    os={
        startTimer=function() nextTimer=nextTimer+1; return nextTimer end,
        cancelTimer=function(id) cancelledTimers[id]=true end
    }
},{__index=_G})

local managerChunk,managerError=loadfile("system/core/window_manager.lua")
assert(managerChunk,managerError)
managerChunk()(E)

local sharedDefinition={
    init=function(self) self.value=0; self.pauses=0; self.resumes=0; self.closes=0 end,
    pause=function(self) self.pauses=self.pauses+1 end,
    resume=function(self) self.resumes=self.resumes+1 end,
    close=function(self) self.closes=self.closes+1 end
}
E.register("notepad","Notepad",nil,240,160,sharedDefinition)

local first=E.openApp("notepad")
local second=E.openApp("notepad")
assert(first and second and first~=second and first.app~=second.app,
    "multi-window apps should receive separate window and app state")
first.app.value=17
assert(second.app.value==0,"app state must not leak between windows: first="..
    tostring(first.app.value).." second="..tostring(second.app.value).." crashes="..
    tostring(first.crash).."/"..tostring(second.crash))
assert(E.OS.active==second,"the newest app window should receive focus")

local area=E.workspace()
local timer=E.scheduleOwnedTimer(second,1,function() error("cancelled timer fired") end)
assert(timer and second.ownedTimers[timer],"window timers should have an owner")
E.minimize(second)
assert(second.minimized and E.OS.active==first and cancelledTimers[timer],
    "minimizing should pause the app, cancel its timer, and focus another window")
assert(not E.fireOwnedTimer(timer),"a canceled timer must not fire")
E.focus(second)
assert(not second.minimized and E.OS.active==second and second.app.resumes==1,
    "restoring a minimized window should resume it and restore focus")

local original={x=second.x,y=second.y,w=second.w,h=second.h}
E.maximize(second)
assert(second.restore and second.x==area.x and second.y==area.y and
    second.w==area.w and second.h==area.h,"maximizing should fill the logical workspace")
E.maximize(second)
assert(not second.restore and second.x==original.x and second.y==original.y and
    second.w==original.w and second.h==original.h,"restoring should recover the prior geometry")

second.x,second.y,second.w,second.h=100000,-100000,100000,100000
E.fit(second)
area=E.workspace()
assert(second.w<=area.w and second.h<=area.h and second.x+12>area.x and
    second.x<area.x+area.w and second.y+E.TITLE>area.y and second.y<area.y+area.h,
    "geometry normalization should keep windows reachable on the logical screen")

first.app.unsaved=true
E.closeWindow(first)
assert(E.OS.modal~=nil and not first.closed,"closing unsaved work should request confirmation")
E.dismiss("Keep")
assert(not first.closed,"keeping the dialog should leave the window open")
E.closeWindow(first)
E.dismiss("Discard")
assert(first.closed and first.app.closes==1 and E.OS.active==second,
    "discard confirmation should close exactly one window and retain a valid active window")

local crashingDefinition={
    init=function(self) self.closes=0 end,
    update=function() error("injected app failure") end,
    close=function(self) self.closes=self.closes+1 end
}
E.register("crasher","Crasher",nil,240,160,crashingDefinition)
local crashing=E.openApp("crasher")
E.appCall(crashing,"update")
assert(crashing.crash and crashing.app.closes==1 and E.OS.running,
    "an app callback failure should be contained and clean up the app once: crash="..
    tostring(crashing.crash).." cleanup="..tostring(crashing.app.closes).." running="..
    tostring(E.OS.running))
assert(not second.crash and not second.closed and E.OS.windows[#E.OS.windows]==crashing,
    "an app failure should not corrupt the other window or stop the OS")
E.closeWindow(crashing)
assert(crashing.closed and crashing.app.closes==1 and E.OS.active==second,
    "closing a crashed app should not run cleanup twice or lose focus")

print("window manager specs passed")

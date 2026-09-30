-- Run with Lua 5.2+ from the repository root:
--   lua tests/input_spec.lua

local E={
    OS={windows={},held={},mouseButtons={},menu=false,modal=nil},
    devices={keyboards={}},cfg={debugInputTrace=false},
    keys={leftCtrl=341,rightCtrl=345,leftAlt=342,rightAlt=346,q=16,w=17,tab=15,
        f1=59,f2=60,f3=61,f5=63,f6=64,escape=1,enter=28,up=200,down=208,left=203,right=205},
    errors=0,events={}
}
setmetatable(E,{__index=_G})
E.unpack=table.unpack or unpack
E.finite=function(value) return type(value)=="number" and value==value and math.abs(value)<1e12 end
E.consumeIgnoredTimer=function() return false end
E.appCall=function(win,method,...)
    local callback=win and win.app and win.app[method]
    if type(callback)~="function" then return end
    local ok,result=pcall(callback,win.app,...)
    if not ok then E.errors=E.errors+1; return nil end
    return result
end
local win={id="input-test",app={
    onSystemEvent=function(self,name,value) E.events[#E.events+1]={self.id,name,value} end,
    onKey=function(_,key) E.lastKey=key end,
    onChar=function(_,text) E.lastText=text end
}}
win.app.id="focused"
local other={id="other-window",app={
    id="background",
    onSystemEvent=function(self,name,value) E.events[#E.events+1]={self.id,name,value} end,
    onKey=function(_,key) E.otherKey=key end,
    onChar=function(_,text) E.otherText=text end
}}
E.OS.windows[1]=win; E.OS.windows[2]=other; E.OS.active=win

local moduleChunk,moduleError=loadfile("system/core/input.lua")
assert(moduleChunk,moduleError)
moduleChunk()(E)

for _,event in ipairs({false,{}, {42}, {"key"}, {"key_up"},
        {"mouse_click"}, {"mouse_drag",1,"bad",nil}, {"mouse_scroll","bad",10,10},
        {"tm_keyboard_key"}}) do
    local ok=pcall(E.handleEvent,event)
    assert(ok,"malformed native and mouse events should be ignored")
end
assert(E.handleEvent(nil)==false and E.handleEvent({})==false,
    "non-event values should be rejected before event-name dispatch")
assert(next(E.OS.held)==nil and E.errors==0,
    "malformed key input should not corrupt held-key state or fail an app")

E.handleEvent({"key",65})
assert(E.OS.held[65] and E.lastKey==65,"valid key input should update state and reach the active app")
E.handleEvent({"key_up",65})
assert(E.OS.held[65]==nil,"valid key release should clear held state")
E.handleEvent({"char","hello"})
assert(E.lastText=="hello","valid text input should reach the active app")
E.handleEvent({"custom_device_event","payload"})
assert(#E.events==2 and E.events[1][2]=="custom_device_event" and E.events[1][3]=="payload" and
    E.events[2][2]=="custom_device_event" and E.events[2][3]=="payload",
    "non-timer system events should be delivered without being consumed as input: count="..
    tostring(#E.events).." event="..tostring(E.events[1] and E.events[1][1]).."/"..
    tostring(E.events[1] and E.events[1][2]).." errors="..tostring(E.errors))
E.handleEvent({"timer",42})
assert(#E.events==2,"timer events should not be broadcast to app system-event handlers")
assert(E.otherKey==nil and E.otherText==nil,
    "key and text input should never be broadcast to background applications")

local keyboardCalls=0
E.devices.keyboards.keyboard={}
win.app.onKey=function(_,key) keyboardCalls=keyboardCalls+1; E.lastKey=key end
E.handleEvent({"tm_keyboard_key","keyboard",66})
assert(keyboardCalls==1 and E.lastKey==66,
    "events from a detected native keyboard should be normalized and delivered")
E.handleEvent({"tm_keyboard_key","unknown",67})
E.handleEvent({"tm_keyboard_key","keyboard"})
assert(keyboardCalls==1,"unknown keyboards and missing native key codes should be ignored")

print("input router specs passed")

-- Run with Lua 5.2+ from the repository root:
--   lua tests/app_modules_spec.lua

local ids={"calendar","clock","currency","diagnostics","files","image","inventory","logs",
    "network","notepad","performance","peripherals","radar","resource","server","settings",
    "setup","system","taskmgr","terminal","updates","web"}
local packageRoot="/.hccos/system/apps"
local appDirectories={}
local manifestTables={}
for _,id in ipairs(ids) do
    appDirectories[id]=true
    local chunk,err=loadfile("system/apps/"..id.."/manifest.lua")
    assert(chunk,err)
    manifestTables[id]=chunk()
end
local registered={}
local config={clockMode="JST",clockInterval=1,networkRefresh=3,resourceRefresh=2,
    maxImageDownload=4194304,inventoryRefresh=2,radarInterval=0.5,dimension="minecraft:overworld",
    serverInterval=2,systemInterval=1,performanceHistory=60,centerX=470,centerZ=-33,grid=true,
    adaptiveFps=true,computerId="test",computerLabel="Test Computer",fpsMax=60,fpsMin=10,
    theme="black",uiScale=1,wallpaperError="",wallpaperLastGood="",wallpaperMode="black",
    accent="cyan",autoUpdateCheck=false,updateChannel="stable",wallpaperEnabled=true,wallpaperPath="",
    imageDownloadConcurrency=3}
local context={paths={},storage={isInternalPath=function() return false end},
    fileService={},ui={mark=function() end},logger={entries={},getEntries=function(self) return self.entries end},
    updater={lastCheck=nil,status=function() return {phase="idle",message="Ready"} end},
    takeAutoUpdatePending=function() return false end}
local appOS={windows={},registry={},order={},logs={},renderRate=20,syncRate=20,started=0}
local E={
    AppDriver={w=576,h=320,scale=1,cellWidth=6,measure=function(text,scale) return #tostring(text)*6*(scale or 1) end,
        logicalWidth=576,logicalHeight=320,setUIScale=function() return true end,
        getActualSize=function() return 80,50 end},AppOS=appOS,Driver={},OS=appOS,
    paths={images="/.hccos/images",downloads="/.hccos/downloads"},
    cfg=config,devices={list={},keyboards={},modems={},inventories={}},P={
        accent=1,textPrimary=2,textSecondary=3,success=4,warning=5,error=6,
        panelBackground=7,windowBackground=8,border=9,grid=10},Widget={},
    performance={getActualFps=function() return 20 end,getTargetFps=function() return 20 end,
        getConfiguredMaxFps=function() return 60 end,getConfiguredMinFps=function() return 10 end,
        getTimerCeilingFps=function() return 20 end,getFrameTimeMs=function() return 50 end,
        getDroppedFrameCount=function() return 0 end,isDegraded=function() return false end},
    keys=setmetatable({}, {__index=function(_,key) return key end}),
    fs={combine=function(a,b) return a:gsub("/$","").."/"..b end,
        getName=function(path) return path:match("([^/]+)$") or path end,
        getDir=function() return "/" end,getSize=function() return 0 end,
        isReadOnly=function() return false end,getFreeSpace=function() return "unlimited" end},
    peripheral={getMethods=function() return {} end},
    finite=function(value) return type(value)=="number" and value==value and math.abs(value)<1e12 end,
    clamp=function(value,minimum,maximum) return math.max(minimum,math.min(maximum,value)) end,
    floor=math.floor,min=math.min,max=math.max,unpack=table.unpack or unpack,
    ascii=function(value) return tostring(value or "") end,
    shortText=function(value,limit) value=tostring(value or ""); return #value<=limit and value or value:sub(1,math.max(0,limit-3)).."..." end,
    now=function() return 1000 end,jst=function() return {year=2026,month=9,day=30,hour=12,min=0,sec=0} end,
    timeText=function() return "12:00:00" end,dateText=function() return "2026-09-30" end,
    mark=function() end,dialog=function() end,notify=function() end,errorBox=function() end,
    logLine=function() end,rescan=function() end,openApp=function() end,appCall=function() end,
    button=function() end,imageList=function() return {} end,
    HCC_VERSION="1.5.1",HCC_VERSION_LABEL="HCC OS v1.5.1",HCC_CPU="test",
    HCC_TARGET_W=576,HCC_TARGET_H=320,HCC_BLOCKS_X=9,HCC_BLOCKS_Y=5,HCC_PIXELS_PER_BLOCK=64}
E.context=context
E.Widget.panel=function() end
E.Widget.graph=function() end
local function sourcePath(path)
    if path:sub(1,#packageRoot)==packageRoot then return "system/apps"..path:sub(#packageRoot+1) end
    return path
end
function E.fs.list(path)
    if path==packageRoot then return ids end
    return {}
end
function E.fs.isDir(path)
    if path==packageRoot then return true end
    local id=path:sub(#packageRoot+2)
    return path:sub(1,#packageRoot+1)==packageRoot.."/" and appDirectories[id]==true
end
function E.fs.exists(path)
    if E.fs.isDir(path) then return true end
    if path:sub(1,#packageRoot)~=packageRoot then return false end
    if path:match("^"..packageRoot.."/[a-z][a-z0-9_-]*/manifest%.lua$") then return true end
    local chunk=loadfile(sourcePath(path))
    return chunk~=nil
end
function E.fs.open(path,mode)
    local id=path:match("^"..packageRoot.."/([a-z][a-z0-9_-]*)/manifest%.lua$")
    local manifest=id and manifestTables[id]
    if not manifest then return nil,"file not found" end
    local function encode(value)
        if type(value)=="string" then return string.format("%q",value) end
        if type(value)~="table" then return tostring(value) end
        local fields={}
        for key,item in pairs(value) do fields[#fields+1]="["..encode(key).."]="..encode(item) end
        return "{"..table.concat(fields,",").."}"
    end
    local source="return "..encode(manifest)
    return {readAll=function() return source end,close=function() return true end}
end
local canvasMethods={}
for _,name in ipairs({"text","paragraph","filledRectangle","rectangle","line"}) do
    canvasMethods[name]=function(self) return self end
end
local function newCanvas(width,height)
    return setmetatable({w=width,h=height},{__index=canvasMethods})
end
canvasMethods.clipping=function(_,_,_,width,height) return newCanvas(width,height) end
setmetatable(E,{__index=_G})
local currencyDataFactory=assert(loadfile("system/core/currency_data.lua"))()
currencyDataFactory(E)
function E.register(id,name,icon,width,height,definition)
    assert(type(id)=="string" and not registered[id],"application registered more than once: "..tostring(id))
    assert(type(definition)=="table","application definition must be a table: "..id)
    registered[id]=definition
    definition.id=id; definition.name=name; definition.iconId=icon
    definition.defaultWidth=width; definition.defaultHeight=height
    E.OS.registry[id]=definition
    E.OS.order[#E.OS.order+1]=id
end

local previousFs=rawget(_G,"fs")
_G.fs=E.fs
local Registry=assert(loadfile("system/core/app_registry.lua"))()
local AppManager=assert(loadfile("system/core/app_manager.lua"))()
local registry=Registry.new({root=packageRoot})
local entries=registry:scan()
assert(#entries==#ids,"app registry did not discover all real packages")
assert(#registry.errors==0,"app registry rejected a real package manifest: "..table.concat(registry.errors,"; "))
local function loadPackage(path)
    local chunk,err=loadfile(sourcePath(path))
    assert(chunk,err)
    return chunk()
end
AppManager.install(E,registry,loadPackage,"/.hccos")
AppManager.installBoot(E,registry,loadPackage)
_G.fs=previousFs

for _,id in ipairs(ids) do assert(registered[id],"missing app registration: "..id) end
assert(registered.updates and type(registered.updates.init)=="function" and
    type(registered.updates.draw)=="function","Update Center service should register its GUI app")

for _,id in ipairs(ids) do
    local definition=registered[id]
    local app=setmetatable({id=id,win={w=definition.defaultWidth or 500,
        h=definition.defaultHeight or 280,buttons={}},context=context},{__index=definition})
    if type(app.init)=="function" then
        local ok,err=pcall(app.init,app)
        assert(ok,"application init failed for "..id..": "..tostring(err))
    end
    if type(app.interval)=="function" then
        local ok,delay=pcall(app.interval,app)
        assert(ok,"application interval failed for "..id..": "..tostring(delay))
        assert(type(delay)=="number" and delay>0 and delay<60,
            "application interval is outside the expected range for "..id)
    end
    if type(app.update)=="function" then
        local ok,err=pcall(app.update,app)
        assert(ok,"application update failed for "..id..": "..tostring(err))
    end
    if type(app.draw)=="function" then
        local ok,err=pcall(app.draw,app,newCanvas(app.win.w,app.win.h))
        assert(ok,"application draw failed for "..id..": "..tostring(err))
    end
end

local notepadDefinition=registered.notepad
local firstNotepad=setmetatable({win={w=400,h=240,buttons={}},context=context},{__index=notepadDefinition})
local secondNotepad=setmetatable({win={w=400,h=240,buttons={}},context=context},{__index=notepadDefinition})
firstNotepad:init(); secondNotepad:init()
firstNotepad.lines[1]="instance one"
assert(secondNotepad.lines[1]=="" and firstNotepad.lines~=secondNotepad.lines,
    "application window state should not be shared between instances")

print("application module specs passed ("..#ids.." packages, registry/init/interval/update/draw)")

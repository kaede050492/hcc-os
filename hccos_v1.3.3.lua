-- Legacy HCC OS v1.3.3 compatibility pack. The active v1.5 desktop is modular
-- and is booted from /.hccos/system; this file is kept only for migration.
-- Run: hccos    Auto-start: /startup.lua -> /hcc_os/boot.lua.
-- No external Lua modules. Settings are generated in /.hccos/config/settings;
-- /.hccos/settings remains a read-only v1.3.3 migration source.
-- GPU API: https://github.com/tom5454/Toms-Peripherals/wiki/GPUImpl
-- Coordinates in this program are zero-based; ONLY Driver converts to the
-- actual Tom's 1-based API. Bitmap input coordinates are also 1-based.
-- Apps record bounded display lists, never access the GPU or call sync.
-- Damage composition replays intersecting commands in back-to-front order.
-- Text damage expands to complete text bounds (native text has no scissor).
-- Estimated TPS measures CC timer delivery, not server processing MSPT.

local unpack = table.unpack or unpack
local floor, min, max = math.floor, math.min, math.max
local HCC_VERSION="1.4.0"
local HCC_VERSION_LABEL="HCC OS v"..HCC_VERSION
local HCC_CPU="Himantel Core 5 140"
local HCC_TARGET_W,HCC_TARGET_H=576,320
local HCC_BLOCKS_X,HCC_BLOCKS_Y,HCC_PIXELS_PER_BLOCK=9,5,64
local HCC_MAX_WINDOWS,HCC_MAX_LOGS,HCC_MAX_HISTORY=24,400,180
local function finite(n) return type(n)=="number" and n==n and math.abs(n)<1e12 end
local function clamp(n,a,b) return max(a,min(b,n)) end
local function now() return os.epoch("utc")/1000 end
local function jst() return os.date("!*t",floor(now())+32400) end
local function timeText(d) return string.format("%02d:%02d:%02d",d.hour,d.min,d.sec) end
local function dateText(d) return string.format("%04d-%02d-%02d",d.year,d.month,d.day) end
local function box(x,y,w,h) return {x=floor(x),y=floor(y),w=max(0,floor(w)),h=max(0,floor(h))} end
local function intersect(a,b)
    local x,y=max(a.x,b.x),max(a.y,b.y)
    local r,t=min(a.x+a.w,b.x+b.w),min(a.y+a.h,b.y+b.h)
    if r<=x or t<=y then return nil end
    return box(x,y,r-x,t-y)
end
local function union(a,b)
    local x,y=min(a.x,b.x),min(a.y,b.y)
    return box(x,y,max(a.x+a.w,b.x+b.w)-x,max(a.y+a.h,b.y+b.h)-y)
end
local function inside(r,x,y) return x>=r.x and y>=r.y and x<r.x+r.w and y<r.y+r.h end
local function copy(t) local r={} for k,v in pairs(t) do r[k]=v end return r end
local function ascii(s) return tostring(s or ""):gsub("[^\032-\126]","?") end
local function readFile(path,limit)
    if fs.isDir(path) then error("This is a directory") end
    if fs.getSize(path)>(limit or 65536) then error("File exceeds 64 KiB editor limit") end
    local f,err=fs.open(path,"r"); if not f then error(err or "Cannot open file") end
    local ok,data=pcall(f.readAll); f.close(); if not ok then error(data) end
    return data or ""
end
local defaults={gpuName="",keyboardName="",detectorName="",resolution=64,
    theme="black",clockInterval=1,radarInterval=0.5,serverInterval=2,
    centerX=470,centerZ=-33,dimension="minecraft:overworld",grid=true,clockMode="JST",
    snapEnabled=true,snapDistance=10,showRichIcons=true,taskbarLabels=true,
    inventoryRefresh=2,systemInterval=1,performanceHistory=60,
    wallpaperMode="black",wallpaperPath="",wallpaperCache=true,
    logLimit=400,networkRefresh=3,resourceRefresh=2,
    maxImageDownload=4194304,imageCacheLimit=4194304,imageCacheEnabled=true,
    configVersion=2,firstBootComplete=true,computerLabel="",accent="cyan",
    updateChannel="stable",autoUpdateCheck=false,
    updateRepository="https://github.com/himantel/hcc-os",computerId=""}
local cfg=copy(defaults)
local configPath="/.hccos/config/settings"
local legacyConfigPath="/.hccos/settings"
local configWarning
local function saveConfig()
    local ok,err=pcall(function()
        if not fs.exists("/.hccos") then fs.makeDir("/.hccos") end
        if not fs.exists("/.hccos/config") then fs.makeDir("/.hccos/config") end
        local f,e=fs.open(configPath,"w"); if not f then error(e or "Settings not writable") end
        local good,reason=pcall(f.write,textutils.serialize(cfg)); f.close()
        if not good then error(reason) end
    end)
    return ok,err
end
local configReadPath=fs.exists(configPath) and configPath or legacyConfigPath
if fs.exists(configReadPath) then
    local ok,data=pcall(function() return textutils.unserialize(readFile(configReadPath)) end)
    if ok and type(data)=="table" then
        for k,v in pairs(defaults) do
            if type(data[k])==type(v) and (type(v)~="number" or finite(data[k])) then cfg[k]=data[k] end
        end
    else configWarning="Invalid settings; using safe defaults" end
end
cfg.resolution=floor(clamp(cfg.resolution,16,64))
cfg.clockInterval=clamp(cfg.clockInterval,0.1,5)
cfg.radarInterval=clamp(cfg.radarInterval,0.25,5)
cfg.serverInterval=clamp(cfg.serverInterval,1,5)
cfg.snapDistance=floor(clamp(cfg.snapDistance,2,32))
cfg.inventoryRefresh=clamp(cfg.inventoryRefresh,0.5,10)
cfg.systemInterval=clamp(cfg.systemInterval,0.25,5)
cfg.performanceHistory=floor(clamp(cfg.performanceHistory,20,180))
cfg.logLimit=floor(clamp(cfg.logLimit,50,HCC_MAX_LOGS))
cfg.networkRefresh=clamp(cfg.networkRefresh,1,15)
cfg.resourceRefresh=clamp(cfg.resourceRefresh,0.5,15)
cfg.maxImageDownload=floor(clamp(cfg.maxImageDownload,65536,16777216))
cfg.imageCacheLimit=floor(clamp(cfg.imageCacheLimit,262144,16777216))
cfg.snapEnabled=cfg.snapEnabled~=false
cfg.showRichIcons=cfg.showRichIcons~=false
cfg.taskbarLabels=cfg.taskbarLabels~=false
cfg.wallpaperMode=({black=true,center=true,fit=true,fill=true,stretch=true,tile=true})[cfg.wallpaperMode] and cfg.wallpaperMode or "black"
cfg.wallpaperPath=type(cfg.wallpaperPath)=="string" and cfg.wallpaperPath:sub(1,128) or ""
cfg.wallpaperCache=cfg.wallpaperCache~=false
cfg.imageCacheEnabled=cfg.imageCacheEnabled~=false
cfg.clockMode=cfg.clockMode=="MCT" and "MCT" or "JST"
local palettes={
    black={desktopBackground=0xFF000000,windowBackground=0xFF10151B,panelBackground=0xFF202B36,
        textPrimary=0xFFF0F5FA,textSecondary=0xFFACBDCB,border=0xFF526472,accent=0xFF46CFF0,
        success=0xFF60DA90,warning=0xFFFFC65B,error=0xFFFF6978,grid=0xFF253440},
    midnight={desktopBackground=0xFF030914,windowBackground=0xFF0E1C30,panelBackground=0xFF1B304C,
        textPrimary=0xFFF0F5FA,textSecondary=0xFFB0C5DD,border=0xFF52769B,accent=0xFFABA0FF,
        success=0xFF60DA90,warning=0xFFFFC65B,error=0xFFFF6978,grid=0xFF263D59}}
if not palettes[cfg.theme] then cfg.theme="black" end
local P=palettes[cfg.theme]
local accentColors={cyan=0xFF46CFF0,blue=0xFF70C8FF,purple=0xFFB9A7FF,green=0xFF60DA90,gold=0xFFFFC65B,red=0xFFFF6978}
local function applyAccent()
    local color=accentColors[tostring(cfg.accent or ""):lower()]
    if color then P=copy(P); P.accent=color end
end
applyAccent()
local devices={list={},keyboards={},inventories={},modems={}}
local gpu
local Driver={w=576,h=320,metrics={},cellWidth=6,calls=0,syncs=0,error=nil}
local function hasMethods(p,names)
    if not p then return false end
    for _,n in ipairs(names) do if type(p[n])~="function" then return false end end
    return true
end
local function scanDevices()
    devices.list={}; devices.detector=nil; devices.detectorName=nil; devices.keyboards={}; devices.inventories={}; devices.modems={}
    local candidates={}
    local namesOk,names=pcall(peripheral.getNames)
    if not namesOk or type(names)~="table" then gpu=nil; devices.gpuName=nil; Driver.error="Peripheral enumeration failed"; logLine("ERROR",Driver.error); return false end
    table.sort(names)
    for _,name in ipairs(names) do
        local ok,p=pcall(peripheral.wrap,name)
        local typeOk,typesValue=pcall(function() return {peripheral.getType(name)} end); local types=typeOk and typesValue or {"unknown"}
        devices.list[#devices.list+1]={name=name,kind=table.concat(types,",")}
        if ok and p then
            if hasMethods(p,{"getSize","refreshSize","setSize","filledRectangle","line","drawText","getTextLength","sync","fill"}) then
                candidates[#candidates+1]={name=name,p=p}
            end
            if hasMethods(p,{"getOnlinePlayers","getPlayerPos"}) and
                (cfg.detectorName=="" or name==cfg.detectorName) and not devices.detector then
                devices.detector=p; devices.detectorName=name
            end
            if hasMethods(p,{"setFireNativeEvents"}) and (cfg.keyboardName=="" or name==cfg.keyboardName) then
                -- Keep peripheral names on events, enabling filtering and no mode mutation.
                pcall(p.setFireNativeEvents,false)
                devices.keyboards[name]=true
            end
            -- Inventory APIs vary between mods.  Classify only peripherals
            -- that expose both the standard list and size methods.
            if hasMethods(p,{"size","list"}) then
                local valid=pcall(function() local n=p.size(); assert(finite(n) and n>=1) end)
                if valid then devices.inventories[#devices.inventories+1]={name=name,p=p} end
            end
            if hasMethods(p,{"open","close","isOpen","transmit"}) then
                local wireless=false
                if type(p.isWireless)=="function" then local wok,wvalue=pcall(p.isWireless); wireless=wok and wvalue==true end
                devices.modems[#devices.modems+1]={name=name,p=p,wireless=wireless}
            end
        end
    end
    local chosen
    for _,c in ipairs(candidates) do
        if cfg.gpuName~="" and c.name==cfg.gpuName then chosen=c; break end
        if cfg.gpuName=="" and (not chosen or c.name==devices.gpuName) then chosen=c end
    end
    gpu=chosen and chosen.p or nil
    devices.gpuName=chosen and chosen.name or nil
    Driver.error=nil; Driver.metrics={}
    if gpu then
        local ok,err=pcall(function()
            gpu.refreshSize()
            sleep(0.1) -- refreshSize is queued on the Minecraft server thread.
            gpu.setSize(cfg.resolution)
            if gpu.setFont then gpu.setFont("ascii") end
            Driver.cellWidth=6
            for ch=32,126 do
                local width=gpu.getTextLength(string.char(ch),1,1)
                Driver.metrics[string.char(ch)]=width
                Driver.cellWidth=max(Driver.cellWidth,width)
            end
            local w,h=gpu.getSize()
            assert(finite(w) and finite(h) and w>=96 and h>=96,"Display must be at least 96x96")
            Driver.w,Driver.h=floor(w),floor(h)
        end)
        if not ok then Driver.error=tostring(err); gpu=nil end
    end
    return gpu~=nil
end
function Driver.getWidth() return Driver.w end
function Driver.getHeight() return Driver.h end
function Driver.getActualSize()
    if gpu then
        local ok,w,h=pcall(gpu.getSize)
        if ok and finite(w) and finite(h) then return w,h end
    end
    return Driver.w,Driver.h
end
function Driver.call(method,...)
    if not gpu then return end
    local ok,err=pcall(gpu[method],...)
    if not ok then Driver.error=tostring(err); gpu=nil; return end
    Driver.calls=Driver.calls+1
end
function Driver.clear(color) Driver.call("fill",color) end
function Driver.sync() if gpu then Driver.call("sync"); Driver.syncs=Driver.syncs+1 end end
function Driver.measure(s,scale)
    s=ascii(s); scale=scale or 1
    local total=0
    for i=1,#s do
        local ch=s:sub(i,i)
        if not Driver.metrics[ch] then
            local ok,w=false,6
            if gpu then ok,w=pcall(gpu.getTextLength,ch,1,1) end
            Driver.metrics[ch]=(ok and finite(w) and w>0) and w or 6
        end
        total=total+Driver.metrics[ch]*scale
    end
    return total
end
-- Liang-Barsky clipping: both endpoints outside can still cross the viewport.
local function clipLine(x1,y1,x2,y2,r)
    if r.w<1 or r.h<1 then return end
    local dx,dy=x2-x1,y2-y1; local lo,hi=0,1
    local pp={-dx,dx,-dy,dy}; local qq={x1-r.x,r.x+r.w-1-x1,y1-r.y,r.y+r.h-1-y1}
    for i=1,4 do
        if pp[i]==0 then if qq[i]<0 then return end
        else
            local t=qq[i]/pp[i]
            if pp[i]<0 then lo=max(lo,t) else hi=min(hi,t) end
            if lo>hi then return end
        end
    end
    return floor(clamp(x1+lo*dx+0.5,r.x,r.x+r.w-1)),floor(clamp(y1+lo*dy+0.5,r.y,r.y+r.h-1)),
        floor(clamp(x1+hi*dx+0.5,r.x,r.x+r.w-1)),floor(clamp(y1+hi*dy+0.5,r.y,r.y+r.h-1))
end
function Driver.filledRectangle(x,y,w,h,color,clip)
    if not (finite(x) and finite(y) and finite(w) and finite(h)) then return end
    local r=intersect(box(x,y,w,h),clip or box(0,0,Driver.w,Driver.h))
    if r then r=intersect(r,box(0,0,Driver.w,Driver.h)) end
    if r then Driver.call("filledRectangle",r.x+1,r.y+1,r.w,r.h,color) end
end
function Driver.pixel(x,y,color,clip) Driver.filledRectangle(x,y,1,1,color,clip) end
function Driver.line(x1,y1,x2,y2,color,clip)
    if not (finite(x1) and finite(y1) and finite(x2) and finite(y2)) then return end
    local r=intersect(clip or box(0,0,Driver.w,Driver.h),box(0,0,Driver.w,Driver.h))
    if not r then return end
    local a,b,c,d=clipLine(x1,y1,x2,y2,r)
    if a then Driver.call("line",a+1,b+1,c+1,d+1,color) end
end
function Driver.rectangle(x,y,w,h,color,clip)
    if not (finite(x) and finite(y) and finite(w) and finite(h)) or w<=0 or h<=0 then return end
    Driver.line(x,y,x+w-1,y,color,clip); Driver.line(x,y+h-1,x+w-1,y+h-1,color,clip)
    Driver.line(x,y,x,y+h-1,color,clip); Driver.line(x+w-1,y,x+w-1,y+h-1,color,clip)
end
function Driver.text(cmd)
    local r=cmd.bounds
    if r.x<0 or r.y<0 or r.x+r.w>Driver.w or r.y+r.h>Driver.h then return end
    Driver.call("drawText",r.x+1,r.y+1,cmd.value,cmd.color,-1,cmd.scale,1)
end
-- A Canvas records local coordinates into an absolute, pre-clipped display list.
local Canvas={}; Canvas.__index=Canvas
local function canvas(list,x,y,w,h,clip)
    return setmetatable({list=list,x=x,y=y,w=w,h=h,clip=intersect(box(x,y,w,h),clip or box(0,0,Driver.w,Driver.h)) or box(0,0,0,0)},Canvas)
end
function Canvas:getWidth() return self.w end
function Canvas:getHeight() return self.h end
function Canvas:clipping(x,y,w,h) return canvas(self.list,self.x+x,self.y+y,w,h,self.clip) end
function Canvas:filledRectangle(x,y,w,h,color)
    if not (finite(x) and finite(y) and finite(w) and finite(h)) then return end
    local r=intersect(box(self.x+x,self.y+y,w,h),self.clip)
    if r then self.list[#self.list+1]={kind="fill",bounds=r,color=color or P.panelBackground} end
end
function Canvas:clear(color) self:filledRectangle(0,0,self.w,self.h,color or P.windowBackground) end
function Canvas:pixel(x,y,color) self:filledRectangle(x,y,1,1,color) end
function Canvas:line(x1,y1,x2,y2,color)
    if not (finite(x1) and finite(y1) and finite(x2) and finite(y2)) then return end
    local a,b,c,d=clipLine(self.x+x1,self.y+y1,self.x+x2,self.y+y2,self.clip)
    if a then self.list[#self.list+1]={kind="line",bounds=box(min(a,c),min(b,d),math.abs(c-a)+1,math.abs(d-b)+1),a=a,b=b,c=c,d=d,color=color or P.border} end
end
function Canvas:rectangle(x,y,w,h,color)
    self:line(x,y,x+w-1,y,color); self:line(x,y+h-1,x+w-1,y+h-1,color)
    self:line(x,y,x,y+h-1,color); self:line(x+w-1,y,x+w-1,y+h-1,color)
end
function Canvas:text(x,y,s,color,scale)
    if not (finite(x) and finite(y)) then return end
    scale=finite(scale) and floor(clamp(scale,1,4)) or 1
    x,y=floor(self.x+x),floor(self.y+y); s=ascii(s)
    -- ASCII native font is 8 pixels tall. Reserve 9 to include a safe gutter.
    local height=9*scale
    if y<self.clip.y or y+height>self.clip.y+self.clip.h then return end
    local start,width,out=x,0,{}
    for i=1,#s do
        local ch=s:sub(i,i); local cw=Driver.measure(ch,scale)
        if x+cw>self.clip.x+self.clip.w then break end
        if x>=self.clip.x then
            if #out==0 then start=x end
            out[#out+1]=ch; width=width+cw
        end
        x=x+cw
    end
    if #out>0 then self.list[#self.list+1]={kind="text",bounds=box(start,y,width,height),value=table.concat(out),color=color or P.textPrimary,scale=scale} end
end
function Canvas:paragraph(x,y,s,color,maxWidth,maxRows)
    local width=maxWidth or self.w-x; local row=""; local count=0
    for word in (ascii(s).." "):gmatch("(%S+)%s+") do
        if Driver.measure(row..word)>width and row~="" then
            self:text(x,y+count*12,row,color); count=count+1; row=""
            if count>=(maxRows or 10) then return end
        end
        row=row..word.." "
    end
    self:text(x,y+count*12,row,color)
end

local OS={windows={},damage={},registry={},order={},active=nil,modal=nil,toast=nil,
    menu=false,menuIndex=1,iconIndex=1,context=nil,pointer={x=0,y=0,visible=false},held={},running=true,
    desktopHover=nil,
    desktop={},task={},overlay={},desktopDirty=true,taskDirty=true,overlayDirty=true,
    started=now(),renderCount=0,renderRate=0,syncRate=0,frameTimer=nil,drag=nil,appTimers={},
    mouseButtons={},hover=nil,logs={},logSequence=0}
local TITLE,TASK=18,20
local mark
local function logLine(level,message)
    level=({INFO=true,WARN=true,ERROR=true})[level] and level or "INFO"
    OS.logSequence=OS.logSequence+1
    OS.logs[#OS.logs+1]={n=OS.logSequence,time=now(),level=level,message=ascii(message)}
    local limit=clamp(floor(cfg.logLimit or 400),50,HCC_MAX_LOGS)
    while #OS.logs>limit do table.remove(OS.logs,1) end
    for _,w in ipairs(OS.windows) do if w.id=="logs" then mark(w) end end
end
local function screen() return box(0,0,Driver.w,Driver.h) end
local function invalidate(r)
    r=intersect(r,screen()); if not r then return end
    -- Merge intersecting damage, but never combine unrelated windows by default.
    local i=1
    while i<=#OS.damage do
        if intersect(r,OS.damage[i]) then r=union(r,table.remove(OS.damage,i)); i=1 else i=i+1 end
    end
    OS.damage[#OS.damage+1]=r
    if #OS.damage>32 then OS.damage={screen()} end
end
mark=function(win)
    if not win then return end
    win.dirty=true
    if not win.minimized then invalidate(win) end
end
local function taskDirty() OS.taskDirty=true; invalidate(box(0,Driver.h-TASK,Driver.w,TASK)) end
local function overlayDirty()
    for _,cmd in ipairs(OS.overlay) do invalidate(cmd.bounds) end
    OS.overlayDirty=true
end
local function notify(message,color)
    overlayDirty(); OS.toast={message=ascii(message),color=color or P.accent,untilTime=now()+4}
    logLine("INFO",message)
end
local function appCall(win,method,...)
    if win.crash then return end
    local f=win.app[method]; if not f then return end
    local ok,result=pcall(f,win.app,...)
    if not ok then
        win.crash=ascii(result); mark(win); logLine("ERROR",win.name.."."..method..": "..win.crash); notify(win.name.." stopped: "..win.crash,P.error)
        return nil
    end
    return result
end
local function focus(win)
    local previous=OS.active
    if win.minimized then appCall(win,"resume"); win.nextUpdate=nil end
    for i,w in ipairs(OS.windows) do if w==win then table.remove(OS.windows,i); break end end
    OS.windows[#OS.windows+1]=win; OS.active=win; win.minimized=false
    mark(previous); mark(win); taskDirty(); OS.desktopDirty=true; invalidate(box(0,0,Driver.w,Driver.h-TASK))
end
local function fit(win)
    local minW=min(win.minWidth or 150,Driver.w)
    local minH=min(win.minHeight or 90,Driver.h-TASK)
    win.w=floor(clamp(win.w,minW,Driver.w))
    win.h=floor(clamp(win.h,minH,Driver.h-TASK))
    local visible=8
    win.x=floor(clamp(win.x,-win.w+visible,Driver.w-visible))
    win.y=floor(clamp(win.y,-TITLE+visible,Driver.h-TASK-visible-win.h))
end
local function allDirty()
    OS.desktopDirty=true; OS.taskDirty=true; OS.overlayDirty=true; OS.damage={screen()}
    for _,w in ipairs(OS.windows) do fit(w); w.dirty=true end
end
local function dialog(title,message,buttons,callback,input)
    overlayDirty()
    OS.drag=nil
    local safeButtons=type(buttons)=="table" and buttons or {"OK"}
    local safeCallback=type(callback)=="function" and callback or nil
    if callback~=nil and not safeCallback then logLine("WARN","Ignored non-function dialog callback") end
    local safeInput=input==nil and nil or tostring(input)
    OS.modal={title=ascii(title),message=ascii(message),buttons=safeButtons,callback=safeCallback,
        input=safeInput,index=safeInput~=nil and 1 or #safeButtons,pos=safeInput and #safeInput or 0}
end
local function dismiss(choice)
    local m=OS.modal; if not m then return end
    OS.modal=nil; overlayDirty()
    if type(m.callback)=="function" then
        local ok,err=pcall(m.callback,choice,m.input)
        if not ok then logLine("ERROR","Dialog callback: "..tostring(err)); dialog("Error",tostring(err),{"OK"}) end
    end
end
local function removeWindow(win)
    if win.timer then os.cancelTimer(win.timer); OS.appTimers[win.timer]=nil; win.timer=nil end
    invalidate(win)
    for i,w in ipairs(OS.windows) do if win==w then table.remove(OS.windows,i); break end end
    if OS.active==win then
        OS.active=nil
        for i=#OS.windows,1,-1 do if not OS.windows[i].minimized then OS.active=OS.windows[i]; break end end
    end
    mark(OS.active); taskDirty(); OS.desktopDirty=true; invalidate(box(0,0,Driver.w,Driver.h-TASK))
end
local function closeWindow(win)
    if not win then return end
    if not win.crash and win.app.unsaved then
        dialog("Unsaved changes","Discard changes in "..win.name.."?",{"Yes","No"},function(b)
            if b=="Yes" then appCall(win,"close"); removeWindow(win) end
        end)
    else appCall(win,"close"); removeWindow(win) end
end
local function maximize(win)
    invalidate(win)
    if win.restore then
        local restore=win.restore; win.restore=nil
        for k,v in pairs(restore) do win[k]=v end
    else
        win.restore={x=win.x,y=win.y,w=win.w,h=win.h,minimized=win.minimized}
        win.x=0; win.y=0; win.w=Driver.w; win.h=Driver.h-TASK; win.minimized=false
    end
    fit(win); mark(win)
end
local function openApp(id,args)
    local def=OS.registry[id]; if not def then return end
    if id~="notepad" then for _,w in ipairs(OS.windows) do if w.id==id then focus(w); return w end end end
    if #OS.windows>=HCC_MAX_WINDOWS then notify("Window limit reached ("..HCC_MAX_WINDOWS..")",P.warning); return end
    local win={id=id,name=def.name,x=70+(#OS.windows%5)*14,y=12+(#OS.windows%5)*12,
        w=def.defaultWidth,h=def.defaultHeight,dirty=true,commands={},buttons={}}
    fit(win)
    win.app=setmetatable({win=win},{__index=def})
    focus(win); appCall(win,"init",args); logLine("INFO","App start: "..id); return win
end
local function register(id,name,icon,w,h,app)
    app.id=id; app.iconId=id; app.name=name; app.icon=icon; app.defaultWidth=w; app.defaultHeight=h
    OS.registry[id]=app; OS.order[#OS.order+1]=id
end
local function button(app,c,x,y,w,label,fn)
    local hit={x=x,y=y,w=w,h=16,action=type(fn)=="function" and fn or function() end}
    local hot=OS.hover and OS.hover.win==app.win and OS.hover.hit
    local fill=hot and (hot.x==x and hot.y==y and P.border or P.panelBackground) or P.panelBackground
    c:filledRectangle(x,y,w,16,fill); c:rectangle(x,y,w,16,hot and P.accent or P.border)
    c:text(x+4,y+3,label,P.textPrimary)
    app.win.buttons[#app.win.buttons+1]=hit
end
local function errorBox(message) logLine("ERROR",message); dialog("Error",ascii(message),{"OK"}) end
local function requestExit()
    local unsaved=0
    for _,w in ipairs(OS.windows) do if w.app.unsaved then unsaved=unsaved+1 end end
    dialog("Exit HCC OS",unsaved>0 and ("Discard "..unsaved.." unsaved document(s) and exit?") or "Exit to CraftOS?",{"Yes","No"},function(b)
        if b=="Yes" then OS.running=false end
    end)
end

-- Shared widget toolkit.  New applications use these bounded primitives so
-- layouts remain readable on both 576x320 displays and smaller test screens.
local ICON_REGISTRY={
    clock={glyph={"  +++  "," +###  ","+####+","+####+","+####+"," +##+ ","  +++  "}},
    files={glyph={"  +++  "," +####+","+#####","+####+","+####+","+####+","+++++++"}},
    peripherals={glyph={" ++ ++ ","+##### ","##+### ","######+","##+### ","+##### "," ++ ++ "}},
    performance={glyph={"#     +","##   ++","#+  +++","#+ ++++","#+++++ ","++++++ ","+++++++"}},
    calendar={glyph={"+++++++","+##### ","+##+##+","+##### ","+##### ","+##### ","+++++++"}},
    currency={glyph={"  +++  "," +###+ ","+##### ","+##+##+","+##### "," +###+ ","  +++  "}},
    network={glyph={"   +   ","  +++  ","+++ +++","  +++  ","+++ +++","  +++  ","   +   "}},
    taskmgr={glyph={"+++++++","+#####+","+#+++#+","+#+++#+","+##### ","+  ++  ","  +++  "}},
    radar={glyph={"  +++  "," ++#++ ","+##### ","++###++","+##### "," ++#++ ","  +++  "}},
    image={glyph={"+++++++","+     +","+  ++ +","+ +## +","+##### ","+     +","+++++++"}},
    resource={glyph={" +++++ ","+##### ","+#+##+ ","+##### ","+##+#+ ","+##### "," +++++ "}},
    terminal={glyph={"       ","+     #","++   ##","+++ ## ","++   ##","+     #","       "}},
    server={glyph={"+++++++","+##+##+","+##### ","+##+##+","+##### ","+##+##+","+++++++"}},
    web={glyph={"  +++  "," ++#++ ","+##### ","+# +#+ ","+##### "," ++#++ ","  +++  "}},
    logs={glyph={"+++++++","+##### ","+##    ","+##### ","+##    ","+##### ","+++++++"}},
    settings={glyph={"  +++  "," +### +","+##### ","+##+##+","+##### "," +### +","  +++  "}},
    notepad={glyph={"  +++++"," +####+","+##### ","+###  +","+##### ","+##### ","+++++++"}},
    inventory={glyph={"+++++++","+##### ","+#+##+ ","+##+#+ ","+#+##+ ","+##### ","+++++++"}},
    system={glyph={"  +++  "," +### +","+##### ","+#+++#+","+##### "," +### +","  +++  "}},
    diagnostics={glyph={"    ++ ","   +## ","  +### "," +#### ","+####+ ","+####  ","+++    "}},
    updates={glyph={"+++++++","+  +  +","+  +  +","+##### ","+  +  +","+  +  +","+++++++"}},
    default={glyph={"+++++++","+##### ","+##### ","+##### ","+##### ","+##### ","+++++++"}}
}
local ICON_ACCENTS={clock=0xFF72D6FF,files=0xFFB8A06A,peripherals=0xFF69D4FF,performance=0xFF66E0A3,calendar=0xFFFFC65B,currency=0xFFFFD166,network=0xFF9EAEFF,taskmgr=0xFF7DD3FC,radar=0xFF64D8FF,image=0xFFB9A7FF,resource=0xFFD49A6A,terminal=0xFFF0F5FA,server=0xFF72D6FF,web=0xFF70C8FF,logs=0xFFBFC9D4,settings=0xFFB7C0CB,notepad=0xFFFFC65B,inventory=0xFFB8A06A,system=0xFF75E0FF,diagnostics=0xFF80E0A0,updates=0xFF80C7FF}
local ICON_CACHE={}
local function iconInstructions(id,size,def)
    local key=id..":"..tostring(size); if ICON_CACHE[key] then return ICON_CACHE[key] end
    local inner=size-4; local cell=max(1,floor(inner/7)); local ox=2+floor((inner-cell*7)/2); local oy=2+floor((inner-cell*7)/2); local out={}
    for py,row in ipairs(def.glyph) do for px=1,min(7,#row) do local ch=row:sub(px,px); if ch~=" " then out[#out+1]={x=ox+(px-1)*cell,y=oy+(py-1)*cell,w=cell,h=cell,ch=ch} end end end
    ICON_CACHE[key]=out; return out
end
local drawAppIcon
local iconIsOffline
drawAppIcon=function(c,appDef,x,y,size,state)
    size=max(6,floor(tonumber(size) or 16)); state=tostring(state or "normal"):lower()
    local id=type(appDef)=="table" and (appDef.id or appDef.iconId) or tostring(appDef or "default"); local def=ICON_REGISTRY[id] or ICON_REGISTRY.default
    local bg=P.panelBackground; local edge=P.border; local fg=P.textPrimary; local accent=ICON_ACCENTS[id] or P.accent
    if state=="hover" then bg=P.windowBackground; edge=P.accent elseif state=="selected" then bg=P.panelBackground; edge=P.accent elseif state=="running" then edge=P.accent elseif state=="disabled" then bg=P.windowBackground; fg=P.textSecondary; accent=P.border elseif state=="error" then edge=P.error elseif state=="offline" then edge=P.error; accent=P.textSecondary end
    c:filledRectangle(x,y,size,size,bg); c:rectangle(x,y,size,size,edge)
    for _,pixel in ipairs(iconInstructions(id,size,def)) do local color=pixel.ch=="+" and accent or fg; if pixel.ch=="o" then color=P.success elseif pixel.ch=="x" then color=P.warning end; c:filledRectangle(x+pixel.x,y+pixel.y,pixel.w,pixel.h,color) end
    if state=="running" then c:filledRectangle(x+size-5,y+2,3,3,P.accent) elseif state=="error" or state=="offline" then c:filledRectangle(x+size-5,y+2,3,3,P.error) end
end
local Widget={}
function Widget.panel(c,x,y,w,h,color,edge)
    c:filledRectangle(x,y,w,h,color or P.panelBackground)
    if edge~=false then c:rectangle(x,y,w,h,edge or P.border) end
end
function Widget.label(c,x,y,value,color,scale) c:text(x,y,value,color or P.textPrimary,scale or 1) end
function Widget.progress(c,x,y,w,h,value,limit,color,bg)
    limit=finite(limit) and limit>0 and limit or 1; value=finite(value) and clamp(value,0,limit) or 0
    Widget.panel(c,x,y,w,h,bg or P.windowBackground,P.border)
    if value>0 then c:filledRectangle(x+1,y+1,max(0,floor((w-2)*value/limit)),max(1,h-2),color or P.accent) end
end
function Widget.icon(c,x,y,def,selected)
    drawAppIcon(c,def,x,y,28,selected and "selected" or "normal")
end
function Widget.value(c,x,y,label,value,color)
    c:text(x,y,label,P.textSecondary); c:text(x+Driver.measure(label)+5,y,value,color or P.textPrimary)
end

-- Applications follow init/update/draw/onMouse/onKey/onChar/close; optional
-- methods can be omitted. Their only drawing capability is a bounded Canvas.

local Clock={}
function Clock:init() self.mode=cfg.clockMode; self:update() end
function Clock:interval() return cfg.clockInterval end
function Clock:update()
    self.date=jst()
    if self.mode=="MCT" then
        local seconds=floor(os.time("ingame")*3600)%86400
        self.value=string.format("%02d:%02d:%02d",floor(seconds/3600),floor(seconds/60)%60,seconds%60)
    else self.value=timeText(self.date) end
    mark(self.win)
end
function Clock:onKey(k)
    if k==keys.e then self.mode=self.mode=="JST" and "MCT" or "JST"; cfg.clockMode=self.mode; self:update() end
end
function Clock:draw(c)
    local scale=c.w>=230 and 3 or (c.w>=160 and 2 or 1)
    c:text(10,10,self.mode=="JST" and "ASIA / TOKYO  UTC+09:00" or "MINECRAFT TIME",P.accent)
    local tw=Driver.measure(self.value,scale)
    c:text(max(6,(c.w-tw)/2),32,self.value,P.textPrimary,scale)
    c:text(10,40+scale*9,dateText(self.date).."  JST DATE",P.textSecondary)
    button(self,c,10,c.h-22,min(140,c.w-20),"E: JST / MCT",function() self:onKey(keys.e) end)
end
register("clock","Clock","CL",260,132,Clock)

local function monthDays(y,m)
    if m==2 then return (y%4==0 and (y%100~=0 or y%400==0)) and 29 or 28 end
    return ({31,28,31,30,31,30,31,31,30,31,30,31})[m]
end
local function weekday(y,m,d)
    local t={0,3,2,5,0,3,5,1,4,6,2,4}
    if m<3 then y=y-1 end
    return (y+floor(y/4)-floor(y/100)+floor(y/400)+t[m]+d)%7
end
local Calendar={}
function Calendar:init() local d=jst(); self.year=d.year; self.month=d.month end
function Calendar:interval() return self.slide and 0.05 or 30 end
function Calendar:move(delta)
    local n=self.year*12+self.month-1+delta
    local y,m=floor(n/12),n%12+1
    if y<1 or y>9999 then return end
    self.slide={year=self.year,month=self.month,at=now(),direction=delta>0 and 1 or -1}
    self.year,self.month=y,m; self.win.nextUpdate=now(); mark(self.win)
end
function Calendar:update()
    if self.slide and now()-self.slide.at>=0.2 then self.slide=nil end
    mark(self.win)
end
function Calendar:onKey(k)
    if k==keys.left then self:move(-1) elseif k==keys.right then self:move(1)
    elseif k==keys.up then self:move(-12) elseif k==keys.down then self:move(12)
    elseif k==keys.home then self:init(); self.slide=nil; mark(self.win) end
end
function Calendar:drawMonth(c,y,m)
    local d=jst(); local cw=c.w/7; local ch=max(12,(c.h-17)/6)
    for i,s in ipairs({"SU","MO","TU","WE","TH","FR","SA"}) do c:text((i-1)*cw+4,2,s,i==1 and P.error or P.textSecondary) end
    local first=weekday(y,m,1)
    for day=1,monthDays(y,m) do
        local ix=first+day-1; local x=(ix%7)*cw; local yy=17+floor(ix/7)*ch
        if day==d.day and m==d.month and y==d.year then c:filledRectangle(x+1,yy,cw-2,ch-2,P.panelBackground); c:rectangle(x+1,yy,cw-2,ch-2,P.accent) end
        c:text(x+5,yy+3,tostring(day),P.textPrimary)
    end
end
function Calendar:draw(c)
    button(self,c,6,5,28,"<",function() self:move(-1) end)
    button(self,c,c.w-34,5,28,">",function() self:move(1) end)
    c:text(45,9,string.format("%04d / %02d",self.year,self.month),P.accent)
    local area=c:clipping(6,29,c.w-12,c.h-47)
    if self.slide then
        local t=clamp((now()-self.slide.at)/0.2,0,1); t=1-(1-t)^3
        local shift=floor(area.w*t)*self.slide.direction
        self:drawMonth(area:clipping(-shift,0,area.w,area.h),self.slide.year,self.slide.month)
        self:drawMonth(area:clipping(self.slide.direction*area.w-shift,0,area.w,area.h),self.year,self.month)
    else self:drawMonth(area,self.year,self.month) end
    c:text(6,c.h-13,"LEFT/RIGHT: MONTH  UP/DOWN: YEAR",P.textSecondary)
end
register("calendar","Calendar","CA",294,248,Calendar)

local function dimension(s)
    if type(s)~="string" or s=="" then return "unknown" end
    local aliases={overworld="minecraft:overworld",the_nether="minecraft:the_nether",nether="minecraft:the_nether",
        the_end="minecraft:the_end",["end"]="minecraft:the_end"}
    return aliases[s:lower()] or s
end
local function rangeFor(distance)
    local r=256
    while r<distance*1.12 do r=r*2 end
    return r
end
local playerColors={0xFF46CFF0,0xFFFFC65B,0xFF60DA90,0xFFBA9FFF,0xFFFF839E,0xFF89AEFF}
local function playerColor(name)
    local n=0; for i=1,#name do n=(n*31+name:byte(i))%997 end
    return playerColors[n%#playerColors+1]
end
local Radar={}
function Radar:init() self.players={}; self.dim=dimension(cfg.dimension); self.dims={self.dim}; self.page=1; self.range=256; self:update() end
function Radar:interval() return cfg.radarInterval end
function Radar:update()
    self.players={}; self.unavailable=0; self.online=0; self.message=nil
    local detector=devices.detector
    if not detector then self.message="Player Detector unavailable"; mark(self.win); return end
    local ok,names=pcall(detector.getOnlinePlayers)
    if not ok or type(names)~="table" then self.message="Detector read failed"; mark(self.win); return end
    table.sort(names); self.online=#names
    local dims={[dimension(cfg.dimension)]=true,[self.dim]=true}; local far=0
    for _,name in ipairs(names) do
        local good,p=pcall(detector.getPlayerPos,name)
        if good and type(p)=="table" and finite(p.x) and finite(p.z) then
            local dim=dimension(p.dimension); dims[dim]=true
            if dim==self.dim and dim~="unknown" then
                local dx,dz=p.x-cfg.centerX,p.z-cfg.centerZ
                local distance=math.sqrt(dx*dx+dz*dz); far=max(far,distance)
                self.players[#self.players+1]={name=name,x=p.x,y=p.y,z=p.z,yaw=p.yaw,distance=distance,color=playerColor(name)}
            end
        else self.unavailable=self.unavailable+1 end
    end
    self.dims={}; for d in pairs(dims) do self.dims[#self.dims+1]=d end; table.sort(self.dims)
    self.range=rangeFor(far); self.far=far; mark(self.win)
end
function Radar:cycleDimension()
    local index=1; for i,d in ipairs(self.dims) do if d==self.dim then index=i end end
    self.dim=self.dims[index%#self.dims+1]; self.page=1; self:update()
end
function Radar:onKey(k)
    if k==keys.g then cfg.grid=not cfg.grid; mark(self.win)
    elseif k==keys.d then self:cycleDimension()
    elseif k==keys.right or k==keys.pageDown then self.page=self.page+1; mark(self.win)
    elseif k==keys.left or k==keys.pageUp then self.page=max(1,self.page-1); mark(self.win) end
end
function Radar:onMouse(kind,x,y,b) if kind=="scroll" then self.page=max(1,self.page+b); mark(self.win) end end
function Radar:draw(c)
    c:text(6,5,self.dim,P.accent)
    if self.message then c:paragraph(8,30,self.message,P.warning); return end
    c:text(6,18,string.format("%d HERE / %d ONLINE  +/- %d",#self.players,self.online,self.range),P.textSecondary)
    local listWidth=c.w>=340 and 146 or (c.w>=240 and 105 or 0)
    local map=c:clipping(5,34,c.w-listWidth-10,c.h-62)
    local cx,cy=map.w/2,map.h/2; local radius=max(1,min(map.w,map.h)/2-16)
    map:rectangle(0,0,map.w,map.h,P.border)
    if cfg.grid then
        for i=-2,2 do
            map:line(cx+i*radius/2,8,cx+i*radius/2,map.h-9,P.grid)
            map:line(8,cy+i*radius/2,map.w-9,cy+i*radius/2,P.grid)
        end
    end
    map:text(cx-3,3,"N",P.textSecondary); map:text(cx-3,map.h-12,"S",P.textSecondary)
    map:text(3,cy-4,"W",P.textSecondary); map:text(map.w-10,cy-4,"E",P.textSecondary)
    map:line(cx-3,cy,cx+3,cy,P.warning); map:line(cx,cy-3,cx,cy+3,P.warning)
    local occupied={}; local positions={}
    for i,p in ipairs(self.players) do
        local x=cx+(p.x-cfg.centerX)/self.range*radius
        local y=cy+(p.z-cfg.centerZ)/self.range*radius
        positions[i]={x=x,y=y}; occupied[#occupied+1]=box(x-4,y-4,9,9)
    end
    for i,p in ipairs(self.players) do
        local x,y=positions[i].x,positions[i].y
        map:filledRectangle(x-2,y-2,5,5,p.color)
        if finite(p.yaw) then
            local angle=math.rad(p.yaw)
            map:line(x,y,x-math.sin(angle)*9,y+math.cos(angle)*9,p.color)
        end
        local label=p.name
        if Driver.measure(label)>map.w/2 then label=label:sub(1,8)..".." end
        local tw=Driver.measure(label)
        local offsets={{6,-12},{6,5},{-tw-6,-12},{-tw-6,5},{-tw/2,-24},{-tw/2,17}}
        for _,offset in ipairs(offsets) do
            local r=box(x+offset[1],y+offset[2],tw,10); local free=r.x>=12 and r.y>=14 and r.x+r.w<map.w-12 and r.y+r.h<map.h-12
            for _,used in ipairs(occupied) do if intersect(r,used) then free=false; break end end
            if free then map:text(r.x,r.y,label,p.color); occupied[#occupied+1]=r; break end
        end
    end
    if listWidth>0 then
        local list=c:clipping(c.w-listWidth,34,listWidth-4,c.h-62)
        local rows=max(1,floor((list.h-14)/38)); local pages=max(1,math.ceil(#self.players/rows))
        self.page=clamp(self.page,1,pages)
        for row=1,rows do
            local p=self.players[(self.page-1)*rows+row]; if not p then break end
            local y=(row-1)*38
            list:text(0,y,p.name,p.color)
            list:text(0,y+11,string.format("X%.0f Z%.0f",p.x,p.z),P.textSecondary)
            list:text(0,y+22,string.format("Y%s  %.0fb",finite(p.y) and tostring(floor(p.y)) or "?",p.distance),P.textSecondary)
        end
        list:text(0,list.h-12,self.page.."/"..pages.."  ARROWS",P.textSecondary)
    end
    button(self,c,5,c.h-23,60,"D: DIM",function() self:cycleDimension() end)
    button(self,c,69,c.h-23,63,cfg.grid and "G: GRID+" or "G: GRID-",function() self:onKey(keys.g) end)
    c:text(139,c.h-19,"X"..cfg.centerX.." Z"..cfg.centerZ,P.textSecondary)
end
register("radar","Player Radar","RA",336,268,Radar)

local function historyPush(t,value) t[#t+1]=value; if #t>90 then table.remove(t,1) end end
local function healthColor(v,tps)
    if tps then return v>=19.5 and P.success or (v>=18 and P.warning or P.error) end
    return v<=50 and P.success or (v<=55 and P.warning or P.error)
end
local function graph(c,x,y,w,h,values,ceiling,color,threshold)
    c:rectangle(x,y,w,h,P.border)
    for i=1,3 do c:line(x+1,y+h*i/4,x+w-2,y+h*i/4,P.grid) end
    if threshold then c:line(x+1,y+h-2-clamp(threshold/ceiling,0,1)*(h-3),x+w-2,y+h-2-clamp(threshold/ceiling,0,1)*(h-3),P.warning) end
    local count=#values
    for i=2,count do
        local x1=x+1+(i-2)/89*(w-3); local x2=x+1+(i-1)/89*(w-3)
        local y1=y+h-2-clamp(values[i-1]/ceiling,0,1)*(h-3); local y2=y+h-2-clamp(values[i]/ceiling,0,1)*(h-3)
        c:line(x1,y1,x2,y2,color)
    end
end
local Server={}
function Server:init()
    self.mode="Estimated"; self.previous=now(); self.expected=cfg.serverInterval
    self.tpsHistory={}; self.tickHistory={}; self.manual={}; self.manualIndex=1; self.manualHistory={}
end
function Server:interval() return cfg.serverInterval end
function Server:resume()
    self.previous=now(); self.expected=cfg.serverInterval
    if self.mode=="Estimated" then self.tps=nil; self.tick=nil; self.tpsHistory={}; self.tickHistory={} end
end
function Server:update()
    local t=now(); local elapsed=t-self.previous; self.previous=t
    if self.mode=="Estimated" and elapsed>0 then
        self.tps=min(20,self.expected*20/elapsed)
        self.tick=elapsed*1000/(self.expected*20)
        historyPush(self.tpsHistory,self.tps); historyPush(self.tickHistory,self.tick)
    end
    self.expected=cfg.serverInterval; mark(self.win)
end
function Server:import()
    dialog("Manual sample","Paste /neoforge tps output, or: Overall 19.8 56",{"OK","Cancel"},function(b,value)
        if b~="OK" then return end
        local rows={}
        for line in (value.."\n"):gmatch("([^\r\n]+)") do
            local name,a,m=line:match("^%s*(.-):%s*([%d%.]+)%s*TPS%s*%(([%d%.]+)%s*ms/tick")
            if not a then name,a,m=line:match("^%s*(.-)%s+([%d%.]+)%s+([%d%.]+)%s*$") end
            a,m=tonumber(a),tonumber(m)
            if a and m and a>=0 and a<=20 and m>=0 and m<=100000 and name~="" then
                name=name:match("^%s*(.-)%s*$")
                local history=self.manualHistory[name] or {tps={},mspt={}}
                self.manualHistory[name]=history; historyPush(history.tps,a); historyPush(history.mspt,m)
                rows[#rows+1]={name=name,tps=a,mspt=m,at=now(),history=history}
            end
        end
        if #rows==0 then errorBox("Use: Overall 19.8 56 (TPS, MSPT in ms)"); return end
        self.manual=rows; self.manualIndex=1; self.mode="Manual"
        mark(self.win)
    end,"")
end
function Server:onKey(k)
    if k==keys.m then
        if self.mode=="Estimated" then if #self.manual==0 then self:import(); return end; self.mode="Manual"
        else self.mode="Estimated"; self.previous=now(); self.tps=nil; self.tick=nil; self.expected=cfg.serverInterval; self.win.nextUpdate=now() end
        if self.mode=="Estimated" then self.tpsHistory={}; self.tickHistory={} end
        mark(self.win)
    elseif k==keys.p then self:import()
    elseif (k==keys.left or k==keys.right) and self.mode=="Manual" and #self.manual>0 then
        self.manualIndex=(self.manualIndex-1+(k==keys.left and -1 or 1))%#self.manual+1
        mark(self.win)
    end
end
function Server:draw(c)
    local row=self.mode=="Manual" and self.manual[self.manualIndex] or nil
    local tps=row and row.tps or self.tps
    local value=row and row.mspt or self.tick
    local th=row and row.history.tps or self.tpsHistory
    local mh=row and row.history.mspt or self.tickHistory
    local source=row and ("Manual: "..row.name) or "Estimated: CC timer delivery"
    c:text(7,6,source,P.accent)
    c:text(7,20,tps and string.format("TPS: %.2f",tps) or "TPS: sampling...",tps and healthColor(tps,true) or P.textSecondary,c.w>=250 and 2 or 1)
    c:text(7,43,row and string.format("MSPT: %.2f ms",value) or "MSPT: Unavailable",row and healthColor(value,false) or P.warning)
    c:text(7,56,row and ("Age: "..floor(now()-row.at).."s  LEFT/RIGHT: dimension") or (value and string.format("Tick interval: %.2f ms (Estimated)",value) or "Waiting for timer sample"),P.textSecondary)
    local w=c.w-14
    c:filledRectangle(7,71,w,5,P.panelBackground)
    if tps then c:filledRectangle(7,71,w*clamp(tps/20,0,1),5,healthColor(tps,true)) end
    c:filledRectangle(7,81,w,5,P.panelBackground)
    if value then c:filledRectangle(7,81,w*clamp(value/100,0,1),5,row and healthColor(value,false) or P.accent) end
    local gh=max(12,floor((c.h-150)/2))
    c:text(7,92,"TPS 0-20 / last 90 samples",P.textSecondary)
    graph(c,7,104,w,gh,th,20,P.success)
    local yy=108+gh
    c:text(7,yy,row and "MSPT / 50ms reference" or "EST. INTERVAL / 50ms reference",P.textSecondary)
    local ceiling=100; for _,v in ipairs(mh) do ceiling=max(ceiling,v*1.1) end
    graph(c,7,yy+12,w,gh,mh,ceiling,P.accent,50)
    button(self,c,7,c.h-21,81,"M: SOURCE",function() self:onKey(keys.m) end)
    button(self,c,93,c.h-21,min(105,c.w-100),"P: PASTE DATA",function() self:import() end)
end
register("server","Server Monitor","SV",300,286,Server)

local Notepad={}
local function splitLines(s)
    local result={}; s=s:gsub("\r\n","\n"):gsub("\r","\n")
    for line in (s.."\n"):gmatch("(.-)\n") do result[#result+1]=line end
    return result
end
function Notepad:init(path)
    self.path=path; self.lines={""}; self.row=1; self.col=0; self.top=1; self.left=0; self.unsaved=false
    if path then
        local ok,data=pcall(readFile,path)
        if not ok then error(data) end
        self.lines=splitLines(data)
        -- Byte editing of UTF-8 could corrupt multi-byte characters. Preserve such
        -- files exactly and expose them as read-only, rather than corrupting data.
        self.readOnly=data:find("[^\009\010\013\032-\126]")~=nil or fs.isReadOnly(path)
        self.win.name=fs.getName(path)
    end
end
function Notepad:saveTo(path,confirmed)
    path=fs.combine("/",path)
    if path=="" or path=="/" or fs.isDir(path) then errorBox("Choose a file path"); return end
    if fs.exists(path) and path~=self.path and not confirmed then
        dialog("Overwrite file",path,{"Yes","No"},function(b) if b=="Yes" then self:saveTo(path,true) end end); return
    end
    local ok,err=pcall(function()
        local f,e=fs.open(path,"w"); if not f then error(e or "Cannot save") end
        local good,reason=pcall(f.write,table.concat(self.lines,"\n")); f.close(); if not good then error(reason) end
    end)
    if not ok then errorBox(err); return end
    self.path=path; self.win.name=fs.getName(path); self.unsaved=false; mark(self.win); taskDirty(); notify("Saved "..path,P.success)
end
function Notepad:save()
    if self.readOnly then errorBox("Read-only document"); return end
    if self.path then self:saveTo(self.path)
    else dialog("Save file","Enter a path",{"OK","Cancel"},function(b,value) if b=="OK" then self:saveTo(value) end end,"/note.txt") end
end
function Notepad:insert(s)
    if self.readOnly then return end
    s=s:gsub("\r\n","\n"):gsub("\r","\n"):gsub("[^\009\010\032-\126]","?"):gsub("\t","    ")
    local total=#s; for _,line in ipairs(self.lines) do total=total+#line+1 end
    if total>65536 then errorBox("Editor limit: 64 KiB"); return end
    local prefix=self.lines[self.row]:sub(1,self.col); local suffix=self.lines[self.row]:sub(self.col+1)
    local parts=splitLines(s)
    self.lines[self.row]=prefix..parts[1]
    if #parts==1 then self.lines[self.row]=self.lines[self.row]..suffix; self.col=self.col+#parts[1]
    else
        for i=2,#parts do table.insert(self.lines,self.row+i-1,parts[i]) end
        self.row=self.row+#parts-1; self.col=#parts[#parts]; self.lines[self.row]=self.lines[self.row]..suffix
    end
    self.unsaved=true; mark(self.win)
end
function Notepad:onChar(s) self:insert(s) end
function Notepad:onKey(k)
    if (OS.held[keys.leftCtrl] or OS.held[keys.rightCtrl]) and k==keys.s then self:save(); return end
    local line=self.lines[self.row]
    if k==keys.left then
        if self.col>0 then self.col=self.col-1 elseif self.row>1 then self.row=self.row-1; self.col=#self.lines[self.row] end
    elseif k==keys.right then
        if self.col<#line then self.col=self.col+1 elseif self.row<#self.lines then self.row=self.row+1; self.col=0 end
    elseif k==keys.up then self.row=max(1,self.row-1); self.col=min(self.col,#self.lines[self.row])
    elseif k==keys.down then self.row=min(#self.lines,self.row+1); self.col=min(self.col,#self.lines[self.row])
    elseif k==keys.home then self.col=0
    elseif k==keys["end"] then self.col=#line
    elseif k==keys.pageUp then self.row=max(1,self.row-(self.visibleRows or 8)); self.col=min(self.col,#self.lines[self.row])
    elseif k==keys.pageDown then self.row=min(#self.lines,self.row+(self.visibleRows or 8)); self.col=min(self.col,#self.lines[self.row])
    elseif not self.readOnly then
        if k==keys.enter then self:insert("\n"); return
        elseif k==keys.tab then self:insert("    "); return
        elseif k==keys.backspace then
            if self.col>0 then self.lines[self.row]=line:sub(1,self.col-1)..line:sub(self.col+1); self.col=self.col-1
            elseif self.row>1 then self.col=#self.lines[self.row-1]; self.lines[self.row-1]=self.lines[self.row-1]..line; table.remove(self.lines,self.row); self.row=self.row-1 end
            self.unsaved=true
        elseif k==keys.delete then
            if self.col<#line then self.lines[self.row]=line:sub(1,self.col)..line:sub(self.col+2)
            elseif self.row<#self.lines then self.lines[self.row]=line..table.remove(self.lines,self.row+1) end
            self.unsaved=true
        end
    end
    self.ensureCursor=true; mark(self.win)
end
function Notepad:onMouse(kind,x,y,b)
    if kind=="scroll" then
        if OS.held[keys.leftShift] or OS.held[keys.rightShift] then self.left=max(0,self.left+b*3)
        else self.top=clamp(self.top+b*3,1,max(1,#self.lines-(self.visibleRows or 1)+1)) end
        self.manualScroll=true
    elseif kind=="click" and y>=26 and y<(self.win.h-TITLE-16) then
        self.row=clamp(self.top+floor((y-26)/12),1,#self.lines)
        self.col=clamp(self.left+floor((x-6)/Driver.cellWidth),0,#self.lines[self.row]); self.ensureCursor=true
    end
    mark(self.win)
end
function Notepad:draw(c)
    button(self,c,5,4,48,"SAVE",function() self:save() end)
    c:text(61,8,self.readOnly and "READ ONLY (ASCII editor)" or (self.unsaved and "* UNSAVED" or "CTRL+S"),self.unsaved and P.warning or P.textSecondary)
    self.visibleRows=max(1,floor((c.h-43)/12)); local cols=max(1,floor((c.w-12)/Driver.cellWidth))
    if self.ensureCursor or (not self.manualScroll) then
        if self.row<self.top then self.top=self.row elseif self.row>=self.top+self.visibleRows then self.top=self.row-self.visibleRows+1 end
        if self.col<self.left then self.left=self.col elseif self.col>=self.left+cols then self.left=self.col-cols+1 end
    end
    self.ensureCursor=false; self.manualScroll=false
    local edit=c:clipping(6,26,c.w-12,c.h-43)
    for i=0,self.visibleRows-1 do
        local s=self.lines[self.top+i]; if not s then break end
        s=ascii(s)
        for j=1,cols do local ch=s:sub(self.left+j,self.left+j); if ch=="" then break end; edit:text((j-1)*Driver.cellWidth,i*12,ch,P.textPrimary) end
    end
    if OS.active==self.win and not self.readOnly then
        edit:line((self.col-self.left)*Driver.cellWidth,(self.row-self.top)*12,(self.col-self.left)*Driver.cellWidth,(self.row-self.top)*12+8,P.accent)
    end
    c:text(5,c.h-13,string.format("%d:%d  %s",self.row,self.col+1,self.path or "NEW FILE"),P.textSecondary)
end
register("notepad","Notepad","NP",400,268,Notepad)

local Files={}
function Files:init() self.path="/"; self.selected=1; self.top=1; self:refresh() end
function Files:refresh()
    self.entries=fs.list(self.path)
    table.sort(self.entries,function(a,b)
        local ad,bd=fs.isDir(fs.combine(self.path,a)),fs.isDir(fs.combine(self.path,b))
        if ad~=bd then return ad end; return a:lower()<b:lower()
    end)
    self.selected=clamp(self.selected,1,max(1,#self.entries)); mark(self.win)
end
function Files:open()
    local name=self.entries[self.selected]; if not name then return end
    local path=fs.combine(self.path,name)
    if fs.isDir(path) then self.path=path; self.selected=1; self.top=1; self:refresh()
    elseif name:lower():match("%.hcci$") then openApp("image",path)
    else openApp("notepad",path) end
end
function Files:up() self.path=fs.getDir(self.path); if self.path=="" then self.path="/" end; self.selected=1; self.top=1; self:refresh() end
function Files:delete()
    local name=self.entries[self.selected]; if not name then return end
    local path=fs.combine(self.path,name)
    if fs.isDir(path) or fs.isReadOnly(path) then errorBox("Only writable files can be deleted here"); return end
    dialog("Delete file","Permanently delete "..path.."?",{"Yes","No"},function(b)
        if b=="Yes" then local ok,e=pcall(fs.delete,path); if ok then self:refresh(); notify("Deleted "..name,P.warning) else errorBox(e) end end
    end)
end
function Files:onKey(k)
    if k==keys.up then self.selected=max(1,self.selected-1)
    elseif k==keys.down then self.selected=min(#self.entries,self.selected+1)
    elseif k==keys.enter then self:open()
    elseif k==keys.backspace then self:up()
    elseif k==keys.delete then self:delete()
    elseif k==keys.f5 then self:refresh() end
    mark(self.win)
end
function Files:onMouse(kind,x,y,b)
    if kind=="scroll" then self.selected=clamp(self.selected+b*3,1,max(1,#self.entries))
    elseif kind=="click" and y>=39 and y<self.win.h-TITLE-16 and x<(self.listWidth or 150) then
        local i=self.top+floor((y-39)/14)
        if i<=#self.entries then
            local double=self.selected==i and self.lastClick and now()-self.lastClick<0.4
            self.selected=i; self.lastClick=now(); if double then self:open() end
        end
    end
    mark(self.win)
end
function Files:draw(c)
    button(self,c,5,4,36,"UP",function() self:up() end)
    button(self,c,45,4,45,"OPEN",function() self:open() end)
    button(self,c,94,4,48,"DEL",function() self:delete() end)
    button(self,c,146,4,45,"NEW",function() openApp("notepad") end)
    c:text(5,25,self.path,P.accent)
    local rows=max(1,floor((c.h-54)/14)); self.listWidth=c.w>=270 and floor(c.w*0.6) or c.w-5
    if self.selected<self.top then self.top=self.selected elseif self.selected>=self.top+rows then self.top=self.selected-rows+1 end
    local list=c:clipping(5,39,self.listWidth-10,c.h-54)
    for i=0,rows-1 do
        local name=self.entries[self.top+i]; if not name then break end
        if self.top+i==self.selected then list:filledRectangle(0,i*14,list.w,13,P.panelBackground) end
        list:text(3,i*14+2,(fs.isDir(fs.combine(self.path,name)) and "+ " or "  ")..name,P.textPrimary)
    end
    local name=self.entries[self.selected]
    if c.w>=270 and name then
        local right=c:clipping(self.listWidth+5,39,c.w-self.listWidth-10,c.h-54)
        local path=fs.combine(self.path,name); local dir=fs.isDir(path)
        right:text(0,0,"INFORMATION",P.accent); right:paragraph(0,18,name,P.textPrimary,right.w,3)
        right:text(0,61,dir and "DIRECTORY" or "FILE",P.textSecondary)
        if not dir then right:text(0,75,tostring(fs.getSize(path)).." bytes",P.textSecondary) end
        right:text(0,89,fs.isReadOnly(path) and "READ ONLY" or "WRITABLE",P.textSecondary)
    end
    c:text(5,c.h-13,#self.entries.." entries | ENTER open | F5 refresh",P.textSecondary)
end
register("files","Files","FI",398,254,Files)

-- Currency Calculator -------------------------------------------------------
-- This app deliberately has no Lightman's Currency API dependency.  Lightman's
-- server values can be changed by an administrator, so all coins and prices are
-- entered by the player and stored in a separate HCC OS data file.
local currencyPath="/.hccos/currency"
local currencyBackupPath="/.hccos/currency.bak"
local currencyCsvPath="/.hccos/currency.csv"
local CURRENCY_SCALE=1000000 -- fixed-point micro units, never Lua floats
local currencyWarning
local currencyData
local currencyDefaults={version=1,baseCoin="",allowDecimals=false,rounding="floor",
    coins={},items={},recent={}}
local function currencyCopy(t)
    local r={}; for k,v in pairs(t) do r[k]=v end; return r
end
local function currencyRead(path)
    local f,err=fs.open(path,"r"); if not f then error(err or "Cannot open currency data") end
    local ok,data=pcall(f.readAll); f.close(); if not ok then error(data) end
    local good,value=pcall(textutils.unserialize,data or "")
    if not good or type(value)~="table" then error("Currency data is invalid") end
    return value
end
local function currencyValidName(s)
    return type(s)=="string" and #s>=1 and #s<=48 and not s:find("[\r\n]")
end
local function currencyFixed(text,allowFraction)
    if type(text)=="number" then text=tostring(text) end
    if type(text)~="string" then return nil end
    text=text:gsub(",",""):gsub("%s+","")
    if text=="" or text:sub(1,1)=="-" or text:sub(1,1)=="+" then return nil end
    if not text:match("^%d*%.?%d*$") or text=="." then return nil end
    local whole,frac=text:match("^(%d*)%.?(%d*)$")
    whole=whole=="" and "0" or whole
    if #whole>12 then return nil end
    frac=frac or ""
    if not allowFraction and frac:gsub("0","")~="" then return nil end
    if #frac>6 then return nil end
    frac=(frac.."000000"):sub(1,6)
    local n=tonumber(whole)*CURRENCY_SCALE+tonumber(frac)
    if not finite(n) or n<0 or n>9000000000000000 then return nil end
    return floor(n)
end
local function currencyInteger(text)
    if type(text)=="number" then text=tostring(text) end
    if type(text)~="string" then return nil end
    text=text:gsub(",",""):gsub("%s+","")
    if not text:match("^%d+$") or #text>12 then return nil end
    local n=tonumber(text); if not finite(n) or n<0 or n>900000000000 then return nil end
    return floor(n)
end
local function currencyFormat(value,allowDecimals)
    if type(value)~="number" or value~=value then return "-" end
    local negative=value<0
    value=floor(math.abs(value)+0.5)
    local whole=floor(value/CURRENCY_SCALE); local rem=value% CURRENCY_SCALE
    local mode=currencyData and currencyData.rounding or "floor"
    if not allowDecimals and mode~="exact" then
        if mode=="ceil" and rem>0 then whole=whole+1 end
        if mode=="round" and rem>=CURRENCY_SCALE/2 then whole=whole+1 end
        local result=tostring(whole):reverse():gsub("(%d%d%d)","%1,"):gsub(",*$",""):reverse()
        return (negative and "-" or "")..result
    end
    local digits=string.format("%06d",rem):gsub("0+$","")
    local result=tostring(whole)
    if digits~="" then result=result.."."..digits end
    local left,tail=result:match("^(%d+)(.*)$")
    left=left:reverse():gsub("(%d%d%d)","%1,"):gsub(",*$",""):reverse()
    return (negative and "-" or "")..left..tail
end
local function currencyRatio(n,d,mode)
    if not n or not d or d<=0 then return nil end
    if mode=="ceil" then return floor((n+d-1)/d) end
    if mode=="round" then return floor((n+d/2)/d) end
    if mode=="exact" then return n/d end
    return floor(n/d)
end
local function currencySanitize(raw)
    local data=currencyCopy(currencyDefaults)
    data.coins={}; data.items={}; data.recent={}
    if type(raw)~="table" then return data end
    data.baseCoin=currencyValidName(raw.baseCoin) and raw.baseCoin or ""
    data.allowDecimals=raw.allowDecimals==true
    data.rounding=({floor=true,round=true,ceil=true,exact=true})[raw.rounding] and raw.rounding or "floor"
    if type(raw.coins)=="table" then
        for _,coin in ipairs(raw.coins) do
            if type(coin)=="table" and currencyValidName(coin.name) then
                local unit=tostring(coin.unit or coin.value or "")
                if currencyFixed(unit,data.allowDecimals) and currencyFixed(unit,data.allowDecimals)>0 then
                    data.coins[#data.coins+1]={name=ascii(coin.name),unit=unit}
                end
            end
        end
    end
    if type(raw.items)=="table" then
        for _,item in ipairs(raw.items) do
            if type(item)=="table" and currencyValidName(item.id) then
                local stack=currencyInteger(tostring(item.stack or 64)) or 64
                local buy=tostring(item.buy or ""); local sell=tostring(item.sell or "")
                if (buy=="" or currencyFixed(buy,data.allowDecimals)) and
                    (sell=="" or currencyFixed(sell,data.allowDecimals)) and stack>=1 and stack<=999999 then
                    data.items[#data.items+1]={id=ascii(item.id),name=ascii(item.name or item.id),buy=buy,sell=sell,
                        stack=stack,favorite=item.favorite==true}
                end
            end
        end
    end
    if type(raw.recent)=="table" then
        for _,id in ipairs(raw.recent) do if currencyValidName(id) then data.recent[#data.recent+1]=id end end
    end
    return data
end
local function currencyLoad()
    local data
    if fs.exists(currencyPath) then
        local ok,value=pcall(currencyRead,currencyPath); if ok then data=value end
    end
    if not data and fs.exists(currencyBackupPath) then
        local ok,value=pcall(currencyRead,currencyBackupPath); if ok then data=value; currencyWarning="Currency data restored from backup" end
    end
    if not data then
        data=currencyCopy(currencyDefaults)
        if fs.exists(currencyPath) then currencyWarning="Currency data invalid; using empty dictionary" end
    end
    return currencySanitize(data)
end
currencyData=currencyLoad()
local function currencySave()
    local ok,err=pcall(function()
        if not fs.exists("/.hccos") then fs.makeDir("/.hccos") end
        if fs.exists(currencyPath) then
            local oldOk,old=pcall(currencyRead,currencyPath)
            if oldOk then
                local f,e=fs.open(currencyBackupPath,"w")
                if not f then error(e or "Cannot write currency backup") end
                local good,reason=pcall(f.write,textutils.serialize(old)); f.close(); if not good then error(reason) end
            end
        end
        local f,e=fs.open(currencyPath,"w"); if not f then error(e or "Cannot save currency data") end
        local good,reason=pcall(f.write,textutils.serialize(currencyData)); f.close(); if not good then error(reason) end
    end)
    return ok,err
end
local function currencyCoinValue(coin)
    return currencyFixed(coin and coin.unit,currencyData.allowDecimals)
end
local function currencyItemValue(item,side)
    return currencyFixed(item and item[side],currencyData.allowDecimals)
end
local function currencyCoinsByValue()
    local coins={}; for _,coin in ipairs(currencyData.coins) do
        if currencyCoinValue(coin) then coins[#coins+1]=coin end
    end
    table.sort(coins,function(a,b) return currencyCoinValue(a)>currencyCoinValue(b) end); return coins
end
local function currencyBreakdown(amount)
    local result={}; local remain=max(0,floor(amount or 0));
    for _,coin in ipairs(currencyCoinsByValue()) do
        local value=currencyCoinValue(coin); local count=floor(remain/value)
        if count>0 then result[#result+1]={name=coin.name,count=count,value=value}; remain=remain-count*value end
    end
    return result,remain
end
local function currencyBreakdownText(amount)
    local result,remain=currencyBreakdown(amount); local lines={}
    for _,part in ipairs(result) do lines[#lines+1]=part.name.." x"..part.count end
    if remain>0 then lines[#lines+1]="Remainder "..currencyFormat(remain,currencyData.allowDecimals) end
    return #lines>0 and table.concat(lines," / ") or "No coins registered"
end
local function currencyItemById(id)
    for _,item in ipairs(currencyData.items) do if item.id==id then return item end end
end
local function currencyFindCoin(name)
    for _,coin in ipairs(currencyData.coins) do if coin.name:lower()==tostring(name or ""):lower() then return coin end end
end
local function currencyCsvSplit(line)
    local parts={}; for field in (line..","):gmatch("(.-),") do parts[#parts+1]=field end; return parts
end
local Currency={}
function Currency:init()
    self.screen="calc"; self.selected=1; self.coinSelected=1; self.sortMode="recent"; self.search=""
    self.side="BUY"; self.inputMode="quantity"; self.input="1"; self.fields={quantity="1",money="0",total="0"}
    self.calcLeft=nil; self.calcOp=nil; self.calcResult=nil; self.convertResult=nil; self:refreshItems()
end
function Currency:interval() return 2 end
function Currency:refreshItems()
    local list={}; local query=self.search:lower()
    for i,item in ipairs(currencyData.items) do
        if query=="" or item.id:lower():find(query,1,true) or item.name:lower():find(query,1,true) then list[#list+1]=i end
    end
    local recent={}; for i,id in ipairs(currencyData.recent) do recent[id]=i end
    table.sort(list,function(a,b)
        local aa,bb=currencyData.items[a],currencyData.items[b]
        if self.sortMode=="favorite" and aa.favorite~=bb.favorite then return aa.favorite end
        if self.sortMode=="price" then return (currencyItemValue(aa,"buy") or math.huge)<(currencyItemValue(bb,"buy") or math.huge) end
        if self.sortMode=="recent" and (recent[aa.id] or 9999)~=(recent[bb.id] or 9999) then return (recent[aa.id] or 9999)<(recent[bb.id] or 9999) end
        return aa.name:lower()<bb.name:lower()
    end)
    self.visibleItems=list; self.selected=clamp(self.selected,1,max(1,#list))
end
function Currency:selectedItem() local i=self.visibleItems and self.visibleItems[self.selected]; return i and currencyData.items[i] end
function Currency:choose(index)
    if not self.visibleItems[index] then return end
    self.selected=index; local item=self:selectedItem(); if not item then return end
    local recent={item.id}; for _,id in ipairs(currencyData.recent) do if id~=item.id and #recent<12 then recent[#recent+1]=id end end
    currencyData.recent=recent; self.fields.quantity="1"; self.inputMode="quantity"; self.input="1"; self.convertResult=nil
    mark(self.win)
end
function Currency:selectItemId(id)
    id=ascii(id)
    self.screen="calc"; self.search=""; self:refreshItems()
    for i,dataIndex in ipairs(self.visibleItems) do
        if currencyData.items[dataIndex].id==id then self:choose(i); return true end
    end
    self.search=id; self:refreshItems(); mark(self.win); return false
end
function Currency:setInputMode(mode)
    self.fields[self.inputMode]=self.input; self.inputMode=mode; self.input=self.fields[mode] or "0"; mark(self.win)
end
function Currency:syncInput()
    self.fields[self.inputMode]=self.input
end
function Currency:keypad(token)
    if token=="C" then self.input="0"
    elseif token=="B" then self.input=#self.input>1 and self.input:sub(1,-2) or "0"
    elseif token=="." then if currencyData.allowDecimals and not self.input:find("%.",1,true) then self.input=self.input.."." end
    elseif token=="ENTER" then
        self:syncInput(); if self.calcResult then self.input=tostring(self.calcResult); self:syncInput(); self.calcResult=nil end
    elseif token=="+" or token=="-" or token=="*" or token=="/" or token=="%" then
        local n=tonumber(self.input:gsub(",","")); if not n then return end
        if self.calcLeft==nil then self.calcLeft=n else self:calculateOp(n) end; self.calcOp=token; self.input="0"
    elseif token=="=" then if self.calcLeft and self.calcOp then self:calculateOp(tonumber(self.input) or 0); self.input=tostring(self.calcResult or 0); self.calcLeft=nil; self.calcOp=nil end
    else
        if self.input=="0" then self.input="" end
        if #self.input<18 then self.input=self.input..token end
    end
    self:syncInput(); mark(self.win)
end
function Currency:calculateOp(right)
    local left=self.calcLeft; local op=self.calcOp; local result
    if op=="+" then result=left+right elseif op=="-" then result=left-right
    elseif op=="*" then result=left*right elseif op=="/" and right~=0 then result=left/right
    elseif op=="%" and right~=0 then result=left%right else return end
    if finite(result) then self.calcResult=result end
end
function Currency:stackInput()
    local item=self:selectedItem(); if not item then errorBox("Register or select an item first"); return end
    askFields("Stacks to items",{{"Stacks","1"},{"Remainder items","0"}},function(values)
        local stacks=currencyInteger(values[1]); local rem=currencyInteger(values[2])
        if not stacks or not rem or rem>=item.stack then errorBox("Use whole stacks and a remainder smaller than stack size"); return end
        self.fields.quantity=tostring(stacks*item.stack+rem); self:setInputMode("quantity"); self.input=self.fields.quantity; mark(self.win)
    end)
end
function Currency:convert()
    local coinNames={}; for _,coin in ipairs(currencyData.coins) do coinNames[#coinNames+1]=coin.name end
    if #coinNames<2 then errorBox("Register at least two coins first"); return end
    askFields("Coin conversion",{{"From coin",coinNames[1]},{"Amount", "1"},{"To coin",coinNames[2]}},function(values)
        local from,to=currencyFindCoin(values[1]),currencyFindCoin(values[3]); local count=currencyInteger(values[2])
        if not from or not to or not count then errorBox("Unknown coin or invalid amount"); return end
        local amount=count*currencyCoinValue(from); local result,remain=currencyBreakdown(amount)
        self.convertResult=values[2].." "..from.name.." = "..currencyBreakdownText(amount)
        if remain>0 then self.convertResult=self.convertResult.." / remainder "..currencyFormat(remain,currencyData.allowDecimals) end
        mark(self.win)
    end)
end
local function askCurrencyFields(title,fields,callback,index,values)
    index=index or 1; values=values or {}
    if not fields[index] then callback(values); return end
    local field=fields[index]
    dialog(title,field[1],{"OK","Cancel"},function(buttonValue,value)
        if buttonValue~="OK" then return end
        values[index]=value; askCurrencyFields(title,fields,index+1,values,callback)
    end,tostring(field[2] or ""))
end
askFields=askCurrencyFields
function Currency:addCoin(edit)
    local old=edit and currencyData.coins[self.coinSelected]
    local fields={{"Coin name",old and old.name or ""},{"Value in base units",old and old.unit or "1"}}
    askFields(edit and "Edit coin" or "Add coin",fields,function(values)
        if not currencyValidName(values[1]) or currencyFindCoin(values[1]) and (not old or old.name~=values[1]) then errorBox("Coin name is empty or already used"); return end
        local value=currencyFixed(values[2],currencyData.allowDecimals)
        if not value or value<=0 then errorBox("Value must be a positive number"); return end
        if old then old.name=ascii(values[1]); old.unit=values[2] else currencyData.coins[#currencyData.coins+1]={name=ascii(values[1]),unit=values[2]} end
        if currencyData.baseCoin=="" then currencyData.baseCoin=ascii(values[1]) end
        local ok,err=currencySave(); if not ok then errorBox(err) else notify("Coin saved",P.success) end
        mark(self.win)
    end)
end
function Currency:addItem(edit)
    local old=edit and self:selectedItem()
    local fields={{"Item ID",old and old.id or "minecraft:item"},{"Display name",old and old.name or "Item"},
        {"Buy price",old and old.buy or ""},{"Sell price",old and old.sell or ""},{"Stack size",old and tostring(old.stack) or "64"}}
    askFields(edit and "Edit item" or "Add item",fields,function(values)
        if not currencyValidName(values[1]) then errorBox("Item ID is empty or invalid"); return end
        local stack=currencyInteger(values[5]); local buy=values[3]; local sell=values[4]
        if (buy~="" and not currencyFixed(buy,currencyData.allowDecimals)) or (sell~="" and not currencyFixed(sell,currencyData.allowDecimals)) then errorBox("Price is invalid"); return end
        if not stack or stack<1 or stack>999999 then errorBox("Stack size must be 1..999999"); return end
        for _,item in ipairs(currencyData.items) do if item~=old and item.id==values[1] then errorBox("Item ID already used"); return end end
        if old then old.id=ascii(values[1]); old.name=ascii(values[2]); old.buy=buy; old.sell=sell; old.stack=stack
        else currencyData.items[#currencyData.items+1]={id=ascii(values[1]),name=ascii(values[2]),buy=buy,sell=sell,stack=stack,favorite=false} end
        local ok,err=currencySave(); if not ok then errorBox(err) else notify("Item saved",P.success) end
        self:refreshItems(); mark(self.win)
    end)
end
function Currency:deleteItem()
    local item=self:selectedItem(); if not item then return end
    dialog("Delete item","Delete "..item.id.." from price dictionary?",{"Yes","No"},function(value)
        if value~="Yes" then return end
        for i,v in ipairs(currencyData.items) do if v==item then table.remove(currencyData.items,i); break end end
        currencySave(); self:refreshItems(); notify("Item deleted",P.warning); mark(self.win)
    end)
end
function Currency:toggleFavorite()
    local item=self:selectedItem(); if item then item.favorite=not item.favorite; currencySave(); self:refreshItems(); mark(self.win) end
end
function Currency:searchDialog()
    dialog("Search items","ID or display name; empty shows all",{"OK","Clear"},function(value,text)
        self.search=value=="Clear" and "" or text; self:refreshItems(); mark(self.win)
    end,self.search)
end
function Currency:sort()
    self.sortMode=({recent="name",name="price",price="favorite",favorite="recent"})[self.sortMode] or "recent"; self:refreshItems(); mark(self.win)
end
function Currency:editSettings()
    askFields("Currency settings",{{"Base coin",currencyData.baseCoin},{"Decimals on? yes/no",currencyData.allowDecimals and "yes" or "no"},{"Rounding floor/round/ceil/exact",currencyData.rounding}},function(values)
        local decimals=values[2]:lower(); local rounding=values[3]:lower()
        if decimals~="yes" and decimals~="no" then errorBox("Decimals must be yes or no"); return end
        if not ({floor=true,round=true,ceil=true,exact=true})[rounding] then errorBox("Rounding must be floor, round, ceil or exact"); return end
        if values[1]~="" and not currencyFindCoin(values[1]) then errorBox("Base coin does not exist"); return end
        currencyData.baseCoin=values[1]; currencyData.allowDecimals=decimals=="yes"; currencyData.rounding=rounding
        local ok,err=currencySave(); if not ok then errorBox(err) else notify("Currency settings saved",P.success) end
        mark(self.win)
    end)
end
function Currency:csvExport()
    local ok,err=pcall(function()
        local f,e=fs.open(currencyCsvPath,"w"); if not f then error(e or "Cannot open CSV") end
        f.write("item_id,name,buy,sell,stack\n")
        for _,item in ipairs(currencyData.items) do f.write(table.concat({item.id,item.name,item.buy,item.sell,tostring(item.stack)},",").."\n") end
        f.close()
    end)
    if ok then notify("CSV exported: "..currencyCsvPath,P.success) else errorBox(err) end
end
function Currency:csvImport()
    if not fs.exists(currencyCsvPath) then errorBox("No CSV at "..currencyCsvPath); return end
    local ok,err=pcall(function()
        local f,e=fs.open(currencyCsvPath,"r"); if not f then error(e or "Cannot read CSV") end
        local content=f.readAll(); f.close(); local first=true
        for line in (content.."\n"):gmatch("([^\r\n]+)") do
            if first then first=false else
                local p=currencyCsvSplit(line); local stack=currencyInteger(p[5] or "64")
                if #p>=5 and currencyValidName(p[1]) and stack and (p[3]=="" or currencyFixed(p[3],currencyData.allowDecimals)) and (p[4]=="" or currencyFixed(p[4],currencyData.allowDecimals)) then
                    local item=currencyItemById(p[1]); if item then item.name=ascii(p[2]); item.buy=p[3]; item.sell=p[4]; item.stack=stack
                    else currencyData.items[#currencyData.items+1]={id=ascii(p[1]),name=ascii(p[2]),buy=p[3],sell=p[4],stack=stack,favorite=false} end
                end
            end
        end
        local saved,e=currencySave(); if not saved then error(e) end
    end)
    if ok then self:refreshItems(); notify("CSV imported: "..currencyCsvPath,P.success); mark(self.win) else errorBox(err) end
end
function Currency:calcValues()
    local item=self:selectedItem(); local unit=item and currencyItemValue(item,self.side=="BUY" and "buy" or "sell")
    local qty=currencyInteger(self.fields.quantity or "0") or 0; local money=currencyFixed(self.fields.money or "0",currencyData.allowDecimals) or 0
    local total=unit and unit*qty or 0
    if self.inputMode=="total" then total=currencyFixed(self.fields.total or "0",currencyData.allowDecimals) or 0 end
    local shownUnit=unit
    if self.inputMode=="total" and qty>0 then shownUnit=total/qty end
    local stack=item and item.stack or 64
    local maxItems=unit and unit>0 and floor(money/unit) or 0
    local buy=currencyItemValue(item,"buy"); local sell=currencyItemValue(item,"sell")
    local purchase=buy and buy*qty or nil; local revenue=sell and sell*qty or nil; local profit=purchase and revenue and revenue-purchase or nil
    return {item=item,unit=shownUnit,priceUnit=unit,qty=qty,total=total,stack=stack,stacks=floor(qty/stack),remainder=qty%stack,maxItems=maxItems,maxStacks=floor(maxItems/stack),remaining=money-maxItems*(unit or 0),purchase=purchase,revenue=revenue,profit=profit,profitItem=buy and sell and sell-buy or nil,profitStack=buy and sell and (sell-buy)*stack or nil,margin=purchase and purchase>0 and profit*100/purchase or nil}
end
function Currency:onKey(k)
    if self.screen=="coins" then
        if k==keys.up then self.coinSelected=max(1,self.coinSelected-1) elseif k==keys.down then self.coinSelected=min(#currencyData.coins,self.coinSelected+1)
        elseif k==keys.enter then self:addCoin(true) elseif k==keys.delete then self:deleteCoin() elseif k==keys.escape then self.screen="calc" end
    elseif k==keys.up then self.selected=max(1,self.selected-1); self:choose(self.selected)
    elseif k==keys.down then self.selected=min(#self.visibleItems,self.selected+1); self:choose(self.selected)
    elseif k==keys.pageUp then self.selected=max(1,self.selected-6); self:choose(self.selected)
    elseif k==keys.pageDown then self.selected=min(#self.visibleItems,self.selected+6); self:choose(self.selected)
    elseif k==keys.enter and self.inputMode=="quantity" then self:keypad("ENTER")
    elseif k==keys.escape then self.screen="calc"; mark(self.win)
    elseif k==keys.b then self.side=self.side=="BUY" and "SELL" or "BUY"; mark(self.win)
    elseif k==keys.s then self:stackInput()
    end
    mark(self.win)
end
function Currency:deleteCoin()
    local coin=currencyData.coins[self.coinSelected]; if not coin then return end
    dialog("Delete coin","Delete "..coin.name.."?",{"Yes","No"},function(value)
        if value=="Yes" then table.remove(currencyData.coins,self.coinSelected); if currencyData.baseCoin==coin.name then currencyData.baseCoin="" end; currencySave(); self.coinSelected=clamp(self.coinSelected,1,max(1,#currencyData.coins)); notify("Coin deleted",P.warning); mark(self.win) end
    end)
end
function Currency:onMouse(kind,x,y,b)
    if self.screen=="coins" then
        if kind=="scroll" then self.coinSelected=clamp(self.coinSelected+b,1,max(1,#currencyData.coins)); mark(self.win)
        elseif kind=="click" and y>=37 and y<self.win.h-42 then local i=1+floor((y-37)/16); if currencyData.coins[i] then self.coinSelected=i; mark(self.win) end end
        return
    end
    if kind=="scroll" then self.selected=clamp(self.selected+b*3,1,max(1,#self.visibleItems)); self:choose(self.selected); return end
    if kind~="click" then return end
    if y>=34 and y<self.win.h-80 and x<165 then local i=1+floor((y-34)/17); if self.visibleItems[i] then self:choose(i) end; return end
    for _,item in ipairs(self.win.buttons) do if inside(item,x,y) then local ok,err=pcall(item.action); if not ok then errorBox(err) end; return end end
end
local function currencyButton(app,c,x,y,w,label,fn) button(app,c,x,y,w,label,fn) end
function Currency:drawCoins(c)
    c:text(6,6,"COIN TYPES / BASE: "..(currencyData.baseCoin=="" and "NOT SET" or currencyData.baseCoin),P.accent)
    c:text(6,21,"Value is stored in user-defined base units",P.textSecondary)
    for i,coin in ipairs(currencyData.coins) do
        local y=37+(i-1)*16; if i==self.coinSelected then c:filledRectangle(5,y,c.w-10,15,P.panelBackground) end
        c:text(9,y+3,coin.name,P.textPrimary); c:text(c.w-115,y+3,currencyFormat(currencyCoinValue(coin),currencyData.allowDecimals),P.accent)
    end
    currencyButton(self,c,6,c.h-38,55,"ADD",function() self:addCoin(false) end)
    currencyButton(self,c,65,c.h-38,55,"EDIT",function() self:addCoin(true) end)
    currencyButton(self,c,124,c.h-38,55,"DEL",function() self:deleteCoin() end)
    currencyButton(self,c,183,c.h-38,65,"BASE",function() local coin=currencyData.coins[self.coinSelected]; if coin then currencyData.baseCoin=coin.name; currencySave(); mark(self.win) end end)
    currencyButton(self,c,252,c.h-38,60,"BACK",function() self.screen="calc"; mark(self.win) end)
end
function Currency:draw(c)
    if self.screen=="coins" then self:drawCoins(c); return end
    local left=164; local mid=188; local right=max(130,c.w-left-mid-10)
    c:filledRectangle(0,0,left,c.h,P.windowBackground); c:line(left,0,left,c.h,P.border); c:line(left+mid,0,left+mid,c.h,P.border)
    c:text(5,5,"ITEMS",P.accent); c:text(5,19,self.search=="" and "ALL" or ("SEARCH: "..self.search),P.textSecondary)
    local rows=max(1,floor((c.h-89)/17));
    if self.selected<1 then self.selected=1 end
    for row=0,rows-1 do local idx=self.selected-rows+1+row; if idx<1 then idx=row+1 end; local dataIndex=self.visibleItems[idx]; local item=dataIndex and currencyData.items[dataIndex]
        if item then local y=34+row*17; if idx==self.selected then c:filledRectangle(3,y,left-7,16,P.panelBackground) end
            local markText=item.favorite and "* " or "  "; local name=item.name:sub(1,20); c:text(7,y+3,markText..name,item.favorite and P.warning or P.textPrimary)
            c:text(7,y+11,item.id:sub(1,23),P.textSecondary)
        end
    end
    c:text(5,c.h-52,string.format("%d/%d  %s",#self.visibleItems>0 and self.selected or 0,#self.visibleItems,self.sortMode),P.textSecondary)
    currencyButton(self,c,4,c.h-35,36,"ADD",function() self:addItem(false) end)
    currencyButton(self,c,44,c.h-35,40,"EDIT",function() self:addItem(true) end)
    currencyButton(self,c,88,c.h-35,36,"DEL",function() self:deleteItem() end)
    currencyButton(self,c,128,c.h-35,34,"FAV",function() self:toggleFavorite() end)
    currencyButton(self,c,4,c.h-17,50,"SEARCH",function() self:searchDialog() end)
    currencyButton(self,c,58,c.h-17,41,"SORT",function() self:sort() end)
    currencyButton(self,c,103,c.h-17,53,"COINS",function() self.screen="coins"; mark(self.win) end)
    c:text(left+7,5,"CALCULATOR",P.accent)
    c:text(left+7,20,"B: "..self.side.."  input: "..self.inputMode,P.textSecondary)
    local display=self.input or "0"; c:filledRectangle(left+7,34,mid-14,21,P.panelBackground); c:rectangle(left+7,34,mid-14,21,P.accent)
    local visible=display; while Driver.measure(visible)>mid-24 and #visible>1 do visible=visible:sub(2) end
    c:text(left+13,40,visible,P.textPrimary)
    local keypad={{"7","8","9","/"},{"4","5","6","*"},{"1","2","3","-"},{"0","00","000","+"},{".","B","C","="}}
    for r,row in ipairs(keypad) do for col,label in ipairs(row) do
        local x=left+7+(col-1)*43; local y=61+(r-1)*20
        currencyButton(self,c,x,y,39,label,function() self:keypad(label) end)
    end end
    currencyButton(self,c,left+7,166,54,"QTY",function() self:setInputMode("quantity") end)
    currencyButton(self,c,left+65,166,54,"MONEY",function() self:setInputMode("money") end)
    currencyButton(self,c,left+123,166,54,"TOTAL",function() self:setInputMode("total") end)
    currencyButton(self,c,left+7,185,82,"STACKS",function() self:stackInput() end)
    currencyButton(self,c,left+93,185,84,"CONVERT",function() self:convert() end)
    currencyButton(self,c,left+7,204,54,"SET",function() self:editSettings() end)
    currencyButton(self,c,left+65,204,54,"CSV OUT",function() self:csvExport() end)
    currencyButton(self,c,left+123,204,54,"CSV IN",function() self:csvImport() end)
    local v=self:calcValues(); local rx=left+mid+7
    c:text(rx,5,"RESULT",P.accent); c:text(rx,19,v.item and v.item.name:sub(1,24) or "No item selected",P.textPrimary)
    local unit=v.unit and currencyFormat(v.unit,currencyData.allowDecimals) or "-"
    local total=currencyFormat(v.total,currencyData.allowDecimals)
    local buyText=v.item and (currencyItemValue(v.item,"buy") and currencyFormat(currencyItemValue(v.item,"buy"),currencyData.allowDecimals) or "-") or "-"
    local sellText=v.item and (currencyItemValue(v.item,"sell") and currencyFormat(currencyItemValue(v.item,"sell"),currencyData.allowDecimals) or "-") or "-"
    c:text(rx,34,"Buy: "..buyText.."  Sell: "..sellText,P.textSecondary); c:text(rx,46,"Unit Price: "..unit,P.textSecondary)
    c:text(rx,58,"Quantity: "..tostring(v.qty),P.textSecondary); c:text(rx,70,"Total Price: "..total,P.accent)
    c:text(rx,82,"Stacks: "..v.stacks.."  Remainder: "..v.remainder,P.textSecondary); c:text(rx,94,"Price/Stack: "..(v.priceUnit and currencyFormat(v.priceUnit*v.stack,currencyData.allowDecimals) or "-"),P.textSecondary)
    c:text(rx,108,"MONEY / BUY",P.accent); c:text(rx,120,"Available: "..currencyFormat(currencyFixed(self.fields.money or "0",currencyData.allowDecimals) or 0,currencyData.allowDecimals),P.textSecondary)
    c:text(rx,132,"Max Items: "..v.maxItems,P.textSecondary); c:text(rx,144,"Max Stacks: "..v.maxStacks,P.textSecondary); c:text(rx,156,"Remaining: "..currencyFormat(v.remaining,currencyData.allowDecimals),P.textSecondary)
    c:text(rx,174,"PROFIT",P.accent); local pc=v.profit and (v.profit>=0 and P.success or P.error) or P.textSecondary
    c:text(rx,186,"Purchase Cost: "..(v.purchase and currencyFormat(v.purchase,currencyData.allowDecimals) or "-"),P.textSecondary); c:text(rx,198,"Sale Revenue: "..(v.revenue and currencyFormat(v.revenue,currencyData.allowDecimals) or "-"),P.textSecondary)
    c:text(rx,210,"Profit: "..(v.profit and currencyFormat(v.profit,currencyData.allowDecimals) or "-"),pc); c:text(rx,222,"Profit/Item: "..(v.profitItem and currencyFormat(v.profitItem,currencyData.allowDecimals) or "-"),pc)
    c:text(rx,234,"Profit/Stack: "..(v.profitStack and currencyFormat(v.profitStack,currencyData.allowDecimals) or "-"),pc); c:text(rx,246,"Margin: "..(v.margin and string.format("%.2f%%",v.margin) or "-"),pc)
    c:paragraph(rx,258,self.convertResult or (currencyData.baseCoin=="" and "Set a base coin in COINS or SET" or "Greedy coins: "..currencyBreakdownText(v.total)),P.textSecondary,right,2)
end
register("currency","Currency Calculator","CU",558,292,Currency)

local rescan

-- HCC Image ---------------------------------------------------------------
-- HCC OS owns this compact image format so it does not invent a PNG/JPEG
-- decoder.  A file is a serialized table with width, height and flat pixels:
-- {version=1,width=...,height=...,pixels={0xAARRGGBB,...}}.  RLE input is
-- also accepted as {rle={{color=...,count=...},...}} and is expanded safely.
local imageDir="/.hccos/images"
local imageCache={}
local imageToStored
local function imageColor(value)
    if type(value)=="number" and finite(value) then return floor(value)%4294967296 end
    if type(value)=="string" then
        local h=value:gsub("^#",""); if #h==6 then h="FF"..h end
        if #h==8 and h:match("^%x+$") then return tonumber(h,16) end
    end
end
local function imageNormalize(raw)
    if type(raw)~="table" then return nil,"not a table" end
    local w=tonumber(raw.width or raw.w); local h=tonumber(raw.height or raw.h)
    if not w or not h or not finite(w) or not finite(h) or w<1 or h<1 or w>1024 or h>768 or w*h>262144 then return nil,"image dimensions are unsafe" end
    w,h=floor(w),floor(h); local pixels={}; local source=raw.pixels; local palette={}
    if type(raw.palette)=="table" then for i=1,min(16,#raw.palette) do palette[i]=imageColor(raw.palette[i]) or 0xFF000000 end end
    if type(source)=="table" then
        local nested=type(source[1])=="table"
        for y=1,h do for x=1,w do
            local value=nested and source[y] and source[y][x] or source[(y-1)*w+x]
            pixels[(y-1)*w+x]=imageColor(value) or 0xFF000000
        end end
    elseif type(raw.rle)=="table" then
        for _,part in ipairs(raw.rle) do
            if type(part)=="table" then
                local rawIndex=part.index; local color
                if rawIndex==nil and type(part[1])=="number" and #palette>0 then rawIndex=part[1] end
                if rawIndex~=nil and #palette>0 then color=palette[floor(rawIndex)+1] end
                color=color or imageColor(part.color or part[1]) or 0xFF000000
                local count=floor(tonumber(part.count or part[2] or 0) or 0)
                for _=1,min(count,w*h-#pixels) do pixels[#pixels+1]=color end
            end
        end
        while #pixels<w*h do pixels[#pixels+1]=0xFF000000 end
    else return nil,"missing pixels or rle" end
    return {version=raw.version==2 and 2 or 1,width=w,height=h,pixels=pixels,palette=#palette>0 and palette or nil,rle=raw.version==2 and raw.rle or nil}
end
local function imageRead(path)
    if type(path)~="string" or path=="" or fs.isDir(path) then return nil,"invalid image path" end
    local ok,raw=pcall(function() return textutils.unserialize(readFile(path,4*1024*1024)) end)
    if not ok then return nil,tostring(raw) end
    return imageNormalize(raw)
end
local function imageWrite(path,data)
    if type(path)~="string" or path=="" or not data then return nil,"invalid image path" end
    local ok,err=pcall(function()
        local dir=fs.getDir(path); if dir~="" and not fs.exists(dir) then fs.makeDir(dir) end
        local f,e=fs.open(path,"w"); if not f then error(e or "image is not writable") end
        local stored=imageToStored and imageToStored(data) or data
        local good,reason=pcall(f.write,textutils.serialize(stored)); f.close(); if not good then error(reason) end
    end)
    return ok,err
end
local function imageList()
    if not fs.exists(imageDir) or not fs.isDir(imageDir) then return {} end
    local out={}; for _,name in ipairs(fs.list(imageDir)) do
        local path=fs.combine(imageDir,name); if not fs.isDir(path) and name:lower():match("%.hcci$") then out[#out+1]=path end
    end
    table.sort(out); return out
end
local function imagePixel(data,x,y)
    if not data or x<1 or y<1 or x>data.width or y>data.height then return 0xFF000000 end
    return data.pixels[(y-1)*data.width+x] or 0xFF000000
end
local function drawImage(c,data,x,y,w,h,mode,zoom,offsetX,offsetY)
    if not data or w<1 or h<1 then return end
    mode=mode or "fit"; zoom=clamp(tonumber(zoom) or 1,0.1,16); offsetX=offsetX or 0; offsetY=offsetY or 0
    local iw,ih=data.width,data.height; local sx,sy=zoom,zoom; local ox,oy=x+offsetX,y+offsetY
    if mode=="fit" or mode=="fill" then
        local fitScale=min(w/iw,h/ih); local fillScale=max(w/iw,h/ih); sx,sy=(mode=="fit" and fitScale or fillScale),(mode=="fit" and fitScale or fillScale)
        ox=x+(w-iw*sx)/2+offsetX; oy=y+(h-ih*sy)/2+offsetY
    elseif mode=="center" then ox=x+(w-iw*sx)/2+offsetX; oy=y+(h-ih*sy)/2+offsetY end
    if mode=="tile" then sx,sy=zoom,zoom; ox=x+offsetX; oy=y+offsetY end
    local runs=0; local maxRuns=60000
    for dy=0,h-1 do
        local py=oy+dy; local srcY=floor((py-oy)/sy)+1
        if mode=="tile" then srcY=((floor((py-oy)/sy))%ih)+1 end
        if srcY>=1 and srcY<=ih then
            local start=nil; local last=nil
            for dx=0,w-1 do
                local px=ox+dx; local srcX=floor((px-ox)/sx)+1
                if mode=="tile" then srcX=((floor((px-ox)/sx))%iw)+1 end
                local color=(srcX>=1 and srcX<=iw) and imagePixel(data,srcX,srcY) or nil
                if color and color==last then
                    -- keep extending this horizontal run
                else
                    if last and start then c:filledRectangle(start,py,px-start,1,last); runs=runs+1 end
                    if color then start=px end; last=color
                end
                if runs>maxRuns then return end
            end
            if last and start then c:filledRectangle(start,py,ox+w-start,1,last); runs=runs+1 end
        end
    end
end
local wallpaperCache={path=nil,renderKey=nil,data=nil,commands=nil}
local function getWallpaper()
    if cfg.wallpaperMode=="black" or cfg.wallpaperPath=="" then return nil end
    local key=cfg.wallpaperPath
    if wallpaperCache.path==key and wallpaperCache.data then return wallpaperCache.data end
    local data,err=imageRead(cfg.wallpaperPath)
    if not data then logLine("WARN","Wallpaper unavailable: "..tostring(err)); cfg.wallpaperMode="black"; wallpaperCache={path=nil,renderKey=nil,data=nil,commands=nil}; return nil end
    wallpaperCache.path=key; wallpaperCache.data=data; wallpaperCache.renderKey=nil; wallpaperCache.commands=nil; return data
end
local function wallpaperCommands()
    local data=getWallpaper(); if not data then return nil end
    local key=table.concat({cfg.wallpaperPath,cfg.wallpaperMode,Driver.w,Driver.h-TASK},"|")
    if cfg.wallpaperCache and wallpaperCache.commands and wallpaperCache.renderKey==key then return wallpaperCache.commands end
    local list={}; local c=canvas(list,0,0,Driver.w,Driver.h-TASK)
    drawImage(c,data,0,0,Driver.w,Driver.h-TASK,cfg.wallpaperMode,1,0,0)
    if cfg.wallpaperCache then wallpaperCache.renderKey=key; wallpaperCache.commands=list end
    return list
end

-- Pure Lua image decoders ---------------------------------------------------
-- CC:Tweaked does not expose a PNG/JPEG decoder.  The following decoder is
-- deliberately bounded and is driven by ImagePipeline coroutines below.
local pngDecode,jpegDecode,imagePrepare
local imageCacheSave,imageCacheLoad,imageCacheClear,imageCachePath
do
local bit32lib=bit32
local function bitFallback(a,b,mode)
    a=(tonumber(a) or 0)%4294967296; b=(tonumber(b) or 0)%4294967296; local out=0; local place=1
    for _=1,32 do local aa=a%2; local bb=b%2; local yes=(mode=="and" and aa==1 and bb==1) or (mode=="or" and (aa==1 or bb==1)) or (mode=="xor" and aa~=bb); if yes then out=out+place end; a=floor(a/2); b=floor(b/2); place=place*2 end
    return out
end
local function band(a,b) return bit32lib and bit32lib.band(a,b) or bitFallback(a,b,"and") end
local function bor(a,b) return bit32lib and bit32lib.bor(a,b) or bitFallback(a,b,"or") end
local function bxor(a,b) return bit32lib and bit32lib.bxor(a,b) or bitFallback(a,b,"xor") end
local function reverseBits(value,count)
    local out=0; for i=1,count do out=out*2+(value%2); value=floor(value/2) end; return out
end
local function huffmanBuild(lengths)
    local count={}; for i=1,15 do count[i]=0 end
    for _,len in ipairs(lengths) do if len>0 then count[len]=count[len]+1 end end
    local nextCode={}; local code=0
    for bits=1,15 do code=(code+(count[bits-1] or 0))*2; nextCode[bits]=code end
    local tree={}
    for symbol,len in ipairs(lengths) do if len>0 then tree[len]=tree[len] or {}; tree[len][reverseBits(nextCode[len],len)]=symbol-1; nextCode[len]=nextCode[len]+1 end end
    return tree
end
local function huffmanDecode(reader,tree)
    local code=0
    for len=1,15 do
        local bit,err=reader:readBits(1); if bit==nil then return nil,err end
        code=code+bit*2^(len-1)
        if tree[len] and tree[len][code]~=nil then return tree[len][code] end
    end
    return nil,"invalid Huffman code"
end
local function newBitReader(data)
    local reader={data=data,pos=1,bits=0,buffer=0}
    function reader:readBits(count)
        while self.bits<count do
            local byte=self.data:byte(self.pos); if not byte then return nil,"unexpected end of compressed data" end
            self.pos=self.pos+1; self.buffer=self.buffer+byte*2^self.bits; self.bits=self.bits+8
        end
        local value=self.buffer%(2^count); self.buffer=floor(self.buffer/(2^count)); self.bits=self.bits-count; return value
    end
    function reader:align() self.bits=0; self.buffer=0 end
    return reader
end
local fixedLit,fixedDist
do
    local lengths={}; for i=0,287 do lengths[i+1]=(i<=143 and 8) or (i<=255 and 9) or (i<=279 and 7) or 8 end
    local dists={}; for i=1,32 do dists[i]=5 end
    fixedLit,fixedDist=huffmanBuild(lengths),huffmanBuild(dists)
end
local lengthBase={3,4,5,6,7,8,9,10,11,13,15,17,19,23,27,31,35,43,51,59,67,83,99,115,131,163,195,227,258}
local lengthExtra={0,0,0,0,0,0,0,0,1,1,1,1,2,2,2,2,3,3,3,3,4,4,4,4,5,5,5,5,0}
local distanceBase={1,2,3,4,5,7,9,13,17,25,33,49,65,97,129,193,257,385,513,769,1025,1537,2049,3073,4097,6145,8193,12289,16385,24577}
local distanceExtra={0,0,0,0,1,1,2,2,3,3,4,4,5,5,6,6,7,7,8,8,9,9,10,10,11,11,12,12,13,13}
local function inflateRaw(data,limit,yieldFn)
    local reader=newBitReader(data); local output={}; local size=0; local final=false
    local function put(value)
        size=size+1; if size>limit then error("decoded image exceeds safety limit") end
        output[size]=string.char(value%256)
        if yieldFn and size%4096==0 then yieldFn(size) end
    end
    while not final do
        final=reader:readBits(1)==1; local kind=reader:readBits(2); if kind==nil then error("invalid DEFLATE header") end
        local litTree,distTree
        if kind==0 then
            reader:align(); local len=reader:readBits(16); local nlen=reader:readBits(16); if not len or not nlen or (len%65536+nlen%65536)~=65535 then error("invalid stored DEFLATE block") end
            for _=1,len do local value=reader:readBits(8); if value==nil then error("truncated stored block") end; put(value) end
        else
            if kind==1 then litTree,distTree=fixedLit,fixedDist
            elseif kind==2 then
                local hlit=reader:readBits(5)+257; local hdist=reader:readBits(5)+1; local hclen=reader:readBits(4)+4
                local order={16,17,18,0,8,7,9,6,10,5,11,4,12,3,13,2,14,1}; local cl={}; for i=1,19 do cl[i]=0 end
                for i=1,hclen do cl[order[i]+1]=reader:readBits(3) end
                local codeTree=huffmanBuild(cl); local all={}; local need=hlit+hdist
                while #all<need do
                    local symbol=huffmanDecode(reader,codeTree); if symbol==nil then error("invalid DEFLATE code lengths") end
                    if symbol<=15 then all[#all+1]=symbol
                    elseif symbol==16 then
                        local repeatCount=reader:readBits(2)+3; local previous=all[#all] or 0; for _=1,repeatCount do all[#all+1]=previous end
                    elseif symbol==17 then for _=1,reader:readBits(3)+3 do all[#all+1]=0 end
                    elseif symbol==18 then for _=1,reader:readBits(7)+11 do all[#all+1]=0 end end
                    if #all>need then error("DEFLATE code length overflow") end
                end
                local ll={}; for i=1,hlit do ll[i]=all[i] end; local dd={}; for i=1,hdist do dd[i]=all[hlit+i] end
                litTree,distTree=huffmanBuild(ll),huffmanBuild(dd)
            else error("reserved DEFLATE block") end
            while true do
                local symbol=huffmanDecode(reader,litTree); if symbol==nil then error("invalid DEFLATE literal") end
                if symbol<256 then put(symbol)
                elseif symbol==256 then break
                elseif symbol<=285 then
                    local index=symbol-256; local length=lengthBase[index]+reader:readBits(lengthExtra[index]); local ds=huffmanDecode(reader,distTree); if not ds or ds>29 then error("invalid DEFLATE distance") end
                    local distance=distanceBase[ds+1]+reader:readBits(distanceExtra[ds+1]); if distance>size then error("DEFLATE distance outside output") end
                    for _=1,length do local from=size-distance+1; put(tonumber(output[from]:byte())) end
                else error("invalid DEFLATE length") end
            end
        end
    end
    return table.concat(output)
end
local function be16(s,p) local a,b=s:byte(p,p+1); if not a or not b then error("truncated image") end; return a*256+b end
local function be32(s,p) local a,b,c,d=s:byte(p,p+3); if not d then error("truncated image") end; return ((a*256+b)*256+c)*256+d end
local function paeth(a,b,c) local p=a+b-c; local pa=math.abs(p-a); local pb=math.abs(p-b); local pc=math.abs(p-c); return pa<=pb and pa<=pc and a or (pb<=pc and b or c) end
function pngDecode(body,yieldFn)
    if body:sub(1,8)~=string.char(137,80,78,71,13,10,26,10) then error("not a PNG") end
    local pos=9; local width,height,depth,colorType; local palette,transparency={},{ }; local idat={}; local interlace
    while pos<=#body do
        local length=be32(body,pos); pos=pos+4; if length<0 or pos+length+7>#body then error("invalid PNG chunk length") end
        local kind=body:sub(pos,pos+3); pos=pos+4; local chunk=body:sub(pos,pos+length-1); pos=pos+length+4
        if kind=="IHDR" then width,height=be32(chunk,1),be32(chunk,5); depth=chunk:byte(9); colorType=chunk:byte(10); interlace=chunk:byte(13)
        elseif kind=="PLTE" then for i=1,#chunk,3 do palette[#palette+1]={chunk:byte(i) or 0,chunk:byte(i+1) or 0,chunk:byte(i+2) or 0} end
        elseif kind=="tRNS" then for i=1,#chunk do transparency[i]=chunk:byte(i) end
        elseif kind=="IDAT" then idat[#idat+1]=chunk
        elseif kind=="IEND" then break end
    end
    if not width or not height or width<1 or height<1 or width>1024 or height>768 or width*height>262144 then error("PNG dimensions are unsafe") end
    if interlace~=0 then error("interlaced PNG is not supported") end
    local channels=({[0]=1,[2]=3,[3]=1,[4]=2,[6]=4})[colorType]; if not channels then error("unsupported PNG color type") end
    if depth~=1 and depth~=2 and depth~=4 and depth~=8 and depth~=16 then error("unsupported PNG bit depth") end
    if colorType==3 and #palette==0 then error("indexed PNG has no palette") end
    local rowBytes=math.ceil(width*channels*depth/8); local bpp=max(1,math.ceil(channels*depth/8)); local compressed=table.concat(idat); if #compressed<6 or (compressed:byte(1)%16)~=8 then error("invalid PNG zlib stream") end
    local raw=inflateRaw(compressed:sub(3,#compressed-4),max(1024*1024,width*(rowBytes+1)*height+64),yieldFn)
    if #raw<height*(rowBytes+1) then error("PNG scanlines are truncated") end
    local previous={}; local pixels={}; local rp=1
    local function sample(row,bit)
        local byte=row[floor(bit/8)+1] or 0; local shift=8-depth-(bit%8); return floor(byte/2^shift)%2^depth
    end
    for y=1,height do
        local filter=raw:byte(rp); rp=rp+1; local row={}; for x=1,rowBytes do local value=raw:byte(rp) or 0; rp=rp+1; local left=row[x-bpp] or 0; local up=previous[x] or 0; local upper=previous[x-bpp] or 0
            if filter==1 then value=(value+left)%256 elseif filter==2 then value=(value+up)%256 elseif filter==3 then value=(value+floor((left+up)/2))%256 elseif filter==4 then value=(value+paeth(left,up,upper))%256 elseif filter~=0 then error("unsupported PNG filter") end; row[x]=value end
        for x=1,width do
            local r,g,b,a
            if colorType==0 then local v=depth==8 and row[x] or (depth==16 and row[(x-1)*2+1] or sample(row,(x-1)*depth)); v=depth<8 and floor(v*255/(2^depth-1)) or v; r,g,b=v,v,v; a=255
            elseif colorType==2 then local base=(x-1)*(depth==16 and 6 or 3)+1; r,g,b=row[base],row[base+(depth==16 and 2 or 1)],row[base+(depth==16 and 4 or 2)]; a=255
            elseif colorType==3 then local index=depth==8 and row[x] or sample(row,(x-1)*depth); local p=palette[index+1]; if not p then error("PNG palette index outside palette") end; r,g,b=p[1],p[2],p[3]; a=transparency[index+1] or 255
            elseif colorType==4 then local base=(x-1)*(depth==16 and 4 or 2)+1; r= row[base]; a=row[base+(depth==16 and 2 or 1)]; g,b=r,r
            elseif colorType==6 then local base=(x-1)*(depth==16 and 8 or 4)+1; r,g,b,a=row[base],row[base+(depth==16 and 2 or 1)],row[base+(depth==16 and 4 or 2)],row[base+(depth==16 and 6 or 3)] end
            pixels[(y-1)*width+x]=(a or 255)*16777216+(r or 0)*65536+(g or 0)*256+(b or 0)
        end
        previous=row; if yieldFn then yieldFn(y/height) end
    end
    return imageNormalize({width=width,height=height,pixels=pixels})
end
local jpegZigzag={0,1,5,6,14,15,27,28,2,4,7,13,16,26,29,42,3,8,12,17,25,30,41,43,9,11,18,24,31,40,44,53,10,19,23,32,39,45,52,54,20,22,33,38,46,51,55,60,21,34,37,47,50,56,59,61,35,36,48,49,57,58,62,63}
local function jpegHuffmanBuild(lengths,symbols)
    local count={}; for i=1,16 do count[i]=lengths[i] or 0 end; local code=0; local nextCode={}
    for bits=1,16 do code=(code+(count[bits-1] or 0))*2; nextCode[bits]=code end
    local tree={}; local at=1
    for bits=1,16 do for _=1,count[bits] do tree[bits]=tree[bits] or {}; tree[bits][nextCode[bits]]=symbols[at]; nextCode[bits]=nextCode[bits]+1; at=at+1 end end
    return tree
end
local function jpegReader(data,pos)
    local r={data=data,pos=pos,bits=0,buffer=0}
    function r:byte()
        local b=self.data:byte(self.pos); self.pos=self.pos+1; if not b then error("truncated JPEG entropy data") end
        if b==255 then local n=self.data:byte(self.pos); self.pos=self.pos+1; if n==0 then return 255 end; error("JPEG restart/marker inside entropy data") end
        return b
    end
    function r:bitsRead(count)
        local value=0; for _=1,count do if self.bits==0 then self.buffer=self:byte(); self.bits=8 end; value=value*2+floor(self.buffer/128); self.buffer=(self.buffer*2)%256; self.bits=self.bits-1 end; return value
    end
    return r
end
local function jpegHuffmanDecode(reader,tree)
    local code=0; for len=1,16 do code=code*2+reader:bitsRead(1); if tree[len] and tree[len][code]~=nil then return tree[len][code] end end; error("invalid JPEG Huffman code")
end
local function jpegReceive(reader,size)
    if size==0 then return 0 end; local value=reader:bitsRead(size); if value<2^(size-1) then return value-(2^size-1) end; return value
end
local JPEG={cos={}}
for u=0,7 do
    JPEG.cos[u]={}
    for x=0,7 do JPEG.cos[u][x]=math.cos((2*x+1)*u*math.pi/16) end
end
function JPEG.segmentEnd(state,length)
    local e=state.pos+length-1
    if length<2 or e>#state.body then error("truncated JPEG segment") end
    return e
end
function JPEG.idct(coeff)
    local out={}
    for y=0,7 do
        for x=0,7 do
            local sum=0
            for v=0,7 do
                for u=0,7 do
                    local cu=u==0 and 0.7071067811865476 or 1
                    local cv=v==0 and 0.7071067811865476 or 1
                    sum=sum+cu*cv*coeff[v*8+u+1]*JPEG.cos[u][x]*JPEG.cos[v][y]
                end
            end
            out[y*8+x+1]=clamp(floor(sum/4+128.5),0,255)
        end
    end
    return out
end
function JPEG.decodeBlock(state,reader,comp,pred)
    local coeff={}
    for i=1,64 do coeff[i]=0 end
    local dc=jpegHuffmanDecode(reader,state.huff.dc[comp.dc])
    pred[comp.id]=(pred[comp.id] or 0)+jpegReceive(reader,dc)
    coeff[1]=pred[comp.id]
    local k=1
    while k<64 do
        local rs=jpegHuffmanDecode(reader,state.huff.ac[comp.ac])
        if rs==0 then break end
        local run=floor(rs/16)
        local size=rs%16
        if size==0 and run~=15 then error("invalid JPEG AC symbol") end
        if size==0 then
            k=k+16
        else
            k=k+run
            if k>63 then error("JPEG coefficient overflow") end
            coeff[jpegZigzag[k+1]+1]=jpegReceive(reader,size)
            k=k+1
        end
    end
    local q=state.quant[comp.qt]
    if not q then error("missing JPEG quantization table") end
    for i=1,64 do coeff[i]=coeff[i]*(q[i] or 1) end
    return JPEG.idct(coeff)
end
function JPEG.parseDHT(state)
    local e=JPEG.segmentEnd(state,be16(state.body,state.pos))
    state.pos=state.pos+2
    while state.pos<=e do
        local info=state.body:byte(state.pos); state.pos=state.pos+1
        local cls=floor(info/16)
        local id=info%16
        local lengths={}
        for i=1,16 do lengths[i]=state.body:byte(state.pos); state.pos=state.pos+1 end
        local total=0
        for i=1,16 do total=total+lengths[i] end
        local symbols={}
        for i=1,total do symbols[i]=state.body:byte(state.pos); state.pos=state.pos+1 end
        if cls>1 then error("invalid JPEG Huffman class") end
        state.huff[cls==0 and "dc" or "ac"][id]=jpegHuffmanBuild(lengths,symbols)
    end
    state.pos=e+1
end
function JPEG.parseDQT(state)
    local e=JPEG.segmentEnd(state,be16(state.body,state.pos))
    state.pos=state.pos+2
    while state.pos<=e do
        local info=state.body:byte(state.pos); state.pos=state.pos+1
        local precision=floor(info/16)
        local id=info%16
        if precision>1 then error("16-bit JPEG quantization unsupported") end
        local q={}
        for i=1,64 do q[jpegZigzag[i]+1]=state.body:byte(state.pos); state.pos=state.pos+1 end
        state.quant[id]=q
    end
    state.pos=e+1
end
function JPEG.parseSOF0(state)
    local e=JPEG.segmentEnd(state,be16(state.body,state.pos))
    state.pos=state.pos+2
    local precision=state.body:byte(state.pos); state.pos=state.pos+1
    if precision~=8 then error("only 8-bit baseline JPEG is supported") end
    state.height=be16(state.body,state.pos)
    state.width=be16(state.body,state.pos+2)
    state.pos=state.pos+4
    local n=state.body:byte(state.pos); state.pos=state.pos+1
    if n<1 or n>3 then error("unsupported JPEG component count") end
    state.maxH,state.maxV=1,1
    for _=1,n do
        local id=state.body:byte(state.pos)
        local sampling=state.body:byte(state.pos+1)
        local qt=state.body:byte(state.pos+2)
        state.pos=state.pos+3
        local comp={id=id,hs=floor(sampling/16),vs=sampling%16,qt=qt}
        if comp.hs<1 or comp.vs<1 or comp.hs>4 or comp.vs>4 then error("unsupported JPEG sampling") end
        state.comps[id]=comp
        state.maxH=max(state.maxH,comp.hs)
        state.maxV=max(state.maxV,comp.vs)
    end
    state.pos=e+1
end
function JPEG.parseSOS(state)
    local e=JPEG.segmentEnd(state,be16(state.body,state.pos))
    state.pos=state.pos+2
    local n=state.body:byte(state.pos); state.pos=state.pos+1
    state.scan={}
    for _=1,n do
        local id=state.body:byte(state.pos)
        local tables=state.body:byte(state.pos+1)
        state.pos=state.pos+2
        local comp=state.comps[id]
        if not comp then error("JPEG scan references unknown component") end
        comp.dc=floor(tables/16)
        comp.ac=tables%16
        state.scan[#state.scan+1]=comp
    end
    local spectralStart=state.body:byte(state.pos)
    local spectralEnd=state.body:byte(state.pos+1)
    local approx=state.body:byte(state.pos+2)
    if spectralStart~=0 or spectralEnd~=63 or approx~=0 then error("non-baseline JPEG scan") end
    state.pos=e+1
end
function JPEG.sample(state,blocks,comp,px,py)
    local cx=floor(px*comp.hs/state.maxH)
    local cy=floor(py*comp.vs/state.maxV)
    local bi=floor(cx/8)+floor(cy/8)*comp.hs+1
    local block=blocks[comp.id][bi]
    return block[(cy%8)*8+(cx%8)+1] or 0
end
function JPEG.decodePixel(state,blocks,px,py)
    local yv=JPEG.sample(state,blocks,state.scan[1],px,py)
    if #state.scan==1 then return yv,yv,yv end
    if #state.scan~=3 then error("unsupported JPEG scan component count") end
    local cb=JPEG.sample(state,blocks,state.scan[2],px,py)-128
    local cr=JPEG.sample(state,blocks,state.scan[3],px,py)-128
    local r=clamp(floor(yv+1.402*cr+0.5),0,255)
    local g=clamp(floor(yv-0.344136*cb-0.714136*cr+0.5),0,255)
    local b=clamp(floor(yv+1.772*cb+0.5),0,255)
    return r,g,b
end
function JPEG.decodeMCU(state,reader,preds,mx,my,pixels)
    local blocks={}
    for _,comp in ipairs(state.scan) do
        blocks[comp.id]={}
        for by=0,comp.vs-1 do
            for bx=0,comp.hs-1 do
                blocks[comp.id][by*comp.hs+bx+1]=JPEG.decodeBlock(state,reader,comp,preds)
            end
        end
    end
    local mcuW,mcuH=state.maxH*8,state.maxV*8
    for py=0,mcuH-1 do
        local iy=my*mcuH+py+1
        if iy<=state.height then
            for px=0,mcuW-1 do
                local ix=mx*mcuW+px+1
                if ix<=state.width then
                    local r,g,b=JPEG.decodePixel(state,blocks,px,py)
                    pixels[(iy-1)*state.width+ix]=0xFF000000+r*65536+g*256+b
                end
            end
        end
    end
end
function JPEG.decodeScan(state,yieldFn)
    if not state.width or not state.height or state.width<1 or state.height<1 or state.width>1024 or state.height>768 or state.width*state.height>262144 then error("JPEG dimensions are unsafe") end
    local reader=jpegReader(state.body,state.pos)
    local preds={}
    local pixels={}
    local mcuW,mcuH=state.maxH*8,state.maxV*8
    local mcusX=math.ceil(state.width/mcuW)
    local mcusY=math.ceil(state.height/mcuH)
    for my=0,mcusY-1 do
        for mx=0,mcusX-1 do
            JPEG.decodeMCU(state,reader,preds,mx,my,pixels)
            if yieldFn then yieldFn((my*mcusX+mx+1)/(mcusX*mcusY)) end
        end
    end
    return imageNormalize({width=state.width,height=state.height,pixels=pixels})
end
function jpegDecode(body,yieldFn)
    if body:byte(1)~=255 or body:byte(2)~=216 then error("not a JPEG") end
    local state={body=body,pos=3,quant={},huff={dc={},ac={}},comps={}}
    while state.pos<=#body do
        while body:byte(state.pos)==255 do state.pos=state.pos+1 end
        local marker=body:byte(state.pos)
        state.pos=state.pos+1
        if not marker then error("truncated JPEG marker") end
        if marker==217 then
            break
        elseif marker==216 or marker==1 or (marker>=208 and marker<=215) then
        elseif marker==196 then
            JPEG.parseDHT(state)
        elseif marker==219 then
            JPEG.parseDQT(state)
        elseif marker==192 then
            JPEG.parseSOF0(state)
        elseif marker==194 then
            error("progressive JPEG is not supported")
        elseif marker==218 then
            JPEG.parseSOS(state)
            return JPEG.decodeScan(state,yieldFn)
        elseif marker>=192 and marker<=254 then
            local length=be16(body,state.pos)
            if length<2 or state.pos+length-1>#body then error("truncated JPEG marker") end
            state.pos=state.pos+length
        end
    end
    error("JPEG has no baseline image scan")
end
local function imageResize(data,targetW,targetH,yieldFn)
    local scale=min(1,targetW/data.width,targetH/data.height); local w=max(1,floor(data.width*scale+0.5)); local h=max(1,floor(data.height*scale+0.5)); local pixels={}
    for y=1,h do
        local sy=clamp(floor((y-0.5)/scale+0.5),1,data.height)
        for x=1,w do local sx=clamp(floor((x-0.5)/scale+0.5),1,data.width); pixels[(y-1)*w+x]=imagePixel(data,sx,sy) end
        if yieldFn then yieldFn(y/h) end
    end
    return imageNormalize({version=1,width=w,height=h,pixels=pixels})
end
local function imageQuantize(data,maxColors,yieldFn)
    maxColors=clamp(floor(maxColors or 16),1,16); local buckets={}
    for i,color in ipairs(data.pixels) do
        local r=floor(color/65536)%256; local g=floor(color/256)%256; local b=color%256; local key=floor(r/8)*1024+floor(g/8)*32+floor(b/8); local q=buckets[key]
        if not q then q={count=0,r=0,g=0,b=0}; buckets[key]=q end; q.count=q.count+1; q.r=q.r+r; q.g=q.g+g; q.b=q.b+b
        if yieldFn and i%4096==0 then yieldFn(i/#data.pixels) end
    end
    local bins={}; for _,q in pairs(buckets) do bins[#bins+1]=q end; table.sort(bins,function(a,b) return a.count>b.count end)
    local palette={}; for i=1,min(maxColors,#bins) do local q=bins[i]; palette[i]=0xFF000000+floor(q.r/q.count+0.5)*65536+floor(q.g/q.count+0.5)*256+floor(q.b/q.count+0.5) end
    if #palette==0 then palette[1]=0xFF000000 end
    local rle={}; local last=nil; local count=0
    for i,color in ipairs(data.pixels) do
        local r=floor(color/65536)%256; local g=floor(color/256)%256; local b=color%256; local best,bestDistance=1,math.huge
        for p,pcolor in ipairs(palette) do local pr=floor(pcolor/65536)%256; local pg=floor(pcolor/256)%256; local pb=pcolor%256; local distance=(r-pr)^2+(g-pg)^2+(b-pb)^2; if distance<bestDistance then best,bestDistance=p,distance end end
        if best==last then count=count+1 else if last then rle[#rle+1]={index=last-1,count=count} end; last=best; count=1 end
        if yieldFn and i%2048==0 then yieldFn(i/#data.pixels) end
    end
    if last then rle[#rle+1]={index=last-1,count=count} end
    local stored={version=2,width=data.width,height=data.height,palette=palette,rle=rle}; local normalized=imageNormalize(stored); return normalized,stored
end
imageToStored=function(data)
    if data and data.version==2 and type(data.palette)=="table" and type(data.rle)=="table" then return {version=2,width=data.width,height=data.height,palette=data.palette,rle=data.rle} end
    local _,stored=imageQuantize(data or {width=1,height=1,pixels={0xFF000000}},16); return stored
end
local imageCacheDir="/.hccos/cache/images"
local function imageHash(value)
    local hash=2166136261; for i=1,#value do hash=(hash*16777619+value:byte(i))%4294967296 end; return string.format("%08x",hash)
end
function imageCachePath(key) return fs.combine(imageCacheDir,imageHash(key)..".hcci") end
function imageCacheLoad(key)
    if not cfg.imageCacheEnabled then return nil end
    local path=imageCachePath(key); if not fs.exists(path) then return nil end
    local data=imageRead(path); if data then return data end
    pcall(fs.delete,path); return nil
end
local function imageCacheTrim()
    if not fs.exists(imageCacheDir) then return end
    local entries={}; local total=0
    for _,name in ipairs(fs.list(imageCacheDir)) do local path=fs.combine(imageCacheDir,name); if not fs.isDir(path) then local size=fs.getSize(path); entries[#entries+1]={path=path,size=size}; total=total+size end end
    table.sort(entries,function(a,b) return a.path<b.path end)
    while total>cfg.imageCacheLimit and #entries>0 do local item=table.remove(entries,1); pcall(fs.delete,item.path); total=total-item.size end
end
function imageCacheSave(key,data)
    if not cfg.imageCacheEnabled then return nil,"image cache disabled" end
    local ok,err=pcall(function()
        if not fs.exists("/.hccos/cache") then fs.makeDir("/.hccos/cache") end
        if not fs.exists(imageCacheDir) then fs.makeDir(imageCacheDir) end
        local f,e=fs.open(imageCachePath(key),"w"); if not f then error(e or "cache is not writable") end; local good,reason=pcall(f.write,textutils.serialize(imageToStored(data))); f.close(); if not good then error(reason) end; imageCacheTrim()
    end)
    return ok,err
end
function imageCacheClear()
    if not fs.exists(imageCacheDir) then return true end
    local ok,err=pcall(function() for _,name in ipairs(fs.list(imageCacheDir)) do local path=fs.combine(imageCacheDir,name); if not fs.isDir(path) then fs.delete(path) end end end); return ok,err
end
function imagePrepare(data,targetW,targetH,progress)
    targetW=max(1,min(576,floor(targetW or 576))); targetH=max(1,min(320,floor(targetH or 320))); local candidates={{1,"16"},{0.8333,"12"},{0.6667,"8"},{0.5,"8"}}; local lastData,lastStored,lastSize
    for _,candidate in ipairs(candidates) do
        local scale,colors=candidate[1],tonumber(candidate[2]); local resized=imageResize(data,max(1,floor(targetW*scale)),max(1,floor(targetH*scale)),function(p) if progress then progress("Resizing...",p) end end)
        local quantized,stored=imageQuantize(resized,colors,function(p) if progress then progress("Quantizing "..colors.." colors...",p) end end); local size=#textutils.serialize(stored); lastData,lastStored,lastSize=quantized,stored,size
        if progress then progress("Compressing...",1) end
        if size<=512000 then return quantized,stored,size end
    end
    return lastData,lastStored,lastSize
end
end

local ImageViewer={}
function ImageViewer:init(path)
    self.mode="fit"; self.zoom=1; self.offsetX=0; self.offsetY=0; self.selected=1; self.path=nil; self.data=nil; self.error=nil
    self.images=imageList()
    if type(path)=="string" and path~="" then self:loadPath(path) elseif self.images[1] then self:loadPath(self.images[1]) end
end
function ImageViewer:loadPath(path)
    local data,err=imageRead(path); self.error=nil
    if not data then self.error=tostring(err); logLine("ERROR","Image load: "..self.error); mark(self.win); return false end
    self.path=path; self.data=data; self.offsetX=0; self.offsetY=0
    for i,v in ipairs(self.images or {}) do if v==path then self.selected=i end end
    mark(self.win); return true
end
function ImageViewer:refreshList() self.images=imageList(); self.selected=clamp(self.selected,1,max(1,#self.images)); if self.images[self.selected] then self:loadPath(self.images[self.selected]) end end
function ImageViewer:openDialog()
    dialog("Open HCC Image","Absolute .hcci path",{"Open","Cancel"},function(b,value)
        if b=="Open" then if not value:lower():match("%.hcci$") then value=value..".hcci" end; self:loadPath(value) end
    end,self.path or "/.hccos/images/image.hcci")
end
function ImageViewer:saveAs()
    if not self.data then return end
    dialog("Save HCC Image","Absolute .hcci path",{"Save","Cancel"},function(b,value)
        if b~="Save" then return end
        if not value:lower():match("%.hcci$") then value=value..".hcci" end
        local ok,err=imageWrite(value,self.data); if not ok then errorBox(err) else self.path=value; self:refreshList(); notify("Image saved",P.success) end
    end,self.path or "/.hccos/images/image.hcci")
end
function ImageViewer:importUrl()
    dialog("Import HCC Image","HTTP URL for a serialized HCC Image",{"GET","Cancel"},function(b,url)
        if b~="GET" then return end
        url=tostring(url or ""):gsub("%s+","")
        if not url:match("^https?://[^%s]+$") then errorBox("Only HTTP/HTTPS URLs are allowed"); return end
        if type(http)~="table" or type(http.get)~="function" then errorBox("CC:T HTTP API unavailable"); return end
        local ok,handle=pcall(http.get,url); if not ok or not handle then errorBox("HTTP image request failed"); return end
        local rok,body=pcall(handle.readAll); if handle.close then pcall(handle.close) end
        if not rok then errorBox("HTTP response could not be read"); return end
        local data,err
        if type(textutils.unserialize)=="function" then
            local uok,raw=pcall(textutils.unserialize,body or "")
            if uok then data,err=imageNormalize(raw) end
        end
        err=err or "Downloaded data is not HCC Image format"
        if not data then errorBox(err); return end
        self.data=data; self.path="/.hccos/images/imported_"..tostring(floor(now()))..".hcci"; local saved,se=imageWrite(self.path,data)
        if not saved then errorBox(se) else self:refreshList(); notify("HCC Image imported",P.success) end
    end,"https://example.com/image.hcci")
end
function ImageViewer:setWallpaper()
    if not self.data or not self.path then errorBox("Save the image before using it as wallpaper"); return end
    cfg.wallpaperPath=self.path; cfg.wallpaperMode=({fit=true,fill=true,center=true,tile=true})[self.mode] and self.mode or "fit"
    wallpaperCache={path=nil,renderKey=nil,data=nil,commands=nil}; local ok,err=saveConfig(); allDirty()
    if ok then notify("Wallpaper set: "..cfg.wallpaperMode,P.success) else errorBox(err) end
end
function ImageViewer:zoomBy(delta) self.mode="100"; self.zoom=clamp(self.zoom+delta,0.1,16); mark(self.win) end
function ImageViewer:onKey(k)
    if k==keys.left then self.offsetX=self.offsetX-8 elseif k==keys.right then self.offsetX=self.offsetX+8
    elseif k==keys.up then self.offsetY=self.offsetY-8 elseif k==keys.down then self.offsetY=self.offsetY+8
    elseif k==keys.f5 then self:refreshList()
    elseif k==keys.pageUp then self:zoomBy(0.25) elseif k==keys.pageDown then self:zoomBy(-0.25)
    elseif k==keys.enter and self.images[self.selected] then self:loadPath(self.images[self.selected]) end
    mark(self.win)
end
function ImageViewer:onMouse(kind,x,y,b)
    if kind=="scroll" then self:zoomBy(b>0 and 0.25 or -0.25)
    elseif kind=="click" and y>=34 and y<self.win.h-35 and x<155 then local i=1+floor((y-34)/17); if self.images[i] then self.selected=i; self:loadPath(self.images[i]) end end
    mark(self.win)
end
function ImageViewer:draw(c)
    c:text(6,5,"IMAGE VIEWER",P.accent); c:text(6,19,self.path or "No .hcci selected",P.textSecondary)
    button(self,c,5,33,42,"OPEN",function() self:openDialog() end); button(self,c,51,33,48,"SAVE",function() self:saveAs() end)
    button(self,c,103,33,41,"FIT",function() self.mode="fit"; self.zoom=1; self.offsetX=0; self.offsetY=0; mark(self.win) end)
    button(self,c,c.w-70,3,65,"IMPORT",function() self:importUrl() end)
    local left=155; c:line(left,31,left,c.h-28,P.border)
    local rows=max(1,floor((c.h-70)/17)); for i=1,min(rows,#self.images) do local y=34+(i-1)*17; if i==self.selected then c:filledRectangle(4,y,left-9,16,P.panelBackground) end; c:text(8,y+3,fs.getName(self.images[i]):sub(1,20),P.textPrimary) end
    local preview=c:clipping(left+5,33,c.w-left-10,c.h-62); Widget.panel(preview,0,0,preview.w,preview.h,0xFF050505,P.border)
    if self.data then drawImage(preview,self.data,2,2,preview.w-4,preview.h-4,self.mode,self.zoom,self.offsetX,self.offsetY)
    elseif self.error then preview:paragraph(8,18,"Image error: "..self.error,P.error,preview.w-16,4)
    else preview:text(8,18,"Open an HCC Image (.hcci)",P.textSecondary) end
    button(self,c,left+5,c.h-24,45,"FILL",function() self.mode="fill"; self.zoom=1; mark(self.win) end)
    button(self,c,left+54,c.h-24,48,"100%",function() self.mode="100"; self.zoom=1; self.offsetX=0; self.offsetY=0; mark(self.win) end)
    button(self,c,left+106,c.h-24,34,"+",function() self:zoomBy(0.25) end)
    button(self,c,left+144,c.h-24,34,"-",function() self:zoomBy(-0.25) end)
    button(self,c,left+182,c.h-24,60,"CENTER",function() self.offsetX=0; self.offsetY=0; mark(self.win) end)
    button(self,c,left+247,c.h-24,75,"WALLPAPER",function() self:setWallpaper() end)
    c:text(6,c.h-13,"F5 refresh  arrows pan  PgUp/PgDn zoom",P.textSecondary)
end
register("image","Image Viewer","IM",530,282,ImageViewer)

-- HCC Web -------------------------------------------------------------------
-- This is a safe text browser, not a JavaScript/CSS engine.  It delegates
-- HTTP/HTTPS transport to CC:Tweaked's permission-controlled http API.
local function webUnescape(s)
    return tostring(s or ""):gsub("&amp;","&"):gsub("&lt;","<"):gsub("&gt;",">"):gsub("&quot;",'"'):gsub("&#39;","'")
end
local function webParse(html,base)
    html=tostring(html or ""):gsub("<script.-</script>",""):gsub("<style.-</style>","")
    local title=webUnescape(html:match("<title[^>]*>(.-)</title>") or "")
    local links={}
    for href,label in html:gmatch("<a[^>]-href%s*=%s*[\"'](.-)[\"'][^>]*>(.-)</a>") do
        label=webUnescape(label:gsub("<[^>]->","")):gsub("%s+"," ")
        if href:sub(1,1)=="/" and base then local origin=base:match("^(https?://[^/]+)"); href=origin and origin..href or href end
        links[#links+1]={url=href,label=label~="" and label or href}
    end
    local text=html:gsub("<br%s*/?>","\n"):gsub("</p%s*>","\n"):gsub("</h[1-6]%s*>","\n"):gsub("<li[^>]*>","* "):gsub("<[^>]->","")
    text=webUnescape(text):gsub("\r"," "):gsub("[ \t]+"," "):gsub("\n%s+","\n")
    local lines={}; for line in (text.."\n"):gmatch("([^\n]*)\n") do if line:match("%S") then lines[#lines+1]=line:sub(1,512) end end
    if #lines==0 then lines={"(empty response)"} end
    return title,lines,links
end
local function webJsonLines(body)
    if type(textutils.unserializeJSON)~="function" then return end
    local trimmed=body:gsub("^%s+","")
    if trimmed:sub(1,1)~="{" and trimmed:sub(1,1)~="[" then return end
    local ok,value=pcall(textutils.unserializeJSON,body); if not ok or value==nil then return end
    local serialized=type(textutils.serializeJSON)=="function" and textutils.serializeJSON(value) or textutils.serialize(value)
    local lines={}; for line in (serialized.."\n"):gmatch("([^\n]*)\n") do lines[#lines+1]=line end
    return lines
end
local function webSafeUrl(url)
    url=tostring(url or ""):gsub("%s+","")
    if #url>512 or not url:match("^https?://[^%s]+$") then return nil end
    return url
end
local Web={}
function Web:init(url)
    self.url=""; self.status="Ready"; self.title="HCC Web"; self.lines={"Enter an HTTP/HTTPS URL and press GO."}; self.links={}; self.linkSelected=1; self.top=1; self.body=""; self.history={}; self.historyIndex=0
    if type(url)=="string" and url~="" then self:load(url,true) end
end
function Web:load(url,record)
    url=webSafeUrl(url); if not url then self.status="Invalid URL"; self.lines={"Only http:// and https:// URLs are allowed."}; mark(self.win); return false end
    if type(http)~="table" or type(http.get)~="function" then self.status="HTTP API unavailable"; self.lines={"CC:Tweaked HTTP API is unavailable or disabled."}; mark(self.win); return false end
    self.status="Loading..."; mark(self.win)
    local ok,handle=pcall(http.get,url,{["User-Agent"]="HCC-Web/1.3"})
    if not ok or not handle then self.status="HTTP request failed"; self.lines={"HTTP request failed: "..tostring(handle or "permission denied")}; logLine("WARN",self.status.." "..url); mark(self.win); return false end
    local readOk,body=pcall(handle.readAll); local code=200
    if type(handle.getResponseCode)=="function" then local cok,cvalue=pcall(handle.getResponseCode); if cok and finite(cvalue) then code=cvalue end end
    if handle.close then pcall(handle.close) end
    if not readOk then self.status="Read failed"; self.lines={"Response body could not be read."}; mark(self.win); return false end
    self.url=url; self.body=tostring(body or ""); self.title,self.lines,self.links=webParse(self.body,url); self.lines=webJsonLines(self.body) or self.lines
    self.status="HTTP "..tostring(code).."  "..#self.body.." bytes"; self.linkSelected=1; self.top=1
    if record~=false then for i=#self.history,self.historyIndex+1,-1 do table.remove(self.history,i) end; self.history[#self.history+1]=url; self.historyIndex=#self.history end
    mark(self.win); logLine("INFO","Web GET "..url.." -> "..tostring(code)); return true
end
function Web:goDialog()
    dialog("HCC Web URL","HTTP/HTTPS URL",{"GO","Cancel"},function(b,value) if b=="GO" then self:load(value,true) end end,self.url~="" and self.url or "https://example.com")
end
function Web:back() if self.historyIndex>1 then self.historyIndex=self.historyIndex-1; self:load(self.history[self.historyIndex],false) end end
function Web:forward() if self.historyIndex<#self.history then self.historyIndex=self.historyIndex+1; self:load(self.history[self.historyIndex],false) end end
function Web:reload() if self.url~="" then self:load(self.url,false) end end
function Web:download()
    if self.body=="" or self.url=="" then return end
    local filename=self.url:match("/([^/?#]+)[?#]?[^/]*$") or "download.txt"; filename=filename:gsub("[^%w%._-]","_"):sub(1,64)
    local path=fs.combine("/.hccos/downloads",filename)
    local save=function() local ok,err=pcall(function() if not fs.exists("/.hccos/downloads") then fs.makeDir("/.hccos/downloads") end; local f,e=fs.open(path,"w"); if not f then error(e) end; f.write(self.body); f.close() end); if ok then notify("Downloaded "..path,P.success) else errorBox(err) end end
    if fs.exists(path) then dialog("Overwrite download","Replace "..path.."?",{"Yes","No"},function(b) if b=="Yes" then save() end end) else save() end
end
function Web:onKey(k)
    if k==keys.left then self:back() elseif k==keys.right then self:forward() elseif k==keys.f5 then self:reload()
    elseif k==keys.up then self.top=max(1,self.top-3) elseif k==keys.down then self.top=min(max(1,#self.lines),self.top+3)
    elseif k==keys.enter and self.links[self.linkSelected] then self:load(self.links[self.linkSelected].url,true)
    elseif k==keys.pageUp then self.top=max(1,self.top-10) elseif k==keys.pageDown then self.top=min(max(1,#self.lines),self.top+10) end
    mark(self.win)
end
function Web:onMouse(kind,x,y,b)
    if kind=="scroll" then self.top=clamp(self.top-b*3,1,max(1,#self.lines))
    elseif kind=="click" and y>=58 and y<self.win.h-29 and x<self.win.w-10 then self.top=clamp(self.top+floor((y-58)/12)-1,1,max(1,#self.lines)) end
    mark(self.win)
end
function Web:draw(c)
    c:text(6,5,"HCC WEB",P.accent); c:text(6,19,self.title:sub(1,42),P.textPrimary)
    button(self,c,5,33,42,"BACK",function() self:back() end); button(self,c,51,33,48,"FORWARD",function() self:forward() end)
    button(self,c,103,33,48,"RELOAD",function() self:reload() end); button(self,c,156,33,39,"GO",function() self:goDialog() end)
    button(self,c,200,33,72,"DOWNLOAD",function() self:download() end)
    c:filledRectangle(277,34,c.w-284,15,P.panelBackground); c:rectangle(277,34,c.w-284,15,P.border); c:text(281,37,self.url=="" and "URL / SEARCH" or self.url,P.textPrimary)
    c:text(6,51,self.status,P.textSecondary); c:line(0,57,c.w-1,57,P.border)
    local rows=max(1,floor((c.h-85)/12)); self.top=clamp(self.top,1,max(1,#self.lines-rows+1))
    for i=0,rows-1 do local line=self.lines[self.top+i]; if not line then break end; c:text(7,62+i*12,line,P.textPrimary) end
    c:text(6,c.h-14,string.format("%d lines  %d links  PgUp/PgDn scroll",#self.lines,#self.links),P.textSecondary)
end
register("web","HCC Web","WB",548,286,Web)

-- HCC Web v1.3.1 image pipeline.  The old text-browser methods above remain
-- as a compatibility baseline; these methods replace transport/rendering with
-- event-driven HTTP and bounded coroutine work.
do
local function webResolveV131(src,base)
    src=tostring(src or ""):gsub("^%s+",""):gsub("%s+$","")
    if src:match("^https?://") then return src end
    if src:sub(1,2)=="//" then return (base and base:match("^(https?):") or "https")..":"..src end
    if not base or not base:match("^https?://") then return nil end
    local origin=base:match("^(https?://[^/]+)")
    if src:sub(1,1)=="/" then return origin..src end
    return (base:match("^(https?://.*/)") or base.."/")..src
end
local function webParseV131(html,base)
    html=tostring(html or ""):gsub("<script.-</script>",""):gsub("<style.-</style>","")
    local title=webUnescape(html:match("<title[^>]*>(.-)</title>") or ""); local links={}; local images={}
    for href,label in html:gmatch("<a[^>]-href%s*=%s*[\"'](.-)[\"'][^>]*>(.-)</a>") do
        local resolved=webResolveV131(href,base); label=webUnescape(label:gsub("<[^>]->",""):gsub("%s+"," "))
        if resolved and webSafeUrl(resolved) then links[#links+1]={url=resolved,label=label~="" and label or resolved} end
    end
    for attrs in html:gmatch("<img%s+([^>]-)>") do
        local src=attrs:match("src%s*=%s*[\"'](.-)[\"']") or attrs:match("src%s*=%s*([^%s>]+)"); local resolved=webResolveV131(src,base)
        if resolved and webSafeUrl(resolved) then images[#images+1]={url=resolved,status="pending"} end
    end
    local text=html:gsub("<br%s*/?>","\n"):gsub("</p%s*>","\n"):gsub("</h[1-6]%s*>","\n"):gsub("<li[^>]*>","* "):gsub("<[^>]->","")
    text=webUnescape(text):gsub("\r"," "):gsub("[ \t]+"," "):gsub("\n%s+","\n")
    local lines={}; for line in (text.."\n"):gmatch("([^\n]*)\n") do if line:match("%S") then lines[#lines+1]=line:sub(1,512) end end
    if #lines==0 then lines={"(empty response)"} end
    for i=1,#images do lines[#lines+1]="[ Image "..i..": Loading image... ]" end
    return title,lines,links,images
end
local function webImageStatusLine(lines,index,status)
    for i,line in ipairs(lines) do if line:match("^%[ Image "..tostring(index)..":") then lines[i]="[ Image "..tostring(index)..": "..status.." ]" end end
end
function Web:interval() return self.job and (self.job.stage=="wait" and 1 or 0.05) or 1 end
function Web:markV131() if self.win then mark(self.win) end end
function Web:cancelJobV131(message)
    if self.job and self.job.handle and self.job.handle.close then pcall(self.job.handle.close) end
    self.job=nil; if message then self.status=message; self:markV131() end
end
function Web:headersV131(handle)
    local out={}; if handle and type(handle.getResponseHeaders)=="function" then local ok,h=pcall(handle.getResponseHeaders); if ok and type(h)=="table" then for k,v in pairs(h) do out[tostring(k):lower()]=tostring(v) end end end; return out
end
function Web:imageKindV131(url,contentType)
    local c=tostring(contentType or ""):lower():match("^[^;]+") or ""; local u=tostring(url):lower()
    if c=="image/png" or u:match("%.png([?#]|$)") then return "png" end
    if c=="image/jpeg" or c=="image/jpg" or u:match("%.jpe?g([?#]|$)") then return "jpeg" end
    if c=="image/hcci" or u:match("%.hcci([?#]|$)") then return "hcci" end
end
function Web:cacheAliasV131(url,w,h) return table.concat({url,"image",tostring(w).."x"..tostring(h)},"|") end
function Web:cacheKeyV131(url,w,h,ctype,length) return table.concat({url,"image",tostring(w).."x"..tostring(h),tostring(ctype or ""),tostring(length or "")},"|") end
function Web:progressV131(stage,value)
    self.status=finite(value) and stage.." "..tostring(clamp(floor(value*100+0.5),0,100)).."%" or stage; self:markV131()
end
function Web:showImageV131(data,path,url,cacheHit)
    self.pageMode="image"; self.imageData=data; self.imagePath=path; self.title=fs.getName(url or self.url):sub(1,48); self.lines={"Direct image view",cacheHit and "Loaded from Image Cache" or "PNG/JPEG converted to HCCI v2"}; self.status=cacheHit and "Image Cache hit" or "Image ready"; self:markV131()
end
function Web:finishImageV131(item,data,cacheKey,alias)
    local saved,err=imageCacheSave(alias,data); if saved and cacheKey~=alias then imageCacheSave(cacheKey,data) end
    local path=saved and imageCachePath(alias) or nil; self.cacheNotice=saved and "" or "Cache unavailable: "..tostring(err)
    if item then item.data=data; item.path=path; item.status=saved and "ready" or "ready (uncached)"; webImageStatusLine(self.lines,item.index,item.status); self.job=nil; self:progressV131("Rendering...",1); self:queueNextImageV131()
    else self.job=nil; self:showImageV131(data,path,self.url,false) end
end
function Web:startConversionV131(body,url,ctype,length,targetW,targetH,item)
    local kind=self:imageKindV131(url,ctype); if not kind then return false,"unsupported image type" end
    local alias=self:cacheAliasV131(url,targetW,targetH); local exact=self:cacheKeyV131(url,targetW,targetH,ctype,length); local cached=imageCacheLoad(alias)
    if cached then if item then self:finishImageV131(item,cached,exact,alias) else self:showImageV131(cached,imageCachePath(alias),url,true) end; return true end
    local co=coroutine.create(function()
        local decoded
        if kind=="png" then decoded=pngDecode(body,function(p) coroutine.yield("Decoding PNG...",p) end)
        elseif kind=="jpeg" then decoded=jpegDecode(body,function(p) coroutine.yield("Decoding JPEG...",p) end)
        else
            coroutine.yield("Decoding HCCI...",0.5); local ok,raw=pcall(textutils.unserialize,body); if not ok then error(raw) end; decoded=imageNormalize(raw); if not decoded then error("invalid HCCI image") end
        end
        local data,stored,size=imagePrepare(decoded,targetW,targetH,function(stage,p) coroutine.yield(stage,p) end)
        return data,stored,size,exact,alias
    end)
    self.job={stage="convert",co=co,item=item,url=url,cacheKey=exact,alias=alias}; self:progressV131(kind=="png" and "Decoding PNG..." or kind=="jpeg" and "Decoding JPEG..." or "Decoding HCCI...",0); return true
end
function Web:startRequestV131(url,kind,targetW,targetH,item)
    if type(http)~="table" or type(http.request)~="function" then return false,"CC:T HTTP request API unavailable" end
    local ok,accepted=pcall(http.request,url,nil,{["User-Agent"]="HCC-Web/1.3.1"},true); if not ok or accepted==false or accepted==nil then return false,"HTTP request failed or denied" end
    self.job={stage="wait",kind=kind,url=url,item=item,targetW=targetW,targetH=targetH}; self:progressV131("Downloading...",0); return true
end
function Web:onHttpSuccessV131(url,handle)
    if not self.job or self.job.url~=url then if handle and handle.close then pcall(handle.close) end; return end
    local h=self:headersV131(handle); local length=tonumber(h["content-length"] or "")
    if length and length>cfg.maxImageDownload then if handle.close then pcall(handle.close) end; self.job=nil; self.status="Image too large"; self.lines={"Download refused: Content-Length exceeds configured limit."}; self:markV131(); return end
    self.job.handle=handle; self.job.stage="download"; self.job.parts={}; self.job.bytes=0; self.job.contentType=h["content-type"] or ""; self.job.length=length; self.job.code=200
    if type(handle.getResponseCode)=="function" then local ok,code=pcall(handle.getResponseCode); if ok and finite(code) then self.job.code=code end end
end
function Web:onHttpFailureV131(url,reason)
    if not self.job or self.job.url~=url then return end
    local item=self.job.item; self.job=nil; self.status="HTTP request failed"; self.lines={"HTTP request failed: "..tostring(reason or "unknown error")}; if item then item.status="failed"; webImageStatusLine(self.lines,item.index,"failed") end; self:markV131(); if self.pageMode=="html" then self:queueNextImageV131() end
end
function Web:bodyReadyV131(job,body)
    if #body>cfg.maxImageDownload then self.job=nil; self.status="Image too large"; self.lines={"Download refused: response exceeds configured limit."}; self:markV131(); return end
    local kind=self:imageKindV131(job.url,job.contentType)
    if kind then self:startConversionV131(body,job.url,job.contentType,job.length,job.targetW or min(576,self.win and self.win.w or 576),job.targetH or min(320,self.win and self.win.h or 320),job.item); return end
    self.body=body; self.title,self.lines,self.links,self.pageImages=webParseV131(body,job.url); self.lines=webJsonLines(body) or self.lines; self.pageMode="html"; self.imageData=nil; self.imagePath=nil; self.linkSelected=1; self.top=1; self.job=nil; self.status="HTTP "..tostring(job.code or 200).."  "..#body.." bytes"; self:markV131(); self:queueNextImageV131()
end
function Web:updateV131()
    local job=self.job; if not job or job.stage=="wait" then return end
    if job.stage=="download" then
        local chunk; local ok=pcall(function() chunk=job.handle.read(16384) end)
        if not ok then if job.handle.close then pcall(job.handle.close) end; self.job=nil; self.status="Read failed"; self.lines={"Response body could not be read."}; self:markV131(); return end
        if chunk and #chunk>0 then job.parts[#job.parts+1]=chunk; job.bytes=job.bytes+#chunk; if job.bytes>cfg.maxImageDownload then if job.handle.close then pcall(job.handle.close) end; self.job=nil; self.status="Image too large"; self.lines={"Download refused: response exceeds configured limit."}; self:markV131(); return end; self:progressV131("Downloading...",job.length and job.bytes/job.length or 0); return end
        if job.handle.close then pcall(job.handle.close) end; self:bodyReadyV131(job,table.concat(job.parts)); return
    end
    if job.stage=="convert" then
        local ok,a,b,c,d,e=coroutine.resume(job.co)
        if not ok then local item=job.item; self.job=nil; if item then item.status="failed"; webImageStatusLine(self.lines,item.index,"failed"); self:markV131(); self:queueNextImageV131() else self.status="Image conversion failed"; self.lines={tostring(a)}; self:markV131() end; return end
        if coroutine.status(job.co)=="dead" then self:finishImageV131(job.item,a,d,e) else self:progressV131(a,b) end
    end
end
function Web:queueNextImageV131()
    if self.pageMode~="html" or self.job then return end
    for i,item in ipairs(self.pageImages or {}) do
        item.index=i
        if item.status=="pending" then
            self.imageIndex=i; local tw=max(64,min(384,(self.win and self.win.w or 548)-190)); local th=max(64,min(200,(self.win and self.win.h or 286)-110)); local ok,err=self:startRequestV131(item.url,"image",tw,th,item)
            if not ok then item.status="failed"; webImageStatusLine(self.lines,i,"failed"); self.status=tostring(err); self:markV131(); return self:queueNextImageV131() end
            return
        end
    end
    if #self.pageImages>0 then self.status="Page ready / images loaded"; self:markV131() end
end
function Web:initV131(url)
    self.url=""; self.status="Ready"; self.title="HCC Web"; self.lines={"Enter an HTTP/HTTPS URL and press GO."}; self.links={}; self.linkSelected=1; self.top=1; self.body=""; self.history={}; self.historyIndex=0; self.job=nil; self.pageMode="text"; self.pageImages={}; self.imageData=nil; self.imagePath=nil; self.imageIndex=1; self.cacheNotice=""
    if type(url)=="string" and url~="" then self:loadV131(url,true) end
end
function Web:loadV131(url,record)
    url=webSafeUrl(url); if not url then self.status="Invalid URL"; self.lines={"Only http:// and https:// URLs are allowed."}; self:markV131(); return false end
    self:cancelJobV131(); self.url=url; self.pageMode="text"; self.pageImages={}; self.imageData=nil; self.imagePath=nil; self.title="HCC Web"; self.lines={"Downloading..."}; self.linkSelected=1; self.top=1
    if record~=false then for i=#self.history,self.historyIndex+1,-1 do table.remove(self.history,i) end; self.history[#self.history+1]=url; self.historyIndex=#self.history end
    local kind=self:imageKindV131(url,""); if kind then local tw=min(576,self.win and self.win.w or 576); local th=min(320,self.win and self.win.h or 320); local alias=self:cacheAliasV131(url,tw,th); local cached=imageCacheLoad(alias); if cached then self:showImageV131(cached,imageCachePath(alias),url,true); return true end end
    local ok,err=self:startRequestV131(url,"page",nil,nil,nil); if not ok then self.status=tostring(err); self.lines={tostring(err)}; self:markV131(); return false end; self:markV131(); return true
end
function Web:cancel() self:cancelJobV131("Cancelled") end
function Web:clearCacheV131() local ok,err=imageCacheClear(); self.cacheNotice=ok and "Image cache cleared" or tostring(err); notify(self.cacheNotice,ok and P.success or P.error); self:markV131() end
function Web:openImageV131() if not self.imageData then return end; local w=openApp("image"); if w and self.imagePath then appCall(w,"loadPath",self.imagePath) elseif self.imageData then notify("Save the image as HCCI first",P.warning) end end
function Web:saveHcciV131()
    if not self.imageData then return end
    dialog("Save HCC Image","Absolute .hcci path",{"Save","Cancel"},function(b,value) if b=="Save" then value=tostring(value or ""); if value:sub(-5):lower()~=".hcci" then value=value..".hcci" end; local ok,err=imageWrite(value,self.imageData); if ok then self.imagePath=value; notify("Saved "..value,P.success) else errorBox(err) end end end,"/.hccos/images/web_image.hcci")
end
function Web:setWallpaperV131()
    if not self.imageData then return end; local path=self.imagePath; if not path then local alias=self:cacheAliasV131(self.url,576,320); local ok=imageCacheSave(alias,self.imageData); if ok then path=imageCachePath(alias); self.imagePath=path end end
    if not path then errorBox("Image cache unavailable; save as HCCI first"); return end
    cfg.wallpaperPath=path; cfg.wallpaperMode="fit"; wallpaperCache={path=nil,renderKey=nil,data=nil,commands=nil}; local ok,err=saveConfig(); allDirty(); if ok then notify("Wallpaper set from converted HCCI",P.success) else errorBox(err) end
end
function Web:downloadV131() Web.download(self) end
function Web:closeV131() self:cancelJobV131() end
function Web:drawV131(c)
    c:text(6,5,"HCC WEB",P.accent); c:text(6,19,self.title:sub(1,42),P.textPrimary)
    button(self,c,5,33,42,"BACK",function() self:back() end); button(self,c,51,33,48,"FORWARD",function() self:forward() end); button(self,c,103,33,48,"RELOAD",function() self:reload() end); button(self,c,156,33,39,"GO",function() self:goDialog() end); button(self,c,200,33,72,"DOWNLOAD",function() self:downloadV131() end); button(self,c,277,33,48,"CACHE",function() self:clearCacheV131() end); button(self,c,330,33,58,"CANCEL",function() self:cancel() end)
    local uw=max(20,c.w-10); c:filledRectangle(5,52,uw,15,P.panelBackground); c:rectangle(5,52,uw,15,P.border); c:text(9,55,self.url=="" and "URL / SEARCH" or self.url,P.textPrimary); c:text(6,70,self.status,P.textSecondary); c:line(0,76,c.w-1,76,P.border)
    if self.pageMode=="image" and self.imageData then
        local pv=c:clipping(5,82,c.w-10,max(20,c.h-111)); Widget.panel(pv,0,0,pv.w,pv.h,0xFF050505,P.border); drawImage(pv,self.imageData,2,2,pv.w-4,pv.h-4,"fit",1,0,0); button(self,c,5,c.h-25,78,"OPEN IMAGE",function() self:openImageV131() end); button(self,c,87,c.h-25,70,"SAVE HCCI",function() self:saveHcciV131() end); button(self,c,161,c.h-25,82,"WALLPAPER",function() self:setWallpaperV131() end); c:text(248,c.h-20,self.cacheNotice,P.warning)
    else
        local pw=175; local lw=max(30,c.w-pw-12); local rows=max(1,floor((c.h-111)/12)); self.top=clamp(self.top,1,max(1,#self.lines-rows+1)); local body=c:clipping(5,82,lw,rows*12+2); Widget.panel(body,0,0,body.w,body.h,0xFF050505,P.border)
        for i=0,rows-1 do local line=self.lines[self.top+i]; if not line then break end; body:text(3,3+i*12,line,P.textPrimary) end
        local pv=c:clipping(c.w-pw-3,82,pw,max(20,c.h-111)); Widget.panel(pv,0,0,pv.w,pv.h,0xFF050505,P.border); local item=self.pageImages and self.pageImages[self.imageIndex]; if item and item.data then drawImage(pv,item.data,2,2,pv.w-4,pv.h-25,"fit",1,0,0); pv:text(4,pv.h-17,"IMG "..self.imageIndex.."/"..#self.pageImages,P.textSecondary) else pv:paragraph(6,16,"Images load after page text.",P.textSecondary,pv.w-12,2) end
        button(self,c,c.w-pw-1,c.h-25,47,"NEXT",function() self.imageIndex=self.imageIndex%max(1,#self.pageImages)+1; mark(self.win) end); c:text(6,c.h-14,string.format("%d lines  %d links  %d images  Q cancel",#self.lines,#self.links,#self.pageImages),P.textSecondary)
    end
end
Web.init=Web.initV131; Web.load=Web.loadV131; Web.interval=Web.interval; Web.update=Web.updateV131; Web.onHttpSuccess=Web.onHttpSuccessV131; Web.onHttpFailure=Web.onHttpFailureV131; Web.draw=Web.drawV131; Web.close=Web.closeV131
end

-- Inventory Viewer ----------------------------------------------------------
-- The viewer intentionally uses only the common ComputerCraft inventory
-- methods.  Mod-specific item APIs are optional and never required to boot.
local Inventory={}
function Inventory:init(args)
    self.selected=1; self.top=1; self.inventoryIndex=1; self.slots={}; self.lastRefresh=0
    self:refresh(args and args.inventory)
end
function Inventory:interval() return cfg.inventoryRefresh end
function Inventory:refresh(preferred)
    if preferred then
        for i,v in ipairs(devices.inventories) do if v.name==preferred then self.inventoryIndex=i end end
    end
    local info=devices.inventories[self.inventoryIndex]
    self.info=info; self.slots={}; self.error=nil
    if info then
        local ok,size=pcall(info.p.size)
        local listed,list=pcall(info.p.list)
        if not ok or not listed or type(list)~="table" then self.error="Inventory list unavailable"
        else
            for slot=1,floor(size) do
                local item=list[slot]
                if item then
                    local detail=item
                    if type(info.p.getItemDetail)=="function" then
                        local good,value=pcall(info.p.getItemDetail,slot); if good and type(value)=="table" then detail=value end
                    end
                    self.slots[slot]={slot=slot,id=ascii(detail.name or detail.id or "unknown"),
                        name=ascii(detail.displayName or detail.name or detail.id or "unknown"),count=floor(detail.count or item.count or 0),
                        nbt=detail.nbt}
                end
            end
        end
    end
    self.selected=clamp(self.selected,1,max(1,info and (pcall(info.p.size) and info.p.size() or 1) or 1))
    self.lastRefresh=now(); mark(self.win)
end
function Inventory:nextInventory(delta)
    if #devices.inventories==0 then self:refresh(); return end
    self.inventoryIndex=(self.inventoryIndex-1+delta)%#devices.inventories+1; self:refresh()
end
function Inventory:openPrice()
    local item=self.slots[self.selected]; if not item then return end
    local w=openApp("currency"); if w then
        appCall(w,"selectItemId",item.id)
        notify(currencyItemById(item.id) and "Currency item selected" or "Item not in Currency dictionary",currencyItemById(item.id) and P.success or P.warning)
    end
end
function Inventory:onKey(k)
    local size=self.info and (select(2,pcall(self.info.p.size)) or 1) or 1
    if k==keys.up then self.selected=max(1,self.selected-1)
    elseif k==keys.down then self.selected=min(size,self.selected+1)
    elseif k==keys.left then self:nextInventory(-1)
    elseif k==keys.right or k==keys.i then self:nextInventory(1)
    elseif k==keys.f5 then self:refresh()
    elseif k==keys.enter or k==keys.p then self:openPrice() end
    mark(self.win)
end
function Inventory:onMouse(kind,x,y,b)
    if kind=="scroll" then self.selected=clamp(self.selected+b*3,1,max(1,self.info and (select(2,pcall(self.info.p.size)) or 1) or 1))
    elseif kind=="click" then
        if y<27 and x>=self.win.w-75 then self:nextInventory(1); return end
        if y>=34 and y<self.win.h-35 and x<self.win.w*0.58 then self.selected=clamp(1+floor((y-34)/18)+self.top-1,1,max(1,self.info and (select(2,pcall(self.info.p.size)) or 1) or 1))
        elseif y>=self.win.h-28 then self:openPrice() end
    end
    mark(self.win)
end
function Inventory:draw(c)
    c:text(6,5,"INVENTORY VIEWER",P.accent)
    if #devices.inventories==0 then
        c:paragraph(8,34,"No compatible inventory peripheral found. Connect a chest or storage peripheral and press F5.",P.warning,c.w-16,5)
        c:text(8,c.h-14,"F5 RESCAN",P.textSecondary); return
    end
    local info=self.info or devices.inventories[self.inventoryIndex]; local size=1
    if info then local ok,n=pcall(info.p.size); if ok and finite(n) then size=n end end
    local title=(info and info.name or "inventory").."  "..size.." slots"
    c:text(6,19,title,P.textSecondary)
    button(self,c,c.w-70,3,63,"NEXT",function() self:nextInventory(1) end)
    local left=floor(c.w*0.58); c:line(left,32,left,c.h-30,P.border)
    local rows=max(1,floor((c.h-70)/18)); self.top=clamp(self.top,1,max(1,size-rows+1))
    if self.selected<self.top then self.top=self.selected elseif self.selected>=self.top+rows then self.top=self.selected-rows+1 end
    for row=0,rows-1 do
        local slot=self.top+row; if slot>size then break end; local item=self.slots[slot]; local y=34+row*18
        if slot==self.selected then c:filledRectangle(5,y,left-10,17,P.panelBackground) end
        c:text(9,y+4,string.format("%03d",slot),P.textSecondary)
        c:text(35,y+4,item and item.name:sub(1,22) or "- empty -",item and P.textPrimary or P.textSecondary)
        if item then c:text(left-48,y+4,"x"..item.count,P.accent) end
    end
    local item=self.slots[self.selected]; local right=c:clipping(left+7,34,c.w-left-12,c.h-64)
    right:text(0,0,"SELECTED SLOT",P.accent)
    if item then
        right:paragraph(0,18,item.name,P.textPrimary,right.w,3)
        right:text(0,57,"ID: "..item.id,P.textSecondary)
        right:text(0,72,"COUNT: "..item.count,P.textPrimary)
        local priced=currencyItemById(item.id)
        right:text(0,90,priced and ("BUY: "..(priced.buy=="" and "-" or priced.buy).."  SELL: "..(priced.sell=="" and "-" or priced.sell)) or "PRICE: NOT REGISTERED",priced and P.success or P.warning)
    else right:text(0,22,"Choose a slot",P.textSecondary) end
    button(self,c,5,c.h-25,95,"P: PRICE",function() self:openPrice() end)
    c:text(106,c.h-20,"I/ARROWS inventory  F5 refresh",P.textSecondary)
end
register("inventory","Inventory Viewer","IV",500,270,Inventory)

-- Peripheral Manager --------------------------------------------------------
local PeripheralManager={}
function PeripheralManager:init() self.selected=1; self.methods={}; self:refresh() end
function PeripheralManager:refresh()
    self.methods={}; self.selected=clamp(self.selected,1,max(1,#devices.list)); local item=devices.list[self.selected]
    if item and peripheral.getMethods then local ok,m=pcall(peripheral.getMethods,item.name); if ok and type(m)=="table" then self.methods=m; table.sort(self.methods) end end
    mark(self.win)
end
function PeripheralManager:onKey(k)
    if k==keys.up then self.selected=max(1,self.selected-1); self:refresh()
    elseif k==keys.down then self.selected=min(#devices.list,self.selected+1); self:refresh()
    elseif k==keys.f5 then rescan(); self:refresh()
    end
end
function PeripheralManager:onMouse(kind,x,y,b)
    if kind=="scroll" then self.selected=clamp(self.selected+b,1,max(1,#devices.list)); self:refresh()
    elseif kind=="click" and y>=32 and y<self.win.h-26 and x<self.win.w*0.52 then self.selected=clamp(1+floor((y-32)/17),1,max(1,#devices.list)); self:refresh() end
end
function PeripheralManager:draw(c)
    c:text(6,5,"PERIPHERAL MANAGER",P.accent); c:text(6,19,"F5 rescan  arrows select",P.textSecondary)
    local left=floor(c.w*0.52); c:line(left,31,left,c.h-27,P.border)
    for i,item in ipairs(devices.list) do
        local y=32+(i-1)*17; if i==self.selected then c:filledRectangle(4,y,left-9,16,P.panelBackground) end
        c:text(8,y+3,item.name:sub(1,24),P.textPrimary); c:text(left-75,y+3,item.kind:sub(1,10),P.textSecondary)
    end
    local item=devices.list[self.selected]; local r=c:clipping(left+7,34,c.w-left-12,c.h-64)
    r:text(0,0,"DEVICE",P.accent); r:text(0,17,item and item.name or "none",P.textPrimary); r:text(0,31,item and item.kind or "",P.textSecondary)
    r:text(0,49,"METHODS",P.accent)
    for i,name in ipairs(self.methods) do r:text(0,63+(i-1)*12,name,P.textSecondary) end
    button(self,c,5,c.h-23,75,"F5 RESCAN",function() rescan(); self:refresh() end)
end
register("peripherals","Peripheral Manager","PM",460,260,PeripheralManager)

-- Network Manager -----------------------------------------------------------
local NetworkManager={}
function NetworkManager:init() self.selected=1; self.channel=1; self.nodes={}; self:refresh() end
function NetworkManager:interval() return cfg.networkRefresh end
function NetworkManager:refresh()
    self.nodes={}
    for _,m in ipairs(devices.modems) do
        local open=false; if type(m.p.isOpen)=="function" then local ok,v=pcall(m.p.isOpen,self.channel); open=ok and v==true end
        self.nodes[#self.nodes+1]={name=m.name,type=m.wireless and "wireless modem" or "wired modem",open=open,localNode=true}
        if type(m.p.getNamesRemote)=="function" then local ok,names=pcall(m.p.getNamesRemote); if ok and type(names)=="table" then for _,remote in ipairs(names) do self.nodes[#self.nodes+1]={name=m.name.." -> "..tostring(remote),type="remote peripheral",remote=true} end end end
    end
    self.selected=clamp(self.selected,1,max(1,#self.nodes)); mark(self.win)
end
function NetworkManager:toggle()
    local node=self.nodes[self.selected]; if not node or node.remote then return end
    for _,m in ipairs(devices.modems) do if m.name==node.name then local ok,err=pcall(function() if node.open then m.p.close(self.channel) else m.p.open(self.channel) end end); if not ok then errorBox(err) else self:refresh(); notify((node.open and "Closed" or "Opened").." channel "..self.channel,P.success) end; return end end
end
function NetworkManager:onKey(k)
    if k==keys.up then self.selected=max(1,self.selected-1) elseif k==keys.down then self.selected=min(#self.nodes,self.selected+1)
    elseif k==keys.f5 then rescan(); self:refresh() elseif k==keys.enter then self:toggle() end; mark(self.win)
end
function NetworkManager:onMouse(kind,x,y,b)
    if kind=="scroll" then self.selected=clamp(self.selected+b,1,max(1,#self.nodes))
    elseif kind=="click" and y>=34 and y<self.win.h-30 then self.selected=clamp(1+floor((y-34)/17),1,max(1,#self.nodes)); self:toggle() end
    mark(self.win)
end
function NetworkManager:draw(c)
    c:text(6,5,"NETWORK MANAGER",P.accent); c:text(6,19,"Logical topology / attach-detach safe",P.textSecondary)
    local left=floor(c.w*0.57); c:line(left,31,left,c.h-28,P.border)
    for i,node in ipairs(self.nodes) do local y=34+(i-1)*17; if i==self.selected then c:filledRectangle(4,y,left-9,16,P.panelBackground) end; c:text(8,y+3,node.name:sub(1,27),P.textPrimary); c:text(left-70,y+3,node.remote and "REMOTE" or (node.open and "OPEN" or "CLOSED"),node.open and P.success or P.textSecondary) end
    local node=self.nodes[self.selected]; c:text(left+8,36,node and node.name or "No modem",P.textPrimary); c:text(left+8,54,node and node.type or "Attach a modem",P.textSecondary)
    c:text(left+8,75,"CHANNEL: "..self.channel,P.accent); c:text(left+8,91,"ENTER / click toggle",P.textSecondary)
    button(self,c,5,c.h-23,75,"F5 RESCAN",function() rescan(); self:refresh() end)
end
register("network","Network Manager","NW",500,250,NetworkManager)

-- Resource Monitor ----------------------------------------------------------
local ResourceMonitor={}
function ResourceMonitor:init() self.items={}; self.previous={}; self.history={}; self.top=1; self:update() end
function ResourceMonitor:interval() return cfg.resourceRefresh end
function ResourceMonitor:update()
    local aggregate={}
    for _,info in ipairs(devices.inventories) do
        local ok,list=pcall(info.p.list)
        if ok and type(list)=="table" then for _,item in pairs(list) do local id=ascii(item.name or item.id or "unknown"); aggregate[id]=(aggregate[id] or 0)+floor(item.count or 0) end end
    end
    self.items={}; local total=0
    for id,count in pairs(aggregate) do
        local price=currencyItemById(id); local unit=price and currencyItemValue(price,"buy"); local value=unit and unit*count or nil
        if value then total=total+value end
        self.items[#self.items+1]={id=id,count=count,change=count-(self.previous[id] or count),item=price,value=value,stack=price and price.stack or 64}
    end
    table.sort(self.items,function(a,b) return a.id<b.id end); self.previous=aggregate
    self.history[#self.history+1]=total; while #self.history>cfg.performanceHistory do table.remove(self.history,1) end; self.total=total; mark(self.win)
end
function ResourceMonitor:onKey(k) if k==keys.f5 then rescan(); self:update() elseif k==keys.up then self.top=max(1,self.top-1) elseif k==keys.down then self.top=min(max(1,#self.items),self.top+1) end; mark(self.win) end
function ResourceMonitor:onMouse(kind,x,y,b) if kind=="scroll" then self.top=clamp(self.top+b,1,max(1,#self.items)); mark(self.win) end end
function ResourceMonitor:draw(c)
    c:text(6,5,"RESOURCE MONITOR",P.accent); c:text(6,19,"Inventory totals / Currency estimate",P.textSecondary)
    local header="ITEM                         COUNT  STACKS CHANGE  VALUE"; c:text(6,35,header,P.accent)
    local rows=max(1,floor((c.h-77)/14)); self.top=clamp(self.top,1,max(1,#self.items-rows+1))
    for row=0,rows-1 do local item=self.items[self.top+row]; if not item then break end; local y=50+row*14; c:text(6,y,item.id:sub(1,28),P.textPrimary); c:text(190,y,tostring(item.count),P.textPrimary); c:text(245,y,string.format("%d+%d",floor(item.count/item.stack),item.count%item.stack),P.textSecondary); c:text(315,y,(item.change>=0 and "+" or "")..item.change,item.change>=0 and P.success or P.warning); c:text(370,y,item.value and currencyFormat(item.value,currencyData.allowDecimals) or "-",item.value and P.accent or P.textSecondary) end
    c:text(6,c.h-15,"TOTAL: "..(self.total and currencyFormat(self.total,currencyData.allowDecimals) or "-").."  F5 refresh",P.accent)
end
register("resource","Resource Monitor","RS",500,250,ResourceMonitor)

-- Log Viewer ----------------------------------------------------------------
local LogViewer={}
function LogViewer:init() self.top=1; self.level="ALL"; self.query="" end
function LogViewer:visible()
    local out={}; local q=self.query:lower()
    for _,entry in ipairs(OS.logs) do if (self.level=="ALL" or entry.level==self.level) and (q=="" or entry.message:lower():find(q,1,true)) then out[#out+1]=entry end end
    return out
end
function LogViewer:search()
    dialog("Log search","Text filter (blank = all)",{"OK","Cancel"},function(b,value) if b=="OK" then self.query=value; self.top=1; mark(self.win) end end,self.query)
end
function LogViewer:clear()
    dialog("Clear log","Delete the in-memory event log?",{"Yes","No"},function(b) if b=="Yes" then OS.logs={}; self.top=1; notify("Log cleared",P.warning); mark(self.win) end end)
end
function LogViewer:onKey(k)
    local entries=self:visible(); if k==keys.up then self.top=max(1,self.top-3) elseif k==keys.down then self.top=min(max(1,#entries),self.top+3) elseif k==keys.f5 then self.query=""; self.level="ALL" elseif k==keys.pageUp then self.top=max(1,self.top-10) elseif k==keys.pageDown then self.top=min(max(1,#entries),self.top+10) end; mark(self.win)
end
function LogViewer:onMouse(kind,x,y,b) if kind=="scroll" then self.top=clamp(self.top+b*3,1,max(1,#self:visible())); mark(self.win) end end
function LogViewer:draw(c)
    local entries=self:visible(); c:text(6,5,"LOG VIEWER",P.accent); c:text(6,19,self.level..(self.query~="" and " / "..self.query or ""),P.textSecondary)
    button(self,c,c.w-163,3,45,"ALL",function() self.level="ALL"; self.top=1; mark(self.win) end); button(self,c,c.w-113,3,48,"WARN",function() self.level="WARN"; self.top=1; mark(self.win) end); button(self,c,c.w-60,3,55,"ERROR",function() self.level="ERROR"; self.top=1; mark(self.win) end)
    local rows=max(1,floor((c.h-66)/13)); self.top=clamp(self.top,1,max(1,#entries-rows+1))
    for row=0,rows-1 do local e=entries[self.top+row]; if not e then break end; local y=35+row*13; local d=os.date("!*t",floor(e.time)+32400); local stamp=string.format("%02d:%02d:%02d",d.hour,d.min,d.sec); c:text(6,y,stamp.." "..e.level,e.level=="ERROR" and P.error or (e.level=="WARN" and P.warning or P.textSecondary)); c:text(91,y,e.message:sub(1,math.max(1,c.w-96)),P.textPrimary) end
    button(self,c,5,c.h-23,58,"SEARCH",function() self:search() end); button(self,c,68,c.h-23,51,"CLEAR",function() self:clear() end); c:text(125,c.h-18,#entries.." entries / F5 reset",P.textSecondary)
end
register("logs","Log Viewer","LG",540,260,LogViewer)

-- Performance graph and System Monitor ------------------------------------
local function graph(c,x,y,w,h,values,color,limit)
    Widget.panel(c,x,y,w,h,P.windowBackground,P.border)
    local n=#values; if n<2 then return end
    limit=limit or 1
    for i=2,n do
        local x1=x+floor((i-2)*max(1,w-2)/max(1,n-1))+1
        local x2=x+floor((i-1)*max(1,w-2)/max(1,n-1))+1
        local y1=y+h-2-floor(clamp(values[i-1]/limit,0,1)*(h-3)); local y2=y+h-2-floor(clamp(values[i]/limit,0,1)*(h-3))
        c:line(x1,y1,x2,y2,color or P.accent)
    end
end
local SystemMonitor={}
function SystemMonitor:init() self.tps={}; self.mspt={}; self.renders={}; self.last=0; self:update() end
function SystemMonitor:interval() return cfg.systemInterval end
function SystemMonitor:update()
    local function push(a,v) a[#a+1]=v; while #a>cfg.performanceHistory do table.remove(a,1) end end
    push(self.tps,OS.renderRate); push(self.mspt,Driver.syncs); push(self.renders,OS.renderCount)
    self.last=now(); mark(self.win)
end
function SystemMonitor:onKey(k) if k==keys.f5 then rescan(); self:update() end end
function SystemMonitor:draw(c)
    c:text(7,5,HCC_VERSION_LABEL.." / SYSTEM MONITOR",P.accent)
    c:text(7,19,"CPU: "..HCC_CPU,P.textPrimary)
    local aw,ah=Driver.getActualSize(); c:text(7,32,string.format("DISPLAY %dx%d  %dx%d blocks @ %dpx",aw,ah,HCC_BLOCKS_X,HCC_BLOCKS_Y,HCC_PIXELS_PER_BLOCK),P.textSecondary)
    local memOk,mem=pcall(collectgarbage,"count"); local gx=c.w>=390 and floor(c.w*0.55) or 0
    c:text(7,47,string.format("UPTIME %ds  WINDOWS %d  PERIPHERALS %d",floor(now()-OS.started),#OS.windows,#devices.list),P.textSecondary)
    c:text(7,61,string.format("GPU %s  PAINT %.1f/s  SYNC %.1f/s",devices.gpuName or "NONE",OS.renderRate,OS.syncRate),P.textSecondary)
    c:text(7,75,"MEMORY: "..(memOk and string.format("%.0f KiB",mem) or "n/a"),P.textSecondary)
    if gx>0 then graph(c,gx,47,c.w-gx-8,82,self.renders,P.accent,max(1,OS.renderCount))
    else graph(c,7,93,c.w-14,62,self.renders,P.accent,max(1,OS.renderCount)) end
    local y=gx>0 and 139 or 166; c:text(7,y,"PERFORMANCE HISTORY",P.accent)
    c:text(7,y+14,"render samples: "..#self.renders.." / "..cfg.performanceHistory,P.textSecondary)
    c:text(7,y+28,"F5 RESCAN   system interval "..cfg.systemInterval.."s",P.textSecondary)
end
register("system","System Monitor","SM",470,225,SystemMonitor)

local Performance={}
function Performance:init() self.values={}; self:update() end
function Performance:interval() return cfg.systemInterval end
function Performance:update() self.values[#self.values+1]=OS.renderRate; while #self.values>cfg.performanceHistory do table.remove(self.values,1) end; mark(self.win) end
function Performance:draw(c)
    c:text(7,6,"PERFORMANCE GRAPH",P.accent); c:text(7,20,"Paint rate / second",P.textSecondary)
    graph(c,8,39,c.w-16,c.h-70,self.values,P.success,max(1,OS.renderRate,1))
    c:text(8,c.h-22,string.format("CURRENT %.1f/s  SAMPLES %d",OS.renderRate,#self.values),P.textPrimary)
end
register("performance","Performance Graph","PG",350,190,Performance)

-- Task Manager --------------------------------------------------------------
local TaskManager={}
function TaskManager:init() self.selected=1 end
function TaskManager:onKey(k)
    if k==keys.up then self.selected=max(1,self.selected-1)
    elseif k==keys.down then self.selected=min(#OS.windows,self.selected+1)
    elseif k==keys.enter then local w=OS.windows[self.selected]; if w then focus(w) end
    elseif k==keys.delete then local w=OS.windows[self.selected]; if w then closeWindow(w) end end
    mark(self.win)
end
function TaskManager:onMouse(kind,x,y,b)
    if kind=="scroll" then self.selected=clamp(self.selected+b,1,max(1,#OS.windows))
    elseif kind=="click" and y>=33 and y<self.win.h-30 then self.selected=clamp(1+floor((y-33)/18),1,max(1,#OS.windows)) end
    mark(self.win)
end
function TaskManager:draw(c)
    c:text(6,6,"TASK MANAGER",P.accent); c:text(6,20,"ENTER focus  DELETE close  F6 tile",P.textSecondary)
    for i,w in ipairs(OS.windows) do
        local y=33+(i-1)*18; if i==self.selected then c:filledRectangle(5,y,c.w-10,17,P.panelBackground) end
        drawAppIcon(c,w.app,8,y+1,14,w.crash and "error" or (w==OS.active and "selected" or (iconIsOffline(w.id) and "offline" or "normal")))
        c:text(28,y+4,w.name:sub(1,24),w.crash and P.error or P.textPrimary)
        c:text(c.w-84,y+4,w.minimized and "MIN" or (w==OS.active and "ACTIVE" or "READY"),P.textSecondary)
    end
    if #OS.windows==0 then c:text(8,45,"No running applications",P.textSecondary) end
    c:text(6,c.h-13,string.format("%d tasks  CPU %s",#OS.windows,HCC_CPU),P.textSecondary)
end
register("taskmgr","Task Manager","TM",390,220,TaskManager)

-- Terminal ------------------------------------------------------------------
local Terminal={}
function Terminal:init() self.lines={HCC_VERSION_LABEL.." terminal","Type help for commands."}; self.input=""; self.cursor=0; self.scroll=0 end
function Terminal:write(line) self.lines[#self.lines+1]=ascii(line); if #self.lines>200 then table.remove(self.lines,1) end end
function Terminal:execute(line)
    line=line:gsub("^%s+",""):gsub("%s+$",""); self:write("> "..line); if line=="" then return end
    local cmd,arg=line:match("^(%S+)%s*(.*)$"); cmd=cmd:lower()
    if cmd=="help" then self:write("help version apps sysinfo peripherals date clear open <id> close tile update recovery install echo <text>")
    elseif cmd=="version" then self:write(HCC_VERSION_LABEL)
    elseif cmd=="apps" then self:write(table.concat(OS.order,"  "))
    elseif cmd=="sysinfo" then local w,h=Driver.getActualSize(); self:write(string.format("CPU %s | DISPLAY %dx%d | GPU %s",HCC_CPU,w,h,devices.gpuName or "none"))
    elseif cmd=="peripherals" then self:write(#devices.list.." peripherals: "..table.concat((function() local a={}; for _,v in ipairs(devices.list) do a[#a+1]=v.name end; return a end)(),", "))
    elseif cmd=="date" then self:write(dateText(jst()).." "..timeText(jst()).." JST")
    elseif cmd=="clear" then self.lines={}; self.scroll=0
    elseif cmd=="echo" then self:write(arg)
    elseif cmd=="open" and OS.registry[arg] then openApp(arg)
    elseif cmd=="update" and HCCV14 then openApp("updates")
    elseif cmd=="recovery" then shell.run("/hcc_os/boot.lua","--recovery")
    elseif cmd=="install" then shell.run("/hcc_os/installer.lua")
    elseif cmd=="close" then closeWindow(self.win)
    elseif cmd=="tile" then tileWindows()
    else self:write("Unknown command: "..cmd) end
    self.input=""; self.cursor=0; self.scroll=0; mark(self.win)
end
function Terminal:onChar(s) self.input=self.input:sub(1,self.cursor)..ascii(s)..self.input:sub(self.cursor+1); self.cursor=self.cursor+#s; mark(self.win) end
function Terminal:onKey(k)
    if k==keys.enter then self:execute(self.input)
    elseif k==keys.left then self.cursor=max(0,self.cursor-1)
    elseif k==keys.right then self.cursor=min(#self.input,self.cursor+1)
    elseif k==keys.home then self.cursor=0 elseif k==keys["end"] then self.cursor=#self.input
    elseif k==keys.backspace and self.cursor>0 then self.input=self.input:sub(1,self.cursor-1)..self.input:sub(self.cursor+1); self.cursor=self.cursor-1
    elseif k==keys.delete then self.input=self.input:sub(1,self.cursor)..self.input:sub(self.cursor+2)
    elseif k==keys.up then self.scroll=min(max(0,#self.lines-1),self.scroll+1)
    elseif k==keys.down then self.scroll=max(0,self.scroll-1) end
    mark(self.win)
end
function Terminal:draw(c)
    c:filledRectangle(0,0,c.w,c.h,0xFF050505)
    local rows=max(1,floor((c.h-32)/11)); local last=#self.lines-self.scroll; local first=max(1,last-rows+1)
    for i=first,last do c:text(7,5+(i-first)*11,self.lines[i],P.textPrimary) end
    c:filledRectangle(5,c.h-22,c.w-10,18,0xFF111111); c:text(8,c.h-18,"> "..self.input,P.accent)
    local cx=8+Driver.measure("> "..self.input:sub(1,self.cursor)); c:line(cx,c.h-19,cx,c.h-7,P.textPrimary)
end
register("terminal","Terminal","TR",510,250,Terminal)

local settingsFields={
    {"system","System","section"}, {"computerLabel","Computer Label","string"},
    {"clockInterval","Clock interval (s)",0.1,5},
    {"radarInterval","Radar interval (s)",0.25,5}, {"serverInterval","Server interval (s)",1,5},
    {"snapEnabled","Window snap","toggle"}, {"snapDistance","Snap distance",2,32},
    {"appearance","Appearance","section"}, {"theme","Theme","theme"}, {"accent","Accent","string"},
    {"showRichIcons","Rich icons","toggle"}, {"taskbarLabels","Taskbar labels","toggle"},
    {"wallpaperMode","Wallpaper mode","wallpaperMode"}, {"wallpaperPath","Wallpaper .hcci path","string"},
    {"display","Display","section"}, {"resolution","GPU resolution",16,64},
    {"centerX","Radar center X",-1000000000,1000000000}, {"centerZ","Radar center Z",-1000000000,1000000000},
    {"input","Input","section"},
    {"dimension","Radar dimension","string"}, {"gpuName","GPU name (blank = auto)","string"},
    {"keyboardName","Keyboard (blank = auto)","string"}, {"detectorName","Detector (blank = auto)","string"}}
table.insert(settingsFields, {"network","Network","section"})
table.insert(settingsFields, {"update","Update & Recovery","action"})
table.insert(settingsFields, {"restore","Restore Previous Version","restore"})
table.insert(settingsFields, {"updateChannel","Update Channel","string"})
table.insert(settingsFields, {"autoUpdateCheck","Automatic update check","toggle"})
table.insert(settingsFields, {"storage","Storage","section"})
table.insert(settingsFields, {"storageInfo","Capacity / free space","storage"})
table.insert(settingsFields, {"about","About","about"})
local Settings={}
function Settings:init() self.selected=1; self.top=1 end
function Settings:edit()
    local f=settingsFields[self.selected]
    if not f or f[3]=="section" or f[3]=="about" or f[3]=="storage" then return end
    if f[3]=="action" then if HCCV14 then openApp("updates") else errorBox("Update service unavailable") end; return end
    if f[3]=="restore" then
        if not HCCV14 then errorBox("Update service unavailable"); return end
        local ok,err=HCCV14.rollback(); if ok then notify("Previous version restored; restart HCC OS",P.success) else errorBox(err) end
        return
    end
    if f[3]=="theme" then cfg.theme=cfg.theme=="black" and "midnight" or "black"; P=palettes[cfg.theme]; applyAccent(); allDirty(); return end
    if f[3]=="toggle" then cfg[f[1]]=not cfg[f[1]]; mark(self.win); return end
    if f[3]=="wallpaperMode" then
        local modes={black="center",center="fit",fit="fill",fill="stretch",stretch="tile",tile="black"}
        cfg.wallpaperMode=modes[cfg.wallpaperMode] or "black"; wallpaperCache={path=nil,renderKey=nil,data=nil,commands=nil}; allDirty(); return
    end
    dialog("Setting",f[2],{"OK","Cancel"},function(b,value)
        if b~="OK" then return end
        if f[3]=="string" then
            if #value>128 or value:find("[\r\n]") then errorBox("Use one line, at most 128 characters"); return end
            cfg[f[1]]=value
        else
            local n=tonumber(value)
            if not finite(n) or n<f[3] or n>f[4] then errorBox("Allowed range: "..f[3].." to "..f[4]); return end
            cfg[f[1]]=n
        end
        for _,w in ipairs(OS.windows) do
            if w.id=="radar" then w.app.dim=dimension(cfg.dimension); w.nextUpdate=now() end
        end
        mark(self.win)
    end,tostring(cfg[f[1]]))
end
function Settings:save()
    local ok,err=saveConfig(); if ok then notify("Settings saved",P.success) else errorBox(err) end
end
function Settings:onKey(k)
    if k==keys.up then self.selected=max(1,self.selected-1)
    elseif k==keys.down then self.selected=min(#settingsFields,self.selected+1)
    elseif k==keys.enter then self:edit()
    elseif k==keys.s then self:save()
    elseif k==keys.f5 then rescan() end
    mark(self.win)
end
function Settings:onMouse(kind,x,y,b)
    if kind=="scroll" then self.selected=clamp(self.selected+b,1,#settingsFields)
    elseif kind=="click" and y>=34 and y<self.win.h-TITLE-31 then
        local i=self.top+floor((y-34)/18)
        if settingsFields[i] then self.selected=i; self:edit() end
    end
    mark(self.win)
end
function Settings:draw(c)
    c:text(6,6,string.format("DISPLAY %dx%d  TARGET 576x320",Driver.w,Driver.h),P.accent)
    c:text(6,19,"Names take effect after RESCAN",P.textSecondary)
    local rows=max(1,floor((c.h-64)/18))
    if self.selected<self.top then self.top=self.selected elseif self.selected>=self.top+rows then self.top=self.selected-rows+1 end
    for j=0,rows-1 do
        local i=self.top+j; local f=settingsFields[i]; if not f then break end
        local y=34+j*18
        if f[3]=="section" then
            c:text(9,y+4,string.upper(f[2]),P.accent)
        else
            if i==self.selected then c:filledRectangle(5,y,c.w-10,17,P.panelBackground) end
            c:clipping(9,y+4,c.w*0.6-12,10):text(0,0,f[2],P.textSecondary)
            local value=(f[3]=="action" and "OPEN") or (f[3]=="restore" and "RUN") or (f[3]=="about" and (HCC_VERSION_LABEL.." / BUILD 1400 / EDITION TOM") or tostring(cfg[f[1]]))
            if f[3]=="about" then
                local id=cfg.computerId~="" and cfg.computerId or "UNKNOWN"
                local label=cfg.computerLabel~="" and cfg.computerLabel or "UNLABELLED"
                local aw,ah=Driver.getActualSize()
                c:clipping(9,y+4,c.w-18,10):text(0,0,string.format("%s / ID %s / %s / %dx%d",HCC_VERSION_LABEL,id,label,aw,ah),P.textPrimary)
            elseif f[3]=="storage" then
                local capacity,free
                if type(fs.getCapacity)=="function" then local ok,value=pcall(fs.getCapacity,"/"); if ok then capacity=value end end
                if type(fs.getFreeSpace)=="function" then local ok,value=pcall(fs.getFreeSpace,"/"); if ok then free=value end end
                local storage=(capacity and free) and string.format("%.0f / %.0f bytes",free,capacity) or "Unavailable"
                c:text(c.w*0.6,y+4,storage,P.textPrimary)
            else
                c:text(c.w*0.6,y+4,value=="" and "AUTO" or value,P.textPrimary)
            end
        end
    end
    button(self,c,5,c.h-23,62,"S: SAVE",function() self:save() end)
    button(self,c,73,c.h-23,80,"RESCAN",function() rescan() end)
    button(self,c,159,c.h-23,76,"UPDATE",function() self:editUpdate() end)
end
function Settings:editUpdate()
    if HCCV14 then openApp("updates") else errorBox("Update service unavailable") end
end
register("settings","Settings","ST",372,272,Settings)

local Diagnostics={}
function Diagnostics:init() self.top=1 end
function Diagnostics:interval() return 1 end
function Diagnostics:update() mark(self.win) end
function Diagnostics:onKey(k)
    if k==keys.down then self.top=self.top+1 elseif k==keys.up then self.top=max(1,self.top-1)
    elseif k==keys.f5 then rescan() end; mark(self.win)
end
function Diagnostics:onMouse(kind,x,y,b) if kind=="scroll" then self.top=max(1,self.top+b*3); mark(self.win) end end
function Diagnostics:draw(c)
    local ok,mem=pcall(collectgarbage,"count")
    local actualW,actualH=Driver.getActualSize()
    local lines={HCC_VERSION_LABEL.." / CC:T 1.120.0", "Version: "..HCC_VERSION,
        "CPU: "..HCC_CPU, "GPU: "..(devices.gpuName or "UNAVAILABLE"),
        string.format("getSize(): %dx%d / %d pixels",actualW,actualH,actualW*actualH),
        "Target 576x320 / 9x5 blocks / 64px: "..((actualW==HCC_TARGET_W and actualH==HCC_TARGET_H) and "MATCH" or "ADAPTIVE LAYOUT"),
        "Player Detector: "..(devices.detectorName or "UNAVAILABLE"),
        "Tom keyboard: "..(next(devices.keyboards) and "CONNECTED" or "NONE; terminal keys available"),
        "Memory: "..(ok and string.format("%.0f KiB",mem) or "Unavailable"),
        "Uptime: "..floor(now()-OS.started).."s",
        string.format("Paints/s %.1f  Sync/s %.1f",OS.renderRate,OS.syncRate),
        "Driver error: "..(Driver.error or "none"),"--- CONNECTED PERIPHERALS ---"}
    for _,p in ipairs(devices.list) do lines[#lines+1]=p.name.." : "..p.kind end
    self.top=clamp(self.top,1,max(1,#lines-floor((c.h-28)/12)+1))
    for i=self.top,#lines do c:text(6,6+(i-self.top)*12,lines[i],i==1 and P.accent or P.textSecondary) end
    button(self,c,5,c.h-22,94,"F5: RESCAN",function() rescan() end)
end
register("diagnostics","Diagnostics","DG",394,258,Diagnostics)

-- Desktop, window decorations and overlays.
local function shortText(value,limit)
    value=ascii(value); if #value<=limit then return value end
    return value:sub(1,max(1,limit-1)).."~"
end
local DESKTOP_LABELS={
    peripherals={"Peripheral","Manager"},network={"Network","Manager"},taskmgr={"Task","Manager"},radar={"Player","Radar"},
    image={"Image","Viewer"},resource={"Resource","Monitor"},server={"Server","Monitor"},system={"System","Monitor"},
    currency={"Currency","Calculator"},inventory={"Inventory","Viewer"},diagnostics={"Diagnostics"},performance={"Performance"},updates={"Update","Recovery"}
}
local function desktopLabel(def,rich)
    local id=def and (def.id or def.iconId); local parts=DESKTOP_LABELS[id]
    if parts then
        local out={}; for i,v in ipairs(parts) do out[#out+1]=rich and v or shortText(v,9) end; return out
    end
    local name=ascii(def and def.name or "App"); if not rich then return {shortText(name,9)} end
    local first,second=name:match("^(%S+)%s+(.+)$")
    if first and second and #first<=12 and #second<=12 then return {first,second} end
    return {shortText(name,13)}
end
iconIsOffline=function(id)
    if id=="radar" then return not devices.detector end
    if id=="network" then return #devices.modems==0 end
    if id=="peripherals" then return #devices.list==0 end
    return false
end
local function iconRects()
    local out={}; local areaH=max(1,Driver.h-TASK); local rich=cfg.showRichIcons and Driver.w>=300 and Driver.h>=210
    local rows,columns,cellW,cellH
    if rich then
        rows=max(1,min(5,floor((areaH-12)/58))); columns=max(1,math.ceil(#OS.order/rows)); cellW=max(1,floor((Driver.w-8)/columns)); cellH=max(48,floor((areaH-8)/rows))
    else
        columns=max(1,min(5,floor((Driver.w-8)/42))); rows=max(1,math.ceil(#OS.order/columns)); cellW=max(1,floor((Driver.w-8)/columns)); cellH=max(28,floor((areaH-8)/rows))
    end
    for i,id in ipairs(OS.order) do
        local col=(i-1)%columns; local row=floor((i-1)/columns); local r=box(4+col*cellW,6+row*cellH,max(12,cellW-2),max(22,cellH-2)); r.rich=rich; out[#out+1]={id=id,r=r}
    end
    return out
end
local function buildDesktop()
    local list={}; local c=canvas(list,0,0,Driver.w,Driver.h-TASK)
    c:clear(P.desktopBackground)
    local wallpaper=wallpaperCommands()
    if wallpaper then for _,cmd in ipairs(wallpaper) do list[#list+1]=cmd end end
    for i,item in ipairs(iconRects()) do
        local def=OS.registry[item.id]; local r=item.r
        local selected=OS.active==nil and i==OS.iconIndex; local hovered=OS.desktopHover==i; local running=false; local failed=false
        for _,w in ipairs(OS.windows) do if w.id==item.id and not w.minimized then running=true end; if w.id==item.id and w.crash then failed=true end end
        local state=failed and "error" or (selected and "selected" or (hovered and "hover" or (running and "running" or (iconIsOffline(item.id) and "offline" or "normal"))))
        if selected then c:filledRectangle(r.x+1,r.y+1,r.w-2,r.h-2,P.panelBackground); c:rectangle(r.x,r.y,r.w,r.h,P.accent) elseif hovered then c:rectangle(r.x,r.y,r.w,r.h,P.border) end
        local iconSize=r.rich and min(32,max(28,min(r.w-8,32))) or min(18,max(14,min(r.w-8,18))); local ix=r.x+floor((r.w-iconSize)/2); drawAppIcon(c,def,ix,r.y+2,iconSize,state)
        if running and not failed then c:filledRectangle(ix+iconSize-5,r.y+4,3,3,P.accent) end
        local labels=desktopLabel(def,r.rich); local ly=r.rich and r.y+35 or r.y+iconSize+5; local lh=#labels*10+2; if r.w>22 then c:filledRectangle(r.x+2,ly-1,r.w-4,lh,P.desktopBackground) end
        for n,label in ipairs(labels) do local clipped=shortText(label,max(3,floor((r.w-6)/6))); c:text(r.x+max(2,floor((r.w-Driver.measure(clipped))/2)),ly+(n-1)*10,clipped,selected and P.textPrimary or (hovered and P.textPrimary or P.textSecondary)) end
    end
    if Driver.w>=450 then
        c:text(Driver.w-170,Driver.h-TASK-31,HCC_VERSION_LABEL.." / CENTRAL LAB",P.border)
        c:text(Driver.w-150,Driver.h-TASK-17,"F1 MENU   F6 TILE",P.border)
    end
    OS.desktop=list; OS.desktopDirty=false
end
local function taskRects()
    local out={}; local available=Driver.w-110
    local width=max(12,min(88,floor(available/max(1,#OS.windows))))
    for i,w in ipairs(OS.windows) do out[#out+1]={win=w,r=box(43+(i-1)*width,Driver.h-TASK+2,width-2,TASK-4)} end
    return out
end
local function buildTask()
    local list={}; local c=canvas(list,0,0,Driver.w,Driver.h)
    c:filledRectangle(0,Driver.h-TASK,Driver.w,TASK,P.panelBackground)
    c:line(0,Driver.h-TASK,Driver.w-1,Driver.h-TASK,P.border)
    c:text(8,Driver.h-TASK+6,"HCC",P.accent)
    for _,item in ipairs(taskRects()) do
        local r,w=item.r,item.win
        local state=w.crash and "error" or (w==OS.active and not w.minimized and "selected" or (iconIsOffline(w.id) and "offline" or "normal"))
        if w==OS.active and not w.minimized then c:filledRectangle(r.x,r.y,r.w,r.h,P.border) end
        if cfg.showRichIcons and r.w>=18 then drawAppIcon(c,w.app,r.x+2,r.y+1,min(16,r.h-2),state) end
        if cfg.taskbarLabels and r.w>=44 then
            local tx=r.x+(cfg.showRichIcons and 21 or 3)
            c:clipping(tx,r.y+4,r.x+r.w-tx-3,10):text(0,0,shortText(w.name,12),w.minimized and P.textSecondary or P.textPrimary)
        end
        if not w.minimized then c:line(r.x,r.y+r.h-1,r.x+r.w-1,r.y+r.h-1,P.accent) end
    end
    c:filledRectangle(Driver.w-92,Driver.h-TASK+2,92,TASK-3,P.panelBackground)
    c:text(Driver.w-88,Driver.h-TASK+3,HCC_VERSION,P.accent)
    c:text(Driver.w-60,Driver.h-TASK+6,timeText(jst()),P.textPrimary)
    OS.task=list; OS.taskDirty=false
end
local function buildWindow(win)
    local list={}; local c=canvas(list,win.x,win.y,win.w,win.h)
    c:clear(P.windowBackground)
    c:filledRectangle(0,0,win.w,TITLE,OS.active==win and P.panelBackground or P.windowBackground)
    c:rectangle(0,0,win.w,win.h,OS.active==win and P.accent or P.border)
    local titleX=6
    if win.w>=110 then drawAppIcon(c,win.app,6,1,14,win.crash and "error" or (OS.active==win and "selected" or "normal")); titleX=24 end
    c:clipping(titleX,5,max(10,win.w-titleX-66),10):text(0,0,win.name,OS.active==win and P.textPrimary or P.textSecondary)
    c:text(win.w-51,5,"_",P.textSecondary); c:text(win.w-34,5,"+",P.accent); c:text(win.w-17,5,"X",P.error)
    win.buttons={}
    local client=c:clipping(1,TITLE,win.w-2,win.h-TITLE-1)
    if not win.crash then
        local prefix=#list; appCall(win,"draw",client)
        if win.crash then for i=#list,prefix+1,-1 do list[i]=nil end end
    end
    if win.crash then client:paragraph(8,8,"Application error: "..win.crash,P.error,client.w-16,12) end
    c:line(win.w-7,win.h-3,win.w-3,win.h-7,P.border)
    win.commands=list; win.dirty=false
end
local function menuBox()
    local h=min(184,Driver.h-TASK-6)
    return box(3,Driver.h-TASK-h-3,min(175,Driver.w-6),h)
end
local function dialogBox()
    local w=min(370,Driver.w-8); local h=min(140,Driver.h-TASK-4)
    return box((Driver.w-w)/2,(Driver.h-TASK-h)/2,w,h)
end
local function buildOverlay()
    local list={}; local c=canvas(list,0,0,Driver.w,Driver.h)
    if OS.menu then
        local r=menuBox(); local m=c:clipping(r.x,r.y,r.w,r.h)
        m:clear(P.windowBackground); m:rectangle(0,0,r.w,r.h,P.accent)
        local visible=max(1,floor((r.h-4)/20))
        OS.menuTop=clamp(OS.menuIndex-visible+1,1,max(1,#OS.order+2-visible))
        for i=OS.menuTop,min(#OS.order+1,OS.menuTop+visible-1) do
            local y=3+(i-OS.menuTop)*20
            if i==OS.menuIndex then m:filledRectangle(2,y,r.w-4,19,P.panelBackground) end
            if i<=#OS.order then
                local def=OS.registry[OS.order[i]]; local state=i==OS.menuIndex and "selected" or "normal"; local bad=false; local live=false
                for _,w in ipairs(OS.windows) do if w.id==OS.order[i] and w.crash then bad=true elseif w.id==OS.order[i] and not w.minimized then live=true end end
                state=bad and "error" or (i==OS.menuIndex and "selected" or (live and "running" or (iconIsOffline(def.id) and "offline" or "normal"))); drawAppIcon(m,def,5,y+1,min(18,max(12,r.w-30)),state)
                m:clipping(28,y+4,max(10,r.w-32),10):text(0,0,shortText(def.name,20),P.textPrimary)
            else m:text(9,y+5,"Exit HCC OS",P.warning) end
        end
    end
    if OS.context then
        local cw=min(150,Driver.w-6); local ch=58; local cx=clamp(OS.context.x,3,Driver.w-cw-3); local cy=clamp(OS.context.y,3,Driver.h-TASK-ch-3); local q=c:clipping(cx,cy,cw,ch); OS.context.rect=box(cx,cy,cw,ch)
        q:clear(P.windowBackground); q:rectangle(0,0,cw,ch,P.accent); q:text(8,7,"OPEN",P.textPrimary); q:text(8,25,"REFRESH DESKTOP",P.textPrimary); q:text(8,43,"CANCEL",P.warning)
    end
    if OS.toast then
        local width=min(300,Driver.w-8); local r=box(Driver.w-width-4,Driver.h-TASK-47,width,41)
        local t=c:clipping(r.x,r.y,r.w,r.h)
        t:clear(P.panelBackground); t:rectangle(0,0,r.w,r.h,OS.toast.color)
        t:paragraph(7,6,OS.toast.message,P.textPrimary,width-14,2)
    end
    if OS.modal then
        local m=OS.modal; local r=dialogBox(); m.rect=r
        local d=c:clipping(r.x,r.y,r.w,r.h)
        d:clear(P.windowBackground); d:rectangle(0,0,r.w,r.h,P.accent)
        d:filledRectangle(1,1,r.w-2,19,P.panelBackground); d:text(8,6,m.title,P.accent)
        d:paragraph(8,27,m.message,P.textPrimary,r.w-16,m.input~=nil and 2 or 5)
        if m.input~=nil then
            local iy=r.h-55
            d:filledRectangle(7,iy,r.w-14,20,P.panelBackground); d:rectangle(7,iy,r.w-14,20,P.accent)
            local visible=m.input:gsub("[\r\n]"," "); local first=1
            while Driver.measure(visible:sub(first,m.pos))+2>r.w-24 and first<=m.pos do first=first+1 end
            local field=d:clipping(11,iy+5,r.w-22,10)
            field:text(0,0,visible:sub(first),P.textPrimary)
            local px=Driver.measure(visible:sub(first,m.pos)); field:line(px,0,px,8,P.accent)
        end
        m.hits={}; local bw=min(70,floor((r.w-18)/#m.buttons))
        for i,label in ipairs(m.buttons) do
            local b=box(r.w-8-(#m.buttons-i+1)*bw,r.h-26,bw-4,18)
            d:filledRectangle(b.x,b.y,b.w,b.h,i==m.index and P.border or P.panelBackground)
            d:text(b.x+6,b.y+5,label,P.textPrimary); m.hits[i]=b
        end
    end
    OS.overlay=list; OS.overlayDirty=false
    for _,cmd in ipairs(list) do invalidate(cmd.bounds) end
end
local function layers()
    local result={OS.desktop}
    for _,w in ipairs(OS.windows) do if not w.minimized then result[#result+1]=w.commands end end
    result[#result+1]=OS.task; result[#result+1]=OS.overlay
    return result
end
local function cursorRect() return box(OS.pointer.x,OS.pointer.y,9,13) end
local function render()
    if not gpu then return end
    if OS.desktopDirty then buildDesktop() end
    if OS.taskDirty then buildTask() end
    for _,w in ipairs(OS.windows) do if w.dirty and not w.minimized then buildWindow(w) end end
    if OS.overlayDirty then buildOverlay() end
    if #OS.damage==0 then return end
    local scene=layers(); local damage=OS.damage; OS.damage={}
    -- Whole text runs must be replayed. Expand damage until all intersected
    -- text fits; this prevents trails when a cursor crosses native glyphs.
    local pending=damage; damage={}
    while #pending>0 do
        local r=table.remove(pending)
        local changed=true
        while changed do
            changed=false
            for _,list in ipairs(scene) do for _,cmd in ipairs(list) do
                if cmd.kind=="text" and intersect(r,cmd.bounds) then
                    local u=union(r,cmd.bounds)
                    if u.x~=r.x or u.y~=r.y or u.w~=r.w or u.h~=r.h then r=u; changed=true end
                end
            end end
            for i=#pending,1,-1 do
                if intersect(r,pending[i]) then r=union(r,table.remove(pending,i)); changed=true end
            end
            for i=#damage,1,-1 do
                if intersect(r,damage[i]) then r=union(r,table.remove(damage,i)); changed=true end
            end
        end
        damage[#damage+1]=r
    end
    for _,r in ipairs(damage) do
        for _,list in ipairs(scene) do for _,cmd in ipairs(list) do
            if intersect(r,cmd.bounds) then
                if cmd.kind=="fill" then local b=cmd.bounds; Driver.filledRectangle(b.x,b.y,b.w,b.h,cmd.color,r)
                elseif cmd.kind=="line" then Driver.line(cmd.a,cmd.b,cmd.c,cmd.d,cmd.color,r)
                elseif cmd.kind=="text" then Driver.text(cmd) end
            end
        end end
        if OS.pointer.visible and intersect(r,cursorRect()) then
            local x,y=OS.pointer.x,OS.pointer.y
            for i=0,9 do Driver.line(x,y+i,x+floor(i/2),y+i,P.textPrimary,r) end
            Driver.line(x,y,x,y+11,0xFF000000,r); Driver.line(x,y,x+6,y+10,0xFF000000,r)
            Driver.line(x+3,y+8,x+6,y+12,P.textPrimary,r)
        end
    end
    Driver.sync(); OS.renderCount=OS.renderCount+1
end
local function tileWindows()
    local visible={}; for _,w in ipairs(OS.windows) do if not w.minimized then visible[#visible+1]=w end end
    local n=#visible; if n==0 then return end
    local columns=1
    if n>1 then columns=math.ceil(math.sqrt(n)) end
    columns=min(columns,max(1,floor(Driver.w/220)),n)
    if columns<1 then columns=1 end
    local rows=math.ceil(n/columns); local areaH=Driver.h-TASK; local gap=4
    for i,w in ipairs(visible) do
        invalidate(w); local col=(i-1)%columns; local row=floor((i-1)/columns)
        local cellW=floor(Driver.w/columns); local cellH=floor(areaH/rows)
        w.restore=nil; w.minimized=false; w.x=col*cellW+gap; w.y=row*cellH+gap
        w.w=cellW-gap*2; w.h=cellH-gap*2; fit(w); mark(w)
    end
    OS.active=visible[#visible]; taskDirty()
end
rescan=function()
    local ok=scanDevices()
    OS.pointer.x=clamp(OS.pointer.x,0,Driver.w-1); OS.pointer.y=clamp(OS.pointer.y,0,Driver.h-1)
    OS.drag=nil; OS.held={}
    for _,w in ipairs(OS.windows) do
        if w.restore then w.restore=nil; w.x=0; w.y=0; w.w=Driver.w; w.h=Driver.h-TASK end
        appCall(w,"resume"); w.nextUpdate=now()
    end
    allDirty()
    notify(ok and "Peripherals rescanned" or "GPU unavailable; reconnect and press F5",ok and P.success or P.warning)
    if not ok then print("[HCC OS] GPU unavailable: "..(Driver.error or "not found")) end
end

local function setMenu(value)
    overlayDirty(); OS.menu=value; OS.drag=nil
end
local function desktopFocus()
    local old=OS.active; OS.active=nil; mark(old); taskDirty(); OS.desktopDirty=true; invalidate(screen())
end
local function snapWindow(win)
    if not cfg.snapEnabled or not win or win.restore then return end
    local d=cfg.snapDistance; local bottom=Driver.h-TASK
    if math.abs(win.x)<d then win.x=0 end
    if math.abs(win.y)<d then win.y=0 end
    if math.abs(win.x+win.w-Driver.w)<d then win.x=Driver.w-win.w end
    if math.abs(win.y+win.h-bottom)<d then win.y=bottom-win.h end
    for _,other in ipairs(OS.windows) do
        if other~=win and not other.minimized then
            if math.abs(win.x-(other.x+other.w))<d then win.x=other.x+other.w end
            if math.abs(win.x+win.w-other.x)<d then win.x=other.x-win.w end
            if math.abs(win.y-(other.y+other.h))<d then win.y=other.y+other.h end
            if math.abs(win.y+win.h-other.y)<d then win.y=other.y-win.h end
        end
    end
    fit(win)
end
local function resizeEdges(win,xx,yy)
    local margin=6
    return {left=xx<=margin,right=xx>=win.w-margin-1,top=yy>=TITLE and yy<=TITLE+margin,
        bottom=yy>=win.h-margin-1}
end
local function updateHover(x,y)
    local old=OS.hover; local oldDesktop=OS.desktopHover; local hovered=nil; local hit=nil
    for i=#OS.windows,1,-1 do
        local w=OS.windows[i]
        if not w.minimized and inside(w,x,y) then
            hovered=w; local xx,yy=x-w.x-1,y-w.y-TITLE
            if yy>=0 then for _,b in ipairs(w.buttons or {}) do if inside(b,xx,yy) then hit=b; break end end end
            break
        end
    end
    local same=old and old.win==hovered and ((old.hit==nil and hit==nil) or (old.hit and hit and old.hit.x==hit.x and old.hit.y==hit.y))
    if not same and old and old.win then mark(old.win) end
    OS.hover=hovered and {win=hovered,hit=hit} or nil
    if not same and OS.hover and OS.hover.win then mark(OS.hover.win) end
    local desktopIndex=nil
    if not hovered then for i,item in ipairs(iconRects()) do if inside(item.r,x,y) then desktopIndex=i; break end end end
    OS.desktopHover=desktopIndex
    if oldDesktop~=desktopIndex then
        OS.desktopDirty=true
        local rects=iconRects(); if oldDesktop and rects[oldDesktop] then invalidate(rects[oldDesktop].r) end; if desktopIndex and rects[desktopIndex] then invalidate(rects[desktopIndex].r) end
    end
end
local function pointer(kind,x,y,buttonId)
    if not finite(x) or not finite(y) then return end
    if OS.pointer.visible then invalidate(cursorRect()) end
    OS.pointer.x=floor(clamp(x,0,Driver.w-1)); OS.pointer.y=floor(clamp(y,0,Driver.h-1))
    OS.pointer.visible=kind~="exit"; if OS.pointer.visible then invalidate(cursorRect()); updateHover(OS.pointer.x,OS.pointer.y) end
    x,y=OS.pointer.x,OS.pointer.y
    if kind=="click" or kind=="down" then OS.mouseButtons[buttonId or 1]=true elseif kind=="up" then OS.mouseButtons[buttonId or 1]=nil end
    if kind=="exit" then return end
    if kind=="up" then
        if OS.drag then snapWindow(OS.drag.win); mark(OS.drag.win); taskDirty() end
        OS.drag=nil; return
    end
    if OS.modal then
        if kind=="click" and buttonId==1 then
            local m=OS.modal; local r=m.rect or dialogBox()
            for i,b in ipairs(m.hits or {}) do if inside(b,x-r.x,y-r.y) then dismiss(m.buttons[i]); break end end
        end
        return
    end
    if kind=="drag" and OS.drag then
        local d=OS.drag; local w=d.win; invalidate(w)
        if d.resize then
            local right=d.right; local bottom=d.bottom
            if d.left then w.x=x-d.offsetX; w.w=right-w.x end
            if d.rightEdge then w.w=d.startW+x-d.startX end
            if d.top then w.y=y-d.offsetY; w.h=bottom-w.y end
            if d.bottomEdge then w.h=d.startH+y-d.startY end
        else w.x=x-d.dx; w.y=y-d.dy end
        fit(w); mark(w); return
    end
    if kind~="click" and kind~="scroll" then return end
    if kind=="click" and buttonId~=1 and buttonId~=2 then return end
    if kind=="click" and buttonId==2 then
        local overWindow=false; for _,w in ipairs(OS.windows) do if not w.minimized and inside(w,x,y) then overWindow=true; break end end
        if not overWindow and y<Driver.h-TASK then
            local selected=nil; for i,item in ipairs(iconRects()) do if inside(item.r,x,y) then selected={index=i,id=item.id}; break end end
            if selected then OS.iconIndex=selected.index; OS.context={x=x,y=y,id=selected.id}; OS.menu=false; overlayDirty() else OS.context=nil; overlayDirty() end
        end
        return
    end
    if OS.context then
        local r=OS.context.rect
        if kind=="click" and r and inside(r,x,y) then
            local row=floor((y-r.y)/18); local id=OS.context.id; OS.context=nil; overlayDirty()
            if row==0 then openApp(id) elseif row==1 then allDirty() end
            return
        elseif kind=="click" then OS.context=nil; overlayDirty() end
    end
    if OS.menu then
        local r=menuBox()
        if inside(r,x,y) then
            local index=floor((y-r.y-3)/20)+(OS.menuTop or 1)
            if index>=1 and index<=#OS.order+1 and kind=="click" then
                setMenu(false); if index>#OS.order then requestExit() else openApp(OS.order[index]) end
            end
            return
        else setMenu(false) end
    end
    if y>=Driver.h-TASK then
        if kind~="click" then return end
        if x<40 then setMenu(not OS.menu); return end
        if x>=Driver.w-92 then openApp("clock"); return end
        for _,item in ipairs(taskRects()) do if inside(item.r,x,y) then
            local w=item.win
            if w==OS.active and not w.minimized then invalidate(w); w.minimized=true; OS.active=nil; taskDirty(); OS.desktopDirty=true; invalidate(box(0,0,Driver.w,Driver.h-TASK))
            else focus(w) end; return
        end end
        return
    end
    for i=#OS.windows,1,-1 do
        local w=OS.windows[i]
        if not w.minimized and inside(w,x,y) then
            if kind=="click" then focus(w) end
            local xx,yy=x-w.x,y-w.y
            if yy<TITLE and kind=="click" then
                if xx>=w.w-21 then closeWindow(w)
                elseif xx>=w.w-39 then maximize(w)
                elseif xx>=w.w-57 then invalidate(w); w.minimized=true; OS.active=nil; taskDirty(); OS.desktopDirty=true; invalidate(box(0,0,Driver.w,Driver.h-TASK))
                elseif not w.restore then
                    local t=now(); local double=w.lastTitleClick and t-w.lastTitleClick<0.4
                    w.lastTitleClick=t
                    if double then maximize(w) else OS.drag={win=w,dx=xx,dy=yy} end
                end
            elseif kind=="click" and not w.restore then
                local edge=resizeEdges(w,xx,yy)
                if edge.left or edge.right or edge.top or edge.bottom then
                    OS.drag={win=w,resize=true,x=x,y=y,startX=x,startY=y,startW=w.w,startH=w.h,
                        right=w.x+w.w,bottom=w.y+w.h,offsetX=x-w.x,offsetY=y-w.y,
                        left=edge.left,top=edge.top,rightEdge=edge.right,bottomEdge=edge.bottom}
                else
                    xx,yy=xx-1,yy-TITLE
                    if kind=="click" then for _,b in ipairs(w.buttons) do if inside(b,xx,yy) then
                        local ok,e=pcall(b.action); if not ok then errorBox(e) end; return
                    end end end
                    appCall(w,"onMouse",kind,xx,yy,buttonId)
                end
            else
                xx,yy=xx-1,yy-TITLE
                if kind=="click" then for _,b in ipairs(w.buttons) do if inside(b,xx,yy) then
                    local ok,e=pcall(b.action); if not ok then errorBox(e) end; return
                end end end
                appCall(w,"onMouse",kind,xx,yy,buttonId)
            end
            return
        end
    end
    if kind=="click" then
        desktopFocus()
        for i,item in ipairs(iconRects()) do if inside(item.r,x,y) then
            local double=OS.iconIndex==i and OS.lastIconClick and now()-OS.lastIconClick<0.45
            OS.iconIndex=i; OS.lastIconClick=now(); OS.desktopDirty=true; invalidate(item.r)
            if double then openApp(item.id) end; break
        end end
    end
end
local function modalKey(k)
    local m=OS.modal
    if k==keys.escape then dismiss("Cancel")
    elseif k==keys.enter then dismiss(m.buttons[m.index])
    elseif k==keys.tab then m.index=m.index%#m.buttons+1; overlayDirty()
    elseif m.input~=nil then
        if k==keys.left then m.pos=max(0,m.pos-1)
        elseif k==keys.right then m.pos=min(#m.input,m.pos+1)
        elseif k==keys.home then m.pos=0
        elseif k==keys["end"] then m.pos=#m.input
        elseif k==keys.backspace and m.pos>0 then m.input=m.input:sub(1,m.pos-1)..m.input:sub(m.pos+1); m.pos=m.pos-1
        elseif k==keys.delete then m.input=m.input:sub(1,m.pos)..m.input:sub(m.pos+2) end
        overlayDirty()
    elseif k==keys.left or k==keys.right then m.index=(m.index-1+(k==keys.left and -1 or 1))%#m.buttons+1; overlayDirty() end
end
local function keyInput(k)
    OS.held[k]=true
    if OS.modal then modalKey(k); return end
    local ctrl=OS.held[keys.leftCtrl] or OS.held[keys.rightCtrl]
    local alt=OS.held[keys.leftAlt] or OS.held[keys.rightAlt]
    if k==keys.f1 then setMenu(not OS.menu); return end
    if OS.menu then
        if k==keys.escape then setMenu(false)
        elseif k==keys.up then OS.menuIndex=(OS.menuIndex-2)%(#OS.order+1)+1; overlayDirty()
        elseif k==keys.down then OS.menuIndex=OS.menuIndex%(#OS.order+1)+1; overlayDirty()
        elseif k==keys.enter then local i=OS.menuIndex; setMenu(false); if i>#OS.order then requestExit() else openApp(OS.order[i]) end end
        return
    end
    if ctrl and k==keys.q then requestExit(); return end
    if ctrl and k==keys.w then closeWindow(OS.active); return end
    if ctrl and k==keys.tab then
        if #OS.windows>0 then focus(OS.windows[1]) end; return
    end
    if k==keys.f5 and not gpu then rescan(); return end
    if k==keys.f6 then tileWindows(); return end
    if k==keys.f5 and not OS.active then rescan(); return end
    local w=OS.active
    if w then
        if k==keys.f2 then invalidate(w); w.minimized=true; OS.active=nil; taskDirty(); OS.desktopDirty=true; invalidate(box(0,0,Driver.w,Driver.h-TASK)); return end
        if k==keys.f3 then maximize(w); return end
        if alt and (k==keys.left or k==keys.right or k==keys.up or k==keys.down) then
            invalidate(w); w.restore=nil
            if k==keys.left then w.x=w.x-8 elseif k==keys.right then w.x=w.x+8 elseif k==keys.up then w.y=w.y-8 else w.y=w.y+8 end
            fit(w); mark(w); return
        end
        if k==keys.escape then desktopFocus(); return end
        appCall(w,"onKey",k)
    else
        if k==keys.enter then openApp(OS.order[OS.iconIndex])
        elseif k==keys.t then openApp("server")
        elseif k==keys.c then openApp("calendar")
        elseif k==keys.e then openApp("clock")
        elseif k==keys.up or k==keys.left then OS.iconIndex=(OS.iconIndex-2)%#OS.order+1; OS.desktopDirty=true; invalidate(screen())
        elseif k==keys.down or k==keys.right or k==keys.tab then OS.iconIndex=OS.iconIndex%#OS.order+1; OS.desktopDirty=true; invalidate(screen()) end
    end
end
local function charInput(s)
    if type(s)~="string" then return end
    if OS.modal then
        local m=OS.modal
        if m.input~=nil then
            s=s:gsub("[^\010\013\032-\126]","?")
            if #m.input+#s>8192 then return end
            m.input=m.input:sub(1,m.pos)..s..m.input:sub(m.pos+1); m.pos=m.pos+#s; m.index=1; overlayDirty()
        end
    elseif not OS.menu and OS.active and not (OS.held[keys.leftCtrl] or OS.held[keys.rightCtrl] or OS.held[keys.leftAlt] or OS.held[keys.rightAlt]) then
        appCall(OS.active,"onChar",s)
    end
end
local function handleEvent(e)
    local name=e[1]
    if (name=="http_success" or name=="http_failure") and _G.HCCV14 and type(_G.HCCV14.handleHttp)=="function" then
        local handled=_G.HCCV14.handleHttp(e[2],e[3])
        if handled then return end
    end
    local prefixed=false
    if name:sub(1,12)=="tm_keyboard_" then
        if not devices.keyboards[e[2]] then return end
        name=name:sub(13); table.remove(e,2); e[1]=name; prefixed=true
    end
    if name=="http_success" or name=="http_failure" then
        for _,w in ipairs(OS.windows) do
            if w.id=="web" and not w.minimized and not w.crash then
                if name=="http_success" then appCall(w,"onHttpSuccess",e[2],e[3]) else appCall(w,"onHttpFailure",e[2],e[3]) end
                break
            end
        end
    elseif name=="terminate" then requestExit()
    elseif name=="key" then keyInput(e[2])
    elseif name=="key_up" then OS.held[e[2]]=nil
    elseif name=="char" or name=="paste" then charInput(e[2])
    elseif name=="portable_disconnect" then OS.held={}; OS.mouseButtons={}; OS.drag=nil; OS.hover=nil
    elseif name=="peripheral" or name=="peripheral_detach" then
        notify(name=="peripheral" and "Peripheral attached" or "Peripheral detached",P.warning); rescan()
    elseif name=="monitor_resize" then rescan()
    elseif name:sub(1,11)=="tm_monitor_" then
        local offset=0
        -- 1.3.1 prefixes attachment name; old releases sent x,y directly.
        if type(e[2])=="string" then if e[2]~=devices.gpuName then return end; offset=1 end
        local x,y,b=e[2+offset],e[3+offset],e[4+offset]
        if not finite(x) or not finite(y) then return end
        local kind=name:sub(12):gsub("^mouse_","")
        if kind=="touch" then kind="click"; b=1 end
        pointer(kind,x-1,y-1,b or 1)
    elseif name=="mouse_move" or name=="mouse_drag" or name=="mouse_click" or name=="mouse_up" or name=="mouse_scroll" then
        -- Some portable keyboards forward unprefixed mouse events.  They use
        -- monitor-style x,y,button arguments after the event name.
        local kind=name:gsub("^mouse_",""); if kind=="scroll" then kind="scroll" end
        local x,y,b
        if prefixed then x,y,b=e[2],e[3],e[4] else b,x,y=e[2],e[3],e[4] end
        if finite(x) and finite(y) then pointer(kind,x-1,y-1,b or 1) end
    end
end

local function boot()
    print("[HCC OS] Detecting Tom's GPU, keyboard and Player Detector...")
    local good=scanDevices()
    if not good then
        print("[HCC OS] "..(Driver.error or "tm_gpu not found"))
        print("Connect GPU + Bitmap Monitors. Press F5 to retry, Ctrl+T to exit.")
        while not good do
            local e={os.pullEventRaw()}
            if e[1]=="terminate" then return false end
            if e[1]=="peripheral" or (e[1]=="key" and e[2]==keys.f5) then good=scanDevices() end
        end
    end
    Driver.clear(0xFF000000)
    local list={}; local c=canvas(list,0,0,Driver.w,Driver.h)
    local x=max(4,floor((Driver.w-220)/2)); local y=max(4,floor((Driver.h-120)/2))
    c:text(x,y,HCC_VERSION_LABEL,P.accent,2)
    local lines={"CPU: "..HCC_CPU,"GPU OK: "..devices.gpuName,string.format("DISPLAY %dx%d",Driver.w,Driver.h),
        devices.detector and "PLAYER DETECTOR OK" or "PLAYER DETECTOR UNAVAILABLE",
        next(devices.keyboards) and "INPUT OK" or "INPUT: COMPUTER KEYBOARD",
        "STARTING DESKTOP..."}
    for i,line in ipairs(lines) do c:text(x,y+30+(i-1)*14,line,P.textPrimary) end
    for _,cmd in ipairs(list) do Driver.text(cmd) end
    Driver.sync(); sleep(0.25)
    if not fs.exists(configPath) then local ok,err=saveConfig(); if not ok then configWarning=tostring(err) end end
    if not fs.exists(currencyPath) then local ok,err=currencySave(); if not ok then currencyWarning=tostring(err) end end
    allDirty()
    if _G.HCCV14 and _G.HCCV14.autoUpdatePending then openApp("updates") end
    if configWarning then notify(configWarning,P.warning)
    else notify("HCC OS ready / F1 menu / double-click an icon",P.accent) end
    return true
end
local function run()
    if not boot() then return end
    local timer,timerAt; local taskSecond=-1; local metricsAt=now(); local lastR,lastS=OS.renderCount,Driver.syncs
    while OS.running do
        local t=now(); local deadline=t+1
        if floor(t)~=taskSecond then
            taskSecond=floor(t); OS.taskDirty=true
            invalidate(box(Driver.w-92,Driver.h-TASK,92,TASK))
        end
        for _,w in ipairs(OS.windows) do
            if w.minimized or w.crash or w.nextUpdate then
                if w.timer then os.cancelTimer(w.timer); OS.appTimers[w.timer]=nil; w.timer=nil end
                w.nextUpdate=nil
            end
            if not w.minimized and not w.crash and w.app.update then
                if not w.timer then
                    local interval=appCall(w,"interval") or 1
                    -- Use an independent CC timer, not a wall-clock deadline.
                    -- At 10 TPS a 2-second (40-tick) timer takes ~4 real seconds.
                    -- Rescheduling fractions of a wall-clock deadline would hide lag.
                    interval=max(0.05,interval)
                    w.timer=os.startTimer(interval); OS.appTimers[w.timer]=w
                end
            end
        end
        if OS.toast then
            if t>=OS.toast.untilTime then overlayDirty(); OS.toast=nil else deadline=min(deadline,OS.toast.untilTime) end
        end
        if t-metricsAt>=1 then
            OS.renderRate=(OS.renderCount-lastR)/(t-metricsAt); OS.syncRate=(Driver.syncs-lastS)/(t-metricsAt)
            lastR,lastS,metricsAt=OS.renderCount,Driver.syncs,t
        end
        if gpu and (#OS.damage>0 or OS.overlayDirty) and not OS.frameTimer then OS.frameTimer=os.startTimer(0.05) end
        if not timer or math.abs(deadline-(timerAt or 0))>0.02 then
            if timer then os.cancelTimer(timer) end
            timerAt=deadline; timer=os.startTimer(max(0.05,deadline-t))
        end
        local e={os.pullEventRaw()}
        if e[1]=="timer" and e[2]==OS.frameTimer then OS.frameTimer=nil; render()
        elseif e[1]=="timer" and OS.appTimers[e[2]] then
            local w=OS.appTimers[e[2]]; OS.appTimers[e[2]]=nil; w.timer=nil
            if not w.minimized and not w.crash then
                local updatedAt=now(); appCall(w,"update",w.lastUpdate and updatedAt-w.lastUpdate or 0); w.lastUpdate=updatedAt
            end
        elseif e[1]=="timer" and e[2]==timer then timer=nil
        else handleEvent(e) end
        if Driver.error and not gpu and not OS.reportedGpuError then
            OS.reportedGpuError=true; print("[HCC OS] GPU: "..Driver.error.."; reconnect or F5")
        elseif gpu then OS.reportedGpuError=false end
    end
    if timer then os.cancelTimer(timer) end
    if OS.frameTimer then os.cancelTimer(OS.frameTimer) end
    for id in pairs(OS.appTimers) do os.cancelTimer(id) end
end

-- v1.4 services are injected at the compatibility boundary. The legacy
-- desktop keeps ownership of GPU, input, windows, icons and all existing apps.
if _G.HCCV14 and type(_G.HCCV14.attachLegacy)=="function" then
    pcall(_G.HCCV14.attachLegacy,{OS=OS,Driver=Driver,mark=mark,button=button,
        palette=P,openApp=openApp,notify=notify,errorBox=errorBox})
end

local ok,err=pcall(run)
for _,w in ipairs(OS.windows) do appCall(w,"close") end
local saved,saveError=saveConfig()
if not saved then print("[HCC OS] Settings not saved: "..tostring(saveError)) end
local currencySaved,currencyError=currencySave()
if not currencySaved then print("[HCC OS] Currency data not saved: "..tostring(currencyError)) end
if gpu then Driver.clear(0xFF000000); Driver.sync() end
if not ok then printError("[HCC OS] "..tostring(err)) else print("[HCC OS] Returned to CraftOS.") end

return function(E)
 local env=setmetatable({},{__index=E})
 local _ENV=env
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
    if context and context.logger then
        local method=level=="ERROR" and context.logger.error or (level=="WARN" and context.logger.warn or context.logger.info)
        if type(method)=="function" then pcall(method,context.logger,ascii(message)) end
    end
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
    local args={...}
    local ok,result=xpcall(function() return f(win.app,unpack(args)) end,function(reason)
        if debug and debug.traceback then return debug.traceback(tostring(reason),2) end
        return tostring(reason)
    end)
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
    local safeInput
    if input~=nil then safeInput=tostring(input) end
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
    win.app=setmetatable({win=win,context=E.appContext},{__index=def})
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
E.OS=OS; E.TITLE=TITLE; E.TASK=TASK; E.logLine=logLine; E.screen=screen; E.invalidate=invalidate; E.mark=mark; E.taskDirty=taskDirty; E.overlayDirty=overlayDirty; E.notify=notify; E.appCall=appCall; E.focus=focus; E.fit=fit; E.allDirty=allDirty; E.dialog=dialog; E.dismiss=dismiss; E.removeWindow=removeWindow; E.closeWindow=closeWindow; E.maximize=maximize; E.openApp=openApp; E.register=register; E.button=button; E.errorBox=errorBox; E.requestExit=requestExit
E.clearLogs=function() OS.logs={} end
local readable={windows=true,active=true,held=true,logs=true,started=true,renderCount=true,renderRate=true,syncRate=true,pointer=true,order=true,registry=true}
E.AppOS=setmetatable({},{__index=function(_,key) if readable[key] then return OS[key] end end,__newindex=function() error("Application OS state is read-only",2) end})

end

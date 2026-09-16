-- HCC OS v1.5 window manager.
-- Windows are model objects. Rendering and input consume the same geometry,
-- which prevents the old title-bar/client-area drift.

return function(E)
    local env=setmetatable({},{__index=E})
    local _ENV=env
    local OS={windows={},damage={},registry={},order={},active=nil,modal=nil,toast=nil,
        menu=false,menuIndex=1,iconIndex=1,desktopPage=1,taskScroll=1,context=nil,
        pointer={x=0,y=0,visible=false,shape="arrow",lastMove=0},held={},running=true,
        desktopHover=nil,desktop={},task={},overlay={},desktopDirty=true,taskDirty=true,
        overlayDirty=true,started=now(),renderCount=0,renderRate=0,syncRate=0,
        frameTimer=nil,drag=nil,appTimers={},mouseButtons={},hover=nil,logs={},logSequence=0,
        nextWindowId=0}
    -- Windows 10 uses a clean desktop surface with a single bottom taskbar;
    -- windows still retain the compact title bar used by the app toolkit.
    local TITLE,TASK,TOP=24,30,0
    local function screen() return box(0,0,Driver.w,Driver.h) end
    local function workspace() return box(0,TOP,Driver.w,max(1,Driver.h-TASK-TOP)) end
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

    local function invalidate(r)
        r=intersect(r,screen()); if not r then return end
        local i=1
        while i<=#OS.damage do
            if intersect(r,OS.damage[i]) then r=union(r,table.remove(OS.damage,i)); i=1 else i=i+1 end
        end
        OS.damage[#OS.damage+1]=r
        if #OS.damage>40 then OS.damage={screen()} end
    end
    mark=function(win)
        if not win then return end
        win.dirty=true
        if not win.minimized then invalidate(win) end
    end
    local function taskDirty() OS.taskDirty=true; invalidate(box(0,Driver.h-TASK,Driver.w,TASK)) end
    local function overlayDirty()
        for _,cmd in ipairs(OS.overlay or {}) do if cmd.bounds then invalidate(cmd.bounds) end end
        OS.overlayDirty=true
    end
    local function notify(message,color)
        OS.toast={message=ascii(message),color=color or P.accent,untilTime=now()+4}
        overlayDirty(); logLine("INFO",message)
    end
    local function appCall(win,method,...)
        if not win or win.crash then return end
        local f=win.app and win.app[method]; if not f then return end
        local args={...}
        local ok,result=xpcall(function() return f(win.app,unpack(args)) end,function(reason)
            return debug and debug.traceback and debug.traceback(tostring(reason),2) or tostring(reason)
        end)
        if not ok then
            win.crash=ascii(result); mark(win); logLine("ERROR",win.name.."."..method..": "..win.crash)
            notify(win.name.." stopped",P.error); return nil
        end
        return result
    end
    local function focus(win)
        if not win then return end
        local previous=OS.active
        if win.minimized then appCall(win,"resume"); win.nextUpdate=nil end
        for i,w in ipairs(OS.windows) do if w==win then table.remove(OS.windows,i); break end end
        OS.windows[#OS.windows+1]=win; OS.active=win; win.minimized=false
        mark(previous); mark(win); taskDirty(); OS.desktopDirty=true; invalidate(workspace())
    end
    local function fit(win)
        local area=workspace(); local minW=min(win.minWidth or 170,area.w); local minH=min(win.minHeight or 100,area.h)
        win.w=floor(clamp(win.w,minW,area.w)); win.h=floor(clamp(win.h,minH,area.h))
        local visible=12
        win.x=floor(clamp(win.x,area.x-win.w+visible,area.x+area.w-visible))
        win.y=floor(clamp(win.y,area.y-TITLE+visible,area.y+area.h-visible))
    end
    local function allDirty()
        OS.desktopDirty=true; OS.taskDirty=true; OS.overlayDirty=true; OS.damage={screen()}
        for _,w in ipairs(OS.windows) do fit(w); w.dirty=true end
    end
    local function dialog(title,message,buttons,callback,input)
        OS.drag=nil; overlayDirty()
        local safeButtons=type(buttons)=="table" and buttons or {"OK"}
        local safeCallback=type(callback)=="function" and callback or nil
        local safeInput=input==nil and nil or tostring(input)
        OS.modal={title=ascii(title),message=ascii(message),buttons=safeButtons,callback=safeCallback,
            input=safeInput,index=safeInput and 1 or #safeButtons,pos=safeInput and #safeInput or 0}
    end
    local function dismiss(choice)
        local modal=OS.modal; if not modal then return end
        OS.modal=nil; overlayDirty()
        if type(modal.callback)=="function" then
            local ok,err=pcall(modal.callback,choice,modal.input)
            if not ok then logLine("ERROR","Dialog callback: "..tostring(err)); dialog("Error",tostring(err),{"OK"}) end
        end
    end
    local function removeWindow(win)
        if not win then return end
        if win.timer then os.cancelTimer(win.timer); OS.appTimers[win.timer]=nil; win.timer=nil end
        invalidate(win)
        for i,w in ipairs(OS.windows) do if w==win then table.remove(OS.windows,i); break end end
        if OS.active==win then
            OS.active=nil
            for i=#OS.windows,1,-1 do if not OS.windows[i].minimized then OS.active=OS.windows[i]; break end end
        end
        mark(OS.active); taskDirty(); OS.desktopDirty=true; invalidate(workspace())
    end
    local function closeWindow(win)
        if not win then return end
        if not win.crash and win.app.unsaved then
            dialog("Unsaved changes","Discard changes in "..win.name.."?",{"Discard","Keep"},function(choice)
                if choice=="Discard" then appCall(win,"close"); removeWindow(win) end
            end)
        else appCall(win,"close"); removeWindow(win) end
    end
    local function minimize(win)
        if not win then return end
        invalidate(win); win.minimized=true; if win==OS.active then OS.active=nil end
        for i=#OS.windows,1,-1 do if not OS.windows[i].minimized then OS.active=OS.windows[i]; break end end
        taskDirty(); OS.desktopDirty=true; invalidate(workspace())
    end
    local function maximize(win)
        if not win then return end
        invalidate(win)
        if win.restore then
            local restore=win.restore; win.restore=nil
            for k,v in pairs(restore) do win[k]=v end
        else
            win.restore={x=win.x,y=win.y,w=win.w,h=win.h,minimized=win.minimized}
            local area=workspace(); win.x,win.y,win.w,win.h=area.x,area.y,area.w,area.h; win.minimized=false
        end
        fit(win); mark(win); taskDirty(); OS.desktopDirty=true
    end
    local function openApp(id,args)
        local def=OS.registry[id]; if not def then return end
        if id~="notepad" then
            for _,w in ipairs(OS.windows) do if w.id==id then focus(w); return w end end
        end
        if #OS.windows>=HCC_MAX_WINDOWS then notify("Window limit reached",P.warning); return end
        local area=workspace(); OS.nextWindowId=OS.nextWindowId+1
        local cascade=(OS.nextWindowId-1)%6
        local available,missing=true,{}
        if type(appAvailable)=="function" then available,missing=appAvailable(def) end
        local win={id=id,name=def.name,x=area.x+28+cascade*18,y=area.y+18+cascade*14,
            w=def.defaultWidth,h=def.defaultHeight,dirty=true,commands={},buttons={},windowId=OS.nextWindowId,
            requirementsMet=available,requirementsMissing=missing}
        fit(win); win.app=setmetatable({win=win,context=E.appContext},{__index=def})
        focus(win); appCall(win,"init",args); logLine("INFO","App start: "..id); return win
    end
    local function register(id,name,icon,w,h,app)
        app.id=id; app.iconId=id; app.name=name; app.icon=icon; app.defaultWidth=w; app.defaultHeight=h
        OS.registry[id]=app; OS.order[#OS.order+1]=id
    end
    local function button(app,c,x,y,w,label,fn)
        local hit={kind="button",x=x,y=y,w=w,h=16,label=label,action=type(fn)=="function" and fn or function() end}
        local hot=OS.hover and OS.hover.win==app.win and OS.hover.hit and
            OS.hover.hit.x==x and OS.hover.hit.y==y
        c:filledRectangle(x,y,w,16,hot and P.border or P.panelBackground); c:rectangle(x,y,w,16,hot and P.accent or P.border)
        c:text(x+4,y+3,label,P.textPrimary); app.win.buttons[#app.win.buttons+1]=hit; return hit
    end
    local function errorBox(message) logLine("ERROR",message); dialog("Error",ascii(message),{"OK"}) end
    local function requestExit()
        local unsaved=0; for _,w in ipairs(OS.windows) do if w.app.unsaved then unsaved=unsaved+1 end end
        dialog("Exit HCC OS",unsaved>0 and ("Discard "..unsaved.." unsaved document(s) and exit?") or "Exit to CraftOS?",{"Exit","Cancel"},function(choice)
            if choice=="Exit" then OS.running=false end
        end)
    end

    E.OS=OS; E.TITLE=TITLE; E.TASK=TASK; E.TOP=TOP; E.workspace=workspace
    E.logLine=logLine; E.screen=screen; E.invalidate=invalidate; E.mark=mark; E.taskDirty=taskDirty
    E.overlayDirty=overlayDirty; E.notify=notify; E.appCall=appCall; E.focus=focus; E.fit=fit
    E.allDirty=allDirty; E.dialog=dialog; E.dismiss=dismiss; E.removeWindow=removeWindow
    E.closeWindow=closeWindow; E.minimize=minimize; E.maximize=maximize; E.openApp=openApp
    E.register=register; E.button=button; E.errorBox=errorBox; E.requestExit=requestExit
    E.clearLogs=function() OS.logs={} end
    local readable={windows=true,active=true,held=true,logs=true,started=true,renderCount=true,renderRate=true,
        syncRate=true,pointer=true,order=true,registry=true,desktopPage=true,taskScroll=true}
    E.AppOS=setmetatable({},{__index=function(_,key) if readable[key] then return OS[key] end end,
        __newindex=function() error("Application OS state is read-only",2) end})
end

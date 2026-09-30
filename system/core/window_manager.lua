-- HCC OS v1.5 window manager.
-- Windows are model objects. Rendering and input consume the same geometry,
-- which prevents the old title-bar/client-area drift.

return function(E)
    local env=setmetatable({},{__index=E})
    local _ENV=env
    local httpService=context and context.httpService
    local sharedHttpRequests=httpService and httpService.requests or
        (context and type(context.httpRequests)=="table" and context.httpRequests or {})
    if context then context.httpRequests=sharedHttpRequests end
    local OS={windows={},damage={},registry={},order={},recentApps={},menuRecentCount=0,active=nil,modal=nil,toast=nil,
        menu=false,powerMenu=false,menuIndex=1,menuQuery="",iconIndex=1,desktopPage=1,taskScroll=1,context=nil,
        pointer={x=0,y=0,visible=false,shape="arrow",lastMove=0},held={},running=true,
        desktopHover=nil,desktop={},task={},overlay={},desktopDirty=true,taskDirty=true,
        overlayDirty=true,started=now(),renderCount=0,renderRate=0,syncRate=0,
        frameTimer=nil,drag=nil,appTimers={},systemTimers={},ownedTimers={},ignoredTimers={},httpRequests=sharedHttpRequests,
        mouseButtons={},hover=nil,logs={},logSequence=0,
        nextWindowId=0,rebootRequested=false,shutdownRequested=false,recoveryRequested=false}
    -- The shell reserves a four-pixel safe area and a bottom taskbar while
    -- application windows retain the shared compact title bar.
    local TITLE,TASK,TOP=30,40,4
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
        if type(E.overlayBounds)=="function" then
            for _,r in ipairs(E.overlayBounds(OS)) do invalidate(r) end
        else
            invalidate(screen())
        end
        OS.overlayDirty=true
    end
    local function notify(message,color)
        OS.toast={message=ascii(message),color=color or P.accent,untilTime=now()+4}
        overlayDirty(); logLine("INFO",message)
    end
    local function rememberIgnoredTimer(id)
        if not finite(id) then return end
        local t=now(); local count,oldestId,oldest=0,nil,math.huge
        for timerId,expires in pairs(OS.ignoredTimers) do
            if expires<=t then OS.ignoredTimers[timerId]=nil
            else
                count=count+1
                if expires<oldest then oldestId,oldest=timerId,expires end
            end
        end
        if count>=256 and oldestId then OS.ignoredTimers[oldestId]=nil end
        OS.ignoredTimers[id]=t+30
    end
    local function trackSystemTimer(id,category)
        if not finite(id) then return nil end
        OS.systemTimers[id]=category or true
        return id
    end
    local function startSystemTimer(delay,category)
        local ok,id=pcall(os.startTimer,delay)
        if not ok or not finite(id) then return nil,tostring(id or "timer unavailable") end
        trackSystemTimer(id,category)
        return id
    end
    local function forgetOwnedTimer(id)
        local record=OS.ownedTimers[id]
        if not record then return nil end
        OS.ownedTimers[id]=nil
        if record.win and record.win.ownedTimers then record.win.ownedTimers[id]=nil end
        return record
    end
    local function cancelTimer(id)
        if not finite(id) then return false end
        local record=forgetOwnedTimer(id)
        local ok=pcall(os.cancelTimer,id)
        OS.systemTimers[id]=nil; OS.appTimers[id]=nil
        if record and record.win and record.win.timer==id then record.win.timer=nil end
        rememberIgnoredTimer(id)
        return ok
    end
    local function cancelOwnedTimers(win)
        if not win or not win.ownedTimers then return end
        local ids={}; for id in pairs(win.ownedTimers) do ids[#ids+1]=id end
        for _,id in ipairs(ids) do cancelTimer(id) end
    end
    local function cancelWindowTimers(win)
        if not win then return end
        if win.timer then cancelTimer(win.timer); win.timer=nil end
        cancelOwnedTimers(win)
    end
    local function cancelSystemTimer(id)
        if not finite(id) then return false end
        return cancelTimer(id)
    end
    local function consumeSystemTimer(id)
        if not finite(id) then return false end
        local known=OS.systemTimers[id]~=nil
        OS.systemTimers[id]=nil
        return known
    end
    local function consumeIgnoredTimer(id)
        if not finite(id) then return false end
        local expires=OS.ignoredTimers[id]
        if not expires then return false end
        OS.ignoredTimers[id]=nil
        return expires>now()
    end
    local cancelWindowHttpRequests
    local function failApp(win,label,reason)
        if not win or win.crash then return false end
        win.crash=ascii(reason or "application failed")
        cancelWindowTimers(win); cancelWindowHttpRequests(win); mark(win)
        if label=="close" then win.cleanupAttempted=true
        elseif not win.cleanupAttempted then
            win.cleanupAttempted=true
            local close=win.app and win.app.close
            if type(close)=="function" then
                local cleanupOk,cleanupError=pcall(close,win.app)
                if not cleanupOk then logLine("WARN",win.name.." cleanup after crash failed: "..ascii(cleanupError)) end
            end
        end
        logLine("ERROR",win.name.."."..tostring(label or "callback")..": "..win.crash)
        notify(win.name.." stopped",P.error)
        return true
    end
    local function invokeApp(win,label,callback)
        local ok,result=xpcall(callback,function(reason)
            return debug and debug.traceback and debug.traceback(tostring(reason),2) or tostring(reason)
        end)
        if not ok then
            failApp(win,label,result)
            return nil
        end
        return result
    end
    local function appCall(win,method,...)
        if not win or (win.crash and method~="close") then return end
        if method=="close" and win.cleanupAttempted then return end
        local f=win.app and win.app[method]; if not f then return end
        local args={...}
        return invokeApp(win,method,function() return f(win.app,unpack(args)) end)
    end
    local function scheduleOwnedTimer(win,delay,callback)
        delay=tonumber(delay)
        if not win or win.closed or win.crash or win.minimized then return nil,"application is not active" end
        if type(callback)~="function" then return nil,"timer callback must be a function" end
        if not finite(delay) or delay<0 or delay>86400 then return nil,"timer delay is out of range" end
        local ok,id=pcall(os.startTimer,delay)
        if not ok or not finite(id) then return nil,tostring(id or "timer unavailable") end
        win.ownedTimers=win.ownedTimers or {}
        local record={win=win,callback=callback}
        OS.ownedTimers[id]=record; win.ownedTimers[id]=true
        return id
    end
    local function cancelOwnedTimer(win,id)
        local record=OS.ownedTimers[id]
        if not record or record.win~=win then return false end
        return cancelTimer(id)
    end
    local function fireOwnedTimer(id)
        local record=forgetOwnedTimer(id)
        if not record then return false end
        local win=record.win
        if win and not win.closed and not win.minimized and not win.crash then
            invokeApp(win,"timer",record.callback)
        end
        return true
    end
    cancelWindowHttpRequests=function(win)
        if httpService and win then httpService:cancelAppOwner(win)
        elseif win then win.httpRequests={} end
    end
    local function requestHttp(win,url,body,headers,binary)
        if not win or win.closed or win.crash or win.minimized then return false,"application is not active" end
        if not httpService then return false,"HTTP request service unavailable" end
        return httpService:requestApp(win,url,body,headers,binary)
    end
    local function cancelHttpRequest(win,url)
        return httpService and httpService:cancelApp(win,url) or false
    end
    local function closeHttpHandle(handle)
        if type(handle)=="table" and type(handle.close)=="function" then pcall(handle.close) end
    end
    local function dispatchHttpEvent(event)
        if not httpService then return false end
        return httpService:dispatch(event,function(win,method,url,payload)
            if not win or win.closed or win.crash or not win.app or type(win.app[method])~="function" then return false end
            appCall(win,method,url,payload)
            return not win.crash
        end,function(message) logLine("ERROR",message) end)
    end
    local function rememberRecentApp(id)
        if type(id)~="string" or not OS.registry[id] then return end
        for index=#OS.recentApps,1,-1 do
            if OS.recentApps[index]==id then table.remove(OS.recentApps,index) end
        end
        table.insert(OS.recentApps,1,id)
        while #OS.recentApps>4 do table.remove(OS.recentApps) end
    end
    local function focus(win)
        if not win then return end
        rememberRecentApp(win.id)
        local previous=OS.active
        local wasMinimized=win.minimized
        win.minimized=false
        if wasMinimized then
            win.lastUpdate=now()
            appCall(win,"resume")
            win.nextUpdate=nil
        end
        for i,w in ipairs(OS.windows) do if w==win then table.remove(OS.windows,i); break end end
        OS.windows[#OS.windows+1]=win; OS.active=win
        if type(E.revealActiveTask)=="function" then E.revealActiveTask() end
        mark(previous); mark(win); taskDirty(); OS.desktopDirty=true; invalidate(workspace())
    end
    local function fit(win)
        local area=workspace(); local minW=min(win.minWidth or 160,area.w); local minH=min(win.minHeight or 116,area.h)
        win.w=floor(clamp(win.w,minW,area.w)); win.h=floor(clamp(win.h,minH,area.h))
        local visible=12
        win.x=floor(clamp(win.x,area.x-win.w+visible,area.x+area.w-visible))
        win.y=floor(clamp(win.y,area.y-TITLE+visible,area.y+area.h-min(TITLE,win.h)))
    end
    local function allDirty()
        OS.desktopDirty=true; OS.taskDirty=true; OS.overlayDirty=true; OS.damage={screen()}
        if OS.pointer then
            OS.pointer.x=clamp(OS.pointer.x or 0,0,Driver.w-1)
            OS.pointer.y=clamp(OS.pointer.y or 0,0,Driver.h-1)
        end
        for _,w in ipairs(OS.windows) do fit(w); w.dirty=true end
    end
    local function dialog(title,message,buttons,callback,input)
        OS.drag=nil
        local safeButtons={}
        if type(buttons)=="table" then
            for _,label in ipairs(buttons) do
                if type(label)=="string" and label~="" then safeButtons[#safeButtons+1]=ascii(label):sub(1,32) end
            end
        end
        if #safeButtons==0 then safeButtons={"OK"} end
        local safeCallback=type(callback)=="function" and callback or nil
        local safeInput
        if input~=nil then safeInput=tostring(input) end
        if safeInput and #safeInput>8192 then safeInput=safeInput:sub(1,8192) end
        OS.modal={title=ascii(title),message=ascii(message),buttons=safeButtons,callback=safeCallback,
            input=safeInput,index=safeInput and 1 or #safeButtons,pos=safeInput and #safeInput or 0}
        overlayDirty()
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
        win.closed=true; cancelWindowTimers(win); cancelWindowHttpRequests(win)
        invalidate(win)
        for i,w in ipairs(OS.windows) do if w==win then table.remove(OS.windows,i); break end end
        if OS.active==win then
            OS.active=nil
            for i=#OS.windows,1,-1 do if not OS.windows[i].minimized then OS.active=OS.windows[i]; break end end
        end
        if type(E.revealActiveTask)=="function" then E.revealActiveTask() end
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
        invalidate(win); win.minimized=true; cancelWindowTimers(win); appCall(win,"pause"); if win==OS.active then OS.active=nil end
        for i=#OS.windows,1,-1 do if not OS.windows[i].minimized then OS.active=OS.windows[i]; break end end
        if type(E.revealActiveTask)=="function" then E.revealActiveTask() end
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
            requirementsMet=available,requirementsMissing=missing,ownedTimers={}}
        fit(win)
        local appContext=type(E.makeAppContext)=="function" and E.makeAppContext(win) or nil
        win.app=setmetatable({win=win,context=appContext},{__index=def})
        focus(win); appCall(win,"init",args); logLine("INFO","App start: "..id); return win
    end
    local function register(id,name,icon,w,h,app)
        app.id=id; app.iconId=id; app.name=name; app.icon=icon; app.defaultWidth=w; app.defaultHeight=h
        OS.registry[id]=app; OS.order[#OS.order+1]=id
    end
    local function menuEntries()
        if OS.powerMenu then OS.menuRecentCount=0; return {"@restart","@shutdown","@exit","@desktop","@back"} end
        local query=ascii(OS.menuQuery or ""):lower()
        local entries,matching,seen={}, {}, {}
        for _,id in ipairs(OS.order) do
            local def=OS.registry[id]
            if def then
                local searchable=(tostring(def.name or "").." "..
                    tostring(def.description or (def.manifest and def.manifest.description) or "")):lower()
                if query=="" or searchable:find(query,1,true) then matching[id]=true end
            end
        end
        OS.menuRecentCount=0
        if query=="" then
            for _,id in ipairs(OS.recentApps) do
                if matching[id] and not seen[id] then
                    entries[#entries+1]=id; seen[id]=true; OS.menuRecentCount=OS.menuRecentCount+1
                end
            end
        end
        for _,id in ipairs(OS.order) do
            if matching[id] and not seen[id] then entries[#entries+1]=id; seen[id]=true end
        end
        return entries
    end
    local function menuCount()
        local entries=menuEntries()
        if OS.powerMenu then return #entries end
        return #entries+(#entries==0 and (OS.menuQuery or "")~="" and 1 or 0)+1
    end
    local function button(app,c,x,y,w,label,fn)
        if type(fn)~="function" then error("Button action must be a function",2) end
        local hit={kind="button",x=x,y=y,w=w,h=16,label=label,action=fn}
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
    local function requestRestart()
        if type(os.reboot)~="function" then errorBox("Computer restart is unavailable"); return end
        local unsaved=0; for _,w in ipairs(OS.windows) do if w.app.unsaved then unsaved=unsaved+1 end end
        local message=unsaved>0 and ("Restart now? Unsaved changes in "..unsaved.." document(s) will be lost.") or
            "Save settings and restart the computer?"
        dialog("Restart HCC OS",message,{"Restart","Cancel"},function(choice)
            if choice=="Restart" then OS.rebootRequested=true; OS.running=false end
        end)
    end
    local function requestShutdown()
        if type(os.shutdown)~="function" then errorBox("Computer shutdown is unavailable"); return end
        local unsaved=0; for _,w in ipairs(OS.windows) do if w.app.unsaved then unsaved=unsaved+1 end end
        local message=unsaved>0 and ("Shut down now? Unsaved changes in "..unsaved.." document(s) will be lost.") or
            "Save settings and shut down the computer?"
        dialog("Shut Down HCC OS",message,{"Shut Down","Cancel"},function(choice)
            if choice=="Shut Down" then OS.shutdownRequested=true; OS.running=false end
        end)
    end
    local function requestRecovery()
        if OS.recoveryRequested then return end
        local unsaved=0; for _,w in ipairs(OS.windows) do if w.app.unsaved then unsaved=unsaved+1 end end
        local message=unsaved>0 and
            ("Enter Recovery and close all windows? Unsaved changes in "..unsaved.." document(s) will be lost.") or
            "Close the desktop and enter Recovery mode?"
        dialog("Enter Recovery",message,{"Continue","Cancel"},function(choice)
            if choice=="Continue" then OS.recoveryRequested=true; OS.running=false end
        end)
    end

    E.OS=OS; E.TITLE=TITLE; E.TASK=TASK; E.TOP=TOP; E.workspace=workspace
    E.logLine=logLine; E.screen=screen; E.invalidate=invalidate; E.mark=mark; E.taskDirty=taskDirty
    E.overlayDirty=overlayDirty; E.notify=notify; E.appCall=appCall; E.failApp=failApp; E.focus=focus; E.fit=fit
    E.startSystemTimer=startSystemTimer; E.trackSystemTimer=trackSystemTimer
    E.cancelSystemTimer=cancelSystemTimer; E.consumeSystemTimer=consumeSystemTimer
    E.cancelWindowTimers=cancelWindowTimers
    E.cancelWindowHttpRequests=cancelWindowHttpRequests
    E.scheduleOwnedTimer=scheduleOwnedTimer; E.cancelOwnedTimer=cancelOwnedTimer
    E.fireOwnedTimer=fireOwnedTimer; E.consumeIgnoredTimer=consumeIgnoredTimer
    E.requestHttp=requestHttp; E.cancelHttpRequest=cancelHttpRequest
    E.dispatchHttpEvent=dispatchHttpEvent; E.closeHttpHandle=closeHttpHandle
    E.allDirty=allDirty; E.dialog=dialog; E.dismiss=dismiss; E.removeWindow=removeWindow
    E.closeWindow=closeWindow; E.minimize=minimize; E.maximize=maximize; E.openApp=openApp
    E.menuEntries=menuEntries; E.menuCount=menuCount
    E.register=register; E.button=button; E.errorBox=errorBox; E.requestExit=requestExit
    E.requestRestart=requestRestart; E.requestShutdown=requestShutdown
    E.requestRecovery=requestRecovery
    E.clearLogs=function() OS.logs={} end
    local readable={windows=true,active=true,held=true,logs=true,started=true,renderCount=true,renderRate=true,
        syncRate=true,pointer=true,order=true,registry=true,desktopPage=true,taskScroll=true}
    E.AppOS=setmetatable({},{__index=function(_,key) if readable[key] then return OS[key] end end,
        __newindex=function() error("Application OS state is read-only",2) end})
end

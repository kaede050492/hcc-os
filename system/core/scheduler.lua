return function(E)
 local env=setmetatable({},{__index=E})
 local _ENV=env
local configWarning=E.configWarning
local api=context and context.api
local function startSystemTimer(delay,category)
    local id,err=E.startSystemTimer(delay,category)
    if not id then error("Unable to start "..tostring(category or "system").." timer: "..tostring(err),0) end
    return id
end
local function cancelSystemTimer(id) if id then E.cancelSystemTimer(id) end end
local function boot()
    print("[HCC OS] Detecting Tom's GPU, keyboard and Player Detector...")
    local good,status=scanDevices()
    if status=="terminate" then return false end
    if not good then
        print("[HCC OS] "..(Driver.error or "tm_gpu not found"))
        print("Connect GPU + Bitmap Monitors. Waiting 10 seconds.")
        print("Press F5 to retry now, Ctrl+T to exit.")
        local timeout=startSystemTimer(10,"gpu-detect-timeout")
        local retry=startSystemTimer(1,"gpu-detect-retry")
        local attempts=1
        while not good do
            local e={os.pullEventRaw()}
            if e[1]=="terminate" then
                cancelSystemTimer(timeout); cancelSystemTimer(retry); return false
            elseif e[1]=="timer" and e[2]==timeout then
                E.consumeSystemTimer(timeout); timeout=nil
                cancelSystemTimer(retry); retry=nil
                error("Tom's GPU was not detected within 10 seconds: "..tostring(Driver.error or "not found"),0)
            elseif e[1]=="peripheral" or e[1]=="peripheral_attach" or e[1]=="peripheral_detach" or
                (e[1]=="key" and e[2]==keys.f5) or (e[1]=="timer" and e[2]==retry) then
                if e[1]=="timer" and e[2]==retry then E.consumeSystemTimer(retry)
                else cancelSystemTimer(retry) end
                retry=nil
                if attempts<12 then
                    attempts=attempts+1; good,status=scanDevices()
                    if status=="terminate" then cancelSystemTimer(timeout); return false end
                    if not good then retry=startSystemTimer(1,"gpu-detect-retry") end
                end
            end
        end
        cancelSystemTimer(timeout); cancelSystemTimer(retry)
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
    Driver.sync()
    if not fs.exists(configPath) then local ok,err=saveConfig(); if not ok then configWarning=tostring(err) end end
    if not fs.exists(currencyPath) then local ok,err=currencySave(); if not ok then currencyWarning=tostring(err) end end
    allDirty()
    if context.config:isFirstBoot() then
        local setupWindow=openApp("setup")
        if not setupWindow then error("First Boot Setup could not be opened",0) end
    elseif api and api.autoUpdatePending then openApp("updates") end
    if configWarning then notify(configWarning,P.warning)
    elseif currencyWarning then notify(currencyWarning,P.warning)
    else notify("HCC OS ready / F1 menu / double-click an icon",P.accent) end
    render()
    return true
end
local function run()
    if not boot() then return end
    local function startTimer(delay,category)
        local id,err=E.startSystemTimer(delay,category)
        if not id then error("Unable to start "..tostring(category or "system").." timer: "..tostring(err),0) end
        return id
    end
    local function cancelTimer(id) if id then E.cancelSystemTimer(id) end end
    local function consumeTimer(id) if id then E.consumeSystemTimer(id) end end
    local timer,timerAt,gpuMissingTimer,wallpaperTimer; local taskSecond=-1; local metricsAt=now(); local lastR,lastS=OS.renderCount,Driver.syncs
    while OS.running do
        local t=now(); local deadline=t+1
        if gpuAvailable() then
            if gpuMissingTimer then cancelTimer(gpuMissingTimer); gpuMissingTimer=nil end
        elseif not gpuMissingTimer then gpuMissingTimer=startTimer(10,"gpu-missing") end
        if floor(t)~=taskSecond then
            taskSecond=floor(t); OS.taskDirty=true
            invalidate(box(0,Driver.h-TASK,Driver.w,TASK))
        end
        if OS.pointer.visible and OS.pointer.lastMove>0 and t-OS.pointer.lastMove>clamp(tonumber(cfg.cursorIdle) or 6,1,30) then
            invalidate(cursorRect()); OS.pointer.visible=false
        end
        for _,w in ipairs(OS.windows) do
            if w.minimized or w.crash or w.nextUpdate then
                if w.timer then cancelTimer(w.timer); OS.appTimers[w.timer]=nil; w.timer=nil end
                w.nextUpdate=nil
            end
            if not w.minimized and not w.crash and w.app.update then
                if not w.timer then
                    local requestedInterval=appCall(w,"interval")
                    if not w.crash then
                        local interval=tonumber(requestedInterval)
                        if not finite(interval) then interval=1 end
                        -- Use an independent CC timer, not a wall-clock deadline.
                        -- At 10 TPS a 2-second (40-tick) timer takes ~4 real seconds.
                        -- Rescheduling fractions of a wall-clock deadline would hide lag.
                        interval=clamp(interval,0.05,3600)
                        local timerId,timerError=E.startSystemTimer(interval,"app-update")
                        if timerId then
                            w.timer=timerId; OS.appTimers[w.timer]=w
                        else
                            E.failApp(w,"timer",timerError or "application timer unavailable")
                        end
                    end
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
        if gpuAvailable() and (#OS.damage>0 or OS.overlayDirty) and not OS.frameTimer then
            local frameDelay=context.performance and context.performance:nextFrameDelay() or 0.05
            OS.frameTimer=startTimer(frameDelay,"frame")
        end
        if type(wallpaperLoading)=="function" and wallpaperLoading() and not wallpaperTimer then
            wallpaperTimer=startTimer(0.05,"wallpaper")
        end
        if not timer or math.abs(deadline-(timerAt or 0))>0.02 then
            if timer then cancelTimer(timer) end
            timerAt=deadline; timer=startTimer(max(0.05,deadline-t),"scheduler")
        end
        local e={os.pullEventRaw()}
        if e[1]=="timer" and E.consumeIgnoredTimer(e[2]) then
        elseif e[1]=="timer" and e[2]==OS.frameTimer then
            consumeTimer(e[2])
            OS.frameTimer=nil
            local qualityBefore=context.performance and context.performance:getQualityLevel()
            local frameStarted=now()
            render()
            local frameFinished=now()
            if context.performance then context.performance:recordFrame(max(0,(frameFinished-frameStarted)*1000),frameFinished) end
            if context.performance and qualityBefore~=context.performance:getQualityLevel() then allDirty() end
        elseif e[1]=="timer" and e[2]==gpuMissingTimer then
            consumeTimer(e[2])
            gpuMissingTimer=nil
            if not gpuAvailable() then error("Tom's GPU remained unavailable for 10 seconds: "..tostring(Driver.error or "not found"),0) end
        elseif e[1]=="timer" and e[2]==wallpaperTimer then
            consumeTimer(e[2])
            wallpaperTimer=nil
            if type(stepWallpaperLoad)=="function" then stepWallpaperLoad(0.006) end
        elseif e[1]=="timer" and OS.appTimers[e[2]] then
            local w=OS.appTimers[e[2]]; OS.appTimers[e[2]]=nil; consumeTimer(e[2]); w.timer=nil
            if not w.minimized and not w.crash then
                local updatedAt=now(); appCall(w,"update",w.lastUpdate and updatedAt-w.lastUpdate or 0); w.lastUpdate=updatedAt
            end
        elseif e[1]=="timer" and e[2]==timer then consumeTimer(e[2]); timer=nil
        elseif e[1]=="timer" and E.fireOwnedTimer(e[2]) then
        else handleEvent(e) end
        if Driver.error and not gpuAvailable() and not OS.reportedGpuError then
            OS.reportedGpuError=true; print("[HCC OS] GPU: "..Driver.error.."; reconnect or F5")
        elseif gpuAvailable() then OS.reportedGpuError=false end
    end
    if timer then cancelTimer(timer) end
    if gpuMissingTimer then cancelTimer(gpuMissingTimer) end
    if wallpaperTimer then cancelTimer(wallpaperTimer) end
    if OS.frameTimer then cancelTimer(OS.frameTimer) end
    local appTimerIds={}; for id in pairs(OS.appTimers) do appTimerIds[#appTimerIds+1]=id end
    for _,id in ipairs(appTimerIds) do cancelTimer(id) end
end
local cleaned=false
local function cleanup()
    if cleaned then return end
    cleaned=true
    for i=#OS.windows,1,-1 do
        local win=OS.windows[i]
        appCall(win,"close"); E.cancelWindowTimers(win); E.cancelWindowHttpRequests(win)
    end
    local systemTimerIds={}
    for id in pairs(OS.systemTimers or {}) do systemTimerIds[#systemTimerIds+1]=id end
    for _,id in ipairs(systemTimerIds) do pcall(E.cancelSystemTimer,id) end
    local updater=context and context.updater
    if updater and (updater.checkJob or updater.downloadJob or
        (updater.state and updater.state.phase=="downloading")) then
        local updateCleaned,updateError=pcall(updater.cleanup,updater)
        if not updateCleaned and context.logger then context.logger:error("Update cleanup failed: "..tostring(updateError)) end
    end
    if context and context.api then context.api.appMark=nil; context.api.updateWindow=nil end
    local saved,saveError=saveConfig()
    if not saved and context.logger then context.logger:error("Settings not saved: "..tostring(saveError)) end
    local currencySaved,currencyError=currencySave()
    if not currencySaved and context.logger then context.logger:error("Currency data not saved: "..tostring(currencyError)) end
    shutdownDisplay()
    if OS.rebootRequested then
        local rebootOk,rebootError=pcall(os.reboot)
        if not rebootOk and context.logger then context.logger:error("Restart failed: "..tostring(rebootError)) end
    elseif OS.shutdownRequested then
        local shutdownOk,shutdownError=pcall(os.shutdown)
        if not shutdownOk and context.logger then context.logger:error("Shutdown failed: "..tostring(shutdownError)) end
    end
end
E.boot=boot; E.run=run; E.cleanup=cleanup

end

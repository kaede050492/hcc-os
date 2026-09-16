return function(E)
 local env=setmetatable({},{__index=E})
 local _ENV=env
local function boot()
    print("[HCC OS] Detecting Tom's GPU, keyboard and Player Detector...")
    local good,status=scanDevices()
    if status=="terminate" then return false end
    if not good then
        print("[HCC OS] "..(Driver.error or "tm_gpu not found"))
        print("Connect GPU + Bitmap Monitors. Waiting 10 seconds.")
        print("Press F5 to retry now, Ctrl+T to exit.")
        local timeout=os.startTimer(10)
        local retry=os.startTimer(1)
        local attempts=1
        while not good do
            local e={os.pullEventRaw()}
            if e[1]=="terminate" then
                os.cancelTimer(timeout); os.cancelTimer(retry); return false
            elseif e[1]=="timer" and e[2]==timeout then
                error("Tom's GPU was not detected within 10 seconds: "..tostring(Driver.error or "not found"),0)
            elseif e[1]=="peripheral" or e[1]=="peripheral_attach" or e[1]=="peripheral_detach" or
                (e[1]=="key" and e[2]==keys.f5) or (e[1]=="timer" and e[2]==retry) then
                os.cancelTimer(retry)
                if attempts<12 then
                    attempts=attempts+1; good,status=scanDevices()
                    if status=="terminate" then os.cancelTimer(timeout); return false end
                    if not good then retry=os.startTimer(1) end
                end
            end
        end
        os.cancelTimer(timeout); os.cancelTimer(retry)
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
    elseif HCCV14 and HCCV14.autoUpdatePending then openApp("updates") end
    if configWarning then notify(configWarning,P.warning)
    else notify("HCC OS ready / F1 menu / double-click an icon",P.accent) end
    render()
    return true
end
local function run()
    if not boot() then return end
    local timer,timerAt,gpuMissingTimer; local taskSecond=-1; local metricsAt=now(); local lastR,lastS=OS.renderCount,Driver.syncs
    while OS.running do
        local t=now(); local deadline=t+1
        if gpuAvailable() then
            if gpuMissingTimer then os.cancelTimer(gpuMissingTimer); gpuMissingTimer=nil end
        elseif not gpuMissingTimer then gpuMissingTimer=os.startTimer(10) end
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
        if gpuAvailable() and (#OS.damage>0 or OS.overlayDirty) and not OS.frameTimer then OS.frameTimer=os.startTimer(0.05) end
        if not timer or math.abs(deadline-(timerAt or 0))>0.02 then
            if timer then os.cancelTimer(timer) end
            timerAt=deadline; timer=os.startTimer(max(0.05,deadline-t))
        end
        local e={os.pullEventRaw()}
        if e[1]=="timer" and e[2]==OS.frameTimer then OS.frameTimer=nil; render()
        elseif e[1]=="timer" and e[2]==gpuMissingTimer then
            gpuMissingTimer=nil
            if not gpuAvailable() then error("Tom's GPU remained unavailable for 10 seconds: "..tostring(Driver.error or "not found"),0) end
        elseif e[1]=="timer" and OS.appTimers[e[2]] then
            local w=OS.appTimers[e[2]]; OS.appTimers[e[2]]=nil; w.timer=nil
            if not w.minimized and not w.crash then
                local updatedAt=now(); appCall(w,"update",w.lastUpdate and updatedAt-w.lastUpdate or 0); w.lastUpdate=updatedAt
            end
        elseif e[1]=="timer" and e[2]==timer then timer=nil
        else handleEvent(e) end
        if Driver.error and not gpuAvailable() and not OS.reportedGpuError then
            OS.reportedGpuError=true; print("[HCC OS] GPU: "..Driver.error.."; reconnect or F5")
        elseif gpuAvailable() then OS.reportedGpuError=false end
    end
    if timer then os.cancelTimer(timer) end
    if gpuMissingTimer then os.cancelTimer(gpuMissingTimer) end
    if OS.frameTimer then os.cancelTimer(OS.frameTimer) end
    for id in pairs(OS.appTimers) do os.cancelTimer(id) end
end
local cleaned=false
local function cleanup()
    if cleaned then return end
    cleaned=true
    for i=#OS.windows,1,-1 do appCall(OS.windows[i],"close") end
    local saved,saveError=saveConfig()
    if not saved and context.logger then context.logger:error("Settings not saved: "..tostring(saveError)) end
    local currencySaved,currencyError=currencySave()
    if not currencySaved and context.logger then context.logger:error("Currency data not saved: "..tostring(currencyError)) end
    shutdownDisplay()
end
E.boot=boot; E.run=run; E.cleanup=cleanup

end

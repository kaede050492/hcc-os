-- HCC OS v1.5 GUI application module.
return function(E)
    local env=setmetatable({Driver=E.AppDriver,OS=E.AppOS},{__index=E})
    local _ENV=env
local Performance={}
function Performance:init() self.values={}; self:update() end
function Performance:interval() return 1 end
function Performance:update()
    local measured=performance and performance:getActualFps() or OS.renderRate
    self.values[#self.values+1]=measured
    while #self.values>cfg.performanceHistory do table.remove(self.values,1) end
    mark(self.win)
end
function Performance:draw(c)
    local controller=performance
    local target=controller and controller:getTargetFps() or 60
    local configuredMax=controller and controller:getConfiguredMaxFps() or target
    local configuredMin=controller and controller:getConfiguredMinFps() or 10
    local timerCeiling=controller and controller:getTimerCeilingFps() or 20
    local actual=controller and controller:getActualFps() or OS.renderRate
    local frame=controller and controller:getFrameTimeMs() or 0
    local dropped=controller and controller:getDroppedFrameCount() or 0
    c:text(7,6,"ADAPTIVE PERFORMANCE",P.accent)
    c:text(7,20,string.format("MAX %d  MIN %d  TARGET %d",configuredMax,configuredMin,target),P.textPrimary)
    c:text(7,32,string.format("TIMER CAP %d  ACTUAL %.1f FPS",timerCeiling,actual),P.textSecondary)
    Widget.graph(c,8,47,c.w-16,c.h-78,self.values,P.success,max(1,target),P)
    c:text(8,c.h-26,string.format("FRAME %.1f ms   DROPPED %d",frame,dropped),P.textSecondary)
    c:text(8,c.h-14,(controller and controller:isDegraded()) and "QUALITY: REDUCED" or "QUALITY: FULL",P.textPrimary)
end
register("performance","Performance Graph","PG",350,190,Performance)

end

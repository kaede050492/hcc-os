-- HCC OS v1.5 GUI application module.
return function(E)
    local env=setmetatable({Driver=E.AppDriver,OS=E.AppOS},{__index=E})
    local _ENV=env
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

end

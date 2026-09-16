-- HCC OS v1.4 GUI application module.
return function(E)
    local env=setmetatable({Driver=E.AppDriver,OS=E.AppOS},{__index=E})
    local _ENV=env
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
    c:text(7,19,"HCC CPU BRAND (FICTIONAL): "..HCC_CPU,P.textPrimary)
    local aw,ah=Driver.getActualSize(); c:text(7,32,string.format("DISPLAY %dx%d  %dx%d blocks @ %dpx",aw,ah,HCC_BLOCKS_X,HCC_BLOCKS_Y,HCC_PIXELS_PER_BLOCK),P.textSecondary)
    local memOk,mem=pcall(collectgarbage,"count"); local gx=c.w>=390 and floor(c.w*0.55) or 0
    c:text(7,47,string.format("UPTIME %ds  WINDOWS %d  PERIPHERALS %d",floor(now()-OS.started),#OS.windows,#devices.list),P.textSecondary)
    c:text(7,61,string.format("GPU %s  PAINT %.1f/s  SYNC %.1f/s",devices.gpuName or "NONE",OS.renderRate,OS.syncRate),P.textSecondary)
    c:text(7,75,"LUA HEAP: "..(memOk and string.format("%.0f KiB",mem) or "n/a"),P.textSecondary)
    if gx>0 then graph(c,gx,47,c.w-gx-8,82,self.renders,P.accent,max(1,OS.renderCount))
    else graph(c,7,93,c.w-14,62,self.renders,P.accent,max(1,OS.renderCount)) end
    local y=gx>0 and 139 or 166; c:text(7,y,"PERFORMANCE HISTORY",P.accent)
    c:text(7,y+14,"render samples: "..#self.renders.." / "..cfg.performanceHistory,P.textSecondary)
    c:text(7,y+28,"F5 RESCAN   system interval "..cfg.systemInterval.."s",P.textSecondary)
end
register("system","System Monitor","SM",470,225,SystemMonitor)
E.graph=graph
end

-- HCC OS v1.5 GUI application module.
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
function SystemMonitor:init() self.renders={}; self.last=0; self:update() end
function SystemMonitor:interval() return cfg.systemInterval end
function SystemMonitor:update()
    self.renders[#self.renders+1]=OS.renderRate
    while #self.renders>cfg.performanceHistory do table.remove(self.renders,1) end
    self.last=now(); mark(self.win)
end
function SystemMonitor:onKey(k) if k==keys.f5 then rescan(); self:update() end end
function SystemMonitor:draw(c)
    if c.w<390 or c.h<160 then
        local aw,ah=Driver.getActualSize()
        local memOk,mem=pcall(collectgarbage,"count")
        local target=performance and performance:getTargetFps() or 60
        local actual=performance and performance:getActualFps() or OS.renderRate
        c:clipping(7,4,c.w-14,10):text(0,0,HCC_VERSION_LABEL.." / SYSTEM MONITOR",P.accent)
        c:clipping(7,17,c.w-14,10):text(0,0,string.format("UP %ds  WINDOWS %d  DEVICES %d",floor(now()-OS.started),#OS.windows,#devices.list),P.textPrimary)
        c:clipping(7,29,c.w-14,10):text(0,0,shortText(string.format("DISPLAY %dx%d  GPU %s",aw,ah,devices.gpuName or "NONE"),44),P.textSecondary)
        c:clipping(7,41,c.w-14,10):text(0,0,string.format("FPS %.1f/%d  HEAP %s",actual,target,memOk and string.format("%.0f KiB",mem) or "n/a"),P.textSecondary)
        if c.h>=70 then
            local graphHeight=max(1,min(22,c.h-68))
            graph(c,7,53,c.w-14,graphHeight,self.renders,P.accent,max(1,target))
        end
        if c.h>=80 then c:clipping(7,c.h-12,c.w-14,10):text(0,0,"F5 RESCAN  /  INTERVAL "..cfg.systemInterval.."s",P.textSecondary) end
        return
    end
    c:text(7,5,HCC_VERSION_LABEL.." / SYSTEM MONITOR",P.accent)
    c:text(7,19,"HCC CPU BRAND (FICTIONAL): "..HCC_CPU,P.textPrimary)
    local aw,ah=Driver.getActualSize(); c:text(7,32,string.format("DISPLAY %dx%d  %dx%d blocks @ %dpx",aw,ah,HCC_BLOCKS_X,HCC_BLOCKS_Y,HCC_PIXELS_PER_BLOCK),P.textSecondary)
    local memOk,mem=pcall(collectgarbage,"count"); local gx=c.w>=390 and floor(c.w*0.55) or 0
    local target=performance and performance:getTargetFps() or 60
    local actual=performance and performance:getActualFps() or OS.renderRate
    local infoWidth=gx>0 and max(1,gx-14) or max(1,c.w-14)
    c:clipping(7,47,infoWidth,10):text(0,0,string.format("UPTIME %ds  WINDOWS %d  DEVICES %d",floor(now()-OS.started),#OS.windows,#devices.list),P.textSecondary)
    local gpuName=shortText(devices.gpuName or "NONE",16)
    c:clipping(7,61,infoWidth,10):text(0,0,string.format("GPU %s  TARGET %d  ACTUAL %.1f",gpuName,target,actual),P.textSecondary)
    c:clipping(7,75,infoWidth,10):text(0,0,string.format("LOGICAL 576x320  PHYSICAL %dx%d",aw,ah),P.textSecondary)
    c:clipping(7,89,infoWidth,10):text(0,0,string.format("SCALE %.2f  SYNC %.1f/s  HEAP %s",Driver.scale,OS.syncRate,memOk and string.format("%.0f KiB",mem) or "n/a"),P.textSecondary)
    if gx>0 then graph(c,gx,47,c.w-gx-8,82,self.renders,P.accent,max(1,target))
    else graph(c,7,107,c.w-14,52,self.renders,P.accent,max(1,target)) end
    local y=gx>0 and 153 or 166; c:text(7,y,"PERFORMANCE HISTORY",P.accent)
    c:text(7,y+14,"render samples: "..#self.renders.." / "..cfg.performanceHistory,P.textSecondary)
    c:text(7,y+28,"F5 RESCAN   system interval "..cfg.systemInterval.."s",P.textSecondary)
end
register("system","System Monitor","SM",470,225,SystemMonitor)
E.graph=graph
end

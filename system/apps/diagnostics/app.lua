-- HCC OS v1.5 GUI application module.
return function(E)
    local env=setmetatable({Driver=E.AppDriver,OS=E.AppOS},{__index=E})
    local _ENV=env
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
        "HCC CPU BRAND (FICTIONAL): "..HCC_CPU, "GPU: "..(devices.gpuName or "UNAVAILABLE"),
        string.format("getSize(): %dx%d / %d pixels",actualW,actualH,actualW*actualH),
        "Target 576x320 / 9x5 blocks / 64px: "..((actualW==HCC_TARGET_W and actualH==HCC_TARGET_H) and "MATCH" or "ADAPTIVE LAYOUT"),
        "Player Detector: "..(devices.detectorName or "UNAVAILABLE"),
        "Tom keyboard: "..(next(devices.keyboards) and "CONNECTED" or "NONE; terminal keys available"),
        "Lua heap: "..(ok and string.format("%.0f KiB",mem) or "Unavailable"),
        "Uptime: "..floor(now()-OS.started).."s",
        string.format("Paints/s %.1f  Sync/s %.1f",OS.renderRate,OS.syncRate),
        "Driver error: "..(Driver.error or "none"),"--- CONNECTED PERIPHERALS ---"}
    for _,p in ipairs(devices.list) do lines[#lines+1]=p.name.." : "..p.kind end
    self.top=clamp(self.top,1,max(1,#lines-floor((c.h-28)/12)+1))
    for i=self.top,#lines do c:text(6,6+(i-self.top)*12,lines[i],i==1 and P.accent or P.textSecondary) end
    button(self,c,5,c.h-22,94,"F5: RESCAN",function() rescan() end)
end
register("diagnostics","Diagnostics","DG",394,258,Diagnostics)

end

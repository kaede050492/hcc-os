-- HCC OS v1.5 GUI application module.
return function(E)
    local env=setmetatable({Driver=E.AppDriver,OS=E.AppOS},{__index=E})
    local _ENV=env
local PeripheralManager={}
function PeripheralManager:init() self.selected=1; self.methods={}; self:refresh() end
function PeripheralManager:refresh()
    self.methods={}; self.selected=clamp(self.selected,1,max(1,#devices.list)); local item=devices.list[self.selected]
    if item and peripheral.getMethods then local ok,m=pcall(peripheral.getMethods,item.name); if ok and type(m)=="table" then self.methods=m; table.sort(self.methods) end end
    mark(self.win)
end
function PeripheralManager:onKey(k)
    if k==keys.up then self.selected=max(1,self.selected-1); self:refresh()
    elseif k==keys.down then self.selected=min(#devices.list,self.selected+1); self:refresh()
    elseif k==keys.f5 then rescan(); self:refresh()
    end
end
function PeripheralManager:onMouse(kind,x,y,b)
    if kind=="scroll" then self.selected=clamp(self.selected+b,1,max(1,#devices.list)); self:refresh()
    elseif kind=="click" and y>=32 and y<self.win.h-26 and x<self.win.w*0.52 then self.selected=clamp(1+floor((y-32)/17),1,max(1,#devices.list)); self:refresh() end
end
function PeripheralManager:draw(c)
    c:text(6,5,"PERIPHERAL MANAGER",P.accent); c:text(6,19,"F5 rescan  arrows select",P.textSecondary)
    local left=floor(c.w*0.52); c:line(left,31,left,c.h-27,P.border)
    for i,item in ipairs(devices.list) do
        local y=32+(i-1)*17; if i==self.selected then c:filledRectangle(4,y,left-9,16,P.panelBackground) end
        c:text(8,y+3,item.name:sub(1,24),P.textPrimary); c:text(left-75,y+3,item.kind:sub(1,10),P.textSecondary)
    end
    local item=devices.list[self.selected]; local r=c:clipping(left+7,34,c.w-left-12,c.h-64)
    r:text(0,0,"DEVICE",P.accent); r:text(0,17,item and item.name or "none",P.textPrimary); r:text(0,31,item and item.kind or "",P.textSecondary)
    r:text(0,49,"METHODS",P.accent)
    for i,name in ipairs(self.methods) do r:text(0,63+(i-1)*12,name,P.textSecondary) end
    button(self,c,5,c.h-23,75,"F5 RESCAN",function() rescan(); self:refresh() end)
end
register("peripherals","Peripheral Manager","PM",460,260,PeripheralManager)

end

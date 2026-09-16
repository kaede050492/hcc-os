-- HCC OS v1.5 GUI application module.
return function(E)
    local env=setmetatable({Driver=E.AppDriver,OS=E.AppOS},{__index=E})
    local _ENV=env
local ResourceMonitor={}
function ResourceMonitor:init() self.items={}; self.previous={}; self.history={}; self.top=1; self:update() end
function ResourceMonitor:interval() return cfg.resourceRefresh end
function ResourceMonitor:update()
    local aggregate={}
    for _,info in ipairs(devices.inventories) do
        local ok,list=pcall(info.p.list)
        if ok and type(list)=="table" then for _,item in pairs(list) do local id=ascii(item.name or item.id or "unknown"); aggregate[id]=(aggregate[id] or 0)+floor(item.count or 0) end end
    end
    self.items={}; local total=0
    for id,count in pairs(aggregate) do
        local price=currencyItemById(id); local unit=price and currencyItemValue(price,"buy"); local value=unit and unit*count or nil
        if value then total=total+value end
        self.items[#self.items+1]={id=id,count=count,change=count-(self.previous[id] or count),item=price,value=value,stack=price and price.stack or 64}
    end
    table.sort(self.items,function(a,b) return a.id<b.id end); self.previous=aggregate
    self.history[#self.history+1]=total; while #self.history>cfg.performanceHistory do table.remove(self.history,1) end; self.total=total; mark(self.win)
end
function ResourceMonitor:onKey(k) if k==keys.f5 then rescan(); self:update() elseif k==keys.up then self.top=max(1,self.top-1) elseif k==keys.down then self.top=min(max(1,#self.items),self.top+1) end; mark(self.win) end
function ResourceMonitor:onMouse(kind,x,y,b) if kind=="scroll" then self.top=clamp(self.top+b,1,max(1,#self.items)); mark(self.win) end end
function ResourceMonitor:draw(c)
    c:text(6,5,"RESOURCE MONITOR",P.accent); c:text(6,19,"Inventory totals / Currency estimate",P.textSecondary)
    local header="ITEM                         COUNT  STACKS CHANGE  VALUE"; c:text(6,35,header,P.accent)
    local rows=max(1,floor((c.h-77)/14)); self.top=clamp(self.top,1,max(1,#self.items-rows+1))
    for row=0,rows-1 do local item=self.items[self.top+row]; if not item then break end; local y=50+row*14; c:text(6,y,item.id:sub(1,28),P.textPrimary); c:text(190,y,tostring(item.count),P.textPrimary); c:text(245,y,string.format("%d+%d",floor(item.count/item.stack),item.count%item.stack),P.textSecondary); c:text(315,y,(item.change>=0 and "+" or "")..item.change,item.change>=0 and P.success or P.warning); c:text(370,y,item.value and currencyFormat(item.value,currencyData.allowDecimals) or "-",item.value and P.accent or P.textSecondary) end
    c:text(6,c.h-15,"TOTAL: "..(self.total and currencyFormat(self.total,currencyData.allowDecimals) or "-").."  F5 refresh",P.accent)
end
register("resource","Resource Monitor","RS",500,250,ResourceMonitor)

end

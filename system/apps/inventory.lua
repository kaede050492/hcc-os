-- HCC OS v1.4 GUI application module.
return function(E)
    local env=setmetatable({Driver=E.AppDriver,OS=E.AppOS},{__index=E})
    local _ENV=env
local Inventory={}
local function inventorySize(info)
    if not info or not info.p or type(info.p.size)~="function" then return 1 end
    local ok,value=pcall(info.p.size)
    if not ok or not finite(value) then return 1 end
    return max(1,floor(value))
end
function Inventory:init(args)
    self.selected=1; self.top=1; self.inventoryIndex=1; self.slots={}; self.lastRefresh=0
    self:refresh(args and args.inventory)
end
function Inventory:interval() return cfg.inventoryRefresh end
function Inventory:refresh(preferred)
    if preferred then
        for i,v in ipairs(devices.inventories) do if v.name==preferred then self.inventoryIndex=i end end
    end
    local info=devices.inventories[self.inventoryIndex]
    self.info=info; self.slots={}; self.error=nil
    if info then
        local size=inventorySize(info)
        local listed,list=pcall(info.p.list)
        if not listed or type(list)~="table" then self.error="Inventory list unavailable"
        else
            for slot=1,size do
                local item=list[slot]
                if item then
                    local detail=item
                    if type(info.p.getItemDetail)=="function" then
                        local good,value=pcall(info.p.getItemDetail,slot); if good and type(value)=="table" then detail=value end
                    end
                    self.slots[slot]={slot=slot,id=ascii(detail.name or detail.id or "unknown"),
                        name=ascii(detail.displayName or detail.name or detail.id or "unknown"),count=floor(detail.count or item.count or 0),
                        nbt=detail.nbt}
                end
            end
        end
    end
    self.selected=clamp(self.selected,1,inventorySize(info))
    self.lastRefresh=now(); mark(self.win)
end
function Inventory:nextInventory(delta)
    if #devices.inventories==0 then self:refresh(); return end
    self.inventoryIndex=(self.inventoryIndex-1+delta)%#devices.inventories+1; self:refresh()
end
function Inventory:openPrice()
    local item=self.slots[self.selected]; if not item then return end
    local w=openApp("currency"); if w then
        appCall(w,"selectItemId",item.id)
        notify(currencyItemById(item.id) and "Currency item selected" or "Item not in Currency dictionary",currencyItemById(item.id) and P.success or P.warning)
    end
end
function Inventory:onKey(k)
    local size=inventorySize(self.info)
    if k==keys.up then self.selected=max(1,self.selected-1)
    elseif k==keys.down then self.selected=min(size,self.selected+1)
    elseif k==keys.left then self:nextInventory(-1)
    elseif k==keys.right or k==keys.i then self:nextInventory(1)
    elseif k==keys.f5 then self:refresh()
    elseif k==keys.enter or k==keys.p then self:openPrice() end
    mark(self.win)
end
function Inventory:onMouse(kind,x,y,b)
    if kind=="scroll" then self.selected=clamp(self.selected+b*3,1,inventorySize(self.info))
    elseif kind=="click" then
        if y<27 and x>=self.win.w-75 then self:nextInventory(1); return end
        if y>=34 and y<self.win.h-35 and x<self.win.w*0.58 then self.selected=clamp(1+floor((y-34)/18)+self.top-1,1,inventorySize(self.info))
        elseif y>=self.win.h-28 then self:openPrice() end
    end
    mark(self.win)
end
function Inventory:draw(c)
    c:text(6,5,"INVENTORY VIEWER",P.accent)
    if #devices.inventories==0 then
        c:paragraph(8,34,"No compatible inventory peripheral found. Connect a chest or storage peripheral and press F5.",P.warning,c.w-16,5)
        c:text(8,c.h-14,"F5 RESCAN",P.textSecondary); return
    end
    local info=self.info or devices.inventories[self.inventoryIndex]; local size=inventorySize(info)
    local title=(info and info.name or "inventory").."  "..size.." slots"
    c:text(6,19,title,P.textSecondary)
    button(self,c,c.w-70,3,63,"NEXT",function() self:nextInventory(1) end)
    local left=floor(c.w*0.58); c:line(left,32,left,c.h-30,P.border)
    local rows=max(1,floor((c.h-70)/18)); self.top=clamp(self.top,1,max(1,size-rows+1))
    if self.selected<self.top then self.top=self.selected elseif self.selected>=self.top+rows then self.top=self.selected-rows+1 end
    for row=0,rows-1 do
        local slot=self.top+row; if slot>size then break end; local item=self.slots[slot]; local y=34+row*18
        if slot==self.selected then c:filledRectangle(5,y,left-10,17,P.panelBackground) end
        c:text(9,y+4,string.format("%03d",slot),P.textSecondary)
        c:text(35,y+4,item and item.name:sub(1,22) or "- empty -",item and P.textPrimary or P.textSecondary)
        if item then c:text(left-48,y+4,"x"..item.count,P.accent) end
    end
    local item=self.slots[self.selected]; local right=c:clipping(left+7,34,c.w-left-12,c.h-64)
    right:text(0,0,"SELECTED SLOT",P.accent)
    if item then
        right:paragraph(0,18,item.name,P.textPrimary,right.w,3)
        right:text(0,57,"ID: "..item.id,P.textSecondary)
        right:text(0,72,"COUNT: "..item.count,P.textPrimary)
        local priced=currencyItemById(item.id)
        right:text(0,90,priced and ("BUY: "..(priced.buy=="" and "-" or priced.buy).."  SELL: "..(priced.sell=="" and "-" or priced.sell)) or "PRICE: NOT REGISTERED",priced and P.success or P.warning)
    else right:text(0,22,"Choose a slot",P.textSecondary) end
    button(self,c,5,c.h-25,95,"P: PRICE",function() self:openPrice() end)
    c:text(106,c.h-20,"I/ARROWS inventory  F5 refresh",P.textSecondary)
end
register("inventory","Inventory Viewer","IV",500,270,Inventory)

end

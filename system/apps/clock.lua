-- HCC OS v1.4 GUI application module.
return function(E)
    local env=setmetatable({Driver=E.AppDriver,OS=E.AppOS},{__index=E})
    local _ENV=env
local Clock={}
function Clock:init() self.mode=cfg.clockMode; self:update() end
function Clock:interval() return cfg.clockInterval end
function Clock:update()
    self.date=jst()
    if self.mode=="MCT" then
        local seconds=floor(os.time("ingame")*3600)%86400
        self.value=string.format("%02d:%02d:%02d",floor(seconds/3600),floor(seconds/60)%60,seconds%60)
    else self.value=timeText(self.date) end
    mark(self.win)
end
function Clock:onKey(k)
    if k==keys.e then self.mode=self.mode=="JST" and "MCT" or "JST"; cfg.clockMode=self.mode; self:update() end
end
function Clock:draw(c)
    local scale=c.w>=230 and 3 or (c.w>=160 and 2 or 1)
    c:text(10,10,self.mode=="JST" and "ASIA / TOKYO  UTC+09:00" or "MINECRAFT TIME",P.accent)
    local tw=Driver.measure(self.value,scale)
    c:text(max(6,(c.w-tw)/2),32,self.value,P.textPrimary,scale)
    c:text(10,40+scale*9,dateText(self.date).."  JST DATE",P.textSecondary)
    button(self,c,10,c.h-22,min(140,c.w-20),"E: JST / MCT",function() self:onKey(keys.e) end)
end
register("clock","Clock","CL",260,132,Clock)

end


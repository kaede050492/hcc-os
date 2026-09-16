-- HCC OS v1.5 GUI application module.
return function(E)
    local env=setmetatable({Driver=E.AppDriver,OS=E.AppOS},{__index=E})
    local _ENV=env
local function monthDays(y,m)
    if m==2 then return (y%4==0 and (y%100~=0 or y%400==0)) and 29 or 28 end
    return ({31,28,31,30,31,30,31,31,30,31,30,31})[m]
end
local function weekday(y,m,d)
    local t={0,3,2,5,0,3,5,1,4,6,2,4}
    if m<3 then y=y-1 end
    return (y+floor(y/4)-floor(y/100)+floor(y/400)+t[m]+d)%7
end
local Calendar={}
function Calendar:init() local d=jst(); self.year=d.year; self.month=d.month end
function Calendar:interval() return self.slide and 0.05 or 30 end
function Calendar:move(delta)
    local n=self.year*12+self.month-1+delta
    local y,m=floor(n/12),n%12+1
    if y<1 or y>9999 then return end
    self.slide={year=self.year,month=self.month,at=now(),direction=delta>0 and 1 or -1}
    self.year,self.month=y,m; self.win.nextUpdate=now(); mark(self.win)
end
function Calendar:update()
    if self.slide and now()-self.slide.at>=0.2 then self.slide=nil end
    mark(self.win)
end
function Calendar:onKey(k)
    if k==keys.left then self:move(-1) elseif k==keys.right then self:move(1)
    elseif k==keys.up then self:move(-12) elseif k==keys.down then self:move(12)
    elseif k==keys.home then self:init(); self.slide=nil; mark(self.win) end
end
function Calendar:drawMonth(c,y,m)
    local d=jst(); local cw=c.w/7; local ch=max(12,(c.h-17)/6)
    for i,s in ipairs({"SU","MO","TU","WE","TH","FR","SA"}) do c:text((i-1)*cw+4,2,s,i==1 and P.error or P.textSecondary) end
    local first=weekday(y,m,1)
    for day=1,monthDays(y,m) do
        local ix=first+day-1; local x=(ix%7)*cw; local yy=17+floor(ix/7)*ch
        if day==d.day and m==d.month and y==d.year then c:filledRectangle(x+1,yy,cw-2,ch-2,P.panelBackground); c:rectangle(x+1,yy,cw-2,ch-2,P.accent) end
        c:text(x+5,yy+3,tostring(day),P.textPrimary)
    end
end
function Calendar:draw(c)
    button(self,c,6,5,28,"<",function() self:move(-1) end)
    button(self,c,c.w-34,5,28,">",function() self:move(1) end)
    c:text(45,9,string.format("%04d / %02d",self.year,self.month),P.accent)
    local area=c:clipping(6,29,c.w-12,c.h-47)
    if self.slide then
        local t=clamp((now()-self.slide.at)/0.2,0,1); t=1-(1-t)^3
        local shift=floor(area.w*t)*self.slide.direction
        self:drawMonth(area:clipping(-shift,0,area.w,area.h),self.slide.year,self.slide.month)
        self:drawMonth(area:clipping(self.slide.direction*area.w-shift,0,area.w,area.h),self.year,self.month)
    else self:drawMonth(area,self.year,self.month) end
    c:text(6,c.h-13,"LEFT/RIGHT: MONTH  UP/DOWN: YEAR",P.textSecondary)
end
register("calendar","Calendar","CA",294,248,Calendar)

end

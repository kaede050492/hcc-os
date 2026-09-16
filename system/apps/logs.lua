-- HCC OS v1.4 GUI application module.
return function(E)
    local env=setmetatable({Driver=E.AppDriver,OS=E.AppOS},{__index=E})
    local _ENV=env
local LogViewer={}
function LogViewer:init() self.top=1; self.level="ALL"; self.query="" end
function LogViewer:visible()
    local out={}; local q=self.query:lower()
    for _,entry in ipairs(OS.logs) do if (self.level=="ALL" or entry.level==self.level) and (q=="" or entry.message:lower():find(q,1,true)) then out[#out+1]=entry end end
    return out
end
function LogViewer:search()
    dialog("Log search","Text filter (blank = all)",{"OK","Cancel"},function(b,value) if b=="OK" then self.query=value; self.top=1; mark(self.win) end end,self.query)
end
function LogViewer:clear()
    dialog("Clear log","Delete the in-memory event log?",{"Yes","No"},function(b) if b=="Yes" then clearLogs(); self.top=1; notify("Log cleared",P.warning); mark(self.win) end end)
end
function LogViewer:onKey(k)
    local entries=self:visible(); if k==keys.up then self.top=max(1,self.top-3) elseif k==keys.down then self.top=min(max(1,#entries),self.top+3) elseif k==keys.f5 then self.query=""; self.level="ALL" elseif k==keys.pageUp then self.top=max(1,self.top-10) elseif k==keys.pageDown then self.top=min(max(1,#entries),self.top+10) end; mark(self.win)
end
function LogViewer:onMouse(kind,x,y,b) if kind=="scroll" then self.top=clamp(self.top+b*3,1,max(1,#self:visible())); mark(self.win) end end
function LogViewer:draw(c)
    local entries=self:visible(); c:text(6,5,"LOG VIEWER",P.accent); c:text(6,19,self.level..(self.query~="" and " / "..self.query or ""),P.textSecondary)
    button(self,c,c.w-163,3,45,"ALL",function() self.level="ALL"; self.top=1; mark(self.win) end); button(self,c,c.w-113,3,48,"WARN",function() self.level="WARN"; self.top=1; mark(self.win) end); button(self,c,c.w-60,3,55,"ERROR",function() self.level="ERROR"; self.top=1; mark(self.win) end)
    local rows=max(1,floor((c.h-66)/13)); self.top=clamp(self.top,1,max(1,#entries-rows+1))
    for row=0,rows-1 do local e=entries[self.top+row]; if not e then break end; local y=35+row*13; local d=os.date("!*t",floor(e.time)+32400); local stamp=string.format("%02d:%02d:%02d",d.hour,d.min,d.sec); c:text(6,y,stamp.." "..e.level,e.level=="ERROR" and P.error or (e.level=="WARN" and P.warning or P.textSecondary)); c:text(91,y,e.message:sub(1,math.max(1,c.w-96)),P.textPrimary) end
    button(self,c,5,c.h-23,58,"SEARCH",function() self:search() end); button(self,c,68,c.h-23,51,"CLEAR",function() self:clear() end); c:text(125,c.h-18,#entries.." entries / F5 reset",P.textSecondary)
end
register("logs","Log Viewer","LG",540,260,LogViewer)

end


-- HCC OS v1.5 GUI application module.
return function(E)
    local env=setmetatable({Driver=E.AppDriver,OS=E.AppOS},{__index=E})
    local _ENV=env
local function historyPush(t,value) t[#t+1]=value; if #t>90 then table.remove(t,1) end end
local function healthColor(v,tps)
    if tps then return v>=19.5 and P.success or (v>=18 and P.warning or P.error) end
    return v<=50 and P.success or (v<=55 and P.warning or P.error)
end
local function graph(c,x,y,w,h,values,ceiling,color,threshold)
    c:rectangle(x,y,w,h,P.border)
    for i=1,3 do c:line(x+1,y+h*i/4,x+w-2,y+h*i/4,P.grid) end
    if threshold then c:line(x+1,y+h-2-clamp(threshold/ceiling,0,1)*(h-3),x+w-2,y+h-2-clamp(threshold/ceiling,0,1)*(h-3),P.warning) end
    local count=#values
    for i=2,count do
        local x1=x+1+(i-2)/89*(w-3); local x2=x+1+(i-1)/89*(w-3)
        local y1=y+h-2-clamp(values[i-1]/ceiling,0,1)*(h-3); local y2=y+h-2-clamp(values[i]/ceiling,0,1)*(h-3)
        c:line(x1,y1,x2,y2,color)
    end
end
local Server={}
function Server:init()
    self.mode="Estimated"; self.previous=now(); self.expected=cfg.serverInterval
    self.tpsHistory={}; self.tickHistory={}; self.manual={}; self.manualIndex=1; self.manualHistory={}
end
function Server:interval() return cfg.serverInterval end
function Server:resume()
    self.previous=now(); self.expected=cfg.serverInterval
    if self.mode=="Estimated" then self.tps=nil; self.tick=nil; self.tpsHistory={}; self.tickHistory={} end
end
function Server:update()
    local t=now(); local elapsed=t-self.previous; self.previous=t
    if self.mode=="Estimated" and elapsed>0 then
        self.tps=min(20,self.expected*20/elapsed)
        self.tick=elapsed*1000/(self.expected*20)
        historyPush(self.tpsHistory,self.tps); historyPush(self.tickHistory,self.tick)
    end
    self.expected=cfg.serverInterval; mark(self.win)
end
function Server:import()
    dialog("Manual sample","Paste /neoforge tps output, or: Overall 19.8 56",{"OK","Cancel"},function(b,value)
        if b~="OK" then return end
        local rows={}
        for line in (value.."\n"):gmatch("([^\r\n]+)") do
            local name,a,m=line:match("^%s*(.-):%s*([%d%.]+)%s*TPS%s*%(([%d%.]+)%s*ms/tick")
            if not a then name,a,m=line:match("^%s*(.-)%s+([%d%.]+)%s+([%d%.]+)%s*$") end
            a,m=tonumber(a),tonumber(m)
            if a and m and a>=0 and a<=20 and m>=0 and m<=100000 and name~="" then
                name=name:match("^%s*(.-)%s*$")
                local history=self.manualHistory[name] or {tps={},mspt={}}
                self.manualHistory[name]=history; historyPush(history.tps,a); historyPush(history.mspt,m)
                rows[#rows+1]={name=name,tps=a,mspt=m,at=now(),history=history}
            end
        end
        if #rows==0 then errorBox("Use: Overall 19.8 56 (TPS, MSPT in ms)"); return end
        self.manual=rows; self.manualIndex=1; self.mode="Manual"
        mark(self.win)
    end,"")
end
function Server:onKey(k)
    if k==keys.m then
        if self.mode=="Estimated" then if #self.manual==0 then self:import(); return end; self.mode="Manual"
        else self.mode="Estimated"; self.previous=now(); self.tps=nil; self.tick=nil; self.expected=cfg.serverInterval; self.win.nextUpdate=now() end
        if self.mode=="Estimated" then self.tpsHistory={}; self.tickHistory={} end
        mark(self.win)
    elseif k==keys.p then self:import()
    elseif (k==keys.left or k==keys.right) and self.mode=="Manual" and #self.manual>0 then
        self.manualIndex=(self.manualIndex-1+(k==keys.left and -1 or 1))%#self.manual+1
        mark(self.win)
    end
end
function Server:draw(c)
    local row=self.mode=="Manual" and self.manual[self.manualIndex] or nil
    local tps=row and row.tps or self.tps
    local value=row and row.mspt or self.tick
    local th=row and row.history.tps or self.tpsHistory
    local mh=row and row.history.mspt or self.tickHistory
    local source=row and ("Manual: "..row.name) or "Estimated: CC timer delivery"
    c:text(7,6,source,P.accent)
    c:text(7,20,tps and string.format("TPS: %.2f",tps) or "TPS: sampling...",tps and healthColor(tps,true) or P.textSecondary,c.w>=250 and 2 or 1)
    c:text(7,43,row and string.format("MSPT: %.2f ms",value) or "MSPT: Unavailable",row and healthColor(value,false) or P.warning)
    c:text(7,56,row and ("Age: "..floor(now()-row.at).."s  LEFT/RIGHT: dimension") or (value and string.format("Tick interval: %.2f ms (Estimated)",value) or "Waiting for timer sample"),P.textSecondary)
    local w=c.w-14
    c:filledRectangle(7,71,w,5,P.panelBackground)
    if tps then c:filledRectangle(7,71,w*clamp(tps/20,0,1),5,healthColor(tps,true)) end
    c:filledRectangle(7,81,w,5,P.panelBackground)
    if value then c:filledRectangle(7,81,w*clamp(value/100,0,1),5,row and healthColor(value,false) or P.accent) end
    local gh=max(12,floor((c.h-150)/2))
    c:text(7,92,"TPS 0-20 / last 90 samples",P.textSecondary)
    graph(c,7,104,w,gh,th,20,P.success)
    local yy=108+gh
    c:text(7,yy,row and "MSPT / 50ms reference" or "EST. INTERVAL / 50ms reference",P.textSecondary)
    local ceiling=100; for _,v in ipairs(mh) do ceiling=max(ceiling,v*1.1) end
    graph(c,7,yy+12,w,gh,mh,ceiling,P.accent,50)
    button(self,c,7,c.h-21,81,"M: SOURCE",function() self:onKey(keys.m) end)
    button(self,c,93,c.h-21,min(105,c.w-100),"P: PASTE DATA",function() self:import() end)
end
register("server","Server Monitor","SV",300,286,Server)

end

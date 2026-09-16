-- HCC OS v1.5 GUI application module.
return function(E)
    local env=setmetatable({Driver=E.AppDriver,OS=E.AppOS},{__index=E})
    local _ENV=env
local function dimension(s)
    if type(s)~="string" or s=="" then return "unknown" end
    local aliases={overworld="minecraft:overworld",the_nether="minecraft:the_nether",nether="minecraft:the_nether",
        the_end="minecraft:the_end",["end"]="minecraft:the_end"}
    return aliases[s:lower()] or s
end
local function rangeFor(distance)
    local r=256
    while r<distance*1.12 do r=r*2 end
    return r
end
local playerColors={0xFF46CFF0,0xFFFFC65B,0xFF60DA90,0xFFBA9FFF,0xFFFF839E,0xFF89AEFF}
local function playerColor(name)
    local n=0; for i=1,#name do n=(n*31+name:byte(i))%997 end
    return playerColors[n%#playerColors+1]
end
local MAX_SCAN_PLAYERS=128
local DETECTOR_CALL_TIMEOUT=1.25
local function playerNames(value)
    if type(value)~="table" then return nil,"Detector returned an invalid player list" end
    local names,seen={},{}
    for _,name in ipairs(value) do
        if type(name)=="string" and name~="" and not seen[name] then
            seen[name]=true; names[#names+1]=name
        end
    end
    table.sort(names)
    if #names>MAX_SCAN_PLAYERS then
        while #names>MAX_SCAN_PLAYERS do table.remove(names) end
    end
    return names
end
local Radar={}
function Radar:init()
    self.players={}; self.records={}; self.pendingNames={}; self.dim=dimension(cfg.dimension); self.dims={self.dim}; self.page=1; self.range=256
    self.scan=nil; self.call=nil; self.scanRequested=false; self.errorShown=false; self.online=0; self.unavailable=0; self.far=0; self.lastDetector=devices.detector
    self.message=nil; self.status=nil
    if devices.detector then self:requestScan() else self:detectorError("Player Detector is not connected.") end
end
function Radar:interval() return (self.scan or next(self.pendingNames)) and 0.05 or cfg.radarInterval end
function Radar:detectorError(message)
    self:cancelDetectorCall(); self.scan=nil; self.scanRequested=false; self.players={}; self.records={}; self.pendingNames={}; self.online=0; self.unavailable=0; self.far=0; self.status=nil; self.message=message or "Player Detector error"
    if not self.errorShown and type(dialog)=="function" then
        self.errorShown=true
        dialog("Player Detector Error",self.message.." Connect the peripheral and press SCAN again.",{"OK"})
    end
    mark(self.win)
end
function Radar:requestScan()
    self.errorShown=false; self.message=nil; self.status="Starting Player Detector scan..."; self.scanRequested=true
    if not devices.detector then self:detectorError("Player Detector is not connected."); return end
    self:cancelDetectorCall()
    self.scan={phase="online",names={},index=1,started=now(),method=nil}
    mark(self.win)
end
local function eventFields(name,a,b,c,d)
    if name=="playerJoin" or name=="playerLeave" or name=="playerClick" then return tostring(a or ""),nil end
    if name=="playerChangedDimension" then return tostring(a or ""),tostring(c or b or "") end
    if name=="player_join" or name=="player_leave" or name=="player_click" then return tostring(b or a or ""),tostring(c or "") end
    if name=="player_changed_dimension" then return tostring(b or a or ""),tostring(d or c or "") end
    if name=="player_death" then return tostring(b or a or ""),nil end
    return "",nil
end
function Radar:rebuildFromRecords()
    if not devices.detector then self:detectorError("Player Detector is not connected."); return end
    local list={}; local dims={[self.dim]=true}; local positioned=0; local far=0
    for _,record in pairs(self.records) do
        if record.dimension then dims[record.dimension]=true end
        local recordDim=record.dimension or "unknown"
        if recordDim==self.dim or recordDim=="unknown" then
            local item={name=record.name,x=record.x,y=record.y,z=record.z,yaw=record.yaw,dimension=recordDim,color=playerColor(record.name)}
            if finite(item.x) and finite(item.z) then
                local dx,dz=item.x-cfg.centerX,item.z-cfg.centerZ; item.distance=math.sqrt(dx*dx+dz*dz); far=max(far,item.distance); positioned=positioned+1
            end
            list[#list+1]=item
        end
    end
    table.sort(list,function(a,b) return tostring(a.name)<tostring(b.name) end)
    self.players=list; self.online=0; for _ in pairs(self.records) do self.online=self.online+1 end
    self.unavailable=max(0,#list-positioned); self.far=far; self.range=rangeFor(far)
    self.dims={}; for d in pairs(dims) do self.dims[#self.dims+1]=d end; table.sort(self.dims)
    if self.online==0 and not self.scan and not next(self.pendingNames) then self.message="No players online. Press SCAN to retry." end
    mark(self.win)
end
Radar.rebuildFromEvents=Radar.rebuildFromRecords
function Radar:cancelDetectorCall()
    local call=self.call; if not call then return end
    self.call=nil
    if call.timeout then pcall(os.cancelTimer,call.timeout) end
end
function Radar:finishDetectorCall(ok,value,reason)
    local call=self.call; if not call then return end
    self.call=nil
    if call.timeout then pcall(os.cancelTimer,call.timeout) end
    local callback=call.callback
    if type(callback)=="function" then
        local callbackOk,callbackError=pcall(callback,ok,value,reason)
        if not callbackOk then self:detectorError("Player Detector callback failed: "..tostring(callbackError)) end
    end
end
function Radar:resumeDetectorCall(...)
    local call=self.call; if not call then return false end
    local ok,a,b=coroutine.resume(call.co,...)
    if not ok then self:finishDetectorCall(false,nil,tostring(a)); return true end
    if coroutine.status(call.co)=="dead" then self:finishDetectorCall(a,b,nil); return true end
    call.filter=a
    return true
end
function Radar:startDetectorCall(method,args,callback)
    if self.call then return false end
    local detector=devices.detector
    local methodOk,fn=pcall(function() return detector and detector[method] end)
    if not methodOk or type(fn)~="function" then
        callback(false,nil,method.." is unavailable")
        return false
    end
    local call={filter=nil,callback=callback,timeout=nil}
    call.co=coroutine.create(function()
        local ok,value=pcall(fn,unpack(args or {}))
        return ok,value
    end)
    call.timeout=os.startTimer(DETECTOR_CALL_TIMEOUT)
    self.call=call
    self:resumeDetectorCall()
    return true
end
function Radar:beginOnlineScan()
    local scan=self.scan; if not scan or self.call then return end
    local method=(devices.detectorApi and devices.detectorApi.getOnlinePlayers) and "getOnlinePlayers" or
        ((devices.detectorApi and devices.detectorApi.getPlayersInRange) and "getPlayersInRange" or nil)
    if not method then self:detectorError("This Player Detector has no supported player-list API"); return end
    self.status="Querying online players..."; mark(self.win)
    local args=method=="getPlayersInRange" and {self.range} or {}
    self:startDetectorCall(method,args,function(ok,value,reason)
        if self.scan~=scan then return end
        if not ok then self:detectorError("Player Detector "..method.." failed: "..tostring(reason or value)); return end
        local names,normaliseError=playerNames(value)
        if not names then self:detectorError(normaliseError); return end
        scan.names=names; scan.method=method; self:beginPositionScan()
    end)
end
function Radar:beginPositionScan()
    local scan=self.scan; if not scan then return end
    self.records={}; self.pendingNames={}
    for _,name in ipairs(scan.names) do self.records[name]={name=name,color=playerColor(name)} end
    scan.phase="position"; scan.index=1
    self.online=#scan.names
    self.status=string.format("Reading positions 0/%d...",#scan.names)
    self:rebuildFromRecords()
end
function Radar:finishScan()
    self.scan=nil; self.scanRequested=false; self.status=nil
    if self.online==0 then self.message="No players online. Press SCAN to retry." else self.message=nil end
    self:rebuildFromRecords()
end
function Radar:stepScan()
    local scan=self.scan; if not scan or not devices.detector then return end
    if scan.phase=="online" then
        self:beginOnlineScan(); return
    end
    if self.call then return end
    if scan.index>#scan.names then self:finishScan(); return end
    local name=scan.names[scan.index]; local record=self.records[name]
    self.status=string.format("Reading positions %d/%d...",scan.index-1,#scan.names); mark(self.win)
    self:startDetectorCall("getPlayerPos",{name},function(ok,pos,reason)
        if self.scan~=scan then return end
        if ok and type(pos)=="table" then
            record.x,record.y,record.z,record.yaw=pos.x,pos.y,pos.z,pos.yaw
            record.dimension=dimension(pos.dimension or record.dimension); record.error=nil
        else record.error=reason or tostring(pos or "Position unavailable") end
        scan.index=scan.index+1; self:rebuildFromRecords()
        if scan.index>#scan.names then self:finishScan() end
    end)
end
function Radar:processPendingNames()
    if self.scan or self.call or not devices.detector then return end
    local name; for candidate in pairs(self.pendingNames) do name=candidate; break end
    if not name then return end
    self.pendingNames[name]=nil
    local record=self.records[name] or {name=name,color=playerColor(name)}; self.records[name]=record
    self:startDetectorCall("getPlayerPos",{name},function(ok,pos,reason)
        if ok and type(pos)=="table" then
            record.x,record.y,record.z,record.yaw=pos.x,pos.y,pos.z,pos.yaw; record.dimension=dimension(pos.dimension or record.dimension); record.error=nil
        else record.error=reason or tostring(pos or "Position unavailable") end
        self:rebuildFromRecords()
    end)
end
function Radar:onSystemEvent(name,a,b,c,d)
    local normalized=tostring(name or "")
    if self.call then
        if normalized=="timer" and a==self.call.timeout then
            self:cancelDetectorCall(); self:detectorError("Player Detector timed out. Scan cancelled."); return
        end
        if not self.call.filter or self.call.filter==normalized then
            if self:resumeDetectorCall(name,a,b,c,d) then return end
        end
    end
    if normalized=="player_join" or normalized=="playerJoin" or normalized=="player_click" or normalized=="playerClick" then
        local username,dim=eventFields(normalized,a,b,c,d); if username=="" then return end
        local record=self.records[username] or {name=username,color=playerColor(username)}
        if dim and dim~="" then record.dimension=dimension(dim) end
        self.records[username]=record; self.pendingNames[username]=true; self.message=nil; self:rebuildFromRecords(); return
    end
    if normalized=="player_leave" or normalized=="playerLeave" or normalized=="player_death" then
        local username=eventFields(normalized,a,b,c,d); if username~="" then self.records[username]=nil; self.pendingNames[username]=nil; self:rebuildFromRecords() end; return
    end
    if normalized=="player_changed_dimension" or normalized=="playerChangedDimension" then
        local username,dim=eventFields(normalized,a,b,c,d); if username=="" then return end
        local record=self.records[username] or {name=username,color=playerColor(username)}; record.dimension=dimension(dim); self.records[username]=record; self:rebuildFromEvents()
    end
end
function Radar:update()
    if devices.detector~=self.lastDetector then
        self.lastDetector=devices.detector; self.records={}; self.pendingNames={}; self.errorShown=false
        if devices.detector then self:requestScan() else self:detectorError("Player Detector is not connected."); return end
        mark(self.win)
    end
    if not devices.detector then return end
    if self.scan then self:stepScan() else self:processPendingNames() end
end
function Radar:cycleDimension()
    if #self.dims==0 then self.dims={self.dim} end
    local index=1; for i,d in ipairs(self.dims) do if d==self.dim then index=i end end
    self.dim=self.dims[index%#self.dims+1]; self.page=1; self:requestScan()
end
function Radar:onKey(k)
    if k==keys.g then cfg.grid=not cfg.grid; mark(self.win)
    elseif k==keys.d then self:cycleDimension()
    elseif k==keys.r then self:requestScan()
    elseif k==keys.right or k==keys.pageDown then self.page=self.page+1; mark(self.win)
    elseif k==keys.left or k==keys.pageUp then self.page=max(1,self.page-1); mark(self.win) end
end
function Radar:onMouse(kind,x,y,b) if kind=="scroll" then self.page=max(1,self.page+b); mark(self.win) end end
function Radar:draw(c)
    c:text(6,5,self.dim,P.accent)
    if self.message then
        c:paragraph(8,30,self.message,self.errorShown and P.error or P.warning,c.w-16,4)
        button(self,c,5,c.h-23,58,"SCAN",function() self:requestScan() end)
        c:text(69,c.h-19,"R: SCAN  D: DIM  G: GRID",P.textSecondary)
        return
    end
    local positioned=0; for _,player in ipairs(self.players) do if finite(player.x) and finite(player.z) then positioned=positioned+1 end end
    c:text(6,18,string.format("%d HERE / %d ONLINE  +/- %d",positioned,self.online or 0,self.range),P.textSecondary)
    if self.status then c:text(6,29,self.status,P.warning) end
    local listWidth=c.w>=340 and 146 or (c.w>=240 and 105 or 0)
    local map=c:clipping(5,34,c.w-listWidth-10,c.h-62)
    local cx,cy=map.w/2,map.h/2; local radius=max(1,min(map.w,map.h)/2-16)
    map:rectangle(0,0,map.w,map.h,P.border)
    if cfg.grid then
        for i=-2,2 do
            map:line(cx+i*radius/2,8,cx+i*radius/2,map.h-9,P.grid)
            map:line(8,cy+i*radius/2,map.w-9,cy+i*radius/2,P.grid)
        end
    end
    map:text(cx-3,3,"N",P.textSecondary); map:text(cx-3,map.h-12,"S",P.textSecondary)
    map:text(3,cy-4,"W",P.textSecondary); map:text(map.w-10,cy-4,"E",P.textSecondary)
    map:line(cx-3,cy,cx+3,cy,P.warning); map:line(cx,cy-3,cx,cy+3,P.warning)
    local occupied={}; local positions={}
    for i,p in ipairs(self.players) do
        if finite(p.x) and finite(p.z) then
            local x=cx+(p.x-cfg.centerX)/self.range*radius
            local y=cy+(p.z-cfg.centerZ)/self.range*radius
            positions[i]={x=x,y=y}; occupied[#occupied+1]=box(x-4,y-4,9,9)
        end
    end
    for i,p in ipairs(self.players) do
        local position=positions[i]
        if position then
            local x,y=position.x,position.y
            map:filledRectangle(x-2,y-2,5,5,p.color)
            if finite(p.yaw) then
                local angle=math.rad(p.yaw)
                map:line(x,y,x-math.sin(angle)*9,y+math.cos(angle)*9,p.color)
            end
            local label=p.name
            if Driver.measure(label)>map.w/2 then label=label:sub(1,8)..".." end
            local tw=Driver.measure(label)
            local offsets={{6,-12},{6,5},{-tw-6,-12},{-tw-6,5},{-tw/2,-24},{-tw/2,17}}
            for _,offset in ipairs(offsets) do
                local r=box(x+offset[1],y+offset[2],tw,10); local free=r.x>=12 and r.y>=14 and r.x+r.w<map.w-12 and r.y+r.h<map.h-12
                for _,used in ipairs(occupied) do if intersect(r,used) then free=false; break end end
                if free then map:text(r.x,r.y,label,p.color); occupied[#occupied+1]=r; break end
            end
        end
    end
    if listWidth>0 then
        local list=c:clipping(c.w-listWidth,34,listWidth-4,c.h-62)
        local rows=max(1,floor((list.h-14)/38)); local pages=max(1,math.ceil(#self.players/rows))
        self.page=clamp(self.page,1,pages)
        for row=1,rows do
            local p=self.players[(self.page-1)*rows+row]; if not p then break end
            local y=(row-1)*38
            list:text(0,y,p.name,p.color)
            if finite(p.x) and finite(p.z) then
                list:text(0,y+11,string.format("X%.0f Z%.0f",p.x,p.z),P.textSecondary)
                list:text(0,y+22,string.format("Y%s  %.0fb",finite(p.y) and tostring(floor(p.y)) or "?",p.distance or 0),P.textSecondary)
            else
                list:text(0,y+11,"POSITION PENDING",P.warning)
                list:text(0,y+22,tostring(p.dimension or "unknown"),P.textSecondary)
            end
        end
        list:text(0,list.h-12,self.page.."/"..pages.."  ARROWS",P.textSecondary)
    end
    button(self,c,5,c.h-23,58,"SCAN",function() self:requestScan() end)
    button(self,c,67,c.h-23,58,"D: DIM",function() self:cycleDimension() end)
    button(self,c,129,c.h-23,63,cfg.grid and "G: GRID+" or "G: GRID-",function() self:onKey(keys.g) end)
    c:text(199,c.h-19,"X"..cfg.centerX.." Z"..cfg.centerZ,P.textSecondary)
end
register("radar","Player Radar","RA",336,268,Radar)
E.dimension=dimension

end

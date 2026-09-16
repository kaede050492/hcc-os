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
local Radar={}
function Radar:init()
    -- Advanced Peripherals exposes player_join/player_leave/player_changed_dimension
    -- events. Keep a local roster from those events instead of synchronously
    -- calling a server-side peripheral method from the UI scheduler.
    self.players={}; self.records={}; self.dim=dimension(cfg.dimension); self.dims={self.dim}; self.page=1; self.range=256
    self.scanRequested=false; self.errorShown=false; self.online=0; self.unavailable=0; self.far=0; self.lastDetector=devices.detector
    if devices.detector then
        self.message="Player Detector ready. Waiting for player events."
    else
        self:detectorError("Player Detector is not connected.")
    end
end
function Radar:interval() return self.scanRequested and 0.05 or cfg.radarInterval end
function Radar:detectorError(message)
    self.scanRequested=false; self.players={}; self.online=0; self.unavailable=0; self.far=0; self.message=message or "Player Detector error"
    if not self.errorShown and type(dialog)=="function" then
        self.errorShown=true
        dialog("Player Detector Error",self.message.." Connect the peripheral and press SCAN again.",{"OK"})
    end
    mark(self.win)
end
function Radar:requestScan()
    self.errorShown=false; self.message="Refreshing event-based player scan..."; self.scanRequested=true
    if not devices.detector then self:detectorError("Player Detector is not connected."); return end
    mark(self.win)
end
local function eventFields(name,a,b,c,d)
    if name=="player_join" or name=="player_leave" then return tostring(b or ""),tostring(c or "") end
    if name=="player_changed_dimension" then return tostring(b or ""),tostring(d or "") end
    if name=="player_death" then return tostring(b or ""),nil end
    if name=="playerJoin" or name=="playerLeave" then return tostring(a or ""),tostring(b or "") end
    if name=="playerChangedDimension" then return tostring(a or ""),tostring(c or "") end
    return nil,nil
end
function Radar:rebuildFromEvents()
    self.scanRequested=false
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
    if self.online==0 then self.message="No player events received yet. Scan is non-blocking." else self.message=nil end
    mark(self.win)
end
function Radar:onSystemEvent(name,a,b,c,d)
    local normalized=tostring(name or "")
    if normalized=="player_join" or normalized=="playerJoin" then
        local username,dim=eventFields(normalized,a,b,c,d); if username=="" then return end
        self.records[username]={name=username,dimension=dimension(dim),color=playerColor(username)}; self:rebuildFromEvents(); return
    end
    if normalized=="player_leave" or normalized=="playerLeave" or normalized=="player_death" then
        local username=eventFields(normalized,a,b,c,d); if username~="" then self.records[username]=nil; self:rebuildFromEvents() end; return
    end
    if normalized=="player_changed_dimension" or normalized=="playerChangedDimension" then
        local username,dim=eventFields(normalized,a,b,c,d); if username=="" then return end
        local record=self.records[username] or {name=username,color=playerColor(username)}; record.dimension=dimension(dim); self.records[username]=record; self:rebuildFromEvents()
    end
end
function Radar:update()
    if devices.detector~=self.lastDetector then
        self.lastDetector=devices.detector; self.records={}; self.errorShown=false
        if devices.detector then self.message="Player Detector connected. Waiting for player events." else self:detectorError("Player Detector is not connected."); return end
        mark(self.win)
    end
    if not devices.detector then return end
    if self.scanRequested then self:rebuildFromEvents() end
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
    if self.message and not self.query then
        c:paragraph(8,30,self.message,self.errorShown and P.error or P.warning,c.w-16,4)
        button(self,c,5,c.h-23,58,"SCAN",function() self:requestScan() end)
        c:text(69,c.h-19,"R: SCAN  D: DIM  G: GRID",P.textSecondary)
        return
    end
    local positioned=0; for _,player in ipairs(self.players) do if finite(player.x) and finite(player.z) then positioned=positioned+1 end end
    c:text(6,18,string.format("%d HERE / %d ONLINE  +/- %d",positioned,self.online or 0,self.range),P.textSecondary)
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

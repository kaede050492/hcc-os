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
function Radar:init() self.players={}; self.dim=dimension(cfg.dimension); self.dims={self.dim}; self.page=1; self.range=256; self:update() end
function Radar:interval() return self.query and 0.05 or cfg.radarInterval end
function Radar:update()
    local detector=devices.detector
    if not detector then self.query=nil; self.players={}; self.message="Player Detector unavailable"; mark(self.win); return end
    if self.query then
        if self.query.detector~=detector then self.query=nil; return end
        local name=self.query.names[self.query.index]
        if name then
            local good,p=pcall(detector.getPlayerPos,name)
            if good and type(p)=="table" and finite(p.x) and finite(p.z) then
                local dim=dimension(p.dimension); self.query.dims[dim]=true
                if dim==self.dim and dim~="unknown" then
                    local dx,dz=p.x-cfg.centerX,p.z-cfg.centerZ
                    local distance=math.sqrt(dx*dx+dz*dz); self.query.far=max(self.query.far,distance)
                    self.query.players[#self.query.players+1]={name=name,x=p.x,y=p.y,z=p.z,yaw=p.yaw,distance=distance,color=playerColor(name)}
                end
            else self.query.unavailable=self.query.unavailable+1 end
            self.query.index=self.query.index+1; return
        end
        self.players=self.query.players; self.unavailable=self.query.unavailable; self.far=self.query.far
        self.dims={}; for d in pairs(self.query.dims) do self.dims[#self.dims+1]=d end; table.sort(self.dims)
        self.range=rangeFor(self.far); self.query=nil; mark(self.win); return
    end
    self.players={}; self.unavailable=0; self.online=0; self.message=nil
    local ok,names=pcall(detector.getOnlinePlayers)
    if not ok or type(names)~="table" then self.message="Detector read failed"; mark(self.win); return end
    table.sort(names); self.online=#names
    self.query={detector=detector,names=names,index=1,players={},unavailable=0,far=0,
        dims={[dimension(cfg.dimension)]=true,[self.dim]=true}}
    -- An empty server is a valid detector response.  Do not recurse here:
    -- calling update() again for an empty list caused an infinite recursion
    -- when Player Detector was connected but no players were online.
    if #names==0 then
        self.players={}; self.query=nil; self.dims={self.dim}; self.range=256
        mark(self.win)
        return
    end
    mark(self.win)
end
function Radar:cycleDimension()
    if #self.dims==0 then self.dims={self.dim} end
    local index=1; for i,d in ipairs(self.dims) do if d==self.dim then index=i end end
    self.dim=self.dims[index%#self.dims+1]; self.page=1; self:update()
end
function Radar:onKey(k)
    if k==keys.g then cfg.grid=not cfg.grid; mark(self.win)
    elseif k==keys.d then self:cycleDimension()
    elseif k==keys.right or k==keys.pageDown then self.page=self.page+1; mark(self.win)
    elseif k==keys.left or k==keys.pageUp then self.page=max(1,self.page-1); mark(self.win) end
end
function Radar:onMouse(kind,x,y,b) if kind=="scroll" then self.page=max(1,self.page+b); mark(self.win) end end
function Radar:draw(c)
    c:text(6,5,self.dim,P.accent)
    if self.message then c:paragraph(8,30,self.message,P.warning); return end
    c:text(6,18,string.format("%d HERE / %d ONLINE  +/- %d",#self.players,self.online,self.range),P.textSecondary)
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
        local x=cx+(p.x-cfg.centerX)/self.range*radius
        local y=cy+(p.z-cfg.centerZ)/self.range*radius
        positions[i]={x=x,y=y}; occupied[#occupied+1]=box(x-4,y-4,9,9)
    end
    for i,p in ipairs(self.players) do
        local x,y=positions[i].x,positions[i].y
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
    if listWidth>0 then
        local list=c:clipping(c.w-listWidth,34,listWidth-4,c.h-62)
        local rows=max(1,floor((list.h-14)/38)); local pages=max(1,math.ceil(#self.players/rows))
        self.page=clamp(self.page,1,pages)
        for row=1,rows do
            local p=self.players[(self.page-1)*rows+row]; if not p then break end
            local y=(row-1)*38
            list:text(0,y,p.name,p.color)
            list:text(0,y+11,string.format("X%.0f Z%.0f",p.x,p.z),P.textSecondary)
            list:text(0,y+22,string.format("Y%s  %.0fb",finite(p.y) and tostring(floor(p.y)) or "?",p.distance),P.textSecondary)
        end
        list:text(0,list.h-12,self.page.."/"..pages.."  ARROWS",P.textSecondary)
    end
    button(self,c,5,c.h-23,60,"D: DIM",function() self:cycleDimension() end)
    button(self,c,69,c.h-23,63,cfg.grid and "G: GRID+" or "G: GRID-",function() self:onKey(keys.g) end)
    c:text(139,c.h-19,"X"..cfg.centerX.." Z"..cfg.centerZ,P.textSecondary)
end
register("radar","Player Radar","RA",336,268,Radar)
E.dimension=dimension

end

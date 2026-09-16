-- HCC OS v1.5 GUI application module.
return function(E)
    local env=setmetatable({Driver=E.AppDriver,OS=E.AppOS},{__index=E})
    local _ENV=env
local NetworkManager={}
function NetworkManager:init() self.selected=1; self.channel=1; self.nodes={}; self:refresh() end
function NetworkManager:interval() return cfg.networkRefresh end
function NetworkManager:refresh()
    self.nodes={}
    for _,m in ipairs(devices.modems) do
        local open=false; if type(m.p.isOpen)=="function" then local ok,v=pcall(m.p.isOpen,self.channel); open=ok and v==true end
        self.nodes[#self.nodes+1]={name=m.name,type=m.wireless and "wireless modem" or "wired modem",open=open,localNode=true}
        if type(m.p.getNamesRemote)=="function" then local ok,names=pcall(m.p.getNamesRemote); if ok and type(names)=="table" then for _,remote in ipairs(names) do self.nodes[#self.nodes+1]={name=m.name.." -> "..tostring(remote),type="remote peripheral",remote=true} end end end
    end
    self.selected=clamp(self.selected,1,max(1,#self.nodes)); mark(self.win)
end
function NetworkManager:toggle()
    local node=self.nodes[self.selected]; if not node or node.remote then return end
    for _,m in ipairs(devices.modems) do if m.name==node.name then local ok,err=pcall(function() if node.open then m.p.close(self.channel) else m.p.open(self.channel) end end); if not ok then errorBox(err) else self:refresh(); notify((node.open and "Closed" or "Opened").." channel "..self.channel,P.success) end; return end end
end
function NetworkManager:onKey(k)
    if k==keys.up then self.selected=max(1,self.selected-1) elseif k==keys.down then self.selected=min(#self.nodes,self.selected+1)
    elseif k==keys.f5 then rescan(); self:refresh() elseif k==keys.enter then self:toggle() end; mark(self.win)
end
function NetworkManager:onMouse(kind,x,y,b)
    if kind=="scroll" then self.selected=clamp(self.selected+b,1,max(1,#self.nodes))
    elseif kind=="click" and y>=34 and y<self.win.h-30 then self.selected=clamp(1+floor((y-34)/17),1,max(1,#self.nodes)); self:toggle() end
    mark(self.win)
end
function NetworkManager:draw(c)
    c:text(6,5,"NETWORK MANAGER",P.accent); c:text(6,19,"Logical topology / attach-detach safe",P.textSecondary)
    local left=floor(c.w*0.57); c:line(left,31,left,c.h-28,P.border)
    for i,node in ipairs(self.nodes) do local y=34+(i-1)*17; if i==self.selected then c:filledRectangle(4,y,left-9,16,P.panelBackground) end; c:text(8,y+3,node.name:sub(1,27),P.textPrimary); c:text(left-70,y+3,node.remote and "REMOTE" or (node.open and "OPEN" or "CLOSED"),node.open and P.success or P.textSecondary) end
    local node=self.nodes[self.selected]; c:text(left+8,36,node and node.name or "No modem",P.textPrimary); c:text(left+8,54,node and node.type or "Attach a modem",P.textSecondary)
    c:text(left+8,75,"CHANNEL: "..self.channel,P.accent); c:text(left+8,91,"ENTER / click toggle",P.textSecondary)
    button(self,c,5,c.h-23,75,"F5 RESCAN",function() rescan(); self:refresh() end)
end
register("network","Network Manager","NW",500,250,NetworkManager)

end

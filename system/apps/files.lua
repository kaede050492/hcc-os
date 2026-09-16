-- HCC OS v1.4 GUI application module.
return function(E)
    local env=setmetatable({Driver=E.AppDriver,OS=E.AppOS},{__index=E})
    local _ENV=env
local Files={}
function Files:init() self.path="/"; self.selected=1; self.top=1; self:refresh() end
function Files:refresh()
    self.entries=fs.list(self.path)
    table.sort(self.entries,function(a,b)
        local ad,bd=fs.isDir(fs.combine(self.path,a)),fs.isDir(fs.combine(self.path,b))
        if ad~=bd then return ad end; return a:lower()<b:lower()
    end)
    self.selected=clamp(self.selected,1,max(1,#self.entries)); mark(self.win)
end
function Files:open()
    local name=self.entries[self.selected]; if not name then return end
    local path=fs.combine(self.path,name)
    if fs.isDir(path) then self.path=path; self.selected=1; self.top=1; self:refresh()
    elseif name:lower():match("%.hcci$") then openApp("image",path)
    else openApp("notepad",path) end
end
function Files:up() self.path=fs.getDir(self.path); if self.path=="" then self.path="/" end; self.selected=1; self.top=1; self:refresh() end
function Files:delete()
    local name=self.entries[self.selected]; if not name then return end
    local path=fs.combine(self.path,name)
    if fs.isDir(path) or fs.isReadOnly(path) then errorBox("Only writable files can be deleted here"); return end
    dialog("Delete file","Permanently delete "..path.."?",{"Yes","No"},function(b)
        if b=="Yes" then local ok,e=pcall(fs.delete,path); if ok then self:refresh(); notify("Deleted "..name,P.warning) else errorBox(e) end end
    end)
end
function Files:onKey(k)
    if k==keys.up then self.selected=max(1,self.selected-1)
    elseif k==keys.down then self.selected=min(#self.entries,self.selected+1)
    elseif k==keys.enter then self:open()
    elseif k==keys.backspace then self:up()
    elseif k==keys.delete then self:delete()
    elseif k==keys.f5 then self:refresh() end
    mark(self.win)
end
function Files:onMouse(kind,x,y,b)
    if kind=="scroll" then self.selected=clamp(self.selected+b*3,1,max(1,#self.entries))
    elseif kind=="click" and y>=39 and y<self.win.h-TITLE-16 and x<(self.listWidth or 150) then
        local i=self.top+floor((y-39)/14)
        if i<=#self.entries then
            local double=self.selected==i and self.lastClick and now()-self.lastClick<0.4
            self.selected=i; self.lastClick=now(); if double then self:open() end
        end
    end
    mark(self.win)
end
function Files:draw(c)
    button(self,c,5,4,36,"UP",function() self:up() end)
    button(self,c,45,4,45,"OPEN",function() self:open() end)
    button(self,c,94,4,48,"DEL",function() self:delete() end)
    button(self,c,146,4,45,"NEW",function() openApp("notepad") end)
    c:text(5,25,self.path,P.accent)
    local rows=max(1,floor((c.h-54)/14)); self.listWidth=c.w>=270 and floor(c.w*0.6) or c.w-5
    if self.selected<self.top then self.top=self.selected elseif self.selected>=self.top+rows then self.top=self.selected-rows+1 end
    local list=c:clipping(5,39,self.listWidth-10,c.h-54)
    for i=0,rows-1 do
        local name=self.entries[self.top+i]; if not name then break end
        if self.top+i==self.selected then list:filledRectangle(0,i*14,list.w,13,P.panelBackground) end
        list:text(3,i*14+2,(fs.isDir(fs.combine(self.path,name)) and "+ " or "  ")..name,P.textPrimary)
    end
    local name=self.entries[self.selected]
    if c.w>=270 and name then
        local right=c:clipping(self.listWidth+5,39,c.w-self.listWidth-10,c.h-54)
        local path=fs.combine(self.path,name); local dir=fs.isDir(path)
        right:text(0,0,"INFORMATION",P.accent); right:paragraph(0,18,name,P.textPrimary,right.w,3)
        right:text(0,61,dir and "DIRECTORY" or "FILE",P.textSecondary)
        if not dir then right:text(0,75,tostring(fs.getSize(path)).." bytes",P.textSecondary) end
        right:text(0,89,fs.isReadOnly(path) and "READ ONLY" or "WRITABLE",P.textSecondary)
    end
    c:text(5,c.h-13,#self.entries.." entries | ENTER open | F5 refresh",P.textSecondary)
end
register("files","Files","FI",398,254,Files)

end


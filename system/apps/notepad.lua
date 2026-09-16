-- HCC OS v1.4 GUI application module.
return function(E)
    local env=setmetatable({Driver=E.AppDriver,OS=E.AppOS},{__index=E})
    local _ENV=env
local Notepad={}
local function splitLines(s)
    local result={}; s=s:gsub("\r\n","\n"):gsub("\r","\n")
    for line in (s.."\n"):gmatch("(.-)\n") do result[#result+1]=line end
    return result
end
function Notepad:init(path)
    self.path=path; self.lines={""}; self.row=1; self.col=0; self.top=1; self.left=0; self.unsaved=false
    if path then
        local ok,data=pcall(readFile,path)
        if not ok then error(data) end
        self.lines=splitLines(data)
        -- Byte editing of UTF-8 could corrupt multi-byte characters. Preserve such
        -- files exactly and expose them as read-only, rather than corrupting data.
        self.readOnly=data:find("[^\009\010\013\032-\126]")~=nil or fs.isReadOnly(path)
        self.win.name=fs.getName(path)
    end
end
function Notepad:saveTo(path,confirmed)
    path=fs.combine("/",path)
    if path=="" or path=="/" or fs.isDir(path) then errorBox("Choose a file path"); return end
    if fs.exists(path) and path~=self.path and not confirmed then
        dialog("Overwrite file",path,{"Yes","No"},function(b) if b=="Yes" then self:saveTo(path,true) end end); return
    end
    local ok,err=pcall(function()
        local f,e=fs.open(path,"w"); if not f then error(e or "Cannot save") end
        local good,reason=pcall(f.write,table.concat(self.lines,"\n")); f.close(); if not good then error(reason) end
    end)
    if not ok then errorBox(err); return end
    self.path=path; self.win.name=fs.getName(path); self.unsaved=false; mark(self.win); taskDirty(); notify("Saved "..path,P.success)
end
function Notepad:save()
    if self.readOnly then errorBox("Read-only document"); return end
    if self.path then self:saveTo(self.path)
    else dialog("Save file","Enter a path",{"OK","Cancel"},function(b,value) if b=="OK" then self:saveTo(value) end end,"/note.txt") end
end
function Notepad:insert(s)
    if self.readOnly then return end
    s=s:gsub("\r\n","\n"):gsub("\r","\n"):gsub("[^\009\010\032-\126]","?"):gsub("\t","    ")
    local total=#s; for _,line in ipairs(self.lines) do total=total+#line+1 end
    if total>65536 then errorBox("Editor limit: 64 KiB"); return end
    local prefix=self.lines[self.row]:sub(1,self.col); local suffix=self.lines[self.row]:sub(self.col+1)
    local parts=splitLines(s)
    self.lines[self.row]=prefix..parts[1]
    if #parts==1 then self.lines[self.row]=self.lines[self.row]..suffix; self.col=self.col+#parts[1]
    else
        for i=2,#parts do table.insert(self.lines,self.row+i-1,parts[i]) end
        self.row=self.row+#parts-1; self.col=#parts[#parts]; self.lines[self.row]=self.lines[self.row]..suffix
    end
    self.unsaved=true; mark(self.win)
end
function Notepad:onChar(s) self:insert(s) end
function Notepad:onKey(k)
    if (OS.held[keys.leftCtrl] or OS.held[keys.rightCtrl]) and k==keys.s then self:save(); return end
    local line=self.lines[self.row]
    if k==keys.left then
        if self.col>0 then self.col=self.col-1 elseif self.row>1 then self.row=self.row-1; self.col=#self.lines[self.row] end
    elseif k==keys.right then
        if self.col<#line then self.col=self.col+1 elseif self.row<#self.lines then self.row=self.row+1; self.col=0 end
    elseif k==keys.up then self.row=max(1,self.row-1); self.col=min(self.col,#self.lines[self.row])
    elseif k==keys.down then self.row=min(#self.lines,self.row+1); self.col=min(self.col,#self.lines[self.row])
    elseif k==keys.home then self.col=0
    elseif k==keys["end"] then self.col=#line
    elseif k==keys.pageUp then self.row=max(1,self.row-(self.visibleRows or 8)); self.col=min(self.col,#self.lines[self.row])
    elseif k==keys.pageDown then self.row=min(#self.lines,self.row+(self.visibleRows or 8)); self.col=min(self.col,#self.lines[self.row])
    elseif not self.readOnly then
        if k==keys.enter then self:insert("\n"); return
        elseif k==keys.tab then self:insert("    "); return
        elseif k==keys.backspace then
            if self.col>0 then self.lines[self.row]=line:sub(1,self.col-1)..line:sub(self.col+1); self.col=self.col-1
            elseif self.row>1 then self.col=#self.lines[self.row-1]; self.lines[self.row-1]=self.lines[self.row-1]..line; table.remove(self.lines,self.row); self.row=self.row-1 end
            self.unsaved=true
        elseif k==keys.delete then
            if self.col<#line then self.lines[self.row]=line:sub(1,self.col)..line:sub(self.col+2)
            elseif self.row<#self.lines then self.lines[self.row]=line..table.remove(self.lines,self.row+1) end
            self.unsaved=true
        end
    end
    self.ensureCursor=true; mark(self.win)
end
function Notepad:onMouse(kind,x,y,b)
    if kind=="scroll" then
        if OS.held[keys.leftShift] or OS.held[keys.rightShift] then self.left=max(0,self.left+b*3)
        else self.top=clamp(self.top+b*3,1,max(1,#self.lines-(self.visibleRows or 1)+1)) end
        self.manualScroll=true
    elseif kind=="click" and y>=26 and y<(self.win.h-TITLE-16) then
        self.row=clamp(self.top+floor((y-26)/12),1,#self.lines)
        self.col=clamp(self.left+floor((x-6)/Driver.cellWidth),0,#self.lines[self.row]); self.ensureCursor=true
    end
    mark(self.win)
end
function Notepad:draw(c)
    button(self,c,5,4,48,"SAVE",function() self:save() end)
    c:text(61,8,self.readOnly and "READ ONLY (ASCII editor)" or (self.unsaved and "* UNSAVED" or "CTRL+S"),self.unsaved and P.warning or P.textSecondary)
    self.visibleRows=max(1,floor((c.h-43)/12)); local cols=max(1,floor((c.w-12)/Driver.cellWidth))
    if self.ensureCursor or (not self.manualScroll) then
        if self.row<self.top then self.top=self.row elseif self.row>=self.top+self.visibleRows then self.top=self.row-self.visibleRows+1 end
        if self.col<self.left then self.left=self.col elseif self.col>=self.left+cols then self.left=self.col-cols+1 end
    end
    self.ensureCursor=false; self.manualScroll=false
    local edit=c:clipping(6,26,c.w-12,c.h-43)
    for i=0,self.visibleRows-1 do
        local s=self.lines[self.top+i]; if not s then break end
        s=ascii(s)
        for j=1,cols do local ch=s:sub(self.left+j,self.left+j); if ch=="" then break end; edit:text((j-1)*Driver.cellWidth,i*12,ch,P.textPrimary) end
    end
    if OS.active==self.win and not self.readOnly then
        edit:line((self.col-self.left)*Driver.cellWidth,(self.row-self.top)*12,(self.col-self.left)*Driver.cellWidth,(self.row-self.top)*12+8,P.accent)
    end
    c:text(5,c.h-13,string.format("%d:%d  %s",self.row,self.col+1,self.path or "NEW FILE"),P.textSecondary)
end
register("notepad","Notepad","NP",400,268,Notepad)

end


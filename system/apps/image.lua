-- HCC OS v1.4 GUI application module.
return function(E)
    local env=setmetatable({Driver=E.AppDriver,OS=E.AppOS},{__index=E})
    local _ENV=env
local ImageViewer={}
function ImageViewer:init(path)
    self.mode="fit"; self.zoom=1; self.offsetX=0; self.offsetY=0; self.selected=1; self.path=nil; self.data=nil; self.error=nil
    self.images=imageList()
    if type(path)=="string" and path~="" then self:loadPath(path) elseif self.images[1] then self:loadPath(self.images[1]) end
end
function ImageViewer:loadPath(path)
    local data,err=imageRead(path); self.error=nil
    if not data then self.error=tostring(err); logLine("ERROR","Image load: "..self.error); mark(self.win); return false end
    self.path=path; self.data=data; self.offsetX=0; self.offsetY=0
    for i,v in ipairs(self.images or {}) do if v==path then self.selected=i end end
    mark(self.win); return true
end
function ImageViewer:refreshList() self.images=imageList(); self.selected=clamp(self.selected,1,max(1,#self.images)); if self.images[self.selected] then self:loadPath(self.images[self.selected]) end end
function ImageViewer:openDialog()
    dialog("Open HCC Image","Absolute .hcci path",{"Open","Cancel"},function(b,value)
        if b=="Open" then if not value:lower():match("%.hcci$") then value=value..".hcci" end; self:loadPath(value) end
    end,self.path or "/.hccos/images/image.hcci")
end
function ImageViewer:saveAs()
    if not self.data then return end
    dialog("Save HCC Image","Absolute .hcci path",{"Save","Cancel"},function(b,value)
        if b~="Save" then return end
        if not value:lower():match("%.hcci$") then value=value..".hcci" end
        local ok,err=imageWrite(value,self.data); if not ok then errorBox(err) else self.path=value; self:refreshList(); notify("Image saved",P.success) end
    end,self.path or "/.hccos/images/image.hcci")
end
function ImageViewer:importUrl()
    dialog("Import HCC Image","HTTP URL for a serialized HCC Image",{"GET","Cancel"},function(b,url)
        if b~="GET" then return end
        url=tostring(url or ""):gsub("%s+","")
        if not url:match("^https?://[^%s]+$") then errorBox("Only HTTP/HTTPS URLs are allowed"); return end
        if type(http)~="table" or type(http.get)~="function" then errorBox("CC:T HTTP API unavailable"); return end
        local ok,handle=pcall(http.get,url); if not ok or not handle then errorBox("HTTP image request failed"); return end
        local rok,body=pcall(handle.readAll); if handle.close then pcall(handle.close) end
        if not rok then errorBox("HTTP response could not be read"); return end
        local data,err
        if type(textutils.unserialize)=="function" then
            local uok,raw=pcall(textutils.unserialize,body or "")
            if uok then data,err=imageNormalize(raw) end
        end
        err=err or "Downloaded data is not HCC Image format"
        if not data then errorBox(err); return end
        self.data=data; self.path="/.hccos/images/imported_"..tostring(floor(now()))..".hcci"; local saved,se=imageWrite(self.path,data)
        if not saved then errorBox(se) else self:refreshList(); notify("HCC Image imported",P.success) end
    end,"https://example.com/image.hcci")
end
function ImageViewer:setWallpaper()
    if not self.data or not self.path then errorBox("Save the image before using it as wallpaper"); return end
    cfg.wallpaperPath=self.path; cfg.wallpaperMode=({fit=true,fill=true,center=true,tile=true})[self.mode] and self.mode or "fit"
    resetWallpaperCache(); local ok,err=saveConfig(); allDirty()
    if ok then notify("Wallpaper set: "..cfg.wallpaperMode,P.success) else errorBox(err) end
end
function ImageViewer:zoomBy(delta) self.mode="100"; self.zoom=clamp(self.zoom+delta,0.1,16); mark(self.win) end
function ImageViewer:onKey(k)
    if k==keys.left then self.offsetX=self.offsetX-8 elseif k==keys.right then self.offsetX=self.offsetX+8
    elseif k==keys.up then self.offsetY=self.offsetY-8 elseif k==keys.down then self.offsetY=self.offsetY+8
    elseif k==keys.f5 then self:refreshList()
    elseif k==keys.pageUp then self:zoomBy(0.25) elseif k==keys.pageDown then self:zoomBy(-0.25)
    elseif k==keys.enter and self.images[self.selected] then self:loadPath(self.images[self.selected]) end
    mark(self.win)
end
function ImageViewer:onMouse(kind,x,y,b)
    if kind=="scroll" then self:zoomBy(b>0 and 0.25 or -0.25)
    elseif kind=="click" and y>=34 and y<self.win.h-35 and x<155 then local i=1+floor((y-34)/17); if self.images[i] then self.selected=i; self:loadPath(self.images[i]) end end
    mark(self.win)
end
function ImageViewer:draw(c)
    c:text(6,5,"IMAGE VIEWER",P.accent); c:text(6,19,self.path or "No .hcci selected",P.textSecondary)
    button(self,c,5,33,42,"OPEN",function() self:openDialog() end); button(self,c,51,33,48,"SAVE",function() self:saveAs() end)
    button(self,c,103,33,41,"FIT",function() self.mode="fit"; self.zoom=1; self.offsetX=0; self.offsetY=0; mark(self.win) end)
    button(self,c,c.w-70,3,65,"IMPORT",function() self:importUrl() end)
    local left=155; c:line(left,31,left,c.h-28,P.border)
    local rows=max(1,floor((c.h-70)/17)); for i=1,min(rows,#self.images) do local y=34+(i-1)*17; if i==self.selected then c:filledRectangle(4,y,left-9,16,P.panelBackground) end; c:text(8,y+3,fs.getName(self.images[i]):sub(1,20),P.textPrimary) end
    local preview=c:clipping(left+5,33,c.w-left-10,c.h-62); Widget.panel(preview,0,0,preview.w,preview.h,0xFF050505,P.border)
    if self.data then drawImage(preview,self.data,2,2,preview.w-4,preview.h-4,self.mode,self.zoom,self.offsetX,self.offsetY)
    elseif self.error then preview:paragraph(8,18,"Image error: "..self.error,P.error,preview.w-16,4)
    else preview:text(8,18,"Open an HCC Image (.hcci)",P.textSecondary) end
    button(self,c,left+5,c.h-24,45,"FILL",function() self.mode="fill"; self.zoom=1; mark(self.win) end)
    button(self,c,left+54,c.h-24,48,"100%",function() self.mode="100"; self.zoom=1; self.offsetX=0; self.offsetY=0; mark(self.win) end)
    button(self,c,left+106,c.h-24,34,"+",function() self:zoomBy(0.25) end)
    button(self,c,left+144,c.h-24,34,"-",function() self:zoomBy(-0.25) end)
    button(self,c,left+182,c.h-24,60,"CENTER",function() self.offsetX=0; self.offsetY=0; mark(self.win) end)
    button(self,c,left+247,c.h-24,75,"WALLPAPER",function() self:setWallpaper() end)
    c:text(6,c.h-13,"F5 refresh  arrows pan  PgUp/PgDn zoom",P.textSecondary)
end
register("image","Image Viewer","IM",530,282,ImageViewer)

end

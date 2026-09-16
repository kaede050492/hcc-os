-- HCC OS v1.5 GUI application module.
return function(E)
    local env=setmetatable({Driver=E.AppDriver,OS=E.AppOS},{__index=E})
local _ENV=env
local function nativeDecode(body)
    if type(E.imageDecodeNativePng)=="function" then return E.imageDecodeNativePng(body) end
    return nil,"Tom's GPU native PNG backend unavailable"
end
local function nativeFree(record)
    if type(E.imageFreeNativePng)=="function" then pcall(E.imageFreeNativePng,record) end
end
local function nativeStage(body,key)
    if type(E.imageStageNativePng)=="function" then
        local ok,path,reason=pcall(E.imageStageNativePng,body,key)
        if ok then return path,reason end
        return nil,tostring(path)
    end
    return nil,"Tom's GPU PNG staging backend unavailable"
end
local function nativeDelete(path)
    if type(E.imageDeleteNativePng)=="function" then pcall(E.imageDeleteNativePng,path); return true end
    return false,"Tom's GPU PNG cleanup backend unavailable"
end
local function persistNativePng(path,key)
    if type(E.imagePersistNativePng)=="function" then
        local ok,result,reason=pcall(E.imagePersistNativePng,path,key)
        if ok then return result,reason end
        return nil,tostring(result)
    end
    return nil,"PNG wallpaper storage unavailable"
end
local function imageKind(path,contentType)
    local c=tostring(contentType or ""):lower():match("^[^;]+") or ""; local p=tostring(path or ""):lower()
    if c=="image/png" or p:match("%.png$") or p:match("%.png[?#]") then return "png" end
    if c=="image/jpeg" or c=="image/jpg" or p:match("%.jpe?g$") or p:match("%.jpe?g[?#]") then return "jpeg" end
    if c=="image/hcci" or p:match("%.hcci$") or p:match("%.hcci[?#]") then return "hcci" end
end
local function responseHeaders(handle)
    local out={}
    if handle and type(handle.getResponseHeaders)=="function" then
        local ok,headers=pcall(handle.getResponseHeaders)
        if ok and type(headers)=="table" then for key,value in pairs(headers) do out[tostring(key):lower()]=tostring(value) end end
    end
    return out
end
local ImageViewer={}
function ImageViewer:init(path)
    self.mode="fit"; self.zoom=1; self.offsetX=0; self.offsetY=0; self.selected=1; self.path=nil; self.data=nil; self.nativeImage=nil; self.error=nil; self.status="Ready"; self.importJob=nil
    self.images=imageList()
    if type(path)=="string" and path~="" then self:loadPath(path) elseif self.images[1] then self:loadPath(self.images[1]) end
end
function ImageViewer:releaseNative()
    if self.nativeImage then nativeFree(self.nativeImage); self.nativeImage=nil end
end
function ImageViewer:loadPath(path)
    self:cancelImport(); self:releaseNative(); self.error=nil; self.status="Loading..."
    path=tostring(path or "")
    local ok,result,reason=xpcall(function()
        local kind=imageKind(path)
        if kind=="png" or kind=="jpeg" then
            local readOk,body=pcall(readFile,path,cfg.maxImageDownload)
            if not readOk then return nil,tostring(body) end
            local availableW=max(1,(self.win and self.win.w or 530)-165); local availableH=max(1,(self.win and self.win.h or 282)-80)
            if kind=="png" then
                local nativeOk,native,nativeError=pcall(nativeDecode,body)
                if not nativeOk then native=nil; nativeError=tostring(native) end
                if native and native.width<=availableW and native.height<=availableH then return {native=native},nil end
                if native then nativeFree(native) end
                local decodedOk,decoded=pcall(pngDecode,body)
                if not decodedOk then return nil,tostring(decoded) end
                local preparedOk,data=pcall(imagePrepare,decoded,availableW,availableH)
                if not preparedOk or not data then return nil,tostring(preparedOk and "image resize failed" or data) end
                return {data=data},nil
            end
            local decodedOk,decoded=pcall(jpegDecode,body)
            if not decodedOk then return nil,tostring(decoded) end
            local preparedOk,data=pcall(imagePrepare,decoded,availableW,availableH)
            if not preparedOk or not data then return nil,tostring(preparedOk and "image resize failed" or data) end
            return {data=data},nil
        end
        local data,err=imageRead(path)
        if not data then return nil,tostring(err) end
        return {data=data},nil
    end,function(value) return tostring(value) end)
    if not ok then reason=tostring(result or "unknown image error"); result=nil end
    if not result then
        self.status="Image load failed"; self.error=tostring(reason or "unknown image error"); logLine("ERROR","Image load: "..self.error); mark(self.win); return false
    end
    self.path=path; self.data=result.data; self.nativeImage=result.native; self.offsetX=0; self.offsetY=0; self.status="Image ready"
    for i,v in ipairs(self.images or {}) do if v==path then self.selected=i end end
    mark(self.win); return true
end
function ImageViewer:refreshList() self.images=imageList(); self.selected=clamp(self.selected,1,max(1,#self.images)); if self.images[self.selected] then self:loadPath(self.images[self.selected]) end end
function ImageViewer:openDialog()
    dialog("Open Image","Absolute .hcci, .png or .jpeg path",{"Open","Cancel"},function(b,value)
        if b=="Open" then self:loadPath(value) end
    end,self.path or "/.hccos/images/image.hcci")
end
function ImageViewer:saveAs()
    if self.nativeImage and self.path then
        dialog("Save PNG Image","Absolute .png path",{"Save","Cancel"},function(b,value)
            if b~="Save" then return end
            value=tostring(value or ""); if not value:lower():match("%.png$") then value=value..".png" end
            local ok,err=pcall(function()
                local dir=fs.getDir(value); if dir~="" and not fs.exists(dir) then fs.makeDir(dir) end
                fs.copy(self.path,value)
            end)
            if not ok then errorBox(err) else self.path=value; self.status="PNG saved"; self:refreshList(); notify("PNG image saved",P.success) end
        end,self.path)
        return
    end
    if not self.data then return end
    dialog("Save HCC Image","Absolute .hcci path",{"Save","Cancel"},function(b,value)
        if b~="Save" then return end
        value=tostring(value or ""); if not value:lower():match("%.hcci$") then value=value..".hcci" end
        local ok,err=imageWrite(value,self.data); if not ok then errorBox(err) else self.path=value; self.status="HCCI saved"; self:refreshList(); notify("Image saved",P.success) end
    end,self.path or "/.hccos/images/image.hcci")
end
function ImageViewer:interval()
    return self.importJob and (self.importJob.stage=="wait" and 0.25 or 0.05) or 1
end
function ImageViewer:cancelImport(message)
    if self.importJob and self.importJob.handle and self.importJob.handle.close then pcall(self.importJob.handle.close) end
    self.importJob=nil
    if message then self.status=message; mark(self.win) end
end
function ImageViewer:importError(message)
    self:cancelImport()
    self.status="Import failed"; self.error=tostring(message or "unknown image import error"); logLine("ERROR","Image import: "..self.error); mark(self.win); errorBox(self.error)
end
function ImageViewer:finishImportData(data)
    if not data then self:importError("Downloaded data could not be converted to an image"); return end
    local path="/.hccos/images/imported_"..tostring(floor(now()*1000))..".hcci"
    local saved,saveError=imageWrite(path,data)
    if not saved then self:importError("Image was decoded but could not be saved: "..tostring(saveError)); return end
    self.data=data; self.path=path; self.nativeImage=nil; self.error=nil; self.status="Image imported and saved"; self.images=imageList()
    for i,value in ipairs(self.images) do if value==path then self.selected=i end end
    mark(self.win); notify("Image imported and saved",P.success)
end
function ImageViewer:startImportBody(job,body)
    body=tostring(body or "")
    if #body==0 then self:importError("Downloaded image is empty"); return end
    if #body>cfg.maxImageDownload then self:importError("Downloaded image exceeds the configured size limit"); return end
    local kind=imageKind(job.url,job.contentType)
    if not kind then self:importError("Unsupported image format (PNG, JPEG or HCCI required)"); return end
    local availableW=max(1,(self.win and self.win.w or 530)-165); local availableH=max(1,(self.win and self.win.h or 282)-80)
    if kind=="png" then
        local nativeOk,native,nativeError=pcall(nativeDecode,body)
        if not nativeOk then native=nil; nativeError=tostring(native) end
        if native and native.width<=availableW and native.height<=availableH then
            local tempPath,stageError=nativeStage(body,job.url)
            if tempPath then
                local storeOk,stored,storeError=pcall(persistNativePng,tempPath,job.url)
                if not storeOk then stored=nil; storeError=tostring(stored or "PNG persistence failed") end
                nativeDelete(tempPath)
                if stored then
                    self:cancelImport(); self:releaseNative(); self.nativeImage=native; self.data=nil; self.path=stored; self.error=nil; self.status="PNG imported and saved"; self.images=imageList()
                    for i,value in ipairs(self.images) do if value==stored then self.selected=i end end
                    mark(self.win); notify("PNG image imported and saved",P.success); return
                end
                nativeFree(native); nativeError=storeError
            else
                nativeFree(native); nativeError=stageError
            end
        elseif native then
            nativeFree(native); nativeError="native PNG exceeds the available viewer area"
        end
        self.importNotice=nativeError and tostring(nativeError):sub(1,72) or nil
    end
    local co=coroutine.create(function()
        local decoded
        if kind=="png" then decoded=pngDecode(body,function(p) coroutine.yield("Decoding PNG...",p) end)
        elseif kind=="jpeg" then decoded=jpegDecode(body,function(p) coroutine.yield("Decoding JPEG...",p) end)
        else
            local parsedOk,raw=pcall(textutils.unserialize,body)
            if not parsedOk then error(raw) end
            local normalized,normalizeError=imageNormalize(raw)
            if not normalized then error(normalizeError or "invalid HCCI image") end
            decoded=normalized
        end
        local data=imagePrepare(decoded,availableW,availableH,function(stage,p) coroutine.yield(stage,p) end)
        return data
    end)
    self.importJob={stage="convert",co=co}; self.status="Converting image... 0%"; mark(self.win)
end
function ImageViewer:onHttpSuccess(url,handle)
    local job=self.importJob
    if not job or job.url~=url then if handle and handle.close then pcall(handle.close) end; return false end
    if type(handle)~="table" then self:importError("HTTP response handle is invalid"); return true end
    local headers=responseHeaders(handle); local length=tonumber(headers["content-length"] or "")
    if length and length>cfg.maxImageDownload then if handle.close then pcall(handle.close) end; self:importError("Downloaded image exceeds the configured size limit"); return true end
    job.handle=handle; job.contentType=headers["content-type"] or ""; job.length=length; job.bytes=0; job.parts={}
    if type(handle.readAll)=="function" then
        local ok,body=pcall(handle.readAll); if handle.close then pcall(handle.close) end
        if not ok then self:importError("HTTP response body could not be read"); return true end
        local processed,processError=pcall(self.startImportBody,self,job,body)
        if not processed then self:importError("Image processing failed: "..tostring(processError)) end
        return true
    end
    if type(handle.read)~="function" then self:importError("HTTP response has no readable body"); return true end
    job.stage="download"; self.status="Downloading... 0%"; mark(self.win); return true
end
function ImageViewer:onHttpFailure(url,reason)
    if not self.importJob or self.importJob.url~=url then return false end
    self:importError("HTTP request failed: "..tostring(reason or "unknown error")); return true
end
function ImageViewer:update()
    local job=self.importJob; if not job then return end
    if job.stage=="wait" then
        if now()-(job.startedAt or now())>30 then self:importError("HTTP request timed out") end
        return
    end
    if job.stage=="download" then
        local chunk; local ok=pcall(function() chunk=job.handle.read(16384) end)
        if not ok then self:importError("HTTP response body could not be read"); return end
        if chunk and #chunk>0 then
            job.parts[#job.parts+1]=chunk; job.bytes=job.bytes+#chunk
            if job.bytes>cfg.maxImageDownload then self:importError("Downloaded image exceeds the configured size limit"); return end
            self.status="Downloading... "..tostring(job.length and floor(clamp(job.bytes/job.length,0,1)*100+0.5) or 0).."%"; mark(self.win); return
        end
        if job.handle.close then pcall(job.handle.close) end
        local processed,processError=pcall(self.startImportBody,self,job,table.concat(job.parts))
        if not processed then self:importError("Image processing failed: "..tostring(processError)) end
        return
    end
    if job.stage=="convert" then
        local ok,a,b=coroutine.resume(job.co)
        if not ok then self:importError("Image conversion failed: "..tostring(a)); return end
        if coroutine.status(job.co)=="dead" then self:cancelImport(); self:finishImportData(a)
        else self.status=tostring(a or "Converting image...").." "..tostring(floor(clamp(tonumber(b) or 0,0,1)*100+0.5)).."%"; mark(self.win) end
    end
end
function ImageViewer:importUrl()
    dialog("Import Image","HTTP URL for PNG, JPEG or HCCI",{"GET","Cancel"},function(b,url)
        if b~="GET" then return end
        url=tostring(url or ""):gsub("%s+","")
        if not url:match("^https?://[^%s]+$") then errorBox("Only HTTP/HTTPS URLs are allowed"); return end
        if type(http)~="table" or type(http.request)~="function" then errorBox("CC:T HTTP request API unavailable"); return end
        self:cancelImport(); self:releaseNative(); self.error=nil; self.importNotice=nil; self.status="Downloading... 0%"
        local ok,accepted=pcall(http.request,url,nil,{["User-Agent"]="HCC-Image-Viewer/1.5"},true)
        if not ok or accepted==false or accepted==nil then self:importError("HTTP image request failed or was denied"); return end
        self.importJob={stage="wait",url=url,startedAt=now()}; mark(self.win)
    end,"https://example.com/image.png")
end
function ImageViewer:setWallpaper()
    if self.nativeImage and self.path then
        local path,storeError=persistNativePng(self.path,self.path)
        if not path then errorBox(storeError); return end
        cfg.wallpaperPath=path; cfg.wallpaperMode="center"
        resetWallpaperCache(); local ok,err=saveConfig(); allDirty()
        if ok then notify("PNG wallpaper set (center)",P.success) else errorBox(err) end
        return
    end
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
    if self.nativeImage then preview:nativeImage(2,2,self.nativeImage,"center")
    elseif self.data then drawImage(preview,self.data,2,2,preview.w-4,preview.h-4,self.mode,self.zoom,self.offsetX,self.offsetY)
    elseif self.error then preview:paragraph(8,18,"Image error: "..self.error,P.error,preview.w-16,4)
    else preview:text(8,18,self.error and ("Image error: "..self.error) or "Open an HCC Image, PNG or JPEG",self.error and P.error or P.textSecondary) end
    button(self,c,left+5,c.h-24,45,"FILL",function() self.mode="fill"; self.zoom=1; mark(self.win) end)
    button(self,c,left+54,c.h-24,48,"100%",function() self.mode="100"; self.zoom=1; self.offsetX=0; self.offsetY=0; mark(self.win) end)
    button(self,c,left+106,c.h-24,34,"+",function() self:zoomBy(0.25) end)
    button(self,c,left+144,c.h-24,34,"-",function() self:zoomBy(-0.25) end)
    button(self,c,left+182,c.h-24,60,"CENTER",function() self.offsetX=0; self.offsetY=0; mark(self.win) end)
    button(self,c,left+247,c.h-24,75,"WALLPAPER",function() self:setWallpaper() end)
    c:text(6,c.h-13,self.status or "F5 refresh  arrows pan  PgUp/PgDn zoom",self.error and P.error or P.textSecondary)
end
function ImageViewer:close() self:cancelImport(); self:releaseNative() end
register("image","Image Viewer","IM",530,282,ImageViewer)

end

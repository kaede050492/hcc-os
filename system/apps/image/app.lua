-- HCC OS v1.5 GUI application module.
return function(E)
    local env=setmetatable({Driver=E.AppDriver,OS=E.AppOS},{__index=E})
local _ENV=env
local storagePaths=E.paths or {}
local imageStorage=storagePaths.images or "/.hccos/images"
local function imageDiagnostic(level,stage,message)
    if type(E.imageDiagnostic)=="function" then pcall(E.imageDiagnostic,level,stage,message)
    elseif type(logLine)=="function" then pcall(logLine,level,"IMAGE "..tostring(stage).." "..tostring(message)) end
end
local function traceError(value)
    local message=tostring(value or "unknown image error")
    if type(debug)=="table" and type(debug.traceback)=="function" then
        local ok,trace=pcall(debug.traceback,message,3)
        if ok and type(trace)=="string" and trace~="" then message=trace end
    end
    return message
end
local function traceCoroutine(co,value)
    if type(debug)=="table" and type(debug.traceback)=="function" and co then
        local ok,trace=pcall(debug.traceback,co,tostring(value or "unknown image error"))
        if ok and type(trace)=="string" and trace~="" then return trace end
    end
    return traceError(value)
end
local function nativeDecode(body)
    if type(E.imageDecodeNativePng)=="function" then return E.imageDecodeNativePng(body) end
    return nil,"Tom's GPU native PNG backend unavailable"
end
local function resizePng(data,width,height)
    if type(E.imageResize)=="function" then return E.imageResize(data,width,height) end
    return imagePrepare(data,width,height)
end
local function httpCacheLoad(url)
    if type(E.imageHttpCacheLoad)~="function" then return nil,nil end
    local ok,body,meta=pcall(E.imageHttpCacheLoad,url,cfg.maxImageDownload)
    if ok then return body,meta end
    return nil,nil
end
local function httpCacheSave(url,body,kind,headers)
    if type(E.imageHttpCacheSave)~="function" then return false end
    local ok,saved=pcall(E.imageHttpCacheSave,url,body,kind,headers)
    return ok and saved==true
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
local function writeRawPng(path,body)
    if type(path)~="string" or path=="" or type(body)~="string" or #body==0 then return false,"invalid PNG data" end
    local ok,err=pcall(function()
        local dir=fs.getDir(path); if dir~="" and not fs.exists(dir) then fs.makeDir(dir) end
        local f,e=fs.open(path,"wb"); if not f then error(e or "PNG is not writable") end
        local wrote,writeError=pcall(f.write,body); f.close(); if not wrote then error(writeError) end
    end)
    return ok,err
end
local function imagePathFor(filename,required)
    local roots={imageStorage}; local seen={[imageStorage]=true}
    for _,mount in ipairs(storagePaths.storageMounts or {}) do
        local root=fs.combine(mount,"hccos/images")
        if not seen[root] then seen[root]=true; roots[#roots+1]=root end
    end
    for _,root in ipairs(roots) do
        local ok,free=pcall(fs.getFreeSpace,root)
        if ok and (free=="unlimited" or (type(free)=="number" and free>=tonumber(required or 0)+4096)) then return fs.combine(root,filename) end
    end
    return fs.combine(imageStorage,filename)
end
local function saveRawPngDialog(body,defaultPath)
    dialog("Save PNG Image","Absolute .png path",{"Save","Cancel"},function(b,value)
        if b~="Save" then return end
        value=tostring(value or ""); if not value:lower():match("%.png$") then value=value..".png" end
        local ok,err=writeRawPng(value,body)
        if ok then notify("PNG image saved",P.success) else
            imageDiagnostic("WARN","viewer.save_png", "primary path failed: "..tostring(err))
            local filename=value:match("([^/]+)$") or "image.png"; local fallback=imagePathFor(filename,#body)
            if fallback~=value then
                imageDiagnostic("INFO","viewer.save_png", "trying storage fallback: "..fallback)
                ok,err=writeRawPng(fallback,body)
                if ok then notify("PNG image saved to "..fallback,P.success); return end
                imageDiagnostic("ERROR","viewer.save_png", "fallback path failed: "..tostring(err))
            end
            errorBox(err)
        end
    end,defaultPath)
end
local function imageKind(path,contentType)
    local c=tostring(contentType or ""):lower():match("^[^;]+") or ""; local p=tostring(path or ""):lower()
    if c=="image/png" or p:match("%.png$") or p:match("%.png[?#]") then return "png" end
    if c=="image/jpeg" or c=="image/jpg" or p:match("%.jpe?g$") or p:match("%.jpe?g[?#]") then return "jpeg" end
    if c=="image/qoi" or c=="image/x-qoi" or p:match("%.qoi$") or p:match("%.qoi[?#]") then return "qoi" end
    if c=="image/hcci" or p:match("%.hcci$") or p:match("%.hcci[?#]") then return "hcci" end
end
local function pngSignature(body) return type(body)=="string" and body:sub(1,8)=="\137PNG\r\n\26\n" end
local function qoiSignature(body) return type(E.qoiSignature)=="function" and E.qoiSignature(body) or type(body)=="string" and body:sub(1,4)=="qoif" end
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
    self.mode="fit"; self.zoom=1; self.offsetX=0; self.offsetY=0; self.selected=1; self.path=nil; self.data=nil; self.rawPngBody=nil; self.importRawPng=nil; self.nativeImage=nil; self.error=nil; self.status="Ready"; self.importJob=nil
    self.images=imageList()
    if type(path)=="string" and path~="" then self:loadPath(path) elseif self.images[1] then self:loadPath(self.images[1]) end
end
function ImageViewer:releaseNative()
    if self.nativeImage then nativeFree(self.nativeImage); self.nativeImage=nil end
end
function ImageViewer:loadPath(path)
    self:cancelImport(); self:releaseNative(); self.rawPngBody=nil; self.importRawPng=nil; self.error=nil; self.status="Loading..."
    path=tostring(path or "")
    imageDiagnostic("INFO","viewer.load", "path="..path)
    local ok,result,reason=xpcall(function()
        local kind=imageKind(path)
        if kind=="qoi" then
            local availableW=max(1,(self.win and self.win.w or 530)-165); local availableH=max(1,(self.win and self.win.h or 282)-80)
            local loaded,loadError=imageLoadQoi(path,availableW,availableH)
            if not loaded then imageDiagnostic("ERROR","viewer.qoi",path..": "..tostring(loadError)); return nil,tostring(loadError) end
            return {data=loaded},nil
        end
        if kind=="png" or kind=="jpeg" then
            local readOk,body=pcall(readFile,path,cfg.maxImageDownload)
            if not readOk then imageDiagnostic("ERROR","viewer.read",path..": "..traceError(body)); return nil,tostring(body) end
            local availableW=max(1,(self.win and self.win.w or 530)-165); local availableH=max(1,(self.win and self.win.h or 282)-80)
            if kind=="png" then
                local nativeOk,native,nativeError=pcall(nativeDecode,body)
                if not nativeOk then native=nil; nativeError=traceError(native); imageDiagnostic("WARN","viewer.native_png", "Tom's GPU call failed; fallback=pure_lua_png: "..nativeError)
                elseif not native then imageDiagnostic("WARN","viewer.native_png", "native decode rejected image; fallback=pure_lua_png: "..tostring(nativeError or "unknown error")) end
                if native and native.width<=availableW and native.height<=availableH then return {native=native,rawPng=body},nil end
                if native then nativeFree(native); imageDiagnostic("INFO","viewer.native_png", "native image is larger than viewer area; fallback=pure_lua_png") end
                local decodedOk,decoded=pcall(pngDecode,body)
                if not decodedOk then imageDiagnostic("ERROR","viewer.png_decode",traceError(decoded)); return nil,tostring(decoded) end
                local preparedOk,data=pcall(imagePrepare,decoded,availableW,availableH)
                if not preparedOk then imageDiagnostic("ERROR","viewer.resize",traceError(data)); return nil,tostring(data) end
                if not data then imageDiagnostic("ERROR","viewer.resize","pure Lua PNG resize returned no image"); return nil,"image resize failed" end
                imageDiagnostic("INFO","viewer.fallback","pure Lua PNG decode/resize succeeded")
                return {data=data,rawPng=body},nil
            end
            local decodedOk,decoded=pcall(jpegDecode,body)
            if not decodedOk then imageDiagnostic("ERROR","viewer.jpeg_decode",traceError(decoded)); return nil,tostring(decoded) end
            local preparedOk,data=pcall(imagePrepare,decoded,availableW,availableH)
            if not preparedOk then imageDiagnostic("ERROR","viewer.resize",traceError(data)); return nil,tostring(data) end
            if not data then imageDiagnostic("ERROR","viewer.resize","JPEG resize returned no image"); return nil,"image resize failed" end
            return {data=data},nil
        end
        local data,err=imageRead(path)
        if not data then return nil,tostring(err) end
        return {data=data},nil
    end,function(value) return traceError(value) end)
    if not ok then reason=traceError(result or "unknown image error"); result=nil end
    if not result then
        self.status="Image load failed"; self.error=tostring(reason or "unknown image error"); imageDiagnostic("ERROR","viewer.load",self.error); logLine("ERROR","Image load: "..self.error); mark(self.win); return false
    end
    self.path=path; self.data=result.data; self.rawPngBody=result.rawPng; self.nativeImage=result.native; self.offsetX=0; self.offsetY=0; self.status="Image ready"
    for i,v in ipairs(self.images or {}) do if v==path then self.selected=i end end
    mark(self.win); return true
end
function ImageViewer:refreshList() self.images=imageList(); self.selected=clamp(self.selected,1,max(1,#self.images)); if self.images[self.selected] then self:loadPath(self.images[self.selected]) end end
function ImageViewer:openDialog()
    dialog("Open Image","Absolute .hcci, .png, .jpeg or .qoi path",{"Open","Cancel"},function(b,value)
        if b=="Open" then self:loadPath(value) end
    end,self.path or fs.combine(imageStorage,"image.hcci"))
end
function ImageViewer:saveAs()
    if self.rawPngBody then
        saveRawPngDialog(self.rawPngBody,self.path and self.path:lower():match("%.png$") and self.path or fs.combine(imageStorage,"image.png"))
        return
    end
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
    end,self.path or fs.combine(imageStorage,"image.hcci"))
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
    self.status="Import failed"; self.error=tostring(message or "unknown image import error"); imageDiagnostic("ERROR","viewer.import",self.error); logLine("ERROR","Image import: "..self.error); mark(self.win); errorBox(self.error)
end
function ImageViewer:finishImportData(data)
    if not data then imageDiagnostic("ERROR","viewer.import.save","decoded image data is missing"); self:importError("Downloaded data could not be converted to an image"); return end
    if self.importRawPng then
        local path=imagePathFor("imported_"..tostring(floor(now()*1000))..".png",#self.importRawPng)
        local saved,saveError=writeRawPng(path,self.importRawPng)
        if not saved then imageDiagnostic("ERROR","viewer.import.save_png","original PNG save failed: "..tostring(saveError)); self:importError("Original PNG could not be saved: "..tostring(saveError)); return end
        self.data=data; self.rawPngBody=self.importRawPng; self.path=path; self.nativeImage=nil; self.error=nil; self.status="PNG imported and saved"; self.images=imageList()
        for i,value in ipairs(self.images) do if value==path then self.selected=i end end
        mark(self.win); notify("PNG image imported and saved",P.success); return
    end
    local path=fs.combine(imageStorage,"imported_"..tostring(floor(now()*1000))..".hcci")
    local saved,saveError=imageWrite(path,data)
    if not saved then imageDiagnostic("ERROR","viewer.import.save_hcci","HCCI save failed: "..tostring(saveError)); self:importError("Image was decoded but could not be saved: "..tostring(saveError)); return end
    self.data=data; self.path=path; self.nativeImage=nil; self.error=nil; self.status="Image imported and saved"; self.images=imageList()
    for i,value in ipairs(self.images) do if value==path then self.selected=i end end
    mark(self.win); notify("Image imported and saved",P.success)
end
function ImageViewer:startImportBody(job,body)
    body=tostring(body or "")
    imageDiagnostic("INFO","viewer.import","received "..#body.." bytes from "..tostring(job.url))
    if #body==0 then imageDiagnostic("ERROR","viewer.import.body","downloaded image is empty"); self:importError("Downloaded image is empty"); return end
    if #body>cfg.maxImageDownload then imageDiagnostic("ERROR","viewer.import.body","download exceeds configured limit"); self:importError("Downloaded image exceeds the configured size limit"); return end
    local kind=imageKind(job.url,job.contentType)
    if not kind and pngSignature(body) then kind="png"; job.contentType="image/png" end
    if not kind and qoiSignature(body) then kind="qoi"; job.contentType="image/qoi" end
    if not kind then imageDiagnostic("ERROR","viewer.import.kind","unsupported image format"); self:importError("Unsupported image format (PNG, JPEG, QOI or HCCI required)"); return end
    self.importRawPng=kind=="png" and body or nil
    self.rawPngBody=self.importRawPng
    local availableW=max(1,(self.win and self.win.w or 530)-165); local availableH=max(1,(self.win and self.win.h or 282)-80)
    if kind=="png" then
        local nativeOk,native,nativeError=pcall(nativeDecode,body)
        if not nativeOk then native=nil; nativeError=traceError(native); imageDiagnostic("WARN","viewer.native_png","Tom's GPU call failed; fallback=pure_lua_png: "..nativeError)
        elseif not native then imageDiagnostic("WARN","viewer.native_png","native decode rejected image; fallback=pure_lua_png: "..tostring(nativeError or "unknown error")) end
        if native and native.width<=availableW and native.height<=availableH then
            local path=imagePathFor("imported_"..tostring(floor(now()*1000))..".png",#body)
            local stored,storeError=writeRawPng(path,body)
            if stored then
                self:cancelImport(); self:releaseNative(); self.nativeImage=native; self.data=nil; self.rawPngBody=body; self.path=path; self.error=nil; self.status="PNG imported and saved"; self.images=imageList()
                for i,value in ipairs(self.images) do if value==path then self.selected=i end end
                mark(self.win); notify("PNG image imported and saved",P.success); return
            end
            nativeFree(native); nativeError=storeError; imageDiagnostic("WARN","viewer.save_png","native decode succeeded but PNG save failed; fallback=pure_lua_png: "..tostring(storeError))
        elseif native then
            nativeFree(native); nativeError="native PNG exceeds the available viewer area"; imageDiagnostic("INFO","viewer.native_png",nativeError.."; fallback=pure_lua_png")
        end
        self.importNotice=nativeError and tostring(nativeError):sub(1,72) or nil
    end
    local co=coroutine.create(function()
        local decoded
        if kind=="png" then decoded=pngDecode(body,function(p) coroutine.yield("Decoding PNG...",p) end)
        elseif kind=="jpeg" then decoded=jpegDecode(body,function(p) coroutine.yield("Decoding JPEG...",p) end)
        elseif kind=="qoi" then coroutine.yield("Decoding QOI...",0.2); local qoiError; decoded,qoiError=imageDecodeQoi(body); if not decoded then error(qoiError or "invalid QOI image") end
        else
            local parsedOk,raw=pcall(textutils.unserialize,body)
            if not parsedOk then error(raw) end
            local normalized,normalizeError=imageNormalize(raw)
            if not normalized then error(normalizeError or "invalid HCCI image") end
            decoded=normalized
        end
        local data=kind=="png" and resizePng(decoded,availableW,availableH) or imagePrepare(decoded,availableW,availableH,function(stage,p) coroutine.yield(stage,p) end)
        return data
    end)
    self.importJob={stage="convert",co=co}; self.status="Converting image... 0%"; imageDiagnostic("INFO","viewer.convert","fallback decoder started: "..kind); mark(self.win)
end
function ImageViewer:onHttpSuccess(url,handle)
    local job=self.importJob
    if not job or job.url~=url then if handle and handle.close then pcall(handle.close) end; imageDiagnostic("WARN","viewer.http","response has no matching image job: "..tostring(url)); return false end
    if type(handle)~="table" then imageDiagnostic("ERROR","viewer.http","response handle is invalid"); self:importError("HTTP response handle is invalid"); return true end
    local headers=responseHeaders(handle); local length=tonumber(headers["content-length"] or "")
    if length and length>cfg.maxImageDownload then if handle.close then pcall(handle.close) end; imageDiagnostic("ERROR","viewer.http","Content-Length exceeds configured limit"); self:importError("Downloaded image exceeds the configured size limit"); return true end
    job.handle=handle; job.contentType=headers["content-type"] or (job.cachedMeta and job.cachedMeta.contentType or ""); job.length=length; job.bytes=0; job.parts={}; job.headers=headers; job.code=200
    if type(handle.getResponseCode)=="function" then local ok,code=pcall(handle.getResponseCode); if ok and finite(code) then job.code=code end end
    if job.code==304 and job.cachedBody then
        if handle.close then pcall(handle.close) end
        job.length=#job.cachedBody; local processed,processError=pcall(self.startImportBody,self,job,job.cachedBody)
        if not processed then imageDiagnostic("ERROR","viewer.process",traceError(processError)); self:importError("Image processing failed: "..tostring(processError)) end
        return true
    end
    if job.code<200 or job.code>=300 then if handle.close then pcall(handle.close) end; imageDiagnostic("ERROR","viewer.http","HTTP image request returned HTTP "..tostring(job.code)); self:importError("HTTP image request returned HTTP "..tostring(job.code)); return true end
    if type(handle.read)~="function" then imageDiagnostic("ERROR","viewer.http","response has no readable body"); self:importError("HTTP response has no readable body"); return true end
    job.stage="download"; self.status="Downloading... 0%"; mark(self.win); return true
end
function ImageViewer:onHttpFailure(url,reason)
    if not self.importJob or self.importJob.url~=url then return false end
    imageDiagnostic("ERROR","viewer.http","HTTP request failed: "..tostring(reason or "unknown error")); self:importError("HTTP request failed: "..tostring(reason or "unknown error")); return true
end
function ImageViewer:update()
    local job=self.importJob; if not job then return end
    if job.stage=="wait" then
        if now()-(job.startedAt or now())>30 then self:importError("HTTP request timed out") end
        return
    end
    if job.stage=="download" then
        local chunk; local ok=pcall(function() chunk=job.handle.read(32768) end)
        if not ok then imageDiagnostic("ERROR","viewer.download", "response body read failed"); self:importError("HTTP response body could not be read"); return end
        if chunk and #chunk>0 then
            job.parts[#job.parts+1]=chunk; job.bytes=job.bytes+#chunk
            if job.bytes>cfg.maxImageDownload then imageDiagnostic("ERROR","viewer.download","stream exceeded configured limit"); self:importError("Downloaded image exceeds the configured size limit"); return end
            self.status="Downloading... "..tostring(job.length and floor(clamp(job.bytes/job.length,0,1)*100+0.5) or 0).."%"; mark(self.win); return
        end
        if job.handle.close then pcall(job.handle.close) end
        local body=table.concat(job.parts); local kind=imageKind(job.url,job.contentType); if kind then httpCacheSave(job.url,body,kind,job.headers or {}) end
        local processed,processError=pcall(self.startImportBody,self,job,body)
        if not processed then imageDiagnostic("ERROR","viewer.process",traceError(processError)); self:importError("Image processing failed: "..tostring(processError)) end
        return
    end
    if job.stage=="convert" then
        local ok,a,b=coroutine.resume(job.co)
        if not ok then local reason=traceCoroutine(job.co,a); imageDiagnostic("ERROR","viewer.convert",reason); self:importError("Image conversion failed: "..tostring(a)); return end
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
        self:cancelImport(); self:releaseNative(); self.rawPngBody=nil; self.importRawPng=nil; self.error=nil; self.importNotice=nil; self.status="Downloading... 0%"
        local cachedBody,cachedMeta=httpCacheLoad(url); local headers={['User-Agent']="HCC-Image-Viewer/1.5.1",Accept="image/png,image/jpeg,image/qoi,image/*;q=0.8"}
        if cachedMeta then if cachedMeta.etag and cachedMeta.etag~="" then headers["If-None-Match"]=cachedMeta.etag end; if cachedMeta.lastModified and cachedMeta.lastModified~="" then headers["If-Modified-Since"]=cachedMeta.lastModified end end
        local ok,accepted=pcall(http.request,url,nil,headers,true)
        if not ok or accepted==false or accepted==nil then self:importError("HTTP image request failed or was denied"); return end
        self.importJob={stage="wait",url=url,startedAt=now(),cachedBody=cachedBody,cachedMeta=cachedMeta}; mark(self.win)
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
    else preview:text(8,18,self.error and ("Image error: "..self.error) or "Open an HCC Image, PNG, JPEG or QOI",self.error and P.error or P.textSecondary) end
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

-- HCC OS v1.5 GUI application module.
return function(E)
    local env=setmetatable({Driver=E.AppDriver,OS=E.AppOS},{__index=E})
local _ENV=env
local storagePaths=E.paths or {}
local imageStorage=storagePaths.images or "/.hccos/images"
local downloadStorage=storagePaths.downloads or "/.hccos/downloads"
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
local function resizePng(data,width,height,progress)
    if type(E.imageResize)=="function" then return E.imageResize(data,width,height,function(value) if progress then progress("Resizing PNG...",value) end end) end
    return imagePrepare(data,width,height,progress)
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
local function nativeStage(body,key)
    if type(E.imageStageNativePng)=="function" then
        local ok,path,reason=pcall(E.imageStageNativePng,body,key)
        if ok then return path,reason end
        return nil,tostring(path)
    end
    return nil,"Tom's GPU native PNG staging unavailable"
end
local function nativeFree(record)
    if type(E.imageFreeNativePng)=="function" then pcall(E.imageFreeNativePng,record) end
end
local function nativeDelete(path)
    if type(E.imageDeleteNativePng)=="function" then pcall(E.imageDeleteNativePng,path); return true end
    return false,"Tom's GPU native PNG cleanup unavailable"
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
            imageDiagnostic("WARN","web.save_png","primary path failed: "..tostring(err))
            local filename=value:match("([^/]+)$") or "web_image.png"; local fallback=imagePathFor(filename,#body)
            if fallback~=value then
                imageDiagnostic("INFO","web.save_png","trying storage fallback: "..fallback)
                ok,err=writeRawPng(fallback,body)
                if ok then notify("PNG image saved to "..fallback,P.success); return end
                imageDiagnostic("ERROR","web.save_png","fallback path failed: "..tostring(err))
            end
            errorBox(err)
        end
    end,defaultPath)
end
local function webUnescape(s)
    return tostring(s or ""):gsub("&amp;","&"):gsub("&lt;","<"):gsub("&gt;",">"):gsub("&quot;",'"'):gsub("&#39;","'")
end
local function webParse(html,base)
    html=tostring(html or ""):gsub("<script.-</script>",""):gsub("<style.-</style>","")
    local title=webUnescape(html:match("<title[^>]*>(.-)</title>") or "")
    local links={}
    for href,label in html:gmatch("<a[^>]-href%s*=%s*[\"'](.-)[\"'][^>]*>(.-)</a>") do
        label=webUnescape(label:gsub("<[^>]->","")):gsub("%s+"," ")
        if href:sub(1,1)=="/" and base then local origin=base:match("^(https?://[^/]+)"); href=origin and origin..href or href end
        links[#links+1]={url=href,label=label~="" and label or href}
    end
    local text=html:gsub("<br%s*/?>","\n"):gsub("</p%s*>","\n"):gsub("</h[1-6]%s*>","\n"):gsub("<li[^>]*>","* "):gsub("<[^>]->","")
    text=webUnescape(text):gsub("\r"," "):gsub("[ \t]+"," "):gsub("\n%s+","\n")
    local lines={}; for line in (text.."\n"):gmatch("([^\n]*)\n") do if line:match("%S") then lines[#lines+1]=line:sub(1,512) end end
    if #lines==0 then lines={"(empty response)"} end
    return title,lines,links
end
local function webJsonLines(body)
    if type(textutils.unserializeJSON)~="function" then return end
    local trimmed=body:gsub("^%s+","")
    if trimmed:sub(1,1)~="{" and trimmed:sub(1,1)~="[" then return end
    local ok,value=pcall(textutils.unserializeJSON,body); if not ok or value==nil then return end
    local serialized=type(textutils.serializeJSON)=="function" and textutils.serializeJSON(value) or textutils.serialize(value)
    local lines={}; for line in (serialized.."\n"):gmatch("([^\n]*)\n") do lines[#lines+1]=line end
    return lines
end
local function webSafeUrl(url)
    url=tostring(url or ""):gsub("%s+","")
    if #url>512 or not url:match("^https?://[^%s]+$") then return nil end
    return url
end
local Web={}
function Web:init(url)
    self.url=""; self.status="Ready"; self.title="HCC Web"; self.lines={"Enter an HTTP/HTTPS URL and press GO."}; self.links={}; self.linkSelected=1; self.top=1; self.body=""; self.history={}; self.historyIndex=0
    if type(url)=="string" and url~="" then self:load(url,true) end
end
function Web:load(url,record)
    url=webSafeUrl(url); if not url then self.status="Invalid URL"; self.lines={"Only http:// and https:// URLs are allowed."}; mark(self.win); return false end
    if type(http)~="table" or type(http.get)~="function" then self.status="HTTP API unavailable"; self.lines={"CC:Tweaked HTTP API is unavailable or disabled."}; mark(self.win); return false end
    self.status="Loading..."; mark(self.win)
    local ok,handle=pcall(http.get,url,{["User-Agent"]="HCC-Web/1.3"})
    if not ok or not handle then self.status="HTTP request failed"; self.lines={"HTTP request failed: "..tostring(handle or "permission denied")}; logLine("WARN",self.status.." "..url); mark(self.win); return false end
    local readOk,body=pcall(handle.readAll); local code=200
    if type(handle.getResponseCode)=="function" then local cok,cvalue=pcall(handle.getResponseCode); if cok and finite(cvalue) then code=cvalue end end
    if handle.close then pcall(handle.close) end
    if not readOk then self.status="Read failed"; self.lines={"Response body could not be read."}; mark(self.win); return false end
    self.url=url; self.body=tostring(body or ""); self.title,self.lines,self.links=webParse(self.body,url); self.lines=webJsonLines(self.body) or self.lines
    self.status="HTTP "..tostring(code).."  "..#self.body.." bytes"; self.linkSelected=1; self.top=1
    if record~=false then for i=#self.history,self.historyIndex+1,-1 do table.remove(self.history,i) end; self.history[#self.history+1]=url; self.historyIndex=#self.history end
    mark(self.win); logLine("INFO","Web GET "..url.." -> "..tostring(code)); return true
end
function Web:goDialog()
    dialog("HCC Web URL","HTTP/HTTPS URL",{"GO","Cancel"},function(b,value) if b=="GO" then self:load(value,true) end end,self.url~="" and self.url or "https://example.com")
end
function Web:back() if self.historyIndex>1 then self.historyIndex=self.historyIndex-1; self:load(self.history[self.historyIndex],false) end end
function Web:forward() if self.historyIndex<#self.history then self.historyIndex=self.historyIndex+1; self:load(self.history[self.historyIndex],false) end end
function Web:reload() if self.url~="" then self:load(self.url,false) end end
function Web:download()
    if self.body=="" or self.url=="" then return end
    local filename=self.url:match("/([^/?#]+)[?#]?[^/]*$") or "download.txt"; filename=filename:gsub("[^%w%._-]","_"):sub(1,64)
    local path=fs.combine(downloadStorage,filename)
    local save=function() local ok,err=pcall(function() if not fs.exists(downloadStorage) then fs.makeDir(downloadStorage) end; local f,e=fs.open(path,"w"); if not f then error(e) end; f.write(self.body); f.close() end); if ok then notify("Downloaded "..path,P.success) else errorBox(err) end end
    if fs.exists(path) then dialog("Overwrite download","Replace "..path.."?",{"Yes","No"},function(b) if b=="Yes" then save() end end) else save() end
end
function Web:onKey(k)
    if k==keys.left then self:back() elseif k==keys.right then self:forward() elseif k==keys.f5 then self:reload()
    elseif k==keys.up then self.top=max(1,self.top-3) elseif k==keys.down then self.top=min(max(1,#self.lines),self.top+3)
    elseif k==keys.enter and self.links[self.linkSelected] then self:load(self.links[self.linkSelected].url,true)
    elseif k==keys.pageUp then self.top=max(1,self.top-10) elseif k==keys.pageDown then self.top=min(max(1,#self.lines),self.top+10) end
    mark(self.win)
end
function Web:onMouse(kind,x,y,b)
    if kind=="scroll" then self.top=clamp(self.top-b*3,1,max(1,#self.lines))
    elseif kind=="click" and y>=58 and y<self.win.h-29 and x<self.win.w-10 then self.top=clamp(self.top+floor((y-58)/12)-1,1,max(1,#self.lines)) end
    mark(self.win)
end
function Web:draw(c)
    c:text(6,5,"HCC WEB",P.accent); c:text(6,19,self.title:sub(1,42),P.textPrimary)
    button(self,c,5,33,42,"BACK",function() self:back() end); button(self,c,51,33,48,"FORWARD",function() self:forward() end)
    button(self,c,103,33,48,"RELOAD",function() self:reload() end); button(self,c,156,33,39,"GO",function() self:goDialog() end)
    button(self,c,200,33,72,"DOWNLOAD",function() self:download() end)
    c:filledRectangle(277,34,c.w-284,15,P.panelBackground); c:rectangle(277,34,c.w-284,15,P.border); c:text(281,37,self.url=="" and "URL / SEARCH" or self.url,P.textPrimary)
    c:text(6,51,self.status,P.textSecondary); c:line(0,57,c.w-1,57,P.border)
    local rows=max(1,floor((c.h-85)/12)); self.top=clamp(self.top,1,max(1,#self.lines-rows+1))
    for i=0,rows-1 do local line=self.lines[self.top+i]; if not line then break end; c:text(7,62+i*12,line,P.textPrimary) end
    c:text(6,c.h-14,string.format("%d lines  %d links  PgUp/PgDn scroll",#self.lines,#self.links),P.textSecondary)
end
register("web","HCC Web","WB",440,230,Web)

-- HCC Web v1.3.1 image pipeline.  The old text-browser methods above remain
-- as a compatibility baseline; these methods replace transport/rendering with
-- event-driven HTTP and bounded coroutine work.
do
local function webResolveV131(src,base)
    src=tostring(src or ""):gsub("^%s+",""):gsub("%s+$","")
    if src:match("^https?://") then return src end
    if src:sub(1,2)=="//" then return (base and base:match("^(https?):") or "https")..":"..src end
    if not base or not base:match("^https?://") then return nil end
    local origin=base:match("^(https?://[^/]+)")
    if src:sub(1,1)=="/" then return origin..src end
    return (base:match("^(https?://.*/)") or base.."/")..src
end
local function webParseV131(html,base)
    html=tostring(html or ""):gsub("<script.-</script>",""):gsub("<style.-</style>","")
    local title=webUnescape(html:match("<title[^>]*>(.-)</title>") or ""); local links={}; local images={}
    for href,label in html:gmatch("<a[^>]-href%s*=%s*[\"'](.-)[\"'][^>]*>(.-)</a>") do
        local resolved=webResolveV131(href,base); label=webUnescape(label:gsub("<[^>]->",""):gsub("%s+"," "))
        if resolved and webSafeUrl(resolved) then links[#links+1]={url=resolved,label=label~="" and label or resolved} end
    end
    for attrs in html:gmatch("<img%s+([^>]-)>") do
        local src=attrs:match("src%s*=%s*[\"'](.-)[\"']") or attrs:match("src%s*=%s*([^%s>]+)"); local resolved=webResolveV131(src,base)
        if resolved and webSafeUrl(resolved) then images[#images+1]={url=resolved,status="pending"} end
    end
    local text=html:gsub("<br%s*/?>","\n"):gsub("</p%s*>","\n"):gsub("</h[1-6]%s*>","\n"):gsub("<li[^>]*>","* "):gsub("<[^>]->","")
    text=webUnescape(text):gsub("\r"," "):gsub("[ \t]+"," "):gsub("\n%s+","\n")
    local lines={}; for line in (text.."\n"):gmatch("([^\n]*)\n") do if line:match("%S") then lines[#lines+1]=line:sub(1,512) end end
    if #lines==0 then lines={"(empty response)"} end
    for i=1,#images do lines[#lines+1]="[ Image "..i..": Loading image... ]" end
    return title,lines,links,images
end
local function webImageStatusLine(lines,index,status)
    for i,line in ipairs(lines) do if line:match("^%[ Image "..tostring(index)..":") then lines[i]="[ Image "..tostring(index)..": "..status.." ]" end end
end
function Web:interval() return self.job and (self.job.stage=="wait" and 0.25 or 0.05) or (#(self.imageJobs or {})>0 and 0.05 or 1) end
function Web:markV131() if self.win then mark(self.win) end end
function Web:cancelJobV131(message)
    if self.job and self.job.handle and self.job.handle.close then pcall(self.job.handle.close) end
    if self.imageJobs then for _,job in ipairs(self.imageJobs) do if job.handle and job.handle.close then pcall(job.handle.close) end end end
    self.job=nil; self.imageJobs={}; if message then self.status=message; self:markV131() end
end
function Web:headersV131(handle)
    local out={}; if handle and type(handle.getResponseHeaders)=="function" then local ok,h=pcall(handle.getResponseHeaders); if ok and type(h)=="table" then for k,v in pairs(h) do out[tostring(k):lower()]=tostring(v) end end end; return out
end
function Web:cacheHeadersV131(meta)
    local headers={['User-Agent']="HCC-Web/1.5.1",Accept="image/png,image/jpeg,image/qoi,image/*;q=0.8"}
    if type(meta)=="table" then
        if meta.etag and meta.etag~="" then headers["If-None-Match"]=meta.etag end
        if meta.lastModified and meta.lastModified~="" then headers["If-Modified-Since"]=meta.lastModified end
    end
    return headers
end
local function pngSignature(body) return type(body)=="string" and body:sub(1,8)=="\137PNG\r\n\26\n" end
local function qoiSignature(body) return type(E.qoiSignature)=="function" and E.qoiSignature(body) or type(body)=="string" and body:sub(1,4)=="qoif" end
function Web:imageKindV131(url,contentType)
    local c=tostring(contentType or ""):lower():match("^[^;]+") or ""; local u=tostring(url):lower()
    if c=="image/png" or u:match("%.png$") or u:match("%.png[?#]") then return "png" end
    if c=="image/jpeg" or c=="image/jpg" or u:match("%.jpe?g$") or u:match("%.jpe?g[?#]") then return "jpeg" end
    if c=="image/qoi" or c=="image/x-qoi" or u:match("%.qoi$") or u:match("%.qoi[?#]") then return "qoi" end
    if c=="image/hcci" or u:match("%.hcci$") or u:match("%.hcci[?#]") then return "hcci" end
end
function Web:cacheAliasV131(url,w,h) return table.concat({url,"image",tostring(w).."x"..tostring(h)},"|") end
function Web:cacheKeyV131(url,w,h,ctype,length) return table.concat({url,"image",tostring(w).."x"..tostring(h),tostring(ctype or ""),tostring(length or "")},"|") end
function Web:progressV131(stage,value)
    self.status=finite(value) and stage.." "..tostring(clamp(floor(value*100+0.5),0,100)).."%" or stage; self:markV131()
end
function Web:showImageV131(data,path,url,cacheHit)
    if self.nativeImage then nativeFree(self.nativeImage); self.nativeImage=nil end
    self.pageMode="image"; self.imageData=data; self.imagePath=path; self.title=fs.getName(url or self.url):sub(1,48); self.lines={"Direct image view",self.rawPngBody and "Original PNG retained" or (cacheHit and "Loaded from Image Cache" or "Converted image")}; self.status=cacheHit and "Image Cache hit" or "Image ready"; self:markV131()
end
function Web:showNativeImageV131(native,path,url)
    if self.nativeImage and self.nativeImage~=native then nativeFree(self.nativeImage) end
    self.pageMode="image"; self.imageData=nil; self.nativeImage=native; self.imagePath=path; self.title=fs.getName(url or self.url):sub(1,48); self.lines={"Direct image view","PNG decoded by Tom's GPU"}; self.status="Native PNG ready"; self:markV131()
end
function Web:finishNativeImageV131(item,native,path,url)
    self.nativeTempPaths=self.nativeTempPaths or {}; if path then self.nativeTempPaths[path]=true end
    if item then
        item.nativeImage=native; item.path=path; item.status=item.rawPngBody and "native PNG ready" or "native ready"; webImageStatusLine(self.lines,item.index,item.status); self.job=nil; self:progressV131("Rendering...",1); self:queueNextImageV131()
    else
        self.job=nil; self:showNativeImageV131(native,path,url)
    end
end
function Web:finishImageV131(item,data,cacheKey,alias)
    if (not item and self.rawPngBody) or (item and item.rawPngBody) then
        if item then
            item.data=data; item.path=nil; item.status="PNG ready"; webImageStatusLine(self.lines,item.index,item.status); self.job=nil; self:progressV131("Rendering...",1); self:queueNextImageV131(); return
        end
        self.job=nil; self.imagePath=nil; self.cacheNotice="Original PNG ready; use SAVE PNG"; self:showImageV131(data,nil,self.url,false); return
    end
    local saved,err=imageCacheSave(alias,data)
    if not saved then imageDiagnostic("WARN","web.cache","image cache save failed; fallback=HCCI: "..tostring(err)) end
    if saved and cacheKey~=alias then
        local exactSaved,exactError=imageCacheSave(cacheKey,data)
        if not exactSaved then imageDiagnostic("WARN","web.cache","exact image cache save failed: "..tostring(exactError)) end
    end
    local path=saved and imageCachePath(alias) or nil
    if not path then
        -- The image cache is optional.  Keep the downloaded image usable
        -- when its directory is unavailable by persisting a normal HCCI in
        -- the user image directory instead.
        local fallback=fs.combine(imageStorage,"web_"..tostring(floor(now()*1000))..".hcci")
         local stored,storeError=imageWrite(fallback,data)
         if stored then path=fallback; self.cacheNotice="Cache unavailable; stored as HCCI"; imageDiagnostic("INFO","web.cache","HCCI fallback saved: "..fallback) else self.cacheNotice="Cache unavailable: "..tostring(err or storeError); imageDiagnostic("ERROR","web.cache","HCCI fallback save failed: "..tostring(err or storeError)) end
    else
        self.cacheNotice=""
    end
    if item then item.data=data; item.path=path; item.status=saved and "ready" or "ready (uncached)"; webImageStatusLine(self.lines,item.index,item.status); self.job=nil; self:progressV131("Rendering...",1); self:queueNextImageV131()
    else self.job=nil; self:showImageV131(data,path,self.url,false) end
end
function Web:startConversionV131(body,url,ctype,length,targetW,targetH,item)
    local kind=self:imageKindV131(url,ctype); if not kind then imageDiagnostic("ERROR","web.convert.kind","unsupported image type: "..tostring(url)); return false,"unsupported image type" end
    if not item then
        self.rawPngBody=kind=="png" and body or nil
        self.rawPngUrl=kind=="png" and url or nil
    elseif kind=="png" then
        item.rawPngBody=body
    end
    local alias=self:cacheAliasV131(url,targetW,targetH); local exact=self:cacheKeyV131(url,targetW,targetH,ctype,length); local cached=kind~="png" and imageCacheLoad(alias) or nil
    if kind=="png" then
        local nativeOk,native,nativeError=pcall(nativeDecode,body)
        if not nativeOk then native=nil; nativeError=traceError(native); imageDiagnostic("WARN","web.native_png","Tom's GPU call failed; fallback=pure_lua_png: "..nativeError)
        elseif not native then imageDiagnostic("WARN","web.native_png","native decode rejected image; fallback=pure_lua_png: "..tostring(nativeError or "unknown error")) end
        if native and native.width<=targetW-4 and native.height<=targetH-4 then
            self:finishNativeImageV131(item,native,nil,url); return true
        elseif native then
            nativeFree(native); nativeError="native PNG exceeds the available viewport"; imageDiagnostic("INFO","web.native_png",nativeError.."; fallback=pure_lua_png")
        end
        if nativeError then self.cacheNotice="Native PNG fallback: "..tostring(nativeError):sub(1,72) end
    end
    if cached then imageDiagnostic("INFO","web.cache","image cache hit: "..tostring(url)); if item then self:finishImageV131(item,cached,exact,alias) else self:showImageV131(cached,imageCachePath(alias),url,true) end; return true end
    local co=coroutine.create(function()
        local decoded
        if kind=="png" then decoded=pngDecode(body,function(p) coroutine.yield("Decoding PNG fallback...",p) end)
        elseif kind=="jpeg" then decoded=jpegDecode(body,function(p) coroutine.yield("Decoding JPEG...",p) end)
        elseif kind=="qoi" then coroutine.yield("Decoding QOI...",0.2); local qoiError; decoded,qoiError=imageDecodeQoi(body); if not decoded then error(qoiError or "invalid QOI image") end
        else
            coroutine.yield("Decoding HCCI...",0.5); local ok,raw=pcall(textutils.unserialize,body); if not ok then error(raw) end; decoded=imageNormalize(raw); if not decoded then error("invalid HCCI image") end
        end
        local data,stored,size
        if kind=="png" then data=resizePng(decoded,targetW,targetH,function(stage,p) coroutine.yield(stage,p) end); size=0 else data,stored,size=imagePrepare(decoded,targetW,targetH,function(stage,p) coroutine.yield(stage,p) end) end
        return data,stored,size,exact,alias
    end)
    self.job={stage="convert",co=co,item=item,url=url,cacheKey=exact,alias=alias}; imageDiagnostic("INFO","web.convert","fallback decoder started: "..kind.." url="..tostring(url)); self:progressV131(kind=="png" and "Decoding PNG..." or kind=="jpeg" and "Decoding JPEG..." or kind=="qoi" and "Decoding QOI..." or "Decoding HCCI...",0); return true
end
function Web:startRequestV131(url,kind,targetW,targetH,item)
    if type(http)~="table" or type(http.request)~="function" then imageDiagnostic("ERROR","web.http","CC:T HTTP request API unavailable: "..tostring(url)); return false,"CC:T HTTP request API unavailable" end
    local cachedBody,cachedMeta
    if kind=="image" then cachedBody,cachedMeta=httpCacheLoad(url) end
    local headers=self:cacheHeadersV131(kind=="image" and cachedMeta or nil)
    if kind~="image" then headers.Accept="text/html,application/xhtml+xml,text/plain;q=0.9,*/*;q=0.5" end
    local ok,accepted=pcall(http.request,url,nil,headers,true); if not ok or accepted==false or accepted==nil then imageDiagnostic("ERROR","web.http","HTTP request failed or denied: "..tostring(url)); return false,"HTTP request failed or denied" end
    local job={stage="wait",kind=kind,url=url,item=item,targetW=targetW,targetH=targetH,startedAt=now(),cachedBody=cachedBody,cachedMeta=cachedMeta}
    if kind=="image" and item then self.imageJobs=self.imageJobs or {}; self.imageJobs[#self.imageJobs+1]=job else self.job=job; self:progressV131("Downloading...",0) end
    return true
end
function Web:findImageJobV131(url)
    for _,job in ipairs(self.imageJobs or {}) do if job.url==url then return job end end
end
function Web:removeImageJobV131(target)
    for i,job in ipairs(self.imageJobs or {}) do if job==target then table.remove(self.imageJobs,i); return end end
end
function Web:failImageJobV131(job,message)
    if job.handle and job.handle.close then pcall(job.handle.close) end
    imageDiagnostic("ERROR","web.image_job",tostring(job.url).." failed: "..traceError(message)); self:removeImageJobV131(job)
    local item=job.item
    if item then item.status="failed: "..tostring(message):sub(1,80); webImageStatusLine(self.lines,item.index,item.status) end
    self:markV131(); self:queueNextImageV131()
end
function Web:onHttpSuccessV131(url,handle)
    local job=self.job
    local imageJob=false
    if not job or job.url~=url then job=self:findImageJobV131(url); imageJob=job~=nil end
    if not job then if handle and handle.close then pcall(handle.close) end; imageDiagnostic("WARN","web.http","response has no matching job: "..tostring(url)); return end
    if type(handle)~="table" then imageDiagnostic("ERROR","web.http","response handle is invalid: "..tostring(url)); if imageJob then self:failImageJobV131(job,"HTTP response handle is invalid") else self:onHttpFailureV131(url,"HTTP response handle is invalid") end; return end
    local h=self:headersV131(handle); local length=tonumber(h["content-length"] or "")
    if length and length>cfg.maxImageDownload then imageDiagnostic("ERROR","web.download","Content-Length exceeds configured limit: "..tostring(url)); if imageJob then self:failImageJobV131(job,"response exceeds configured limit") else if handle.close then pcall(handle.close) end; self.job=nil; self.status="Image too large"; self.lines={"Download refused: Content-Length exceeds configured limit."}; self:markV131() end; return end
    job.handle=handle; job.parts={}; job.bytes=0; job.contentType=h["content-type"] or (job.cachedMeta and job.cachedMeta.contentType or ""); job.length=length; job.headers=h; job.code=200
    if type(handle.getResponseCode)=="function" then local ok,code=pcall(handle.getResponseCode); if ok and finite(code) then job.code=code end end
    if job.code==304 and job.cachedBody then
        if handle.close then pcall(handle.close) end
        if imageJob then self:removeImageJobV131(job) else self.job=nil end
        job.length=#job.cachedBody; self:bodyReadyV131(job,job.cachedBody,true); return true
    end
    if job.code<200 or job.code>=300 then imageDiagnostic("ERROR","web.http","HTTP response "..tostring(job.code)..": "..tostring(url)); if imageJob then self:failImageJobV131(job,"HTTP "..tostring(job.code)) else self:onHttpFailureV131(url,"HTTP "..tostring(job.code)) end; return true end
    if type(handle.read)~="function" then imageDiagnostic("ERROR","web.download","response has no readable body: "..tostring(url)); if imageJob then self:failImageJobV131(job,"HTTP response has no readable body") else self:onHttpFailureV131(url,"HTTP response has no readable body") end; return end
    job.stage="download"
    return true
end
function Web:onHttpFailureV131(url,reason)
    local job=self.job; local imageJob=false
    if not job or job.url~=url then job=self:findImageJobV131(url); imageJob=job~=nil end
    if not job then imageDiagnostic("WARN","web.http","failure has no matching job: "..tostring(url)); return end
    if imageJob then self:failImageJobV131(job,"HTTP request failed: "..tostring(reason or "unknown error")); return end
    imageDiagnostic("ERROR","web.http",tostring(url).." failed: "..tostring(reason or "unknown error"))
    local item=job.item; self.job=nil; self.status="HTTP request failed"; self.lines={"HTTP request failed: "..tostring(reason or "unknown error")}; if item then item.status="failed"; webImageStatusLine(self.lines,item.index,"failed") end; self:markV131(); if self.pageMode=="html" then self:queueNextImageV131() end
end
function Web:bodyReadyV131(job,body)
    imageDiagnostic("INFO","web.body","received "..#body.." bytes from "..tostring(job.url))
    if #body>cfg.maxImageDownload then imageDiagnostic("ERROR","web.body","response exceeds configured limit: "..tostring(job.url)); self.job=nil; self.status="Image too large"; self.lines={"Download refused: response exceeds configured limit."}; self:markV131(); return end
    local kind=self:imageKindV131(job.url,job.contentType)
    if not kind and pngSignature(body) then kind="png"; job.contentType="image/png" end
    if not kind and qoiSignature(body) then kind="qoi"; job.contentType="image/qoi" end
    if kind then
        if pngSignature(body)==false and kind=="png" then imageDiagnostic("ERROR","web.png_signature","invalid PNG response: "..tostring(job.url)); local item=job.item; if item then item.status="invalid PNG"; webImageStatusLine(self.lines,item.index,item.status); self:queueNextImageV131() else self.status="Invalid PNG response"; self.lines={"The server did not return a valid PNG."}; self:markV131() end; return end
        if kind=="qoi" and not qoiSignature(body) then imageDiagnostic("ERROR","web.qoi_signature","invalid QOI response: "..tostring(job.url)); local item=job.item; if item then item.status="invalid QOI"; webImageStatusLine(self.lines,item.index,item.status); self:queueNextImageV131() else self.status="Invalid QOI response"; self.lines={"The server did not return a valid QOI."}; self:markV131() end; return end
        if not job.cachedBody then local cacheSaved= httpCacheSave(job.url,body,kind,job.headers or {}); if not cacheSaved then imageDiagnostic("WARN","web.cache","raw HTTP image cache save failed: "..tostring(job.url)) end end
    local ok,err=self:startConversionV131(body,job.url,job.contentType,job.length,job.targetW or max(64,(self.win and self.win.w or 576)-14),job.targetH or max(64,(self.win and self.win.h or 360)-TITLE-115),job.item)
        if not ok then
            imageDiagnostic("ERROR","web.convert",tostring(job.url)..": "..traceError(err))
            local item=job.item; self.job=nil; self.status="Image conversion unavailable"; self.lines={"Image conversion failed: ",tostring(err or "unsupported image type")}
            if item then item.status="failed"; webImageStatusLine(self.lines,item.index,"failed") end
            self:markV131(); if item then self:queueNextImageV131() end
        end
        return
    end
    self.body=body; self.title,self.lines,self.links,self.pageImages=webParseV131(body,job.url); self.lines=webJsonLines(body) or self.lines; self.pageMode="html"; self.imageData=nil; self.imagePath=nil; self.linkSelected=1; self.top=1; self.job=nil; self.status="HTTP "..tostring(job.code or 200).."  "..#body.." bytes"; self:markV131(); self:queueNextImageV131()
end
function Web:updateV131()
    self:updateImageJobsV131()
    local job=self.job; if not job then self:queueNextImageV131(); return end
    if job.stage=="wait" then
        if now()-(job.startedAt or now())>30 then self:onHttpFailureV131(job.url,"request timed out") end
        return
    end
    if job.stage=="download" then
        local chunk; local ok=pcall(function() chunk=job.handle.read(32768) end)
        if not ok then imageDiagnostic("ERROR","web.download","response body read failed: "..tostring(job.url)); if job.handle.close then pcall(job.handle.close) end; self.job=nil; self.status="Read failed"; self.lines={"Response body could not be read."}; self:markV131(); return end
        if chunk and #chunk>0 then job.parts[#job.parts+1]=chunk; job.bytes=job.bytes+#chunk; if job.bytes>cfg.maxImageDownload then if job.handle.close then pcall(job.handle.close) end; self.job=nil; self.status="Image too large"; self.lines={"Download refused: response exceeds configured limit."}; self:markV131(); return end; self:progressV131("Downloading...",job.length and job.bytes/job.length or 0); return end
        if job.handle.close then pcall(job.handle.close) end
        local processed,processError=pcall(self.bodyReadyV131,self,job,table.concat(job.parts))
        if not processed then imageDiagnostic("ERROR","web.process",traceError(processError)); self.job=nil; self.status="Image processing failed"; self.lines={"Image processing failed:",tostring(processError)}; self:markV131() end
        return
    end
    if job.stage=="convert" then
        local ok,a,b,c,d,e=coroutine.resume(job.co)
        if not ok then
            local reason=traceCoroutine(job.co,a); imageDiagnostic("ERROR","web.convert",tostring(job.url)..": "..reason)
            local item=job.item; self.job=nil; self.status="Image conversion failed: "..reason
            if item then item.status="failed"; webImageStatusLine(self.lines,item.index,"failed: "..reason:sub(1,96)); self:markV131(); self:queueNextImageV131()
            else self.lines={"Image conversion failed:",reason}; self:markV131() end
            return
        end
        if coroutine.status(job.co)=="dead" then self:finishImageV131(job.item,a,d,e) else self:progressV131(a,b) end
    end
end
function Web:updateImageJobsV131()
    for _,job in ipairs(self.imageJobs or {}) do
        if job.stage=="wait" then
            if now()-(job.startedAt or now())>30 then self:failImageJobV131(job,"request timed out") end
        elseif job.stage=="download" then
            local chunk; local ok=pcall(function() chunk=job.handle.read(32768) end)
            if not ok then imageDiagnostic("ERROR","web.download","parallel response body read failed: "..tostring(job.url)); self:failImageJobV131(job,"HTTP response body could not be read")
            elseif chunk and #chunk>0 then
                job.parts[#job.parts+1]=chunk; job.bytes=job.bytes+#chunk
                if job.bytes>cfg.maxImageDownload then self:failImageJobV131(job,"response exceeds configured limit")
                else
                    local item=job.item; if item then item.status="downloading "..tostring(job.length and floor(clamp(job.bytes/job.length,0,1)*100+0.5) or 0).."%"; webImageStatusLine(self.lines,item.index,item.status) end
                    self:markV131()
                end
            else
                if job.handle.close then pcall(job.handle.close) end
                self:removeImageJobV131(job); local body=table.concat(job.parts); job.parts=nil; job.body=body; if job.item then job.item.body=nil; job.item.contentType=job.contentType; job.item.targetW=job.targetW; job.item.targetH=job.targetH end
                local processed,processError=pcall(self.bodyReadyV131,self,job,body)
                if not processed then imageDiagnostic("ERROR","web.process","parallel image processing failed: "..traceError(processError)); local item=job.item; if item then item.status="processing failed"; webImageStatusLine(self.lines,item.index,item.status) end; self:markV131(); self:queueNextImageV131() end
                return
            end
        end
    end
end
function Web:queueNextImageV131()
    if self.pageMode~="html" then return end
    self.imageJobs=self.imageJobs or {}
    local capacity=max(0,cfg.imageDownloadConcurrency-#self.imageJobs)
    for i,item in ipairs(self.pageImages or {}) do
        if capacity<=0 then break end
        item.index=i
        if item.status=="pending" then
            self.imageIndex=item.index; local tw=max(64,min(384,(self.win and self.win.w or 548)-190)); local th=max(64,min(200,(self.win and self.win.h or 286)-110)); local ok,err=self:startRequestV131(item.url,"image",tw,th,item)
            if not ok then item.status="failed"; webImageStatusLine(self.lines,item.index,"failed"); self.status=tostring(err); self:markV131() else item.status="downloading 0%"; webImageStatusLine(self.lines,item.index,item.status); capacity=capacity-1 end
        end
    end
    if self.job then return end
    local active=#(self.imageJobs or {})
    if active==0 then
        local pending=false
        for _,item in ipairs(self.pageImages or {}) do if item.status=="pending" or item.status:match("^downloading") then pending=true end end
        if not pending and not self.job then self.status="Page ready / images loaded"; self:markV131() end
    end
end
function Web:initV131(url)
    self.url=""; self.status="Ready"; self.title="HCC Web"; self.lines={"Enter an HTTP/HTTPS URL and press GO."}; self.links={}; self.linkSelected=1; self.top=1; self.body=""; self.history={}; self.historyIndex=0; self.job=nil; self.imageJobs={}; self.pageMode="text"; self.pageImages={}; self.imageData=nil; self.nativeImage=nil; self.nativeTempPaths={}; self.imagePath=nil; self.rawPngBody=nil; self.rawPngUrl=nil; self.imageIndex=1; self.cacheNotice=""
    if type(url)=="string" and url~="" then self:loadV131(url,true) end
end
function Web:loadV131(url,record)
    url=webSafeUrl(url); if not url then self.status="Invalid URL"; self.lines={"Only http:// and https:// URLs are allowed."}; self:markV131(); return false end
    self:cancelJobV131(); if self.nativeImage then nativeFree(self.nativeImage); self.nativeImage=nil end; for _,item in ipairs(self.pageImages or {}) do if item.nativeImage then nativeFree(item.nativeImage) end end; for path in pairs(self.nativeTempPaths or {}) do nativeDelete(path) end; self.nativeTempPaths={}; self.url=url; self.pageMode="text"; self.pageImages={}; self.imageData=nil; self.imagePath=nil; self.rawPngBody=nil; self.rawPngUrl=nil; self.title="HCC Web"; self.lines={"Downloading..."}; self.linkSelected=1; self.top=1
    if record~=false then for i=#self.history,self.historyIndex+1,-1 do table.remove(self.history,i) end; self.history[#self.history+1]=url; self.historyIndex=#self.history end
    local kind=self:imageKindV131(url,"")
    local requestKind=kind and "image" or "page"; local tw=requestKind=="image" and max(64,(self.win and self.win.w or 576)-14) or nil; local th=requestKind=="image" and max(64,(self.win and self.win.h or 360)-TITLE-115) or nil
    local ok,err=self:startRequestV131(url,requestKind,tw,th,nil); if not ok then self.status=tostring(err); self.lines={tostring(err)}; self:markV131(); return false end; self:markV131(); return true
end
function Web:cancel() self:cancelJobV131("Cancelled") end
function Web:clearCacheV131() local ok,err=imageCacheClear(); local rawOk,rawErr=true,nil; if type(E.imageHttpCacheClear)=="function" then rawOk,rawErr=pcall(E.imageHttpCacheClear); rawOk=rawOk and rawErr~=false end; ok=ok and rawOk; self.cacheNotice=ok and "Image cache cleared" or tostring(err or rawErr); notify(self.cacheNotice,ok and P.success or P.error); self:markV131() end
function Web:openImageV131() if not self.imageData and not self.nativeImage then return end; local w=openApp("image"); if w and self.imagePath then appCall(w,"loadPath",self.imagePath) elseif self.rawPngBody then notify("Save the image as PNG first",P.warning) elseif self.imageData then notify("Save the image before opening it",P.warning) end end
function Web:saveHcciV131()
    if self.rawPngBody then
        saveRawPngDialog(self.rawPngBody,fs.combine(imageStorage,"web_image.png"))
        return
    end
    if self.nativeImage and self.imagePath then
        dialog("Save PNG Image","Absolute .png path",{"Save","Cancel"},function(b,value)
            if b~="Save" then return end
            value=tostring(value or ""); if not value:lower():match("%.png$") then value=value..".png" end
            local ok,err=pcall(function()
                local dir=fs.getDir(value); if dir~="" and not fs.exists(dir) then fs.makeDir(dir) end
                fs.copy(self.imagePath,value)
            end)
            if ok then notify("PNG image saved",P.success) else errorBox(err) end
        end,fs.combine(imageStorage,"web_image.png"))
        return
    end
    if not self.imageData then return end
    dialog("Save HCC Image","Absolute .hcci path",{"Save","Cancel"},function(b,value) if b=="Save" then value=tostring(value or ""); if value:sub(-5):lower()~=".hcci" then value=value..".hcci" end; local ok,err=imageWrite(value,self.imageData); if ok then self.imagePath=value; notify("Saved "..value,P.success) else errorBox(err) end end end,fs.combine(imageStorage,"web_image.hcci"))
end
function Web:setWallpaperV131()
    if self.rawPngBody then
        local path=imagePathFor("wallpaper_"..tostring(floor(now()*1000))..".png",#self.rawPngBody)
        local stored,storeError=writeRawPng(path,self.rawPngBody)
        if not stored then errorBox("Could not save original PNG: "..tostring(storeError)); return end
        cfg.wallpaperPath=path; cfg.wallpaperMode="center"; resetWallpaperCache(); local ok,err=saveConfig(); allDirty()
        if ok then notify("PNG wallpaper set (center)",P.success) else errorBox(err) end
        return
    end
    if self.nativeImage and self.imagePath then
        local path,storeError=persistNativePng(self.imagePath,self.url)
        if not path then errorBox(storeError); return end
        cfg.wallpaperPath=path; cfg.wallpaperMode="center"; resetWallpaperCache(); local ok,err=saveConfig(); allDirty()
        if ok then notify("PNG wallpaper set (center)",P.success) else errorBox(err) end
        return
    end
    if not self.imageData then return end
    local path=self.imagePath
    if not path then
        local alias=self:cacheAliasV131(self.url,max(64,(self.win and self.win.w or 576)-14),max(64,(self.win and self.win.h or 360)-TITLE-115)); local ok=imageCacheSave(alias,self.imageData)
        if ok then path=imageCachePath(alias) else
            path=fs.combine(imageStorage,"web_wallpaper_"..tostring(floor(now()*1000))..".hcci")
            local stored,storeError=imageWrite(path,self.imageData)
            if not stored then errorBox("Could not save image as HCCI: "..tostring(storeError)); return end
        end
        self.imagePath=path
    end
    cfg.wallpaperPath=path; cfg.wallpaperMode="fit"; resetWallpaperCache(); local ok,err=saveConfig(); allDirty(); if ok then notify("Wallpaper set from converted HCCI",P.success) else errorBox(err) end
end
function Web:downloadV131() Web.download(self) end
function Web:closeV131()
    self:cancelJobV131()
    if self.nativeImage then nativeFree(self.nativeImage); self.nativeImage=nil end
    for _,item in ipairs(self.pageImages or {}) do if item.nativeImage then nativeFree(item.nativeImage); item.nativeImage=nil end end
    for path in pairs(self.nativeTempPaths or {}) do nativeDelete(path) end
    self.nativeTempPaths={}
end
function Web:drawV131(c)
    c:text(6,5,"HCC WEB",P.accent); c:text(6,19,self.title:sub(1,42),P.textPrimary)
    button(self,c,5,33,42,"BACK",function() self:back() end); button(self,c,51,33,48,"FORWARD",function() self:forward() end); button(self,c,103,33,48,"RELOAD",function() self:reload() end); button(self,c,156,33,39,"GO",function() self:goDialog() end); button(self,c,200,33,72,"DOWNLOAD",function() self:downloadV131() end); button(self,c,277,33,48,"CACHE",function() self:clearCacheV131() end); button(self,c,330,33,58,"CANCEL",function() self:cancel() end)
    local uw=max(20,c.w-10); c:filledRectangle(5,52,uw,15,P.panelBackground); c:rectangle(5,52,uw,15,P.border); c:text(9,55,self.url=="" and "URL / SEARCH" or self.url,P.textPrimary); c:text(6,70,self.status,P.textSecondary); c:line(0,76,c.w-1,76,P.border)
    if self.pageMode=="image" and (self.imageData or self.nativeImage) then
        local pv=c:clipping(5,82,c.w-10,max(20,c.h-111)); Widget.panel(pv,0,0,pv.w,pv.h,0xFF050505,P.border)
        if self.nativeImage then pv:nativeImage(2,2,self.nativeImage,"center") else drawImage(pv,self.imageData,2,2,pv.w-4,pv.h-4,"fit",1,0,0) end
        button(self,c,5,c.h-25,78,"OPEN IMAGE",function() self:openImageV131() end); button(self,c,87,c.h-25,70,(self.rawPngBody or self.nativeImage) and "SAVE PNG" or "SAVE HCCI",function() self:saveHcciV131() end); button(self,c,161,c.h-25,82,"WALLPAPER",function() self:setWallpaperV131() end); c:text(248,c.h-20,self.cacheNotice,P.warning)
    else
        local pw=175; local lw=max(30,c.w-pw-12); local rows=max(1,floor((c.h-111)/12)); self.top=clamp(self.top,1,max(1,#self.lines-rows+1)); local body=c:clipping(5,82,lw,rows*12+2); Widget.panel(body,0,0,body.w,body.h,0xFF050505,P.border)
        for i=0,rows-1 do local line=self.lines[self.top+i]; if not line then break end; body:text(3,3+i*12,line,P.textPrimary) end
        local pv=c:clipping(c.w-pw-3,82,pw,max(20,c.h-111)); Widget.panel(pv,0,0,pv.w,pv.h,0xFF050505,P.border); local item=self.pageImages and self.pageImages[self.imageIndex]; if item and item.nativeImage then pv:nativeImage(2,2,item.nativeImage,"center"); pv:text(4,pv.h-17,"IMG "..self.imageIndex.."/"..#self.pageImages,P.textSecondary) elseif item and item.data then drawImage(pv,item.data,2,2,pv.w-4,pv.h-25,"fit",1,0,0); pv:text(4,pv.h-17,"IMG "..self.imageIndex.."/"..#self.pageImages,P.textSecondary) else pv:paragraph(6,16,"Images load after page text.",P.textSecondary,pv.w-12,2) end
        button(self,c,c.w-pw-1,c.h-25,47,"NEXT",function() self.imageIndex=self.imageIndex%max(1,#self.pageImages)+1; mark(self.win) end); c:text(6,c.h-14,string.format("%d lines  %d links  %d images  Q cancel",#self.lines,#self.links,#self.pageImages),P.textSecondary)
    end
end
Web.init=Web.initV131; Web.load=Web.loadV131; Web.interval=Web.interval; Web.update=Web.updateV131; Web.onHttpSuccess=Web.onHttpSuccessV131; Web.onHttpFailure=Web.onHttpFailureV131; Web.draw=Web.drawV131; Web.close=Web.closeV131
end

end

-- HCC OS v1.4 GUI application module.
return function(E)
    local env=setmetatable({Driver=E.AppDriver,OS=E.AppOS},{__index=E})
    local _ENV=env
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
    local path=fs.combine("/.hccos/downloads",filename)
    local save=function() local ok,err=pcall(function() if not fs.exists("/.hccos/downloads") then fs.makeDir("/.hccos/downloads") end; local f,e=fs.open(path,"w"); if not f then error(e) end; f.write(self.body); f.close() end); if ok then notify("Downloaded "..path,P.success) else errorBox(err) end end
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
register("web","HCC Web","WB",548,286,Web)

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
function Web:interval() return self.job and (self.job.stage=="wait" and 1 or 0.05) or 1 end
function Web:markV131() if self.win then mark(self.win) end end
function Web:cancelJobV131(message)
    if self.job and self.job.handle and self.job.handle.close then pcall(self.job.handle.close) end
    self.job=nil; if message then self.status=message; self:markV131() end
end
function Web:headersV131(handle)
    local out={}; if handle and type(handle.getResponseHeaders)=="function" then local ok,h=pcall(handle.getResponseHeaders); if ok and type(h)=="table" then for k,v in pairs(h) do out[tostring(k):lower()]=tostring(v) end end end; return out
end
function Web:imageKindV131(url,contentType)
    local c=tostring(contentType or ""):lower():match("^[^;]+") or ""; local u=tostring(url):lower()
    if c=="image/png" or u:match("%.png$") or u:match("%.png[?#]") then return "png" end
    if c=="image/jpeg" or c=="image/jpg" or u:match("%.jpe?g$") or u:match("%.jpe?g[?#]") then return "jpeg" end
    if c=="image/hcci" or u:match("%.hcci$") or u:match("%.hcci[?#]") then return "hcci" end
end
function Web:cacheAliasV131(url,w,h) return table.concat({url,"image",tostring(w).."x"..tostring(h)},"|") end
function Web:cacheKeyV131(url,w,h,ctype,length) return table.concat({url,"image",tostring(w).."x"..tostring(h),tostring(ctype or ""),tostring(length or "")},"|") end
function Web:progressV131(stage,value)
    self.status=finite(value) and stage.." "..tostring(clamp(floor(value*100+0.5),0,100)).."%" or stage; self:markV131()
end
function Web:showImageV131(data,path,url,cacheHit)
    self.pageMode="image"; self.imageData=data; self.imagePath=path; self.title=fs.getName(url or self.url):sub(1,48); self.lines={"Direct image view",cacheHit and "Loaded from Image Cache" or "PNG/JPEG converted to HCCI v2"}; self.status=cacheHit and "Image Cache hit" or "Image ready"; self:markV131()
end
function Web:finishImageV131(item,data,cacheKey,alias)
    local saved,err=imageCacheSave(alias,data); if saved and cacheKey~=alias then imageCacheSave(cacheKey,data) end
    local path=saved and imageCachePath(alias) or nil; self.cacheNotice=saved and "" or "Cache unavailable: "..tostring(err)
    if item then item.data=data; item.path=path; item.status=saved and "ready" or "ready (uncached)"; webImageStatusLine(self.lines,item.index,item.status); self.job=nil; self:progressV131("Rendering...",1); self:queueNextImageV131()
    else self.job=nil; self:showImageV131(data,path,self.url,false) end
end
function Web:startConversionV131(body,url,ctype,length,targetW,targetH,item)
    local kind=self:imageKindV131(url,ctype); if not kind then return false,"unsupported image type" end
    local alias=self:cacheAliasV131(url,targetW,targetH); local exact=self:cacheKeyV131(url,targetW,targetH,ctype,length); local cached=imageCacheLoad(alias)
    if cached then if item then self:finishImageV131(item,cached,exact,alias) else self:showImageV131(cached,imageCachePath(alias),url,true) end; return true end
    local co=coroutine.create(function()
        local decoded
        if kind=="png" then decoded=pngDecode(body,function(p) coroutine.yield("Decoding PNG...",p) end)
        elseif kind=="jpeg" then decoded=jpegDecode(body,function(p) coroutine.yield("Decoding JPEG...",p) end)
        else
            coroutine.yield("Decoding HCCI...",0.5); local ok,raw=pcall(textutils.unserialize,body); if not ok then error(raw) end; decoded=imageNormalize(raw); if not decoded then error("invalid HCCI image") end
        end
        local data,stored,size=imagePrepare(decoded,targetW,targetH,function(stage,p) coroutine.yield(stage,p) end)
        return data,stored,size,exact,alias
    end)
    self.job={stage="convert",co=co,item=item,url=url,cacheKey=exact,alias=alias}; self:progressV131(kind=="png" and "Decoding PNG..." or kind=="jpeg" and "Decoding JPEG..." or "Decoding HCCI...",0); return true
end
function Web:startRequestV131(url,kind,targetW,targetH,item)
    if type(http)~="table" or type(http.request)~="function" then return false,"CC:T HTTP request API unavailable" end
    local ok,accepted=pcall(http.request,url,nil,{["User-Agent"]="HCC-Web/1.3.1"},true); if not ok or accepted==false or accepted==nil then return false,"HTTP request failed or denied" end
    self.job={stage="wait",kind=kind,url=url,item=item,targetW=targetW,targetH=targetH}; self:progressV131("Downloading...",0); return true
end
function Web:onHttpSuccessV131(url,handle)
    if not self.job or self.job.url~=url then if handle and handle.close then pcall(handle.close) end; return end
    local h=self:headersV131(handle); local length=tonumber(h["content-length"] or "")
    if length and length>cfg.maxImageDownload then if handle.close then pcall(handle.close) end; self.job=nil; self.status="Image too large"; self.lines={"Download refused: Content-Length exceeds configured limit."}; self:markV131(); return end
    self.job.handle=handle; self.job.stage="download"; self.job.parts={}; self.job.bytes=0; self.job.contentType=h["content-type"] or ""; self.job.length=length; self.job.code=200
    if type(handle.getResponseCode)=="function" then local ok,code=pcall(handle.getResponseCode); if ok and finite(code) then self.job.code=code end end
end
function Web:onHttpFailureV131(url,reason)
    if not self.job or self.job.url~=url then return end
    local item=self.job.item; self.job=nil; self.status="HTTP request failed"; self.lines={"HTTP request failed: "..tostring(reason or "unknown error")}; if item then item.status="failed"; webImageStatusLine(self.lines,item.index,"failed") end; self:markV131(); if self.pageMode=="html" then self:queueNextImageV131() end
end
function Web:bodyReadyV131(job,body)
    if #body>cfg.maxImageDownload then self.job=nil; self.status="Image too large"; self.lines={"Download refused: response exceeds configured limit."}; self:markV131(); return end
    local kind=self:imageKindV131(job.url,job.contentType)
    if kind then self:startConversionV131(body,job.url,job.contentType,job.length,job.targetW or min(576,self.win and self.win.w or 576),job.targetH or min(320,self.win and self.win.h or 320),job.item); return end
    self.body=body; self.title,self.lines,self.links,self.pageImages=webParseV131(body,job.url); self.lines=webJsonLines(body) or self.lines; self.pageMode="html"; self.imageData=nil; self.imagePath=nil; self.linkSelected=1; self.top=1; self.job=nil; self.status="HTTP "..tostring(job.code or 200).."  "..#body.." bytes"; self:markV131(); self:queueNextImageV131()
end
function Web:updateV131()
    local job=self.job; if not job or job.stage=="wait" then return end
    if job.stage=="download" then
        local chunk; local ok=pcall(function() chunk=job.handle.read(16384) end)
        if not ok then if job.handle.close then pcall(job.handle.close) end; self.job=nil; self.status="Read failed"; self.lines={"Response body could not be read."}; self:markV131(); return end
        if chunk and #chunk>0 then job.parts[#job.parts+1]=chunk; job.bytes=job.bytes+#chunk; if job.bytes>cfg.maxImageDownload then if job.handle.close then pcall(job.handle.close) end; self.job=nil; self.status="Image too large"; self.lines={"Download refused: response exceeds configured limit."}; self:markV131(); return end; self:progressV131("Downloading...",job.length and job.bytes/job.length or 0); return end
        if job.handle.close then pcall(job.handle.close) end; self:bodyReadyV131(job,table.concat(job.parts)); return
    end
    if job.stage=="convert" then
        local ok,a,b,c,d,e=coroutine.resume(job.co)
        if not ok then
            local reason=tostring(a or "unknown image decoder error")
            local item=job.item; self.job=nil; self.status="Image conversion failed: "..reason
            if item then item.status="failed"; webImageStatusLine(self.lines,item.index,"failed: "..reason:sub(1,96)); self:markV131(); self:queueNextImageV131()
            else self.lines={"Image conversion failed:",reason}; self:markV131() end
            return
        end
        if coroutine.status(job.co)=="dead" then self:finishImageV131(job.item,a,d,e) else self:progressV131(a,b) end
    end
end
function Web:queueNextImageV131()
    if self.pageMode~="html" or self.job then return end
    for i,item in ipairs(self.pageImages or {}) do
        item.index=i
        if item.status=="pending" then
            self.imageIndex=i; local tw=max(64,min(384,(self.win and self.win.w or 548)-190)); local th=max(64,min(200,(self.win and self.win.h or 286)-110)); local ok,err=self:startRequestV131(item.url,"image",tw,th,item)
            if not ok then item.status="failed"; webImageStatusLine(self.lines,i,"failed"); self.status=tostring(err); self:markV131(); return self:queueNextImageV131() end
            return
        end
    end
    if #self.pageImages>0 then self.status="Page ready / images loaded"; self:markV131() end
end
function Web:initV131(url)
    self.url=""; self.status="Ready"; self.title="HCC Web"; self.lines={"Enter an HTTP/HTTPS URL and press GO."}; self.links={}; self.linkSelected=1; self.top=1; self.body=""; self.history={}; self.historyIndex=0; self.job=nil; self.pageMode="text"; self.pageImages={}; self.imageData=nil; self.imagePath=nil; self.imageIndex=1; self.cacheNotice=""
    if type(url)=="string" and url~="" then self:loadV131(url,true) end
end
function Web:loadV131(url,record)
    url=webSafeUrl(url); if not url then self.status="Invalid URL"; self.lines={"Only http:// and https:// URLs are allowed."}; self:markV131(); return false end
    self:cancelJobV131(); self.url=url; self.pageMode="text"; self.pageImages={}; self.imageData=nil; self.imagePath=nil; self.title="HCC Web"; self.lines={"Downloading..."}; self.linkSelected=1; self.top=1
    if record~=false then for i=#self.history,self.historyIndex+1,-1 do table.remove(self.history,i) end; self.history[#self.history+1]=url; self.historyIndex=#self.history end
    local kind=self:imageKindV131(url,""); if kind then local tw=min(576,self.win and self.win.w or 576); local th=min(320,self.win and self.win.h or 320); local alias=self:cacheAliasV131(url,tw,th); local cached=imageCacheLoad(alias); if cached then self:showImageV131(cached,imageCachePath(alias),url,true); return true end end
    local ok,err=self:startRequestV131(url,"page",nil,nil,nil); if not ok then self.status=tostring(err); self.lines={tostring(err)}; self:markV131(); return false end; self:markV131(); return true
end
function Web:cancel() self:cancelJobV131("Cancelled") end
function Web:clearCacheV131() local ok,err=imageCacheClear(); self.cacheNotice=ok and "Image cache cleared" or tostring(err); notify(self.cacheNotice,ok and P.success or P.error); self:markV131() end
function Web:openImageV131() if not self.imageData then return end; local w=openApp("image"); if w and self.imagePath then appCall(w,"loadPath",self.imagePath) elseif self.imageData then notify("Save the image as HCCI first",P.warning) end end
function Web:saveHcciV131()
    if not self.imageData then return end
    dialog("Save HCC Image","Absolute .hcci path",{"Save","Cancel"},function(b,value) if b=="Save" then value=tostring(value or ""); if value:sub(-5):lower()~=".hcci" then value=value..".hcci" end; local ok,err=imageWrite(value,self.imageData); if ok then self.imagePath=value; notify("Saved "..value,P.success) else errorBox(err) end end end,"/.hccos/images/web_image.hcci")
end
function Web:setWallpaperV131()
    if not self.imageData then return end; local path=self.imagePath; if not path then local alias=self:cacheAliasV131(self.url,576,320); local ok=imageCacheSave(alias,self.imageData); if ok then path=imageCachePath(alias); self.imagePath=path end end
    if not path then errorBox("Image cache unavailable; save as HCCI first"); return end
    cfg.wallpaperPath=path; cfg.wallpaperMode="fit"; resetWallpaperCache(); local ok,err=saveConfig(); allDirty(); if ok then notify("Wallpaper set from converted HCCI",P.success) else errorBox(err) end
end
function Web:downloadV131() Web.download(self) end
function Web:closeV131() self:cancelJobV131() end
function Web:drawV131(c)
    c:text(6,5,"HCC WEB",P.accent); c:text(6,19,self.title:sub(1,42),P.textPrimary)
    button(self,c,5,33,42,"BACK",function() self:back() end); button(self,c,51,33,48,"FORWARD",function() self:forward() end); button(self,c,103,33,48,"RELOAD",function() self:reload() end); button(self,c,156,33,39,"GO",function() self:goDialog() end); button(self,c,200,33,72,"DOWNLOAD",function() self:downloadV131() end); button(self,c,277,33,48,"CACHE",function() self:clearCacheV131() end); button(self,c,330,33,58,"CANCEL",function() self:cancel() end)
    local uw=max(20,c.w-10); c:filledRectangle(5,52,uw,15,P.panelBackground); c:rectangle(5,52,uw,15,P.border); c:text(9,55,self.url=="" and "URL / SEARCH" or self.url,P.textPrimary); c:text(6,70,self.status,P.textSecondary); c:line(0,76,c.w-1,76,P.border)
    if self.pageMode=="image" and self.imageData then
        local pv=c:clipping(5,82,c.w-10,max(20,c.h-111)); Widget.panel(pv,0,0,pv.w,pv.h,0xFF050505,P.border); drawImage(pv,self.imageData,2,2,pv.w-4,pv.h-4,"fit",1,0,0); button(self,c,5,c.h-25,78,"OPEN IMAGE",function() self:openImageV131() end); button(self,c,87,c.h-25,70,"SAVE HCCI",function() self:saveHcciV131() end); button(self,c,161,c.h-25,82,"WALLPAPER",function() self:setWallpaperV131() end); c:text(248,c.h-20,self.cacheNotice,P.warning)
    else
        local pw=175; local lw=max(30,c.w-pw-12); local rows=max(1,floor((c.h-111)/12)); self.top=clamp(self.top,1,max(1,#self.lines-rows+1)); local body=c:clipping(5,82,lw,rows*12+2); Widget.panel(body,0,0,body.w,body.h,0xFF050505,P.border)
        for i=0,rows-1 do local line=self.lines[self.top+i]; if not line then break end; body:text(3,3+i*12,line,P.textPrimary) end
        local pv=c:clipping(c.w-pw-3,82,pw,max(20,c.h-111)); Widget.panel(pv,0,0,pv.w,pv.h,0xFF050505,P.border); local item=self.pageImages and self.pageImages[self.imageIndex]; if item and item.data then drawImage(pv,item.data,2,2,pv.w-4,pv.h-25,"fit",1,0,0); pv:text(4,pv.h-17,"IMG "..self.imageIndex.."/"..#self.pageImages,P.textSecondary) else pv:paragraph(6,16,"Images load after page text.",P.textSecondary,pv.w-12,2) end
        button(self,c,c.w-pw-1,c.h-25,47,"NEXT",function() self.imageIndex=self.imageIndex%max(1,#self.pageImages)+1; mark(self.win) end); c:text(6,c.h-14,string.format("%d lines  %d links  %d images  Q cancel",#self.lines,#self.links,#self.pageImages),P.textSecondary)
    end
end
Web.init=Web.initV131; Web.load=Web.loadV131; Web.interval=Web.interval; Web.update=Web.updateV131; Web.onHttpSuccess=Web.onHttpSuccessV131; Web.onHttpFailure=Web.onHttpFailureV131; Web.draw=Web.drawV131; Web.close=Web.closeV131
end

end

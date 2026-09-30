return function(E)
 local env=setmetatable({},{__index=E})
    local _ENV=env
local TomGpu
if type(require)=="function" then
    local ok,value=pcall(require,"hcc.tom_gpu")
    if ok and type(value)=="table" then TomGpu=value end
end
local devices={list={},keyboards={},inventories={},modems={},gpuAvailable=false,keyboardAvailable=false,
    detectorAvailable=false,detectorApi={},detectorCapabilities={}}
local gpu
local keyboardDevices={}
local nativeImageDrawUnavailable=false
local nativeImageDrawError=nil
local Driver={w=576,h=320,logicalWidth=576,logicalHeight=320,physicalWidth=576,physicalHeight=320,
    scale=1,offsetX=0,offsetY=0,metrics={},cellWidth=6,calls=0,syncs=0,error=nil}
local function updateViewport()
    local userScale=cfg.uiScale==2 and 2 or 1
    Driver.logicalWidth=floor(E.HCC_TARGET_W/userScale)
    Driver.logicalHeight=floor(E.HCC_TARGET_H/userScale)
    Driver.w,Driver.h=Driver.logicalWidth,Driver.logicalHeight
    Driver.scale=min(Driver.physicalWidth/Driver.logicalWidth,Driver.physicalHeight/Driver.logicalHeight)
    Driver.offsetX=(Driver.physicalWidth-Driver.logicalWidth*Driver.scale)/2
    Driver.offsetY=(Driver.physicalHeight-Driver.logicalHeight*Driver.scale)/2
    Driver.metrics={}
end
function Driver.setUIScale(value)
    if value~=1 and value~=2 then return false,"UI scale must be 1 or 2" end
    cfg.uiScale=value
    updateViewport()
    return true
end
local function wasTerminated(value) return tostring(value or ""):lower():find("terminated",1,true)~=nil end
local function scanDevices()
    nativeImageDrawUnavailable=false; nativeImageDrawError=nil
    devices.list={}; devices.detector=nil; devices.detectorName=nil; devices.detectorApi={}; devices.detectorCapabilities={}
    devices.keyboards={}; devices.inventories={}; devices.modems={}
    devices.gpuCapabilities={}; devices.backend="tom_gpu"
    devices.gpuAvailable=false; devices.keyboardAvailable=false; devices.detectorAvailable=false
    local candidates={}; keyboardDevices={}
    local registry=context and context.capabilities
    if not registry then
        local ok,value=pcall(function() return require("core.capabilities") end)
        if ok and type(value)=="table" and type(value.new)=="function" then
            registry=value.new({api=peripheral,logger=context and context.logger})
            if context then context.capabilities=registry end
        end
    end
    if not registry or type(registry.scan)~="function" then
        gpu=nil; devices.gpuName=nil; Driver.error="Peripheral capability registry unavailable"
        logLine("ERROR",Driver.error); return false
    end
    local scanOk,records,scanError=pcall(registry.scan,registry)
    if not scanOk then scanError=records; records={} end
    if type(records)~="table" then records={}; scanError=scanError or "Peripheral enumeration failed" end
    if scanError and wasTerminated(scanError) then return false,"terminate" end
    for _,record in ipairs(records) do
        local name=record.name
        local p=record.handle
        local types=record.types or {}
        local found=record.capabilities or {}
        devices.list[#devices.list+1]={name=name,kind=#types>0 and table.concat(types,",") or "unknown"}
        if p then
            if found.tom_gpu then
                local capabilities={}
                if TomGpu and type(TomGpu.capabilities)=="function" then
                    local capsOk,value=pcall(TomGpu.capabilities,p)
                    if not capsOk and wasTerminated(value) then return false,"terminate" end
                    if capsOk and type(value)=="table" then capabilities=value
                    elseif not capsOk then logLine("WARN",name.." GPU capability query failed: "..tostring(value)) end
                end
                candidates[#candidates+1]={name=name,p=p,capabilities=capabilities}
            end
            if found.player_detector and (cfg.detectorName=="" or name==cfg.detectorName) and
                (not devices.detector or (found.player_radar and not devices.detectorCapabilities.player_radar)) then
                devices.detector=p; devices.detectorName=name; devices.detectorApi=found.detector_methods or {}
                devices.detectorCapabilities=found
            end
            if found.tom_keyboard and (cfg.keyboardName=="" or name==cfg.keyboardName) then
                keyboardDevices[name]=p
                devices.keyboards[name]=true
            end
            if found.inventory then devices.inventories[#devices.inventories+1]={name=name,p=p} end
            if found.modem then
                local wireless=false
                if type(p.isWireless)=="function" then
                    local wok,wvalue=pcall(p.isWireless)
                    if not wok and wasTerminated(wvalue) then return false,"terminate" end
                    wireless=wok and wvalue==true
                end
                devices.modems[#devices.modems+1]={name=name,p=p,wireless=wireless}
            end
        end
    end
    local chosen
    for _,candidate in ipairs(candidates) do
        if cfg.gpuName~="" and candidate.name==cfg.gpuName then chosen=candidate; break end
    end
    chosen=chosen or candidates[1]
    gpu=chosen and chosen.p or nil
    devices.gpuName=chosen and chosen.name or nil
    devices.gpuCapabilities=chosen and chosen.capabilities or {}
    devices.backend="tom_gpu"
    Driver.error=not gpu and (scanError or "Tom's GPU not found") or nil; Driver.metrics={}
    if gpu then
        local ok,err=pcall(gpu.refreshSize)
        if not ok and wasTerminated(err) then gpu=nil; Driver.error="Terminated"; return false,"terminate" end
        if ok then
            -- refreshSize is queued on the server thread. Yield without
            -- allowing a protected call to consume the terminate event.
            local refreshTimer,timerError=E.startSystemTimer(0.1,"gpu-refresh")
            if not refreshTimer then
                gpu=nil; Driver.error="GPU refresh timer unavailable: "..tostring(timerError)
                return false
            end
            local deferred={}; local refreshed=false
            while not refreshed do
                local event={os.pullEventRaw()}
                if event[1]=="terminate" then
                    E.cancelSystemTimer(refreshTimer); gpu=nil; Driver.error="Terminated"
                    return false,"terminate"
                end
                if event[1]=="timer" and event[2]==refreshTimer then
                    E.consumeSystemTimer(refreshTimer); refreshed=true
                else deferred[#deferred+1]=event end
            end
            for _,event in ipairs(deferred) do os.queueEvent(unpack(event)) end
        end
        if ok then ok,err=pcall(function()
            gpu.setSize(cfg.resolution)
            if gpu.setFont then gpu.setFont("ascii") end
            Driver.cellWidth=6
            local width=gpu.getTextLength("M",1,1)
            if finite(width) and width>0 then Driver.metrics.M=width; Driver.cellWidth=max(Driver.cellWidth,width) end
            local width,height=gpu.getSize()
            assert(finite(width) and finite(height) and width>=96 and height>=96,"Display must be at least 96x96")
            Driver.physicalWidth,Driver.physicalHeight=floor(width),floor(height)
            updateViewport()
        end) end
        if not ok and wasTerminated(err) then gpu=nil; Driver.error="Terminated"; return false,"terminate" end
        if not ok then
            Driver.error=tostring(err); gpu=nil
            if context and context.logger then pcall(context.logger.error,context.logger,"Tom's GPU initialization failed: "..Driver.error) end
        end
    end
    devices.gpuAvailable=gpu~=nil
    -- Recovery and GPU discovery run on the standard CraftOS terminal. Keep
    -- Tom keyboards in native mode until a usable bitmap display is ready so
    -- those paths receive ordinary key/char events instead of tm_keyboard_*.
    for name,keyboard in pairs(keyboardDevices) do
        local keyboardOk,keyboardError=pcall(keyboard.setFireNativeEvents,not devices.gpuAvailable)
        if not keyboardOk then
            if wasTerminated(keyboardError) then return false,"terminate" end
            devices.keyboards[name]=nil; keyboardDevices[name]=nil
            if context and context.logger then
                pcall(context.logger.warn,context.logger,name.." keyboard mode change failed: "..tostring(keyboardError))
            end
        end
    end
    devices.keyboardAvailable=next(devices.keyboards)~=nil
    devices.detectorAvailable=devices.detector~=nil
    return devices.gpuAvailable
end
function Driver.getWidth() return Driver.w end
function Driver.getHeight() return Driver.h end
function Driver.getActualSize()
    if gpu then
        local ok,w,h=pcall(gpu.getSize)
        if ok and finite(w) and finite(h) then return w,h end
    end
    return Driver.physicalWidth,Driver.physicalHeight
end
local function physicalPoint(x,y)
    return floor(Driver.offsetX+x*Driver.scale+0.5),floor(Driver.offsetY+y*Driver.scale+0.5)
end
local function physicalTextSize(scale)
    return max(1,floor(scale*Driver.scale+0.5))
end
function Driver.toLogical(x,y)
    if not (finite(x) and finite(y) and finite(Driver.scale) and Driver.scale>0) then return nil end
    local px,py=x-Driver.offsetX,y-Driver.offsetY
    local width,height=Driver.logicalWidth*Driver.scale,Driver.logicalHeight*Driver.scale
    if px<0 or py<0 or px>=width or py>=height then return nil end
    return floor(px/Driver.scale),floor(py/Driver.scale)
end
function Driver.getViewport()
    return {x=Driver.offsetX,y=Driver.offsetY,w=Driver.logicalWidth*Driver.scale,h=Driver.logicalHeight*Driver.scale}
end
function Driver.call(method,...)
    if not gpu then return false end
    local ok,err=pcall(gpu[method],...)
    if not ok then
        Driver.error=tostring(err); gpu=nil; devices.gpuAvailable=false
        if context and context.logger then pcall(context.logger.error,context.logger,"Tom's GPU "..tostring(method).." failed: "..Driver.error) end
        if wasTerminated(err) then error(err,0) end
        for name,keyboard in pairs(keyboardDevices) do
            local keyboardOk,keyboardError=pcall(keyboard.setFireNativeEvents,true)
            if not keyboardOk then
                if wasTerminated(keyboardError) then error(keyboardError,0) end
                devices.keyboards[name]=nil; keyboardDevices[name]=nil
                if context and context.logger then
                    pcall(context.logger.warn,context.logger,name.." keyboard terminal fallback failed: "..tostring(keyboardError))
                end
            end
        end
        devices.keyboardAvailable=next(devices.keyboards)~=nil
        return false
    end
    Driver.calls=Driver.calls+1
    return true
end
function Driver.clear(color) Driver.call("fill",color) end
function Driver.sync() if Driver.call("sync") then Driver.syncs=Driver.syncs+1 end end
function Driver.measure(s,scale)
    s=ascii(s); scale=finite(scale) and clamp(scale,1,4) or 1
    local fontSize=physicalTextSize(scale)
    local total=0
    for i=1,#s do
        local ch=s:sub(i,i)
        local key=ch..":"..fontSize
        if not Driver.metrics[key] then
            local ok,w=false,6
            if gpu then ok,w=pcall(gpu.getTextLength,ch,fontSize,1) end
            local physicalWidth=(ok and finite(w) and w>0) and w or 6
            Driver.metrics[key]=physicalWidth/Driver.scale
        end
        total=total+Driver.metrics[key]
    end
    return total
end
-- Liang-Barsky clipping: both endpoints outside can still cross the viewport.
local function clipLine(x1,y1,x2,y2,r)
    if r.w<1 or r.h<1 then return end
    local dx,dy=x2-x1,y2-y1; local lo,hi=0,1
    local pp={-dx,dx,-dy,dy}; local qq={x1-r.x,r.x+r.w-1-x1,y1-r.y,r.y+r.h-1-y1}
    for i=1,4 do
        if pp[i]==0 then if qq[i]<0 then return end
        else
            local t=qq[i]/pp[i]
            if pp[i]<0 then lo=max(lo,t) else hi=min(hi,t) end
            if lo>hi then return end
        end
    end
    return floor(clamp(x1+lo*dx+0.5,r.x,r.x+r.w-1)),floor(clamp(y1+lo*dy+0.5,r.y,r.y+r.h-1)),
        floor(clamp(x1+hi*dx+0.5,r.x,r.x+r.w-1)),floor(clamp(y1+hi*dy+0.5,r.y,r.y+r.h-1))
end
function Driver.filledRectangle(x,y,w,h,color,clip)
    if not (finite(x) and finite(y) and finite(w) and finite(h)) then return end
    local r=intersect(box(x,y,w,h),clip or box(0,0,Driver.w,Driver.h))
    if r then r=intersect(r,box(0,0,Driver.w,Driver.h)) end
    if r then
        local left=floor(Driver.offsetX+r.x*Driver.scale)
        local top=floor(Driver.offsetY+r.y*Driver.scale)
        local right=math.ceil(Driver.offsetX+(r.x+r.w)*Driver.scale)-1
        local bottom=math.ceil(Driver.offsetY+(r.y+r.h)*Driver.scale)-1
        left,top=max(0,left),max(0,top)
        right,bottom=min(Driver.physicalWidth-1,right),min(Driver.physicalHeight-1,bottom)
        if right>=left and bottom>=top then Driver.call("filledRectangle",left+1,top+1,right-left+1,bottom-top+1,color) end
    end
end
function Driver.pixel(x,y,color,clip) Driver.filledRectangle(x,y,1,1,color,clip) end
function Driver.line(x1,y1,x2,y2,color,clip)
    if not (finite(x1) and finite(y1) and finite(x2) and finite(y2)) then return end
    local r=intersect(clip or box(0,0,Driver.w,Driver.h),box(0,0,Driver.w,Driver.h))
    if not r then return end
    local a,b,c,d=clipLine(x1,y1,x2,y2,r)
    if a then
        local xStart,yStart=physicalPoint(a,b); local xEnd,yEnd=physicalPoint(c,d)
        xStart,yStart=clamp(xStart,0,Driver.physicalWidth-1),clamp(yStart,0,Driver.physicalHeight-1)
        xEnd,yEnd=clamp(xEnd,0,Driver.physicalWidth-1),clamp(yEnd,0,Driver.physicalHeight-1)
        Driver.call("line",xStart+1,yStart+1,xEnd+1,yEnd+1,color)
    end
end
function Driver.rectangle(x,y,w,h,color,clip)
    if not (finite(x) and finite(y) and finite(w) and finite(h)) or w<=0 or h<=0 then return end
    Driver.line(x,y,x+w-1,y,color,clip); Driver.line(x,y+h-1,x+w-1,y+h-1,color,clip)
    Driver.line(x,y,x,y+h-1,color,clip); Driver.line(x+w-1,y,x+w-1,y+h-1,color,clip)
end
function Driver.text(cmd)
    local r=cmd.bounds
    if r.x<0 or r.y<0 or r.x+r.w>Driver.w or r.y+r.h>Driver.h then return end
    local x,y=physicalPoint(r.x,r.y)
    Driver.call("drawText",x+1,y+1,cmd.value,cmd.color,-1,physicalTextSize(cmd.scale),1)
end
function Driver.drawTextSmart(x,y,value,color,scale,clip)
    scale=finite(scale) and floor(clamp(scale,1,4)) or 1
    local bounds=box(x,y,Driver.measure(value,scale),9*scale)
    local visible=intersect(bounds,clip or box(0,0,Driver.w,Driver.h))
    if visible and visible.x==bounds.x and visible.y==bounds.y and visible.w==bounds.w and visible.h==bounds.h then
        Driver.text({bounds=bounds,value=ascii(value),color=color,scale=scale})
    end
end
function Driver.nativePngAvailable()
    return gpu and not nativeImageDrawUnavailable and Driver.scale==1 and Driver.offsetX==0 and Driver.offsetY==0 and
        type(gpu.newBuffer)=="function" and type(gpu.decodeImage)=="function" and type(gpu.drawImage)=="function"
end
function Driver.decodePng(body)
    if type(body)~="string" or #body==0 then return nil,"empty PNG data" end
    if not Driver.nativePngAvailable() then return nil,"Tom's GPU native PNG API unavailable" end
    local buffer,image
    local ok,result=pcall(function()
        -- Tom's Peripherals 1.3.1 accepts an optional initial size for its
        -- LuaByteBuffer.  Use it when available so large PNGs do not depend
        -- on repeated implicit buffer growth.
        local created,createdValue=pcall(gpu.newBuffer,#body)
        if created then buffer=createdValue else buffer=gpu.newBuffer() end
        if not buffer or type(buffer.write)~="function" or type(buffer.ref)~="function" then error("Tom's GPU byte buffer API unavailable") end
        -- Keep the argument list conservative for CC:T and write the raw PNG
        -- bytes exactly as documented by Tom's LuaByteBuffer API.
        for first=1,#body,256 do
            local bytes={body:byte(first,min(#body,first+255))}
            buffer.write(unpack(bytes))
        end
        image=gpu.decodeImage(buffer.ref())
        if not image or type(image.ref)~="function" or type(image.getWidth)~="function" or type(image.getHeight)~="function" then error("Tom's GPU returned an invalid image") end
        local width,height=image.getWidth(),image.getHeight()
        if not (finite(width) and finite(height) and width>0 and height>0) then error("Tom's GPU image dimensions are invalid") end
        local reference=image.ref()
        if type(reference)~="string" or reference=="" then error("Tom's GPU image reference is invalid") end
        return {native=true,ref=reference,width=floor(width),height=floor(height),image=image,buffer=buffer}
    end)
    if buffer and type(buffer.free)=="function" then pcall(buffer.free) end
    if not ok then
        if image and type(image.free)=="function" then pcall(image.free) end
        return nil,tostring(result)
    end
    return result
end
function Driver.freeNativeImage(record)
    if type(record)~="table" or record.freed then return end
    record.freed=true
    if record.image and type(record.image.free)=="function" then pcall(record.image.free) end
end
function Driver.nativeImageFits(record,x,y,clip,canvasClip)
    if type(record)~="table" or record.freed or not (finite(record.width) and finite(record.height)) then return false end
    if Driver.scale~=1 or Driver.offsetX~=0 or Driver.offsetY~=0 then return false end
    local bounds=box(x,y,record.width,record.height); local screen=box(0,0,Driver.w,Driver.h)
    local function fullyVisible(area)
        local r=intersect(bounds,area)
        return r and r.x==x and r.y==y and r.w==record.width and r.h==record.height
    end
    return fullyVisible(screen) and fullyVisible(clip or screen) and fullyVisible(canvasClip or screen)
end
function Driver.drawNativeImage(x,y,record,clip,canvasClip)
    if not gpu then return false,"GPU unavailable" end
    if nativeImageDrawUnavailable then return false,nativeImageDrawError end
    if not Driver.nativeImageFits(record,x,y,clip,canvasClip) then return false,"native image does not fit the active display area" end
    if type(gpu.drawImage)~="function" then
        nativeImageDrawUnavailable=true; nativeImageDrawError="Tom's GPU native image drawing is unavailable"
        if context and context.logger then pcall(context.logger.warn,context.logger,nativeImageDrawError) end
        return false,nativeImageDrawError
    end
    local ok,err=pcall(gpu.drawImage,x+1,y+1,record.ref)
    if not ok then
        nativeImageDrawUnavailable=true; nativeImageDrawError="Tom's GPU drawImage failed: "..tostring(err)
        if context and context.logger then pcall(context.logger.warn,context.logger,nativeImageDrawError) end
        return false,nativeImageDrawError
    end
    Driver.calls=Driver.calls+1
    return true
end
E.Driver=Driver; E.devices=devices; E.scanDevices=scanDevices; E.clipLine=clipLine
E.gpuAvailable=function() return gpu~=nil end
E.shutdownDisplay=function() if gpu then Driver.clear(0xFF000000); Driver.sync() end end
local allowed={w=true,h=true,logicalWidth=true,logicalHeight=true,physicalWidth=true,physicalHeight=true,
    scale=true,offsetX=true,offsetY=true,cellWidth=true,calls=true,syncs=true,error=true,measure=true,
    getWidth=true,getHeight=true,getActualSize=true,getViewport=true,setUIScale=true}
E.AppDriver=setmetatable({},{__index=function(_,key) if allowed[key] then return Driver[key] end end,__newindex=function() error("Application display access is read-only",2) end})

end

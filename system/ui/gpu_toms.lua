return function(E)
 local env=setmetatable({},{__index=E})
 local _ENV=env
local devices={list={},keyboards={},inventories={},modems={},gpuAvailable=false,keyboardAvailable=false,detectorAvailable=false}
local gpu
local Driver={w=576,h=320,metrics={},cellWidth=6,calls=0,syncs=0,error=nil}
local function hasMethods(p,names)
    if not p then return false end
    for _,n in ipairs(names) do if type(p[n])~="function" then return false end end
    return true
end
local function wasTerminated(value) return tostring(value or ""):lower():find("terminated",1,true)~=nil end
local function scanDevices()
    devices.list={}; devices.detector=nil; devices.detectorName=nil; devices.keyboards={}; devices.inventories={}; devices.modems={}
    devices.gpuAvailable=false; devices.keyboardAvailable=false; devices.detectorAvailable=false
    local candidates={}
    local namesOk,names=pcall(peripheral.getNames)
    if not namesOk and wasTerminated(names) then return false,"terminate" end
    if not namesOk or type(names)~="table" then gpu=nil; devices.gpuName=nil; Driver.error="Peripheral enumeration failed"; logLine("ERROR",Driver.error); return false end
    table.sort(names)
    for _,name in ipairs(names) do
        local ok,p=pcall(peripheral.wrap,name)
        local typeOk,typesValue=pcall(function() return {peripheral.getType(name)} end); local types=typeOk and typesValue or {"unknown"}
        if (not ok and wasTerminated(p)) or (not typeOk and wasTerminated(typesValue)) then return false,"terminate" end
        devices.list[#devices.list+1]={name=name,kind=table.concat(types,",")}
        if ok and p then
            if hasMethods(p,{"getSize","refreshSize","setSize","filledRectangle","line","drawText","getTextLength","sync","fill"}) then
                candidates[#candidates+1]={name=name,p=p}
            end
            if hasMethods(p,{"getOnlinePlayers","getPlayerPos"}) and
                (cfg.detectorName=="" or name==cfg.detectorName) and not devices.detector then
                devices.detector=p; devices.detectorName=name
            end
            if hasMethods(p,{"setFireNativeEvents"}) and (cfg.keyboardName=="" or name==cfg.keyboardName) then
                -- Keep peripheral names on events, enabling filtering and no mode mutation.
                local keyboardOk,keyboardError=pcall(p.setFireNativeEvents,false)
                if not keyboardOk and wasTerminated(keyboardError) then return false,"terminate" end
                devices.keyboards[name]=true
            end
            -- Inventory APIs vary between mods.  Classify only peripherals
            -- that expose both the standard list and size methods.
            if hasMethods(p,{"size","list"}) then
                devices.inventories[#devices.inventories+1]={name=name,p=p}
            end
            if hasMethods(p,{"open","close","isOpen","transmit"}) then
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
    for _,c in ipairs(candidates) do
        if cfg.gpuName~="" and c.name==cfg.gpuName then chosen=c; break end
        if cfg.gpuName=="" and (not chosen or c.name==devices.gpuName) then chosen=c end
    end
    gpu=chosen and chosen.p or nil
    devices.gpuName=chosen and chosen.name or nil
    Driver.error=nil; if not gpu then Driver.error="Tom's GPU not found" end; Driver.metrics={}
    if gpu then
        local ok,err=pcall(gpu.refreshSize)
        if not ok and wasTerminated(err) then gpu=nil; Driver.error="Terminated"; return false,"terminate" end
        if ok then
            -- refreshSize is queued on the server thread. Yield without
            -- allowing a protected call to consume the terminate event.
            local refreshTimer=os.startTimer(0.1)
            local deferred={}; local refreshed=false
            while not refreshed do
                local event={os.pullEventRaw()}
                if event[1]=="terminate" then
                    os.cancelTimer(refreshTimer); gpu=nil; Driver.error="Terminated"
                    return false,"terminate"
                end
                if event[1]=="timer" and event[2]==refreshTimer then refreshed=true
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
            local w,h=gpu.getSize()
            assert(finite(w) and finite(h) and w>=96 and h>=96,"Display must be at least 96x96")
            Driver.w,Driver.h=floor(w),floor(h)
        end) end
        if not ok and wasTerminated(err) then gpu=nil; Driver.error="Terminated"; return false,"terminate" end
        if not ok then
            Driver.error=tostring(err); gpu=nil
            if context and context.logger then pcall(context.logger.error,context.logger,"Tom's GPU initialization failed: "..Driver.error) end
        end
    end
    devices.gpuAvailable=gpu~=nil
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
    return Driver.w,Driver.h
end
function Driver.call(method,...)
    if not gpu then return end
    local ok,err=pcall(gpu[method],...)
    if not ok then
        Driver.error=tostring(err); gpu=nil
        if context and context.logger then pcall(context.logger.error,context.logger,"Tom's GPU "..tostring(method).." failed: "..Driver.error) end
        return
    end
    Driver.calls=Driver.calls+1
end
function Driver.clear(color) Driver.call("fill",color) end
function Driver.sync() if gpu then Driver.call("sync"); Driver.syncs=Driver.syncs+1 end end
function Driver.measure(s,scale)
    s=ascii(s); scale=scale or 1
    local total=0
    for i=1,#s do
        local ch=s:sub(i,i)
        if not Driver.metrics[ch] then
            local ok,w=false,6
            if gpu then ok,w=pcall(gpu.getTextLength,ch,1,1) end
            Driver.metrics[ch]=(ok and finite(w) and w>0) and w or 6
        end
        total=total+Driver.metrics[ch]*scale
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
    if r then Driver.call("filledRectangle",r.x+1,r.y+1,r.w,r.h,color) end
end
function Driver.pixel(x,y,color,clip) Driver.filledRectangle(x,y,1,1,color,clip) end
function Driver.line(x1,y1,x2,y2,color,clip)
    if not (finite(x1) and finite(y1) and finite(x2) and finite(y2)) then return end
    local r=intersect(clip or box(0,0,Driver.w,Driver.h),box(0,0,Driver.w,Driver.h))
    if not r then return end
    local a,b,c,d=clipLine(x1,y1,x2,y2,r)
    if a then Driver.call("line",a+1,b+1,c+1,d+1,color) end
end
function Driver.rectangle(x,y,w,h,color,clip)
    if not (finite(x) and finite(y) and finite(w) and finite(h)) or w<=0 or h<=0 then return end
    Driver.line(x,y,x+w-1,y,color,clip); Driver.line(x,y+h-1,x+w-1,y+h-1,color,clip)
    Driver.line(x,y,x,y+h-1,color,clip); Driver.line(x+w-1,y,x+w-1,y+h-1,color,clip)
end
function Driver.text(cmd)
    local r=cmd.bounds
    if r.x<0 or r.y<0 or r.x+r.w>Driver.w or r.y+r.h>Driver.h then return end
    Driver.call("drawText",r.x+1,r.y+1,cmd.value,cmd.color,-1,cmd.scale,1)
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
    return gpu and type(gpu.newBuffer)=="function" and type(gpu.decodeImage)=="function" and type(gpu.drawImage)=="function"
end
function Driver.decodePng(body)
    if type(body)~="string" or #body==0 then return nil,"empty PNG data" end
    if not Driver.nativePngAvailable() then return nil,"Tom's GPU native PNG API unavailable" end
    local buffer,image
    local ok,result=pcall(function()
        buffer=gpu.newBuffer()
        if type(buffer)~="table" or type(buffer.write)~="function" or type(buffer.ref)~="function" then error("Tom's GPU byte buffer API unavailable") end
        for first=1,#body,512 do
            local bytes={body:byte(first,min(#body,first+511))}
            buffer.write(unpack(bytes))
        end
        image=gpu.decodeImage(buffer.ref())
        if type(image)~="table" or type(image.ref)~="function" or type(image.getWidth)~="function" or type(image.getHeight)~="function" then error("Tom's GPU returned an invalid image") end
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
function Driver.nativeImageFits(record,x,y,clip)
    if type(record)~="table" or record.freed or not (finite(record.width) and finite(record.height)) then return false end
    local r=intersect(box(x,y,record.width,record.height),clip or box(0,0,Driver.w,Driver.h))
    return r and r.x==x and r.y==y and r.w==record.width and r.h==record.height
end
function Driver.drawNativeImage(x,y,record,clip)
    if not Driver.nativeImageFits(record,x,y,clip) or not gpu or type(gpu.drawImage)~="function" then return false end
    local ok,err=pcall(gpu.drawImage,x+1,y+1,record.ref)
    if not ok then
        Driver.error="Tom's GPU drawImage failed: "..tostring(err)
        if context and context.logger then pcall(context.logger.warn,context.logger,Driver.error) end
        return false
    end
    Driver.calls=Driver.calls+1
    return true
end
E.Driver=Driver; E.devices=devices; E.scanDevices=scanDevices; E.clipLine=clipLine
E.gpuAvailable=function() return gpu~=nil end
E.shutdownDisplay=function() if gpu then Driver.clear(0xFF000000); Driver.sync() end end
local allowed={w=true,h=true,cellWidth=true,calls=true,syncs=true,error=true,measure=true,getWidth=true,getHeight=true,getActualSize=true}
E.AppDriver=setmetatable({},{__index=function(_,key) if allowed[key] then return Driver[key] end end,__newindex=function() error("Application display access is read-only",2) end})

end

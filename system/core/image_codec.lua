return function(E)
 local env=setmetatable({},{__index=E})
 local _ENV=env
-- HCC Image ---------------------------------------------------------------
-- HCC OS owns this compact image format so it does not invent a PNG/JPEG
-- decoder.  A file is a serialized table with width, height and flat pixels:
-- {version=1,width=...,height=...,pixels={0xAARRGGBB,...}}.  RLE input is
-- also accepted as {rle={{color=...,count=...},...}} and is expanded safely.
local imageDir="/.hccos/images"
local imageCache={}
local imageToStored
local function imageColor(value)
    if type(value)=="number" and finite(value) then return floor(value)%4294967296 end
    if type(value)=="string" then
        local h=value:gsub("^#",""); if #h==6 then h="FF"..h end
        if #h==8 and h:match("^%x+$") then return tonumber(h,16) end
    end
end
local function imageNormalize(raw)
    if type(raw)~="table" then return nil,"not a table" end
    local w=tonumber(raw.width or raw.w); local h=tonumber(raw.height or raw.h)
    if not w or not h or not finite(w) or not finite(h) or w<1 or h<1 or w>1024 or h>768 or w*h>262144 then return nil,"image dimensions are unsafe" end
    w,h=floor(w),floor(h); local pixels={}; local source=raw.pixels; local palette={}
    if type(raw.palette)=="table" then for i=1,min(16,#raw.palette) do palette[i]=imageColor(raw.palette[i]) or 0xFF000000 end end
    if type(source)=="table" then
        local nested=type(source[1])=="table"
        for y=1,h do for x=1,w do
            local value=nested and source[y] and source[y][x] or source[(y-1)*w+x]
            pixels[(y-1)*w+x]=imageColor(value) or 0xFF000000
        end end
    elseif type(raw.rle)=="table" then
        for _,part in ipairs(raw.rle) do
            if type(part)=="table" then
                local rawIndex=part.index; local color
                if rawIndex==nil and type(part[1])=="number" and #palette>0 then rawIndex=part[1] end
                if rawIndex~=nil and #palette>0 then color=palette[floor(rawIndex)+1] end
                color=color or imageColor(part.color or part[1]) or 0xFF000000
                local count=floor(tonumber(part.count or part[2] or 0) or 0)
                for _=1,min(count,w*h-#pixels) do pixels[#pixels+1]=color end
            end
        end
        while #pixels<w*h do pixels[#pixels+1]=0xFF000000 end
    else return nil,"missing pixels or rle" end
    return {version=raw.version==2 and 2 or 1,width=w,height=h,pixels=pixels,palette=#palette>0 and palette or nil,rle=raw.version==2 and raw.rle or nil}
end
local function imageRead(path)
    if type(path)~="string" or path=="" or fs.isDir(path) then return nil,"invalid image path" end
    local ok,raw=pcall(function() return textutils.unserialize(readFile(path,4*1024*1024)) end)
    if not ok then return nil,tostring(raw) end
    return imageNormalize(raw)
end
local function imageWrite(path,data)
    if type(path)~="string" or path=="" or not data then return nil,"invalid image path" end
    local ok,err=pcall(function()
        local dir=fs.getDir(path); if dir~="" and not fs.exists(dir) then fs.makeDir(dir) end
        local f,e=fs.open(path,"w"); if not f then error(e or "image is not writable") end
        local stored=imageToStored and imageToStored(data) or data
        local good,reason=pcall(f.write,textutils.serialize(stored)); f.close(); if not good then error(reason) end
    end)
    return ok,err
end
local function imageList()
    if not fs.exists(imageDir) or not fs.isDir(imageDir) then return {} end
    local out={}; for _,name in ipairs(fs.list(imageDir)) do
        local path=fs.combine(imageDir,name); if not fs.isDir(path) and name:lower():match("%.hcci$") then out[#out+1]=path end
    end
    table.sort(out); return out
end
local function imagePixel(data,x,y)
    if not data or x<1 or y<1 or x>data.width or y>data.height then return 0xFF000000 end
    return data.pixels[(y-1)*data.width+x] or 0xFF000000
end
local function drawImage(c,data,x,y,w,h,mode,zoom,offsetX,offsetY)
    if not data or w<1 or h<1 then return end
    mode=mode or "fit"; zoom=clamp(tonumber(zoom) or 1,0.1,16); offsetX=offsetX or 0; offsetY=offsetY or 0
    local iw,ih=data.width,data.height; local sx,sy=zoom,zoom; local ox,oy=x+offsetX,y+offsetY
    if mode=="stretch" then sx,sy=w/iw,h/ih; ox,oy=x,y
    elseif mode=="fit" or mode=="fill" then
        local fitScale=min(w/iw,h/ih); local fillScale=max(w/iw,h/ih); sx,sy=(mode=="fit" and fitScale or fillScale),(mode=="fit" and fitScale or fillScale)
        ox=x+(w-iw*sx)/2+offsetX; oy=y+(h-ih*sy)/2+offsetY
    elseif mode=="center" then ox=x+(w-iw*sx)/2+offsetX; oy=y+(h-ih*sy)/2+offsetY end
    if mode=="tile" then sx,sy=zoom,zoom; ox=x+offsetX; oy=y+offsetY end
    local runs=0; local maxRuns=60000
    for dy=0,h-1 do
        local py=y+dy; local srcY=floor((py-oy)/sy)+1
        if mode=="tile" then srcY=((floor((py-oy)/sy))%ih)+1 end
        if srcY>=1 and srcY<=ih then
            local start=nil; local last=nil
            for dx=0,w-1 do
                local px=x+dx; local srcX=floor((px-ox)/sx)+1
                if mode=="tile" then srcX=((floor((px-ox)/sx))%iw)+1 end
                local color=(srcX>=1 and srcX<=iw) and imagePixel(data,srcX,srcY) or nil
                if color and color==last then
                    -- keep extending this horizontal run
                else
                    if last and start then c:filledRectangle(start,py,px-start,1,last); runs=runs+1 end
                    if color then start=px end; last=color
                end
                if runs>maxRuns then return end
            end
            if last and start then c:filledRectangle(start,py,x+w-start,1,last); runs=runs+1 end
        end
    end
end
local wallpaperCache={path=nil,renderKey=nil,data=nil,commands=nil}
local nativeWallpaperLoad
local function clearWallpaperCache()
    if wallpaperCache.data and wallpaperCache.data.native and type(Driver)=="table" and type(Driver.freeNativeImage)=="function" then Driver.freeNativeImage(wallpaperCache.data) end
    wallpaperCache={path=nil,renderKey=nil,data=nil,commands=nil}
end
local function getWallpaper()
    if cfg.wallpaperMode=="black" or cfg.wallpaperPath=="" then return nil end
    local key=cfg.wallpaperPath
    if wallpaperCache.path==key and wallpaperCache.data then return wallpaperCache.data end
    local data,err
    if cfg.wallpaperPath:lower():match("%.png$") and nativeWallpaperLoad then data,err=nativeWallpaperLoad(cfg.wallpaperPath,cfg.wallpaperMode,Driver.w,Driver.h-TASK) else data,err=imageRead(cfg.wallpaperPath) end
    if not data then logLine("WARN","Wallpaper unavailable: "..tostring(err)); cfg.wallpaperMode="black"; clearWallpaperCache(); return nil end
    wallpaperCache.path=key; wallpaperCache.data=data; wallpaperCache.renderKey=nil; wallpaperCache.commands=nil; return data
end
local function wallpaperCommands()
    local data=getWallpaper(); if not data then return nil end
    local key=table.concat({cfg.wallpaperPath,cfg.wallpaperMode,Driver.w,Driver.h-TASK},"|")
    if cfg.wallpaperCache and wallpaperCache.commands and wallpaperCache.renderKey==key then return wallpaperCache.commands end
    local list={}; local c=canvas(list,0,0,Driver.w,Driver.h-TASK)
    if data.native then c:nativeImage(0,0,data,"center") else drawImage(c,data,0,0,Driver.w,Driver.h-TASK,cfg.wallpaperMode,1,0,0) end
    if cfg.wallpaperCache then wallpaperCache.renderKey=key; wallpaperCache.commands=list end
    return list
end

-- Pure Lua image decoders ---------------------------------------------------
-- CC:Tweaked does not expose a PNG/JPEG decoder.  The following decoder is
-- deliberately bounded and is driven by ImagePipeline coroutines below.
local pngDecode,jpegDecode,imagePrepare
local imageCacheSave,imageCacheLoad,imageCacheClear,imageCachePath
do
local bit32lib=bit32
local function bitFallback(a,b,mode)
    a=(tonumber(a) or 0)%4294967296; b=(tonumber(b) or 0)%4294967296; local out=0; local place=1
    for _=1,32 do local aa=a%2; local bb=b%2; local yes=(mode=="and" and aa==1 and bb==1) or (mode=="or" and (aa==1 or bb==1)) or (mode=="xor" and aa~=bb); if yes then out=out+place end; a=floor(a/2); b=floor(b/2); place=place*2 end
    return out
end
local function band(a,b) return bit32lib and bit32lib.band(a,b) or bitFallback(a,b,"and") end
local function bor(a,b) return bit32lib and bit32lib.bor(a,b) or bitFallback(a,b,"or") end
local function bxor(a,b) return bit32lib and bit32lib.bxor(a,b) or bitFallback(a,b,"xor") end
local function reverseBits(value,count)
    local out=0; for i=1,count do out=out*2+(value%2); value=floor(value/2) end; return out
end
local function huffmanBuild(lengths)
    local count={}; for i=1,15 do count[i]=0 end
    for _,len in ipairs(lengths) do
        if type(len)~="number" or len~=floor(len) or len<0 or len>15 then error("invalid DEFLATE Huffman code length") end
        if len>0 then count[len]=count[len]+1 end
    end
    local nextCode={}; local code=0
    for bits=1,15 do code=(code+(count[bits-1] or 0))*2; nextCode[bits]=code end
    local tree={}
    for symbol,len in ipairs(lengths) do
        if len>0 then
            if nextCode[len]>=2^len then error("oversubscribed DEFLATE Huffman table") end
            tree[len]=tree[len] or {}; tree[len][reverseBits(nextCode[len],len)]=symbol-1; nextCode[len]=nextCode[len]+1
        end
    end
    return tree
end
local function huffmanDecode(reader,tree)
    local code=0
    for len=1,15 do
        local bit,err=reader:readBits(1); if bit==nil then return nil,err end
        code=code+bit*2^(len-1)
        if tree[len] and tree[len][code]~=nil then return tree[len][code] end
    end
    return nil,"invalid Huffman code"
end
local function newBitReader(data)
    local reader={data=data,pos=1,bits=0,buffer=0}
    function reader:readBits(count)
        if type(count)~="number" or count~=floor(count) or count<0 or count>16 then return nil,"invalid DEFLATE bit count" end
        while self.bits<count do
            local byte=self.data:byte(self.pos); if not byte then return nil,"unexpected end of compressed data" end
            self.pos=self.pos+1; self.buffer=self.buffer+byte*2^self.bits; self.bits=self.bits+8
        end
        local value=self.buffer%(2^count); self.buffer=floor(self.buffer/(2^count)); self.bits=self.bits-count; return value
    end
    function reader:align() self.bits=0; self.buffer=0 end
    return reader
end
local function deflateBits(reader,count,reason)
    local value,err=reader:readBits(count)
    if type(value)~="number" then error(reason or ("truncated DEFLATE input: "..tostring(err))) end
    return value
end
local fixedLit,fixedDist
do
    local lengths={}; for i=0,287 do lengths[i+1]=(i<=143 and 8) or (i<=255 and 9) or (i<=279 and 7) or 8 end
    local dists={}; for i=1,32 do dists[i]=5 end
    fixedLit,fixedDist=huffmanBuild(lengths),huffmanBuild(dists)
end
local lengthBase={3,4,5,6,7,8,9,10,11,13,15,17,19,23,27,31,35,43,51,59,67,83,99,115,131,163,195,227,258}
local lengthExtra={0,0,0,0,0,0,0,0,1,1,1,1,2,2,2,2,3,3,3,3,4,4,4,4,5,5,5,5,0}
local distanceBase={1,2,3,4,5,7,9,13,17,25,33,49,65,97,129,193,257,385,513,769,1025,1537,2049,3073,4097,6145,8193,12289,16385,24577}
local distanceExtra={0,0,0,0,1,1,2,2,3,3,4,4,5,5,6,6,7,7,8,8,9,9,10,10,11,11,12,12,13,13}
local function inflateRaw(data,limit,yieldFn)
    local reader=newBitReader(data); local output={}; local size=0; local final=false
    local function put(value)
        if type(value)~="number" then error("invalid DEFLATE byte") end
        size=size+1; if size>limit then error("decoded image exceeds safety limit") end
        output[size]=string.char(value%256)
        if yieldFn and size%4096==0 then yieldFn(size) end
    end
    while not final do
        final=deflateBits(reader,1,"truncated DEFLATE header")==1
        local kind=deflateBits(reader,2,"truncated DEFLATE header")
        local litTree,distTree
        if kind==0 then
            reader:align(); local len=deflateBits(reader,16,"truncated stored DEFLATE block"); local nlen=deflateBits(reader,16,"truncated stored DEFLATE block"); if (len%65536+nlen%65536)~=65535 then error("invalid stored DEFLATE block") end
            for _=1,len do put(deflateBits(reader,8,"truncated stored DEFLATE block")) end
        else
            if kind==1 then litTree,distTree=fixedLit,fixedDist
            elseif kind==2 then
                local hlit=deflateBits(reader,5,"truncated DEFLATE dynamic header")+257
                local hdist=deflateBits(reader,5,"truncated DEFLATE dynamic header")+1
                local hclen=deflateBits(reader,4,"truncated DEFLATE dynamic header")+4
                local order={16,17,18,0,8,7,9,6,10,5,11,4,12,3,13,2,14,1}; local cl={}; for i=1,19 do cl[i]=0 end
                for i=1,hclen do
                    local orderIndex=order[i]
                    if type(orderIndex)~="number" then error("invalid DEFLATE code length order") end
                    cl[orderIndex+1]=deflateBits(reader,3,"truncated DEFLATE code length")
                end
                local codeTree=huffmanBuild(cl); local all={}; local need=hlit+hdist
                while #all<need do
                    local symbol,decodeError=huffmanDecode(reader,codeTree); if type(symbol)~="number" then error("invalid DEFLATE code lengths: "..tostring(decodeError)) end
                    if symbol<=15 then all[#all+1]=symbol
                    elseif symbol==16 then
                        if #all==0 then error("invalid DEFLATE code length repeat") end
                        local repeatCount=deflateBits(reader,2,"truncated DEFLATE code length repeat")+3; local previous=all[#all]; for _=1,repeatCount do all[#all+1]=previous end
                    elseif symbol==17 then for _=1,deflateBits(reader,3,"truncated DEFLATE code length repeat")+3 do all[#all+1]=0 end
                    elseif symbol==18 then for _=1,deflateBits(reader,7,"truncated DEFLATE code length repeat")+11 do all[#all+1]=0 end
                    else error("invalid DEFLATE code length symbol") end
                    if #all>need then error("DEFLATE code length overflow") end
                end
                local ll={}; for i=1,hlit do ll[i]=all[i] end; local dd={}; for i=1,hdist do dd[i]=all[hlit+i] end
                litTree,distTree=huffmanBuild(ll),huffmanBuild(dd)
            else error("reserved DEFLATE block") end
            while true do
                local symbol,decodeError=huffmanDecode(reader,litTree); if type(symbol)~="number" then error("invalid DEFLATE literal: "..tostring(decodeError)) end
                if symbol<256 then put(symbol)
                elseif symbol==256 then break
                elseif symbol<=285 then
                    local index=symbol-256; local base,extra=lengthBase[index],lengthExtra[index]
                    if type(base)~="number" or type(extra)~="number" then error("invalid DEFLATE length") end
                    local length=base+deflateBits(reader,extra,"truncated DEFLATE length")
                    local ds,distanceError=huffmanDecode(reader,distTree); if type(ds)~="number" or ds<0 or ds>29 then error("invalid DEFLATE distance: "..tostring(distanceError)) end
                    local distanceBaseValue,distanceBits=distanceBase[ds+1],distanceExtra[ds+1]
                    if type(distanceBaseValue)~="number" or type(distanceBits)~="number" then error("invalid DEFLATE distance") end
                    local distance=distanceBaseValue+deflateBits(reader,distanceBits,"truncated DEFLATE distance"); if distance>size then error("DEFLATE distance outside output") end
                    for _=1,length do local from=size-distance+1; local byte=output[from]; if type(byte)~="string" then error("invalid DEFLATE back-reference") end; put(byte:byte()) end
                else error("invalid DEFLATE length") end
            end
        end
    end
    return table.concat(output)
end
local function be16(s,p) local a,b=s:byte(p,p+1); if not a or not b then error("truncated image") end; return a*256+b end
local function be32(s,p) local a,b,c,d=s:byte(p,p+3); if not d then error("truncated image") end; return ((a*256+b)*256+c)*256+d end
local function paeth(a,b,c) local p=a+b-c; local pa=math.abs(p-a); local pb=math.abs(p-b); local pc=math.abs(p-c); return pa<=pb and pa<=pc and a or (pb<=pc and b or c) end
function pngDecode(body,yieldFn)
    if type(body)~="string" then error("invalid PNG data") end
    if body:sub(1,8)~=string.char(137,80,78,71,13,10,26,10) then error("not a PNG") end
    local pos=9; local width,height,depth,colorType; local palette,transparency={},{ }; local idat={}; local interlace
    local hasIHDR,hasIDAT,hasIEND=false,false,false
    while pos<=#body do
        local length=be32(body,pos); pos=pos+4; if length<0 or pos+length+7>#body then error("invalid PNG chunk length") end
        local kind=body:sub(pos,pos+3); pos=pos+4; local chunk=body:sub(pos,pos+length-1); pos=pos+length+4
        if kind=="IHDR" then
            if hasIHDR or #chunk~=13 then error("invalid PNG IHDR") end
            width,height=be32(chunk,1),be32(chunk,5); depth=chunk:byte(9); colorType=chunk:byte(10); interlace=chunk:byte(13); hasIHDR=true
        elseif kind=="PLTE" then
            if not hasIHDR or #chunk==0 or #chunk%3~=0 then error("invalid PNG palette") end
            for i=1,#chunk,3 do palette[#palette+1]={chunk:byte(i),chunk:byte(i+1),chunk:byte(i+2)} end
        elseif kind=="tRNS" then for i=1,#chunk do transparency[i]=chunk:byte(i) end
        elseif kind=="IDAT" then
            if not hasIHDR then error("PNG IDAT before IHDR") end
            hasIDAT=true; idat[#idat+1]=chunk
        elseif kind=="IEND" then hasIEND=true; break end
    end
    if not hasIHDR then error("PNG has no IHDR") end
    if not hasIDAT then error("PNG has no IDAT data") end
    if not hasIEND then error("PNG is missing IEND") end
    if not width or not height or width<1 or height<1 or width>1024 or height>768 or width*height>262144 then error("PNG dimensions are unsafe") end
    if type(depth)~="number" or type(colorType)~="number" or type(interlace)~="number" then error("truncated PNG IHDR") end
    if interlace~=0 then error("interlaced PNG is not supported") end
    local channels=({[0]=1,[2]=3,[3]=1,[4]=2,[6]=4})[colorType]; if not channels then error("unsupported PNG color type") end
    if depth~=1 and depth~=2 and depth~=4 and depth~=8 and depth~=16 then error("unsupported PNG bit depth") end
    if colorType==3 and #palette==0 then error("indexed PNG has no palette") end
    local rowBytes=math.ceil(width*channels*depth/8); local bpp=max(1,math.ceil(channels*depth/8)); local compressed=table.concat(idat); local cmf,flg=compressed:byte(1,2)
    if #compressed<6 or not cmf or not flg or cmf%16~=8 or (cmf*256+flg)%31~=0 then error("invalid PNG zlib stream") end
    local raw=inflateRaw(compressed:sub(3,#compressed-4),max(1024*1024,width*(rowBytes+1)*height+64),yieldFn)
    if #raw<height*(rowBytes+1) then error("PNG scanlines are truncated") end
    local previous={}; local pixels={}; local rp=1
    local function sample(row,bit)
        local byte=row[floor(bit/8)+1] or 0; local shift=8-depth-(bit%8); return floor(byte/2^shift)%2^depth
    end
    for y=1,height do
        local filter=raw:byte(rp); rp=rp+1; local row={}; for x=1,rowBytes do local value=raw:byte(rp) or 0; rp=rp+1; local left=row[x-bpp] or 0; local up=previous[x] or 0; local upper=previous[x-bpp] or 0
            if filter==1 then value=(value+left)%256 elseif filter==2 then value=(value+up)%256 elseif filter==3 then value=(value+floor((left+up)/2))%256 elseif filter==4 then value=(value+paeth(left,up,upper))%256 elseif filter~=0 then error("unsupported PNG filter") end; row[x]=value end
        for x=1,width do
            local r,g,b,a
            if colorType==0 then local v=depth==8 and row[x] or (depth==16 and row[(x-1)*2+1] or sample(row,(x-1)*depth)); v=depth<8 and floor(v*255/(2^depth-1)) or v; r,g,b=v,v,v; a=255
            elseif colorType==2 then local base=(x-1)*(depth==16 and 6 or 3)+1; r,g,b=row[base],row[base+(depth==16 and 2 or 1)],row[base+(depth==16 and 4 or 2)]; a=255
            elseif colorType==3 then local index=depth==8 and row[x] or sample(row,(x-1)*depth); local p=palette[index+1]; if not p then error("PNG palette index outside palette") end; r,g,b=p[1],p[2],p[3]; a=transparency[index+1] or 255
            elseif colorType==4 then local base=(x-1)*(depth==16 and 4 or 2)+1; r= row[base]; a=row[base+(depth==16 and 2 or 1)]; g,b=r,r
            elseif colorType==6 then local base=(x-1)*(depth==16 and 8 or 4)+1; r,g,b,a=row[base],row[base+(depth==16 and 2 or 1)],row[base+(depth==16 and 4 or 2)],row[base+(depth==16 and 6 or 3)] end
            pixels[(y-1)*width+x]=(a or 255)*16777216+(r or 0)*65536+(g or 0)*256+(b or 0)
        end
        previous=row; if yieldFn then yieldFn(y/height) end
    end
    return imageNormalize({width=width,height=height,pixels=pixels})
end
local jpegZigzag={0,1,5,6,14,15,27,28,2,4,7,13,16,26,29,42,3,8,12,17,25,30,41,43,9,11,18,24,31,40,44,53,10,19,23,32,39,45,52,54,20,22,33,38,46,51,55,60,21,34,37,47,50,56,59,61,35,36,48,49,57,58,62,63}
local function jpegHuffmanBuild(lengths,symbols)
    local count={}; for i=1,16 do count[i]=lengths[i] or 0 end; local code=0; local nextCode={}
    for bits=1,16 do code=(code+(count[bits-1] or 0))*2; nextCode[bits]=code end
    local tree={}; local at=1
    for bits=1,16 do for _=1,count[bits] do tree[bits]=tree[bits] or {}; tree[bits][nextCode[bits]]=symbols[at]; nextCode[bits]=nextCode[bits]+1; at=at+1 end end
    return tree
end
local function jpegReader(data,pos)
    local r={data=data,pos=pos,bits=0,buffer=0}
    function r:byte()
        local b=self.data:byte(self.pos); self.pos=self.pos+1; if not b then error("truncated JPEG entropy data") end
        if b==255 then local n=self.data:byte(self.pos); self.pos=self.pos+1; if n==0 then return 255 end; error("JPEG restart/marker inside entropy data") end
        return b
    end
    function r:bitsRead(count)
        local value=0; for _=1,count do if self.bits==0 then self.buffer=self:byte(); self.bits=8 end; value=value*2+floor(self.buffer/128); self.buffer=(self.buffer*2)%256; self.bits=self.bits-1 end; return value
    end
    return r
end
local function jpegHuffmanDecode(reader,tree)
    local code=0; for len=1,16 do code=code*2+reader:bitsRead(1); if tree[len] and tree[len][code]~=nil then return tree[len][code] end end; error("invalid JPEG Huffman code")
end
local function jpegReceive(reader,size)
    if size==0 then return 0 end; local value=reader:bitsRead(size); if value<2^(size-1) then return value-(2^size-1) end; return value
end
local JPEG={cos={}}
for u=0,7 do
    JPEG.cos[u]={}
    for x=0,7 do JPEG.cos[u][x]=math.cos((2*x+1)*u*math.pi/16) end
end
function JPEG.segmentEnd(state,length)
    local e=state.pos+length-1
    if length<2 or e>#state.body then error("truncated JPEG segment") end
    return e
end
function JPEG.idct(coeff)
    local out={}
    for y=0,7 do
        for x=0,7 do
            local sum=0
            for v=0,7 do
                for u=0,7 do
                    local cu=u==0 and 0.7071067811865476 or 1
                    local cv=v==0 and 0.7071067811865476 or 1
                    sum=sum+cu*cv*coeff[v*8+u+1]*JPEG.cos[u][x]*JPEG.cos[v][y]
                end
            end
            out[y*8+x+1]=clamp(floor(sum/4+128.5),0,255)
        end
    end
    return out
end
function JPEG.decodeBlock(state,reader,comp,pred)
    local coeff={}
    for i=1,64 do coeff[i]=0 end
    local dc=jpegHuffmanDecode(reader,state.huff.dc[comp.dc])
    pred[comp.id]=(pred[comp.id] or 0)+jpegReceive(reader,dc)
    coeff[1]=pred[comp.id]
    local k=1
    while k<64 do
        local rs=jpegHuffmanDecode(reader,state.huff.ac[comp.ac])
        if rs==0 then break end
        local run=floor(rs/16)
        local size=rs%16
        if size==0 and run~=15 then error("invalid JPEG AC symbol") end
        if size==0 then
            k=k+16
        else
            k=k+run
            if k>63 then error("JPEG coefficient overflow") end
            coeff[jpegZigzag[k+1]+1]=jpegReceive(reader,size)
            k=k+1
        end
    end
    local q=state.quant[comp.qt]
    if not q then error("missing JPEG quantization table") end
    for i=1,64 do coeff[i]=coeff[i]*(q[i] or 1) end
    return JPEG.idct(coeff)
end
function JPEG.parseDHT(state)
    local e=JPEG.segmentEnd(state,be16(state.body,state.pos))
    state.pos=state.pos+2
    while state.pos<=e do
        local info=state.body:byte(state.pos); state.pos=state.pos+1
        local cls=floor(info/16)
        local id=info%16
        local lengths={}
        for i=1,16 do lengths[i]=state.body:byte(state.pos); state.pos=state.pos+1 end
        local total=0
        for i=1,16 do total=total+lengths[i] end
        local symbols={}
        for i=1,total do symbols[i]=state.body:byte(state.pos); state.pos=state.pos+1 end
        if cls>1 then error("invalid JPEG Huffman class") end
        state.huff[cls==0 and "dc" or "ac"][id]=jpegHuffmanBuild(lengths,symbols)
    end
    state.pos=e+1
end
function JPEG.parseDQT(state)
    local e=JPEG.segmentEnd(state,be16(state.body,state.pos))
    state.pos=state.pos+2
    while state.pos<=e do
        local info=state.body:byte(state.pos); state.pos=state.pos+1
        local precision=floor(info/16)
        local id=info%16
        if precision>1 then error("16-bit JPEG quantization unsupported") end
        local q={}
        for i=1,64 do q[jpegZigzag[i]+1]=state.body:byte(state.pos); state.pos=state.pos+1 end
        state.quant[id]=q
    end
    state.pos=e+1
end
function JPEG.parseSOF0(state)
    local e=JPEG.segmentEnd(state,be16(state.body,state.pos))
    state.pos=state.pos+2
    local precision=state.body:byte(state.pos); state.pos=state.pos+1
    if precision~=8 then error("only 8-bit baseline JPEG is supported") end
    state.height=be16(state.body,state.pos)
    state.width=be16(state.body,state.pos+2)
    state.pos=state.pos+4
    local n=state.body:byte(state.pos); state.pos=state.pos+1
    if n<1 or n>3 then error("unsupported JPEG component count") end
    state.maxH,state.maxV=1,1
    for _=1,n do
        local id=state.body:byte(state.pos)
        local sampling=state.body:byte(state.pos+1)
        local qt=state.body:byte(state.pos+2)
        state.pos=state.pos+3
        local comp={id=id,hs=floor(sampling/16),vs=sampling%16,qt=qt}
        if comp.hs<1 or comp.vs<1 or comp.hs>4 or comp.vs>4 then error("unsupported JPEG sampling") end
        state.comps[id]=comp
        state.maxH=max(state.maxH,comp.hs)
        state.maxV=max(state.maxV,comp.vs)
    end
    state.pos=e+1
end
function JPEG.parseSOS(state)
    local e=JPEG.segmentEnd(state,be16(state.body,state.pos))
    state.pos=state.pos+2
    local n=state.body:byte(state.pos); state.pos=state.pos+1
    state.scan={}
    for _=1,n do
        local id=state.body:byte(state.pos)
        local tables=state.body:byte(state.pos+1)
        state.pos=state.pos+2
        local comp=state.comps[id]
        if not comp then error("JPEG scan references unknown component") end
        comp.dc=floor(tables/16)
        comp.ac=tables%16
        state.scan[#state.scan+1]=comp
    end
    local spectralStart=state.body:byte(state.pos)
    local spectralEnd=state.body:byte(state.pos+1)
    local approx=state.body:byte(state.pos+2)
    if spectralStart~=0 or spectralEnd~=63 or approx~=0 then error("non-baseline JPEG scan") end
    state.pos=e+1
end
function JPEG.sample(state,blocks,comp,px,py)
    local cx=floor(px*comp.hs/state.maxH)
    local cy=floor(py*comp.vs/state.maxV)
    local bi=floor(cx/8)+floor(cy/8)*comp.hs+1
    local block=blocks[comp.id][bi]
    return block[(cy%8)*8+(cx%8)+1] or 0
end
function JPEG.decodePixel(state,blocks,px,py)
    local yv=JPEG.sample(state,blocks,state.scan[1],px,py)
    if #state.scan==1 then return yv,yv,yv end
    if #state.scan~=3 then error("unsupported JPEG scan component count") end
    local cb=JPEG.sample(state,blocks,state.scan[2],px,py)-128
    local cr=JPEG.sample(state,blocks,state.scan[3],px,py)-128
    local r=clamp(floor(yv+1.402*cr+0.5),0,255)
    local g=clamp(floor(yv-0.344136*cb-0.714136*cr+0.5),0,255)
    local b=clamp(floor(yv+1.772*cb+0.5),0,255)
    return r,g,b
end
function JPEG.decodeMCU(state,reader,preds,mx,my,pixels)
    local blocks={}
    for _,comp in ipairs(state.scan) do
        blocks[comp.id]={}
        for by=0,comp.vs-1 do
            for bx=0,comp.hs-1 do
                blocks[comp.id][by*comp.hs+bx+1]=JPEG.decodeBlock(state,reader,comp,preds)
            end
        end
    end
    local mcuW,mcuH=state.maxH*8,state.maxV*8
    for py=0,mcuH-1 do
        local iy=my*mcuH+py+1
        if iy<=state.height then
            for px=0,mcuW-1 do
                local ix=mx*mcuW+px+1
                if ix<=state.width then
                    local r,g,b=JPEG.decodePixel(state,blocks,px,py)
                    pixels[(iy-1)*state.width+ix]=0xFF000000+r*65536+g*256+b
                end
            end
        end
    end
end
function JPEG.decodeScan(state,yieldFn)
    if not state.width or not state.height or state.width<1 or state.height<1 or state.width>1024 or state.height>768 or state.width*state.height>262144 then error("JPEG dimensions are unsafe") end
    local reader=jpegReader(state.body,state.pos)
    local preds={}
    local pixels={}
    local mcuW,mcuH=state.maxH*8,state.maxV*8
    local mcusX=math.ceil(state.width/mcuW)
    local mcusY=math.ceil(state.height/mcuH)
    for my=0,mcusY-1 do
        for mx=0,mcusX-1 do
            JPEG.decodeMCU(state,reader,preds,mx,my,pixels)
            if yieldFn then yieldFn((my*mcusX+mx+1)/(mcusX*mcusY)) end
        end
    end
    return imageNormalize({width=state.width,height=state.height,pixels=pixels})
end
function jpegDecode(body,yieldFn)
    if body:byte(1)~=255 or body:byte(2)~=216 then error("not a JPEG") end
    local state={body=body,pos=3,quant={},huff={dc={},ac={}},comps={}}
    while state.pos<=#body do
        while body:byte(state.pos)==255 do state.pos=state.pos+1 end
        local marker=body:byte(state.pos)
        state.pos=state.pos+1
        if not marker then error("truncated JPEG marker") end
        if marker==217 then
            break
        elseif marker==216 or marker==1 or (marker>=208 and marker<=215) then
        elseif marker==196 then
            JPEG.parseDHT(state)
        elseif marker==219 then
            JPEG.parseDQT(state)
        elseif marker==192 then
            JPEG.parseSOF0(state)
        elseif marker==194 then
            error("progressive JPEG is not supported")
        elseif marker==218 then
            JPEG.parseSOS(state)
            return JPEG.decodeScan(state,yieldFn)
        elseif marker>=192 and marker<=254 then
            local length=be16(body,state.pos)
            if length<2 or state.pos+length-1>#body then error("truncated JPEG marker") end
            state.pos=state.pos+length
        end
    end
    error("JPEG has no baseline image scan")
end
local function imageResize(data,targetW,targetH,yieldFn)
    local scale=min(1,targetW/data.width,targetH/data.height); local w=max(1,floor(data.width*scale+0.5)); local h=max(1,floor(data.height*scale+0.5)); local pixels={}
    for y=1,h do
        local sy=clamp(floor((y-0.5)/scale+0.5),1,data.height)
        for x=1,w do local sx=clamp(floor((x-0.5)/scale+0.5),1,data.width); pixels[(y-1)*w+x]=imagePixel(data,sx,sy) end
        if yieldFn then yieldFn(y/h) end
    end
    return imageNormalize({version=1,width=w,height=h,pixels=pixels})
end
local function imageQuantize(data,maxColors,yieldFn)
    maxColors=clamp(floor(maxColors or 16),1,16); local buckets={}
    for i,color in ipairs(data.pixels) do
        local r=floor(color/65536)%256; local g=floor(color/256)%256; local b=color%256; local key=floor(r/8)*1024+floor(g/8)*32+floor(b/8); local q=buckets[key]
        if not q then q={count=0,r=0,g=0,b=0}; buckets[key]=q end; q.count=q.count+1; q.r=q.r+r; q.g=q.g+g; q.b=q.b+b
        if yieldFn and i%4096==0 then yieldFn(i/#data.pixels) end
    end
    local bins={}; for _,q in pairs(buckets) do bins[#bins+1]=q end; table.sort(bins,function(a,b) return a.count>b.count end)
    local palette={}; for i=1,min(maxColors,#bins) do local q=bins[i]; palette[i]=0xFF000000+floor(q.r/q.count+0.5)*65536+floor(q.g/q.count+0.5)*256+floor(q.b/q.count+0.5) end
    if #palette==0 then palette[1]=0xFF000000 end
    local rle={}; local last=nil; local count=0
    for i,color in ipairs(data.pixels) do
        local r=floor(color/65536)%256; local g=floor(color/256)%256; local b=color%256; local best,bestDistance=1,math.huge
        for p,pcolor in ipairs(palette) do local pr=floor(pcolor/65536)%256; local pg=floor(pcolor/256)%256; local pb=pcolor%256; local distance=(r-pr)^2+(g-pg)^2+(b-pb)^2; if distance<bestDistance then best,bestDistance=p,distance end end
        if best==last then count=count+1 else if last then rle[#rle+1]={index=last-1,count=count} end; last=best; count=1 end
        if yieldFn and i%2048==0 then yieldFn(i/#data.pixels) end
    end
    if last then rle[#rle+1]={index=last-1,count=count} end
    local stored={version=2,width=data.width,height=data.height,palette=palette,rle=rle}; local normalized=imageNormalize(stored); return normalized,stored
end
imageToStored=function(data)
    if data and data.version==2 and type(data.palette)=="table" and type(data.rle)=="table" then return {version=2,width=data.width,height=data.height,palette=data.palette,rle=data.rle} end
    local _,stored=imageQuantize(data or {width=1,height=1,pixels={0xFF000000}},16); return stored
end
local imageCacheDir="/.hccos/cache/images"
local nativePngTempDir="/.hccos/temp/images"
local function imageHash(value)
    local hash=2166136261; for i=1,#value do hash=(hash*16777619+value:byte(i))%4294967296 end; return string.format("%08x",hash)
end
function imageCachePath(key) return fs.combine(imageCacheDir,imageHash(key)..".hcci") end
function imageCacheLoad(key)
    if not cfg.imageCacheEnabled then return nil end
    local path=imageCachePath(key); if not fs.exists(path) then return nil end
    local data=imageRead(path); if data then return data end
    pcall(fs.delete,path); return nil
end
local function imageCacheTrim()
    if not fs.exists(imageCacheDir) then return end
    local entries={}; local total=0
    for _,name in ipairs(fs.list(imageCacheDir)) do local path=fs.combine(imageCacheDir,name); if not fs.isDir(path) then local size=fs.getSize(path); entries[#entries+1]={path=path,size=size}; total=total+size end end
    table.sort(entries,function(a,b) return a.path<b.path end)
    while total>cfg.imageCacheLimit and #entries>0 do local item=table.remove(entries,1); pcall(fs.delete,item.path); total=total-item.size end
end
function imageCacheSave(key,data)
    if not cfg.imageCacheEnabled then return nil,"image cache disabled" end
    local ok,err=pcall(function()
        if not fs.exists("/.hccos/cache") then fs.makeDir("/.hccos/cache") end
        if not fs.exists(imageCacheDir) then fs.makeDir(imageCacheDir) end
        local f,e=fs.open(imageCachePath(key),"w"); if not f then error(e or "cache is not writable") end; local good,reason=pcall(f.write,textutils.serialize(imageToStored(data))); f.close(); if not good then error(reason) end; imageCacheTrim()
    end)
    return ok,err
end
function imageCacheClear()
    if not fs.exists(imageCacheDir) then return true end
    local ok,err=pcall(function() for _,name in ipairs(fs.list(imageCacheDir)) do local path=fs.combine(imageCacheDir,name); if not fs.isDir(path) then fs.delete(path) end end end); return ok,err
end
local function imageDecodeNativePng(body)
    if type(Driver)~="table" or type(Driver.decodePng)~="function" then return nil,"Tom's GPU native PNG backend unavailable" end
    return Driver.decodePng(body)
end
local function imageLoadNativePng(path,limit)
    if type(path)~="string" or path=="" or not fs.exists(path) or fs.isDir(path) then return nil,"invalid PNG path" end
    local ok,body=pcall(readFile,path,limit or cfg.maxImageDownload)
    if not ok then return nil,tostring(body) end
    return imageDecodeNativePng(body)
end
local function imageStageNativePng(body,key)
    if type(body)~="string" or #body==0 then return nil,"empty PNG data" end
    local ok,pathOrError=pcall(function()
        if not fs.exists(nativePngTempDir) then fs.makeDir(nativePngTempDir) end
        local path=fs.combine(nativePngTempDir,imageHash(tostring(key or "png"))..".png")
        local f,err=fs.open(path,"w"); if not f then error(err or "temporary PNG is not writable") end
        local wrote,writeError=pcall(f.write,body); f.close(); if not wrote then error(writeError) end
        return path
    end)
    if not ok then return nil,tostring(pathOrError) end
    return pathOrError
end
local function imageFreeNativePng(record)
    if type(Driver)=="table" and type(Driver.freeNativeImage)=="function" then Driver.freeNativeImage(record) end
end
local function imageDeleteNativePng(path)
    if type(path)~="string" or path:sub(1,#nativePngTempDir+1)~=nativePngTempDir.."/" then return false,"unsafe temporary PNG path" end
    if fs.exists(path) then return pcall(fs.delete,path) end
    return true
end
local function imagePersistNativePng(path,key)
    if type(path)~="string" or path=="" or not fs.exists(path) or fs.isDir(path) then return nil,"invalid PNG source path" end
    local ok,result=pcall(function()
        if not fs.exists(imageDir) then fs.makeDir(imageDir) end
        local destination=fs.combine(imageDir,"wallpaper_"..imageHash(tostring(key or path))..".png")
        if path~=destination then
            if fs.exists(destination) then fs.delete(destination) end
            fs.copy(path,destination)
        end
        return destination
    end)
    if not ok then return nil,tostring(result) end
    return result
end
nativeWallpaperLoad=function(path,mode,targetW,targetH)
    local ok,body=pcall(readFile,path,cfg.maxImageDownload)
    if not ok then return nil,tostring(body) end
    local native,nativeError=imageDecodeNativePng(body)
    if native and mode=="center" and native.width<=targetW and native.height<=targetH then return native end
    if native then imageFreeNativePng(native) end
    local decoded,decodeError=pcall(pngDecode,body)
    if not decoded then return nil,tostring(nativeError or decodeError) end
    local data=imagePrepare(decodeError,targetW,targetH)
    if not data then return nil,"PNG wallpaper conversion failed" end
    return data
end
function imagePrepare(data,targetW,targetH,progress)
    targetW=max(1,min(576,floor(targetW or 576))); targetH=max(1,min(320,floor(targetH or 320))); local candidates={{1,"16"},{0.8333,"12"},{0.6667,"8"},{0.5,"8"}}; local lastData,lastStored,lastSize
    for _,candidate in ipairs(candidates) do
        local scale,colors=candidate[1],tonumber(candidate[2]); local resized=imageResize(data,max(1,floor(targetW*scale)),max(1,floor(targetH*scale)),function(p) if progress then progress("Resizing...",p) end end)
        local quantized,stored=imageQuantize(resized,colors,function(p) if progress then progress("Quantizing "..colors.." colors...",p) end end); local size=#textutils.serialize(stored); lastData,lastStored,lastSize=quantized,stored,size
        if progress then progress("Compressing...",1) end
        if size<=512000 then return quantized,stored,size end
    end
    return lastData,lastStored,lastSize
end
end
E.imageRead=imageRead; E.imageWrite=imageWrite; E.imageList=imageList; E.imagePixel=imagePixel; E.imageNormalize=imageNormalize; E.drawImage=drawImage; E.wallpaperCommands=wallpaperCommands; E.pngDecode=pngDecode; E.jpegDecode=jpegDecode; E.imagePrepare=imagePrepare; E.imageCacheSave=imageCacheSave; E.imageCacheLoad=imageCacheLoad; E.imageCacheClear=imageCacheClear; E.imageCachePath=imageCachePath; E.imageDecodeNativePng=imageDecodeNativePng; E.imageLoadNativePng=imageLoadNativePng; E.imageStageNativePng=imageStageNativePng; E.imageFreeNativePng=imageFreeNativePng; E.imageDeleteNativePng=imageDeleteNativePng; E.imagePersistNativePng=imagePersistNativePng
E.resetWallpaperCache=clearWallpaperCache

end

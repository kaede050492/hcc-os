-- Run with Lua 5.2+ from the repository root:
--   lua tests/image_codec_spec.lua

local environment=setmetatable({},{__index=_G})
local chunk,loadError=loadfile("system/core/image_codec.lua","t",environment)
assert(chunk,loadError)
local factory=chunk()
local E=setmetatable({
    paths={images="/.hccos/images",logs="/.hccos/logs",cache="/.hccos/cache",temp="/.hccos/temp"},
    cfg={maxImageDownload=4194304,imageCacheEnabled=true,imageCacheLimit=4194304,
        wallpaperPath="",wallpaperMode="black",wallpaperEnabled=true,wallpaperBackground="#080B12"},
    Driver={w=576,h=320},TASK=32,
    fs={combine=function(a,b) return a:gsub("/$","").."/"..b end},
    finite=function(value) return type(value)=="number" and value==value and math.abs(value)<1e12 end,
    floor=math.floor,min=math.min,max=math.max,
    clamp=function(value,minimum,maximum) return math.max(minimum,math.min(maximum,value)) end,
    textutils={serialize=function() return "serialized image" end},
    logLine=function() end
},{__index=_G})
factory(E)
for _,name in ipairs({"pngDecode","jpegDecode","imageDecodeQoi","imageLoadQoi","qoiSignature",
    "imageResize","imageDecodeNativePng","imageLoadNativePng","imageStageNativePng",
    "imageFreeNativePng","imageDeleteNativePng","imagePersistNativePng"}) do
    assert(type(E[name])=="function","image service API was not exported: "..name)
end

local normalized,normalizeError=E.imageNormalize({width=2,height=2,pixels={
    "#112233","#445566","#778899","#AABBCC"}})
assert(normalized and normalized.width==2 and normalized.height==2 and
    normalized.pixels[1]==0xFF112233,"valid HCCI pixels should normalize to bounded ARGB values")
assert(E.imagePixel(normalized,3,1)==0xFF000000,"out-of-range image reads should return opaque black")

local oversized=E.imageNormalize({width=513,height=513,pixels={}})
assert(oversized==nil,"dimensions above the normalized pixel budget should be rejected before expansion")
local rle=assert(E.imageNormalize({width=3,height=2,rle={{color="#123456",count=999999999}}}))
assert(#rle.pixels==6 and rle.pixels[6]==0xFF123456,
    "oversized RLE counts should be capped at the declared pixel count")

local pngSignature=string.char(137,80,78,71,13,10,26,10)
local function be32(value)
    return string.char(math.floor(value/16777216)%256,math.floor(value/65536)%256,
        math.floor(value/256)%256,value%256)
end
local function pngChunk(name,data)
    return be32(#data)..name..data.."\0\0\0\0"
end
local hugePng=pngSignature..pngChunk("IHDR",be32(8192)..be32(8192)..string.char(8,2,0,0,0))..
    pngChunk("IDAT","")..pngChunk("IEND","")
local pngOk,pngError=pcall(E.pngDecode,hugePng)
assert(not pngOk and tostring(pngError):find("dimensions are unsafe",1,true),
    "oversized PNG dimensions should be rejected before pixel allocation")
local wrongPngOk=pcall(E.pngDecode,"not a PNG")
assert(not wrongPngOk,"invalid PNG signatures should fail with a controlled decoder error")

local function qoiHeader(width,height)
    return "qoif"..be32(width)..be32(height)..string.char(3,0)
end
local qoiData,qoiError=E.imageDecodeQoi(qoiHeader(1025,1))
assert(qoiData==nil and tostring(qoiError):find("dimensions are unsafe",1,true),
    "QOI dimensions should be checked before loading the decoder")
local previousBit32=rawget(_G,"bit32")
_G.bit32={
    extract=function(value,field,width) return math.floor(value/2^field)%2^width end,
    rshift=function(value,bits) return math.floor(value/2^bits) end,
    lshift=function(value,bits) return (value*2^bits)%4294967296 end
}
local qoiChunk,qoiLoadError=loadfile("system/lib/hcc/qoi_d.lua")
assert(qoiChunk,qoiLoadError)
local qoiDecoder=qoiChunk()
_G.bit32=previousBit32
E.modules={load=function(_,name) assert(name=="hcc.qoi_d"); return qoiDecoder end}
local qoiEnd="\0\0\0\0\0\0\0\1"
local decodedQoi,qoiDecodeError=E.imageDecodeQoi(qoiHeader(1,1)..string.char(254,0x11,0x22,0x33)..qoiEnd)
local expectedQoiColor=tonumber("FF112233",16)%4294967296
assert(decodedQoi and decodedQoi.width==1 and decodedQoi.pixels[1]==expectedQoiColor,
    "a valid QOI image should pass through the exported decoder: "..tostring(qoiDecodeError))
local previousFs=rawget(_G,"fs")
local validQoi=qoiHeader(1,1)..string.char(254,0x11,0x22,0x33)..qoiEnd
E.fs.exists=function(path) return path=="/sample.qoi" end
E.fs.isDir=function() return false end
E.fs.getSize=function() return #validQoi end
E.fs.open=function(path,mode)
    assert(path=="/sample.qoi" and mode=="rb")
    return {readAll=function() return validQoi end,close=function() end}
end
_G.fs=E.fs
local loadedQoi,loadQoiError=E.imageLoadQoi("/sample.qoi",100,100)
_G.fs=previousFs
assert(loadedQoi and loadedQoi.pixels[1]==expectedQoiColor,
    "QOI file loading should use the safe exported decoder: "..tostring(loadQoiError))
local brokenQoi,brokenQoiError=E.imageDecodeQoi(qoiHeader(1,1)..qoiEnd)
assert(brokenQoi==nil and type(brokenQoiError)=="string",
    "QOI decoder failures should return a contained error")
local jpegOk=pcall(E.jpegDecode,"not a JPEG")
assert(not jpegOk,"invalid JPEG signatures should be rejected")

local pixels={}
for index=1,250000 do pixels[index]=0xFF000000+(index%16777216) end
local commands={{kind="prior"}}
local canvas={list=commands}
function canvas:filledRectangle(x,y,w,h,color)
    self.list[#self.list+1]={x=x,y=y,w=w,h=h,color=color}
end
E.drawImage(canvas,{width=500,height=500,pixels=pixels},0,0,500,500,"stretch",1,0,0,nil,1)
assert(commands[1].kind=="prior" and #commands<=12001,
    "complex image rendering should preserve prior commands and cap emitted fills")

print("image codec specs passed (normalization, malformed headers, bounded draw output)")

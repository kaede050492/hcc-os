-- HCC OS v1.5 shared GUI runtime.
local Runtime={}
local defaults={networkRefresh=3,resourceRefresh=2,maxImageDownload=4194304,
  imageCacheLimit=4194304,imageCacheEnabled=true,
  imageDownloadConcurrency=3,httpImageCacheLimit=8388608,httpImageCacheEnabled=true,
  cursorIdle=6,uiScale=1,wallpaperEnabled=true,wallpaperMode="black",
  wallpaperPath="",wallpaperBackground="#080B12",wallpaperLastGood="",
  wallpaperLastFailed="",wallpaperError="",fpsMax=60,fpsMin=10,adaptiveFps=true,
  debugInputTrace=false}
local palettes={
 -- Keep the existing theme name for settings compatibility while using an
 -- original Fluent-inspired dark surface palette and cyan accent.
 black={desktopBackground=0xFF080D14,windowBackground=0xFF171E27,panelBackground=0xFF222B36,
 textPrimary=0xFFF2F6FA,textSecondary=0xFFB6C2CE,border=0xFF3A4858,accent=0xFF46CFF0,
 success=0xFF64D99A,warning=0xFFFFC86A,error=0xFFFF727E,grid=0xFF182533,
 taskbarBackground=0xFF121922,titlebarActive=0xFF243543,titlebarInactive=0xFF1A222C,
 menuBackground=0xFF161E28,menuHeader=0xFF202A35,menuSelection=0xFF293948,
 desktopSelection=0xFF163746,desktopHover=0xFF152A35,wallpaperMark=0xFF101923,
 inputBackground=0xFF101720},
 midnight={desktopBackground=0xFF070912,windowBackground=0xFF111727,panelBackground=0xFF1C263A,
 textPrimary=0xFFF0F2FA,textSecondary=0xFFB5C0D7,border=0xFF3E4E70,accent=0xFFABA0FF,
 success=0xFF60DA90,warning=0xFFFFC65B,error=0xFFFF6978,grid=0xFF202D48,
 taskbarBackground=0xFF101522,titlebarActive=0xFF242B49,titlebarInactive=0xFF171D2C,
 menuBackground=0xFF121827,menuHeader=0xFF1C263A,menuSelection=0xFF293754,
 desktopSelection=0xFF242E55,desktopHover=0xFF1B2542,wallpaperMark=0xFF0C1424,
 inputBackground=0xFF151D2D}}
local accents={cyan=0xFF46CFF0,blue=0xFF70C8FF,purple=0xFFB9A7FF,green=0xFF60DA90,gold=0xFFFFC65B,red=0xFFFF6978}
local micaSurfaces={"windowBackground","panelBackground","border","taskbarBackground","titlebarActive",
 "titlebarInactive","menuBackground","menuHeader","menuSelection","desktopSelection","desktopHover",
 "wallpaperMark","inputBackground"}
function Runtime.new(context)
 local E=setmetatable({context=context},{__index=_ENV})
 E.unpack=table.unpack or unpack
 E.floor,E.min,E.max=math.floor,math.min,math.max
 E.HCC_VERSION="1.5.1"; E.HCC_VERSION_LABEL="HCC OS v1.5.1"
 E.HCC_CPU="Himantel Core 5 140"; E.HCC_TARGET_W,E.HCC_TARGET_H=576,320
 E.HCC_BLOCKS_X,E.HCC_BLOCKS_Y,E.HCC_PIXELS_PER_BLOCK=9,5,64
 E.HCC_MAX_WINDOWS,E.HCC_MAX_LOGS,E.HCC_MAX_HISTORY=24,400,180
 E.WINDOW_CORNER_RADIUS=8
 E.TASKBAR_CORNER_RADIUS=10
 E.START_MENU_CORNER_RADIUS=12
 local geometry
 local Color
 if type(require)=="function" then
  local ok,value=pcall(require,"hcc.geometry")
  if ok and type(value)=="table" then geometry=value end
  local colorOk,colorValue=pcall(require,"hcc.color")
  if colorOk and type(colorValue)=="table" then Color=colorValue end
 end
 E.finite=function(n) return type(n)=="number" and n==n and math.abs(n)<1e12 end
 E.clamp=function(n,a,b) return math.max(a,math.min(b,n)) end
 E.now=function() return os.epoch("utc")/1000 end
 E.jst=function() return os.date("!*t",math.floor(E.now())+32400) end
 E.timeText=function(d) return string.format("%02d:%02d:%02d",d.hour,d.min,d.sec) end
 E.dateText=function(d) return string.format("%04d-%02d-%02d",d.year,d.month,d.day) end
 E.geometry=geometry
 E.color=Color
 E.box=geometry and geometry.rect or function(x,y,w,h) return {x=math.floor(x),y=math.floor(y),w=math.max(0,math.floor(w)),h=math.max(0,math.floor(h))} end
 E.intersect=geometry and geometry.intersect or function(a,b) local x,y=math.max(a.x,b.x),math.max(a.y,b.y); local r,t=math.min(a.x+a.w,b.x+b.w),math.min(a.y+a.h,b.y+b.h); if r<=x or t<=y then return nil end; return E.box(x,y,r-x,t-y) end
 E.union=geometry and geometry.union or function(a,b) local x,y=math.min(a.x,b.x),math.min(a.y,b.y); return E.box(x,y,math.max(a.x+a.w,b.x+b.w)-x,math.max(a.y+a.h,b.y+b.h)-y) end
 E.inside=geometry and geometry.contains or function(r,x,y) return x>=r.x and y>=r.y and x<r.x+r.w and y<r.y+r.h end
 E.insideRounded=geometry and geometry.roundedContains or E.inside
 E.copy=function(t) local r={} for k,v in pairs(t) do r[k]=v end return r end
 E.ascii=function(s)
  local value=tostring(s or ""):gsub("[^\032-\126]","?")
  return value
 end
 E.readFile=function(path,limit) if fs.isDir(path) then error("This is a directory") end; if fs.getSize(path)>(limit or 65536) then error("File exceeds 64 KiB editor limit") end; local f,err=fs.open(path,"r"); if not f then error(err or "Cannot open file") end; local ok,data=pcall(f.readAll); f.close(); if not ok then error(data) end; return data or "" end
 E.cfg=context.config.data
 for k,v in pairs(defaults) do if E.cfg[k]==nil then E.cfg[k]=v end end
 E.cfg.resolution=math.floor(E.clamp(tonumber(E.cfg.resolution) or 64,16,64))
 E.cfg.clockInterval=E.clamp(tonumber(E.cfg.clockInterval) or 1,0.1,5)
 E.cfg.radarInterval=E.clamp(tonumber(E.cfg.radarInterval) or 0.5,0.25,5)
 E.cfg.serverInterval=E.clamp(tonumber(E.cfg.serverInterval) or 2,1,5)
 E.cfg.snapDistance=math.floor(E.clamp(tonumber(E.cfg.snapDistance) or 10,2,32))
 E.cfg.inventoryRefresh=E.clamp(tonumber(E.cfg.inventoryRefresh) or 2,0.5,10)
 E.cfg.systemInterval=E.clamp(tonumber(E.cfg.systemInterval) or 1,0.25,5)
 E.cfg.performanceHistory=math.floor(E.clamp(tonumber(E.cfg.performanceHistory) or 60,20,180))
 E.cfg.networkRefresh=E.clamp(tonumber(E.cfg.networkRefresh) or 3,1,15)
 E.cfg.resourceRefresh=E.clamp(tonumber(E.cfg.resourceRefresh) or 2,0.5,15)
  E.cfg.maxImageDownload=math.floor(E.clamp(tonumber(E.cfg.maxImageDownload) or 4194304,65536,16777216))
  E.cfg.imageCacheLimit=math.floor(E.clamp(tonumber(E.cfg.imageCacheLimit) or 4194304,262144,16777216))
  E.cfg.imageDownloadConcurrency=math.floor(E.clamp(tonumber(E.cfg.imageDownloadConcurrency) or 3,1,4))
  E.cfg.httpImageCacheLimit=math.floor(E.clamp(tonumber(E.cfg.httpImageCacheLimit) or 8388608,0,33554432))
  E.cfg.httpImageCacheEnabled=E.cfg.httpImageCacheEnabled~=false
 E.cfg.cursorIdle=E.clamp(tonumber(E.cfg.cursorIdle) or 6,1,30)
 E.cfg.uiScale=E.cfg.uiScale==2 and 2 or 1
 E.performance=context.performance
 E.configPath=context.paths.settings
 E.configWarning=context.config.notice or context.config.warning
 E.palettes=palettes
 E.wallpaperTint=nil
 E.applyAccent=function()
  local base=palettes[E.cfg.theme] or palettes.black; E.P=E.copy(base); E.palette=E.P
  local accent=accents[tostring(E.cfg.accent or ""):lower()]; if accent then E.P.accent=accent end
  if Color and E.wallpaperTint then
   for _,key in ipairs(micaSurfaces) do
    if E.P[key] then E.P[key]=Color.blend(E.P[key],E.wallpaperTint,0.36,22) end
   end
  end
  E.palette=E.P
 end
 E.setWallpaperTint=function(color,deferRedraw)
  if color~=nil and (not Color or type(Color.isColor)~="function" or not Color.isColor(color)) then return false end
  if E.wallpaperTint==color then return false end
  E.wallpaperTint=color; E.applyAccent()
  if not deferRedraw and E.allDirty then E.allDirty() end
  return true
 end
 E.setTheme=function(name) E.cfg.theme=palettes[name] and name or "black"; E.applyAccent(); if E.allDirty then E.allDirty() end end
 E.applyAccent()
 E.saveConfig=function() return context.config:save() end
 return E
end
return Runtime

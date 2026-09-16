-- HCC OS v1.5 shared GUI runtime.
local Runtime={}
local defaults={networkRefresh=3,resourceRefresh=2,maxImageDownload=4194304,
  imageCacheLimit=4194304,imageCacheEnabled=true,wallpaperCache=true,
  imageDownloadConcurrency=3,httpImageCacheLimit=8388608,httpImageCacheEnabled=true,
  cursorIdle=6,uiScale=1}
local palettes={
 -- Keep the existing "black" theme name for compatibility, but make its
 -- default shell match the Windows 10 dark desktop: blue wallpaper, dark
 -- taskbar, light text and a Windows blue accent.
 black={desktopBackground=0xFF075985,windowBackground=0xFF1F1F1F,panelBackground=0xFF2D2D30,
 textPrimary=0xFFF3F3F3,textSecondary=0xFFC8C8C8,border=0xFF5A5A5A,accent=0xFF0078D4,
 success=0xFF6CCB5F,warning=0xFFFFC857,error=0xFFE81123,grid=0xFF0B6EA8,
 taskbarBackground=0xFF111111,titlebarActive=0xFF0078D4,titlebarInactive=0xFF2D2D30,
 menuBackground=0xFF202020,menuHeader=0xFF2D2D30,menuSelection=0xFF3A3A3A,
 desktopSelection=0xFF146EA5,desktopHover=0xFF1A638F,wallpaperMark=0xFF0B4F78,
 inputBackground=0xFF2B2B2B},
 midnight={desktopBackground=0xFF030914,windowBackground=0xFF0E1C30,panelBackground=0xFF1B304C,
 textPrimary=0xFFF0F5FA,textSecondary=0xFFB0C5DD,border=0xFF52769B,accent=0xFFABA0FF,
 success=0xFF60DA90,warning=0xFFFFC65B,error=0xFFFF6978,grid=0xFF263D59,
 taskbarBackground=0xFF09111D,titlebarActive=0xFF1D4F91,titlebarInactive=0xFF1B304C,
 menuBackground=0xFF0E1C30,menuHeader=0xFF1B304C,menuSelection=0xFF28476A,
 desktopSelection=0xFF284F7A,desktopHover=0xFF1C3A5B,wallpaperMark=0xFF071A31,
 inputBackground=0xFF10243D}}
local accents={cyan=0xFF46CFF0,blue=0xFF70C8FF,purple=0xFFB9A7FF,green=0xFF60DA90,gold=0xFFFFC65B,red=0xFFFF6978}
function Runtime.new(context)
 local E=setmetatable({context=context},{__index=_ENV})
 E.unpack=table.unpack or unpack
 E.floor,E.min,E.max=math.floor,math.min,math.max
 E.HCC_VERSION="1.5.0"; E.HCC_VERSION_LABEL="HCC OS v1.5.0"
 E.HCC_CPU="Himantel Core 5 140"; E.HCC_TARGET_W,E.HCC_TARGET_H=576,320
 E.HCC_BLOCKS_X,E.HCC_BLOCKS_Y,E.HCC_PIXELS_PER_BLOCK=9,5,64
 E.HCC_MAX_WINDOWS,E.HCC_MAX_LOGS,E.HCC_MAX_HISTORY=24,400,180
 local geometry
 if type(require)=="function" then
  local ok,value=pcall(require,"hcc.geometry")
  if ok and type(value)=="table" then geometry=value end
 end
 E.finite=function(n) return type(n)=="number" and n==n and math.abs(n)<1e12 end
 E.clamp=function(n,a,b) return math.max(a,math.min(b,n)) end
 E.now=function() return os.epoch("utc")/1000 end
 E.jst=function() return os.date("!*t",math.floor(E.now())+32400) end
 E.timeText=function(d) return string.format("%02d:%02d:%02d",d.hour,d.min,d.sec) end
 E.dateText=function(d) return string.format("%04d-%02d-%02d",d.year,d.month,d.day) end
 E.geometry=geometry
 E.box=geometry and geometry.rect or function(x,y,w,h) return {x=math.floor(x),y=math.floor(y),w=math.max(0,math.floor(w)),h=math.max(0,math.floor(h))} end
 E.intersect=geometry and geometry.intersect or function(a,b) local x,y=math.max(a.x,b.x),math.max(a.y,b.y); local r,t=math.min(a.x+a.w,b.x+b.w),math.min(a.y+a.h,b.y+b.h); if r<=x or t<=y then return nil end; return E.box(x,y,r-x,t-y) end
 E.union=geometry and geometry.union or function(a,b) local x,y=math.min(a.x,b.x),math.min(a.y,b.y); return E.box(x,y,math.max(a.x+a.w,b.x+b.w)-x,math.max(a.y+a.h,b.y+b.h)-y) end
 E.inside=geometry and geometry.contains or function(r,x,y) return x>=r.x and y>=r.y and x<r.x+r.w and y<r.y+r.h end
 E.copy=function(t) local r={} for k,v in pairs(t) do r[k]=v end return r end
 E.ascii=function(s) return tostring(s or ""):gsub("[^\032-\126]","?") end
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
 E.configPath=context.paths.settings
 E.configWarning=context.config.warning
 E.palettes=palettes
 E.applyAccent=function()
  local base=palettes[E.cfg.theme] or palettes.black; E.P=E.copy(base); E.palette=E.P
  local color=accents[tostring(E.cfg.accent or ""):lower()]; if color then E.P.accent=color end; E.palette=E.P
 end
 E.setTheme=function(name) E.cfg.theme=palettes[name] and name or "black"; E.applyAccent(); if E.allDirty then E.allDirty() end end
 E.applyAccent()
 E.saveConfig=function() return context.config:save() end
 E.HCCV14=context.api
 return E
end
return Runtime

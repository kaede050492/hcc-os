-- HCC OS v1.5 graphical first-boot setup.
return function(E)
 local env=setmetatable({Driver=E.AppDriver,OS=E.AppOS},{__index=E}); local _ENV=env
 local pages={"Welcome","Display","Input","Network","Appearance","Computer Label","Update Settings","Finish"}
 local Setup={}
 function Setup:init() self.page=1; self.status="Settings are saved only when Finish is selected."; self.networkStatus="Not checked" end
 function Setup:interval() return 0.5 end
 function Setup:update()
  if self.networkStarted and HCCV14 and HCCV14.context and HCCV14.context.updater then
   local state=HCCV14.context.updater:status(); self.networkStatus=state.message or state.phase or self.networkStatus
  end
  mark(self.win)
 end
 function Setup:next(delta)
  self.page=clamp(self.page+delta,1,#pages)
  if pages[self.page]=="Network" and not self.networkStarted and HCCV14 then
   self.networkStarted=true; local ok,err=HCCV14.beginAutoCheck()
   self.networkStatus=ok and "Checking GitHub manifest..." or ("Manifest check unavailable: "..tostring(err))
  end
  mark(self.win)
 end
 function Setup:edit()
  local page=pages[self.page]
  if page=="Appearance" then dialog("Appearance","Theme black/midnight",{"OK","Cancel"},function(b,v) if b=="OK" then setTheme(v); mark(self.win) end end,cfg.theme)
  elseif page=="Computer Label" then dialog("Computer Label","Name for this computer",{"OK","Cancel"},function(b,v) if b=="OK" then cfg.computerLabel=ascii(v):sub(1,48); mark(self.win) end end,cfg.computerLabel)
  elseif page=="Update Settings" then cfg.autoUpdateCheck=not cfg.autoUpdateCheck; mark(self.win)
  elseif page=="Finish" then
   local ok,err=context.config:completeFirstBoot()
   if not ok then errorBox(err); return end
   for i,id in ipairs(OS.order) do if id=="setup" then table.remove(OS.order,i); break end end
   OS.registry.setup=nil; notify("Setup complete",P.success); closeWindow(self.win)
  else self:next(1) end
 end
 function Setup:onKey(k)
  local page=pages[self.page]
  if k==keys.left then self:next(-1) elseif k==keys.right then self:next(1) elseif k==keys.enter then self:edit()
  elseif page=="Appearance" and k==keys.a then dialog("Accent","cyan/blue/purple/green/gold/red",{"OK","Cancel"},function(b,v) if b=="OK" then cfg.accent=ascii(v):lower(); applyAccent(); allDirty() end end,cfg.accent)
  elseif page=="Appearance" and k==keys.w then local modes={black="center",center="fit",fit="fill",fill="stretch",stretch="tile",tile="black"}; cfg.wallpaperMode=modes[cfg.wallpaperMode] or "black"; resetWallpaperCache(); allDirty()
  elseif page=="Update Settings" and k==keys.c then cfg.updateChannel=cfg.updateChannel=="stable" and "beta" or "stable"; mark(self.win) end
 end
 function Setup:draw(c)
  c:text(8,7,"FIRST BOOT SETUP  "..self.page.."/"..#pages,P.accent)
  for i=1,#pages do c:filledRectangle(8+(i-1)*math.max(8,math.floor((c.w-16)/#pages)),23,math.max(4,math.floor((c.w-20)/#pages)),3,i<=self.page and P.accent or P.border) end
  local page=pages[self.page]; c:text(8,37,page,P.textPrimary,2)
  if page=="Welcome" then c:paragraph(8,66,"Welcome to HCC OS v1.5. Existing files are preserved. This setup configures the modular Tom's GPU desktop.",P.textSecondary,c.w-16,6)
  elseif page=="Display" then c:text(8,66,"Tom's GPU: "..tostring(devices.gpuName or "Unavailable"),P.textPrimary); c:text(8,82,string.format("Measured display: %dx%d",Driver.w,Driver.h),P.textSecondary); c:text(8,98,"Reference: 9x5 blocks / 64 pixels per block",P.textSecondary)
  elseif page=="Input" then c:text(8,66,next(devices.keyboards) and "Portable/Tom keyboard connected" or "CC:T keyboard active",P.textPrimary); c:text(8,82,"Mouse events and drag capture are enabled.",P.textSecondary)
  elseif page=="Network" then c:text(8,66,type(http)=="table" and "HTTP API available" or "HTTP API unavailable",P.textPrimary); c:paragraph(8,82,"GitHub manifest: "..self.networkStatus,P.textSecondary,c.w-16,3)
  elseif page=="Appearance" then c:text(8,66,"Theme: "..cfg.theme.."  Accent: "..tostring(cfg.accent),P.textPrimary); c:text(8,82,"Wallpaper: "..cfg.wallpaperMode,P.textSecondary); c:text(8,99,"ENTER theme  A accent  W wallpaper mode",P.textSecondary)
  elseif page=="Computer Label" then c:text(8,66,"Label: "..(cfg.computerLabel~="" and cfg.computerLabel or "Unlabelled"),P.textPrimary)
  elseif page=="Update Settings" then c:text(8,66,"Channel: "..cfg.updateChannel,P.textPrimary); c:text(8,82,"Automatic check: "..(cfg.autoUpdateCheck and "ON" or "OFF"),P.textSecondary); c:text(8,99,"C channel  ENTER automatic check",P.textSecondary)
  else c:paragraph(8,66,"Finish saves first-boot state and opens the HCC OS desktop.",P.textPrimary,c.w-16,4) end
  button(self,c,8,c.h-25,62,"BACK",function() self:next(-1) end); button(self,c,75,c.h-25,62,self.page==#pages and "FINISH" or "NEXT",function() self:edit() end)
  c:text(145,c.h-20,self.status,P.textSecondary)
 end
 register("setup","Setup","ST",430,220,Setup)
end

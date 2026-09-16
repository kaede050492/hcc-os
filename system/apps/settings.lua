-- HCC OS v1.4 GUI application module.
return function(E)
    local env=setmetatable({Driver=E.AppDriver,OS=E.AppOS},{__index=E})
    local _ENV=env
local settingsFields={
    {"system","System","section"}, {"computerLabel","Computer Label","string"},
    {"clockInterval","Clock interval (s)",0.1,5},
    {"radarInterval","Radar interval (s)",0.25,5}, {"serverInterval","Server interval (s)",1,5},
    {"snapEnabled","Window snap","toggle"}, {"snapDistance","Snap distance",2,32},
    {"appearance","Appearance","section"}, {"theme","Theme","theme"}, {"accent","Accent","string"},
    {"showRichIcons","Rich icons","toggle"}, {"taskbarLabels","Taskbar labels","toggle"},
    {"wallpaperMode","Wallpaper mode","wallpaperMode"}, {"wallpaperPath","Wallpaper .hcci path","string"},
    {"display","Display","section"}, {"resolution","GPU resolution",16,64},
    {"centerX","Radar center X",-1000000000,1000000000}, {"centerZ","Radar center Z",-1000000000,1000000000},
    {"input","Input","section"},
    {"dimension","Radar dimension","string"}, {"gpuName","GPU name (blank = auto)","string"},
    {"keyboardName","Keyboard (blank = auto)","string"}, {"detectorName","Detector (blank = auto)","string"}}
table.insert(settingsFields, {"network","Network","section"})
table.insert(settingsFields, {"update","Update & Recovery","action"})
table.insert(settingsFields, {"restore","Restore Previous Version","restore"})
table.insert(settingsFields, {"updateChannel","Update Channel","string"})
table.insert(settingsFields, {"autoUpdateCheck","Automatic update check","toggle"})
table.insert(settingsFields, {"storage","Storage","section"})
table.insert(settingsFields, {"storageInfo","Capacity / free space","storage"})
table.insert(settingsFields, {"about","About","about"})
local Settings={}
function Settings:init() self.selected=1; self.top=1 end
function Settings:edit()
    local f=settingsFields[self.selected]
    if not f or f[3]=="section" or f[3]=="about" or f[3]=="storage" then return end
    if f[3]=="action" then if HCCV14 then openApp("updates") else errorBox("Update service unavailable") end; return end
    if f[3]=="restore" then
        if not HCCV14 then errorBox("Update service unavailable"); return end
        local ok,err=HCCV14.rollback(); if ok then notify("Previous version restored; restart HCC OS",P.success) else errorBox(err) end
        return
    end
    if f[3]=="theme" then setTheme(cfg.theme=="black" and "midnight" or "black"); return end
    if f[3]=="toggle" then cfg[f[1]]=not cfg[f[1]]; mark(self.win); return end
    if f[3]=="wallpaperMode" then
        local modes={black="center",center="fit",fit="fill",fill="stretch",stretch="tile",tile="black"}
        cfg.wallpaperMode=modes[cfg.wallpaperMode] or "black"; resetWallpaperCache(); allDirty(); return
    end
    dialog("Setting",f[2],{"OK","Cancel"},function(b,value)
        if b~="OK" then return end
        if f[3]=="string" then
            if #value>128 or value:find("[\r\n]") then errorBox("Use one line, at most 128 characters"); return end
            cfg[f[1]]=value
        else
            local n=tonumber(value)
            if not finite(n) or n<f[3] or n>f[4] then errorBox("Allowed range: "..f[3].." to "..f[4]); return end
            cfg[f[1]]=n
        end
        for _,w in ipairs(OS.windows) do
            if w.id=="radar" then w.app.dim=dimension(cfg.dimension); w.nextUpdate=now() end
        end
        mark(self.win)
    end,tostring(cfg[f[1]]))
end
function Settings:save()
    local ok,err=saveConfig(); if ok then notify("Settings saved",P.success) else errorBox(err) end
end
function Settings:onKey(k)
    if k==keys.up then self.selected=max(1,self.selected-1)
    elseif k==keys.down then self.selected=min(#settingsFields,self.selected+1)
    elseif k==keys.enter then self:edit()
    elseif k==keys.s then self:save()
    elseif k==keys.f5 then rescan() end
    mark(self.win)
end
function Settings:onMouse(kind,x,y,b)
    if kind=="scroll" then self.selected=clamp(self.selected+b,1,#settingsFields)
    elseif kind=="click" and y>=34 and y<self.win.h-TITLE-31 then
        local i=self.top+floor((y-34)/18)
        if settingsFields[i] then self.selected=i; self:edit() end
    end
    mark(self.win)
end
function Settings:draw(c)
    c:text(6,6,string.format("DISPLAY %dx%d  TARGET 576x320",Driver.w,Driver.h),P.accent)
    c:text(6,19,"Names take effect after RESCAN",P.textSecondary)
    local rows=max(1,floor((c.h-64)/18))
    if self.selected<self.top then self.top=self.selected elseif self.selected>=self.top+rows then self.top=self.selected-rows+1 end
    for j=0,rows-1 do
        local i=self.top+j; local f=settingsFields[i]; if not f then break end
        local y=34+j*18
        if f[3]=="section" then
            c:text(9,y+4,string.upper(f[2]),P.accent)
        else
            if i==self.selected then c:filledRectangle(5,y,c.w-10,17,P.panelBackground) end
            c:clipping(9,y+4,c.w*0.6-12,10):text(0,0,f[2],P.textSecondary)
            local value=(f[3]=="action" and "OPEN") or (f[3]=="restore" and "RUN") or (f[3]=="about" and (HCC_VERSION_LABEL.." / BUILD 1400 / EDITION TOM") or tostring(cfg[f[1]]))
            if f[3]=="about" then
                local id=cfg.computerId~="" and cfg.computerId or "UNKNOWN"
                local label=cfg.computerLabel~="" and cfg.computerLabel or "UNLABELLED"
                local aw,ah=Driver.getActualSize()
                c:clipping(9,y+4,c.w-18,10):text(0,0,string.format("%s / ID %s / %s / %dx%d",HCC_VERSION_LABEL,id,label,aw,ah),P.textPrimary)
            elseif f[3]=="storage" then
                local capacity,free
                if type(fs.getCapacity)=="function" then local ok,value=pcall(fs.getCapacity,"/"); if ok then capacity=value end end
                if type(fs.getFreeSpace)=="function" then local ok,value=pcall(fs.getFreeSpace,"/"); if ok then free=value end end
                local storage=(capacity and free) and string.format("%.0f / %.0f bytes",free,capacity) or "Unavailable"
                c:text(c.w*0.6,y+4,storage,P.textPrimary)
            else
                c:text(c.w*0.6,y+4,value=="" and "AUTO" or value,P.textPrimary)
            end
        end
    end
    button(self,c,5,c.h-23,62,"S: SAVE",function() self:save() end)
    button(self,c,73,c.h-23,80,"RESCAN",function() rescan() end)
    button(self,c,159,c.h-23,76,"UPDATE",function() self:editUpdate() end)
end
function Settings:editUpdate()
    if HCCV14 then openApp("updates") else errorBox("Update service unavailable") end
end
register("settings","Settings","ST",372,272,Settings)

end

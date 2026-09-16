-- HCC OS v1.5 GUI application module.
return function(E)
    local env=setmetatable({Driver=E.AppDriver,OS=E.AppOS},{__index=E})
    local _ENV=env
local Terminal={}
function Terminal:init() self.lines={HCC_VERSION_LABEL.." terminal","Type help for commands."}; self.input=""; self.cursor=0; self.scroll=0 end
function Terminal:write(line) self.lines[#self.lines+1]=ascii(line); if #self.lines>200 then table.remove(self.lines,1) end end
function Terminal:execute(line)
    line=line:gsub("^%s+",""):gsub("%s+$",""); self:write("> "..line); if line=="" then return end
    local cmd,arg=line:match("^(%S+)%s*(.*)$"); cmd=cmd:lower()
    if cmd=="help" then self:write("help version apps sysinfo peripherals date clear open <id> close tile update recovery install echo <text>")
    elseif cmd=="version" then self:write(HCC_VERSION_LABEL)
    elseif cmd=="apps" then self:write(table.concat(OS.order,"  "))
    elseif cmd=="sysinfo" then local w,h=Driver.getActualSize(); self:write(string.format("HCC FICTIONAL CPU %s | DISPLAY %dx%d | GPU %s",HCC_CPU,w,h,devices.gpuName or "none"))
    elseif cmd=="peripherals" then self:write(#devices.list.." peripherals: "..table.concat((function() local a={}; for _,v in ipairs(devices.list) do a[#a+1]=v.name end; return a end)(),", "))
    elseif cmd=="date" then self:write(dateText(jst()).." "..timeText(jst()).." JST")
    elseif cmd=="clear" then self.lines={}; self.scroll=0
    elseif cmd=="echo" then self:write(arg)
    elseif cmd=="open" and OS.registry[arg] then openApp(arg)
    elseif cmd=="update" and HCCV14 then openApp("updates")
    elseif cmd=="recovery" then shell.run("/startup.lua","--recovery")
    elseif cmd=="install" then self:write("Run the standalone installer from CraftOS.")
    elseif cmd=="close" then closeWindow(self.win)
    elseif cmd=="tile" then tileWindows()
    else self:write("Unknown command: "..cmd) end
    self.input=""; self.cursor=0; self.scroll=0; mark(self.win)
end
function Terminal:onChar(s) self.input=self.input:sub(1,self.cursor)..ascii(s)..self.input:sub(self.cursor+1); self.cursor=self.cursor+#s; mark(self.win) end
function Terminal:onKey(k)
    if k==keys.enter then self:execute(self.input)
    elseif k==keys.left then self.cursor=max(0,self.cursor-1)
    elseif k==keys.right then self.cursor=min(#self.input,self.cursor+1)
    elseif k==keys.home then self.cursor=0 elseif k==keys["end"] then self.cursor=#self.input
    elseif k==keys.backspace and self.cursor>0 then self.input=self.input:sub(1,self.cursor-1)..self.input:sub(self.cursor+1); self.cursor=self.cursor-1
    elseif k==keys.delete then self.input=self.input:sub(1,self.cursor)..self.input:sub(self.cursor+2)
    elseif k==keys.up then self.scroll=min(max(0,#self.lines-1),self.scroll+1)
    elseif k==keys.down then self.scroll=max(0,self.scroll-1) end
    mark(self.win)
end
function Terminal:draw(c)
    c:filledRectangle(0,0,c.w,c.h,0xFF050505)
    local rows=max(1,floor((c.h-32)/11)); local last=#self.lines-self.scroll; local first=max(1,last-rows+1)
    for i=first,last do c:text(7,5+(i-first)*11,self.lines[i],P.textPrimary) end
    c:filledRectangle(5,c.h-22,c.w-10,18,0xFF111111); c:text(8,c.h-18,"> "..self.input,P.accent)
    local cx=8+Driver.measure("> "..self.input:sub(1,self.cursor)); c:line(cx,c.h-19,cx,c.h-7,P.textPrimary)
end
register("terminal","Terminal","TR",510,250,Terminal)

end

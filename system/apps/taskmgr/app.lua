-- HCC OS v1.5 GUI application module.
return function(E)
    local env=setmetatable({Driver=E.AppDriver,OS=E.AppOS},{__index=E})
    local _ENV=env
local TaskManager={}
function TaskManager:init() self.selected=1 end
function TaskManager:onKey(k)
    if k==keys.up then self.selected=max(1,self.selected-1)
    elseif k==keys.down then self.selected=min(#OS.windows,self.selected+1)
    elseif k==keys.enter then local w=OS.windows[self.selected]; if w then focus(w) end
    elseif k==keys.delete then local w=OS.windows[self.selected]; if w then closeWindow(w) end end
    mark(self.win)
end
function TaskManager:onMouse(kind,x,y,b)
    if kind=="scroll" then self.selected=clamp(self.selected+b,1,max(1,#OS.windows))
    elseif kind=="click" and y>=33 and y<self.win.h-30 then self.selected=clamp(1+floor((y-33)/18),1,max(1,#OS.windows)) end
    mark(self.win)
end
function TaskManager:draw(c)
    c:text(6,6,"TASK MANAGER",P.accent); c:text(6,20,"ENTER focus  DELETE close  F6 tile",P.textSecondary)
    for i,w in ipairs(OS.windows) do
        local y=33+(i-1)*18; if i==self.selected then c:filledRectangle(5,y,c.w-10,17,P.panelBackground) end
        drawAppIcon(c,w.app,8,y+1,14,w.crash and "error" or (w==OS.active and "selected" or (iconIsOffline(w.id) and "offline" or "normal")))
        c:text(28,y+4,w.name:sub(1,24),w.crash and P.error or P.textPrimary)
        c:text(c.w-84,y+4,w.minimized and "MIN" or (w==OS.active and "ACTIVE" or "READY"),P.textSecondary)
    end
    if #OS.windows==0 then c:text(8,45,"No running applications",P.textSecondary) end
    c:text(6,c.h-13,string.format("%d tasks  HCC FICTIONAL CPU %s",#OS.windows,HCC_CPU),P.textSecondary)
end
register("taskmgr","Task Manager","TM",390,220,TaskManager)

end

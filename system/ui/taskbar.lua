return function(E)
 local env=setmetatable({},{__index=E})
 local _ENV=env
local function taskRects()
    local out={}; local available=Driver.w-110
    local width=max(12,min(88,floor(available/max(1,#OS.windows))))
    for i,w in ipairs(OS.windows) do out[#out+1]={win=w,r=box(43+(i-1)*width,Driver.h-TASK+2,width-2,TASK-4)} end
    return out
end
local function buildTask()
    local list={}; local c=canvas(list,0,0,Driver.w,Driver.h)
    c:filledRectangle(0,Driver.h-TASK,Driver.w,TASK,P.panelBackground)
    c:line(0,Driver.h-TASK,Driver.w-1,Driver.h-TASK,P.border)
    c:text(8,Driver.h-TASK+6,"HCC",P.accent)
    for _,item in ipairs(taskRects()) do
        local r,w=item.r,item.win
        local state=w.crash and "error" or (w==OS.active and not w.minimized and "selected" or (iconIsOffline(w.id) and "offline" or "normal"))
        if w==OS.active and not w.minimized then c:filledRectangle(r.x,r.y,r.w,r.h,P.border) end
        if cfg.showRichIcons and r.w>=18 then drawAppIcon(c,w.app,r.x+2,r.y+1,min(16,r.h-2),state) end
        if cfg.taskbarLabels and r.w>=44 then
            local tx=r.x+(cfg.showRichIcons and 21 or 3)
            c:clipping(tx,r.y+4,r.x+r.w-tx-3,10):text(0,0,shortText(w.name,12),w.minimized and P.textSecondary or P.textPrimary)
        end
        if not w.minimized then c:line(r.x,r.y+r.h-1,r.x+r.w-1,r.y+r.h-1,P.accent) end
    end
    c:filledRectangle(Driver.w-92,Driver.h-TASK+2,92,TASK-3,P.panelBackground)
    c:text(Driver.w-88,Driver.h-TASK+3,HCC_VERSION,P.accent)
    c:text(Driver.w-60,Driver.h-TASK+6,timeText(jst()),P.textPrimary)
    OS.task=list; OS.taskDirty=false
end
E.taskRects=taskRects; E.buildTask=buildTask

end


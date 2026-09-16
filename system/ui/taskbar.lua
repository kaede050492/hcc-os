-- HCC OS v1.5 bottom taskbar.

return function(E)
    local env=setmetatable({},{__index=E})
    local _ENV=env
    local function taskRects()
        local startW=78; local statusW=min(164,max(120,floor(Driver.w*0.26)))
        local available=max(1,Driver.w-startW-statusW-4); local count=#OS.windows
        local width=count>0 and max(46,min(142,floor(available/count))) or 0; local result={}
        for i,w in ipairs(OS.windows) do
            result[#result+1]={win=w,r=box(startW+(i-1)*width,Driver.h-TASK+3,max(1,width-3),TASK-6)}
        end
        return result,startW,statusW
    end
    local function buildTask()
        local list={}; local c=canvas(list,0,0,Driver.w,Driver.h); local tasks,startW,statusW=taskRects()
        c:filledRectangle(0,Driver.h-TASK,Driver.w,TASK,P.panelBackground)
        c:line(0,Driver.h-TASK,Driver.w-1,Driver.h-TASK,P.accent)
        c:filledRectangle(0,Driver.h-TASK,startW,TASK,OS.menu and P.accent or P.panelBackground)
        drawControlIcon(c,12,Driver.h-TASK+7,13,"menu",OS.menu and P.desktopBackground or P.accent)
        c:text(32,Driver.h-TASK+9,"START",OS.menu and P.desktopBackground or P.textPrimary)
        for _,item in ipairs(tasks) do
            local r,w=item.r,item.win; local active=w==OS.active and not w.minimized
            if active then c:filledRectangle(r.x,r.y,r.w,r.h,P.windowBackground) end
            local state=w.crash and "error" or (active and "selected" or (w.minimized and "disabled" or "running"))
            if r.w>=22 then drawAppIcon(c,w.app,r.x+3,r.y+2,min(18,r.h-2),state) end
            if r.w>=62 then
                local tx=r.x+24; local width=max(8,r.x+r.w-tx-4)
                c:clipping(tx,r.y+5,width,10):text(0,0,shortText(w.name,math.max(4,floor(width/6))),
                    active and P.textPrimary or P.textSecondary)
            end
            if active then c:filledRectangle(r.x+2,r.y+r.h-2,r.w-4,2,P.accent) end
        end
        local statusX=Driver.w-statusW
        c:filledRectangle(statusX,Driver.h-TASK+1,statusW-1,TASK-2,P.windowBackground)
        local gpuLabel=devices.gpuAvailable and "GPU" or "OFF"
        c:text(statusX+8,Driver.h-TASK+9,gpuLabel,devices.gpuAvailable and P.success or P.warning)
        c:text(statusX+43,Driver.h-TASK+9,timeText(jst()),P.textPrimary)
        if Driver.w>=480 then c:text(statusX+99,Driver.h-TASK+9,HCC_VERSION,P.textSecondary) end
        OS.task=list; OS.taskDirty=false
    end
    E.taskRects=taskRects; E.buildTask=buildTask
end

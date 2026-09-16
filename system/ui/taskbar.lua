-- HCC OS v1.5 bottom taskbar.

return function(E)
    local env=setmetatable({},{__index=E})
    local _ENV=env
    local function taskRects()
        local startW=36; local searchW=min(72,max(58,floor(Driver.w*0.13)))
        local statusW=min(178,max(142,floor(Driver.w*0.28)))
        local taskStart=startW+searchW; local available=max(1,Driver.w-taskStart-statusW-4); local count=#OS.windows
        local width=count>0 and max(46,min(142,floor(available/count))) or 0; local result={}
        for i,w in ipairs(OS.windows) do
            result[#result+1]={win=w,r=box(taskStart+(i-1)*width,Driver.h-TASK+3,max(1,width-3),TASK-6)}
        end
        return result,startW,statusW,searchW
    end
    local function buildTask()
        local list={}; local c=canvas(list,0,0,Driver.w,Driver.h); local tasks,startW,statusW,searchW=taskRects()
        local barY=Driver.h-TASK; local bar=P.taskbarBackground or P.panelBackground
        c:filledRectangle(0,barY,Driver.w,TASK,bar)
        c:line(0,barY,Driver.w-1,barY,P.border)
        c:filledRectangle(0,barY,startW,TASK,OS.menu and P.accent or bar)
        drawControlIcon(c,10,barY+8,14,"windows",OS.menu and P.textPrimary or P.accent)
        c:filledRectangle(startW,barY,searchW,TASK,P.inputBackground or P.panelBackground)
        c:line(startW,barY,startW,Driver.h-1,P.border)
        drawControlIcon(c,startW+7,barY+8,13,"search",P.textSecondary)
        if searchW>=66 then c:text(startW+26,barY+10,"SEARCH",P.textSecondary) end
        for _,item in ipairs(tasks) do
            local r,w=item.r,item.win; local active=w==OS.active and not w.minimized
            if active then c:filledRectangle(r.x,r.y,r.w,r.h,P.menuSelection or P.windowBackground) end
            local state=w.crash and "error" or (active and "selected" or (w.minimized and "disabled" or "running"))
            if r.w>=28 then drawAppIcon(c,w.app,r.x+3,r.y,min(24,r.h),state) end
            if r.w>=62 then
                local tx=r.x+30; local width=max(8,r.x+r.w-tx-4)
                c:clipping(tx,r.y+5,width,10):text(0,0,shortText(w.name,math.max(4,floor(width/6))),
                    active and P.textPrimary or P.textSecondary)
            end
            if active then c:filledRectangle(r.x+2,r.y+r.h-2,r.w-4,2,P.accent) end
        end
        local statusX=Driver.w-statusW
        c:filledRectangle(statusX,barY+1,statusW-1,TASK-2,bar)
        local gpuLabel=devices.gpuAvailable and "GPU" or "OFF"
        c:text(statusX+7,barY+5,gpuLabel,devices.gpuAvailable and P.success or P.warning)
        c:text(statusX+40,barY+5,timeText(jst()),P.textPrimary)
        if Driver.w>=480 then c:text(statusX+40,barY+15,dateText(jst()),P.textSecondary) end
        OS.task=list; OS.taskDirty=false
    end
    E.taskRects=taskRects; E.buildTask=buildTask
end

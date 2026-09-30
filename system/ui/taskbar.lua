-- HCC OS v1.5 bottom taskbar.

return function(E)
    local env=setmetatable({},{__index=E})
    local _ENV=env
    local function taskRects()
        local startW=min(42,max(36,floor(Driver.w*0.075)))
        local searchW=min(52,max(34,floor(Driver.w*0.09)))
        local statusW=min(136,max(78,floor(Driver.w*0.22)))
        local taskArea=max(0,Driver.w-startW-searchW-statusW)
        local count=#OS.windows
        local capacity=max(1,floor(taskArea/58))
        local overflow=count>capacity
        local arrowW=overflow and 15 or 0
        local usable=max(1,taskArea-arrowW*2)
        if overflow then capacity=max(1,floor(usable/58)) end
        capacity=min(capacity,max(1,count))
        local width=count>0 and max(1,min(132,floor(usable/capacity))) or 0
        local first=clamp(OS.taskScroll or 1,1,max(1,count-capacity+1))
        OS.taskScroll=first
        local arrowStart=startW+searchW
        local taskStart=arrowStart+arrowW
        if not overflow and count>0 then taskStart=taskStart+floor((usable-width*count)/2) end
        local visibleEnd=min(count,first+capacity-1); local result={}
        for i=first,visibleEnd do
            local w=OS.windows[i]
            local x=taskStart+(i-first)*width
            result[#result+1]={win=w,index=i,r=box(x,Driver.h-TASK+3,max(1,width-3),TASK-6)}
        end
        return result,startW,statusW,searchW,{taskStart=taskStart,arrowStart=arrowStart,taskArea=taskArea,arrowW=arrowW,
            capacity=capacity,width=width,first=first,last=visibleEnd,overflow=overflow}
    end
    local function revealActiveTask()
        local _,_,_,_,layout=taskRects(); local activeIndex
        for i,w in ipairs(OS.windows) do if w==OS.active then activeIndex=i; break end end
        if activeIndex and activeIndex<layout.first then OS.taskScroll=activeIndex
        elseif activeIndex and activeIndex>=layout.first+layout.capacity then OS.taskScroll=activeIndex-layout.capacity+1 end
        OS.taskScroll=clamp(OS.taskScroll or 1,1,max(1,#OS.windows-layout.capacity+1))
    end
    local function buildTask()
        local list={}; local root=canvas(list,0,0,Driver.w,Driver.h); local tasks,startW,statusW,searchW,layout=taskRects()
        local barY=Driver.h-TASK; local bar=P.taskbarBackground or P.panelBackground
        local c=root:roundedClipping(0,barY,Driver.w,TASK,TASKBAR_CORNER_RADIUS)
        c:filledRectangle(0,0,Driver.w,TASK,bar)
        c:line(0,0,Driver.w-1,0,P.border)
        c:filledRectangle(0,0,startW,TASK,OS.menu and P.menuSelection or bar)
        drawControlIcon(c,floor((startW-16)/2),12,16,"menu",OS.menu and P.textPrimary or P.accent)
        c:filledRectangle(startW,0,searchW,TASK,P.inputBackground or P.panelBackground)
        c:line(startW,0,startW,TASK-1,P.border)
        if searchW>=28 then drawControlIcon(c,startW+floor((searchW-13)/2),13,13,"search",P.textSecondary) end
        if searchW>=66 then c:text(startW+26,15,"SEARCH",P.textSecondary) end
        if layout.overflow then
            c:text(startW+searchW+4,14,"<",P.textSecondary)
            c:text(startW+searchW+layout.taskArea-layout.arrowW+2,14,">",P.textSecondary)
        end
        for _,item in ipairs(tasks) do
            local r,w=item.r,item.win; local y=r.y-barY; local active=w==OS.active and not w.minimized
            if active then c:filledRectangle(r.x,y,r.w,r.h,P.menuSelection or P.windowBackground) end
            local state=w.crash and "error" or (active and "selected" or (w.minimized and "disabled" or "running"))
            if r.w>=20 then drawAppIcon(c,w.app,r.x+3,y,min(24,r.h),state) end
            if cfg.taskbarLabels~=false and r.w>=62 then
                local tx=r.x+30; local textWidth=max(8,r.x+r.w-tx-4)
                c:clipping(tx,y+5,textWidth,10):text(0,0,shortText(w.name,math.max(4,floor(textWidth/6))),
                    active and P.textPrimary or P.textSecondary)
            end
            if active then c:filledRectangle(r.x+2,y+r.h-2,max(1,r.w-4),2,P.accent) end
        end
        local statusX=max(0,Driver.w-statusW)
        c:filledRectangle(statusX,1,max(0,statusW-1),TASK-2,bar)
        local gpuLabel=statusW>=100 and (devices.gpuAvailable and "GPU" or "OFF") or
            (devices.gpuAvailable and "G" or "!")
        c:text(statusX+5,5,gpuLabel,devices.gpuAvailable and P.success or P.warning)
        c:text(statusX+max(23,statusW-53),5,timeText(jst()),P.textPrimary)
        if statusW>=120 then c:text(statusX+max(23,statusW-53),16,dateText(jst()),P.textSecondary) end
        OS.task=list; OS.taskDirty=false
    end
    E.taskRects=taskRects; E.buildTask=buildTask; E.revealActiveTask=revealActiveTask
end

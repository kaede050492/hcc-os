-- HCC OS v1.5 desktop surface.

return function(E)
    local env=setmetatable({},{__index=E})
    local _ENV=env
    local LABELS={
        peripherals={"Peripheral","Manager"},network={"Network","Manager"},taskmgr={"Task","Manager"},
        radar={"Player","Radar"},image={"Image","Viewer"},resource={"Resource","Monitor"},
        server={"Server","Monitor"},system={"System","Monitor"},currency={"Currency","Calc"},
        inventory={"Inventory","Viewer"},diagnostics={"Diagnostics"},performance={"Performance"},
        updates={"Update","Recovery"},terminal={"Terminal"},notepad={"Notepad"},clock={"Clock"},
        calendar={"Calendar"},files={"Files"},web={"HCC Web"},logs={"Log Viewer"},settings={"Settings"}
    }

    local function shortText(value,limit)
        value=ascii(value); if #value<=limit then return value end
        return value:sub(1,max(1,limit-1)).."~"
    end
    local function desktopLabel(def)
        local parts=LABELS[def and (def.id or def.iconId)]
        if parts then return parts end
        return {shortText(def and def.name or "App",12)}
    end
    local function iconIsOffline(id)
        if id=="radar" then return not devices.detector end
        if id=="network" then return #devices.modems==0 end
        if id=="peripherals" then return #devices.list==0 end
        return false
    end
    local function layout()
        local area=workspace(); local rail=74; local gridX=rail+14; local gridY=TOP+12
        local cellW=76; local cellH=60
        local columns=max(1,floor((Driver.w-gridX-10)/cellW))
        local rows=max(1,floor((Driver.h-TASK-gridY-10)/cellH))
        return {rail=rail,gridX=gridX,gridY=gridY,cellW=cellW,cellH=cellH,
            columns=columns,rows=rows,pageSize=columns*rows,area=area}
    end
    local function iconRects()
        local l=layout(); local pages=max(1,math.ceil(#OS.order/l.pageSize))
        OS.desktopPage=clamp(OS.desktopPage or 1,1,pages); OS.desktopPageCount=pages
        local first=(OS.desktopPage-1)*l.pageSize+1; local out={}
        for offset=0,min(l.pageSize-1,#OS.order-first) do
            local i=first+offset; local col=offset%l.columns; local row=floor(offset/l.columns)
            out[#out+1]={id=OS.order[i],index=offset+1,orderIndex=i,
                r=box(l.gridX+col*l.cellW,l.gridY+row*l.cellH,l.cellW-6,l.cellH-6)}
        end
        return out
    end
    local function buildDesktop()
        local list={}; local c=canvas(list,0,0,Driver.w,Driver.h-TASK); local l=layout()
        c:clear(P.desktopBackground)
        local wallpaper=wallpaperCommands()
        if wallpaper then for _,cmd in ipairs(wallpaper) do list[#list+1]=cmd end end
        c:filledRectangle(0,0,Driver.w,TOP,P.panelBackground); c:line(0,TOP-1,Driver.w-1,TOP-1,P.border)
        c:text(12,7,"HCC OS",P.accent); c:text(68,8,"CONTROL DESKTOP",P.textSecondary)
        local status=devices.gpuAvailable and "GPU READY" or "GPU OFFLINE"
        local statusColor=devices.gpuAvailable and P.success or P.warning
        local statusWidth=Driver.measure(status)+Driver.measure(timeText(jst()))+30
        c:text(max(Driver.w-statusWidth,150),8,status,statusColor)
        c:text(Driver.w-Driver.measure(timeText(jst()))-10,8,timeText(jst()),P.textPrimary)

        c:filledRectangle(8,TOP+10,l.rail-14,Driver.h-TASK-TOP-20,P.panelBackground)
        c:line(l.rail-6,TOP+10,l.rail-6,Driver.h-TASK-10,P.border)
        c:text(18,TOP+20,"APPS",P.accent)
        c:text(18,TOP+34,"F1",P.textSecondary); c:text(18,TOP+46,"MENU",P.textSecondary)
        local items=iconRects()
        if OS.desktopPageCount>1 then
            c:text(18,Driver.h-TASK-42,"PAGE",P.textSecondary)
            c:text(18,Driver.h-TASK-30,string.format("%d/%d",OS.desktopPage,OS.desktopPageCount),P.textPrimary)
        end
        for _,item in ipairs(items) do
            local def=OS.registry[item.id]; local r=item.r; local selected=OS.active==nil and OS.iconIndex==item.index
            local hovered=OS.desktopHover==item.index; local running=false; local failed=false
            for _,w in ipairs(OS.windows) do
                if w.id==item.id and not w.minimized then running=true end
                if w.id==item.id and w.crash then failed=true end
            end
            local state=failed and "error" or (selected and "selected" or (hovered and "hover" or
                (running and "running" or (iconIsOffline(item.id) and "offline" or "normal"))))
            if selected then c:filledRectangle(r.x,r.y,r.w,r.h,P.panelBackground); c:rectangle(r.x,r.y,r.w,r.h,P.accent)
            elseif hovered then c:rectangle(r.x,r.y,r.w,r.h,P.border) end
            local size=min(30,r.w-16); drawAppIcon(c,def,r.x+floor((r.w-size)/2),r.y+5,size,state)
            local labels=desktopLabel(def); local labelColor=(selected or hovered) and P.textPrimary or P.textSecondary
            for row,label in ipairs(labels) do
                local clipped=shortText(label,max(4,floor((r.w-8)/6)))
                c:text(r.x+floor((r.w-Driver.measure(clipped))/2),r.y+38+(row-1)*9,clipped,labelColor)
            end
            if running and not failed then c:filledRectangle(r.x+r.w-8,r.y+5,3,3,P.success) end
        end
        if Driver.w>=420 then
            c:text(Driver.w-185,Driver.h-TASK-18,HCC_VERSION_LABEL.."  /  READY",P.border)
        end
        OS.desktop=list; OS.desktopDirty=false
    end
    E.shortText=shortText; E.DESKTOP_LABELS=LABELS; E.desktopLabel=desktopLabel; E.iconIsOffline=iconIsOffline
    E.desktopLayout=layout; E.iconRects=iconRects; E.buildDesktop=buildDesktop
end

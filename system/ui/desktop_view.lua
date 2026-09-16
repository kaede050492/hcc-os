-- HCC OS v1.5 desktop surface.

return function(E)
    local env=setmetatable({},{__index=E})
    local _ENV=env
    local LABELS={
        peripherals={"Peripheral","Manager"},network={"Network","Manager"},taskmgr={"Task","Manager"},
        radar={"Player","Radar"},image={"Image","Viewer"},resource={"Resource","Monitor"},
        server={"Server","Monitor"},system={"System","Monitor"},currency={"Currency","Calc"},
        inventory={"Inventory","Viewer"},diagnostics={"Diagnostics"},performance={"Performance"},
        updates={"System","Update"},terminal={"Terminal"},notepad={"Notepad"},clock={"Clock"},
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
        local area=workspace(); local rail=0; local gridX=12; local gridY=12
        local cellW=78; local cellH=64
        local columns=max(1,floor((Driver.w-gridX-10)/cellW))
        local rows=max(1,floor((Driver.h-TASK-gridY-8)/cellH))
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
        -- A restrained Windows-style wallpaper mark gives the default blue
        -- background some depth without competing with a user wallpaper.
        if not wallpaper then
            local mx,my=Driver.w-174,Driver.h-TASK-154
            local mark=P.wallpaperMark or P.grid
            c:filledRectangle(mx,my,66,28,mark); c:filledRectangle(mx+34,my,66,28,mark)
            c:filledRectangle(mx,my+34,66,28,mark); c:filledRectangle(mx+34,my+34,66,28,mark)
            c:line(mx+31,my,mx+31,my+62,P.desktopBackground)
            c:line(mx,my+31,mx+96,my+31,P.desktopBackground)
        end
        local items=iconRects()
        if OS.desktopPageCount>1 then
            c:text(12,Driver.h-TASK-42,"PAGE",P.textSecondary)
            c:text(12,Driver.h-TASK-30,string.format("%d/%d",OS.desktopPage,OS.desktopPageCount),P.textPrimary)
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
            if selected then c:filledRectangle(r.x,r.y,r.w,r.h,P.desktopSelection or P.panelBackground); c:rectangle(r.x,r.y,r.w,r.h,P.accent)
            elseif hovered then c:filledRectangle(r.x,r.y,r.w,r.h,P.desktopHover or P.border); c:rectangle(r.x,r.y,r.w,r.h,P.accent) end
            local size=min(30,r.w-16); drawAppIcon(c,def,r.x+floor((r.w-size)/2),r.y+5,size,state)
            local labels=desktopLabel(def); local labelColor=(selected or hovered) and P.textPrimary or P.textSecondary
            for row,label in ipairs(labels) do
                local clipped=shortText(label,max(4,floor((r.w-8)/6)))
                c:text(r.x+floor((r.w-Driver.measure(clipped))/2),r.y+38+(row-1)*9,clipped,labelColor)
            end
            if running and not failed then c:filledRectangle(r.x+r.w-8,r.y+5,3,3,P.success) end
        end
        if Driver.w>=420 then c:text(Driver.w-185,Driver.h-TASK-18,HCC_VERSION_LABEL.."  /  READY",P.border) end
        OS.desktop=list; OS.desktopDirty=false
    end
    E.shortText=shortText; E.DESKTOP_LABELS=LABELS; E.desktopLabel=desktopLabel; E.iconIsOffline=iconIsOffline
    E.desktopLayout=layout; E.iconRects=iconRects; E.buildDesktop=buildDesktop
end

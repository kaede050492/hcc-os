return function(E)
 local env=setmetatable({},{__index=E})
 local _ENV=env
local function tileWindows()
    local visible={}; for _,w in ipairs(OS.windows) do if not w.minimized then visible[#visible+1]=w end end
    local n=#visible; if n==0 then return end
    local columns=1
    if n>1 then columns=math.ceil(math.sqrt(n)) end
    columns=min(columns,max(1,floor(Driver.w/220)),n)
    if columns<1 then columns=1 end
    local rows=math.ceil(n/columns); local areaH=Driver.h-TASK; local gap=4
    for i,w in ipairs(visible) do
        invalidate(w); local col=(i-1)%columns; local row=floor((i-1)/columns)
        local cellW=floor(Driver.w/columns); local cellH=floor(areaH/rows)
        w.restore=nil; w.minimized=false; w.x=col*cellW+gap; w.y=row*cellH+gap
        w.w=cellW-gap*2; w.h=cellH-gap*2; fit(w); mark(w)
    end
    OS.active=visible[#visible]; taskDirty()
end
rescan=function()
    local ok,status=scanDevices()
    if status=="terminate" then OS.running=false; return end
    OS.pointer.x=clamp(OS.pointer.x,0,Driver.w-1); OS.pointer.y=clamp(OS.pointer.y,0,Driver.h-1)
    OS.drag=nil; OS.held={}
    for _,w in ipairs(OS.windows) do
        if w.restore then w.restore=nil; w.x=0; w.y=0; w.w=Driver.w; w.h=Driver.h-TASK end
        appCall(w,"resume"); w.nextUpdate=now()
    end
    allDirty()
    notify(ok and "Peripherals rescanned" or "GPU unavailable; reconnect and press F5",ok and P.success or P.warning)
    if not ok then print("[HCC OS] GPU unavailable: "..(Driver.error or "not found")) end
end

local function setMenu(value)
    overlayDirty(); OS.menu=value; OS.drag=nil
end
local function desktopFocus()
    local old=OS.active; OS.active=nil; mark(old); taskDirty(); OS.desktopDirty=true; invalidate(screen())
end
local function snapWindow(win)
    if not cfg.snapEnabled or not win or win.restore then return end
    local d=cfg.snapDistance; local bottom=Driver.h-TASK
    if math.abs(win.x)<d then win.x=0 end
    if math.abs(win.y)<d then win.y=0 end
    if math.abs(win.x+win.w-Driver.w)<d then win.x=Driver.w-win.w end
    if math.abs(win.y+win.h-bottom)<d then win.y=bottom-win.h end
    for _,other in ipairs(OS.windows) do
        if other~=win and not other.minimized then
            if math.abs(win.x-(other.x+other.w))<d then win.x=other.x+other.w end
            if math.abs(win.x+win.w-other.x)<d then win.x=other.x-win.w end
            if math.abs(win.y-(other.y+other.h))<d then win.y=other.y+other.h end
            if math.abs(win.y+win.h-other.y)<d then win.y=other.y-win.h end
        end
    end
    fit(win)
end
local function resizeEdges(win,xx,yy)
    local margin=6
    return {left=xx<=margin,right=xx>=win.w-margin-1,top=yy>=TITLE and yy<=TITLE+margin,
        bottom=yy>=win.h-margin-1}
end
local function updateHover(x,y)
    local old=OS.hover; local oldDesktop=OS.desktopHover; local hovered=nil; local hit=nil
    for i=#OS.windows,1,-1 do
        local w=OS.windows[i]
        if not w.minimized and inside(w,x,y) then
            hovered=w; local xx,yy=x-w.x-1,y-w.y-TITLE
            if yy>=0 then for _,b in ipairs(w.buttons or {}) do if inside(b,xx,yy) then hit=b; break end end end
            break
        end
    end
    local same=old and old.win==hovered and ((old.hit==nil and hit==nil) or (old.hit and hit and old.hit.x==hit.x and old.hit.y==hit.y))
    if not same and old and old.win then mark(old.win) end
    OS.hover=hovered and {win=hovered,hit=hit} or nil
    if not same and OS.hover and OS.hover.win then mark(OS.hover.win) end
    local desktopIndex=nil
    if not hovered then for i,item in ipairs(iconRects()) do if inside(item.r,x,y) then desktopIndex=i; break end end end
    OS.desktopHover=desktopIndex
    if oldDesktop~=desktopIndex then
        OS.desktopDirty=true
        local rects=iconRects(); if oldDesktop and rects[oldDesktop] then invalidate(rects[oldDesktop].r) end; if desktopIndex and rects[desktopIndex] then invalidate(rects[desktopIndex].r) end
    end
end
local function pointer(kind,x,y,buttonId)
    if not finite(x) or not finite(y) then return end
    if OS.pointer.visible then invalidate(cursorRect()) end
    OS.pointer.x=floor(clamp(x,0,Driver.w-1)); OS.pointer.y=floor(clamp(y,0,Driver.h-1))
    OS.pointer.visible=kind~="exit"; if OS.pointer.visible then invalidate(cursorRect()); updateHover(OS.pointer.x,OS.pointer.y) end
    x,y=OS.pointer.x,OS.pointer.y
    if kind=="click" or kind=="down" then OS.mouseButtons[buttonId or 1]=true elseif kind=="up" then OS.mouseButtons[buttonId or 1]=nil end
    if kind=="exit" then return end
    if kind=="up" then
        if OS.drag then snapWindow(OS.drag.win); mark(OS.drag.win); taskDirty() end
        OS.drag=nil; return
    end
    if OS.modal then
        if kind=="click" and buttonId==1 then
            local m=OS.modal; local r=m.rect or dialogBox()
            for i,b in ipairs(m.hits or {}) do if inside(b,x-r.x,y-r.y) then dismiss(m.buttons[i]); break end end
        end
        return
    end
    if kind=="drag" and OS.drag then
        local d=OS.drag; local w=d.win; invalidate(w)
        if d.resize then
            local right=d.right; local bottom=d.bottom
            if d.left then w.x=x-d.offsetX; w.w=right-w.x end
            if d.rightEdge then w.w=d.startW+x-d.startX end
            if d.top then w.y=y-d.offsetY; w.h=bottom-w.y end
            if d.bottomEdge then w.h=d.startH+y-d.startY end
        else w.x=x-d.dx; w.y=y-d.dy end
        fit(w); mark(w); return
    end
    if kind~="click" and kind~="scroll" then return end
    if kind=="click" and buttonId~=1 and buttonId~=2 then return end
    if kind=="click" and buttonId==2 then
        local overWindow=false; for _,w in ipairs(OS.windows) do if not w.minimized and inside(w,x,y) then overWindow=true; break end end
        if not overWindow and y<Driver.h-TASK then
            local selected=nil; for i,item in ipairs(iconRects()) do if inside(item.r,x,y) then selected={index=i,id=item.id}; break end end
            if selected then OS.iconIndex=selected.index; OS.context={x=x,y=y,id=selected.id}; OS.menu=false; overlayDirty() else OS.context=nil; overlayDirty() end
        end
        return
    end
    if OS.context then
        local r=OS.context.rect
        if kind=="click" and r and inside(r,x,y) then
            local row=floor((y-r.y)/18); local id=OS.context.id; OS.context=nil; overlayDirty()
            if row==0 then openApp(id) elseif row==1 then allDirty() end
            return
        elseif kind=="click" then OS.context=nil; overlayDirty() end
    end
    if OS.menu then
        local r=menuBox()
        if inside(r,x,y) then
            local index=floor((y-r.y-3)/20)+(OS.menuTop or 1)
            if index>=1 and index<=#OS.order+1 and kind=="click" then
                setMenu(false); if index>#OS.order then requestExit() else openApp(OS.order[index]) end
            end
            return
        else setMenu(false) end
    end
    if y>=Driver.h-TASK then
        if kind~="click" then return end
        if x<40 then setMenu(not OS.menu); return end
        if x>=Driver.w-92 then openApp("clock"); return end
        for _,item in ipairs(taskRects()) do if inside(item.r,x,y) then
            local w=item.win
            if w==OS.active and not w.minimized then invalidate(w); w.minimized=true; OS.active=nil; taskDirty(); OS.desktopDirty=true; invalidate(box(0,0,Driver.w,Driver.h-TASK))
            else focus(w) end; return
        end end
        return
    end
    for i=#OS.windows,1,-1 do
        local w=OS.windows[i]
        if not w.minimized and inside(w,x,y) then
            if kind=="click" then focus(w) end
            local xx,yy=x-w.x,y-w.y
            if yy<TITLE and kind=="click" then
                if xx>=w.w-21 then closeWindow(w)
                elseif xx>=w.w-39 then maximize(w)
                elseif xx>=w.w-57 then invalidate(w); w.minimized=true; OS.active=nil; taskDirty(); OS.desktopDirty=true; invalidate(box(0,0,Driver.w,Driver.h-TASK))
                elseif not w.restore then
                    local t=now(); local double=w.lastTitleClick and t-w.lastTitleClick<0.4
                    w.lastTitleClick=t
                    if double then maximize(w) else OS.drag={win=w,dx=xx,dy=yy} end
                end
            elseif kind=="click" and not w.restore then
                local edge=resizeEdges(w,xx,yy)
                if edge.left or edge.right or edge.top or edge.bottom then
                    OS.drag={win=w,resize=true,x=x,y=y,startX=x,startY=y,startW=w.w,startH=w.h,
                        right=w.x+w.w,bottom=w.y+w.h,offsetX=x-w.x,offsetY=y-w.y,
                        left=edge.left,top=edge.top,rightEdge=edge.right,bottomEdge=edge.bottom}
                else
                    xx,yy=xx-1,yy-TITLE
                    if kind=="click" then for _,b in ipairs(w.buttons) do if inside(b,xx,yy) then
                        local ok,e=pcall(b.action); if not ok then errorBox(e) end; return
                    end end end
                    appCall(w,"onMouse",kind,xx,yy,buttonId)
                end
            else
                xx,yy=xx-1,yy-TITLE
                if kind=="click" then for _,b in ipairs(w.buttons) do if inside(b,xx,yy) then
                    local ok,e=pcall(b.action); if not ok then errorBox(e) end; return
                end end end
                appCall(w,"onMouse",kind,xx,yy,buttonId)
            end
            return
        end
    end
    if kind=="click" then
        desktopFocus()
        for i,item in ipairs(iconRects()) do if inside(item.r,x,y) then
            local double=OS.iconIndex==i and OS.lastIconClick and now()-OS.lastIconClick<0.45
            OS.iconIndex=i; OS.lastIconClick=now(); OS.desktopDirty=true; invalidate(item.r)
            if double then openApp(item.id) end; break
        end end
    end
end
E.tileWindows=tileWindows; E.rescan=rescan; E.setMenu=setMenu; E.desktopFocus=desktopFocus; E.snapWindow=snapWindow; E.resizeEdges=resizeEdges; E.pointer=pointer

end


-- HCC OS v1.5 window actions and layout commands.

return function(E)
    local env=setmetatable({},{__index=E})
    local _ENV=env
    local function tileWindows()
        local visible={}; for _,w in ipairs(OS.windows) do if not w.minimized then visible[#visible+1]=w end end
        local n=#visible; if n==0 then return end
        local area=workspace(); local columns=min(n,max(1,floor(area.w/220))); local rows=math.ceil(n/columns); local gap=6
        for i,w in ipairs(visible) do
            invalidate(w); local col=(i-1)%columns; local row=floor((i-1)/columns)
            local cellW=floor(area.w/columns); local cellH=floor(area.h/rows)
            w.restore=nil; w.x=area.x+col*cellW+gap; w.y=area.y+row*cellH+gap
            w.w=cellW-gap*2; w.h=cellH-gap*2; fit(w); mark(w)
        end
        OS.active=visible[#visible]; taskDirty(); OS.desktopDirty=true
    end
    local function rescan()
        local ok,status=scanDevices()
        if status=="terminate" then OS.running=false; return end
        OS.pointer.x=clamp(OS.pointer.x,0,Driver.w-1); OS.pointer.y=clamp(OS.pointer.y,0,Driver.h-1)
        OS.drag=nil; OS.held={}; OS.mouseButtons={}
        for _,w in ipairs(OS.windows) do
            if w.restore then w.restore=nil; local area=workspace(); w.x,w.y,w.w,w.h=area.x,area.y,area.w,area.h end
            appCall(w,"resume"); w.nextUpdate=now(); mark(w)
        end
        allDirty(); notify(ok and "Peripherals rescanned" or "GPU unavailable; reconnect and press F5",ok and P.success or P.warning)
        if not ok then print("[HCC OS] GPU unavailable: "..(Driver.error or "not found")) end
    end
    local function setMenu(value)
        OS.menu=value and true or false; OS.context=nil; OS.drag=nil
        if OS.menu then OS.menuIndex=clamp(OS.menuIndex,1,#OS.order+1) end
        overlayDirty()
    end
    local function desktopFocus()
        local old=OS.active; OS.active=nil; mark(old); taskDirty(); OS.desktopDirty=true; invalidate(workspace())
    end
    local function snapWindow(win)
        if not cfg.snapEnabled or not win or win.restore then return end
        local d=cfg.snapDistance; local area=workspace()
        if math.abs(win.x-area.x)<d then win.x=area.x end
        if math.abs(win.y-area.y)<d then win.y=area.y end
        if math.abs(win.x+win.w-(area.x+area.w))<d then win.x=area.x+area.w-win.w end
        if math.abs(win.y+win.h-(area.y+area.h))<d then win.y=area.y+area.h-win.h end
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
    local function resizeEdges(win,x,y)
        local margin=6
        return {left=x<=margin,right=x>=win.w-margin-1,top=y>=TITLE and y<=TITLE+margin,
            bottom=y>=win.h-margin-1}
    end
    local function cycleWindow(direction)
        local candidates={}; for _,w in ipairs(OS.windows) do if not w.minimized then candidates[#candidates+1]=w end end
        if #candidates==0 then return end
        local current=1; for i,w in ipairs(candidates) do if w==OS.active then current=i; break end end
        local nextIndex=((current-1+(direction or 1))%#candidates)+1; focus(candidates[nextIndex])
    end
    local function changeDesktopPage(delta)
        local pages=OS.desktopPageCount or 1; OS.desktopPage=clamp((OS.desktopPage or 1)+(delta or 0),1,pages)
        OS.iconIndex=1; OS.desktopHover=nil; OS.desktopDirty=true; invalidate(workspace())
    end
    E.tileWindows=tileWindows; E.rescan=rescan; E.setMenu=setMenu; E.desktopFocus=desktopFocus
    E.snapWindow=snapWindow; E.resizeEdges=resizeEdges; E.cycleWindow=cycleWindow; E.changeDesktopPage=changeDesktopPage
end

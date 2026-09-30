-- HCC OS v1.5 input router.
-- Normalises CraftOS, monitor and Tom's native keyboard/mouse events before
-- dispatching them to the window manager.

return function(E)
    local env=setmetatable({},{__index=E})
    local _ENV=env
    local function modalKey(k)
        local m=OS.modal; if not m then return end
        if k==keys.escape then dismiss("Cancel")
        elseif k==keys.enter then dismiss(m.buttons[m.index])
        elseif k==keys.tab then m.index=m.index%#m.buttons+1; overlayDirty()
        elseif m.input~=nil then
            if k==keys.left then m.pos=max(0,m.pos-1)
            elseif k==keys.right then m.pos=min(#m.input,m.pos+1)
            elseif k==keys.home then m.pos=0
            elseif k==keys["end"] then m.pos=#m.input
            elseif k==keys.backspace and m.pos>0 then m.input=m.input:sub(1,m.pos-1)..m.input:sub(m.pos+1); m.pos=m.pos-1
            elseif k==keys.delete then m.input=m.input:sub(1,m.pos)..m.input:sub(m.pos+2) end
            overlayDirty()
        elseif k==keys.left or k==keys.right then
            m.index=(m.index-1+(k==keys.left and -1 or 1))%#m.buttons+1; overlayDirty()
        end
    end
    local function activateMenuSelection()
        local entries=menuEntries(); local index=OS.menuIndex; local id=entries[index]
        if OS.powerMenu then
            if id=="@back" then OS.powerMenu=false; OS.menuIndex=1; overlayDirty(); return end
            setMenu(false)
            if id=="@restart" then requestRestart()
            elseif id=="@shutdown" then requestShutdown()
            elseif id=="@exit" then requestExit()
            elseif id=="@desktop" then desktopFocus() end
            return
        end
        if not id and #entries==0 and (OS.menuQuery or "")~="" and index==1 then return end
        if not id then OS.powerMenu=true; OS.menuIndex=1; overlayDirty(); return end
        setMenu(false)
        openApp(id)
    end
    local function traceInput(kind,target)
        if cfg.debugInputTrace==true then logLine("INFO","Input "..kind.." -> "..target) end
    end
    local function keyInput(k)
        if not finite(k) then return end
        OS.held[k]=true
        local ctrl=OS.held[keys.leftCtrl] or OS.held[keys.rightCtrl]
        local alt=OS.held[keys.leftAlt] or OS.held[keys.rightAlt]
        if ctrl and k==keys.q then
            traceInput("key","emergency exit")
            if OS.menu then setMenu(false) end
            requestExit(); return
        end
        if OS.modal then traceInput("key","modal"); modalKey(k); return end
        traceInput("key",(k==keys.f1 or OS.menu) and "start menu" or (OS.active and "window:"..OS.active.id or "desktop"))
        if k==keys.f1 then setMenu(not OS.menu); return end
        if OS.menu then
            if OS.powerMenu then
                local count=menuCount()
                if k==keys.escape or k==keys.left then OS.powerMenu=false; OS.menuIndex=1; overlayDirty()
                elseif k==keys.up then OS.menuIndex=(OS.menuIndex-2)%count+1; overlayDirty()
                elseif k==keys.down then OS.menuIndex=OS.menuIndex%count+1; overlayDirty()
                elseif k==keys.enter or k==keys.right then activateMenuSelection() end
                return
            end
            local count=menuCount()
            if k==keys.escape or (k==keys.left and OS.menuQuery=="") then setMenu(false)
            elseif k==keys.backspace then
                if #OS.menuQuery>0 then OS.menuQuery=OS.menuQuery:sub(1,-2); OS.menuIndex=1; overlayDirty() end
            elseif k==keys.left then OS.menuQuery=OS.menuQuery:sub(1,-2); OS.menuIndex=1; overlayDirty()
            elseif k==keys.up then OS.menuIndex=(OS.menuIndex-2)%count+1; overlayDirty()
            elseif k==keys.down then OS.menuIndex=OS.menuIndex%count+1; overlayDirty()
            elseif k==keys.enter or k==keys.right then activateMenuSelection() end
            return
        end
        if ctrl and k==keys.w then closeWindow(OS.active); return end
        if ctrl and k==keys.tab then cycleWindow(1); return end
        if k==keys.f5 then rescan(); return end
        if k==keys.f6 then tileWindows(); return end
        local w=OS.active
        if w then
            if k==keys.f2 then minimize(w); return end
            if k==keys.f3 then maximize(w); return end
            if alt and (k==keys.left or k==keys.right or k==keys.up or k==keys.down) then
                invalidate(w); w.restore=nil
                if k==keys.left then w.x=w.x-12 elseif k==keys.right then w.x=w.x+12 elseif k==keys.up then w.y=w.y-12 else w.y=w.y+12 end
                fit(w); mark(w); return
            end
            if k==keys.escape then desktopFocus(); return end
            appCall(w,"onKey",k)
        else
            if k==keys.enter then
                local item=iconRects()[OS.iconIndex]; if item then openApp(item.id) end
            elseif k==keys.left then
                if OS.iconIndex==1 then changeDesktopPage(-1) else OS.iconIndex=OS.iconIndex-1; OS.desktopDirty=true; invalidate(workspace()) end
            elseif k==keys.right then
                if OS.iconIndex>=#iconRects() then changeDesktopPage(1) else OS.iconIndex=OS.iconIndex+1; OS.desktopDirty=true; invalidate(workspace()) end
            elseif k==keys.up or k==keys.down then
                local items=iconRects(); local l=desktopLayout(); local delta=k==keys.up and -l.columns or l.columns
                local nextIndex=OS.iconIndex+delta
                if nextIndex>=1 and nextIndex<=#items then OS.iconIndex=nextIndex; OS.desktopDirty=true; invalidate(workspace()) end
            elseif k==keys.tab then cycleWindow(1)
            end
        end
    end
    local function charInput(s)
        if type(s)~="string" then return end
        traceInput("text",OS.modal and "modal" or (OS.menu and "start menu" or (OS.active and "window:"..OS.active.id or "desktop")))
        if OS.modal then
            local m=OS.modal
            if m.input~=nil then
                s=s:gsub("[^\010\013\032-\126]","?")
                if #m.input+#s>8192 then return end
                m.input=m.input:sub(1,m.pos)..s..m.input:sub(m.pos+1); m.pos=m.pos+#s; m.index=1; overlayDirty()
            end
        elseif OS.menu then
            if not OS.powerMenu then
                s=s:gsub("[\r\n\t]"," "):gsub("[^\032-\126]","?")
                if #OS.menuQuery+#s>80 then s=s:sub(1,max(0,80-#OS.menuQuery)) end
                if #s>0 then OS.menuQuery=OS.menuQuery..s; OS.menuIndex=1; overlayDirty() end
            end
        elseif OS.active and not (OS.held[keys.leftCtrl] or OS.held[keys.rightCtrl] or OS.held[keys.leftAlt] or OS.held[keys.rightAlt]) then
            appCall(OS.active,"onChar",s)
        end
    end
    local function hitWindow(x,y)
        for i=#OS.windows,1,-1 do
            local w=OS.windows[i]
            if not w.minimized and insideRounded(box(w.x,w.y,w.w,w.h),WINDOW_CORNER_RADIUS,x,y) then return w end
        end
    end
    local function hitTaskbar(x,y)
        return insideRounded(box(0,Driver.h-TASK,Driver.w,TASK),TASKBAR_CORNER_RADIUS,x,y)
    end
    local function resizeShape(edge)
        if edge.top and edge.left or edge.bottom and edge.right then return "resize_nwse" end
        if edge.top and edge.right or edge.bottom and edge.left then return "resize_nesw" end
        if edge.top or edge.bottom then return "resize_ns" end
        if edge.left or edge.right then return "resize_ew" end
        return "arrow"
    end
    local function updateHover(x,y)
        local old=OS.hover; local oldDesktop=OS.desktopHover; local hovered=hitWindow(x,y); local hit=nil; local shape="arrow"
        if hovered then
            local xx,yy=x-hovered.x-1,y-hovered.y-TITLE
            for _,b in ipairs(hovered.buttons or {}) do if yy>=0 and inside(b,xx,yy) then hit=b; shape="hand"; break end end
            if not hit then
                local wx,wy=x-hovered.x,y-hovered.y; local edge=resizeEdges(hovered,wx,wy)
                if edge.left or edge.right or edge.top or edge.bottom then shape=resizeShape(edge)
                elseif wy<TITLE then shape="hand" end
            end
        end
        local desktopIndex=nil
        if not hovered and y<TOP then shape="hand"
        elseif not hovered then
            for i,item in ipairs(iconRects()) do if inside(item.r,x,y) then desktopIndex=item.index; shape="hand"; break end end
            if hitTaskbar(x,y) then shape="hand" end
        end
        if OS.modal and OS.modal.input~=nil then
            local r=OS.modal.rect or dialogBox(); local field=box(r.x+8,r.y+r.h-58,r.w-16,22)
            if inside(field,x,y) then shape="text" end
        end
        if OS.menu then
            local r=menuBox(); local field=box(r.x+10,r.y+34,r.w-20,20)
            local count=menuCount(); local listTop=menuListY+menuHeaderHeight(OS)
            if not OS.powerMenu and inside(field,x,y) then shape="text"
            elseif insideRounded(r,START_MENU_CORNER_RADIUS,x,y) and y-r.y>=listTop then
                local index=menuIndexAt(OS,y)
                if index>=1 and index<=count and OS.menuIndex~=index then OS.menuIndex=index; overlayDirty() end
            end
        end
        if old and old.win then mark(old.win) end
        OS.hover=hovered and {win=hovered,hit=hit} or nil; OS.desktopHover=desktopIndex; cursor.set(shape)
        if OS.hover and OS.hover.win then mark(OS.hover.win) end
        if oldDesktop~=desktopIndex then OS.desktopDirty=true; invalidate(workspace()) end
    end
    local function invokeButton(win,xx,yy)
        for _,b in ipairs(win.buttons or {}) do
            if inside(b,xx,yy) then
                local ok,err=pcall(b.action,xx-b.x,yy-b.y)
                if not ok then errorBox(err) end
                return true
            end
        end
        return false
    end
    local function desktopClick(x,y)
        desktopFocus()
        for _,item in ipairs(iconRects()) do if inside(item.r,x,y) then
            local double=OS.iconIndex==item.index and OS.lastIconClick and now()-OS.lastIconClick<0.45
            OS.iconIndex=item.index; OS.lastIconClick=now(); OS.desktopDirty=true; invalidate(item.r)
            if double then openApp(item.id) end
            return
        end end
    end
    local function taskClick(x,y)
        if not hitTaskbar(x,y) then return false end
        local tasks,startW,_,searchW,layout=taskRects()
        if x<startW then setMenu(not OS.menu); return true end
        if x<startW+searchW then setMenu(true); return true end
        if layout.overflow and x>=startW+searchW and x<layout.taskStart then
            OS.taskScroll=max(1,layout.first-layout.capacity); taskDirty(); return true
        end
        local rightStart=startW+searchW+layout.taskArea-layout.arrowW
        if layout.overflow and x>=rightStart and x<rightStart+layout.arrowW then
            OS.taskScroll=min(max(1,#OS.windows-layout.capacity+1),layout.first+layout.capacity); taskDirty(); return true
        end
        for _,item in ipairs(tasks) do if inside(item.r,x,y) then
            if item.win==OS.active and not item.win.minimized then minimize(item.win) else focus(item.win) end
            return true
        end end
        local _,_,statusW=taskRects()
        return x>=Driver.w-statusW
    end
    local function pointer(kind,x,y,buttonId)
        if not (finite(x) and finite(y)) then return end
        if kind=="scroll" and not finite(buttonId) then return end
        local traceTarget
        if OS.modal then traceTarget="modal"
        elseif OS.menu and insideRounded(menuBox(),START_MENU_CORNER_RADIUS,x,y) then traceTarget="start menu"
        elseif OS.drag then traceTarget="window drag"
        elseif hitTaskbar(x,y) then traceTarget="taskbar"
        else
            local target=hitWindow(x,y)
            traceTarget=target and ((y-target.y<TITLE) and "window manager" or "window:"..target.id) or "desktop"
        end
        if kind=="click" or kind=="scroll" then traceInput("pointer_"..kind,traceTarget) end
        if OS.pointer.visible then invalidate(cursorRect()) end
        OS.pointer.x,OS.pointer.y=floor(clamp(x,0,Driver.w-1)),floor(clamp(y,0,Driver.h-1)); OS.pointer.lastMove=now()
        OS.pointer.visible=kind~="exit"
        if OS.pointer.visible then updateHover(OS.pointer.x,OS.pointer.y); invalidate(cursorRect()) end
        x,y=OS.pointer.x,OS.pointer.y
        if kind=="click" or kind=="down" then OS.mouseButtons[buttonId or 1]=true
        elseif kind=="up" then OS.mouseButtons[buttonId or 1]=nil end
        if kind=="exit" then return end
        if kind=="drag" and OS.drag then
            local d=OS.drag; local w=d.win; invalidate(w)
            if d.resize then
                local right,bottom=d.right,d.bottom
                if d.left then w.x=x-d.offsetX; w.w=right-w.x end
                if d.rightEdge then w.w=d.startW+x-d.startX end
                if d.top then w.y=y-d.offsetY; w.h=bottom-w.y end
                if d.bottomEdge then w.h=d.startH+y-d.startY end
            else w.x=x-d.dx; w.y=y-d.dy end
            fit(w)
            -- The old rectangle was invalidated before changing geometry;
            -- mark again so the compositor also redraws the new rectangle.
            mark(w)
            cursor.set(d.resize and resizeShape(d) or "move"); return
        end
        if kind=="up" then
            if OS.drag then snapWindow(OS.drag.win); mark(OS.drag.win); taskDirty(); OS.drag=nil end
            return
        end
        if OS.modal then
            if kind=="click" and buttonId==1 then
                local m=OS.modal; local r=m.rect or dialogBox()
                for i,b in ipairs(m.hits or {}) do if inside(b,x-r.x,y-r.y) then dismiss(m.buttons[i]); break end end
            end
            return
        end
        if kind~="click" and kind~="scroll" then return end
        if kind=="click" and buttonId~=1 and buttonId~=2 then return end
        if kind=="scroll" then
            if OS.menu then
                OS.menuIndex=clamp(OS.menuIndex+(buttonId>0 and -2 or 2),1,menuCount()); overlayDirty(); return
            end
            local w=hitWindow(x,y)
            if w then focus(w); appCall(w,"onMouse",kind,x-w.x-1,y-w.y-TITLE,buttonId) elseif y<TOP then changeDesktopPage(buttonId>0 and -1 or 1) end
            return
        end
        if buttonId==2 then
            local w=hitWindow(x,y)
            if not w and y>=TOP and y<Driver.h-TASK then
                for _,item in ipairs(iconRects()) do if inside(item.r,x,y) then
                    OS.iconIndex=item.index; OS.context={x=x,y=y,id=item.id}; OS.menu=false; overlayDirty(); return
                end end
            end
            return
        end
        if OS.context then
            local r=OS.context.rect
            if r and inside(r,x,y) then
                local row=floor((y-r.y)/21); local id=OS.context.id; OS.context=nil; overlayDirty()
                if row==0 then openApp(id) elseif row==1 then allDirty() end
            else OS.context=nil; overlayDirty() end
            return
        end
        if OS.menu then
            local r=menuBox(); local search=box(r.x+10,r.y+34,r.w-20,20)
            if insideRounded(r,START_MENU_CORNER_RADIUS,x,y) then
                if not OS.powerMenu and inside(search,x,y) then return end
                local count=menuCount(); local listTop=menuListY+menuHeaderHeight(OS)
                if y-r.y>=listTop then
                    local index=menuIndexAt(OS,y)
                    if index>=1 and index<=count then
                        OS.menuIndex=index; activateMenuSelection()
                    end
                end
                return
            end
            setMenu(false)
        end
        if y>=Driver.h-TASK then if taskClick(x,y) then return end end
        local w=hitWindow(x,y)
        if w then
            focus(w); local xx,yy=x-w.x,y-w.y
            if yy<TITLE then
                if xx>=w.w-22 then closeWindow(w)
                elseif w.w>=154 and xx>=w.w-44 then maximize(w)
                elseif w.w>=154 and xx>=w.w-66 then minimize(w)
                else
                    local double=w.lastTitleClick and now()-w.lastTitleClick<0.45; w.lastTitleClick=now()
                    if double then maximize(w) else OS.drag={win=w,dx=xx,dy=yy} end
                end
            else
                local edge=resizeEdges(w,xx,yy)
                if edge.left or edge.right or edge.top or edge.bottom then
                    OS.drag={win=w,resize=true,startX=x,startY=y,startW=w.w,startH=w.h,right=w.x+w.w,bottom=w.y+w.h,
                        offsetX=x-w.x,offsetY=y-w.y,left=edge.left,top=edge.top,rightEdge=edge.right,bottomEdge=edge.bottom}
                else
                    local cx,cy=xx-1,yy-TITLE
                    if not invokeButton(w,cx,cy) then appCall(w,"onMouse",kind,cx,cy,buttonId) end
                end
            end
            return
        end
        desktopClick(x,y)
    end
    local function dispatchSystemEvent(e)
        local name=e[1]
        -- Focused input is routed below; broadcasting it would mix app state.
        if name=="timer" or name=="terminate" or name=="key" or name=="key_up" or
            name=="char" or name=="paste" or name=="monitor_touch" or
            name:sub(1,6)=="mouse_" or name:sub(1,12)=="tm_keyboard_" or
            (name:sub(1,11)=="tm_monitor_" and name~="tm_monitor_resize") then return end
        for i=#OS.windows,1,-1 do
            local win=OS.windows[i]
            if win and not win.closed and not win.minimized and not win.crash and win.app and type(win.app.onSystemEvent)=="function" then
                appCall(win,"onSystemEvent",unpack(e))
            end
        end
    end
    local function handleEvent(e)
        if type(e)~="table" or type(e[1])~="string" then return false end
        local name=e[1]
        if name=="timer" then
            if E.consumeIgnoredTimer then E.consumeIgnoredTimer(e[2]) end
            return
        end
        if name=="shutdown" or name=="reboot" then
            if name=="shutdown" then requestShutdown() else requestRestart() end
            return
        end
        if name:sub(1,12)=="tm_keyboard_" then
            if type(e[2])~="string" or not devices.keyboards or not devices.keyboards[e[2]] then return end
            local keyboardEvent=name:sub(13)
            if keyboardEvent=="shutdown" or keyboardEvent=="reboot" then
                if keyboardEvent=="shutdown" then requestShutdown() else requestRestart() end
                return
            end
        end
        if name=="http_success" or name=="http_failure" then
            local serviceHandled=E.dispatchHttpEvent and E.dispatchHttpEvent(e)
            if not serviceHandled then
                local api=context and context.api
                if api and type(api.handleHttp)=="function" then
                    local ok,result=pcall(api.handleHttp,e[2],e[3])
                    if not ok then logLine("ERROR","HTTP service callback failed: "..tostring(result)) end
                end
                -- Legacy and unclaimed events have no owned response reader.
                if E.closeHttpHandle then E.closeHttpHandle(name=="http_success" and e[3] or e[4]) end
            end
            return
        end
        dispatchSystemEvent(e)
        if name:sub(1,12)=="tm_keyboard_" then
            if type(e[2])~="string" or not devices.keyboards or not devices.keyboards[e[2]] then return end
            name=name:sub(13); table.remove(e,2)
        end
        if name=="terminate" then OS.running=false
        elseif name=="key" then keyInput(e[2])
        elseif name=="key_up" then if finite(e[2]) then OS.held[e[2]]=nil end
        elseif name=="char" or name=="paste" then charInput(e[2])
        elseif name=="portable_disconnect" then OS.held={}; OS.mouseButtons={}; OS.drag=nil; OS.hover=nil
        elseif name=="peripheral" or name=="peripheral_attach" or name=="peripheral_detach" then
            notify(name=="peripheral_detach" and "Peripheral detached" or "Peripheral attached",P.warning); rescan()
        elseif name=="monitor_resize" or name=="tm_monitor_resize" then rescan()
        elseif name:sub(1,11)=="tm_monitor_" then
            local offset=0; if type(e[2])=="string" then if e[2]~=devices.gpuName then return end; offset=1 end
            local x,y,b=e[2+offset],e[3+offset],e[4+offset]; if finite(x) and finite(y) then
                local kind=name:sub(12):gsub("^mouse_",""); if kind=="touch" then kind="click"; b=1 end
                if kind=="exit" then pointer(kind,OS.pointer.x,OS.pointer.y,b or 1)
                else
                    local logicalX,logicalY=Driver.toLogical(x-1,y-1)
                    if logicalX then pointer(kind,logicalX,logicalY,b or 1)
                    else pointer("exit",OS.pointer.x,OS.pointer.y) end
                end
            end
        elseif name=="monitor_touch" then
            if devices.gpuName and e[2]~=devices.gpuName then return end
            if finite(e[3]) and finite(e[4]) then pointer("click",e[3]-1,e[4]-1,1) end
        elseif name=="mouse_move" or name=="mouse_drag" or name=="mouse_click" or name=="mouse_up" or name=="mouse_scroll" then
            local kind=name:gsub("^mouse_",""); local b,x,y
            if kind=="move" then x,y,b=e[2],e[3],1 else b,x,y=e[2],e[3],e[4] end
            if finite(x) and finite(y) then pointer(kind,x-1,y-1,b or 1) end
        end
    end
    E.modalKey=modalKey; E.keyInput=keyInput; E.charInput=charInput; E.handleEvent=handleEvent; E.pointer=pointer
end

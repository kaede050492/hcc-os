return function(E)
 local env=setmetatable({},{__index=E})
 local _ENV=env
local function modalKey(k)
    local m=OS.modal
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
    elseif k==keys.left or k==keys.right then m.index=(m.index-1+(k==keys.left and -1 or 1))%#m.buttons+1; overlayDirty() end
end
local function keyInput(k)
    OS.held[k]=true
    if OS.modal then modalKey(k); return end
    local ctrl=OS.held[keys.leftCtrl] or OS.held[keys.rightCtrl]
    local alt=OS.held[keys.leftAlt] or OS.held[keys.rightAlt]
    if k==keys.f1 then setMenu(not OS.menu); return end
    if OS.menu then
        if k==keys.escape then setMenu(false)
        elseif k==keys.up then OS.menuIndex=(OS.menuIndex-2)%(#OS.order+1)+1; overlayDirty()
        elseif k==keys.down then OS.menuIndex=OS.menuIndex%(#OS.order+1)+1; overlayDirty()
        elseif k==keys.enter then local i=OS.menuIndex; setMenu(false); if i>#OS.order then requestExit() else openApp(OS.order[i]) end end
        return
    end
    if ctrl and k==keys.q then requestExit(); return end
    if ctrl and k==keys.w then closeWindow(OS.active); return end
    if ctrl and k==keys.tab then
        if #OS.windows>0 then focus(OS.windows[1]) end; return
    end
    if k==keys.f5 and not gpuAvailable() then rescan(); return end
    if k==keys.f6 then tileWindows(); return end
    if k==keys.f5 and not OS.active then rescan(); return end
    local w=OS.active
    if w then
        if k==keys.f2 then invalidate(w); w.minimized=true; OS.active=nil; taskDirty(); OS.desktopDirty=true; invalidate(box(0,0,Driver.w,Driver.h-TASK)); return end
        if k==keys.f3 then maximize(w); return end
        if alt and (k==keys.left or k==keys.right or k==keys.up or k==keys.down) then
            invalidate(w); w.restore=nil
            if k==keys.left then w.x=w.x-8 elseif k==keys.right then w.x=w.x+8 elseif k==keys.up then w.y=w.y-8 else w.y=w.y+8 end
            fit(w); mark(w); return
        end
        if k==keys.escape then desktopFocus(); return end
        appCall(w,"onKey",k)
    else
        if k==keys.enter then openApp(OS.order[OS.iconIndex])
        elseif k==keys.t then openApp("server")
        elseif k==keys.c then openApp("calendar")
        elseif k==keys.e then openApp("clock")
        elseif k==keys.up or k==keys.left then OS.iconIndex=(OS.iconIndex-2)%#OS.order+1; OS.desktopDirty=true; invalidate(screen())
        elseif k==keys.down or k==keys.right or k==keys.tab then OS.iconIndex=OS.iconIndex%#OS.order+1; OS.desktopDirty=true; invalidate(screen()) end
    end
end
local function charInput(s)
    if type(s)~="string" then return end
    if OS.modal then
        local m=OS.modal
        if m.input~=nil then
            s=s:gsub("[^\010\013\032-\126]","?")
            if #m.input+#s>8192 then return end
            m.input=m.input:sub(1,m.pos)..s..m.input:sub(m.pos+1); m.pos=m.pos+#s; m.index=1; overlayDirty()
        end
    elseif not OS.menu and OS.active and not (OS.held[keys.leftCtrl] or OS.held[keys.rightCtrl] or OS.held[keys.leftAlt] or OS.held[keys.rightAlt]) then
        appCall(OS.active,"onChar",s)
    end
end
local function handleEvent(e)
    local name=e[1]
    if (name=="http_success" or name=="http_failure") and HCCV14 and type(HCCV14.handleHttp)=="function" then
        local handled=HCCV14.handleHttp(e[2],e[3])
        if handled then return end
    end
    local prefixed=false
    if name:sub(1,12)=="tm_keyboard_" then
        if not devices.keyboards[e[2]] then return end
        name=name:sub(13); table.remove(e,2); e[1]=name; prefixed=true
    end
    if name=="http_success" or name=="http_failure" then
        for _,w in ipairs(OS.windows) do
            if w.id=="web" and not w.minimized and not w.crash then
                if name=="http_success" then appCall(w,"onHttpSuccess",e[2],e[3]) else appCall(w,"onHttpFailure",e[2],e[3]) end
                break
            end
        end
    elseif name=="terminate" then OS.running=false
    elseif name=="key" then keyInput(e[2])
    elseif name=="key_up" then OS.held[e[2]]=nil
    elseif name=="char" or name=="paste" then charInput(e[2])
    elseif name=="portable_disconnect" then OS.held={}; OS.mouseButtons={}; OS.drag=nil; OS.hover=nil
    elseif name=="peripheral" or name=="peripheral_attach" or name=="peripheral_detach" then
        notify(name=="peripheral_detach" and "Peripheral detached" or "Peripheral attached",P.warning); rescan()
    elseif name=="monitor_resize" or name=="tm_monitor_resize" then rescan()
    elseif name:sub(1,11)=="tm_monitor_" then
        local offset=0
        -- 1.3.1 prefixes attachment name; old releases sent x,y directly.
        if type(e[2])=="string" then if e[2]~=devices.gpuName then return end; offset=1 end
        local x,y,b=e[2+offset],e[3+offset],e[4+offset]
        if not finite(x) or not finite(y) then return end
        local kind=name:sub(12):gsub("^mouse_","")
        if kind=="touch" then kind="click"; b=1 end
        pointer(kind,x-1,y-1,b or 1)
    elseif name=="mouse_move" or name=="mouse_drag" or name=="mouse_click" or name=="mouse_up" or name=="mouse_scroll" then
        -- Some portable keyboards forward unprefixed mouse events.  They use
        -- monitor-style x,y,button arguments after the event name.
        local kind=name:gsub("^mouse_",""); if kind=="scroll" then kind="scroll" end
        local x,y,b
        if prefixed then x,y,b=e[2],e[3],e[4] else b,x,y=e[2],e[3],e[4] end
        if finite(x) and finite(y) then pointer(kind,x-1,y-1,b or 1) end
    end
end
E.modalKey=modalKey; E.keyInput=keyInput; E.charInput=charInput; E.handleEvent=handleEvent

end

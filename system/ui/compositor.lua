-- HCC OS v1.5 retained-mode compositor.

return function(E)
    local env=setmetatable({},{__index=E})
    local _ENV=env
    local function buildWindow(win)
        local list={}; local c=canvas(list,win.x,win.y,win.w,win.h)
        local active=OS.active==win
        c:filledRectangle(3,3,win.w,win.h,P.desktopBackground)
        c:clear(P.windowBackground)
        local titleColor=active and (P.titlebarActive or P.accent) or (P.titlebarInactive or P.panelBackground)
        c:filledRectangle(0,0,win.w,TITLE,titleColor)
        c:line(0,0,win.w-1,0,active and P.accent or P.border)
        c:line(0,win.h-1,win.w-1,win.h-1,P.border)
        c:line(0,0,0,win.h-1,active and P.accent or P.border)
        c:line(win.w-1,0,win.w-1,win.h-1,active and P.accent or P.border)
        local titleX=7
        if win.w>=118 then drawAppIcon(c,win.app,7,4,16,win.crash and "error" or (active and "selected" or "normal")); titleX=28 end
        local controls=win.w>=154 and 66 or 48
        c:clipping(titleX,7,max(10,win.w-titleX-controls-4),10):text(0,0,shortText(win.name,28),P.textPrimary)
        local controlY=4; local controlW=22
        c:filledRectangle(win.w-controls,1,controls-1,TITLE-2,titleColor)
        if win.w>=154 then drawControlIcon(c,win.w-62,controlY,15,"minimize",P.textPrimary) end
        drawControlIcon(c,win.w-40,controlY,15,win.restore and "restore" or "maximize",P.textPrimary)
        drawControlIcon(c,win.w-18,controlY,15,"close",P.textPrimary)
        win.buttons={}; local client=c:clipping(1,TITLE,win.w-2,max(1,win.h-TITLE-2))
        if not win.crash then
            local prefix=#list; appCall(win,"draw",client)
            if win.crash then for i=#list,prefix+1,-1 do list[i]=nil end end
        end
        if win.crash then client:paragraph(8,8,"Application error: "..win.crash,P.error,client.w-16,5) end
        c:line(win.w-8,win.h-4,win.w-4,win.h-8,P.border)
        win.commands=list; win.dirty=false
    end

    local function buildOverlay()
        local list={}; local c=canvas(list,0,0,Driver.w,Driver.h)
        if OS.menu then
            local r=menuBox(); local m=c:clipping(r.x,r.y,r.w,r.h)
            m:clear(P.menuBackground or P.windowBackground); m:rectangle(0,0,r.w,r.h,P.border)
            m:filledRectangle(1,1,r.w-2,31,P.menuHeader or P.panelBackground)
            drawControlIcon(m,10,9,14,"windows",P.accent); m:text(31,10,"HCC OS",P.textPrimary)
            m:filledRectangle(10,34,r.w-20,20,P.inputBackground or P.panelBackground)
            drawControlIcon(m,16,38,12,"search",P.textSecondary); m:text(35,40,"Type to search",P.textSecondary)
            local visible=max(1,floor((r.h-menuListY-6)/menuRowH)); OS.menuTop=clamp(OS.menuIndex-visible+1,1,max(1,#OS.order+1-visible))
            for i=OS.menuTop,min(#OS.order+1,OS.menuTop+visible-1) do
                local y=menuListY+(i-OS.menuTop)*menuRowH; local selected=i==OS.menuIndex
                if selected then m:filledRectangle(6,y-1,r.w-12,21,P.menuSelection or P.panelBackground) end
                if i<=#OS.order then
                    local def=OS.registry[OS.order[i]]; local failed=false; local running=false
                    for _,w in ipairs(OS.windows) do if w.id==OS.order[i] and w.crash then failed=true elseif w.id==OS.order[i] and not w.minimized then running=true end end
                    local state=failed and "error" or (selected and "selected" or (running and "running" or "normal"))
                    drawAppIcon(m,def,8,y,18,state)
                    m:clipping(33,y+5,max(10,r.w-42),10):text(0,0,shortText(def.name,28),P.textPrimary)
                else
                    drawControlIcon(m,10,y+2,16,"close",P.warning); m:text(34,y+5,"Exit HCC OS",P.warning)
                end
            end
        end
        if OS.context then
            local cw=min(178,Driver.w-8); local ch=64; local cx=clamp(OS.context.x,4,Driver.w-cw-4); local cy=clamp(OS.context.y,TOP,Driver.h-TASK-ch-4)
            local q=c:clipping(cx,cy,cw,ch); OS.context.rect=box(cx,cy,cw,ch); q:clear(P.windowBackground); q:rectangle(0,0,cw,ch,P.accent)
            q:text(9,7,"OPEN",P.textPrimary); q:text(9,28,"REFRESH DESKTOP",P.textPrimary); q:text(9,49,"CANCEL",P.warning)
        end
        if OS.toast then
            local width=min(300,Driver.w-12); local r=box(Driver.w-width-6,TOP+5,width,40); local t=c:clipping(r.x,r.y,r.w,r.h)
            t:clear(P.panelBackground); t:rectangle(0,0,r.w,r.h,OS.toast.color); t:paragraph(8,7,OS.toast.message,P.textPrimary,width-16,2)
        end
        if OS.modal then
            local modal=OS.modal; local r=dialogBox(); modal.rect=r; local d=c:clipping(r.x,r.y,r.w,r.h)
            d:clear(P.windowBackground); d:rectangle(0,0,r.w,r.h,P.accent)
            d:filledRectangle(1,1,r.w-2,23,P.panelBackground); d:text(9,8,modal.title,P.accent)
            d:paragraph(9,32,modal.message,P.textPrimary,r.w-18,modal.input~=nil and 2 or 6)
            if modal.input~=nil then
                local iy=r.h-58; d:filledRectangle(8,iy,r.w-16,22,P.panelBackground); d:rectangle(8,iy,r.w-16,22,P.accent)
                local value=modal.input:gsub("[\r\n]"," "); local first=1
                while Driver.measure(value:sub(first,modal.pos))+2>r.w-28 and first<=modal.pos do first=first+1 end
                local field=d:clipping(12,iy+6,r.w-24,10); field:text(0,0,value:sub(first),P.textPrimary)
                field:line(Driver.measure(value:sub(first,modal.pos)),0,Driver.measure(value:sub(first,modal.pos)),8,P.accent)
            end
            modal.hits={}; local bw=min(84,floor((r.w-20)/max(1,#modal.buttons)))
            for i,label in ipairs(modal.buttons) do
                local b=box(r.w-10-(#modal.buttons-i+1)*bw,r.h-29,bw-5,20)
                d:filledRectangle(b.x,b.y,b.w,b.h,i==modal.index and P.border or P.panelBackground)
                d:text(b.x+6,b.y+6,label,P.textPrimary); modal.hits[i]=b
            end
        end
        OS.overlay=list; OS.overlayDirty=false
    end
    local function layers()
        local result={OS.desktop}
        for _,w in ipairs(OS.windows) do if not w.minimized then result[#result+1]=w.commands end end
        result[#result+1]=OS.task; result[#result+1]=OS.overlay
        return result
    end
    local function cursorRect() return cursorBounds(OS.pointer) end
    local function render()
        if not gpuAvailable() then return end
        if OS.desktopDirty then buildDesktop() end
        if OS.taskDirty then buildTask() end
        for _,w in ipairs(OS.windows) do if w.dirty and not w.minimized then buildWindow(w) end end
        if OS.overlayDirty then buildOverlay() end
        if #OS.damage==0 then return end
        local scene=layers(); local pending=OS.damage; OS.damage={}; local damage={}
        while #pending>0 do
            local r=table.remove(pending)
            local changed=true
            while changed do
                changed=false
                for _,layer in ipairs(scene) do for _,cmd in ipairs(layer or {}) do
                    if (cmd.kind=="text" or cmd.kind=="native_image") and intersect(r,cmd.bounds) then
                        local u=union(r,cmd.bounds)
                        if u.x~=r.x or u.y~=r.y or u.w~=r.w or u.h~=r.h then r=u; changed=true end
                    end
                end end
                for i=#pending,1,-1 do if intersect(r,pending[i]) then r=union(r,table.remove(pending,i)); changed=true end end
                for i=#damage,1,-1 do if intersect(r,damage[i]) then r=union(r,table.remove(damage,i)); changed=true end end
            end
            damage[#damage+1]=r
        end
        for _,r in ipairs(damage) do
            for _,layer in ipairs(scene) do for _,cmd in ipairs(layer or {}) do
                if intersect(r,cmd.bounds) then
                    if cmd.kind=="fill" then local b=cmd.bounds; Driver.filledRectangle(b.x,b.y,b.w,b.h,cmd.color,r)
                    elseif cmd.kind=="line" then Driver.line(cmd.a,cmd.b,cmd.c,cmd.d,cmd.color,r)
                    elseif cmd.kind=="text" then Driver.text(cmd)
                    elseif cmd.kind=="native_image" then Driver.drawNativeImage(cmd.bounds.x,cmd.bounds.y,cmd.record,r) end
                end
            end end
            if OS.pointer.visible and intersect(r,cursorRect()) then drawCursor(OS.pointer,r) end
        end
        Driver.sync(); OS.renderCount=OS.renderCount+1
    end
    E.buildWindow=buildWindow; E.buildOverlay=buildOverlay; E.layers=layers; E.cursorRect=cursorRect; E.render=render
end

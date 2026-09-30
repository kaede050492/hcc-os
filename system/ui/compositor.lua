-- HCC OS v1.5 retained-mode compositor.

return function(E)
    local env=setmetatable({},{__index=E})
    local _ENV=env
    local function buildWindow(win)
        local list={}; local c=canvas(list,win.x,win.y,win.w,win.h)
        local active=OS.active==win
        c=c:roundedClipping(0,0,win.w,win.h,WINDOW_CORNER_RADIUS)
        c:clear(active and P.accent or P.border)
        c:roundedClipping(1,1,win.w-2,win.h-2,max(0,WINDOW_CORNER_RADIUS-1)):clear(P.windowBackground)
        local titleColor=active and (P.titlebarActive or P.accent) or (P.titlebarInactive or P.panelBackground)
        c:filledRectangle(1,1,win.w-2,TITLE-2,titleColor)
        local titleX=7
        if win.w>=118 then drawAppIcon(c,win.app,7,4,16,win.crash and "error" or (active and "selected" or "normal")); titleX=28 end
        local controls=win.w>=154 and 66 or 48
        c:clipping(titleX,7,max(10,win.w-titleX-controls-4),10):text(0,0,shortText(win.name,28),P.textPrimary)
        local controlY=4; local controlW=22
        c:filledRectangle(win.w-controls+1,1,controls-2,TITLE-2,titleColor)
        if win.w>=154 then drawControlIcon(c,win.w-62,controlY,15,"minimize",P.textPrimary) end
        drawControlIcon(c,win.w-40,controlY,15,win.restore and "restore" or "maximize",P.textPrimary)
        drawControlIcon(c,win.w-18,controlY,15,"close",P.textPrimary)
        win.buttons={}; local client=c:clipping(1,TITLE,win.w-2,max(1,win.h-TITLE-2))
        if not win.crash then
            local prefix=#list; appCall(win,"draw",client)
            if win.crash then for i=#list,prefix+1,-1 do list[i]=nil end end
            if not win.crash then
                for i=prefix+1,#list do
                    if list[i].kind=="native_image" then list[i].owner=win end
                end
            end
        end
        if win.crash then client:paragraph(8,8,"Application error: "..win.crash,P.error,client.w-16,5) end
        c:line(win.w-8,win.h-4,win.w-4,win.h-8,P.border)
        win.commands=list; win.dirty=false
    end

    local function buildOverlay()
        local list={}; local c=canvas(list,0,0,Driver.w,Driver.h)
        if OS.menu then
            local r=menuBox(); local m=c:roundedClipping(r.x,r.y,r.w,r.h,START_MENU_CORNER_RADIUS)
            m:clear(P.border)
            m=m:roundedClipping(1,1,r.w-2,r.h-2,max(0,START_MENU_CORNER_RADIUS-1))
            m:clear(P.menuBackground or P.windowBackground)
            m:filledRectangle(1,1,r.w-2,31,P.menuHeader or P.panelBackground)
            drawControlIcon(m,10,9,14,"menu",P.accent); m:text(31,10,"HCC OS",P.textPrimary)
            m:filledRectangle(10,34,r.w-20,20,P.inputBackground or P.panelBackground)
            local query=OS.menuQuery or ""
            if OS.powerMenu then
                drawControlIcon(m,16,38,12,"power",P.textSecondary)
                m:text(35,40,"POWER OPTIONS",P.textPrimary)
            else
                drawControlIcon(m,16,38,12,"search",P.textSecondary)
                local prompt=query=="" and "Search apps" or shortText(query,max(1,floor((r.w-54)/6)))
                m:clipping(35,38,max(1,r.w-45),12):text(0,0,prompt,query=="" and P.textSecondary or P.textPrimary)
            end
            local entries=menuEntries(); local count=menuCount(); local headerHeight=menuHeaderHeight(OS)
            local visible=max(1,floor((r.h-menuListY-headerHeight-6)/menuRowH)); OS.menuTop=clamp(OS.menuIndex-visible+1,1,max(1,count-visible))
            if OS.menuRecentCount>0 then m:text(9,menuListY+1,"RECENT",P.accent) end
            for i=OS.menuTop,min(count,OS.menuTop+visible-1) do
                local y=menuRowY(OS,i); local selected=i==OS.menuIndex
                if selected then m:filledRectangle(6,y-1,r.w-12,21,P.menuSelection or P.panelBackground) end
                if OS.powerMenu then
                    local id=entries[i]
                    local labels={['@restart']={"restart","Restart computer",P.textPrimary},
                        ['@shutdown']={"power","Shut down computer",P.warning},
                        ['@exit']={"close","Exit HCC OS",P.warning},
                        ['@desktop']={"desktop","Show desktop",P.textPrimary},
                        ['@back']={"back","Back to apps",P.textSecondary}}
                    local item=labels[id]
                    if item then drawControlIcon(m,10,y+2,16,item[1],selected and P.accent or item[3]); m:text(34,y+5,item[2],item[3]) end
                elseif i<=#entries then
                    local id=entries[i]; local def=OS.registry[id]; local failed=false; local running=false
                    for _,w in ipairs(OS.windows) do if w.id==id and w.crash then failed=true elseif w.id==id and not w.minimized then running=true end end
                    local available=true
                    if def and type(appAvailable)=="function" then available=appAvailable(def) end
                    local state=failed and "error" or (not available and "offline" or
                        (selected and "selected" or (running and "running" or "normal")))
                    drawAppIcon(m,def,8,y,18,state)
                    local labelWidth=available and max(10,r.w-42) or max(10,r.w-106)
                    m:clipping(33,y+5,labelWidth,10):text(0,0,shortText(def.name,28),available and P.textPrimary or P.textSecondary)
                    if not available then m:text(r.w-54,y+5,"OFFLINE",P.warning) end
                    if OS.menuRecentCount>0 and i==OS.menuRecentCount and i<count then
                        m:line(8,y+menuRowH-1,r.w-8,y+menuRowH-1,P.border)
                    end
                elseif #entries==0 and query~="" and i==1 then
                    m:text(12,y+5,"No apps found",P.textSecondary)
                else
                    drawControlIcon(m,10,y+2,16,"power",selected and P.accent or P.textSecondary)
                    m:text(34,y+5,"Power options",selected and P.textPrimary or P.textSecondary)
                end
            end
        end
        if OS.context then
            local r=contextBox(OS.context.x,OS.context.y); local q=c:clipping(r.x,r.y,r.w,r.h); OS.context.rect=r
            q:clear(P.windowBackground); q:rectangle(0,0,r.w,r.h,P.accent)
            q:text(9,7,"OPEN",P.textPrimary); q:text(9,28,"REFRESH DESKTOP",P.textPrimary); q:text(9,49,"CANCEL",P.warning)
        end
        if OS.toast then
            local r=toastBox(); local t=c:clipping(r.x,r.y,r.w,r.h)
            t:clear(P.panelBackground); t:rectangle(0,0,r.w,r.h,OS.toast.color); t:paragraph(8,7,OS.toast.message,P.textPrimary,r.w-16,2)
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
        local nativeFallbacks={}
        for _,r in ipairs(damage) do
            for _,layer in ipairs(scene) do for _,cmd in ipairs(layer or {}) do
                if intersect(r,cmd.bounds) then
                    if cmd.kind=="fill" then local b=cmd.bounds; Driver.filledRectangle(b.x,b.y,b.w,b.h,cmd.color,r)
                    elseif cmd.kind=="line" then Driver.line(cmd.a,cmd.b,cmd.c,cmd.d,cmd.color,r)
                    elseif cmd.kind=="text" then Driver.text(cmd)
                    elseif cmd.kind=="native_image" and not cmd.record.drawFailureReported then
                        local drawn,reason=Driver.drawNativeImage(cmd.bounds.x,cmd.bounds.y,cmd.record,r,cmd.clip)
                        if not drawn and reason~="GPU unavailable" then
                            cmd.record.drawFailureReported=true; cmd.record.drawFailure=reason
                            if cmd.owner then nativeFallbacks[#nativeFallbacks+1]={owner=cmd.owner,record=cmd.record,reason=reason} end
                        end
                    end
                end
            end end
            if OS.pointer.visible and intersect(r,cursorRect()) then drawCursor(OS.pointer,r) end
        end
        Driver.sync(); OS.renderCount=OS.renderCount+1
        for _,failure in ipairs(nativeFallbacks) do
            appCall(failure.owner,"onNativeImageFailure",failure.record,failure.reason)
        end
    end
    E.buildWindow=buildWindow; E.buildOverlay=buildOverlay; E.layers=layers; E.cursorRect=cursorRect; E.render=render
end

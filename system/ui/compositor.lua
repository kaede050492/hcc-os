return function(E)
 local env=setmetatable({},{__index=E})
 local _ENV=env
local function buildWindow(win)
    local list={}; local c=canvas(list,win.x,win.y,win.w,win.h)
    c:clear(P.windowBackground)
    c:filledRectangle(0,0,win.w,TITLE,OS.active==win and P.panelBackground or P.windowBackground)
    c:rectangle(0,0,win.w,win.h,OS.active==win and P.accent or P.border)
    local titleX=6
    if win.w>=110 then drawAppIcon(c,win.app,6,1,14,win.crash and "error" or (OS.active==win and "selected" or "normal")); titleX=24 end
    c:clipping(titleX,5,max(10,win.w-titleX-66),10):text(0,0,win.name,OS.active==win and P.textPrimary or P.textSecondary)
    c:text(win.w-51,5,"_",P.textSecondary); c:text(win.w-34,5,"+",P.accent); c:text(win.w-17,5,"X",P.error)
    win.buttons={}
    local client=c:clipping(1,TITLE,win.w-2,win.h-TITLE-1)
    if not win.crash then
        local prefix=#list; appCall(win,"draw",client)
        if win.crash then for i=#list,prefix+1,-1 do list[i]=nil end end
    end
    if win.crash then client:paragraph(8,8,"Application error: "..win.crash,P.error,client.w-16,12) end
    c:line(win.w-7,win.h-3,win.w-3,win.h-7,P.border)
    win.commands=list; win.dirty=false
end
local function buildOverlay()
    local list={}; local c=canvas(list,0,0,Driver.w,Driver.h)
    if OS.menu then
        local r=menuBox(); local m=c:clipping(r.x,r.y,r.w,r.h)
        m:clear(P.windowBackground); m:rectangle(0,0,r.w,r.h,P.accent)
        local visible=max(1,floor((r.h-4)/20))
        OS.menuTop=clamp(OS.menuIndex-visible+1,1,max(1,#OS.order+2-visible))
        for i=OS.menuTop,min(#OS.order+1,OS.menuTop+visible-1) do
            local y=3+(i-OS.menuTop)*20
            if i==OS.menuIndex then m:filledRectangle(2,y,r.w-4,19,P.panelBackground) end
            if i<=#OS.order then
                local def=OS.registry[OS.order[i]]; local state=i==OS.menuIndex and "selected" or "normal"; local bad=false; local live=false
                for _,w in ipairs(OS.windows) do if w.id==OS.order[i] and w.crash then bad=true elseif w.id==OS.order[i] and not w.minimized then live=true end end
                state=bad and "error" or (i==OS.menuIndex and "selected" or (live and "running" or (iconIsOffline(def.id) and "offline" or "normal"))); drawAppIcon(m,def,5,y+1,min(18,max(12,r.w-30)),state)
                m:clipping(28,y+4,max(10,r.w-32),10):text(0,0,shortText(def.name,20),P.textPrimary)
            else m:text(9,y+5,"Exit HCC OS",P.warning) end
        end
    end
    if OS.context then
        local cw=min(150,Driver.w-6); local ch=58; local cx=clamp(OS.context.x,3,Driver.w-cw-3); local cy=clamp(OS.context.y,3,Driver.h-TASK-ch-3); local q=c:clipping(cx,cy,cw,ch); OS.context.rect=box(cx,cy,cw,ch)
        q:clear(P.windowBackground); q:rectangle(0,0,cw,ch,P.accent); q:text(8,7,"OPEN",P.textPrimary); q:text(8,25,"REFRESH DESKTOP",P.textPrimary); q:text(8,43,"CANCEL",P.warning)
    end
    if OS.toast then
        local width=min(300,Driver.w-8); local r=box(Driver.w-width-4,Driver.h-TASK-47,width,41)
        local t=c:clipping(r.x,r.y,r.w,r.h)
        t:clear(P.panelBackground); t:rectangle(0,0,r.w,r.h,OS.toast.color)
        t:paragraph(7,6,OS.toast.message,P.textPrimary,width-14,2)
    end
    if OS.modal then
        local m=OS.modal; local r=dialogBox(); m.rect=r
        local d=c:clipping(r.x,r.y,r.w,r.h)
        d:clear(P.windowBackground); d:rectangle(0,0,r.w,r.h,P.accent)
        d:filledRectangle(1,1,r.w-2,19,P.panelBackground); d:text(8,6,m.title,P.accent)
        d:paragraph(8,27,m.message,P.textPrimary,r.w-16,m.input~=nil and 2 or 5)
        if m.input~=nil then
            local iy=r.h-55
            d:filledRectangle(7,iy,r.w-14,20,P.panelBackground); d:rectangle(7,iy,r.w-14,20,P.accent)
            local visible=m.input:gsub("[\r\n]"," "); local first=1
            while Driver.measure(visible:sub(first,m.pos))+2>r.w-24 and first<=m.pos do first=first+1 end
            local field=d:clipping(11,iy+5,r.w-22,10)
            field:text(0,0,visible:sub(first),P.textPrimary)
            local px=Driver.measure(visible:sub(first,m.pos)); field:line(px,0,px,8,P.accent)
        end
        m.hits={}; local bw=min(70,floor((r.w-18)/#m.buttons))
        for i,label in ipairs(m.buttons) do
            local b=box(r.w-8-(#m.buttons-i+1)*bw,r.h-26,bw-4,18)
            d:filledRectangle(b.x,b.y,b.w,b.h,i==m.index and P.border or P.panelBackground)
            d:text(b.x+6,b.y+5,label,P.textPrimary); m.hits[i]=b
        end
    end
    OS.overlay=list; OS.overlayDirty=false
    for _,cmd in ipairs(list) do invalidate(cmd.bounds) end
end
local function layers()
    local result={OS.desktop}
    for _,w in ipairs(OS.windows) do if not w.minimized then result[#result+1]=w.commands end end
    result[#result+1]=OS.task; result[#result+1]=OS.overlay
    return result
end
local function cursorRect() return box(OS.pointer.x,OS.pointer.y,9,13) end
local function render()
    if not gpuAvailable() then return end
    if OS.desktopDirty then buildDesktop() end
    if OS.taskDirty then buildTask() end
    for _,w in ipairs(OS.windows) do if w.dirty and not w.minimized then buildWindow(w) end end
    if OS.overlayDirty then buildOverlay() end
    if #OS.damage==0 then return end
    local scene=layers(); local damage=OS.damage; OS.damage={}
    -- Whole text runs must be replayed. Expand damage until all intersected
    -- text fits; this prevents trails when a cursor crosses native glyphs.
    local pending=damage; damage={}
    while #pending>0 do
        local r=table.remove(pending)
        local changed=true
        while changed do
            changed=false
            for _,list in ipairs(scene) do for _,cmd in ipairs(list) do
                if (cmd.kind=="text" or cmd.kind=="native_image") and intersect(r,cmd.bounds) then
                    local u=union(r,cmd.bounds)
                    if u.x~=r.x or u.y~=r.y or u.w~=r.w or u.h~=r.h then r=u; changed=true end
                end
            end end
            for i=#pending,1,-1 do
                if intersect(r,pending[i]) then r=union(r,table.remove(pending,i)); changed=true end
            end
            for i=#damage,1,-1 do
                if intersect(r,damage[i]) then r=union(r,table.remove(damage,i)); changed=true end
            end
        end
        damage[#damage+1]=r
    end
    for _,r in ipairs(damage) do
        for _,list in ipairs(scene) do for _,cmd in ipairs(list) do
            if intersect(r,cmd.bounds) then
                if cmd.kind=="fill" then local b=cmd.bounds; Driver.filledRectangle(b.x,b.y,b.w,b.h,cmd.color,r)
                elseif cmd.kind=="line" then Driver.line(cmd.a,cmd.b,cmd.c,cmd.d,cmd.color,r)
                elseif cmd.kind=="text" then Driver.text(cmd) end
                if cmd.kind=="native_image" then Driver.drawNativeImage(cmd.bounds.x,cmd.bounds.y,cmd.record,r) end
            end
        end end
        if OS.pointer.visible and intersect(r,cursorRect()) then
            local x,y=OS.pointer.x,OS.pointer.y
            for i=0,9 do Driver.line(x,y+i,x+floor(i/2),y+i,P.textPrimary,r) end
            Driver.line(x,y,x,y+11,0xFF000000,r); Driver.line(x,y,x+6,y+10,0xFF000000,r)
            Driver.line(x+3,y+8,x+6,y+12,P.textPrimary,r)
        end
    end
    Driver.sync(); OS.renderCount=OS.renderCount+1
end
E.buildWindow=buildWindow; E.buildOverlay=buildOverlay; E.layers=layers; E.cursorRect=cursorRect; E.render=render

end

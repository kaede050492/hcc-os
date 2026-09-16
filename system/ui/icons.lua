-- HCC OS v1.5 flat pixel icon manager.
--
-- The icon language is intentionally drawn with the primitives exposed by the
-- Tom's GPU adapter. It uses no font glyphs, so every icon stays crisp at the
-- 16, 24 and 32 pixel sizes used by the shell.

return function(E)
    local env=setmetatable({},{__index=E})
    local _ENV=env

    local ICONS={
        clock=true,calendar=true,files=true,terminal=true,server=true,network=true,
        peripherals=true,settings=true,radar=true,inventory=true,image=true,web=true,
        logs=true,performance=true,taskmgr=true,resource=true,currency=true,system=true,
        diagnostics=true,updates=true,notepad=true,default=true
    }
    local COLORS={
        clock=0xFF62C7F2,calendar=0xFFFFC857,files=0xFFFFC857,terminal=0xFF69D391,
        server=0xFF6ED4F5,network=0xFF9EB9FF,peripherals=0xFF62C7F2,
        settings=0xFFB6C4D3,radar=0xFF5BD6E6,inventory=0xFFD3B06B,
        image=0xFFB9A7FF,web=0xFF70C8FF,logs=0xFFBFC9D4,
        performance=0xFF69D391,taskmgr=0xFF7DC9F5,resource=0xFFFF9F5B,
        currency=0xFFFFD166,system=0xFF75D9FF,diagnostics=0xFF7CE0A0,
        updates=0xFF70C8FF,notepad=0xFFFFC857
    }
    local DARK=0xFF111820

    local function q(value,size) return floor(value*size/32+0.5) end
    local function rr(c,x,y,size,rx,ry,rw,rh,color)
        c:filledRectangle(x+q(rx,size),y+q(ry,size),max(1,q(rw,size)),max(1,q(rh,size)),color)
    end
    local function ro(c,x,y,size,rx,ry,rw,rh,color)
        c:rectangle(x+q(rx,size),y+q(ry,size),max(1,q(rw,size)),max(1,q(rh,size)),color)
    end
    local function rl(c,x,y,size,x1,y1,x2,y2,color)
        c:line(x+q(x1,size),y+q(y1,size),x+q(x2,size),y+q(y2,size),color)
    end
    local function iconFrame(c,x,y,size,bg,edge)
        c:filledRectangle(x,y,size,size,bg); c:rectangle(x,y,size,size,edge)
        if size>=12 then c:filledRectangle(x+1,y+1,size-2,size-2,DARK) end
    end
    local function drawClock(c,x,y,s,a)
        ro(c,x,y,s,6,5,20,20,a); rr(c,x,y,s,9,8,14,14,DARK)
        rl(c,x,y,s,16,15,16,10,a); rl(c,x,y,s,16,15,21,15,a)
        rr(c,x,y,s,15,6,2,2,a); rr(c,x,y,s,15,24,2,2,a)
    end
    local function drawCalendar(c,x,y,s,a)
        rr(c,x,y,s,5,6,22,22,a); rr(c,x,y,s,5,6,22,6,0xFF2B6F9D)
        rr(c,x,y,s,9,3,3,6,a); rr(c,x,y,s,20,3,3,6,a)
        for row=0,2 do for col=0,2 do rr(c,x,y,s,9+col*5,15+row*4,2,2,DARK) end end
    end
    local function drawFiles(c,x,y,s,a)
        rr(c,x,y,s,5,9,22,17,a); rr(c,x,y,s,7,6,9,5,a)
        rr(c,x,y,s,7,12,18,2,0xFFFFE18A); rr(c,x,y,s,8,17,15,2,0xFFE7A83F)
        ro(c,x,y,s,5,9,22,17,0xFF8D6B32)
    end
    local function drawTerminal(c,x,y,s,a)
        rr(c,x,y,s,5,6,22,20,0xFF090D12); ro(c,x,y,s,5,6,22,20,0xFF52606D)
        rl(c,x,y,s,9,13,13,17,a); rl(c,x,y,s,13,17,10,21,a); rl(c,x,y,s,17,22,23,22,0xFF4CA6C8)
    end
    local function drawServer(c,x,y,s,a)
        for row=0,2 do
            local yy=6+row*7; rr(c,x,y,s,6,yy,20,5,0xFF273442); ro(c,x,y,s,6,yy,20,5,a)
            rr(c,x,y,s,9,yy+2,2,2,a); rr(c,x,y,s,14,yy+2,7,1,0xFF6D8190)
        end
    end
    local function drawNetwork(c,x,y,s,a)
        rl(c,x,y,s,10,11,21,8,a); rl(c,x,y,s,10,11,9,22,a); rl(c,x,y,s,21,8,22,21,a)
        rr(c,x,y,s,7,8,6,6,a); rr(c,x,y,s,18,5,6,6,a); rr(c,x,y,s,19,18,6,6,a)
    end
    local function drawPeripherals(c,x,y,s,a)
        ro(c,x,y,s,8,8,16,16,a); rr(c,x,y,s,12,12,8,8,a)
        for i=0,2 do
            rr(c,x,y,s,5,10+i*5,3,2,a); rr(c,x,y,s,24,10+i*5,3,2,a)
            rr(c,x,y,s,10+i*5,5,2,3,a); rr(c,x,y,s,10+i*5,24,2,3,a)
        end
    end
    local function drawSettings(c,x,y,s,a)
        rr(c,x,y,s,14,4,4,6,a); rr(c,x,y,s,14,22,4,6,a)
        rr(c,x,y,s,4,14,6,4,a); rr(c,x,y,s,22,14,6,4,a)
        rr(c,x,y,s,8,8,16,16,a); rr(c,x,y,s,12,12,8,8,DARK)
        rr(c,x,y,s,10,10,12,12,a); rr(c,x,y,s,13,13,6,6,DARK)
    end
    local function drawRadar(c,x,y,s,a)
        ro(c,x,y,s,5,5,22,22,a); ro(c,x,y,s,9,9,14,14,a)
        rl(c,x,y,s,16,6,16,26,a); rl(c,x,y,s,6,16,26,16,a)
        rl(c,x,y,s,16,16,23,9,a); rr(c,x,y,s,14,14,4,4,a)
    end
    local function drawInventory(c,x,y,s,a)
        ro(c,x,y,s,5,5,22,22,a)
        rl(c,x,y,s,5,13,27,13,a); rl(c,x,y,s,5,20,27,20,a)
        rl(c,x,y,s,13,5,13,27,a); rl(c,x,y,s,20,5,20,27,a)
        rr(c,x,y,s,7,7,4,4,a); rr(c,x,y,s,15,15,4,4,a); rr(c,x,y,s,22,22,3,3,a)
    end
    local function drawImage(c,x,y,s,a)
        ro(c,x,y,s,5,5,22,22,a); rr(c,x,y,s,9,9,4,4,0xFFFFC857)
        rl(c,x,y,s,7,24,14,15,a); rl(c,x,y,s,14,15,19,21,a); rl(c,x,y,s,19,21,25,13,a)
    end
    local function drawWeb(c,x,y,s,a)
        ro(c,x,y,s,5,5,22,22,a); ro(c,x,y,s,10,5,12,22,a); ro(c,x,y,s,5,11,22,10,a)
        rl(c,x,y,s,5,16,27,16,a); rl(c,x,y,s,16,5,16,27,a)
    end
    local function drawDocument(c,x,y,s,a)
        rr(c,x,y,s,7,4,16,24,a); rr(c,x,y,s,18,4,5,5,DARK)
        rl(c,x,y,s,18,4,18,9,a); rl(c,x,y,s,18,9,23,9,a)
        rr(c,x,y,s,10,13,10,2,DARK); rr(c,x,y,s,10,18,13,2,DARK); rr(c,x,y,s,10,23,8,2,DARK)
    end
    local function drawGraph(c,x,y,s,a)
        ro(c,x,y,s,5,5,22,22,a); rl(c,x,y,s,8,23,8,10,a); rl(c,x,y,s,8,23,25,23,a)
        rl(c,x,y,s,9,19,13,15,a); rl(c,x,y,s,13,15,17,18,a); rl(c,x,y,s,17,18,22,10,a); rl(c,x,y,s,22,10,25,12,a)
    end
    local function drawTask(c,x,y,s,a)
        rr(c,x,y,s,5,5,22,22,a); rr(c,x,y,s,9,9,5,5,DARK); rr(c,x,y,s,18,9,5,5,DARK)
        rr(c,x,y,s,9,18,5,5,DARK); rr(c,x,y,s,18,18,5,5,DARK)
    end
    local function drawCalculator(c,x,y,s,a)
        rr(c,x,y,s,7,4,18,25,0xFF273442); ro(c,x,y,s,7,4,18,25,a)
        rr(c,x,y,s,10,7,12,5,a); for row=0,2 do for col=0,2 do rr(c,x,y,s,10+col*4,15+row*4,2,2,a) end end
    end
    local function drawSystem(c,x,y,s,a)
        rr(c,x,y,s,5,5,10,10,a); rr(c,x,y,s,17,5,10,10,a)
        rr(c,x,y,s,5,17,10,10,a); rr(c,x,y,s,17,17,10,10,a)
        rl(c,x,y,s,15,5,15,27,a); rl(c,x,y,s,5,15,27,15,a)
    end
    local function drawDiagnostics(c,x,y,s,a)
        rl(c,x,y,s,16,4,25,8,a); rl(c,x,y,s,25,8,23,23,a); rl(c,x,y,s,23,23,16,28,a)
        rl(c,x,y,s,16,28,9,23,a); rl(c,x,y,s,9,23,7,8,a); rl(c,x,y,s,7,8,16,4,a)
        rl(c,x,y,s,10,16,15,21,a); rl(c,x,y,s,15,21,23,12,a)
    end
    local function drawUpdates(c,x,y,s,a)
        rl(c,x,y,s,9,11,9,7,a); rl(c,x,y,s,9,7,14,7,a); rl(c,x,y,s,14,7,12,4,a)
        rl(c,x,y,s,23,21,23,25,a); rl(c,x,y,s,23,25,18,25,a); rl(c,x,y,s,18,25,20,28,a)
        rl(c,x,y,s,9,7,6,10,a); rl(c,x,y,s,9,7,12,10,a); rl(c,x,y,s,23,25,20,22,a); rl(c,x,y,s,23,25,26,22,a)
        ro(c,x,y,s,12,12,8,8,a)
    end
    local function drawDefault(c,x,y,s,a)
        ro(c,x,y,s,6,6,20,20,a); rr(c,x,y,s,12,12,8,8,a)
        for i=0,2 do rr(c,x,y,s,7+i*7,12,3,3,a); rr(c,x,y,s,12,7+i*7,3,3,a) end
    end

    local DRAWERS={clock=drawClock,calendar=drawCalendar,files=drawFiles,terminal=drawTerminal,
        server=drawServer,network=drawNetwork,peripherals=drawPeripherals,settings=drawSettings,
        radar=drawRadar,inventory=drawInventory,image=drawImage,web=drawWeb,logs=drawDocument,
        notepad=drawDocument,performance=drawGraph,resource=drawGraph,taskmgr=drawTask,
        currency=drawCalculator,system=drawSystem,diagnostics=drawDiagnostics,updates=drawUpdates,
        default=drawDefault}

    local function iconId(def)
        return type(def)=="table" and (def.iconId or def.id) or tostring(def or "default")
    end
    local function drawControl(c,x,y,size,kind,color)
        color=color or P.textPrimary; size=max(8,floor(tonumber(size) or 12)); local mid=floor(size/2)
        if kind=="close" then
            c:line(x+3,y+3,x+size-4,y+size-4,color); c:line(x+size-4,y+3,x+3,y+size-4,color)
        elseif kind=="maximize" then c:rectangle(x+3,y+3,size-6,size-6,color)
        elseif kind=="restore" then
            c:rectangle(x+4,y+2,size-6,size-6,color); c:line(x+2,y+4,x+2,y+size-3,color); c:line(x+2,y+size-3,x+size-5,y+size-3,color)
        elseif kind=="minimize" then c:line(x+3,y+mid,x+size-4,y+mid,color)
        elseif kind=="menu" then
            c:filledRectangle(x+2,y+3,size-4,2,color); c:filledRectangle(x+2,y+mid-1,size-4,2,color); c:filledRectangle(x+2,y+size-5,size-4,2,color)
        elseif kind=="windows" then
            local half=max(2,floor((size-5)/2)); c:filledRectangle(x+2,y+2,half,half,color); c:filledRectangle(x+3+half,y+1,half,half,color)
            c:filledRectangle(x+2,y+3+half,half,half,color); c:filledRectangle(x+3+half,y+2+half,half,half,color)
        elseif kind=="search" then
            c:rectangle(x+2,y+2,size-7,size-7,color); c:line(x+size-5,y+size-5,x+size-2,y+size-2,color)
        elseif kind=="back" then c:line(x+size-3,y+2,x+3,y+mid,color); c:line(x+3,y+mid,x+size-3,y+size-3,color)
        end
    end
    local function drawAppIcon(c,def,x,y,size,state)
        size=max(8,floor(tonumber(size) or 16)); state=tostring(state or "normal")
        local id=iconId(def); local bg=P.panelBackground; local edge=P.border; local accent=COLORS[id] or P.accent
        if state=="hover" then bg=P.windowBackground; edge=P.accent
        elseif state=="selected" or state=="running" then edge=P.accent
        elseif state=="disabled" then accent=P.border; edge=P.border
        elseif state=="error" or state=="offline" then edge=P.error; accent=P.textSecondary end
        iconFrame(c,x,y,size,bg,edge); (DRAWERS[id] or DRAWERS.default)(c,x,y,size,accent)
        if state=="running" then c:filledRectangle(x+size-5,y+2,3,3,P.success)
        elseif state=="error" or state=="offline" then c:filledRectangle(x+size-5,y+2,3,3,P.error) end
    end

    local Manager={}
    function Manager.draw(c,id,x,y,size,state)
        return drawAppIcon(c,type(id)=="table" and id or {id=tostring(id),iconId=tostring(id)},x,y,size,state)
    end
    -- Keep the public order consistent with every caller: canvas, x, y,
    -- size, kind, color. Invalid sizes fall back safely inside drawControl.
    function Manager.drawControl(c,x,y,size,kind,color) return drawControl(c,x,y,size,kind,color) end
    function Manager.app(c,def,x,y,size,state) return drawAppIcon(c,def,x,y,size,state) end

    E.ICON_REGISTRY=ICONS; E.ICON_ACCENTS=COLORS; E.IconManager=Manager; E.icons=Manager
    E.drawAppIcon=Manager.app; E.drawControlIcon=Manager.drawControl
end

-- HCC OS v1.5 high definition pixel cursor manager.
-- Shapes use explicit dimensions and hotspots so damage tracking and input
-- coordinates remain aligned with the visible pointer.

return function(E)
    local env=setmetatable({},{__index=E})
    local _ENV=env
    local SHAPES={
        arrow={w=16,h=24,hotX=0,hotY=0}, hand={w=18,h=22,hotX=5,hotY=2},
        text={w=16,h=24,hotX=8,hotY=12}, busy={w=18,h=18,hotX=9,hotY=9},
        resize_ns={w=16,h=24,hotX=8,hotY=12}, resize_ew={w=24,h=16,hotX=12,hotY=8},
        resize_nwse={w=20,h=20,hotX=10,hotY=10}, resize_nesw={w=20,h=20,hotX=10,hotY=10},
        forbidden={w=20,h=20,hotX=10,hotY=10}, move={w=18,h=18,hotX=9,hotY=9}
    }
    local ALIASES={resize="resize_nwse",arrow="arrow",hand="hand",text="text",busy="busy",move="move"}
    local BLACK=0xFF05080B
    local WHITE=0xFFF7F9FC

    local function normalise(shape)
        shape=tostring(shape or "arrow")
        if SHAPES[shape] then return shape end
        return ALIASES[shape] or "arrow"
    end
    local function cursorBounds(pointer)
        local shape=normalise(pointer and pointer.shape); local d=SHAPES[shape]
        return box(pointer.x-d.hotX,pointer.y-d.hotY,d.w,d.h)
    end
    local function row(x,y,count,color,clip)
        if count>0 then Driver.filledRectangle(x,y,count,1,color,clip) end
    end
    local function arrow(x,y,clip)
        for i=0,13 do row(x,y+i,i+2,BLACK,clip) end
        row(x,y+14,10,BLACK,clip); row(x,y+15,7,BLACK,clip)
        for i=16,23 do row(x+3,y+i,7,BLACK,clip) end
        for i=1,11 do row(x+1,y+i,i,WHITE,clip) end
        row(x+1,y+12,9,WHITE,clip); row(x+1,y+13,7,WHITE,clip)
        for i=14,17 do row(x+1,y+i,5,WHITE,clip) end
        for i=18,22 do row(x+4,y+i,5,WHITE,clip) end
    end
    local function hand(x,y,clip)
        Driver.filledRectangle(x+6,y+2,5,12,BLACK,clip); Driver.filledRectangle(x+3,y+9,13,9,BLACK,clip)
        Driver.filledRectangle(x+5,y+3,3,10,WHITE,clip); Driver.filledRectangle(x+8,y+5,3,9,WHITE,clip)
        Driver.filledRectangle(x+11,y+8,3,8,WHITE,clip); Driver.filledRectangle(x+14,y+11,2,5,WHITE,clip)
        Driver.filledRectangle(x+5,y+12,10,5,WHITE,clip); Driver.line(x+4,y+17,x+14,y+20,BLACK,clip)
        Driver.line(x+4,y+17,x+3,y+12,BLACK,clip)
    end
    local function textCursor(x,y,clip)
        Driver.filledRectangle(x+7,y,3,24,BLACK,clip); Driver.filledRectangle(x+8,y+2,1,20,WHITE,clip)
        Driver.filledRectangle(x+3,y,11,2,BLACK,clip); Driver.filledRectangle(x+3,y+22,11,2,BLACK,clip)
        Driver.filledRectangle(x+5,y+2,7,1,WHITE,clip); Driver.filledRectangle(x+5,y+21,7,1,WHITE,clip)
    end
    local function busy(x,y,clip)
        local c=0xFF62C7F2
        Driver.line(x+6,y+1,x+11,y+1,c,clip); Driver.line(x+14,y+4,x+16,y+8,c,clip)
        Driver.line(x+16,y+10,x+13,y+15,c,clip); Driver.line(x+10,y+16,x+5,y+16,c,clip)
        Driver.line(x+3,y+13,x+1,y+9,c,clip); Driver.line(x+2,y+6,x+5,y+2,c,clip)
        Driver.filledRectangle(x+8,y+7,3,3,WHITE,clip)
    end
    local function resizeNS(x,y,clip)
        Driver.filledRectangle(x+7,y+3,3,18,BLACK,clip); Driver.filledRectangle(x+8,y+4,1,16,WHITE,clip)
        Driver.line(x+8,y+1,x+4,y+5,BLACK,clip); Driver.line(x+8,y+1,x+12,y+5,BLACK,clip)
        Driver.line(x+8,y+22,x+4,y+18,BLACK,clip); Driver.line(x+8,y+22,x+12,y+18,BLACK,clip)
        Driver.line(x+8,y+2,x+5,y+5,WHITE,clip); Driver.line(x+8,y+21,x+5,y+18,WHITE,clip)
    end
    local function resizeEW(x,y,clip)
        Driver.filledRectangle(x+3,y+7,18,3,BLACK,clip); Driver.filledRectangle(x+4,y+8,16,1,WHITE,clip)
        Driver.line(x+1,y+8,x+5,y+4,BLACK,clip); Driver.line(x+1,y+8,x+5,y+12,BLACK,clip)
        Driver.line(x+22,y+8,x+18,y+4,BLACK,clip); Driver.line(x+22,y+8,x+18,y+12,BLACK,clip)
        Driver.line(x+2,y+8,x+5,y+5,WHITE,clip); Driver.line(x+21,y+8,x+18,y+5,WHITE,clip)
    end
    local function diagonal(x,y,clip,reverse)
        local c=0xFFF7F9FC
        Driver.line(x+3,y+17,x+17,y+3,BLACK,clip); Driver.line(x+5,y+17,x+17,y+5,BLACK,clip)
        Driver.line(x+4,y+16,x+16,y+4,c,clip)
        if reverse then
            Driver.line(x+3,y+3,x+7,y+7,BLACK,clip); Driver.line(x+17,y+17,x+13,y+13,BLACK,clip)
            Driver.line(x+4,y+4,x+7,y+7,c,clip); Driver.line(x+16,y+16,x+13,y+13,c,clip)
        else
            Driver.line(x+3,y+17,x+7,y+13,BLACK,clip); Driver.line(x+17,y+3,x+13,y+7,BLACK,clip)
            Driver.line(x+4,y+16,x+7,y+13,c,clip); Driver.line(x+16,y+4,x+13,y+7,c,clip)
        end
    end
    local function forbidden(x,y,clip)
        local c=0xFFE81123
        Driver.line(x+6,y+2,x+14,y+2,BLACK,clip); Driver.line(x+16,y+4,x+18,y+6,BLACK,clip)
        Driver.line(x+18,y+14,x+16,y+16,BLACK,clip); Driver.line(x+14,y+18,x+6,y+18,BLACK,clip)
        Driver.line(x+4,y+16,x+2,y+14,BLACK,clip); Driver.line(x+2,y+6,x+4,y+4,BLACK,clip)
        Driver.line(x+7,y+3,x+13,y+3,c,clip); Driver.line(x+16,y+6,x+17,y+13,c,clip)
        Driver.line(x+13,y+16,x+7,y+16,c,clip); Driver.line(x+4,y+13,x+3,y+7,c,clip)
        Driver.line(x+4,y+4,x+16,y+16,c,clip); Driver.line(x+5,y+3,x+17,y+15,c,clip)
    end
    local function move(x,y,clip)
        Driver.filledRectangle(x+8,y+3,3,12,BLACK,clip); Driver.filledRectangle(x+3,y+8,13,3,BLACK,clip)
        Driver.line(x+9,y+1,x+5,y+5,WHITE,clip); Driver.line(x+9,y+1,x+13,y+5,WHITE,clip)
        Driver.line(x+9,y+17,x+5,y+13,WHITE,clip); Driver.line(x+9,y+17,x+13,y+13,WHITE,clip)
        Driver.line(x+1,y+9,x+5,y+5,WHITE,clip); Driver.line(x+1,y+9,x+5,y+13,WHITE,clip)
        Driver.line(x+17,y+9,x+13,y+5,WHITE,clip); Driver.line(x+17,y+9,x+13,y+13,WHITE,clip)
    end
    local DRAW={arrow=arrow,hand=hand,text=textCursor,busy=busy,resize_ns=resizeNS,resize_ew=resizeEW,
        resize_nwse=function(x,y,c) diagonal(x,y,c,false) end,
        resize_nesw=function(x,y,c) diagonal(x,y,c,true) end,forbidden=forbidden,move=move}
    local Manager={shapes=SHAPES}
    function Manager.normalise(shape) return normalise(shape) end
    function Manager.set(shape,pointer)
        local target=pointer or (OS and OS.pointer); local value=normalise(shape)
        if target then target.shape=value end
        return value
    end
    function Manager.get(pointer) return normalise((pointer or (OS and OS.pointer) or {}).shape) end
    local function drawCursor(pointer,clip)
        if not pointer or not pointer.visible then return end
        local shape=normalise(pointer.shape); local d=SHAPES[shape]
        DRAW[shape](pointer.x-d.hotX,pointer.y-d.hotY,clip)
    end
    E.CursorManager=Manager; E.cursor=Manager; E.cursorBounds=cursorBounds; E.drawCursor=drawCursor
end

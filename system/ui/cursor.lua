-- HCC OS v1.5 pointer renderer.

return function(E)
    local env=setmetatable({},{__index=E})
    local _ENV=env
    local function cursorBounds(pointer)
        local shape=pointer and pointer.shape or "arrow"
        if shape=="hand" then return box(pointer.x-1,pointer.y-1,15,15) end
        if shape:find("resize",1,true) or shape=="move" then return box(pointer.x-3,pointer.y-3,18,18) end
        return box(pointer.x,pointer.y,13,15)
    end
    local function drawCursor(pointer,clip)
        if not pointer or not pointer.visible then return end
        local x,y=pointer.x,pointer.y; local shape=pointer.shape or "arrow"
        if shape=="hand" then
            Driver.filledRectangle(x+3,y+2,7,10,0xFF000000,clip)
            Driver.filledRectangle(x+4,y+1,4,9,P.textPrimary,clip)
            Driver.filledRectangle(x+2,y+5,2,6,P.textPrimary,clip)
            Driver.filledRectangle(x+8,y+3,3,8,P.textPrimary,clip)
            Driver.line(x+3,y+12,x+10,y+12,P.textPrimary,clip)
        elseif shape=="move" then
            Driver.line(x+8,y+1,x+8,y+15,P.textPrimary,clip); Driver.line(x+1,y+8,x+15,y+8,P.textPrimary,clip)
            Driver.line(x+8,y+1,x+5,y+4,0xFF000000,clip); Driver.line(x+8,y+1,x+11,y+4,0xFF000000,clip)
        elseif shape:find("resize",1,true) then
            Driver.line(x+2,y+13,x+13,y+2,P.textPrimary,clip)
            Driver.line(x+5,y+13,x+13,y+5,P.textPrimary,clip)
            Driver.line(x+2,y+10,x+10,y+2,P.textPrimary,clip)
        else
            for i=0,10 do Driver.line(x,y+i,x+floor(i/2),y+i,P.textPrimary,clip) end
            Driver.line(x,y,x,y+12,0xFF000000,clip); Driver.line(x,y,x+7,y+11,0xFF000000,clip)
            Driver.line(x+3,y+9,x+7,y+14,P.textPrimary,clip)
        end
    end
    E.cursorBounds=cursorBounds; E.drawCursor=drawCursor
end

-- HCC OS v1.5 icon system.
-- Icons are rendered from a small, consistent vector-like pixel language so
-- they remain legible on every Tom's GPU resolution.

return function(E)
    local env=setmetatable({},{__index=E})
    local _ENV=env
    local ICONS={
        clock={"  ###  "," ##### ","## # ##","##   ##","## ### "," ##### ","  ###  "},
        calendar={" ######","##    #","# ### #","#     #","# ### #","#     #","#######"},
        files={"  #### "," ######","##    #","##    #","##    #","##    #","#######"},
        terminal={"#######","#     #","##   ##","  ###  ","  ###  ","#     #","#######"},
        server={"#######","## # ##","#######","## # ##","#######","## # ##","#######"},
        network={"   #   ","  ###  ","## # ##"," ######","## # ##","  ###  ","   #   "},
        peripherals={"# ### #","#######"," ## ## ","#######"," ## ## ","#######","# ### #"},
        settings={"  ###  "," ##### ","### ###","#######","### ###"," ##### ","  ###  "},
        radar={"  ###  "," #   # ","#  #  #","#######","#  #  #"," #   # ","  ###  "},
        inventory={"#######","# ### #","#######","# ### #","#######","# ### #","#######"},
        image={"#######","#     #","# ### #","#  #  #","# ### #","#     #","#######"},
        web={"  ###  "," #   # ","# ### #","  ###  ","# ### #"," #   # ","  ###  "},
        logs={"#######","#     #","# ### #","# ### #","# ### #","#     #","#######"},
        performance={"#     #","##    #","# #   #","#  #  #","#   # #","#    ##","#     #"},
        taskmgr={"#######","#  #  #","# ### #","# ### #","#  #  #","# ### #","#######"},
        resource={"  ###  "," ##### ","## # ##","#######","## # ##"," ##### ","  ###  "},
        currency={"  ###  "," ######","##  #  ","  ###  ","  #  ##","###### ","  ###  "},
        system={"#######","##   ##","# ### #","# ### #","# ### #","##   ##","#######"},
        diagnostics={"    ## ","   ### ","  #### "," ##### ","###### ","#####  ","##     "},
        updates={"#######","#  #  #","#  #  #","# ### #","#  #  #","#  #  #","#######"},
        notepad={" ##### "," ######","##    #","## ## #","##    #","##    #","#######"},
        default={"#######","#     #","# ### #","# ### #","# ### #","#     #","#######"}
    }
    local COLORS={clock=0xFF73D8FF,calendar=0xFFFFC65B,files=0xFFD1A56E,terminal=0xFFF0F5FA,
        server=0xFF72D6FF,network=0xFF9EAFFF,peripherals=0xFF69D4FF,settings=0xFFB7C0CB,
        radar=0xFF64D8FF,inventory=0xFFB8A06A,image=0xFFB9A7FF,web=0xFF70C8FF,
        logs=0xFFBFC9D4,performance=0xFF66E0A3,taskmgr=0xFF7DD3FC,resource=0xFFD49A6A,
        currency=0xFFFFD166,system=0xFF75E0FF,diagnostics=0xFF80E0A0,updates=0xFF80C7FF,
        notepad=0xFFFFC65B}
    local CACHE={}

    local function patternFor(id)
        return ICONS[id] or ICONS.default
    end

    local function instructions(id,size)
        local key=tostring(id)..":"..tostring(size)
        if CACHE[key] then return CACHE[key] end
        local pattern=patternFor(id); local cell=max(1,floor((size-4)/7))
        local ox=2+floor((size-4-cell*7)/2); local oy=ox; local result={}
        for row,line in ipairs(pattern) do
            for col=1,7 do
                if line:sub(col,col)~=" " then
                    result[#result+1]={x=ox+(col-1)*cell,y=oy+(row-1)*cell,w=cell,h=cell}
                end
            end
        end
        CACHE[key]=result
        return result
    end

    local function iconId(def)
        return type(def)=="table" and (def.iconId or def.id) or tostring(def or "default")
    end

    local function drawControl(c,x,y,size,kind,color)
        color=color or P.textPrimary; size=max(8,floor(size or 12)); local mid=floor(size/2)
        if kind=="close" then
            c:line(x+3,y+3,x+size-4,y+size-4,color); c:line(x+size-4,y+3,x+3,y+size-4,color)
        elseif kind=="maximize" then c:rectangle(x+3,y+3,size-6,size-6,color)
        elseif kind=="restore" then
            c:rectangle(x+4,y+2,size-6,size-6,color); c:line(x+2,y+4,x+2,y+size-3,color); c:line(x+2,y+size-3,x+size-5,y+size-3,color)
        elseif kind=="minimize" then c:line(x+3,y+mid,x+size-4,y+mid,color)
        elseif kind=="menu" then
            c:filledRectangle(x+2,y+3,size-4,2,color); c:filledRectangle(x+2,y+mid-1,size-4,2,color); c:filledRectangle(x+2,y+size-5,size-4,2,color)
        elseif kind=="back" then c:line(x+size-3,y+2,x+3,y+mid,color); c:line(x+3,y+mid,x+size-3,y+size-3,color)
        end
    end

    local function drawAppIcon(c,def,x,y,size,state)
        size=max(8,floor(tonumber(size) or 16)); state=tostring(state or "normal")
        local id=iconId(def); local bg=P.panelBackground; local edge=P.border
        local fg=P.textPrimary; local accent=COLORS[id] or P.accent
        if state=="hover" then bg=P.windowBackground; edge=P.accent
        elseif state=="selected" then edge=P.accent
        elseif state=="running" then edge=P.accent
        elseif state=="disabled" then fg=P.textSecondary; accent=P.border
        elseif state=="error" or state=="offline" then edge=P.error; accent=P.textSecondary end
        c:filledRectangle(x,y,size,size,bg); c:rectangle(x,y,size,size,edge)
        for _,pixel in ipairs(instructions(id,size)) do c:filledRectangle(x+pixel.x,y+pixel.y,pixel.w,pixel.h,accent) end
        if state=="running" then c:filledRectangle(x+size-5,y+2,3,3,P.success)
        elseif state=="error" or state=="offline" then c:filledRectangle(x+size-5,y+2,3,3,P.error) end
    end

    E.ICON_REGISTRY=ICONS; E.ICON_ACCENTS=COLORS
    E.drawAppIcon=drawAppIcon; E.drawControlIcon=drawControl
end

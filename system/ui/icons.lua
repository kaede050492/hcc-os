return function(E)
 local env=setmetatable({},{__index=E})
 local _ENV=env
local ICON_REGISTRY={
    clock={glyph={"  +++  "," +###  ","+####+","+####+","+####+"," +##+ ","  +++  "}},
    files={glyph={"  +++  "," +####+","+#####","+####+","+####+","+####+","+++++++"}},
    peripherals={glyph={" ++ ++ ","+##### ","##+### ","######+","##+### ","+##### "," ++ ++ "}},
    performance={glyph={"#     +","##   ++","#+  +++","#+ ++++","#+++++ ","++++++ ","+++++++"}},
    calendar={glyph={"+++++++","+##### ","+##+##+","+##### ","+##### ","+##### ","+++++++"}},
    currency={glyph={"  +++  "," +###+ ","+##### ","+##+##+","+##### "," +###+ ","  +++  "}},
    network={glyph={"   +   ","  +++  ","+++ +++","  +++  ","+++ +++","  +++  ","   +   "}},
    taskmgr={glyph={"+++++++","+#####+","+#+++#+","+#+++#+","+##### ","+  ++  ","  +++  "}},
    radar={glyph={"  +++  "," ++#++ ","+##### ","++###++","+##### "," ++#++ ","  +++  "}},
    image={glyph={"+++++++","+     +","+  ++ +","+ +## +","+##### ","+     +","+++++++"}},
    resource={glyph={" +++++ ","+##### ","+#+##+ ","+##### ","+##+#+ ","+##### "," +++++ "}},
    terminal={glyph={"       ","+     #","++   ##","+++ ## ","++   ##","+     #","       "}},
    server={glyph={"+++++++","+##+##+","+##### ","+##+##+","+##### ","+##+##+","+++++++"}},
    web={glyph={"  +++  "," ++#++ ","+##### ","+# +#+ ","+##### "," ++#++ ","  +++  "}},
    logs={glyph={"+++++++","+##### ","+##    ","+##### ","+##    ","+##### ","+++++++"}},
    settings={glyph={"  +++  "," +### +","+##### ","+##+##+","+##### "," +### +","  +++  "}},
    notepad={glyph={"  +++++"," +####+","+##### ","+###  +","+##### ","+##### ","+++++++"}},
    inventory={glyph={"+++++++","+##### ","+#+##+ ","+##+#+ ","+#+##+ ","+##### ","+++++++"}},
    system={glyph={"  +++  "," +### +","+##### ","+#+++#+","+##### "," +### +","  +++  "}},
    diagnostics={glyph={"    ++ ","   +## ","  +### "," +#### ","+####+ ","+####  ","+++    "}},
    updates={glyph={"+++++++","+  +  +","+  +  +","+##### ","+  +  +","+  +  +","+++++++"}},
    default={glyph={"+++++++","+##### ","+##### ","+##### ","+##### ","+##### ","+++++++"}}
}
local ICON_ACCENTS={clock=0xFF72D6FF,files=0xFFB8A06A,peripherals=0xFF69D4FF,performance=0xFF66E0A3,calendar=0xFFFFC65B,currency=0xFFFFD166,network=0xFF9EAEFF,taskmgr=0xFF7DD3FC,radar=0xFF64D8FF,image=0xFFB9A7FF,resource=0xFFD49A6A,terminal=0xFFF0F5FA,server=0xFF72D6FF,web=0xFF70C8FF,logs=0xFFBFC9D4,settings=0xFFB7C0CB,notepad=0xFFFFC65B,inventory=0xFFB8A06A,system=0xFF75E0FF,diagnostics=0xFF80E0A0,updates=0xFF80C7FF}
local ICON_CACHE={}
local function iconInstructions(id,size,def)
    local key=id..":"..tostring(size); if ICON_CACHE[key] then return ICON_CACHE[key] end
    local inner=size-4; local cell=max(1,floor(inner/7)); local ox=2+floor((inner-cell*7)/2); local oy=2+floor((inner-cell*7)/2); local out={}
    for py,row in ipairs(def.glyph) do for px=1,min(7,#row) do local ch=row:sub(px,px); if ch~=" " then out[#out+1]={x=ox+(px-1)*cell,y=oy+(py-1)*cell,w=cell,h=cell,ch=ch} end end end
    ICON_CACHE[key]=out; return out
end
local drawAppIcon
local iconIsOffline
drawAppIcon=function(c,appDef,x,y,size,state)
    size=max(6,floor(tonumber(size) or 16)); state=tostring(state or "normal"):lower()
    local id=type(appDef)=="table" and (appDef.id or appDef.iconId) or tostring(appDef or "default"); local def=ICON_REGISTRY[id] or ICON_REGISTRY.default
    local bg=P.panelBackground; local edge=P.border; local fg=P.textPrimary; local accent=ICON_ACCENTS[id] or P.accent
    if state=="hover" then bg=P.windowBackground; edge=P.accent elseif state=="selected" then bg=P.panelBackground; edge=P.accent elseif state=="running" then edge=P.accent elseif state=="disabled" then bg=P.windowBackground; fg=P.textSecondary; accent=P.border elseif state=="error" then edge=P.error elseif state=="offline" then edge=P.error; accent=P.textSecondary end
    c:filledRectangle(x,y,size,size,bg); c:rectangle(x,y,size,size,edge)
    for _,pixel in ipairs(iconInstructions(id,size,def)) do local color=pixel.ch=="+" and accent or fg; if pixel.ch=="o" then color=P.success elseif pixel.ch=="x" then color=P.warning end; c:filledRectangle(x+pixel.x,y+pixel.y,pixel.w,pixel.h,color) end
    if state=="running" then c:filledRectangle(x+size-5,y+2,3,3,P.accent) elseif state=="error" or state=="offline" then c:filledRectangle(x+size-5,y+2,3,3,P.error) end
end
E.ICON_REGISTRY=ICON_REGISTRY; E.ICON_ACCENTS=ICON_ACCENTS; E.drawAppIcon=drawAppIcon

end




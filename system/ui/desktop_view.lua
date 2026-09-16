return function(E)
 local env=setmetatable({},{__index=E})
 local _ENV=env
local function shortText(value,limit)
    value=ascii(value); if #value<=limit then return value end
    return value:sub(1,max(1,limit-1)).."~"
end
local DESKTOP_LABELS={
    peripherals={"Peripheral","Manager"},network={"Network","Manager"},taskmgr={"Task","Manager"},radar={"Player","Radar"},
    image={"Image","Viewer"},resource={"Resource","Monitor"},server={"Server","Monitor"},system={"System","Monitor"},
    currency={"Currency","Calculator"},inventory={"Inventory","Viewer"},diagnostics={"Diagnostics"},performance={"Performance"},updates={"Update","Recovery"}
}
local function desktopLabel(def,rich)
    local id=def and (def.id or def.iconId); local parts=DESKTOP_LABELS[id]
    if parts then
        local out={}; for i,v in ipairs(parts) do out[#out+1]=rich and v or shortText(v,9) end; return out
    end
    local name=ascii(def and def.name or "App"); if not rich then return {shortText(name,9)} end
    local first,second=name:match("^(%S+)%s+(.+)$")
    if first and second and #first<=12 and #second<=12 then return {first,second} end
    return {shortText(name,13)}
end
iconIsOffline=function(id)
    if id=="radar" then return not devices.detector end
    if id=="network" then return #devices.modems==0 end
    if id=="peripherals" then return #devices.list==0 end
    return false
end
local function iconRects()
    local out={}; local areaH=max(1,Driver.h-TASK); local rich=cfg.showRichIcons and Driver.w>=300 and Driver.h>=210
    local rows,columns,cellW,cellH
    if rich then
        rows=max(1,min(5,floor((areaH-12)/58))); columns=max(1,math.ceil(#OS.order/rows)); cellW=max(1,floor((Driver.w-8)/columns)); cellH=max(48,floor((areaH-8)/rows))
    else
        columns=max(1,min(5,floor((Driver.w-8)/42))); rows=max(1,math.ceil(#OS.order/columns)); cellW=max(1,floor((Driver.w-8)/columns)); cellH=max(28,floor((areaH-8)/rows))
    end
    for i,id in ipairs(OS.order) do
        local col=(i-1)%columns; local row=floor((i-1)/columns); local r=box(4+col*cellW,6+row*cellH,max(12,cellW-2),max(22,cellH-2)); r.rich=rich; out[#out+1]={id=id,r=r}
    end
    return out
end
local function buildDesktop()
    local list={}; local c=canvas(list,0,0,Driver.w,Driver.h-TASK)
    c:clear(P.desktopBackground)
    local wallpaper=wallpaperCommands()
    if wallpaper then for _,cmd in ipairs(wallpaper) do list[#list+1]=cmd end end
    for i,item in ipairs(iconRects()) do
        local def=OS.registry[item.id]; local r=item.r
        local selected=OS.active==nil and i==OS.iconIndex; local hovered=OS.desktopHover==i; local running=false; local failed=false
        for _,w in ipairs(OS.windows) do if w.id==item.id and not w.minimized then running=true end; if w.id==item.id and w.crash then failed=true end end
        local state=failed and "error" or (selected and "selected" or (hovered and "hover" or (running and "running" or (iconIsOffline(item.id) and "offline" or "normal"))))
        if selected then c:filledRectangle(r.x+1,r.y+1,r.w-2,r.h-2,P.panelBackground); c:rectangle(r.x,r.y,r.w,r.h,P.accent) elseif hovered then c:rectangle(r.x,r.y,r.w,r.h,P.border) end
        local iconSize=r.rich and min(32,max(28,min(r.w-8,32))) or min(18,max(14,min(r.w-8,18))); local ix=r.x+floor((r.w-iconSize)/2); drawAppIcon(c,def,ix,r.y+2,iconSize,state)
        if running and not failed then c:filledRectangle(ix+iconSize-5,r.y+4,3,3,P.accent) end
        local labels=desktopLabel(def,r.rich); local ly=r.rich and r.y+35 or r.y+iconSize+5; local lh=#labels*10+2; if r.w>22 then c:filledRectangle(r.x+2,ly-1,r.w-4,lh,P.desktopBackground) end
        for n,label in ipairs(labels) do local clipped=shortText(label,max(3,floor((r.w-6)/6))); c:text(r.x+max(2,floor((r.w-Driver.measure(clipped))/2)),ly+(n-1)*10,clipped,selected and P.textPrimary or (hovered and P.textPrimary or P.textSecondary)) end
    end
    if Driver.w>=450 then
        c:text(Driver.w-170,Driver.h-TASK-31,HCC_VERSION_LABEL.." / CENTRAL LAB",P.border)
        c:text(Driver.w-150,Driver.h-TASK-17,"F1 MENU   F6 TILE",P.border)
    end
    OS.desktop=list; OS.desktopDirty=false
end
E.shortText=shortText; E.DESKTOP_LABELS=DESKTOP_LABELS; E.desktopLabel=desktopLabel; E.iconIsOffline=iconIsOffline; E.iconRects=iconRects; E.buildDesktop=buildDesktop

end


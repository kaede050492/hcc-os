-- Run with Lua 5.2+ from the repository root:
--   lua tests/ui_layout_spec.lua

local taskbarChunk,taskbarError=loadfile("system/ui/taskbar.lua")
assert(taskbarChunk,taskbarError)
local taskbarModule=taskbarChunk()
local menuChunk,menuError=loadfile("system/ui/start_menu.lua")
assert(menuChunk,menuError)
local menuModule=menuChunk()

local function box(x,y,w,h)
    return {x=math.floor(x),y=math.floor(y),w=math.max(0,math.floor(w)),h=math.max(0,math.floor(h))}
end
local function clamp(value,minimum,maximum)
    return math.max(minimum,math.min(maximum,value))
end
local function environment(width,height)
    local OS={windows={},taskScroll=1}
    local E={Driver={w=width,h=height},OS=OS,TASK=32,TOP=22,
        TASKBAR_CORNER_RADIUS=10,
        box=box,clamp=clamp,floor=math.floor,min=math.min,max=math.max}
    setmetatable(E,{__index=_G})
    taskbarModule(E)
    menuModule(E)
    return E
end
local function within(rect,width,height,label)
    assert(rect.x>=0 and rect.y>=0 and rect.w>0 and rect.h>0 and
        rect.x+rect.w<=width and rect.y+rect.h<=height,
        label.." should stay inside the logical display")
end

for _,size in ipairs({{576,320},{288,160}}) do
    local width,height=size[1],size[2]
    local E=environment(width,height)
    local menu=E.menuBox()
    within(menu,width,height,"start menu")
    within(E.dialogBox(),width,height,"dialog")
    within(E.contextBox(-10000,10000),width,height,"context menu")
    within(E.toastBox(),width,height,"toast")

    local recent={menuRecentCount=2,powerMenu=false,menuTop=3}
    local rowY=menu.y+E.menuRowY(recent,4)
    assert(E.menuIndexAt(recent,rowY+math.floor(E.menuRowH/2))==4,
        "menu rows should map back to the same app index")
    recent.powerMenu=true
    rowY=menu.y+E.menuRowY(recent,4)
    assert(E.menuIndexAt(recent,rowY+math.floor(E.menuRowH/2))==4,
        "power menu rows should omit the recent-app header")
    local overlays=E.overlayBounds({menu=true,context={x=0,y=0},toast=true,modal=true})
    assert(#overlays==4,"all active overlays should contribute a hit-test bound")

    E.OS.windows={}
    local noTasks=E.taskRects()
    assert(#noTasks==0,"an empty session should not reserve task buttons")
    local single={id=1,minimized=false}
    E.OS.windows={single}; E.OS.active=single
    local oneTask=E.taskRects()
    assert(#oneTask==1,"a single window should have one task button")

    E.OS.windows={}
    for index=1,24 do
        E.OS.windows[index]={id=index,minimized=index%4==0}
    end
    E.OS.active=E.OS.windows[24]
    E.OS.taskScroll=1
    E.revealActiveTask()
    local visible,_,_,_,layout=E.taskRects()
    assert(layout.overflow and #visible==layout.capacity,
        "the taskbar should expose only its visible capacity when windows overflow")
    local activeVisible=false
    for _,item in ipairs(visible) do
        within(item.r,width,height,"task button")
        if item.win==E.OS.active then activeVisible=true end
    end
    assert(activeVisible,"the active window should be revealed after taskbar overflow")
    assert(E.OS.taskScroll>=1 and E.OS.taskScroll<=24-layout.capacity+1,
        "taskbar scroll position should stay within the window list")
end

print("UI layout specs passed (scaled logical sizes, overlays, task overflow)")

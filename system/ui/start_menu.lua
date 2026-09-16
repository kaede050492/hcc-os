-- HCC OS v1.5 overlay layout helpers.

return function(E)
    local floor,min,max=math.floor,math.min,math.max
    E.menuBox=function()
        local w=min(330,max(238,E.Driver.w-12)); local h=min(270,max(178,E.Driver.h-E.TASK-8))
        return E.box(4,E.Driver.h-E.TASK-h-4,w,h)
    end
    E.menuListY=62; E.menuRowH=22
    E.dialogBox=function()
        local w=min(390,max(230,E.Driver.w-12)); local h=min(170,max(112,E.Driver.h-E.TASK-8))
        return E.box((E.Driver.w-w)/2,(E.TOP+(E.Driver.h-E.TASK-E.TOP-h)/2),w,h)
    end
end

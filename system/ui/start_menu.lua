-- HCC OS v1.5 overlay layout helpers.

return function(E)
    local floor,min,max=math.floor,math.min,math.max
    E.menuBox=function()
        local w=min(250,max(190,E.Driver.w-12)); local h=min(230,max(130,E.Driver.h-E.TASK-E.TOP-8))
        return E.box(6,E.Driver.h-E.TASK-h-5,w,h)
    end
    E.dialogBox=function()
        local w=min(390,max(230,E.Driver.w-12)); local h=min(170,max(112,E.Driver.h-E.TASK-8))
        return E.box((E.Driver.w-w)/2,(E.TOP+(E.Driver.h-E.TASK-E.TOP-h)/2),w,h)
    end
end

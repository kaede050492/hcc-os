return function(E)
 local floor,min,max=math.floor,math.min,math.max
 E.menuBox=function() local h=min(184,E.Driver.h-E.TASK-6); return E.box(3,E.Driver.h-E.TASK-h-3,min(175,E.Driver.w-6),h) end
 E.dialogBox=function() local w=min(370,E.Driver.w-8); local h=min(140,E.Driver.h-E.TASK-4); return E.box((E.Driver.w-w)/2,(E.Driver.h-E.TASK-h)/2,w,h) end
end


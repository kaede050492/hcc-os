-- HCC OS v1.5 overlay layout helpers.

return function(E)
    local floor,min,max=math.floor,math.min,math.max
    E.menuBox=function()
        local w=min(360,max(160,E.Driver.w-16)); local h=min(250,max(96,E.Driver.h-E.TASK-8))
        h=min(h,max(1,E.Driver.h-48-E.TOP))
        return E.box(max(8,floor((E.Driver.w-w)/2)),max(E.TOP,E.Driver.h-48-h),w,h)
    end
    E.menuListY=62; E.menuRowH=22
    E.menuHeaderHeight=function(OS) return not OS.powerMenu and (OS.menuRecentCount or 0)>0 and 12 or 0 end
    E.menuRowY=function(OS,index)
        return E.menuListY+E.menuHeaderHeight(OS)+(index-(OS.menuTop or 1))*E.menuRowH
    end
    E.menuIndexAt=function(OS,y)
        local r=E.menuBox()
        return floor((y-r.y-E.menuListY-E.menuHeaderHeight(OS))/E.menuRowH)+(OS.menuTop or 1)
    end
    E.dialogBox=function()
        local w=min(390,max(230,E.Driver.w-12)); local h=min(170,max(112,E.Driver.h-E.TASK-8))
        return E.box((E.Driver.w-w)/2,(E.TOP+(E.Driver.h-E.TASK-E.TOP-h)/2),w,h)
    end
    E.contextBox=function(x,y)
        local w=min(178,E.Driver.w-8); local h=64
        return E.box(E.clamp(x,4,E.Driver.w-w-4),E.clamp(y,E.TOP,E.Driver.h-E.TASK-h-4),w,h)
    end
    E.toastBox=function()
        local w=min(300,E.Driver.w-12)
        return E.box(E.Driver.w-w-6,E.TOP+5,w,40)
    end
    E.overlayBounds=function(OS)
        local bounds={}
        if OS.menu then bounds[#bounds+1]=E.menuBox() end
        if OS.context then bounds[#bounds+1]=E.contextBox(OS.context.x,OS.context.y) end
        if OS.toast then bounds[#bounds+1]=E.toastBox() end
        if OS.modal then bounds[#bounds+1]=E.dialogBox() end
        return bounds
    end
end

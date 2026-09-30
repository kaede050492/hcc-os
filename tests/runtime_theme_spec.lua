-- Run with Lua 5.2+ from the repository root:
--   lua tests/runtime_theme_spec.lua

local colorChunk,colorError=loadfile("system/lib/hcc/color.lua")
assert(colorChunk,colorError)
local Color=colorChunk()
local environment=setmetatable({
    require=function(name)
        if name=="hcc.color" then return Color end
    end
},{__index=_G})

local runtimeChunk,runtimeError=loadfile("system/core/runtime.lua","t",environment)
assert(runtimeChunk,runtimeError)
local Runtime=runtimeChunk()
local context={
    config={data={theme="black",accent="cyan"},save=function() return true end},
    paths={settings="/.hccos/settings.lua"}
}
local E=Runtime.new(context)
local tint=0xFF4090E0
local blackWindow=E.P.windowBackground
local redraws=0
E.allDirty=function() redraws=redraws+1 end

assert(E.setWallpaperTint(tint,true),"a valid wallpaper tint should be accepted")
assert(redraws==0,"deferred tint updates should not trigger an immediate redraw")
assert(E.P.windowBackground==Color.blend(blackWindow,tint,0.36,22),
    "window surfaces should blend a bounded amount of wallpaper color")
assert(E.P.textPrimary==E.palettes.black.textPrimary,
    "wallpaper tint should preserve foreground text colors")
assert(not E.setWallpaperTint(tint,true),"an unchanged tint should not rebuild the palette")
assert(not E.setWallpaperTint("invalid",true),"invalid colors should be rejected")

E.setTheme("midnight")
assert(redraws==1,"theme changes should request one redraw")
assert(E.P.windowBackground==Color.blend(E.palettes.midnight.windowBackground,tint,0.36,22),
    "the active wallpaper tint should carry across theme changes")
assert(E.setWallpaperTint(nil),"clearing the tint should be accepted")
assert(redraws==2,"a non-deferred tint clear should request one redraw")
assert(E.P.windowBackground==E.palettes.midnight.windowBackground,
    "clearing the tint should restore the selected theme surface")

print("runtime theme specs passed")

-- Run with a Lua 5.2+ interpreter from the repository root:
--   lua tests/color_spec.lua

local chunk,loadError=loadfile("system/lib/hcc/color.lua")
assert(chunk,loadError)
local Color=chunk()
local function unsigned(value) return value%4294967296 end

local sampled=Color.sample({width=2,height=2,pixels={
    0xFFFF0000,0xFF00FF00,
    0xFF0000FF,0xFFFFFFFF
}},2,2)
assert(sampled==unsigned(0xFF808080),"sampling should return the average of opaque pixels")

local alphaWeighted=Color.sample({width=2,height=1,pixels={0x00FFFFFF,0xFFFF0000}},2,1)
assert(alphaWeighted==unsigned(0xFFFF0000),"transparent pixels should not change the sampled backdrop tint")
assert(Color.sample({width=1,height=1,pixels={0}},1,1)==nil,
    "fully transparent image data should not produce a tint")
assert(Color.sample({width=1,height=1,pixels={0xFF123456}},"invalid",math.huge)==unsigned(0xFF123456),
    "invalid sampling dimensions should fall back to bounded defaults")

local base=0xFF202830
assert(Color.blend(base,0xFFFFFFFF,0)==base,"zero blend should preserve the base surface")
assert(Color.blend(base,0xFFFFFFFF,1,12)==unsigned(0xFF2C343C),
    "surface tint should respect its maximum per-channel shift")
assert(Color.blend(base,0xFFFFFFFF,1,0)==base,"zero channel shift should preserve the base surface")

print("color specs passed")

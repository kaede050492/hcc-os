-- Run with Lua 5.2+ from the repository root:
--   lua tests/capabilities_spec.lua

local moduleChunk,moduleError=loadfile("system/core/capabilities.lua")
assert(moduleChunk,moduleError)
local CapabilityRegistry=moduleChunk()
local gpuMethods={"getSize","refreshSize","setSize","filledRectangle","line",
    "drawText","getTextLength","sync","fill"}
local devices={
    gpu={type="tm_gpu",methods=gpuMethods,handle={marker="gpu"}},
    keyboard={type="keyboard",methods={"setFireNativeEvents"},handle={marker="keyboard"}},
    detector={type="playerDetector",methods={"getOnlinePlayers","getPlayerPos"},handle={marker="detector"}},
    partial={type="unknown",methods={"getPlayersInRange"},handle={marker="partial"}},
    inventory={type="inventory",methods={"list","size"},handle={marker="inventory"}},
    broken={type="unknown",methodsError="method scan failed",typeError="type scan failed",wrapError="wrap failed"}
}
local names={"inventory","partial","detector","keyboard","gpu","broken"}
local logs={}
local api={
    getNames=function() local copy={} for i,name in ipairs(names) do copy[i]=name end return copy end,
    getType=function(name)
        if devices[name] and devices[name].typeError then error(devices[name].typeError) end
        return devices[name] and devices[name].type
    end,
    getMethods=function(name)
        local device=devices[name]
        if device and device.methodsError then error(device.methodsError) end
        return device and device.methods or {}
    end,
    wrap=function(name)
        local device=devices[name]
        if device and device.wrapError then error(device.wrapError) end
        return device and device.handle
    end
}
local logger={warn=function(_,message) logs[#logs+1]=message end}
local registry=CapabilityRegistry.new({api=api,logger=logger})
local items,scanError=registry:scan()
assert(not scanError and #items==6 and registry.generation==1,
    "a successful scan should include every named device")
assert(registry:find("tom_gpu").name=="gpu" and registry:find("tom_keyboard").name=="keyboard",
    "Tom's hardware should be identified by methods, regardless of device labels")
assert(registry:find("modem")==nil and registry:find("inventory").name=="inventory",
    "capabilities should require their complete method sets")
assert(registry:find("player_radar").name=="detector" and
    registry:get("partial").capabilities.player_detector and
    not registry:get("partial").capabilities.player_radar,
    "partial detectors should be visible without being advertised as radar-capable")
assert(registry:find("tom_gpu","missing-preference").name=="gpu",
    "an unavailable preferred device should fall back to another matching device")
assert(#registry.errors==3 and #logs==3,
    "type, method, and wrapping errors should be isolated and logged per device")

local snapshot=registry:snapshot()
assert(#snapshot==#items and snapshot[1].capabilities.detector_methods==nil,
    "snapshots should omit mutable internal method sets")
assert(registry:get("gpu").handle.marker=="gpu",
    "the live registry should retain wrapped handles for adapters")

names={"keyboard"}
items=registry:scan()
assert(#items==1 and items[1].name=="keyboard" and registry.generation==2,
    "rescanning should discard disconnected devices and advance the generation")

local failing=CapabilityRegistry.new({api={getNames=function() error("peripheral bus failed") end},logger=logger})
items,scanError=failing:scan()
assert(#items==0 and scanError:find("peripheral bus failed",1,true),
    "peripheral enumeration errors should return an empty result instead of escaping")

print("capability registry specs passed")

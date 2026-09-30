-- Run with Lua 5.2+ from the repository root:
--   lua tests/module_loader_spec.lua

local sources={
    ["/system/app/main.lua"]='isolatedValue=(isolatedValue or 0)+1; local dep=require("lib.dep"); return {value=dep.value}',
    ["/system/lib/dep.lua"]='loads=(loads or 0)+1; return {value=loads}',
    ["/system/broken.lua"]='error("injected module failure")',
    ["/system/cycle/a.lua"]='return require("cycle.b")',
    ["/system/cycle/b.lua"]='return require("cycle.a")'
}
local oldFs=_G.fs
_G.fs={
    combine=function(root,relative)
        if relative:sub(1,1)=="/" then return relative end
        return root:gsub("/$","").."/"..relative:gsub("^/","")
    end,
    exists=function(path) return sources[path]~=nil end,
    isDir=function() return false end,
    open=function(path,mode)
        if mode~="r" or sources[path]==nil then return nil,"file not found: "..path end
        local source=sources[path]
        return {readAll=function() return source end,close=function() end}
    end
}

local ok,loadError=pcall(function()
    local moduleChunk,moduleError=loadfile("system/core/module_loader.lua")
    assert(moduleChunk,moduleError)
    local ModuleLoader=moduleChunk()
    local loader=ModuleLoader.new({roots={"/system"}})
    local first=loader:load("app.main")
    assert(first.value==1 and loader:load("app/main.lua")==first,
        "normalized module names should resolve and return the cached module value")
    assert(_G.isolatedValue==nil and _G.loads==nil,
        "module top-level assignments should remain inside the module environment")

    local other=ModuleLoader.new({roots={"/system"}})
    local independent=other:load("lib.dep")
    assert(independent.value==1 and other.cache["lib/dep"]~=loader.cache["lib/dep"],
        "separate OS loaders should not share module cache state")
    loader:clear("app.main")
    assert(loader:load("app/main.lua")~=first,
        "clearing one cache key should permit a fresh module instance")

    for _,name in ipairs({"", "../secret", "cycle/../a", "..\\secret"}) do
        assert(not pcall(loader.load,loader,name),"unsafe module names should be rejected: "..name)
    end

    local cycle=ModuleLoader.new({roots={"/system"}})
    local cycleOk,cycleError=pcall(cycle.load,cycle,"cycle.a")
    assert(not cycleOk and tostring(cycleError):find("circular module dependency",1,true),
        "circular dependencies should fail with a specific diagnostic")
    assert(not next(cycle.loading),"failed circular loads should release every loading marker")

    local brokenOk=pcall(loader.load,loader,"broken")
    assert(not brokenOk and loader.loading.broken==nil,
        "runtime failures should release the loading marker")
    sources["/system/broken.lua"]='return {recovered=true}'
    assert(loader:load("broken").recovered,
        "a failed module should be retryable after its source is repaired")
end)
_G.fs=oldFs
assert(ok,loadError)

print("module loader specs passed")

-- Run with Lua 5.2+ from the repository root:
--   lua tests/app_manager_spec.lua

local moduleChunk,moduleError=loadfile("system/core/app_manager.lua")
assert(moduleChunk,moduleError)
local AppManager=moduleChunk()
local attachedService
local entries={
    {id="good",name="Good",iconId="good-icon",defaultWidth=220,defaultHeight=140,
        entryPath="/apps/good.lua",path="/apps/good",requirements={},desktop={visible=true,order=2}},
    {id="tableapp",name="Table App",iconId="tableapp",defaultWidth=210,defaultHeight=130,
        entryPath="/apps/tableapp.lua",path="/apps/tableapp",requirements={},desktop={visible=true,order=3}},
    {id="hidden",name="Hidden",iconId="hidden",defaultWidth=200,defaultHeight=120,
        entryPath="/apps/hidden.lua",path="/apps/hidden",requirements={},desktop={visible=false,order=4}},
    {id="service",name="Service",iconId="service",defaultWidth=200,defaultHeight=120,
        entryPath="/apps/service.lua",path="/apps/service",requirements={},desktop={visible=true,order=5},service=true},
    {id="servicefail",name="Service Failure",iconId="servicefail",defaultWidth=200,defaultHeight=120,
        entryPath="/apps/servicefail.lua",path="/apps/servicefail",requirements={},desktop={visible=true,order=6},service=true},
    {id="broken",name="Broken",iconId="broken",defaultWidth=200,defaultHeight=120,
        entryPath="/apps/broken.lua",path="/apps/broken",requirements={},desktop={visible=true,order=7}},
    {id="missing",name="Missing Registration",iconId="missing",defaultWidth=200,defaultHeight=120,
        entryPath="/apps/missing.lua",path="/apps/missing",requirements={},desktop={visible=true,order=8}},
    {id="invalid",name="Invalid",iconId="invalid",defaultWidth=200,defaultHeight=120,
        entryPath="/apps/invalid.lua",path="/apps/invalid",requirements={},desktop={visible=true,order=9}},
    {id="setup",name="Setup",iconId="setup",defaultWidth=300,defaultHeight=220,
        entryPath="/apps/setup.lua",path="/apps/setup",requirements={},desktop={visible=false,order=1},bootOnly=true}
}
local registry={
    scan=function() return entries end,
    requirements=function() return true,{} end,
    available=function() return true,{} end
}
local E={OS={registry={},order={}},devices={},P={error=1,textPrimary=2,textSecondary=3},errors={}}
function E.register(id,name,icon,width,height,app)
    app.id=id; app.name=name; app.iconId=icon; app.defaultWidth=width; app.defaultHeight=height
    E.OS.registry[id]=app; E.OS.order[#E.OS.order+1]=id
end
function E.logLine(level,message) E.errors[#E.errors+1]={level=level,message=message} end
local modules={
    ["/apps/good.lua"]=function(env)
        env.register("good","Old Name","old-icon",1,1,{draw=function() end})
    end,
    ["/apps/tableapp.lua"]={draw=function() end},
    ["/apps/hidden.lua"]=function(env) env.register("hidden","Hidden","hidden",200,120,{}) end,
    ["/apps/service.lua"]={attach=function(env)
        attachedService=env
        env.register("service","Old Service Name","old-service",1,1,{})
    end},
    ["/apps/servicefail.lua"]={attach=function() error("service attach failed") end},
    ["/apps/broken.lua"]=false,
    ["/apps/missing.lua"]=function() end,
    ["/apps/invalid.lua"]=42,
    ["/apps/setup.lua"]=function(env) env.register("setup","Setup","setup",300,220,{}) end
}
local function loadModule(path)
    local value=modules[path]
    if value==false then error("broken package source") end
    return value
end

local installed=AppManager.install(E,registry,loadModule,"/system/")
assert(#installed==8 and E.OS.registry.setup==nil,
    "desktop installation should exclude boot-only applications")
assert(E.OS.registry.good.name=="Good" and E.OS.registry.good.defaultWidth==220 and
    E.OS.registry.good.manifest==entries[1],
    "manifest metadata should override stale registration defaults")
assert(E.OS.registry.tableapp and E.OS.registry.service and attachedService==E,
    "table applications and service entrypoints should install through their contracts")
assert(E.OS.registry.hidden and not table.concat(E.OS.order,","):find("hidden",1,true),
    "hidden applications should be registered without appearing in desktop order")
for _,id in ipairs({"servicefail","broken","missing","invalid"}) do
    local fallback=E.OS.registry[id]
    assert(fallback and fallback.packageError and type(fallback.init)=="function" and
        type(fallback.draw)=="function","failed packages should receive a visible fallback: "..id)
end
assert(#E.errors==4,"every failed package should leave one diagnostic: "..tostring(#E.errors).." / "..
    table.concat((function() local result={} for _,item in ipairs(E.errors) do result[#result+1]=item.message end return result end)()," | "))

local bootRegistry={scan=function() return entries end}
AppManager.installBoot(E,bootRegistry,loadModule)
assert(E.OS.registry.setup and E.OS.registry.setup.bootOnly and
    not table.concat(E.OS.order,","):find("setup",1,true),
    "boot-only Setup should install separately and remain off the desktop")

print("app manager specs passed")

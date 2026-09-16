-- HCC OS v1.5 application package loader.
-- The registry owns discovery and manifest metadata; this module only loads
-- the package entrypoints into the existing Window Manager contract.

local AppManager={}

local function traceback(reason)
    return debug and debug.traceback and debug.traceback(tostring(reason),2) or tostring(reason)
end

local function applyManifest(def,entry)
    def.id=entry.id; def.iconId=entry.iconId; def.name=entry.name
    def.defaultWidth=entry.defaultWidth or def.defaultWidth; def.defaultHeight=entry.defaultHeight or def.defaultHeight
    def.desktop=entry.desktop; def.requirements=entry.requirements
    def.manifest=entry; def.packagePath=entry.path; def.entryPath=entry.entryPath
    def.bootOnly=entry.bootOnly; def.service=entry.service
end

local function visibleEntries(registry,includeBoot)
    local result={}
    for _,entry in ipairs(registry:scan()) do
        if includeBoot or not entry.bootOnly then result[#result+1]=entry end
    end
    return result
end

function AppManager.install(E,registry,loadModule,base)
    if type(registry)~="table" or type(registry.scan)~="function" then
        error("HCC OS application registry is missing",0)
    end
    local entries=visibleEntries(registry,false)
    E.appRegistry=registry
    E.appRequirements=function(def) return registry:requirements(def,E.devices) end
    E.appAvailable=function(def) return registry:available(def,E.devices) end
    for _,entry in ipairs(entries) do
        local module=loadModule(entry.entryPath)
        local ok,err
        if entry.service then
            if type(module)=="table" and type(module.attach)=="function" then
                ok,err=xpcall(function() return module.attach(E,E.HCCV15 or E.HCCV14) end,traceback)
            else
                ok,err=false,"Service app must return attach(environment, api): "..entry.id
            end
        elseif type(module)=="function" then
            ok,err=xpcall(function() return module(E) end,traceback)
        elseif type(module)=="table" then
            ok,err=xpcall(function() return E.register(entry.id,entry.name,entry.iconId,entry.defaultWidth,entry.defaultHeight,module) end,traceback)
        else
            ok,err=false,"Invalid application entry: "..entry.entryPath
        end
        if not ok then error("Application package failed: "..entry.id.."\n"..tostring(err),0) end
        local def=E.OS.registry[entry.id]
        if not def then error("Application did not register with Window Manager: "..entry.id,0) end
        applyManifest(def,entry)
    end
    local order={}
    for _,entry in ipairs(entries) do
        local def=E.OS.registry[entry.id]
        if def and def.desktop.visible~=false then order[#order+1]=entry.id end
    end
    E.OS.order=order
    E.OS.desktopPage=1; E.OS.iconIndex=1; E.OS.desktopDirty=true
    return entries
end

function AppManager.installBoot(E,registry,loadModule)
    for _,entry in ipairs(visibleEntries(registry,true)) do
        if entry.bootOnly and entry.id=="setup" then
            local module=loadModule(entry.entryPath)
            if type(module)=="function" then module(E) end
            local def=E.OS.registry[entry.id]
            if def then
                applyManifest(def,entry)
                if def.desktop.visible==false then
                    for index,id in ipairs(E.OS.order) do
                        if id==entry.id then table.remove(E.OS.order,index); break end
                    end
                end
            end
        end
    end
end

return AppManager

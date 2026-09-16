-- HCC OS v1.5 application package loader.
-- The registry owns discovery and manifest metadata; this module only loads
-- the package entrypoints into the existing Window Manager contract.

local AppManager={}
local applyManifest

local function traceback(reason)
    return debug and debug.traceback and debug.traceback(tostring(reason),2) or tostring(reason)
end

local function logFailure(E,entry,reason)
    local message="Application package failed: "..tostring(entry.id).." - "..tostring(reason)
    if type(E.logLine)=="function" then
        pcall(E.logLine,"ERROR",message)
    elseif E.context and E.context.logger and type(E.context.logger.error)=="function" then
        pcall(E.context.logger.error,E.context.logger,message)
    end
    return message
end

local function removeRegistration(E,id)
    if not E.OS then return end
    E.OS.registry[id]=nil
    local order={}
    for _,item in ipairs(E.OS.order or {}) do
        if item~=id then order[#order+1]=item end
    end
    E.OS.order=order
end

local function failedApplication(E,entry,reason)
    local message=logFailure(E,entry,reason)
    local app={id=entry.id,name=entry.name,iconId=entry.iconId,
        defaultWidth=entry.defaultWidth,defaultHeight=entry.defaultHeight,
        packageError=message}
    function app:init()
        self.packageError=message
        if type(E.errorBox)=="function" then E.errorBox(message) end
    end
    function app:draw(c)
        c:text(8,8,"APPLICATION UNAVAILABLE",E.P.error)
        c:text(8,25,"The application could not be loaded.",E.P.textPrimary)
        c:text(8,42,"Check the boot log or repair the update.",E.P.textSecondary)
        c:clipping(8,61,c.w-16,28):text(0,0,tostring(reason),E.P.textSecondary)
    end
    return app
end

local function installFallback(E,entry,reason)
    removeRegistration(E,entry.id)
    local app=failedApplication(E,entry,reason)
    E.register(entry.id,entry.name,entry.iconId,entry.defaultWidth,entry.defaultHeight,app)
    local def=E.OS.registry[entry.id]
    applyManifest(def,entry)
    return def
end

local function safeLoad(loadModule,path)
    return xpcall(function() return loadModule(path) end,traceback)
end

applyManifest=function(def,entry)
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
        local loaded,module=safeLoad(loadModule,entry.entryPath)
        local ok,err=loaded,nil
        if not loaded then
            installFallback(E,entry,module)
        elseif entry.service then
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
        if loaded and not ok then installFallback(E,entry,err) end
        local def=E.OS.registry[entry.id]
        if not def then def=installFallback(E,entry,"Application did not register with Window Manager") end
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
            local loaded,module=safeLoad(loadModule,entry.entryPath)
            local ok,err=loaded,true
            if loaded and type(module)=="function" then
                ok,err=xpcall(function() return module(E) end,traceback)
            elseif loaded then
                ok,err=false,"Invalid boot application entry: "..entry.entryPath
            end
            if not ok then installFallback(E,entry,err) end
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

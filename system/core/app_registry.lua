-- HCC OS v1.5 application registry.
-- Applications are self-describing packages:
--   /system/apps/<id>/manifest.lua
--   /system/apps/<id>/app.lua
--
-- The registry is the single source for discovery, desktop metadata and
-- peripheral capability checks. Legacy flat files remain readable during an
-- upgrade, but are never preferred over a valid package.

local Registry={}
Registry.__index=Registry

local function safeId(value)
    value=tostring(value or "")
    return value:match("^[a-z][a-z0-9_-]*$") and value or nil
end

local function safeEntry(value)
    value=tostring(value or "app.lua")
    if value:find("%z") or value:find("..",1,true) or value:find("/",1,true) or value:find("\\",1,true) then return nil end
    return value:match("^[%w_-]+%.lua$") and value or nil
end

local function readLuaTable(path)
    local file,err=fs.open(path,"r")
    if not file then return nil,err end
    local ok,source=pcall(file.readAll); pcall(file.close)
    if not ok then return nil,source end
    local chunk,loadError=load(source,"@"..path,"t",{})
    if not chunk then return nil,loadError end
    local ran,value=pcall(chunk)
    if not ran or type(value)~="table" then return nil,ran and "manifest must return a table" or value end
    return value
end

local function copy(value)
    local result={}
    for key,item in pairs(value or {}) do result[key]=item end
    return result
end

local function normaliseRequirements(value)
    local result={}
    if type(value)~="table" then return result end
    if #value>0 then
        for _,item in ipairs(value) do if type(item)=="string" and item~="" then result[#result+1]=item end end
    else
        for key,item in pairs(value) do if item==true then result[#result+1]=tostring(key) end end
    end
    table.sort(result)
    return result
end

function Registry.new(options)
    options=options or {}
    return setmetatable({root=options.root or "/.hccos/system/apps",logger=options.logger,
        entries={},byId={},errors={},generation=0},Registry)
end

function Registry:log(level,message)
    if self.logger and type(self.logger[level])=="function" then pcall(self.logger[level],self.logger,message) end
end

function Registry:manifestEntry(directory,manifest)
    local id=safeId(manifest.id or directory)
    if not id or id~=directory then return nil,"invalid application id: "..tostring(manifest.id or directory) end
    local entry=safeEntry(manifest.entry)
    if not entry then return nil,"invalid application entry for "..id end
    local desktop=type(manifest.desktop)=="table" and copy(manifest.desktop) or {}
    local window=type(manifest.window)=="table" and copy(manifest.window) or {}
    local result=copy(manifest)
    result.id=id; result.name=tostring(manifest.name or id); result.iconId=tostring(manifest.icon or manifest.iconId or id)
    result.entry=entry; result.directory=directory; result.path=fs.combine(self.root,directory)
    result.entryPath=fs.combine(result.path,entry); result.manifestPath=fs.combine(result.path,"manifest.lua")
    result.desktop=desktop; result.desktop.visible=desktop.visible~=false
    result.desktop.order=tonumber(desktop.order) or 1000
    result.desktop.column=tonumber(desktop.column); result.desktop.row=tonumber(desktop.row)
    result.window=window; result.defaultWidth=tonumber(window.width or manifest.defaultWidth) or 300
    result.defaultHeight=tonumber(window.height or manifest.defaultHeight) or 200
    result.requirements=normaliseRequirements(manifest.requirements or manifest.requires)
    result.bootOnly=manifest.bootOnly==true; result.service=manifest.service==true
    return result
end

function Registry:scan()
    local entries,errors={},{}
    local names={}
    local rootExists,rootExistsValue=pcall(fs.exists,self.root)
    local rootIsDir,rootDir=pcall(fs.isDir,self.root)
    if rootExists and rootExistsValue and rootIsDir and rootDir then
        local listed,list=pcall(fs.list,self.root)
        if listed and type(list)=="table" then names=list
        else errors[#errors+1]="cannot list application directory: "..tostring(list) end
    end
    table.sort(names)
    for _,name in ipairs(names) do
        local path=fs.combine(self.root,name)
        local dirOk,isDir=pcall(fs.isDir,path)
        local manifestOk,hasManifest=pcall(fs.exists,fs.combine(path,"manifest.lua"))
        local appOk,hasApp=pcall(fs.exists,fs.combine(path,"app.lua"))
        if dirOk and isDir and manifestOk and hasManifest and appOk and hasApp then
            local manifest,err=readLuaTable(fs.combine(path,"manifest.lua"))
            local entry,entryError=manifest and self:manifestEntry(name,manifest)
            if not entry then
                errors[#errors+1]=tostring(err or entryError or ("invalid package: "..name))
            else entries[#entries+1]=entry end
        end
    end
    -- A partially upgraded installation can still boot from the old flat
    -- catalog. This fallback is intentionally used only when no packages were
    -- found, so new packages always win and removed apps stay removed.
    if #entries==0 then
        local legacyPath=fs.combine(self.root,"app_catalog.lua")
        local legacy=fs.exists(legacyPath) and readLuaTable(legacyPath) or nil
        if type(legacy)=="table" then
            for _,item in ipairs(legacy) do
                local id=safeId(item.id); local moduleName=item.module or id; local module=moduleName and safeEntry(moduleName..".lua")
                if id and module and fs.exists(fs.combine(self.root,module)) then
                    entries[#entries+1]={id=id,name=tostring(item.name or id),iconId=id,entry=module,
                        entryPath=fs.combine(self.root,module),manifestPath=legacyPath,path=self.root,
                        desktop={visible=id~="setup",order=#entries+1},window={},
                        requirements=normaliseRequirements(item.requirements),service=id=="updates",bootOnly=id=="setup",legacy=true}
                end
            end
        end
    end
    table.sort(entries,function(a,b)
        if a.desktop.order~=b.desktop.order then return a.desktop.order<b.desktop.order end
        return a.id<b.id
    end)
    self.entries,self.byId,self.errors=entries,{},errors
    for _,entry in ipairs(entries) do self.byId[entry.id]=entry end
    self.generation=self.generation+1
    for _,message in ipairs(errors) do self:log("warn","App registry: "..message) end
    return entries
end

function Registry:entry(id)
    return self.byId[tostring(id)]
end

function Registry:requirements(def,devices)
    local missing={}; devices=devices or {}
    local checks={
        gpu={ok=devices.gpuAvailable==true,label="Tom's GPU"},
        keyboard={ok=devices.keyboardAvailable==true,label="Tom's keyboard"},
        peripheral={ok=#(devices.list or {})>0,label="peripheral"},
        detector={ok=devices.detector~=nil or devices.detectorAvailable==true,label="Player Detector"},
        modem={ok=#(devices.modems or {})>0,label="modem"},
        inventory={ok=#(devices.inventories or {})>0,label="inventory peripheral"}
    }
    for _,requirement in ipairs((def and def.requirements) or {}) do
        local check=checks[requirement]
        if check and not check.ok then missing[#missing+1]=check.label
        elseif not check then missing[#missing+1]=requirement end
    end
    return #missing==0,missing
end

function Registry:available(def,devices)
    local ok,missing=self:requirements(def,devices)
    return ok,missing
end

return {new=function(options) return Registry.new(options) end}

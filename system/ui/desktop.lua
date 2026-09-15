local Desktop = {}

local function loadModule(path)
    local file, err = fs.open(path, "r")
    if not file then error(err or ("Missing module: "..path), 0) end
    local source = file.readAll()
    file.close()
    local chunk, loadError = load(source, "@"..path, "t", _ENV)
    if not chunk then error(loadError or ("Could not load module: "..path), 0) end
    local ok, value = xpcall(chunk, function(reason)
        return tostring(reason or "Unknown application module failure")
    end)
    if not ok then error(value, 0) end
    return value
end

local function makeEnvironment(context, appModules)
    local environment = {
        context=context, palette={accent=0xFF46CFF0, textPrimary=0xFFF0F5FA,
            textSecondary=0xFFACBDCB, panelBackground=0xFF202B36, error=0xFFFF6978},
        apps=appModules, mark=function() end
    }
    function environment.register(id, name, icon, width, height, app)
        appModules[id] = {id=id, name=name, icon=icon, width=width, height=height, app=app}
    end
    function environment.button(app, canvas, x, y, width, label, action)
        if canvas and canvas.text then canvas:text(x+4, y+3, label, environment.palette.textPrimary) end
        if app and app.win then
            app.win.buttons = app.win.buttons or {}
            app.win.buttons[#app.win.buttons+1] = {x=x, y=y, w=width, h=16, action=action}
        end
    end
    return environment
end

local function readCatalog(catalog)
    if type(catalog) ~= "table" then error("v1.4 application catalog is missing", 0) end
    local modules, ordered = {}, {}
    for _, entry in ipairs(catalog) do
        if type(entry) ~= "table" or type(entry.id) ~= "string" then
            error("Invalid v1.4 application catalog entry", 0)
        end
        local module = loadModule("/.hccos/system/apps/"..entry.id..".lua")
        modules[entry.id] = module
        ordered[#ordered+1] = {id=entry.id, name=entry.name or module.name or entry.id,
            source=entry.source or "module", module=module}
    end
    return modules, ordered
end

local function drawDesktop(ordered, selected, message)
    term.clear()
    term.setCursorPos(1, 1)
    print("HCC OS v1.4.0 Desktop")
    print("System modules: /.hccos/system/core, ui, apps")
    print("")
    for index, app in ipairs(ordered) do
        local prefix = index == selected and "> " or "  "
        print(prefix..tostring(index)..". "..tostring(app.name))
    end
    print("")
    if message and message ~= "" then print(message) end
    print("UP/DOWN select  ENTER open  R recovery  Q shell")
end

function Desktop.run(context, catalog)
    local modules, ordered = readCatalog(catalog)
    local environment = makeEnvironment(context, modules)
    if context and context.ui then environment.ui = context.ui end
    if modules.updates and type(modules.updates.attach) == "function" then
        modules.updates.attach(environment, _G.HCCV14)
    elseif _G.HCCV14 and type(_G.HCCV14.attachApp) == "function" then
        _G.HCCV14.attachApp(environment)
    end
    local selected, message = 1, "Ready"
    while true do
        drawDesktop(ordered, selected, message)
        local event, key = os.pullEventRaw("key")
        if event == "key" then
            if key == keys.up then selected = (selected-2)%#ordered+1
            elseif key == keys.down then selected = selected%#ordered+1
            elseif key == keys.enter then
                local app = ordered[selected]
                message = tostring(app.name).." is registered as a v1.4 module."
            elseif key == keys.r then
                if context and type(context.enterRecovery) == "function" then
                    return context.enterRecovery("manual recovery request")
                end
                return "recovery"
            elseif key == keys.q or key == keys.escape then
                return "stopped"
            end
        end
    end
end

return Desktop

local Bridge = {}

local function errorText(value)
    local text = tostring(value or "")
    if text == "" or text == "nil" then text = "Unknown desktop start failure" end
    return text
end

local function traceback(value)
    local text = errorText(value)
    if type(debug) == "table" and type(debug.traceback) == "function" then
        local ok, result = pcall(debug.traceback, text, 2)
        if ok and type(result) == "string" and result ~= "" then return result end
    end
    return text
end

function Bridge.find(paths)
    local candidates = {paths.legacy, "/hcc_os/legacy/hccos_v1.3.3.lua", "/hccos.lua"}
    for _, path in ipairs(candidates) do
        if fs.exists(path) and not fs.isDir(path) then return path end
    end
    return nil
end

function Bridge.run(paths, logger)
    local path = Bridge.find(paths)
    if not path then return false, "v1.3.3 compatibility application pack is missing" end
    local f, err = fs.open(path, "r")
    if not f then return false, err end
    local source = f.readAll()
    f.close()
    local chunk, loadError = load(source, "@"..path, "t", _ENV)
    if not chunk then return false, errorText(loadError) end
    logger:info("Starting legacy-compatible HCC application pack: "..path)
    local ok, runError = xpcall(chunk, traceback)
    return ok, runError
end

return Bridge

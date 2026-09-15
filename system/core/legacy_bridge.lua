local Bridge = {}

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
    if not chunk then return false, loadError end
    logger:info("Starting legacy-compatible HCC application pack: "..path)
    local ok, runError = pcall(chunk)
    return ok, runError
end

return Bridge

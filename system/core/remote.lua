-- The only module that owns the public GitHub endpoints.
local Remote = {}
Remote.repository = "https://github.com/himantel/hcc-os"
Remote.rawRoot = "https://raw.githubusercontent.com/himantel/hcc-os/main"
Remote.manifestPath = "hcc_os/manifest.lua"

local function safeUrl(url)
    return type(url) == "string" and #url < 512 and url:match("^https://[^%s]+$") and url or nil
end

local function loadLuaTable(source, name)
    local chunk, err = load(source, "@"..name, "t", {})
    if not chunk then return nil, err end
    local ok, value = pcall(chunk)
    if not ok or type(value) ~= "table" then return nil, "manifest is not a table" end
    return value
end

function Remote.parseManifest(source)
    return loadLuaTable(source, "remote manifest")
end

function Remote.manifestUrl(config)
    local root = config and config.updateRepository or Remote.repository
    if type(root) ~= "string" or root == "" then root = Remote.repository end
    root = root:gsub("/$", "")
    local raw = root:gsub("github%.com/", "raw.githubusercontent.com/")
    if raw:match("raw%.githubusercontent%.com") then
        return raw.."/main/"..Remote.manifestPath
    end
    return Remote.rawRoot.."/"..Remote.manifestPath
end

function Remote.fileUrl(relative, config)
    relative = tostring(relative or "")
    local root = Remote.manifestUrl(config):gsub("/"..Remote.manifestPath.."$", "")
    if relative == "manifest.lua" then return root.."/"..Remote.manifestPath end
    return root.."/hcc_os/system/"..relative
end

function Remote.rootFileUrl(relative, config)
    relative = tostring(relative or "")
    local root = Remote.manifestUrl(config):gsub("/"..Remote.manifestPath.."$", "")
    return root.."/"..relative
end

function Remote.fetch(url)
    url = safeUrl(url)
    if not url then return nil, "invalid HTTPS URL" end
    if type(http) ~= "table" or type(http.get) ~= "function" then return nil, "HTTP API unavailable" end
    local ok, handle = pcall(http.get, url, { ["User-Agent"] = "HCC-OS/1.4.0" })
    if not ok or not handle then return nil, tostring(handle or "HTTP request denied") end
    local readOk, body = pcall(handle.readAll)
    local code = 200
    if type(handle.getResponseCode) == "function" then
        local codeOk, responseCode = pcall(handle.getResponseCode)
        if codeOk and responseCode then code = responseCode end
    end
    if handle.close then pcall(handle.close) end
    if not readOk or code < 200 or code >= 300 then return nil, "HTTP "..tostring(code) end
    return body
end

function Remote.fetchManifest(config)
    local url = Remote.manifestUrl(config)
    local body, err = Remote.fetch(url)
    if not body then return nil, err end
    local manifest, parseError = Remote.parseManifest(body)
    if not manifest then return nil, parseError end
    return manifest
end

function Remote.check(config, localManifest)
    local manifest, err = Remote.fetchManifest(config)
    if not manifest then return nil, err end
    local localBuild = tonumber(localManifest and localManifest.build) or 0
    local remoteBuild = tonumber(manifest.build) or 0
    return {
        available = remoteBuild > localBuild,
        localVersion = tostring(localManifest and localManifest.version or "unknown"),
        remoteVersion = tostring(manifest.version or "unknown"),
        localBuild = localBuild,
        remoteBuild = remoteBuild,
        manifest = manifest
    }
end

return Remote

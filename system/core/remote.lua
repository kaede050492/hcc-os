-- The only module that owns the public GitHub endpoints.
local Remote = {}
Remote.repository = "https://github.com/kaede050492/hcc-os"
Remote.rawRoot = "https://raw.githubusercontent.com/kaede050492/hcc-os/main"
Remote.manifestPath = "manifest.lua"

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

local function compareVersion(left, right)
    local function parts(value)
        local result = {}
        for number in tostring(value or "0"):gmatch("%d+") do result[#result+1] = tonumber(number) or 0 end
        if #result == 0 then result[1] = 0 end
        return result
    end
    local a, b = parts(left), parts(right)
    for index = 1, math.max(#a, #b) do
        local av, bv = a[index] or 0, b[index] or 0
        if av ~= bv then return av > bv and 1 or -1 end
    end
    return 0
end

local function revisionOf(manifest)
    if type(manifest) ~= "table" then return "", "none" end
    if manifest.revision ~= nil and tostring(manifest.revision) ~= "" then return tostring(manifest.revision), "revision" end
    if manifest.build ~= nil and tostring(manifest.build) ~= "" then return tostring(manifest.build), "build" end
    return "", "none"
end

local function compareRevision(left, right)
    if left == right then return 0 end
    local function parts(value)
        local result = {}
        for number in tostring(value or ""):gmatch("%d+") do result[#result+1] = tonumber(number) or 0 end
        return result
    end
    local a, b = parts(left), parts(right)
    if #a > 0 and #b > 0 then
        for index = 1, math.max(#a, #b) do
            local av, bv = a[index] or 0, b[index] or 0
            if av ~= bv then return av > bv and 1 or -1 end
        end
    end
    return tostring(left) > tostring(right) and 1 or -1
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
    return root.."/system/"..relative
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
    local ok, handle, requestError = pcall(http.get, url)
    if not ok then return nil, tostring(handle or "HTTP request failed") end
    if not handle then return nil, tostring(requestError or "HTTP request denied") end
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

function Remote.compareManifests(localManifest, manifest)
    if type(manifest) ~= "table" then return nil, "remote manifest is invalid" end
    local localVersion = tostring(localManifest and localManifest.version or "unknown")
    local remoteVersion = tostring(manifest.version or "unknown")
    local localRevision, localRevisionKind = revisionOf(localManifest)
    local remoteRevision, remoteRevisionKind = revisionOf(manifest)
    local versionComparison = compareVersion(remoteVersion, localVersion)
    local revisionComparison = versionComparison == 0 and compareRevision(remoteRevision, localRevision) or 0
    local available = versionComparison > 0 or (versionComparison == 0 and revisionComparison > 0)
    return {
        available = available,
        refreshAvailable = versionComparison == 0 and revisionComparison == 0,
        downgradeBlocked = versionComparison < 0 or (versionComparison == 0 and revisionComparison < 0),
        localVersion = localVersion,
        remoteVersion = remoteVersion,
        localRevision = localRevision,
        remoteRevision = remoteRevision,
        localRevisionKind = localRevisionKind,
        remoteRevisionKind = remoteRevisionKind,
        localBuild = tonumber(localManifest and localManifest.build) or 0,
        remoteBuild = tonumber(manifest.build) or 0,
        manifest = manifest
    }
end

function Remote.check(config, localManifest)
    local manifest, err = Remote.fetchManifest(config)
    if not manifest then return nil, err end
    return Remote.compareManifests(localManifest, manifest)
end

return Remote

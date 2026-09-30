-- Run with a Lua 5.2+ interpreter from the repository root:
--   lua tests/app_registry_spec.lua

local function newFixture(entryPath, includeEntry)
    local root = "/fixture/apps"
    local package = root.."/sample"
    local manifestPath = package.."/manifest.lua"
    local files = {
        [manifestPath] = "return { id='sample', name='Sample', entry='"..entryPath.."' }"
    }
    if includeEntry then files[package.."/"..entryPath] = "return {}" end
    local directories = {[root]=true,[package]=true}

    local function combine(first, second)
        local left = tostring(first or ""):gsub("/+$", "")
        local right = tostring(second or ""):gsub("^/+", "")
        if left == "" then return "/"..right end
        if right == "" then return left end
        return left.."/"..right
    end

    local api = {
        combine=combine,
        exists=function(path) return files[path] ~= nil or directories[path] == true end,
        isDir=function(path) return directories[path] == true end,
        list=function(path)
            if path ~= root then error("unexpected list path: "..tostring(path)) end
            return {"sample"}
        end,
        open=function(path, mode)
            if mode ~= "r" or not files[path] then return nil, "missing fixture file" end
            local source = files[path]
            return {readAll=function() return source end, close=function() end}
        end
    }
    return api, root, package
end

local function registryFor(api, root)
    local environment = setmetatable({fs=api}, {__index=_G})
    local chunk, loadError = loadfile("system/core/app_registry.lua", "t", environment)
    assert(chunk, loadError)
    local module = chunk()
    return module.new({root=root})
end

do
    local api, root, package = newFixture("main_screen.lua", true)
    local registry = registryFor(api, root)
    local entries = registry:scan()
    assert(#entries == 1, "a valid custom entry should be discovered")
    assert(entries[1].entryPath == package.."/main_screen.lua", "the declared entry path should be loaded")
    assert(#registry.errors == 0, "a valid custom entry should not produce diagnostics")
end

do
    local api, root = newFixture("missing.lua", false)
    local registry = registryFor(api, root)
    assert(#registry:scan() == 0, "a missing custom entry must not be registered")
    assert(#registry.errors == 1 and registry.errors[1]:find("missing.lua", 1, true),
        "a missing custom entry should produce a useful diagnostic")
end

do
    local api, root = newFixture("../escape.lua", true)
    local registry = registryFor(api, root)
    assert(#registry:scan() == 0, "a traversal entry must not be registered")
    assert(#registry.errors == 1, "an unsafe entry should produce a package diagnostic")
end

print("app registry specs passed")

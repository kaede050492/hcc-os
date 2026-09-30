-- Run from the repository root with Lua 5.2 or newer:
--   lua tests/run.lua

local specs={
    "tests/app_registry_spec.lua",
    "tests/app_manager_spec.lua",
    "tests/app_modules_spec.lua",
    "tests/desktop_lifecycle_spec.lua",
    "tests/ui_layout_spec.lua",
    "tests/scheduler_spec.lua",
    "tests/image_codec_spec.lua",
    "tests/startup_spec.lua",
    "tests/module_loader_spec.lua",
    "tests/file_service_spec.lua",
    "tests/http_service_spec.lua",
    "tests/capabilities_spec.lua",
    "tests/performance_spec.lua",
    "tests/config_spec.lua",
    "tests/window_manager_spec.lua",
    "tests/input_spec.lua",
    "tests/color_spec.lua",
    "tests/runtime_theme_spec.lua"
}

for _,path in ipairs(specs) do
    local chunk,loadError=loadfile(path)
    assert(chunk,loadError)
    local ok,runError=pcall(chunk)
    if not ok then error(path..": "..tostring(runError),0) end
end

print("all HCC OS specs passed")

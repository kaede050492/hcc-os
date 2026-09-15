-- Setup is executed by core/setup.lua before the desktop starts. This module
-- keeps the application catalog complete for installers and future UI routing.
return {id="setup", name="Setup", kind="firstboot", source="core/setup.lua"}

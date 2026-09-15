-- Recovery Mode is executed by core/recovery.lua and intentionally remains
-- available even when the normal desktop application pack cannot start.
return {id="recovery", name="Recovery Mode", kind="boot", source="core/recovery.lua"}

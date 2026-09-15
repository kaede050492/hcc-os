-- Installer package copy of the minimal root boot loader.
local source = "/hcc_os/boot.lua"
if fs.exists(source) then
    local f = fs.open(source, "r")
    local text = f.readAll(); f.close()
    local chunk, err = load(text, "@"..source, "t", _ENV)
    if not chunk then error(err) end
    chunk()
else
    print("[HCC OS] /hcc_os/boot.lua is missing")
end

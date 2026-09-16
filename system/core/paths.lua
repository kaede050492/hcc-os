-- Canonical HCC OS paths. User data is never inside SYSTEM_ROOT.

return {
    version = "1.5.0",
    system = "/.hccos/system",
    core = "/.hccos/system/core",
    ui = "/.hccos/system/ui",
    apps = "/.hccos/system/apps",
    versionFile = "/.hccos/system/version.lua",
    config = "/.hccos/config",
    settings = "/.hccos/config/settings",
    legacySettings = "/.hccos/settings",
    images = "/.hccos/images",
    cache = "/.hccos/cache",
    downloads = "/.hccos/downloads",
    logs = "/.hccos/logs",
    backups = "/.hccos/backups",
    temp = "/.hccos/temp",
    updateTemp = "/.hccos/temp/update",
    currency = "/.hccos/currency",
    currencyBackup = "/.hccos/currency.bak",
    startup = "/startup.lua",
    manifest = "/.hccos/system/manifest.lua"
}

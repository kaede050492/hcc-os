-- HCC OS v1.5 application catalog. Applications are loaded from the
-- corresponding system/apps module and are not executed through the legacy pack.

return {
    {id="clock", name="Clock", source="module"},
    {id="calendar", name="Calendar", source="module"},
    {id="radar", name="Player Radar", source="module"},
    {id="server", name="Server Monitor", source="module"},
    {id="notepad", name="Notepad", source="module"},
    {id="files", name="Files", source="module"},
    {id="currency", name="Currency Calculator", source="module"},
    {id="image", name="Image Viewer", source="module"},
    {id="web", name="HCC Web", source="module"},
    {id="inventory", name="Inventory Viewer", source="module"},
    {id="peripherals", name="Peripheral Manager", source="module"},
    {id="network", name="Network Manager", source="module"},
    {id="resource", name="Resource Monitor", source="module"},
    {id="logs", name="Log Viewer", source="module"},
    {id="system", name="System Monitor", source="module"},
    {id="performance", name="Performance Graph", source="module"},
    {id="taskmgr", name="Task Manager", source="module"},
    {id="terminal", name="Terminal", source="module"},
    {id="settings", name="Settings", source="module"},
    {id="diagnostics", name="Diagnostics", source="module"},
    {id="updates", module="update_recovery", name="System Update", source="v1.5"}
}

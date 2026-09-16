-- Legacy compatibility catalog for installations that have not received the
-- manifest.lua + app.lua package layout yet. New boots use App Registry scan.

return {
    {id="clock", name="Clock", source="module"},
    {id="calendar", name="Calendar", source="module"},
    {id="radar", name="Player Radar", requirements={"detector"}, source="module"},
    {id="server", name="Server Monitor", source="module"},
    {id="notepad", name="Notepad", source="module"},
    {id="files", name="Files", source="module"},
    {id="currency", name="Currency Calculator", source="module"},
    {id="image", name="Image Viewer", source="module"},
    {id="web", name="HCC Web", source="module"},
    {id="inventory", name="Inventory Viewer", requirements={"inventory"}, source="module"},
    {id="peripherals", name="Peripheral Manager", requirements={"peripheral"}, source="module"},
    {id="network", name="Network Manager", requirements={"modem"}, source="module"},
    {id="resource", name="Resource Monitor", requirements={"inventory"}, source="module"},
    {id="logs", name="Log Viewer", source="module"},
    {id="system", name="System Monitor", source="module"},
    {id="performance", name="Performance Graph", source="module"},
    {id="taskmgr", name="Task Manager", source="module"},
    {id="terminal", name="Terminal", source="module"},
    {id="settings", name="Settings", source="module"},
    {id="diagnostics", name="Diagnostics", source="module"},
    {id="updates", module="update_recovery", name="System Update", source="v1.5.1"}
}

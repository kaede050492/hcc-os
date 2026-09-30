-- HCC OS bounded widgets. Visual-only elements do not consume pointer input;
-- interactive elements always carry an explicit callback.
local W = {}

local function requireAction(action, name)
    if type(action) ~= "function" then
        error(tostring(name or "widget") .. " action must be a function", 3)
    end
    return action
end

local function add(app, kind, x, y, w, h, value, action)
    requireAction(action, kind)
    local hit = {kind=kind, x=x, y=y, w=w, h=h, value=value, action=action}
    local win = app and (app.win or app.window)
    if win then
        win.buttons = win.buttons or {}
        win.buttons[#win.buttons+1] = hit
    end
    return hit
end

function W.panel(canvas, x, y, w, h, color, edge)
    canvas:filledRectangle(x, y, w, h, color)
    if edge ~= false then canvas:rectangle(x, y, w, h, edge) end
end

function W.label(canvas, x, y, value, color, scale)
    canvas:text(x, y, value, color, scale or 1)
end

function W.button(app, canvas, x, y, w, label, action, palette)
    palette = palette or {}
    requireAction(action, "button")
    canvas:filledRectangle(x, y, w, 16, palette.panelBackground)
    canvas:rectangle(x, y, w, 16, palette.border)
    canvas:text(x+4, y+3, label, palette.textPrimary)
    return add(app, "button", x, y, w, 16, label, action)
end

function W.iconButton(app, canvas, x, y, size, draw, action, palette)
    palette = palette or {}
    requireAction(action, "icon button")
    W.panel(canvas, x, y, size, size, palette.panelBackground, palette.border)
    if draw ~= nil then
        if type(draw) ~= "function" then error("icon drawing callback must be a function", 2) end
        draw(canvas, x+2, y+2, size-4)
    end
    return add(app, "icon", x, y, size, size, nil, action)
end

function W.textBox(app, canvas, x, y, w, value, palette)
    palette = palette or {}
    W.panel(canvas, x, y, w, 18, palette.panelBackground, palette.border)
    canvas:clipping(x+4, y+4, w-8, 10):text(0, 0, tostring(value or ""), palette.textPrimary)
end

function W.numberBox(app, canvas, x, y, w, value, palette)
    W.textBox(app, canvas, x, y, w, tostring(value or 0), palette)
end

function W.checkbox(app, canvas, x, y, label, value, action, palette)
    palette = palette or {}
    requireAction(action, "checkbox")
    W.panel(canvas, x, y, 13, 13, palette.windowBackground, palette.border)
    if value then canvas:filledRectangle(x+3, y+3, 7, 7, palette.accent) end
    canvas:text(x+18, y+2, label, palette.textPrimary)
    return add(app, "checkbox", x, y, 18+#tostring(label or "")*6, 14, value,
        function() action(not value) end)
end

function W.slider(app, canvas, x, y, w, value, minimum, maximum, action, palette)
    palette = palette or {}
    requireAction(action, "slider")
    minimum, maximum = tonumber(minimum) or 0, tonumber(maximum) or 1
    if maximum < minimum then maximum = minimum end
    value = tonumber(value) or minimum
    value = math.max(minimum, math.min(maximum, value))
    W.panel(canvas, x, y, w, 8, palette.windowBackground, palette.border)
    local ratio = maximum > minimum and (value-minimum)/(maximum-minimum) or 0
    local fillWidth = math.max(0, math.floor((w-2)*ratio))
    if fillWidth > 0 then canvas:filledRectangle(x+1, y+1, fillWidth, 6, palette.accent) end
    return add(app, "slider", x, y, w, 10, value, function(localX)
        local usable = math.max(1, w-1)
        local nextRatio = math.max(0, math.min(1, (tonumber(localX) or 0)/usable))
        action(minimum+(maximum-minimum)*nextRatio)
    end)
end

function W.listView(app, canvas, x, y, w, h, rows, selected, palette, action)
    palette = palette or {}
    local view = canvas:clipping(x, y, w, h)
    W.panel(view, 0, 0, w, h, palette.windowBackground, palette.border)
    for i, row in ipairs(rows or {}) do
        local rowY = 2+(i-1)*14
        if rowY+13 > h then break end
        if i == selected then view:filledRectangle(1, rowY, w-2, 13, palette.panelBackground) end
        view:text(4, rowY+2, tostring(row), palette.textPrimary)
        if type(action) == "function" then
            local index, item = i, row
            add(app, "list", x+1, y+rowY, math.max(1, w-2), 13, item,
                function() action(index, item) end)
        end
    end
end

function W.scrollView(canvas, x, y, w, h)
    return canvas:clipping(x, y, w, h)
end

function W.dropdown(app, canvas, x, y, w, value, action, palette)
    palette = palette or {}
    requireAction(action, "dropdown")
    W.panel(canvas, x, y, w, 18, palette.panelBackground, palette.border)
    canvas:clipping(x+4, y+4, w-20, 10):text(0, 0, tostring(value or ""), palette.textPrimary)
    canvas:text(x+w-12, y+4, "v", palette.accent)
    return add(app, "dropdown", x, y, w, 18, value, function() action() end)
end

function W.tabs(app, canvas, x, y, w, items, selected, action, palette)
    palette = palette or {}
    requireAction(action, "tabs")
    items = type(items) == "table" and items or {}
    if #items == 0 or w < #items then return end
    local each = math.floor(w/#items)
    for i, item in ipairs(items) do
        local index = i
        local buttonWidth = math.max(1, math.min(each-2, w-(i-1)*each))
        W.button(app, canvas, x+(i-1)*each, y, buttonWidth, item,
            function() action(index) end, {
                panelBackground=i == selected and palette.border or palette.panelBackground,
                border=palette.border,
                textPrimary=palette.textPrimary
            })
    end
end

function W.contextMenu(app, canvas, x, y, w, items, palette)
    palette = palette or {}
    items = type(items) == "table" and items or {}
    local h = #items*18+2
    W.panel(canvas, x, y, w, h, palette.windowBackground, palette.accent)
    for i, item in ipairs(items) do
        local label, action, disabled
        if type(item) == "table" then
            label, action, disabled = item.label or item[1], item.action or item[2], item.disabled == true
        else
            label = tostring(item or "")
        end
        local rowY = y+1+(i-1)*18
        canvas:text(x+6, y+5+(i-1)*18, tostring(label or ""), disabled and palette.textSecondary or palette.textPrimary)
        if not disabled and type(action) == "function" then
            add(app, "menu", x+1, rowY, w-2, 18, item, action)
        end
    end
end

function W.dialog(canvas, x, y, w, h, title, message, palette)
    palette = palette or {}
    W.panel(canvas, x, y, w, h, palette.windowBackground, palette.accent)
    canvas:filledRectangle(x+1, y+1, w-2, 18, palette.panelBackground)
    canvas:text(x+7, y+5, title, palette.accent)
    canvas:paragraph(x+7, y+27, message, palette.textPrimary, w-14,
        math.max(1, math.floor((h-34)/12)))
end

function W.tooltip(canvas, x, y, text, palette)
    palette = palette or {}
    text = tostring(text or "")
    local w = math.max(1, math.min(canvas.w-x, 8+#text*6))
    W.panel(canvas, x, y, w, 16, palette.panelBackground, palette.border)
    canvas:text(x+4, y+3, text, palette.textPrimary)
end

function W.progress(canvas, x, y, w, h, value, limit, color, background)
    limit = tonumber(limit) or 1
    if limit <= 0 then limit = 1 end
    value = math.max(0, math.min(limit, tonumber(value) or 0))
    W.panel(canvas, x, y, w, h, background, false)
    if value > 0 and w > 2 and h > 2 then
        canvas:filledRectangle(x+1, y+1, math.floor((w-2)*value/limit), h-2, color)
    end
end

function W.progressBar(...)
    return W.progress(...)
end

function W.graph(canvas, x, y, w, h, values, color, limit, palette)
    palette = palette or {}
    W.panel(canvas, x, y, w, h, palette.windowBackground, palette.border)
    limit = tonumber(limit) or 1
    if limit <= 0 or w <= 3 or h <= 3 then return end
    for i=2, #values do
        local x1 = x+1+math.floor((i-2)*(w-3)/math.max(1, #values-1))
        local x2 = x+1+math.floor((i-1)*(w-3)/math.max(1, #values-1))
        local v1 = math.max(0, math.min(1, (tonumber(values[i-1]) or 0)/limit))
        local v2 = math.max(0, math.min(1, (tonumber(values[i]) or 0)/limit))
        local y1 = y+h-2-math.floor(v1*(h-3))
        local y2 = y+h-2-math.floor(v2*(h-3))
        canvas:line(x1, y1, x2, y2, color)
    end
end

function W.splitter(app, canvas, x, y, w, h, vertical, action, palette)
    palette = palette or {}
    requireAction(action, "splitter")
    canvas:filledRectangle(x, y, w, h, palette.border)
    return add(app, "splitter", x, y, w, h, vertical, action)
end

function W.icon(canvas, x, y, definition, selected)
    if W.drawIcon then
        W.drawIcon(canvas, definition, x, y, 28, selected and "selected" or "normal")
    end
end

function W.value(canvas, x, y, label, value, color, palette)
    palette = palette or {}
    canvas:text(x, y, label, palette.textSecondary)
    canvas:text(x+#tostring(label or "")*6+5, y, value, color or palette.textPrimary)
end

return W

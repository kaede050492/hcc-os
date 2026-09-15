-- UI module boundary for v1.4.0. The legacy desktop supplies the compatible
-- Canvas widget implementation while new screens use these helpers.
return {
    panel = function(canvas, x, y, w, h, fill, edge)
        canvas:filledRectangle(x, y, w, h, fill)
        if edge ~= false then canvas:rectangle(x, y, w, h, edge) end
    end,
    label = function(canvas, x, y, value, color, scale) canvas:text(x, y, value, color, scale) end
}

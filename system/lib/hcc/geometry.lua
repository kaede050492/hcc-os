-- HCC OS v1.5 shared geometry module.
-- This is deliberately dependency-free so it can also be installed as an
-- external module under /.hccos/lib or /lib.

local Geometry = {}
local floor, min, max = math.floor, math.min, math.max

local function number(value, fallback)
    value = tonumber(value)
    return value == value and value or fallback
end

function Geometry.rect(x, y, w, h)
    return {
        x = floor(number(x, 0)), y = floor(number(y, 0)),
        w = max(0, floor(number(w, 0))), h = max(0, floor(number(h, 0)))
    }
end

function Geometry.copy(rect)
    return Geometry.rect(rect.x, rect.y, rect.w, rect.h)
end

function Geometry.right(rect) return rect.x + rect.w end
function Geometry.bottom(rect) return rect.y + rect.h end

function Geometry.contains(rect, x, y)
    return rect and x >= rect.x and y >= rect.y and x < Geometry.right(rect) and y < Geometry.bottom(rect)
end

function Geometry.intersect(a, b)
    if not a or not b then return nil end
    local x, y = max(a.x, b.x), max(a.y, b.y)
    local r, bottom = min(Geometry.right(a), Geometry.right(b)), min(Geometry.bottom(a), Geometry.bottom(b))
    if r <= x or bottom <= y then return nil end
    return Geometry.rect(x, y, r - x, bottom - y)
end

function Geometry.union(a, b)
    if not a then return Geometry.copy(b) end
    if not b then return Geometry.copy(a) end
    local x, y = min(a.x, b.x), min(a.y, b.y)
    return Geometry.rect(x, y, max(Geometry.right(a), Geometry.right(b)) - x,
        max(Geometry.bottom(a), Geometry.bottom(b)) - y)
end

function Geometry.inset(rect, amount)
    amount = max(0, floor(number(amount, 0)))
    return Geometry.rect(rect.x + amount, rect.y + amount,
        rect.w - amount * 2, rect.h - amount * 2)
end

function Geometry.expand(rect, amount)
    amount = max(0, floor(number(amount, 0)))
    return Geometry.rect(rect.x - amount, rect.y - amount,
        rect.w + amount * 2, rect.h + amount * 2)
end

function Geometry.clampPoint(x, y, bounds)
    return max(bounds.x, min(Geometry.right(bounds) - 1, floor(number(x, bounds.x)))),
        max(bounds.y, min(Geometry.bottom(bounds) - 1, floor(number(y, bounds.y))))
end

function Geometry.near(value, target, distance)
    return math.abs(value - target) <= max(0, number(distance, 0))
end

return Geometry

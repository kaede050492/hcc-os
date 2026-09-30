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

function Geometry.roundedRectRow(rect, radius, y)
    if not rect or rect.w < 1 or rect.h < 1 or y < rect.y or y >= Geometry.bottom(rect) then return nil end
    radius = math.max(0, math.min(floor(number(radius, 0)), floor(math.min(rect.w, rect.h) / 2)))
    if radius == 0 then return rect.x, Geometry.right(rect) end
    local row = y - rect.y
    local verticalDistance = 0
    if row < radius then verticalDistance = radius - (row + 0.5)
    elseif row >= rect.h - radius then verticalDistance = (row + 0.5) - (rect.h - radius) end
    local halfWidth = math.sqrt(math.max(0, radius * radius - verticalDistance * verticalDistance))
    local inset = math.max(0, math.min(floor(rect.w / 2), math.ceil(radius - halfWidth - 0.5)))
    return rect.x + inset, Geometry.right(rect) - inset
end

function Geometry.roundedContains(rect, radius, x, y)
    if not Geometry.contains(rect, x, y) then return false end
    local left, right = Geometry.roundedRectRow(rect, radius, y)
    return left ~= nil and x >= left and x < right
end

function Geometry.roundedContainsRect(rect, radius, area)
    if not rect or not area or area.w < 1 or area.h < 1 then return false end
    local right, bottom = Geometry.right(area) - 1, Geometry.bottom(area) - 1
    return Geometry.roundedContains(rect, radius, area.x, area.y) and
        Geometry.roundedContains(rect, radius, right, area.y) and
        Geometry.roundedContains(rect, radius, area.x, bottom) and
        Geometry.roundedContains(rect, radius, right, bottom)
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

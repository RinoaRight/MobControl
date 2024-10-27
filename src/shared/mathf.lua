--!strict
--!native
-- MIT License
-- Copyright (c) 2022-2024 Andrew Zhilin (https://github.com/zoon)
--
--[=[
    Header
    Usage:
    ```lua
    local x = ...
    ```
--]=]

type str = string
type bool = boolean
type num = number
type integer = num
type uint = integer
type int = integer
type u32 = uint
type i32 = int
type u8 = uint
type id = int
type vec = Vector3
type cf = CFrame
type array<a> = { a }
type table = { [any]: any }
type map<k, v> = { [k]: vec }
type fun = (...any) -> ...any

local _fmt = string.format

----------------------------
-- Module
-----------------------------
local m = {}
m.__index = m

local PI_2 = 2 * math.pi
local PI_4 = 2 * PI_2

local function asinh(x: num)
    return math.log(x + math.sqrt(x * x + 1))
end
m.asinh = asinh

function m.catenary(p0: vec, p1: vec, length: num, segments: int?, out_points: array<vec>?): (num, num?, int)
    local v = p1.Y - p0.Y
    if v < 0 then
        p0, p1 = p1, p0
        v *= -1
    end
    local TINY = 2 ^ -8
    local p2 = Vector3.new(p1.X, p0.Y, p1.Z)
    local h = (p2 - p0).Magnitude
    local hh = 0.5 * h
    local distance = (p1 - p0).Magnitude
    local is_line = length - distance <= TINY
    local iteration = 0
    local a: num
    if h < TINY and not is_line then -- vertical line with overhang
        a = TINY ---@todo: do not working - to think about
    elseif is_line then -- tight line
        a = math.huge
        length = distance
    else -- catenary
        local c = 0.5 * math.sqrt(length * length - v * v)
        local a_min = 0
        local a_max = 4 * TINY
        -- upper bound
        while c < a_max * math.sinh(hh / a_max) do
            a_min = a_max
            a_max *= 2
        end
        repeat -- bisect
            a = 0.5 * (a_min + a_max)
            iteration += 1
            if c < a * math.sinh(hh / a) then
                a_min = a
            else
                a_max = a
            end
        ---@note: `a_max < TINY` for almost vertical catenary, iteration always < 10
        until (a_max - a_min) / a_max < TINY or a_max < TINY
        assert(iteration <= 10, "too many iterations")
    end
    -- calculate points only if out array provided
    if out_points then
        assert(segments and segments > 0, "must specify the number of segments")
        table.clear(out_points)
    else
        return a, nil, iteration
    end
    local seg_len = length / segments
    out_points[1] = p0
    if 0 < a and a < math.huge then
        -- vertex
        local x0 = hh - a * asinh(v / (2 * a * math.sinh(hh / a)))
        local y0 = -a * math.cosh(x0 / a)
        warn("x0", x0, "y0", y0)

        local hdir = (p2 - p0).Unit -- horizontal vector towards target
        for i = 2, segments do
            local cat_len = (i - 1) * seg_len
            -- catenary length at [0..x] = a*sinh(x/a)
            local x = x0 + a * asinh(cat_len / a - math.sinh(x0 / a))
            local y = y0 + a * math.cosh((x - x0) / a)
            local hp = p0 + x * hdir
            out_points[i] = Vector3.new(hp.X, hp.Y + y, hp.Z)
        end
    elseif a == 0 then -- vertical with overhang
        -- TODO: to think
    else -- line
        local dir = (p1 - p0).Unit
        for i = 2, segments do
            out_points[i] = p0 + ((i - 1) * seg_len) * dir
        end
    end
    out_points[segments + 1] = p1
    return a, seg_len, iteration
end
function m.catenary2(p0: vec, p1: vec, length: num, segments: int?, out_points: array<vec>?): (num, num?, int)
    local v = p1.Y - p0.Y
    if v < 0 then
        p0, p1 = p1, p0
        v *= -1
    end
    local TINY = 2 ^ -8
    local p2 = Vector3.new(p1.X, p0.Y, p1.Z)
    local h = (p2 - p0).Magnitude
    local hh = 0.5 * h
    local distance = (p1 - p0).Magnitude
    local is_line = length - distance <= TINY
    local iteration = 0
    local a: num
    if h < 0.01 and not is_line then -- vertical line with overhang
        a = 0
    elseif is_line then -- tight line
        a = math.huge
        length = distance
    else -- catenary
        local c = 0.5 * math.sqrt(length * length - v * v)
        local a_min = 0
        local a_max = 4 * TINY
        -- upper bound
        while c < a_max * math.sinh(hh / a_max) do
            a_min = a_max
            a_max *= 2
        end
        repeat -- bisect
            a = 0.5 * (a_min + a_max)
            iteration += 1
            if c < a * math.sinh(hh / a) then
                a_min = a
            else
                a_max = a
            end
        ---@note: `a_max < TINY` for almost vertical catenary, iteration always < 10
        until (a_max - a_min) / a_max < TINY or a_max < TINY
        assert(iteration <= 16, "too many iterations")
    end
    -- calculate points only if out array provided
    if out_points then
        assert(segments and segments > 0, "must specify the number of segments")
        table.clear(out_points)
    else
        return a, nil, iteration
    end
    local seg_len = length / segments
    out_points[1] = p0
    if 0 < a and a < math.huge then
        local q = math.sinh(hh / a)
        -- vertex
        local x0 = hh - a * asinh(v / (2 * a * q))
        local y0 = -a * math.cosh(x0 / a)

        local q0 = math.sinh(x0 / a)

        local hdir = (p2 - p0).Unit -- horizontal vector towards target
        for i = 2, segments do
            local cat_len = (i - 1) * seg_len
            -- catenary length at [0..x] = a*sinh(x/a)

            local x = x0 + a * asinh(cat_len / a - q0)
            local y = y0 + a * math.cosh((x - x0) / a)
            local hp = p0 + x * hdir
            out_points[i] = Vector3.new(hp.X, hp.Y + y, hp.Z)
        end
    elseif a == 0 then -- vertical with overhang
        local seg0 = 0.5 * (length - v)
        for i = 2, segments do
            local cat_len = (i - 1) * seg_len
            local y = if cat_len < seg0 then -cat_len else -2 * seg0 + cat_len
            out_points[i] = Vector3.new(p0.X, p0.Y + y, p0.Z)
        end
    else -- line
        local dir = (p1 - p0).Unit
        for i = 2, segments do
            out_points[i] = p0 + ((i - 1) * seg_len) * dir
        end
    end
    out_points[segments + 1] = p1
    return a, seg_len, iteration
end
---[[ test
do
    local n_seg = 20
    local p0 = Vector3.new(0, 10, 0)
    local p1 = Vector3.new(1, 15, 0)
    local points = table.create(n_seg + 1)
    local len = 1.2 * (p1 - p0).Magnitude
    local a, seg_len, it = m.catenary(p0, p1, len, n_seg, points)
    print("===>", a, it, seg_len)
    for i, v in points do
        warn(i, v)
    end
end
--]]
--[[
local num = function()
    return math.random(-10, 125)
end
local N = 1000
local J = 8
local count = 0
local p0s = {}
local p1s = {}
local lens = {}
for i = 1, N do
    local p0 = Vector3.new(num(), num(), num())
    local p1 = Vector3.new(num(), num(), num())
    local len = (1 + 2 * math.random()) * (p1 - p0).Magnitude
    local a, _, it = m.catenary(p0, p1, len)
    p0s[i] = p0
    p1s[i] = p1
    lens[i] = len
    if it > J then
        count += 1
        warn(i, it, a, p0, "|", p1, len)
    end
    if a == 0 or a == math.huge then
        print(i, it, a == 0 and "vertical" or "line", p0, "|", p1, len)
    end
end
warn(">", J, count, "of", N)
local perfn = require("perfn")
perfn()
perfn("old", function(i)
    local _ = m.catenary(p0s[i], p1s[i], lens[i])
end)

--]]
local TINY = 2 ^ -8
assert(math.abs((0.261 - m.catenary(Vector3.new(0, 0, 0), Vector3.new(1, 1, 0), 2))) < TINY)
local v1 = Vector3.new(1, 0, 0)
local v2 = Vector3.new(1 + TINY, 1, 0)
print(m.catenary(v1, v2, 2))
local d = (v1 - v2).Magnitude
print(d)

function m.truncate_vec(a: vec, max: num)
    if a.Magnitude > max then
        return a.Unit * max
    end
    return a
end

--@note: stable version
function m.lerp(t: num, min: num?, max: num?)
    return (min or 0) * (1 - t) + t * (max or 1)
end

function m.truncate(a: num, max: num)
    return math.clamp(a, -max, max)
end

function m.near(a: num, b: num, tolerance: num?): bool
    return math.abs(a - b) < (tolerance or TINY)
end

function m.near_vec(a: vec, b: vec): bool
    return (a - b).Magnitude < TINY
end

---@note: cubic
function m.smooth_step<a>(t: num)
    t = math.clamp(t, 0, 1)
    return t * t * (3 - 2 * t)
end

function m.smooth_step_edges(x: num, edge0: num, edge1: num)
    local t = math.clamp((x - edge0) / (edge1 - edge0), 0, 1)
    return t * t * (3 - 2 * t)
end

---@see: https://iquilezles.org/articles/ismoothstep/
function m.inverse_smooth_step(y: num)
    return 0.5 - math.sin(math.asin(1.0 - 2.0 * y) / 3.0)
end

-- critically dumped spring
---@note: `tta`: approximately the time it will take to reach the target
function m.critical<a>(dt: num, goal: a, tt: num, pos: a, vel: a): (a, a)
    local shift: any = pos :: any - goal
    local velocity: any = vel
    local omega = PI_4 / tt
    local odt = omega * dt
    local decay = math.exp(-odt)
    local pos1 = (decay * (1 + odt)) * shift + (decay * dt) * velocity + goal
    local vel1 = (decay * (1 - odt)) * velocity - (decay * omega * odt) * shift
    return pos1, vel1
end

function m.pp(v: any)
    local t = type(v)
    if t == "vector" then
        return _fmt("[%5.2f, %5.2f, %5.2f]", v.X, v.Y, v.Z)
    end
    return tostring(v)
end

-----------------------------
-- Quick test
-----------------------------
local v3 = function(x, y, z)
    return Vector3.new(x, y, z)
end
local goal, p, v = v3(100, 0, 0), v3(0, 0, 0), v3(0, 0, 0)
p, v = m.critical(0.33, goal, 2, p, v)
-- print(p, v)
assert(math.floor(p.X) == 61)

warn("[mathf -- ok]")

return m

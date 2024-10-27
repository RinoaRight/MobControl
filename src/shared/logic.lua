--!strict
--!native
type str = string
type bool = boolean
type num = number
type positive = num
type integer = num
type uint = integer
type int = integer
type u32 = uint
type i32 = int
type u8 = uint
type array<a> = { a }
type table = { [any]: any }
type map<k, v> = { [k]: v }
type fun = (...any) -> ...any
local fmt = string.format

local PHI = 0.5 * (1 + math.sqrt(5)) -- golden ratio (1.618)

local m = {}
m.__index = m
m.PHI = PHI

local floor = math.floor
local round = math.round
local log = math.log

--[[ stylua: ignore]] script = script or require'script'
local rand = require(script.Parent.rand)

-----------------------------
-- Util
-----------------------------

do
    local function round_factory(rounder: (num) -> int): (x: num, mul: num) -> int
        return function(x, mul)
        --[[stylua: ignore]] if _G.__DEV__ then assert(mul and mul ~= 0) end
            return mul * rounder(x / mul)
        end
    end
    m.fround = round_factory(math.floor)
    m.cround = round_factory(math.ceil)
    --[=[
        @summary: round to multiply of `mul` (like Excel's MROUND)
    ]=]
    m.mround = round_factory(math.round)
end

--[=[
    @summary: quest requirements rounder (to very "round" number)
]=]
function m.qround(x: positive): u32
    assert(x > 0, "arg must be positive")
    local k = x < 100 and 10 or 5 * 10 ^ floor(log(x, 10) - 1)
    local exp = floor(log(x, k))
    local man = x * k ^ -exp
    return round(man) * k ^ exp
end

-- quick test
assert(m.qround(1.5) == 2)
assert(m.qround(7) == 7)
assert(m.qround(11) == 10)
assert(m.qround(67) == 70)
assert(m.qround(123) == 100)
print(m.qround(357))
assert(m.qround(1637) == 1500)
assert(m.qround(1837) == 2000)

--[=[
    @summary probability round, ex. 1.2 -> 1 or 2
]=]
function m.pround(x: num): int
    assert(x >= 0, "must be positive")
    local c, extra = math.modf(x)
    if math.random() <= extra then
        c += 1
    end
    return c
end

-----------------------------
-- Triangular number
-----------------------------
--@see: https://en.wikipedia.org/wiki/Triangular_number
local function triangular_number(x)
    return 0.5 * x * (x + 1)
end

local function triangular_number_sum(x: int)
    return x * (x + 1) * (x + 2) / 6
end

m.triangular_number = triangular_number
m.triangular_number_sum = triangular_number_sum

-----------------------------
-- Geometric progression
-----------------------------
---@summary n-th member 1-based, i.e `n == 1` -> `initial`
local function geom(initial: num, rate: num, n: int): num
    return initial * rate ^ (n - 1)
end
m.geom = geom

---@summary sum of first n members of geometric sequence
local function geom_sum(initial: num, rate: num, n: int): num
    return initial * (1 - rate ^ n) / (1 - rate)
end
m.geom_sum = geom_sum

function m.geom_rate(n: int, from: int, to: int)
    return math.pow(to / from, 1 / (n - 1))
end

-- secant method
---@ref: https://en.wikipedia.org/wiki/Secant_method#Computational_example
function m.secant_method(f: fun, x0: num, iterations: int?, tolerance: num?): num
    local x: num
    local n = iterations or 50
    local tol = tolerance or 1.48e-08
    local x1 = x0 * (1 + 1e-4) + math.sign(x0) * 1e-4
    for i = 1, n do
        x = x1 - f(x1) * (x1 - x0) / (f(x1) - f(x0))
        x0, x1 = x1, x
        if math.abs(x0 - x1) < tol or math.abs(x0 / x1 - 1) < tol or math.abs(f(x1)) < tol then
            return x
        end
    end
    error(fmt("Failed to converge after %d iterations, value is %*", n, x))
end
do --test
    local function e(x: num)
        return x * x - 612
    end
    local x = m.secant_method(e, 10)
    assert(e(x) < 1.48e-08)
end

function m.geom_rate_approx(initial: num, n: num, sum: num, guess: num?)
    local function f(x)
        return geom_sum(initial, x, n) - sum
    end
    return m.secant_method(f, guess or PHI)
end
do -- quick test
    local sum = m.geom_sum(2, 2.1, 5)
    assert(math.abs(m.geom_rate_approx(2, 5, sum) - 2.1) < 1e-10)
end

local function geom_nth(initial: num, rate: num, sum: num): num
    return log(1 - sum * (1 - rate) / initial, rate)
end
m.geom_nth = geom_nth

---@returns level: uint, progress: num in [0, 1)
function m.lvl_progress(xp: num, first_req: num, rate: num, max_lvl: num?): (u32, num)
    local lvl, progress = math.modf(geom_nth(first_req, rate, xp))
    if max_lvl and lvl > max_lvl then
        return lvl, 0
    end
    return lvl, progress
end

---@usage: affordable_amount(1, 1.6, 4, 100)//1 => 4
function m.affordable_amount(first_req: num, rate: num, owned: num, cash: num): num
    return log(1 - cash * (1 - rate) / (first_req * rate ^ owned), rate)
end
assert(math.floor(m.affordable_amount(1, 1.6, 4, 100)) == 4)

function m.series(n: int, from: int, to: int?)
    local rate = if to then math.pow(to / from, 1 / (n - 1)) else 1.618
    local function loop(i): ...int
        if i <= n then
            return math.round(geom(from, rate, i)), loop(i + 1)
        end
    end
    print(("~> series of %* [%* .. %*] rate: %4.4g"):format(n, from, to, rate))
    return loop(1)
end

function m.qseries(n: int, from: int, to: int?)
    local rate = if to then math.pow(to / from, 1 / (n - 1)) else 1.618
    local function loop(i): ...int
        if i <= n then
            return m.qround(geom(from, rate, i)), loop(i + 1)
        end
    end
    print(("~> series of %* [%* .. %*] rate: %4.4g"):format(n, from, to, rate))
    return loop(1)
end

-----------------------------
-- Interpolations
-----------------------------
local function lerp(min: num, max: num, t: num)
    return min * (1 - t) + t * max -- stable
end
m.lerp = lerp

local function clamped_lerp(min: num, max: num, t: num)
    t = math.clamp(t, 0, 1)
    return min * (1 - t) + t * max
end
m.clamped_lerp = clamped_lerp

local function inverse_lerp(min: num, max: num, val: num): num
    local divisor = max - min
    if math.abs(divisor) < 1e-6 then
        return val >= max and 1 or 0
    end
    return (val - min) / divisor
end
m.inverse_lerp = inverse_lerp

function m.clamped_remap(min_in, max_in, min_out, max_out, val)
    return lerp(min_out, max_out, math.clamp(inverse_lerp(min_in, max_in, val), 0, 1))
end

function m.remap(min_in, max_in, min_out, max_out, val)
    return lerp(min_out, max_out, inverse_lerp(min_in, max_in, val))
end

function m.weighted_choice<a>(kw_pairs: map<a, num>): a
    local sum = 0
    for _, w in pairs(kw_pairs) do
        sum += w
    end
    local r = rand.uniform(0, sum)
    for k, w in pairs(kw_pairs) do
        r -= w
        if r < 0 then
            return k
        end
    end
    error("weighted_choice")
end

type rad = num
-----------------------------
-- Sunflower Distribution 2D
-----------------------------
---@ref: https://en.wikipedia.org/wiki/Fibonacci_sequence#Nature
---@ref: https://stackoverflow.com/a/28572551/4487767
do
    local PI2 = 2 * math.pi
    local Theta = PI2 / PHI ^ 2 -- golden angle ~137.5 degree
    ---@returns x, y, azimuth
    function m.sunflower(i: uint, dist: num): (num, num, rad)
        local theta, r = i * Theta, dist * math.sqrt(i)
        return r * math.cos(theta), r * math.sin(theta), theta % PI2
    end
end
print("[logic -- ok]")

return m

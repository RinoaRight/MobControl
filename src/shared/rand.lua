type num = number
type bool = boolean
type integer = number
type int = integer
type i32 = int
type u32 = integer

local m = {}
m.__index = m

-- aliases for math.random
local random = math.random
m.randomseed = math.randomseed
m.random = random

---@return number # in [a, b)
local function uniform(a: num, b: num?)
    if not b then
        b, a = a, 0
    end
    assert(a < b :: num, "empty interval")
    local r = random()
    return a * (1 - r) + r * b :: num
end
m.uniform = uniform

---@return number in (0, 1]
local function random1()
    return 1.0 - random()
end
m.random1 = random1

local function unit2d()
    local r = 2 * math.pi * random()
    return math.cos(r), math.sin(r)
end
m.unit2d = unit2d()

local function unit_disc2d()
    local r = math.sqrt(random())
    local x, y = unit2d()
    return r * x, r * y
end
m.unit_disc2d = unit_disc2d

local function unit3d()
    local x = 2 * random() - 1
    local r = math.sqrt(1 - x * x)
    local y, z = unit2d()
    return x, r * y, r * z
end

m.unit3d = unit3d

---@summary triangular distribution
---@note: for good results with integers: floor(triangular(a, b + 1, [a..b+1])
function m.triangular(a: num, b: num, c: num?)
    assert(a <= b and not c or a <= (c :: num) and (c :: num) <= b, "a < b and a <= c <= b")
    local r = b - a
    if r == 0 then
        return a
    end
    local mode = if c then (c - a) / r else 0.5
    local u = random()
    if u > mode then
        u, mode = 1 - u, 1 - mode
        a, b, r = b, a, -r
    end
    return a + r * math.sqrt(u * mode)
end

---@return number # number in `(-1, 1)` more likely around `0`
function m.binomial()
    return random() - random()
end

function m.blur(x: num, radius: num?)
    local r = radius or 0.10
    assert(r > 0 and r < 1, "radius in (0, 1)")
    local dx = r * x
    return x + dx * (random() - random())
end

function m.bool(): bool
    return random(0, 1) == 1
end

-- stylua: ignore
function m.test(chance): bool
    if chance >= 1 then return true  end
    if chance <= 0 then return false end
    return random() + chance >= 1
end

--[[
local count = 0
while count < 100000 do
    local x = m.test(0.0001)
    count += 1
    if x then
        print("success @", count)
        break
    end
end
--]]

---@return number # in [0, 100]
function m.percent(): int
    return random(0, 100)
end

function m.u32()
    local l = random(0, 0xffff)
    local h = random(0, 0xffff)
    return h * 0x10000 + l
end

function m.u8()
    return random(0, 0xff)
end

-----------------------------
-- Extra utility
-----------------------------
function m.weighted_choice<K>(gacha: { [K]: num }): K
    assert(next(gacha), "empty gacha")
    local sum = 0
    for _, weight in pairs(gacha) do
        assert(weight > 0, "weight <= 0")
        sum += weight
    end
    local r = m.uniform(0, sum)
    for key, w in pairs(gacha) do
        r -= w
        if r < 0 then
            return key
        end
    end
    error("can't be here")
end

-- do
--     local gacha = { A = 1, B = 1, C = 0.5 }
--     for i = 1, 20 do
--         print(i, m.weighted_choice(gacha))
--     end
-- end

---@summary cumulative binomial probability of single success
---@param n number # number of trials
---@param p number # probability of success in trial
function m.success(n, p)
    assert(n >= 0 and 0 <= p and p <= 1, "n >= 0 and p in [0, 1]")
    return 1 - (1 - p) ^ n
end

local function binomial_c(n, k)
    assert(n >= 0 and k >= 0 and n >= k)
    if k == n then
        return 1
    end
    if k > n - k then
        k = n - k
    end
    local c = 0
    for i = 1, k do
        c *= (n - i + 1) / i
    end
    return c
end

function m.bernoulli_trial(n, p, k)
    local q = 1 - p
    return binomial_c(n, k) * p ^ k * q ^ (n - k)
end

---@param n number # number of trials
---@param p number # probability of success in trial
---@param k? number # number of success (default: `1`)
---@return number
function m.cumulative_binomial_probability(n, p, k: num?): num
    if not k or k == 1 then
        return m.success(n, p)
    end
    local sum = 0
    for i = k :: num, n do
        sum += m.bernoulli_trial(n, p, i)
    end
    return sum
end

--[[
print(m.cumulative_binomial_probability(3, 0.2, 1), 0.488)
print(m.cumulative_binomial_probability(2, 0.5, 1), 0.75)
print(m.cumulative_binomial_probability(100, 0.001, 1), 0.0952078529)

local xs = { 0, 0, 0, 0, 0 }
for i = 1, 10000 do
    xs[m.bool() and 2 or 1] += 1
end
print(table.unpack(xs))
--]]

warn("[rand -- ok]")

return m

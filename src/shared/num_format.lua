--!strict
-- MIT License
-- Copyright (c) 2022 Andrew Zhilin (https://github.com/zoon)

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
type array<a> = { a }
type table = { [any]: any }
type fun = (...any) -> ...any
local fmt = string.format

local function is_integer(x: num)
    local _, fraction = math.modf(x)
    return math.abs(fraction) < 0.01
end

-- stylua: ignore
if not game then (function() script = require("script") :: any end)() end
local En = require(script.Parent.enum)

-----------------------------
-- Module
-----------------------------
local m = {}


function m.format_time(seconds: int, use_hours: any?, use_days: any?)
    seconds = math.floor(seconds < 0 and 0 or seconds)
    use_hours = use_hours or seconds >= 3600
    use_days = use_days or seconds >= 86400
    local fmt = use_days and "!%j:%H:%M:%S" or (use_hours and "!%H:%M:%S" or "!%M:%S")
    return os.date(fmt, seconds)
end

function m.format_countdown(tte_timestamp: int, use_hours: any?, use_days: any?)
    local seconds = math.max(0, tte_timestamp - os.time())
    return m.format_time(seconds, use_hours, use_days)
end

-- print(m.format_time(29400))
-- print(m.format_countdown(os.time()+29400))

-- stylua: ignore
local ROMAN_NUMERALS: En.Enum = En.gt {
    M  = 1000,
    CM = 900,
    D  = 500,
    CD = 400,
    C  = 100,
    XC = 90,
    L  = 50,
    XL = 40,
    X  = 10,
    IX = 9,
    V  = 5,
    IV = 4,
    I  = 1,
}

---@summary: convert unsigned to roman numeral string
function m.roman(n: u32): str
    assert(n > 0)
    n = bit32.bor(n, 0)
    local res = ""
    for _, val in ROMAN_NUMERALS:ids() do
        if n == 0 then
            break
        end
        local k = math.floor(n / val)
        for _ = 1, k do
            res ..= ROMAN_NUMERALS[val]
        end
        n %= val
    end
    return res
end

assert(m.roman(10123) == "MMMMMMMMMMCXXIII")
assert(m.roman(14) == "XIV")

local function last_sub(s: str, n: u32): str
    return string.char(string.byte(s, -n, -1))
end

---@summary: convert unsigned to ordinal string
function m.ordinal(n: u32): str
    assert(n >= 1)
    local num = tostring(math.floor(n))
    local last2 = last_sub(num, 2)
    if last2 == "11" then
        return num .. "th"
    end
    if last2 == "12" then
        return num .. "th"
    end
    if last2 == "13" then
        return num .. "th"
    end
    local last = last_sub(num, 1)
    if last == "1" then
        return num .. "st"
    end
    if last == "2" then
        return num .. "nd"
    end
    if last == "3" then
        return num .. "rd"
    end
    return num .. "th"
end

assert(m.ordinal(1337) == "1337th")
assert(m.ordinal(23) == "23rd")
assert(m.ordinal(11) == "11th")

-- thousand     3 k
-- million      6 m
-- billion      9 b
-- trillion    12 t
-- quadrillion 15 q
-- quintillion 18 i
-- sextillion  21 x
-- septillion  24 p
-- octillion   26 o
-- nonillion   29 n
-- decillion   32 d
-- undecillion 35 u

-- NB. for bigger numbers use BigNumber.tostring
-- billion, trillion, quadrillion, quintillion, sextillion
local MAX_NUM = 9.999999e38 -- 1000u
local _tiers = { "K", "M", "B", "T", "Q", "I", "X", "P", "O", "N", "D", "U" }
local _tiers_lower = { " k", " m", " b", " t", " q", " i", " x", " p", " o", " n", " d", " u" }
---@param num number
local function format_number(num, cents: any?, lower_tier: any?, isWithNegative: bool?)
    if type(num) ~= "number" then
        error("", 2)
    end
    if num <= 0 and not isWithNegative then
        return "0"
    end
    cents = cents and not is_integer(num)
    if num > MAX_NUM then
        -- error(("num:%.7g > MAX_NUM (%.7g)"):format(MAX_NUM, num))
        num = MAX_NUM
    end
    local tiers = lower_tier and _tiers_lower or _tiers
    if num < 100000 then
        local fmt_str = cents and "%.2f" or "%.0f"
        local formatted = fmt(fmt_str, num)
        if num > 1000 then -- add 1000 commas
            formatted = string.gsub(formatted, "^(-?%d+)(%d%d%d)", "%1,%2")
        end
        return formatted
    end
    local tier = math.floor(math.log(num, 10) / 3)
    num = num / 10 ^ (3 * tier)
    return fmt("%.4g%s", num, tiers[tier])
end
m.format_number = format_number

local function format_to_one_decimal(x: num)
    local a = string.format("%2g", math.round(10 * x) / 10)
    return a
end
m.format_to_one_decimal = format_to_one_decimal

m.format_damage = function(x)
    return format_number(x, false)
end
m.format_ectos = function(x)
    return format_number(x, false)
end

assert(format_number(MAX_NUM, true, true) == "1000 u")
assert(format_number(9999.95) == "10,000")
assert(format_number(12.95) == "13")
assert(format_number(12.95, true) == "12.95")
assert(format_number(9999.95, true) == "9,999.95")
assert(format_number(99999.95, true) == "99,999.95") -- widest, 9 chars
assert(format_number(123456789000.1234567890) == "123.5B")
assert(format_number(12345678900.1234567890) == "12.35B")
assert(format_number(1234567890.1234567890) == "1.235B")
assert(format_number(1E18) == "1I", format_number(1E18))
assert(format_number(1E21) == "1X")
assert(format_number(0.9e24) == "900X")
assert(format_number(0.9999e24) == "999.9X")
assert(format_number(0.99999e24) == "1000X")
assert(format_number(0.99999e32) == "100N")

print("[num_format -- ok]")

m = table.freeze(m)

return m

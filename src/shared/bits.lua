--!nonstrict
--[[
    Bit-twiddling utils, TPOP style.
    + bit printer
    + some tricks from Hackers Delight.

    TODO:
     -- 53-bit as 64 bit
     -+ vector as 72 bit
]]

type str = string
type bool = boolean
type num = number
type integer = num
type uint = integer
type int = integer
type u32 = uint
type u53 = uint
type u8 = uint
type u5 = uint
type u3 = uint
type i32 = int
type i8 = int
type array<a> = { a }
type table = { [any]: any }
type fun = (...any) -> ...any
type map<k, v> = { [k]: v }
local fmt = string.format

---@alias integer number
local _fmt = string.format
local byte = string.byte

---@class bits
local bits = {}

bits.MAX_UINT32 = 0xffff_ffff
bits.MIN_UINT32 = 0
bits.MAX_INT32 = 0x7fff_ffff
bits.MIN_INT32 = -0x8000_0000
local MAX_UINT53 = 0x20_0000_0000_0000
bits.MAX_UINT53 = MAX_UINT53

local bor, band = bit32.bor, bit32.band
local lsh, rsh = bit32.lshift, bit32.rshift

local function uint32(x: i32): u32
    -- assert(bits.MIN_INT32 <= x and x <= bits.MAX_INT32)
    return bor(x, 0)
end
bits.u32 = uint32

local function int32(n: u32)
    -- assert(0 <= n and n <= bits.MAX_UINT32)
    return n <= 0x7FFFFFFF and n or n - 0x100000000
end
bits.i32 = int32

---@summary get `n` bits from position `pos`;
-- bits are numbered from 0 LSB up, read from MSB to LSB
---@param x integer
---@param pos integer @ in [0, 31]
---@param n integer
function bits.getbits(x: i32, pos: u32, n: u32)
    return bit32.extract(x, pos + 1 - n, n)
end

---@param x integer
---@param pos integer @ in [0, 31]
---@return boolean
function bits.getbit(x: i32, pos: u32)
    return bit32.extract(x, pos, 1) ~= 0
end

---@summary: set `n` bits from position `pos` to value `val`;
-- bits are numbered from 0 LSB up, filled from MSB to LSB
---@param x integer
---@param pos integer @ in [0, 31]
---@param n integer
---@param val integer
function bits.setbits(x: i32, pos: u32, n: u32, val: i32)
    return bit32.replace(x, val, pos + 1 - n, n)
end

---@summary: is number is a power of 2
local function has_single_bit(x: i32): boolean
    return not (x == 0 or bit32.btest(x, x - 1))
end

bits.has_single_bit = has_single_bit

assert(bits.has_single_bit(2 ^ 5))
assert(not bits.has_single_bit(0))
assert(not bits.has_single_bit(0b0101))

-- set or remove flag according to bool
function bits.flag(x: i32, flag, bool)
    assert(has_single_bit(flag))
    if bool then
        return bit32.bor(x, flag)
    end
    return if bit32.btest(x, flag) then bit32.bxor(x, flag) else x
end

function bits.eq_masked(a: u32, b: u32, mask: u32)
    return bit32.band(a, mask) == bit32.band(b, mask)
end

---@param x integer
---@param pos integer @ in [0, 31]
---@param bool boolean | '0' | '1'
function bits.setbit(x: i32, pos: u32, bool: boolean | u32)
    assert(type(x) == "number", x)
    assert(0 <= pos and pos <= 31, pos)
    --  bool and bool ~= 0 and (x | 1 << p) or (x & ~(1 << p))
    local v = if bool and bool ~= 0 then 1 else 0
    return bit32.replace(x, v, pos, 1)
end

function bits.flip(x: i32, ...: u32): u32
    local n = select("#", ...)
    if n == 0 then
        x = uint32(x)
    end
    for i = 1, n do
        x = bit32.bxor(x, lsh(1, select(i, ...)))
    end
    return x :: u32
end

---@see: https://en.wikipedia.org/wiki/Hamming_weight (popcount64c)
---@perf: ~70 ns
local function popcount32(x: i32): u32
    x = x - band(rsh(x, 1), 0x55555555)
    x = band(x, 0x33333333) + band(rsh(x, 2), 0x33333333)
    x = band(x + rsh(x, 4), 0x0F0F0F0F)
    return rsh(band(x * 0x01010101, 0xFFFFFFFF), 24)
end
bits.popcount32 = popcount32

do -- popcount 8bit (2.5x faster for byte)
    local _count = table.create(255, 0)
    _count[0] = 0
    for i = 1, 255 do
        _count[i] = popcount32(i)
    end
    local function popcount8(x: i8): u3
        return _count[band(x, 0xff)]
    end
    bits.popcount8 = popcount8
end

---@perf 40 ns per bit, O(n)
local function to_args(x: i32): ...u32
    if x > 0 then
        local bit = bit32.countrz(x)
        return bit, to_args(bit32.replace(x, 0, bit, 1))
    else
        return
    end
end
bits.to_args = to_args

---@perf: 40 ns per bit, O(n)
local function to_indices(x: i32, out: { u5 }?): { u5 }
    if out then
        table.clear(out)
    else
        out = table.create(popcount32(x)) :: { u5 }
    end
    assert(out)
    while true do
        local bit = bit32.countrz(x)
        if bit > 31 then
            break
        end
        table.insert(out, bit)
        x = bit32.replace(x, 0, bit, 1)
    end
    return out
end
bits.to_indices = to_indices

---@summary: floor power of 2
function bits.flp2(x: num): u32
    assert(0 <= x and x <= 0xffff_ffff)
    return lsh(1, 31 - bit32.countlz(x))
end

---@summary: ceil power of 2
function bits.clp2(x: num): u32
    assert(0 <= x and x <= 0x7fff_ffff)
    return lsh(1, 32 - bit32.countlz(x - 1))
end
assert(bits.flp2(0xffff_ffff) == 0x8000_0000)
assert(bits.clp2(0x7fff_ffff) == 0x8000_0000)
assert(bits.flp2(0) == 0)
assert(bits.clp2(0) == 0)
assert(bits.flp2(1) == 1)
assert(bits.clp2(1) == 1)
assert(bits.flp2(3) == 2)
assert(bits.clp2(3) == 4)

function bits.split53(x: u53): (u32, u32) -- hi, lo
    assert(0 <= x and x <= MAX_UINT53)
    return bor(x / 0x100000000), x % 0x100000000
end

function bits.join53(hi: u32, lo: u32): u53
    assert(hi <= 0x200_0000)
    assert(0 <= lo and lo <= 0xFFFF_FFFF)
    return hi * 0x100000000 + lo
end

assert(bits.join53(bits.split53(MAX_UINT53)) == MAX_UINT53)

-----------------------------
-- 32-bitset ops
-----------------------------
function bits.contains(set: u32, other: u32): bool
    return band(set, other) == other
end

function bits.symmetric_diff(set: u32, other: u32): u32
    return bit32.bxor(set, other)
end

function bits.diff(set: u32, other: u32): u32
    return band(set, bit32.bnot(other))
end

function bits.union(set: u32, other: u32): u32
    return bor(set, other)
end

function bits.intersect(set: u32, other: u32): u32
    return band(set, other)
end

---@summary: recursive bit printer, zero-allocates (modulo result) and quite fast, up to 128 bit (4x32 bit-fields)
export type BitPrinter = (x: u32, y: u32?, z: u32?, w: u32?) -> string
function bits.make_bit_printer(bit_len: u32, group_len: u32?, zero_one_group_arg_chars: str?, prefix: str?): BitPrinter
    assert(bit_len and 0 < bit_len and bit_len <= 32)
    group_len = group_len or bit_len -- default is no grouping
    assert(group_len)
    assert(group_len <= bit_len)
    zero_one_group_arg_chars = zero_one_group_arg_chars or "01_|"
    assert(type(zero_one_group_arg_chars) == "string")
    local ZERO, ONE, GROUP_SEP, ARG_SEP = zero_one_group_arg_chars:byte(1, 4)
    assert(ZERO)
    assert(ONE)
    prefix = prefix or ""
    assert(prefix)

    local max_idx = bit_len - 1

    local function concat_left(right_idx, ...)
        if right_idx <= 0 then
            return ...
        end
        return concat_left(right_idx - 1, string.byte(prefix, right_idx), ...)
    end

    local function loop(x: u32, y: u32?, z: u32?, w: u32?, group: u32, bit_idx: u32, arg_idx: u32, ...)
        if bit_idx > max_idx then
            bit_idx = 0
            arg_idx += 1
            group = group_len - 1
            if ARG_SEP and arg_idx <= 4 then
                return loop(x, y, z, w, group, bit_idx, arg_idx, ARG_SEP, ...)
            end
        end
        if arg_idx > 4 then -- we done
            return concat_left(#prefix, ...)
        end
        local arg = select(-arg_idx, x, y, z, w)
        local bit = bit32.btest(arg, lsh(1, bit_idx)) and ONE or ZERO
        if GROUP_SEP and bit_idx >= group and bit_idx < max_idx then
            return loop(x, y, z, w, group + group_len, bit_idx + 1, arg_idx, GROUP_SEP, bit, ...)
        end
        return loop(x, y, z, w, group, bit_idx + 1, arg_idx, bit, ...)
    end
    return function(x: u32, y: u32?, z: u32?, w: u32?): string
        -- we scan args right to left, using negative index
        local arg_idx = 1
        while not select(-arg_idx, x, y, z, w) do
            arg_idx += 1
        end
        return string.char(loop(x, y, z, w, group_len - 1, 0, arg_idx))
    end
end

-- TODO: better API
---@summary: returns luau literal binary string grouped by 4
bits.luau = bits.make_bit_printer(32, 4, "01_", "0b_")
bits.u16 = bits.make_bit_printer(16, 4, "01_")
bits.u8 = bits.make_bit_printer(8, 4, "01_")

---@summary: returns raw bits (MSB to LSB)
bits.tostring = bits.make_bit_printer(32, 32, "01")
do
    local _str32 = bits.make_bit_printer(32, 32, "01")
    local _str22 = bits.make_bit_printer(22, 22, "01")
    bits.tostring53 = function(u53: u53)
        local hi, lo = bits.split53(u53)
        return _str22(hi) .. _str32(lo)
    end

    local x = 0x10_ffff_ffff_0fff
    assert(bits.tostring53(x) == "010000111111111111111111111111111111110000111111111111")
    assert(tonumber(bits.tostring53(x), 2) == x)
    assert(bits.tostring53(MAX_UINT53) == "100000000000000000000000000000000000000000000000000000")

    local _ps32 = bits.make_bit_printer(32, 4, "01-")
    local _ps21 = bits.make_bit_printer(21, 4, "01-")
    bits.ps53 = function(u53: u53)
        local hi, lo = bits.split53(u53)
        return _ps21(hi) .. _ps32(lo)
    end
    assert(bits.ps53(x) == "1-0000-1111-1111-1111-11111111-1111-1111-1111-0000-1111-1111-1111")
end

local print_vector = bits.make_bit_printer(24, 8, "01_|")
bits.vector = function(v3: Vector3)
    return print_vector(v3.X, v3.Y, v3.Z)
end

function bits.hex(x: u32 | any, roundtrip: any?)
    if type(x) == "number" then
        return if roundtrip then fmt("0x%.8X", x) else fmt("%.8X", x)
    end
    local s = tostring(x)
    return (
        s:gsub(".", function(c)
            local b = byte(c)
            return if b <= 31 or b >= 126 then fmt("\\x%.2X", b) else c
        end)
    )
end

---@note: can be used for CyberChef input (`From Hex`)
function bits.str_to_hex(s: str, fmt_str: str?): str
    fmt_str = fmt_str or "%02x"
    local out = {}
    for i = 1, #s do
        out[i] = fmt(fmt_str, byte(s, i))
    end
    return table.concat(out, " ")
end

-----------------------------
-- Set
-----------------------------
-- non-expandable bitset
local set_mmt = {}
set_mmt.__index = set_mmt
local set = setmetatable({}, set_mmt)
set.__index = set
bits.set = set

local function n_ints(size)
    local r, n = size % 32, math.ceil(size / 32)
    return if r == 0 then n else n + 1
end

function set.new(n: int?)
    n = n or 32
    return table.freeze(setmetatable({ _data = table.create(n_ints(n), 0), _size = n }, set))
end

set_mmt.__call = set.new

function set.__len(self)
    return self._size
end

function set:__index(k)
    if type(k) == "number" then
        assert(1 <= k and k <= #self)
        k -= 1 -- to 0-index
        local idx, bit = math.ceil(k / 32) + 1, k % 32
        return bit32.btest(self._data[idx], bit32.lshift(1, bit))
    end
    return rawget(set, k)
end

function set:__newindex(k, val: any)
    assert(type(k) == "number", "indexer must be integer")
    assert(1 <= k and k <= #self)
    local bit = if not val or val == 0 then 0 else 1 -- `0` is falsy too
    k -= 1 -- to 0-index
    local idx, bit_idx = math.ceil(k / 32) + 1, k % 32
    local u32 = self._data[idx]
    self._data[idx] = bit32.replace(u32, bit, bit_idx, 1)
    return self
end

function set:popcount(): int
    local count = 0
    for _, v in self._data do
        count += bits.popcount32(v)
    end
    return count
end

-----------------------------
-- Quick test
-----------------------------
do -- set
    local s8 = set.new(8)
    assert(#s8 == 8)
    assert(s8:popcount() == 0)
    s8[1] = 1
    assert(s8:popcount() == 1)
    assert(s8[1])
    assert(s8._data[1] == 1)
    s8[1] = 0
    assert(s8:popcount() == 0)

    local s211 = set.new(211)
    assert(#s211 == 211)
    assert(s211:popcount() == 0)
    s211[200] = 1
    assert(s211:popcount() == 1)
    assert(s211[200])
end

do -- uint/int32
    assert(uint32(-1) == bits.MAX_UINT32)
    assert(int32(bits.MAX_UINT32) == -1)
end
do
    local v = 0b_1_1110
    local x = bits.setbits(0, 31, 5, v)
    assert(bits.getbits(x, 31, 5) == v)
    assert(bits.hex(x) == "F0000000")
    assert(bits.tostring(bits.setbits(0, 31, 5, v)) == "11110000000000000000000000000000")
    assert(bits.luau(bits.setbits(0, 31, 5, v)) == "0b_1111_0000_0000_0000_0000_0000_0000_0000")
    assert(tonumber(bits.tostring(bits.setbits(0, 31, 5, v)), 2) == bits.setbits(0, 31, 5, v))
end

do
    local v = 0b_1001
    local x = bits.setbits(0, 31, 4, v)
    assert(bits.getbits(x, 31, 4) == v)
    assert(bits.hex(x) == "90000000")
    assert(bits.tostring(x) == "10010000000000000000000000000000")
end

do
    local v = bits.flip(0, 0, 2, 4, 31)
    assert(bits.tostring(v) == "10000000000000000000000000010101")
    v = bits.flip(v, 0, 2, 4, 31)
    assert(v == 0)
end

do
    local x = -1
    assert(bits.getbit(x, 31))
    x = bits.setbit(x, 31, 0) -- 01111111111111111111111111111111
end

do
    assert(popcount32(-1) == 32)
    assert(popcount32(1) == 1)
    assert(popcount32(5) == 2)
    assert(popcount32(0x555555) == 12)
    assert(popcount32(0x33333333) == 16)
end

do
    local v3 = Vector3.new(-1, 0x555555, 0x333333)
    assert(bits.vector(v3) == "11111111_11111111_11111111|01010101_01010101_01010101|00110011_00110011_00110011")
end

do
    local s = "\x65\x66_hello\x10"
    assert(bits.hex(s) == "ef_hello\\x10")
    assert(bits.str_to_hex(s) == "65 66 5f 68 65 6c 6c 6f 10")
end

do
    local flags = 0
    local F = 0b_0010
    flags = bits.flag(flags, F, true)
    flags = bits.flag(flags, F, true)
    assert(flags == F)
    flags = bits.flag(flags, F, false)
    flags = bits.flag(flags, F, false)
    assert(flags == 0)
end

warn("[bits -- ok]")

return bits

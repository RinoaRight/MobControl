--!strict
--!native
--!optimize 2

-- MIT License
-- Copyright (c) 2024 Andrew Zhilin (https://github.com/zoon)

local __DEV__ = not workspace or game:GetService("RunService"):IsStudio()

--[=[
    Opinionated Luau binary serializer very similar to Message Pack (MP) with LE byte order.
    ref: https://github.com/msgpack/msgpack/blob/master/spec.md
    Notes:
--- - all integers outside [-2^32-1, 2^32-1] will be serialized as 64-bit doubles (with no extra tag)
--- - all integers in [-32, 127] will be encoded as 1 byte
--- - all integers in [0, 2^20-1] will be encoded as 3 bytes
--- - option: all doubles in [-8192, 8192] will be serialized as float32
    Spec (tag bits layout):
--- - 0xxx_xxxx fix uint [0, 127]
--- - 111x_xxxx fix neg [-32, -1]
--- - 1000_xxxx uint20 [0, 2^20-1]
--- - 1001_xxxx fix array [0, 15]
--- - 101x_xxxx fix str [0, 31]
--- - == tags and values 1100 xxxx
--- - 1100_0000 nil
--- - 1100_0001 false
--- - 1100_0010 true
--- - 1100_0011 uint8 [0, 255]
--- - 1100_0100 uint32
--- - 1100_0101 neg8 [-255, -1]
--- - 1100_0110 neg16 [-2^16-1, -1]
--- - 1100_0111 neg32 [-2^32-1, -1]
--- - 1100_1000 f32
--- - 1100_1001 f64
--- - 1100_1010 map8
--- - 1100_1011 map32
--- - 1100_1100 array8
--- - 1100_1101 array32
--- - 1100_1110 str8
--- - 1100_1111 str32
--- - == tags and values 1101 xxxx
--- - 1101_0000 buffer8
--- - 1101_0001 buffer32
--- - 1101_0010 vector (3xf32)
--- - 1101_0011 tuple8
--- - 1101_0100 (reserved)
--- - 1101_0101 (reserved)
--- - 1101_0110 (reserved)
--- - 1101_0111 (reserved)
--- - 1101_1000 (reserved)
--- - 1101_1001 (reserved)
--- - 1101_1010 (reserved)
--- - 1101_1011 (reserved)
--- - 1101_1100 (reserved)
--- - 1101_1101 (reserved)
--- - 1101_1110 (reserved)
--- - 1101_1111 (reserved)
]=]

--[=[ performance (state snapshot 32K)
--- +----------------------------+-----------+----------+----------+
--- | lpack 32K                  | μ      10 |  636 μs  |   3.3 KB | gc: 10 μs
--- | lpack-32K+base64           | μ      10 |  888 μs  | 135.4 KB | gc: 16 μs
--- +----------------------------+-----------+----------+----------+
]=]

type str = string
type bool = boolean
type num = number
type uint = num
type int = num
type u32 = uint
type u8 = uint
type id = int
type buf = buffer
type array<a> = { a }
type map<k, v> = { [k]: v }
type packer = (buf, c: int, ...any) -> (buf, int)
type unpacker = (buf, c: int, tag: u8?) -> (any, int)
type pack = str
type pack64 = str
type base64 = str
local fmt = string.format


--- @note: buffer reallocation is expensive, try to use default value pretty big for your dataset
local _scratch_buffer = buffer.create(0x10000) -- 64K
local _scratch_array = table.create(16) :: { any }
local MAX_INT = 2 ^ 32 - 1
local MIN_INT = -MAX_INT
local MAX_F64_TO_F32 = 2 ^ 13 - 1 -- at least 3 digits for fractional part
local MIN_F64_TO_F32 = -MAX_F64_TO_F32

-----------------------------
-- Utility
-----------------------------
local function grow(b: buf, len: int, opt: "exact"?): buf
    if len < buffer.len(b) then
        return b
    end
    local size = buffer.len(b)
    -- exact len, or next power of 2
    size = if opt == "exact" then len else bit32.lshift(1, 32 - bit32.countlz(math.max(len, 2 * size) - 1))
    local fresh = buffer.create(size)
    buffer.copy(fresh, 0, b)
    warn("grow to:", size)
    return fresh
end

local function _tag_reserved(t: str): unpacker
    return function(_, _)
        error(`tag '{t}' is reserved`, 3)
    end
end

-----------------------------
-- Encoders
-----------------------------
local PACK = {} :: map<str, packer>
local UNPACK = {} :: map<u8, unpacker>

PACK["nil"] = function(b: buf, c: int)
    local nxt = c + 1
    b = grow(b, nxt)
    buffer.writeu8(b, c, 0b_1100_0000)
    return b, nxt
end

local function unpack_nil(b: buf, c: int)
    return nil, c
end

PACK["boolean"] = function(b: buf, c: int, v: bool)
    local nxt = c + 1
    b = grow(b, nxt)
    buffer.writeu8(b, c, if v then 0b_1100_0010 else 0b_1100_0001)
    return b, nxt
end

local function unpack_false(b: buf, c: int)
    return false, c
end

local function unpack_true(b: buf, c: int)
    return true, c
end

PACK["number"] = function(b: buf, c: int, v: num)
    if math.floor(v) == v and MIN_INT <= v and v <= MAX_INT then
        return PACK[if v >= 0 then "uint" else "neg"](b, c, v)
    end
    if MIN_F64_TO_F32 <= v and v <= MAX_F64_TO_F32 then
        return PACK["f32"](b, c, v)
    end
    return PACK["f64"](b, c, v)
end

PACK["f32"] = function(b: buf, c: int, v: num)
    local nxt = c + 5
    b = grow(b, nxt)
    buffer.writeu8(b, c, 0b_1100_1000)
    buffer.writef32(b, c + 1, v)
    return b, nxt
end

local function unpack_f32(b: buf, c: int)
    return buffer.readf32(b, c), c + 4
end

local function unpack_f64(b: buf, c: int)
    return buffer.readf64(b, c), c + 8
end

PACK["f64"] = function(b: buf, c: int, v: num)
    local nxt = c + 9
    b = grow(b, nxt)
    buffer.writeu8(b, c, 0b_1100_1001)
    buffer.writef64(b, c + 1, v)
    return b, nxt
end

PACK["uint"] = function(b: buf, c: int, v: u32)
    if v <= 0x7f then -- fix uint
        local nxt = c + 1
        b = grow(b, nxt)
        buffer.writeu8(b, c, v)
        return b, nxt
    end
    if v <= 0xff then -- uint8
        local nxt = c + 2
        b = grow(b, nxt)
        buffer.writeu8(b, c, 0b_1100_0011)
        buffer.writeu8(b, c + 1, v)
        return b, nxt
    end
    if v <= 0xf_ffff then -- uint20
        local nxt = c + 3
        b = grow(b, nxt)
        buffer.writeu8(b, c, 0b_1000_0000 + bit32.rshift(v, 16))
        buffer.writeu16(b, c + 1, bit32.band(v, 0xffff))
        return b, nxt
    end
    -- uint32
    b = grow(b, c + 5)
    buffer.writeu8(b, c, 0b_1100_0100)
    buffer.writeu32(b, c + 1, v)
    return b, c + 5
end

local function unpack_fix_uint(b: buf, c: int, tag: u8?)
    return tag, c
end

local function unpack_uint8(b: buf, c: int)
    return buffer.readu8(b, c), c + 1
end

local function unpack_uint20(b: buf, c: int, tag: u8?)
    local hi = tag :: u8 - 0b_1000_0000
    local lo = buffer.readu16(b, c)
    return bit32.lshift(hi, 16) + lo, c + 2
end

local function unpack_uint32(b: buf, c: int)
    return buffer.readu32(b, c), c + 4
end

PACK["neg"] = function(b: buf, c: int, v: int)
    -- assume v < 0
    if v >= -0x20 then -- fix neg
        b = grow(b, c + 1)
        buffer.writeu8(b, c, 0x100 + v)
        return b, c + 1
    end
    if v >= -0xff then -- neg8
        local nxt = c + 2
        b = grow(b, nxt)
        buffer.writeu8(b, c, 0b_1100_0101)
        buffer.writeu8(b, c + 1, -v)
        return b, nxt
    end
    if v >= -0xffff then -- neg16
        local nxt = c + 3
        b = grow(b, nxt)
        buffer.writeu8(b, c, 0b_1100_0110)
        buffer.writeu16(b, c + 1, -v)
        return b, nxt
    end
    -- neg32
    local nxt = c + 5
    b = grow(b, nxt)
    buffer.writeu8(b, c, 0b_1100_0111)
    buffer.writeu32(b, c + 1, -v)
    return b, nxt
end

local function unpack_fix_neg(b: buf, c: int, tag: u8?)
    return tag :: u8 - 0x100, c
end

local unpack_neg8 = function(b: buf, c: int, tag: u8?)
    return -buffer.readu8(b, c), c + 1
end

local unpack_neg16 = function(b: buf, c: int, tag: u8?)
    return -buffer.readu16(b, c), c + 2
end

local unpack_neg32 = function(b: buf, c: int, tag: u8?)
    return -buffer.readu32(b, c), c + 4
end

PACK["string"] = function(b: buf, c: int, v: str)
    local n = #v
    if n <= 0x1f then -- fix str
        local nxt = c + 1 + n
        b = grow(b, nxt)
        buffer.writeu8(b, c, 0b_1010_0000 + n)
        buffer.writestring(b, c + 1, v)
        return b, nxt
    end
    if n <= 0xff then -- str8
        local nxt = c + 2 + n
        b = grow(b, nxt)
        buffer.writeu8(b, c, 0b_1100_1110)
        buffer.writeu8(b, c + 1, n)
        buffer.writestring(b, c + 2, v)
        return b, nxt
    end
    local nxt = c + 5 + n
    b = grow(b, nxt)
    buffer.writeu8(b, c, 0b_1100_1111)
    buffer.writeu32(b, c + 1, n)
    buffer.writestring(b, c + 5, v)
    return b, nxt
end

local function unpack_fixstr(b: buf, c: int, tag: u8?)
    local n = tag :: u8 - 0b_1010_0000
    return buffer.readstring(b, c, n), c + n
end

local function unpack_str8(b: buf, c: int, tag: u8?)
    local n = buffer.readu8(b, c)
    c += 1
    return buffer.readstring(b, c, n), c + n
end
local function unpack_str32(b: buf, c: int, tag: u8?)
    local n = buffer.readu32(b, c)
    c += 4
    return buffer.readstring(b, c, n), c + n
end

PACK["array"] = function(b: buf, c: int, v: { any }, n: int)
    if n <= 0xf then -- fix array
        b = grow(b, c + 1)
        buffer.writeu8(b, c, 0b_1001_0000 + n)
        c += 1
    elseif n <= 0xff then -- array8
        b = grow(b, c + 2)
        buffer.writeu8(b, c, 0b_1100_1100)
        buffer.writeu8(b, c + 1, n)
        c += 2
    else -- array32
        b = grow(b, c + 5)
        buffer.writeu8(b, c, 0b_1100_1101)
        buffer.writeu32(b, c + 1, n)
        c += 5
    end
    for _, v in v do
        local pack = PACK[typeof(v)] or error(`no packer for type '{typeof(v)}'`)
        b, c = pack(b, c, v)
    end
    return b, c
end

local function unpack_fixarray(b: buf, c: int, tag: u8?)
    local n = tag :: u8 - 0b_1001_0000
    local out, val = table.create(n), nil
    for i = 1, n do
        tag, c = buffer.readu8(b, c), c + 1
        val, c = UNPACK[tag :: u8](b, c, tag)
        out[i] = val
    end
    return out, c
end

local function unpack_array8(b: buf, c: int, tag: u8?)
    local n = buffer.readu8(b, c)
    c += 1
    local out, val = table.create(n), nil
    for i = 1, n do
        tag, c = buffer.readu8(b, c), c + 1
        val, c = UNPACK[tag :: u8](b, c, tag)
        out[i] = val
    end
    return out, c
end

local function unpack_array32(b: buf, c: int, tag: u8?)
    local n = buffer.readu32(b, c)
    c += 4
    local out, val = table.create(n), nil
    for i = 1, n do
        tag, c = buffer.readu8(b, c), c + 1
        val, c = UNPACK[tag :: u8](b, c, tag)
        out[i] = val
    end
    return out, c
end

PACK["map"] = function(b: buf, c: int, v: { [any]: any }, count: int)
    if count <= 0xff then -- map8
        b = grow(b, c + 2)
        buffer.writeu8(b, c, 0b_1100_1010)
        buffer.writeu8(b, c + 1, count)
        c += 2
    else -- map32
        b = grow(b, c + 5)
        buffer.writeu8(b, c, 0b_1100_1011)
        buffer.writeu32(b, c + 1, count)
        c += 5
    end
    for k, v in v do
        local pk = PACK[typeof(k)] or error(`no packer for type '{typeof(k)}'`, 3)
        b, c = pk(b, c, k)
        local pv = PACK[typeof(v)] or error(`no packer for type '{typeof(v)}'`, 3)
        b, c = pv(b, c, v)
    end
    return b, c
end

local function unpack_map8(b: buf, c: int, tag: u8?)
    local count = buffer.readu8(b, c)
    c += 1
    local out, key, val = {}, nil, nil
    for i = 1, count do
        tag, c = buffer.readu8(b, c), c + 1
        key, c = UNPACK[tag :: u8](b, c, tag)
        tag, c = buffer.readu8(b, c), c + 1
        val, c = UNPACK[tag :: u8](b, c, tag)
        out[key] = val
    end
    return out, c
end

local function unpack_map32(b: buf, c: int, tag: u8?)
    local count = buffer.readu32(b, c)
    c += 4
    local out, key, val = {}, nil, nil
    for i = 1, count do
        tag, c = buffer.readu8(b, c), c + 1
        key, c = UNPACK[tag :: u8](b, c, tag)
        tag, c = buffer.readu8(b, c), c + 1
        val, c = UNPACK[tag :: u8](b, c, tag)
        out[key] = val
    end
    return out, c
end

PACK["table"] = function(b: buf, c: int, v: map<any, any>)
    local n = #v
    local count = 0
    for _ in v do
        count += 1
    end
    if n == count then
        return PACK["array"](b, c, v, n)
    end
    return PACK["map"](b, c, v, count)
end

PACK["buffer"] = function(b: buf, c: int, v: buf)
    local n = buffer.len(v)
    if n <= 0xff then -- buffer8
        b = grow(b, c + 2)
        buffer.writeu8(b, c, 0b_1101_0000)
        buffer.writeu8(b, c + 1, n)
        c += 2
    else -- buffer32
        b = grow(b, c + 5)
        buffer.writeu8(b, c, 0b_1101_0001)
        buffer.writeu32(b, c + 1, n)
        c += 5
    end
    buffer.copy(b, c, v, 0, n)
    return b, c + n
end

local function unpack_buffer8(b: buf, c: int, tag: u8?)
    local n = buffer.readu8(b, c)
    local out = buffer.create(n)
    c += 1
    buffer.copy(out, 0, b, c, n)
    return out, c + n
end

local function unpack_buffer32(b: buf, c: int, tag: u8?)
    local n = buffer.readu32(b, c)
    c += 4
    local out = buffer.create(n)
    buffer.copy(out, 0, b, c, n)
    return out, c + n
end

PACK["vector"] = function(b: buf, c: int, v: Vector3)
    b = grow(b, c + 13)
    buffer.writeu8(b, c, 0b_1101_0010)
    buffer.writef32(b, c + 1, v.X)
    buffer.writef32(b, c + 5, v.Y)
    buffer.writef32(b, c + 9, v.Z)
    return b, c + 13
end
PACK["Vector3"] = PACK["vector"]

local function unpack_vector(b: buf, c: int, tag: u8?)
    local x = buffer.readf32(b, c)
    local y = buffer.readf32(b, c + 4)
    local z = buffer.readf32(b, c + 8)
    return Vector3.new(x, y, z), c + 12
end

UNPACK[0b_1100_0000] = unpack_nil
UNPACK[0b_1100_0001] = unpack_false
UNPACK[0b_1100_0010] = unpack_true
UNPACK[0b_1100_0011] = unpack_uint8
UNPACK[0b_1100_0100] = unpack_uint32
UNPACK[0b_1100_0101] = unpack_neg8
UNPACK[0b_1100_0110] = unpack_neg16
UNPACK[0b_1100_0111] = unpack_neg32
UNPACK[0b_1100_1000] = unpack_f32
UNPACK[0b_1100_1001] = unpack_f64
UNPACK[0b_1100_1010] = unpack_map8
UNPACK[0b_1100_1011] = unpack_map32
UNPACK[0b_1100_1100] = unpack_array8
UNPACK[0b_1100_1101] = unpack_array32
UNPACK[0b_1100_1110] = unpack_str8
UNPACK[0b_1100_1111] = unpack_str32
UNPACK[0b_1101_0000] = unpack_buffer8
UNPACK[0b_1101_0001] = unpack_buffer32
UNPACK[0b_1101_0010] = unpack_vector
-- we need to occupy all non-fixed tags
UNPACK[0b_1101_0011] = function(...: any)
    error(debug.traceback "tag: 1101_0011 - tuple always top level and never nested", 3)
end
UNPACK[0b_1101_0100] = _tag_reserved("1101_0100")
UNPACK[0b_1101_0101] = _tag_reserved("1101_0101")
UNPACK[0b_1101_0110] = _tag_reserved("1101_0110")
UNPACK[0b_1101_0111] = _tag_reserved("1101_0111")
UNPACK[0b_1101_1000] = _tag_reserved("1101_1000")
UNPACK[0b_1101_1001] = _tag_reserved("1101_1001")
UNPACK[0b_1101_1010] = _tag_reserved("1101_1010")
UNPACK[0b_1101_1011] = _tag_reserved("1101_1011")
UNPACK[0b_1101_1100] = _tag_reserved("1101_1100")
UNPACK[0b_1101_1101] = _tag_reserved("1101_1101")
UNPACK[0b_1101_1110] = _tag_reserved("1101_1110")
UNPACK[0b_1101_1111] = _tag_reserved("1101_1111")

-- unpackers for packed tags
for tag = 0x00, 0xff do
    if UNPACK[tag] ~= nil then
        continue -- already occupied
    end
    if tag < 0b_1100_0000 then
        if tag < 0b_1000_0000 then
            UNPACK[tag] = unpack_fix_uint
        elseif tag < 0b_1001_0000 then
            UNPACK[tag] = unpack_uint20
        elseif tag < 0b_1010_0000 then
            UNPACK[tag] = unpack_fixarray
        else
            UNPACK[tag] = unpack_fixstr
        end
    elseif tag >= 0b_1110_000 then
        UNPACK[tag] = unpack_fix_neg
    else
        error("can't be here")
    end
end

-- for _ , typ in {"nil", "boolean", "number", "string", "table", "buffer", "Vector3"} do
--     assert(PACK[typ] ~= nil, `no packer for type '{typ}'`)
-- end

-----------------------------
-- Base64
-----------------------------
local PAD: u8 = string.byte("=") -- 0x3d
local EMPTY_BUF = buffer.create(0)

-- RFC 4648
local STD = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"
assert(#STD == 64)
local ENC = buffer.fromstring(STD)
local DEC = buffer.create(256)
buffer.fill(DEC, 0, 0xff) -- 0xff means invalid
for i = 0, buffer.len(ENC) - 1 do
    buffer.writeu8(DEC, buffer.readu8(ENC, i), i)
end

local function encoded_len(len: int): int
    return math.floor((len + 2) / 3) * 4
end

-- assume sting to encode in [0, count-1]
local function _enc64(bytes: buf, count: int): (buf, int, int)
    local buf = grow(bytes, count + encoded_len(count), "exact")
    local by3 = 3 * math.floor(count / 3)
    local ri, wi = 0, count
    while ri < by3 do
        local u24 = buffer.readu8(buf, ri + 2) + 0x100 * buffer.readu8(buf, ri + 1) + 0x10000 * buffer.readu8(buf, ri)
        buffer.writeu8(buf, wi + 3, buffer.readu8(ENC, bit32.band(u24, 0x3f)))
        buffer.writeu8(buf, wi + 2, buffer.readu8(ENC, bit32.band(bit32.rshift(u24, 6), 0x3f)))
        buffer.writeu8(buf, wi + 1, buffer.readu8(ENC, bit32.band(bit32.rshift(u24, 12), 0x3f)))
        buffer.writeu8(buf, wi, buffer.readu8(ENC, bit32.band(bit32.rshift(u24, 18), 0x3f)))
        ri += 3
        wi += 4
    end
    local tail = count - by3
    if tail > 0 then
        buffer.writeu8(buf, wi + 3, PAD)
        local u24 = 0x10000 * buffer.readu8(buf, ri)
        if tail == 2 then
            u24 += 0x100 * buffer.readu8(buf, ri + 1)
            buffer.writeu8(buf, wi + 2, buffer.readu8(ENC, bit32.band(bit32.rshift(u24, 6), 0x3f)))
        end
        if tail == 1 then
            buffer.writeu8(buf, wi + 2, PAD)
        end
        buffer.writeu8(buf, wi + 1, buffer.readu8(ENC, bit32.band(bit32.rshift(u24, 12), 0x3f)))
        buffer.writeu8(buf, wi, buffer.readu8(ENC, bit32.band(bit32.rshift(u24, 18), 0x3f)))
        wi += 4
    end
    return buf, count, wi
end

---@note: Reuses input buffer for output, resulting in similar performance while allocating half the memory
local function _dec64(s64: str, scratch: buf?): (buf, int)
    if s64 == "" then
        return EMPTY_BUF, 0
    end
    local strlen = #s64
    assert(strlen >= 4 and strlen % 4 == 0, "base64 length must be a multiple of 4")
    local buf: buf -- read/write buffer
    if type(scratch) == "buffer" then
        buf = grow(scratch, strlen, "exact")
        buffer.writestring(buf, 0, s64)
    else
        buf = buffer.fromstring(s64)
    end
    local ri, wi = 0, 0
    local by4 = strlen - 4
    while ri < by4 do -- by 4 bytes
        local b4 = buffer.readu8(DEC, buffer.readu8(buf, ri + 3))
        local b3 = buffer.readu8(DEC, buffer.readu8(buf, ri + 2))
        local b2 = buffer.readu8(DEC, buffer.readu8(buf, ri + 1))
        local b1 = buffer.readu8(DEC, buffer.readu8(buf, ri))
        ---@perf: this assertion is rather pricy (~10% runtime)
        if bit32.bor(b1, b2, b3, b4) == 0xff then
            error(fmt("invalid base64 sequence at: %d: 0x%X 0x%X 0x%X 0x%X", ri, b1, b2, b3, b4), 2)
        end
        local u24 = b1 * 0x40000 + b2 * 0x1000 + b3 * 0x40 + b4
        buffer.writeu8(buf, wi + 2, u24)
        buffer.writeu8(buf, wi + 1, bit32.rshift(u24, 8))
        buffer.writeu8(buf, wi, bit32.rshift(u24, 16))
        ri += 4
        wi += 3
    end
    -- else -- last 1..3 bytes to decode
    local b4 = buffer.readu8(buf, ri + 3)
    local b3 = buffer.readu8(buf, ri + 2)
    local b2 = buffer.readu8(DEC, buffer.readu8(buf, ri + 1))
    local b1 = buffer.readu8(DEC, buffer.readu8(buf, ri))
    local ntail = if b4 == PAD and b3 == PAD then 1 elseif b4 == PAD then 2 else 3
    b3 = ntail < 2 and 0 or buffer.readu8(DEC, b3)
    b4 = ntail < 3 and 0 or buffer.readu8(DEC, b4)
    local u24 = b1 * 0x40000 + b2 * 0x1000 + b3 * 0x40 + b4
    assert(bit32.bor(b1, b2, b3, b4) ~= 0xff, "invalid base64 sequence at last 1..3 bytes")
    local shift = 16
    while ntail > 0 do
        buffer.writeu8(buf, wi, bit32.rshift(u24, shift))
        wi += 1
        shift -= 8
        ntail -= 1
    end
    return buf, wi
end

-----------------------------
-- Module
-----------------------------
local m = {}
m.__index = m

local function _pack_tuple8(b: buf, offset: int, ...)
    local n = select("#", ...)
    assert(n <= 255, "tuple can only hold up to 255 elements")
    b = grow(b, 2)
    buffer.writeu8(b, offset, 0b_1101_0011)
    buffer.writeu8(b, offset + 1, n)
    offset += 2
    for i = 1, n do
        local el = (select(i, ...))
        local pack = PACK[typeof(el)] or error(`no packer for type '{typeof(el)}'`, 3)
        b, offset = pack(b, offset, el)
    end
    return b, offset
end

local function _unpack_tuple8(b: buf, offset: int): ...any
    local tag: u8 = buffer.readu8(b, offset)
    local n: u8 = buffer.readu8(b, offset + 1)
    offset += 2
    if __DEV__ then
        if tag ~= 0b_1101_0011 then
            error(`tuple8: expected tag 1101_0011, got {tag}`, 3)
        end
    end
    table.clear(_scratch_array) -- not necessary, but just in case
    local val: any
    for i = 1, n do
        tag, offset = buffer.readu8(b, offset), offset + 1
        val, offset = UNPACK[tag :: u8](b, offset, tag)
        _scratch_array[i] = val
    end
    return table.unpack(_scratch_array, 1, n)
end

local function _pack(buf: buf, offset: int, data: any): (buf, int)
    local packer = PACK[typeof(data)] or error(`no packer for type '{typeof(data)}'`, 3)
    return packer(buf, offset, data)
end

local function _unpack(buf: buf, offset: int): (any, int)
    local tag = buffer.readu8(buf, offset)
    local unpacker = UNPACK[tag] or error(`no unpacker for tag '{tag}'`, 3)
    return unpacker(buf, offset + 1, tag)
end

--- Packs the given data into a string, optionally encoding it to base64.
---
--- @param data any The data to be packed.
--- @param enc? "base64" An optional flag to indicate the data should be base64 encoded.
--- @return string The packed string.
function m.pack(data: any, enc: "base64"?): string
    local b: buffer, c: int = _scratch_buffer, 0
    local packer = PACK[typeof(data)] or error(`no packer for type '{typeof(data)}'`, 3)
    b, c = packer(b, c, data)
    if enc == "base64" then
        local buf, from, to = _enc64(b, c)
        return buffer.readstring(buf, from, to - from)
    end
    return buffer.readstring(b, 0, c)
end

--- Unpacks a value from a string, optionally decoding the string from base64 first.
---
--- @param data string The string to unpack.
--- @param enc? "base64" An optional flag to indicate the string is base64 encoded.
--- @return any The unpacked value.
function m.unpack(data: string, enc: "base64"?): any
    local b: buffer
    if enc == "base64" then
        local cd = 0
        b, cd = _dec64(data, _scratch_buffer)
        local val: any, cu: int = _unpack(b, 0)
        assert(cd == cu, "unpack failed: length mismatch (base64)")
        return val
    end
    local len = #data
    b = buffer.fromstring(data)
    local val: any, cu: int = _unpack(b, 0)
    assert(len == cu, "unpack failed: length mismatch")
    return val
end

--- Packs the given tuple into a string, optionally encoding it to base64.
---
--- @param ... any The tuple values to be packed.
--- @return string The packed string.
function m.pack_tuple(...: any): string
    local b = _scratch_buffer
    local c = 0
    b, c = _pack_tuple8(b, c, ...)
    return buffer.readstring(b, 0, c)
end

--- Unpacks a tuple from the given packed data string.
---
--- @param data string The packed data string containing the tuple.
--- @return ...any The unpacked tuple values.
function m.unpack_tuple(data: string): ...any
    local len = #data
    local b = grow(_scratch_buffer, len, "exact")
    buffer.writestring(b, 0, data, len)
    return _unpack_tuple8(b, 0)
end

--- Returns the arity (number of arguments) of the given packed data.
---
--- @param data string The packed data to check the arity of.
--- @return int The arity of the packed data.
function m.arity(data: string): int
    local tag = string.byte(data, 1)
    if tag == 0b_1101_0011 then -- tuple8
        local n = string.byte(data, 2)
        return n
    end
    return 1
end

m.base64 = {}
--- Encodes the given string data to a base64 string.
---
--- @param data str The string to be encoded.
--- @return str The base64 encoded string.
function m.base64.encode(data: str): str
    local len = #data
    local bytes = grow(_scratch_buffer, len + encoded_len(len), "exact")
    buffer.writestring(bytes, 0, data, len)
    local out, from, to = _enc64(bytes, len)
    return buffer.readstring(out, from, to - from)
end
--- Decodes the given base64 string to a string.
---
--- @param base64 str The base64 encoded string to be decoded.
--- @param opt "remove-whitespace"? An optional flag to remove any whitespace from the base64 string before decoding.
--- @return str The decoded string.
function m.base64.decode(base64: str, opt: "remove-whitespace"?): str
    if opt == "remove-whitespace" and base64:find("%s+") then
        base64 = base64:gsub("%s+", "")
    end
    local out, c = _dec64(base64, _scratch_buffer)
    return buffer.readstring(out, 0, c)
end

--- Returns the length of the base64 encoded string for the given input string.
---
--- @param data str The input string to calculate the encoded length for.
--- @return int The length of the base64 encoded string.
function m.base64.encoded_len(data: str): int
    return encoded_len(#data)
end

-----------------------------
-- Quick test
-----------------------------
---[[ tags
do
    local b: buffer, c: int = _scratch_buffer, 0
    local val: any

    -- fix uint
    c = 0
    b, c = _pack(b, c, 123)
    assert(c == 1)
    val, c = _unpack(b, 0)
    assert(val :: any == 123)
    -- fix neg
    c = 0
    b, c = _pack(b, c, -31)
    assert(c == 1)
    val, c = _unpack(b, 0)
    assert(val :: any == -31)
    -- uint20
    c = 0
    b, c = _pack(b, c, 2 ^ 20 - 1)
    assert(c == 3)
    val, c = _unpack(b, 0)
    assert(c == 3)
    assert(val :: any == 2 ^ 20 - 1)
    -- fix array
    c = 0
    b, c = _pack(b, c, { 1, 2, 3 })
    assert(c == 4)
    val, c = _unpack(b, 0)
    assert(val[1] == 1)
    assert(val[2] == 2)
    assert(val[3] == 3)
    -- fix str
    c = 0
    b, c = _pack(b, c, "hello")
    assert(c == 6)
    val, c = _unpack(b, 0)
    assert(val :: any == "hello")
    -- nil
    c = 0
    b, c = _pack(b, c, nil)
    assert(c == 1)
    val, c = _unpack(b, 0)
    assert(val == nil)
    -- true
    c = 0
    b, c = _pack(b, c, true)
    assert(c == 1)
    val, c = _unpack(b, 0)
    assert(val == true)
    -- false
    c = 0
    b, c = _pack(b, c, false)
    assert(c == 1)
    val, c = _unpack(b, 0)
    assert(val :: any == false)
    -- uint8
    c = 0
    b, c = _pack(b, c, 128)
    assert(c == 2)
    val, c = _unpack(b, 0)
    assert(val :: any == 128)
    -- uint32
    c = 0
    b, c = _pack(b, c, 123456789)
    assert(c == 5)
    val, c = _unpack(b, 0)
    assert(val :: any == 123456789)
    -- neg8
    c = 0
    b, c = _pack(b, c, -128)
    assert(c == 2)
    val, c = _unpack(b, 0)
    assert(val :: any == -128)
    -- neg16
    c = 0
    b, c = _pack(b, c, -12345)
    assert(c == 3)
    val, c = _unpack(b, 0)
    assert(val :: any == -12345)
    --neg32
    c = 0
    b, c = _pack(b, c, -123456789)
    assert(c == 5)
    val, c = _unpack(b, 0)
    assert(val :: any == -123456789)
    -- f32
    c = 0
    b, c = _pack(b, c, 123.456)
    assert(c == 5)
    val, c = _unpack(b, 0)
    assert(math.abs(val :: any - 123.456) < 1e-4)
    -- f64
    c = 0
    b, c = _pack(b, c, 12345.456789)
    assert(c == 9)
    val, c = _unpack(b, 0)
    assert(val :: any == 12345.456789)
    -- map8
    c = 0
    b, c = _pack(b, c, { a = 1, b = 2 })
    assert(c == 8)
    val, c = _unpack(b, 0)
    assert((val :: any).a == 1)
    assert((val :: any).b == 2)

    -- map32
    local m32 = {}
    local len = 0
    for i = 257, 1256 do
        m32[i] = i
        len += 1
    end
    c = 0
    b, c = _pack(b, c, m32)
    assert(c == 3 * len + 3 * len + 1 + 4)
    val, c = _unpack(b, 0)
    local len1 = 0
    for k, v in val :: any do
        len1 += 1
        assert(k == v)
    end
    assert(len == len1)

    -- buffer8
    local b8 = buffer.create(100)
    for i = 0, 99 do
        buffer.writeu8(b8, i, i)
    end
    c = 0
    b, c = _pack(b, c, b8)
    assert(c == 102)
    val, c = _unpack(b, 0)
    for i = 0, 99 do
        assert(buffer.readu8(val :: any, i) == i)
    end
    assert(buffer.len(val :: any) == buffer.len(b8))

    -- buffer32
    local b32 = buffer.create(1000)
    for i = 0, 999 do
        buffer.writeu8(b32, i, i % 256)
    end
    c = 0
    b, c = _pack(b, c, b32)
    assert(c == 1005)
    val, c = _unpack(b, 0)
    for i = 0, 999 do
        assert(buffer.readu8(val :: any, i) == i % 256)
    end
    assert(buffer.len(val :: any) == buffer.len(b32))

    -- vector
    c = 0
    local vec = Vector3.new(1, 2, math.pi)
    b, c = _pack(b, c, vec)
    assert(c == 13)
    val, c = _unpack(b, 0)
    assert(val :: any == vec)

    -- tuple
    c = 0
    b, c = _pack_tuple8(b, c, { 1 }, 2, 3)
    assert(c == 2 + 2 + 2)
    local x, y, z = _unpack_tuple8(b, 0)
    assert(x[1] == 1)
    assert(y == 2)
    assert(z == 3)
end
--]]

---[[ pack/unpack
local data: map<any, any> = {
    1,
    2,
    true,
    false,
    Vector3.new(1, 2, math.pi),
    { 3, { { "nested" } } :: any },
    pi = math.pi,
    hello = "hello",
    huge = math.huge,
    big = 2 ^ 53 - 1,
}

-- binary string
local packed = m.pack(data)
local data1 = m.unpack(packed)
assert(data1[1] == 1)
assert(data1[2] == 2)
assert(data1[3] == true)
assert(data1[4] == false)
assert(data1[5] == Vector3.new(1, 2, math.pi))
assert(data1[6][1] == 3)
assert(data1[6][2][1][1] == "nested")
assert(math.abs(data1.pi - math.pi) < 0.0001) -- converted to f32
assert(data1.hello == "hello")
assert(data1.huge == math.huge)
assert(data1.big == 2 ^ 53 - 1)
-- base64
local b64 = "ygoBAQICA8IEwQXSAACAPwAAAEDbD0lABpIDkZGmbmVzdGVkpWhlbGxvpWhlbGxvonBpyNsPSUCjYmlnyf///////z9DpGh1Z2XJAAAAAAAA8H8="
assert(m.pack(data, "base64") == b64)
local data2 = m.unpack(b64, "base64")
assert(data2[1] == 1)
assert(data2[2] == 2)
assert(data2[3] == true)
assert(data2[4] == false)
assert(data2[5] == Vector3.new(1, 2, math.pi))
assert(data2[6][1] == 3)
assert(data2[6][2][1][1] == "nested")
assert(math.abs(data2.pi - math.pi) < 0.0001) -- converted to f32
assert(data2.hello == "hello")
assert(data2.huge == math.huge)
assert(data2.big == 2 ^ 53 - 1)
--]]

---[[ tuple
do
    local p = m.pack_tuple(1, 2, { 3 }, nil)
    assert(m.arity(p) == 4)
    local x, y, z, u = m.unpack_tuple(p)
    assert(x == 1)
    assert(y == 2)
    assert(z[1] == 3)
    assert(u == nil)
end
--]]

---[[
-- stylua: ignore
do -- base64
    local test_data = {
        [""]                 = "",
        ["A"]                = "QQ==",
        ["BC"]               = "QkM=",
        ["DEF"]              = "REVG",
        ["*?!@"]             = "Kj8hQA==",
        ["Man "]             = "TWFuIA==",
        ["7904 (base10)"]    = "NzkwNCAoYmFzZTEwKQ==",
        ["1234567890A"]      = "MTIzNDU2Nzg5MEE=",
        ["1337lEEt\0\0\0\0"] = "MTMzN2xFRXQAAAAA",
        ["<D\254"]           = "PET+",
        ["Use our super handy online tool to decode or encode your data."] =
            "VXNlIG91ciBzdXBlciBoYW5keSBvbmxpbmUgdG9vbCB0byBkZWNvZGUgb3IgZW5jb2RlIHlvdXIgZGF0YS4=",
    }
    for raw, encoded in pairs(test_data) do
        assert(m.base64.encode(raw) == encoded, string.format("err encode: %q -> %q", raw, m.base64.encode(raw)))
        assert(m.base64.decode(encoded) == raw, string.format("err decode: %q -> %q", raw, m.base64.decode(encoded)))
    end
end
--]]

-----------------------------
-- Extra
-----------------------------

print("[lpack -- ok]")
return table.freeze(m)

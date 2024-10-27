--!strict

-- The MIT License (MIT)
-- Copyright (c) 2022 Andrew Zhilin (https://github.com/zoon)

-- An ULID is a 16 byte Universally Unique Lexicographically Sortable Identifier
---@see: https://github.com/ulid/spec
---@see: https://www.crockford.com/base32.html

--[[
    Pretty fast implementation of ULID for luau/ROBLOX.
    Generator performance is about 1μs/ULID.
    # ULID vs GUID:
        - Contains milliseconds precision time-stamp of generation time and
          80-bit of the randomness.
        - 128-bit compatibility with UUID.
        - Lexicographically sortable!
        - Canonically encoded as a 26 character string, as opposed to the 36
          character UUID
        - Uses Crockford's base32 for better efficiency and readability.
        - Case insensitive.
        - No special characters (URL safe).
    # API:
        - `ulid.generate:  () -> ULID`
            generates unique ids ordered by timestamp
        - `ulid.monotonic: () -> ULID`
            generates lexicographic ordered unique ids
        - `ulid.decode_time: (ulid:ulid, iso8601: bool?) -> ts_ms | str`
            extracts millisecond time-stamp or date in ISO8601 format from given ULID

    # Binary layout:
    The components are encoded as 16 octets.
    Each component is encoded with the MSB first (network byte order).
    0                   1                   2                   3
    0 1 2 3 4 5 6 7 8 9 0 1 2 3 4 5 6 7 8 9 0 1 2 3 4 5 6 7 8 9 0 1
    +-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+
    |                      32_bit_uint_time_high                    |
    +-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+
    |     16_bit_uint_time_low      |       16_bit_uint_random      |
    +-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+
    |                       32_bit_uint_random                      |
    +-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+
    |                       32_bit_uint_random                      |
    +-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+
--]]
type str = string
export type ULID = str
type bool = boolean
type code_table = { [u8]: u8 }
type integer = number
type u48 = integer
type u32 = integer
type u16 = integer
type u8 = integer
type timestamp_ms = u48

local band, rsh = bit32.band, bit32.rshift
local char, byte, unpack = string.char, string.byte, table.unpack
local format = string.format

local ROBLOX = not not game

-- NB: in vanilla luau without synchronization we will (rarely, 1 to thousands)
-- get glitches with monotonic generator. (!) Synchronization can freeze-up luau
-- VM up to 1s.
local SYNCHRONIZE_CLOCK_WITH_TIME = not ROBLOX -- and false

local ULID_CHARS = 26
local ULID_TIMESTAMP_LAST = 10

-----------------------------
-- Base32
-----------------------------
local N_BASE = 32
---@see: https://www.crockford.com/base32.html
local CROCKFORD_ALPHABET = "0123456789ABCDEFGHJKMNPQRSTVWXYZ"
assert(#CROCKFORD_ALPHABET == N_BASE)
local ENC: code_table = {}
local DEC: code_table = {}
do
    for n = 0, N_BASE - 1 do
        local b = CROCKFORD_ALPHABET:byte(n + 1)
        ENC[n], DEC[b] = b, n
        -- Crockford-32 is case insensitive
        DEC[byte(char(b):lower())] = n
    end
    -- extra Crockford-32 substitutions
    DEC[byte("O")] = 0
    DEC[byte("o")] = 0
    DEC[byte("I")] = 1
    DEC[byte("i")] = 1
    DEC[byte("L")] = 1
    DEC[byte("l")] = 1
end

-----------------------------
-- Util
-----------------------------
local function buffer_to_ulid(buffer: { u8 }, from: u8?, to: u8?)
    return char(unpack(buffer, from or 1, to or ULID_CHARS))
end

local function hex2num(str: str, from: u8, to: u8): integer
    return assert(tonumber(string.sub(str, from, to), 16), "can't parse hex string")
end

local function encode_buffer(buffer: { u8 }, seed: integer, from: u8, to: u8?)
    local range = (to or #buffer) - from
    for n = range, 0, -1 do
        local mod = seed % N_BASE
        buffer[n + from] = ENC[mod]
        seed = (seed - mod) / N_BASE
    end
end

local function _decode_buffer(buffer: { u8 }, seed: integer, from: u8, to: u8?)
    local range = (to or #buffer) - from
    assert(range <= 11, "53-bit overflow") -- math.log(N_BASE ^ (range - 1), 2) <= 53
    for n = 0, range do
        seed += DEC[buffer[from + n]] * N_BASE ^ (range - n)
    end
    return seed
end

local function _decode_id(id: str, seed: integer, from: u8, to: u8?)
    local range = (to or #id) - from
    for n = 0, range do
        local b = assert(DEC[byte(id, from + n)], "invalid ID")
        seed += b * N_BASE ^ (range - n)
    end
    return seed
end

-----------------------------
-- Data
-----------------------------
local timestamp: () -> timestamp_ms
local entropy: () -> (u16, u32, u32)
do
    if ROBLOX then
        local Workspace = game:GetService("Workspace")
        local HTTP = game:GetService("HttpService")
        timestamp = function()
            --@note: GetServerTimeNow has microsecond precision
            --@ref: https://create.roblox.com/docs/reference/engine/classes/Workspace#GetServerTimeNow
            return math.floor(Workspace:GetServerTimeNow() * 1000)
        end
        entropy = function()
            local guid = HTTP:GenerateGUID(false)
            return hex2num(guid, 10, 13), hex2num(guid, 1, 8), hex2num(guid, 25, 32)
        end
    else -- vanilla luau
        if SYNCHRONIZE_CLOCK_WITH_TIME then
            local ts0 = os.time()
            local ts1 = ts0
            local clock_0 = os.clock()
            while true do
                -- blocking!
                ts1 = os.time()
                if ts1 > ts0 then
                    break
                end
            end
            local offset = 1000 * (ts1 - os.clock())
            warn("ulid: wait for synchronization ...", math.round(1000 * (os.clock() - clock_0)) .. " ms")
            timestamp = function()
                return math.floor(1000 * os.clock() + offset)
            end
        else
            timestamp = function()
                local _, ms = math.modf(os.clock()) -- fake milliseconds
                return math.floor((os.time() + ms) * 1000)
            end
        end
        -- stylua: ignore
        entropy = function()
            return
                math.random(0, 0xffff),
                math.floor(math.ldexp(math.random(), 32)),
                math.floor(math.ldexp(math.random(), 32))
        end
    end
end

local increment: ({ u8 }) -> ()
local fill_buffer: ({ u8 }, timestamp_ms, u16, u32, u32) -> ()
do
    increment = function(bytes)
        assert(#bytes == 26)
        local i = 26
        while i > 10 do
            local b = DEC[bytes[i]]
            if b == 31 then
                bytes[i] = ENC[0]
            else
                bytes[i] = ENC[b + 1]
                break
            end
            i -= 1
        end
        assert(i > 10, "unexpected error: can't increment entropy." .. i)
    end
    fill_buffer = function(buffer: { u8 }, ts: timestamp_ms, u16: u16, u321: u32, u322: u32)
        assert(buffer and #buffer == 26)
        -- first 10 bytes: base32 timestamp
        encode_buffer(buffer, ts, 1, ULID_TIMESTAMP_LAST)
        -- last 16 bytes: base32 entropy
        -- NB: faster then string.pack("> I2 I4 I4") and doesn't allocate
        buffer[11] = band(rsh(u16, 8), 0xff)
        buffer[12] = band(u16, 0xff)
        buffer[13] = band(rsh(u321, 24), 0xff)
        buffer[14] = band(rsh(u321, 16), 0xff)
        buffer[15] = band(rsh(u321, 8), 0xff)
        buffer[16] = band(u321, 0xff)
        buffer[17] = band(rsh(u322, 24), 0xff)
        buffer[18] = band(rsh(u322, 16), 0xff)
        buffer[19] = band(rsh(u322, 8), 0xff)
        buffer[20] = band(u322, 0xff)
        local i = 15
        local j = 18
        for _ = 1, 2 do
            local b1, b2, b3, b4, b5 = buffer[i + 1], buffer[i + 2], buffer[i + 3], buffer[i + 4], buffer[i + 5]
            local v1 = b1 * 0x1000000 + b2 * 0x10000 + b3 * 0x100 + b4
            local h1 = b4 * 0x40000000 + b5 * 0x400000
            buffer[j + 1] = ENC[rsh(v1, 27)]
            buffer[j + 2] = ENC[band(rsh(v1, 22), 0x1f)]
            buffer[j + 3] = ENC[band(rsh(v1, 17), 0x1f)]
            buffer[j + 4] = ENC[band(rsh(v1, 12), 0x1f)]
            buffer[j + 5] = ENC[band(rsh(v1, 7), 0x1f)]
            buffer[j + 6] = ENC[band(rsh(v1, 2), 0x1f)]
            buffer[j + 7] = ENC[rsh(h1, 27)]
            buffer[j + 8] = ENC[band(b5, 0x1f)]
            j -= 8
            i -= 5
        end
    end
end
-----------------------------
-- Module
-----------------------------
local mt = {}
mt.__index = mt
local m = {}
m.__index = mt
setmetatable(m, mt)

do -- monotonic
    local _ts_state = timestamp()
    local _buffer = table.create(26, 0) :: { u8 }
    fill_buffer(_buffer, _ts_state, entropy())

    function m.monotonic(): ULID
        local ts = timestamp()
        if ts == _ts_state then
            increment(_buffer)
        else
            assert(ts > _ts_state, "time travel problem")
            _ts_state = ts
            fill_buffer(_buffer, _ts_state, entropy())
        end
        return buffer_to_ulid(_buffer)
    end
end

do -- random
    local _buffer = table.create(26, 0) :: { u8 }
    function m.generate(): ULID
        local ts = timestamp()
        fill_buffer(_buffer, ts, entropy())
        return buffer_to_ulid(_buffer)
    end
end

-- alias
m.gen = m.generate
function mt:__call()
    return m.generate()
end

function m.decode_time(ulid: str, iso8601: any?): timestamp_ms | str
    assert(ulid and type(ulid) == "string" and #ulid == 26, "invalid ulid")
    local ts = 0
    for i = 0, 9 do
        local b = assert(DEC[byte(ulid, i + 1)], "invalid ulid")
        ts += b * 32 ^ (9 - i)
    end
    if iso8601 then
        return format("%s.%03dZ", os.date("!%Y-%m-%dT%H:%M:%S", math.floor(ts / 1000)) :: str, ts % 1000)
    end
    return ts
end

m.timestamp = timestamp

function m.is(a: any): bool
    if type(a) == "string" and #a == 26 then
        -- is string is crockford-32?
        for i = 1, 26 do
            if not DEC[byte(a, i)] then
                warn(char(byte(a, i)))
                return false
            end
        end
        return true
    end
    return false
end

-----------------------------
-- Quick test
-----------------------------
do -- increment
    local buffer = table.create(26, ENC[0])
    buffer[26] = ENC[31]
    increment(buffer)
    assert(char(unpack(buffer, 24, 26)) == "010")
    buffer[25] = ENC[31]
    assert(char(unpack(buffer, 24, 26)) == "0Z0")
    increment(buffer)
    assert(char(unpack(buffer, 24, 26)) == "0Z1")
end

do -- basic tests
    assert(#m.generate() == 26)
    local id = "01GCQ0RRRMMP1HP6QH6SXQ9SXA"
    assert(m.decode_time(id, true) == "2022-09-11T19:35:07.284Z")
end
do -- decode time and encoding
    local buffer = table.create(26, 0)
    local ts_01012022 = 1640995200_000 -- Jan 1 00:00: 2022 UTC
    fill_buffer(buffer, ts_01012022, 0, 0, 0)
    local id1 = char(unpack(buffer))
    assert(id1 == "01FR9EZ7000000000000000000")
    assert(m.decode_time(id1) == ts_01012022)
    assert(m.decode_time(id1, true) == "2022-01-01T00:00:00.000Z")
    fill_buffer(buffer, ts_01012022, 0xffff, 0xffff_ffff, 0xffff_ffff)
    local id2 = char(unpack(buffer))
    assert(m.decode_time(id1) == m.decode_time(id2))
    assert(id2 == "01FR9EZ700ZZZZZZZZZZZZZZZZ")
    local id3 = "01fr9ez700zzzzzzzzzzzzzzzz" -- case insensitivity
    assert(assert(m.decode_time(id3) == ts_01012022))
    local id4 = "OLfr9ez7o0zzzzzzzzzzzzzzzz" -- substitute some `0, 1` with `O, o, L`
    assert(assert(m.decode_time(id4) == ts_01012022))
end
do -- lexicographic order
    local ids = {}
    for i = 1, 1000 do
        ids[i] = m.monotonic()
        assert(m.is(ids[i]))
    end
    for i = 2, 1000 do
        local lhs, rhs = ids[i - 1] :: ULID, ids[i] :: ULID
        local lts, rts = m.decode_time(lhs) :: timestamp_ms, m.decode_time(rhs) :: timestamp_ms
        assert(lhs < rhs)
        assert(lts <= rts)
    end
end
export type UlidGen = typeof(m)

print("[ulid -- ok]")

return table.freeze(m)

--!strict
--!native

-- The MIT License (MIT)
-- Copyright (c) 2022-2024 Andrew Zhilin (https://github.com/zoon)

-- RoFlake is a 9 byte, timestamped, sortable identifier, inspired by ULID and Snowflake.
---@see: https://github.com/ulid/spec
---@see: https://en.wikipedia.org/wiki/Snowflake_ID

--[=[
    Pretty fast implementation of Snowflake like UID for luau/ROBLOX. Generator performance is
    about 0.5 μs/uid.
    # Roflake features:
        - Contains milliseconds precision 40-bit time-stamp of generation time and
          32-bit of the randomness.
        - Canonically encoded as a 15 character string, as opposed to the 36
          character UUID
        - Uses Crockford's base32 for better efficiency and readability.
        - Case insensitive.
        - No special characters (URL safe).
        - Has binary form with only 9 binary characters.
        - Creation time sortable, monotonic version even lexicographically sortable.
        - With caution can be used like UUID.
    # API:
        - `roflake.uida`:  () -> 15 char unique base32(Crockford) encoded string
        - `roflake.uidb`:  () -> 9 char unique binary string
        - `roflake.monoa`: () -> 15 char unique lexicographic ordered base32(Crockford) encoded string
        - `roflake.monob`: () -> 9 char unique lexicographic ordered binary string
        - `roflake.new`: () -> returns new instance of uid generator with independent `uida`, `uidb`, etc. methods
        - `roflake.to_timestamp`: (uid: uida | uidb, iso8601: truthy) -> timestamp (ms) or iso8601 formatted time string
        - `roflake.to_entropy`: (uid: uida | uidb) -> 32-bit entropy
        - `roflake.timestamp`: () -> unix time in ms
        - `roflake.time`: () -> unix time in seconds with millisecond precision
        - `roflake.date`: () -> `now` formatted as iso8601 string
        - `roflake.to_ascii`: (uid: uida | uidb) -> pass trough `uida`, encode `uidb` to `uida`
        - `roflake.to_bin`: (uid: uida | uidb) -> pass trough `uidb`, encode `uida` to `uidb`
        - `roflake.plausible`: (any) -> can it be uida or uidb
--]=]

type str = string
export type RFID = str
type bool = boolean
type code_table = { [u8]: u8 }
type num = number
type int = number
type u40 = int
type u32 = int
type u8 = int
type msec = int
type ts = int
type ts40 = int

type buf = buffer
export type uidb = str -- 9 byte binary string
export type uida = str -- 15 byte ascii string
type b9 = buf -- len = 9
type b15 = buf -- len = 15

local char, byte = string.char, string.byte
local wu8, ru8 = buffer.writeu8, buffer.readu8
local wu32, ru32 = buffer.writeu32, buffer.readu32
local fmt = string.format

local ROBLOX = not not game

-- Timestamps be valid Jan 2020 .. Nov 2054.
local RF_EPOCH_MS = 1000 * os.time { year = 2020, month = 1, day = 1, hour = 0 }
local RF_END_OF_TIME = RF_EPOCH_MS + 2 ^ 40 - 1

local function iso8601(ms: num)
    return fmt("%s.%03dZ", os.date("!%Y-%m-%dT%H:%M:%S", math.floor(ms / 1000)) :: str, ms % 1000)
end

local ERR_TIMESTAMP_OVERFLOW = "not valid after: " .. iso8601(RF_END_OF_TIME)

-- NB: in *vanilla luau* without synchronization we will (rarely, 1 to thousands)
-- get glitches with monotonic generator. (!) Synchronization can freeze-up luau
-- VM up to 1s!
local SYNCHRONIZE_CLOCK_WITH_TIME = not ROBLOX and "turn on in luau"

-----------------------------
-- Base32 tables
-----------------------------
local N_BASE = 32
---@see: https://www.crockford.com/base32.html
local CROCKFORD_ALPHABET = "0123456789ABCDEFGHJKMNPQRSTVWXYZ"
assert(#CROCKFORD_ALPHABET == N_BASE)
local ENC = buffer.create(N_BASE)
local DEC = buffer.create(0x100)
buffer.fill(DEC, 0, 0xff) -- to detect wrong encoding
do
    for n = 0, N_BASE - 1 do
        local b = CROCKFORD_ALPHABET:byte(n + 1)
        wu8(ENC, n, b)
        wu8(DEC, b, n)
        -- Crockford-32 is case insensitive
        wu8(DEC, byte(char(b):lower()), n)
    end
    -- extra Crockford-32 substitutions
    wu8(DEC, byte("O"), 0)
    wu8(DEC, byte("o"), 0)
    wu8(DEC, byte("I"), 1)
    wu8(DEC, byte("i"), 1)
    wu8(DEC, byte("L"), 1)
    wu8(DEC, byte("l"), 1)
end

-----------------------------
-- Data
-----------------------------
local time: () -> number
local timestamp: () -> msec
local entropy: (cache: { u32 }) -> u32
do
    if ROBLOX then
        local function hex2num(str, from, to): int
            return assert(tonumber(string.sub(str, from, to), 16), "can't parse hex string")
        end
        local Workspace = game:GetService("Workspace")
        local HttpService = game:GetService("HttpService")
        time = function()
            return Workspace:GetServerTimeNow()
        end
        timestamp = function()
            return math.floor(Workspace:GetServerTimeNow() * 1000)
        end

        local FOUR = byte("4")
        -- extract 3x random u32 from GUID, cache 2 and return 1
        entropy = function(cache)
            if #cache > 0 then
                return table.remove(cache) :: u32
            end
            local guid = HttpService:GenerateGUID(false)
            assert(guid:byte(15) == FOUR, "not a ver. 4 UUID")
            -- 11111111-0000-Mxxx-Nxxx-222222220000
            cache[1] = hex2num(guid, 1, 8)
            cache[2] = hex2num(guid, 25, 32)
            return hex2num(guid, 10, 13) * 0x10000 + hex2num(guid, 33, 36)
        end
    else -- vanilla Luau+
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
            warn("roflake: wait for synchronization ...", math.round(1000 * (os.clock() - clock_0)) .. " ms")
            time = function()
                return os.clock() + offset
            end
            timestamp = function()
                return math.floor(1000 * os.clock() + offset)
            end
        else -- fake ms part of timestamp by os.clock fractional part
            time = function()
                local _, ms = math.modf(os.clock())
                return os.time() + ms
            end
            timestamp = function()
                local _, ms = math.modf(os.clock())
                return math.floor((os.time() + ms) * 1000)
            end
        end
        entropy = function(_cache)
            return math.floor(math.ldexp(math.random(), 32))
        end
    end
end
-----------------------------
-- Util
-----------------------------
local function encode_buffer(b: buf, seed: int, from: u8, to: u8)
    for n = to - from, 0, -1 do
        local mod = seed % N_BASE
        wu8(b, from + n, ru8(ENC, mod))
        seed = (seed - mod) / N_BASE
    end
    assert(seed == 0, "overflow")
    return b
end

local function encode_timestamp(b: b15, timestamp: ts)
    assert(timestamp <= RF_END_OF_TIME, ERR_TIMESTAMP_OVERFLOW)
    encode_buffer(b, timestamp - RF_EPOCH_MS, 0, 7)
    return b
end

local function encode_entropy(b: b15, entropy: u32, clean_up: any?)
    assert(entropy <= 0xffff_ffff, "entropy overflow")
    entropy *= 0x08 -- lshift by 3 to 35 bit
    if clean_up then
        buffer.fill(b, 8, 0)
    end
    encode_buffer(b, entropy, 8, 14)
    return b
end

local function decode_buffer(b: buf, seed: int, from: u8, to: u8)
    local range = to - from
    assert(range < 11, "luau integer overflow") -- -- math.log(N_BASE ^ (range - 1), 2) <= 53
    for n = 0, range do
        local d = ru8(DEC, ru8(b, from + n))
        -- assert(d < N_BASE, "invalid encoding")
        seed += d * N_BASE ^ (range - n)
    end
    return seed
end

local function decode_timestamp(b: b15): ts
    return decode_buffer(b, RF_EPOCH_MS, 0, 7)
end

local function decode_entropy(b: b15): u32
    return decode_buffer(b, 0, 8, 14) / 0x08
end

local function timestamp_bb9(b: b9): ts
    return RF_EPOCH_MS + bit32.byteswap(ru32(b, 0)) * 0x100 + ru8(b, 4)
end

local function entropy_bb9(b: b9): u32
    return bit32.byteswap(ru32(b, 5))
end

local function fill_bb9(scratch: b9, timestamp: int, entropy: u32)
    buffer.fill(scratch, 0, 0)
    timestamp -= RF_EPOCH_MS
    wu8(scratch, 0, timestamp // 0x10000_0000)
    wu32(scratch, 1, bit32.byteswap(timestamp % 0x10000_0000))
    wu32(scratch, 5, bit32.byteswap(entropy))
    return scratch
end

-----------------------------
-- Module
-----------------------------
local m = {}
export type RoFlake = {
    uida: () -> uida,
    uidb: () -> uidb,
    monoa: () -> uida,
    monob: () -> uidb,
}

function m.new(): RoFlake
    local random_cache = table.create(2)
    -- NB: 7x base32 chars can hold 35-bit and `increment` can overflow entropy
    -- out of 32-bit. It's ok for string representation, but for binary
    -- serialization it should be 32. Therefore for monotonic roflake we discard
    -- most significant bit from entropy to make room for the increment.
    local function entropy31()
        return bit32.band(0x7fff_ffff, entropy(random_cache))
    end
    local scratch_9 = buffer.create(9)
    local scratch_15 = buffer.create(15)
    local timestamp_state = timestamp()
    local entropy_state = entropy31()
    local monotonic_buffer_15 = encode_timestamp(encode_entropy(buffer.create(15), entropy_state), timestamp_state)

    -- methods
    local function uidb(): uidb
        local ts = timestamp()
        local e = entropy(random_cache)
        return buffer.tostring(fill_bb9(scratch_9, ts, e))
    end

    local function uida(): uida
        buffer.fill(scratch_15, 0, 0)
        encode_timestamp(scratch_15, timestamp())
        encode_entropy(scratch_15, entropy(random_cache))
        return buffer.tostring(scratch_15)
    end

    local function monoa(): uida
        local ts = timestamp()
        if ts == timestamp_state then
            entropy_state += 1
            assert(entropy_state <= 0xffff_ffff, "entropy overflow")
            -- we reuse encoded timestamp here, but don't forget zero-up entropy part
            encode_entropy(monotonic_buffer_15, entropy_state, "0")
        else
            assert(ts > timestamp_state, "time travel problem")
            timestamp_state = ts
            entropy_state = entropy31()
            buffer.fill(monotonic_buffer_15, 0, 0)
            encode_timestamp(monotonic_buffer_15, timestamp_state)
            encode_entropy(monotonic_buffer_15, entropy_state)
        end
        return buffer.tostring(monotonic_buffer_15)
    end
    local function monob(): uidb
        local ts = timestamp()
        if ts == timestamp_state then
            entropy_state += 1
            assert(entropy_state <= 0xffff_ffff, "entropy overflow")
        else
            assert(ts > timestamp_state, "time travel problem")
            timestamp_state = ts
            entropy_state = entropy31()
        end
        return buffer.tostring(fill_bb9(scratch_9, timestamp_state, entropy_state))
    end
    return table.freeze {
        uida = uida,
        uidb = uidb,
        monoa = monoa,
        monob = monob,
    }
end

---@summary: unix time in milliseconds
m.timestamp = timestamp

---@summary: unix time in seconds with millisecond precision
m.time = time

local _scratch_9 = buffer.create(9)
local _scratch_15 = buffer.create(15)

function m.to_ascii(roflake: uida | uidb): uida ---@throw
    local n = type(roflake) == "string" and #roflake
    if n == 15 then
        return roflake
    elseif n == 9 then
        buffer.writestring(_scratch_9, 0, roflake)
        buffer.fill(_scratch_15, 0, 0)
        local ts = timestamp_bb9(_scratch_9)
        local e = entropy_bb9(_scratch_9)
        encode_timestamp(_scratch_15, ts)
        encode_entropy(_scratch_15, e)
        return buffer.tostring(_scratch_15)
    end
    error("not a roflake: " .. string.format("%q", tostring(roflake)))
end

function m.to_bin(roflake: uida | uidb): uidb ---@throw
    local n = type(roflake) == "string" and #roflake
    if n == 9 then
        return roflake
    elseif n == 15 then
        buffer.writestring(_scratch_15, 0, roflake)
        buffer.fill(_scratch_9, 0, 0)
        local ts = decode_timestamp(_scratch_15)
        local e = decode_entropy(_scratch_15)
        return buffer.tostring(fill_bb9(_scratch_9, ts, e))
    end
    error("not a roflake: " .. string.format("'%q'", tostring(roflake)))
end

function m.pp(o: any): str
    if m.plausible(o) then
        return m.to_ascii(o)
    end
    return tostring(o)
end

function m.to_timestamp(roflake: uida | uidb, opt: "iso8601"? ): str | int
    local n = type(roflake) == "string" and #roflake
    local timestamp: ts = 0
    if n == 9 then
        buffer.writestring(_scratch_9, 0, roflake)
        timestamp = timestamp_bb9(_scratch_9)
    elseif n == 15 then
        buffer.writestring(_scratch_15, 0, roflake)
        timestamp = decode_timestamp(_scratch_15)
    else
        error("not an uid string")
    end
    return if opt == "iso8601" then iso8601(timestamp) else timestamp
end

function m.to_entropy(roflake: uida | uidb): u32
    local n = type(roflake) == "string" and #roflake
    if n == 9 then
        buffer.writestring(_scratch_9, 0, roflake)
        return entropy_bb9(_scratch_9)
    elseif n == 15 then
        buffer.writestring(_scratch_15, 0, roflake)
        return decode_entropy(_scratch_15)
    else
        error("not an uid string")
    end
end

function m.plausible(o: any)
    local t = type(o)
    if t ~= "string" then
        return false
    end
    if #o == 15 then
        buffer.writestring(_scratch_15, 0, o)
        for i = 0, 14 do
            if ru8(DEC, ru8(_scratch_15, i)) > N_BASE then
                return false
            end
        end
    elseif #o ~= 9 then
        return false
    end
    local ts = m.to_timestamp(o) :: int
    return RF_EPOCH_MS <= ts and ts <= RF_END_OF_TIME
end

-----------------------------
-- Not thread-safe methods
-----------------------------
local STATIC_INSTANCE = m.new()
m.uida = STATIC_INSTANCE.uida
m.uidb = STATIC_INSTANCE.uidb
m.monoa = STATIC_INSTANCE.monoa
m.monob = STATIC_INSTANCE.monob
m.iso8601 = iso8601
m.date = function(timestamp_ms: int?)
    return iso8601(timestamp_ms or timestamp())
end


-- aliases
m.is = m.plausible
--[=[ generates ascii uid ]=]
m.gen = STATIC_INSTANCE.uida
--[=[ generates ascii uid ]=]
m.monotonic = STATIC_INSTANCE.monoa

function m.encode(ts: msec, uint: u32): uidb
    return buffer.tostring(fill_bb9(_scratch_9, ts, uint))
end

-----------------------------
-- Quick test
-----------------------------
assert(m.is(m.uidb()))
assert(m.is(m.uida()))
assert(not m.is("GD5XSE008YRA9D~"))
do
    local N = 1e6
    local mons = table.create(N)
    for i = 1, N do
        table.insert(mons, m.monob())
    end

    for i = 2, #mons do
        assert(mons[i - 1] < mons[i])
    end
    for i = 1, N do
        local ts = timestamp()
        local r9 = m.to_timestamp(m.uidb()) :: num
        assert(ts == r9 or ts == (r9 - 1))
    end
end

do
    local first = m.uida()
    local ts = m.timestamp()
    --[[ stylua: ignore]] repeat until m.timestamp() > ts
    local second = m.uida()
    assert(second > first)
end

do
    local E31 = 0x7FFF_FFFF
    local T = RF_EPOCH_MS
    local s9 = buffer.create(9)
    fill_bb9(s9, T, E31)
    local u1 = buffer.tostring(s9)
    assert(timestamp_bb9(s9) == T)
    assert(entropy_bb9(s9) == E31)
    local a1 = m.to_ascii(u1)
    local ba1 = buffer.fromstring(a1)
    assert(decode_timestamp(ba1) == T)
    local ea1 = decode_entropy(ba1)
    assert(ea1 == E31)
end

do
    local u1 = m.monob()
    local u2 = m.to_ascii(u1)
    assert(m.to_timestamp(u2) == m.to_timestamp(u1))
    local e1 = entropy_bb9(buffer.fromstring(u1))
    local e2 = decode_entropy(buffer.fromstring(u2))
    assert(e1 == e2)
    local u3 = m.to_bin(u2)
    assert(u3 == u1)
end

do -- test hiding something in the uid
    local E31 = 0x1234_5678
    local T = timestamp()
    local r9 = m.encode(T, E31)
    assert(m.to_timestamp(r9) == T)
    assert(m.to_entropy(r9) == E31)
    local r15 = m.to_ascii(r9)
    assert(m.to_timestamp(r15) == T)
    assert(m.to_entropy(r15) == E31)
end

--[=[ performance
--[[ stylua: ignore]] script = script or require'script'
local perfn = require(script.Parent.perfn)
perfn()
local N = 1000
perfn("RoFlake")
local _: any
perfn("uida", function()
    _ = m.uida()
end, N)
perfn("uidb", function()
    _ = m.uidb()
end, N)
perfn("monoa", function()
    _ = m.monoa()
end, N)
perfn("monob", function()
    _ = m.monob()
end, N)

--]=]

-- print("now:", m.to_timestamp(m.uidb(), "iso"))
warn("[roflake -- ok]", m.uida())
return table.freeze(m)

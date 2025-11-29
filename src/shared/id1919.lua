--!strict
--!nolint
-- MIT License
-- Copyright (c) 2023 Andrew Zhilin (https://github.com/zoon)


--[=[
    16 bit id
     6 bit kind (64..127) and 9 bit id (0..511): 0b_1kkk_kkki_iiii_iiii
    NB: most significant bit of id is always `1`, which gives us
    minimum id = 0x8000 (this is convenient for debugging)

--]=]
-- stylua: ignore

type str = string
type bool = boolean
type num = number
type uint = num
type int = num
type u32 = uint
type u20 = uint
type i32 = int
type u9 = uint
export type kind = u9
export type ord = u9
export type bits = u9
export type id = u20
export type flag = u20
export type idk = id | flag
type array<a> = { a }
type map<k, v> = { [k]: v }
type table = map<any, any>
type fun = (...any) -> ...any
local fmt = string.format

-----------------------------
-- Module
-----------------------------
local m = {}
m.__index = m

local FLAG_BIT = 0x200 -- bit 10
local IDK_BIT = 0x80000 -- bit 20
local MIN_ORD = 0
local MAX_ORD = 511

m.MIN_KIND = MIN_ORD
m.MAX_KIND = MAX_ORD
m.MIN_ORD = MIN_ORD
m.MAX_ORD = MAX_ORD

local function encode(kind: kind, ord: ord): id
    assert(MIN_ORD <= ord and ord <= MAX_ORD, "ord out of range")
    assert(MIN_ORD <= kind and kind <= MAX_ORD, "kind out of range")
    return bit32.bor(0x80000, bit32.lshift(kind, 10), ord)
end

local function encode_flag(kind: kind, bits: bits): flag
    return bit32.bor(encode(kind, bits), FLAG_BIT)
end

local MIN_IDK = encode(MIN_ORD, MIN_ORD)
local MAX_IDK = encode_flag(MAX_ORD, MAX_ORD)
warn(fmt("id1919: note: id is in [0x%X .. 0x%X]", MIN_IDK, MAX_IDK))

local function decode(id: id): (kind, ord | bits)
    if not id then
        error(debug.traceback("id is nil"))
    end
    if MIN_IDK <= id and id <= MAX_IDK then
        -- ok
    else
        error(debug.traceback(fmt("id out of range: 0x%X", id)))
    end
    assert(MIN_IDK <= id and id <= MAX_IDK)
    return bit32.band(0x1ff, bit32.rshift(id, 10)), bit32.band(0x1ff, id)
end

local function has_single_bit(x: u32): bool
    return not (x == 0 or bit32.btest(x, x - 1))
end

m.encode = encode
m.decode = decode

local function plausible(id: any): bool
    -- number, integer, in range
    return type(id) == "number" and MIN_IDK <= id and id <= MAX_IDK and math.ceil(id) == id
end
assert(not plausible(-1))

function m.is_flags(id: any): bool
    return plausible(id) and bit32.btest(id, FLAG_BIT)
end

function m.is_id(id: any): bool
    return plausible(id) and not bit32.btest(id, FLAG_BIT)
end

m.plausible = plausible
m.is = m.plausible -- alias

do -- iota and flags
    local iter: fun
    function m.iota(kind: num | any, first: num?, step: num?, last: num?): id
        if type(kind) == "number" then
            assert(kind == bit32.bor(kind) and MIN_ORD <= kind and kind <= MAX_ORD, "not a valid kind")
            first = first or MIN_ORD
            step = step or 1
            last = last or MAX_ORD
            iter = coroutine.wrap(function()
                for i = first :: num, last :: num, step :: num do
                    coroutine.yield(encode(kind, i))
                end
                error(fmt("~> %* %* ", last, step))
            end)
        end
        assert(iter, "you must initialize `iota` with `kind`")
        local ok, id = pcall(iter)
        if not ok then
            error("out-of-range: " .. tostring(id :: str), 2)
        end
        return id
    end

    function m.flag(kind: kind | any?): flag
        if type(kind) == "number" then
            assert(MIN_ORD <= kind and kind <= MAX_ORD, "not a valid kind")
            iter = coroutine.wrap(function()
                coroutine.yield(encode_flag(kind, 0))
                for i = 0, 8 do
                    coroutine.yield(encode_flag(kind, 2 ^ i))
                end
                error("~> flag must be 9 bit max")
            end)
        end
        assert(iter, "you must initialize `flag` with `kind`")
        local ok, id = pcall(iter)
        if not ok then
            error("out-of-range: " .. tostring(id :: str), 2)
        end
        return id
    end
end

do
    local function or_loop(accu: uint, kind: kind, f1: flag?, ...: flag): uint
        if f1 then
            local fk, ff = decode(f1)
            if fk ~= kind then
                error("wrong kind of arg")
            end
            return or_loop(bit32.bor(accu, ff), kind, ...)
        end
        return accu
    end

    function m.flag_test(flags: flag, f1: flag, ...: flag): bool
        local kind, _ = decode(flags)
        local rest = or_loop(0, kind, f1, ...)
        return bit32.btest(flags, rest)
    end

    function m.flag_or(f: flag, f1: flag, ...: flag): flag
        local kind, flags = decode(f)
        flags = or_loop(flags, kind, f1, ...)
        return encode_flag(kind, flags)
    end

    function m.flag_set(flags: flag, f: flag, bool: bool): flag
        local flags_kind, flag_bits = decode(flags)
        local fk, ff = decode(f)
        if fk ~= flags_kind then
            error("wrong kind of arg")
        end
        if not has_single_bit(ff) then
            error("arg#2 not a single bit")
        end
        if bool then
            flags = bit32.bor(flags, ff)
        elseif bit32.btest(flags, ff) then
            flags = bit32.bxor(flags, ff)
        else
            return flags
        end
        return flags
    end

    local function split_loop(kind: kind, bits: u9): ...flag
        if bits ~= 0 then
            local flag = bit32.countrz(bits)
            bits = bit32.replace(bits, 0, flag, 1)
            return encode_flag(kind, bit32.lshift(1, flag)), split_loop(kind, bits)
        end
    end

    function m.flag_split(flags: flag): ...flag
        local kind, bits = decode(flags)
        if bits == 0 or has_single_bit(bits) then
            return flags
        end
        return split_loop(kind, bits)
    end

    local function popcount(x: u32): int
        local count = 0
        while x ~= 0 do
            count = count + 1
            x = bit32.band(x, x - 1)
        end
        return count
    end

    local POPCOUNT_U9 = {} :: map<int, int>
    for i = 0, 0x1ff do
        POPCOUNT_U9[i] = popcount(i)
    end
    table.freeze(POPCOUNT_U9)

    function m.flag_count(flags: flag): int
        local kind, bits = decode(flags)
        return POPCOUNT_U9[bits]
    end
end
-----------------------------
-- Quick test
-----------------------------
for k = m.MIN_KIND, m.MAX_KIND do
    local ord = math.random(MIN_ORD, MAX_ORD)
    local kid = encode(k, ord)
    local kind, ord1 = decode(kid)
    if kind ~= k or ord1 ~= ord then
        error(fmt("%* -> %* | %* -> %*", k, kind, ord, ord1))
    end
end

repeat -- usage example and test
    if workspace then -- repl only
        break
    end

    local En = require("./Enum")

    local Id = {}
    Id.__index = Id
    local KindToIds = {} :: { [int]: En.Enum }

    -- stylua: ignore
    -----------------------------
    -- Kind
    -----------------------------
    Id.Kind = En.with_id "KindOfId" {
        Pet     = En.iota(MIN_ORD, 1, MAX_ORD),
        Egg     = En.iota'',
        Area    = En.iota'',
        Enchant = En.iota'',
        PetF    = En.iota'',
    }

    -- stylua: ignore
    -----------------------------
    -- Pet
    -----------------------------
    Id.Pet = En.with_id "Id.Pet" {
        CAT  = m.iota(Id.Kind.Pet, 1),
        DOG  = m.iota'',
        DOG1 = m.iota'',
        DOG2 = m.iota'',
    }
    KindToIds[Id.Kind.Pet] = Id.Pet
    type Pet = typeof(Id.Pet) -- consider to export

    -- stylua: ignore
    -----------------------------
    -- Egg
    -----------------------------
    Id.Egg = En.with_id "Id.Egg" {
        Common   = m.iota(Id.Kind.Egg, 0, 1, m.MAX_ORD),
        Uncommon = m.iota'',
    }
    KindToIds[Id.Kind.Egg] = Id.Egg
    type Egg = typeof(Id.Egg) -- consider to export

    -- stylua: ignore
    -----------------------------
    -- PetF
    -----------------------------
    Id.PetF = En.with_id "Id.PetF" {
        NONE         = m.flag(Id.Kind.PetF),
        EQUIPPED     = m.flag'',
        ENABLED      = m.flag'',
        BOUGHT       = m.flag'',
        __RESERVED_1 = m.flag'',
        __RESERVED_2 = m.flag'',
    }
    KindToIds[Id.Kind.PetF] = Id.PetF
    export type PetF = typeof(Id.PetF)

    -- test flags
    local _, x = decode(Id.PetF.EQUIPPED)
    assert(x == 1)
    assert(m.flag_test(Id.PetF.ENABLED, Id.PetF.ENABLED))
    assert(not m.flag_test(Id.PetF.ENABLED, Id.PetF.BOUGHT))
    local flags = m.flag_or(Id.PetF.ENABLED, Id.PetF.BOUGHT)
    assert(m.flag_test(flags, Id.PetF.ENABLED, Id.PetF.BOUGHT))
    assert(not m.flag_test(flags, Id.PetF.EQUIPPED))
    flags = m.flag_set(flags, Id.PetF.EQUIPPED, true)
    assert(m.flag_test(flags, Id.PetF.EQUIPPED))
    flags = m.flag_set(flags, Id.PetF.EQUIPPED, false)
    flags = m.flag_set(flags, Id.PetF.EQUIPPED, false)
    assert(not m.flag_test(flags, Id.PetF.EQUIPPED))

    local pet_flags = m.flag_or(Id.PetF.EQUIPPED, Id.PetF.ENABLED, Id.PetF.BOUGHT)
    assert(m.flag_count(pet_flags) == 3, "flags count failed")
    local a, b, c = m.flag_split(pet_flags)
    assert(a == Id.PetF.EQUIPPED)
    assert(b == Id.PetF.ENABLED)
    assert(c == Id.PetF.BOUGHT)

    -- test ids
    local k, _ = decode(Id.Pet.DOG)
    assert(Id.Kind:key(k) == "Pet")
    assert(Id.Pet:key(Id.Pet.DOG) == "DOG")

    function Id:name(id: any)
        assert(self == Id, "add `:` to call")
        if not m.plausible(id) then
            return tostring(id)
        end
        local k, _ = decode(id)
        local en = KindToIds[k]
        if not en or not en:peek(id) then
            return "?" .. tostring(id)
        end
        return en:full_name(id)
    end

    function Id:key(id: id)
        assert(self == Id, "add `:` to call")
        local k, _ = decode(id)
        local en = KindToIds[k]
        if not en then
            return "?" .. tostring(id)
        end
        return en:key(id)
    end
until true

warn("[id1919 -- ok]")

return m

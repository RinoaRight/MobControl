--!strict
-- MIT License
-- Copyright (c) 2024 Andrew Zhilin (https://github.com/zoon)

--[[ stylua: ignore]] script = script or require'script'
local idk = require(script.Parent.id1919)
local roflake = require(script.Parent.roflake)
local struct = require(script.Parent.struct)
local enum = require(script.Parent.enum)

type str = string
type bool = boolean
type num = number
type integer = num
type uint = integer
type int = integer
type u32 = uint
type i32 = int
type u16 = uint
type kind = idk.kind
type ord = idk.ord
type idk = idk.idk
export type id = idk.id
export type flag = idk.flag

type array<a> = { a }
type table = { [any]: any }
type map<k, v> = { [k]: v }
type fun = (...any) -> ...any
local fmt = string.format

local iota = idk.iota
local flag = idk.flag
local _encode = idk.encode
local decode = idk.decode

-----------------------------
-----------------------------
-- Module
-----------------------------
-----------------------------
local Id = {}
Id.__index = Id

-----------------------------
-----------------------------
-- Kind Declaration
-----------------------------
-----------------------------
-- stylua: ignore
local Kind = table.freeze {
    NONE            = enum.iota(idk.MIN_KIND, 1, idk.MAX_KIND),
    Struct          = enum.iota'',
    ServerError     = enum.iota'',
    Boost           = enum.iota'',
    Pet             = enum.iota'',
    Egg             = enum.iota'',
    Area            = enum.iota'',
    Effect          = enum.iota'',
    Ability         = enum.iota'',
    Animation       = enum.iota'',
    Product         = enum.iota'',
    Pass            = enum.iota'',
    PassF           = enum.iota'',
    Countable       = enum.iota'',
    Weapon          = enum.iota'',
    PlayerStats     = enum.iota'',
    TimedEvent      = enum.iota'',
    STMState        = enum.iota'',
    -- protocol:
    S2S             = enum.iota(110, 1, idk.MAX_KIND),
    S2C             = enum.iota'',
    S2CC            = enum.iota'',
    C2S             = enum.iota'',
    C2C             = enum.iota'',
    US2CC           = enum.iota'', -- unreliable broadcast
    RS2CC           = enum.iota'', -- reliable broadcast
    -- states:
    Quest           = "Quest",
    TestF           = enum.iota''
}
Id.Kind = Kind

local KIND_TO_ENUM: map<kind, enum.Enum> = {}

-----------------------------
-- Id methods
-----------------------------
do -- Id methods fold
    local function _check_arg<a>(o: a): ()
        return o == Id and error("remove `:` from call", 3)
    end

    --- Retrieves an Enum object by its kind name
    --- @param name string The name of the kind to look up
    --- @return Enum The corresponding enum object
    --- @throws Error if the kind name is not found
    function Id.enum_by_kind_name(name: str): enum.Enum
        _check_arg(name)
        local kind = Id.Kind[name] :: id
        return kind and KIND_TO_ENUM[kind] or error("can't find: " .. name)
    end

    local _id_full_name_cache: { [id]: str } = {}
    --- Gets the full name of an id
    --- @param id any The id to get the name for
    --- @return string The full name of the id, or string representation if not an id
    function Id.name(id: any): str
        _check_arg(id)
        if not idk.is(id) then
            return tostring(id)
        end
        if not _id_full_name_cache[id] then
            local k, _ = idk.decode(id)
            local en = KIND_TO_ENUM[k]
            if not en or not en:peek(id) then
                return tostring(id)
            end
            _id_full_name_cache[id] = en:full_name(id)
        end
        return _id_full_name_cache[id]
    end

    --- Gets the key (short name) for an id
    --- @param id id The id to get the key for
    --- @return string The key of the id, or "?{id}" if invalid
    --- @throws Error if the input is not a valid id
    function Id.key(id: id)
        _check_arg(id)
        assert(idk.plausible(id), "not an id")
        local kind, _ord = idk.decode(id)
        local enum = KIND_TO_ENUM[kind]
        if not enum or not enum:peek(id) then
            return "?" .. tostring(id)
        end
        return enum:key(id)
    end

    --- Checks if a value is a plausible id
    --- @param o any The value to check
    --- @return boolean True if the value is a plausible id
    Id.is = idk.plausible

    --- Checks if a value is a valid id (stricter than is())
    --- @param id any The value to check
    --- @return boolean True if the value is a valid id
    Id.is_id = idk.is_id

    --- Checks if a value is a valid flag
    --- @param flag any The value to check
    --- @return boolean True if the value is a valid flag
    Id.is_flag = idk.is_flags

    --- Combines multiple flags using OR operation
    --- @param flag flag The first flag
    --- @param ... flag Additional flags to combine
    --- @return id The combined flag value
    Id.flag_or = idk.flag_or

    ---Tests if flags are set
    --- @param flag flag The flags to test
    --- @param ... flag The flags to check for
    --- @return boolean True if all specified flags are set
    Id.flag_test = idk.flag_test

    --- Sets or unsets a flag in a flag combination
    --- @param flags flag The current flags
    --- @param flag flag The flag to modify
    --- @param state boolean True to set the flag, false to unset
    --- @return flag The modified flags
    Id.flag_set = idk.flag_set

    --- Splits a combined flag into individual flags
    --- @param flag flag The combined flags to split
    --- @return ...flag The individual flags
    Id.flag_split = idk.flag_split

    --- Counts the number of flags set in a flag combination
    --- @param flag flag The combined flags to count
    --- @return integer The number of flags that are set
    Id.flag_count = idk.flag_count

    --- Pretty prints any value, with special handling for ids, flags, roflakes, and structs
    --- @param o any The value to pretty print
    --- @return string The formatted string representation
    function Id.pp(o: any): str
        _check_arg(o)
        if idk.plausible(o) then
            if idk.is_flags(o) then
                local count = idk.flag_count(o)
                if count < 2 then
                    return Id.name(o)
                end
                local flags = { idk.flag_split(o) } :: any
                flags[1] = Id.name(flags[1])
                for i = 2, count do
                    flags[i] = Id.key(flags[i])
                end
                return table.concat(flags, "|")
            end
            return Id.name(o)
        elseif roflake.plausible(o) then
            return roflake.pp(o)
        elseif struct.is(o) then
            local out = {}
            local mt = assert(getmetatable(o))
            local tag_id = o[#o + 1]
            for i = 1, #o do
                table.insert(out, fmt("%*: %*", Id.pp(mt[i]), Id.pp(o[i])))
            end
            return fmt("%*:[%*]", Id.key(tag_id), table.concat(out, ", "))
        elseif type(o) == "number" and o ~= math.floor(o) then -- only for floats
            return fmt("%.7g", o)
        elseif type(o) == "vector" then
            return fmt("(%.7g, %.7g, %.7g)", o.X, o.Y, o.Z)
        end
        return tostring(o)
    end

    --- Creates an id from a kind and ordinal number
    --- @param of_kind integer The kind to create the id for
    --- @param ord integer The ordinal number
    --- @return id The created id
    function Id.from_ordinal(of_kind: int, ord: int): id
        _check_arg(of_kind)
        return idk.encode(of_kind, ord)
    end

    --- Gets the ordinal number from an id
    --- @param id id The id to get the ordinal from
    --- @param of_kind? integer Optional kind to verify against
    --- @return integer The ordinal number
    --- @throws Error if id is invalid or kind doesn't match
    function Id.to_ordinal(id: id, of_kind: int?)
        _check_arg(id)
        assert(idk.plausible(id), "not an id")
        local kind, ord = idk.decode(id)
        if of_kind then
            assert(of_kind == kind, "wrong kind")
        end
        return ord
    end

    --- Calculates the distance between two ids of the same kind
    --- @param a id The first id
    --- @param b id The second id
    --- @return integer The distance between the ids
    --- @throws Error if either input is invalid or kinds don't match
    function Id.distance(a: id, b: id)
        _check_arg(a)
        assert(Id.is_id(a), "arg 1 not an id")
        assert(Id.is_id(b), "arg 2 not an id")
        local ak, ai = decode(a)
        local bk, bi = decode(b)
        assert(ak == bk, "ids must be the same kind")
        return bi - ai
    end

    --- Gets the string representation (key) of an id or flag if available
    --- @param id any The id or flag to peek at
    --- @return string? The string representation (key), or nil if not available
    function Id.peek(id: any): str?
        _check_arg(id)
        if idk.plausible(id) then
            local k, _ = decode(id)
            local en = KIND_TO_ENUM[k]
            return en and en:peek(id) :: str?
        end
        return nil
    end

    --- Gets the enum object associated with an id
    --- @param id id The id or flag to get the enum for
    --- @return Enum The associated enum object
    --- @throws Error if no enum is found for the id's kind
    function Id.enum(id: id): enum.Enum
        _check_arg(id)
        local k, _i = decode(id)
        return assert(KIND_TO_ENUM[k])
    end

    --- Gets the kind of an id or flag
    --- @param id? id The id to get the kind from
    --- @return kind The kind of the id, or NONE if invalid/nil
    function Id.kind(id: id?)
        _check_arg(id)
        if id and idk.plausible(id) then
            return (decode(id))
        end
        return Id.Kind.NONE
    end

    --- Casts an id to a different kind
    --- @param id id The id to cast
    --- @param kind kind The target kind
    --- @return id The cast id
    --- @throws Error if the cast is invalid
    function Id.cast_id_to_kind(id: id, kind: kind): id
        _check_arg(id)
        local key = Id.key(id)
        if not key then
            error("invalid id:" .. Id.name(id))
        end
        local other = KIND_TO_ENUM[kind] :: any
        if not other then
            error("wrong kind: " .. (Id.Kind[kind] or kind))
        end
        if not other:peek(key) then
            error("id: " .. Id.name(id) .. " not linked to " .. (Id.Kind[kind] or kind))
        end
        return other[key]
    end

    --- Parses a string representation of an id
    --- @param str string The string to parse (format: "Id.kind.xxx" or "kind.xxx")
    --- @return id? The parsed id, or nil if invalid format
    function Id.parse(str): id?
        local m, kind, id = string.match(str, "(%w+)[.](%w+)[.]?(%w*)")
        if id == "" then
            kind, id = m, kind
        elseif m ~= "Id" then
            return nil
        end
        local e = Id.enum_by_kind_name(kind :: str)
        return if e ~= nil then e:peek(id) :: id? else nil
    end
end -- end of fold
-----------------------------
-----------------------------
-- Id Declarations
-----------------------------
-----------------------------
-- stylua: ignore
-----------------------------
-- TestF
-----------------------------
---[[
Id.TestF = enum.with_id "Id.TestFlags" {
    NONE = flag(Id.Kind.TestF),
    A  = flag'',
    B  = flag'',
    C  = flag'',
    _1 = flag'',
    _2 = flag'',
    _3 = flag'',
    _4 = flag'',
    _5 = flag'',
    _6 = flag'',
}
KIND_TO_ENUM[Id.Kind.TestF] = Id.TestF
export type TestF = typeof(Id.TestF)
do
    local abc = idk.flag_or(Id.TestF.A, Id.TestF.B, Id.TestF.C)
    assert(Id.pp(abc) == "Id.TestFlags.A|B|C")
    abc = Id.flag_set(abc, Id.TestF.A, false)
    abc = Id.flag_set(abc, Id.TestF.B, false)
    abc = Id.flag_set(abc, Id.TestF.C, false)
    assert(Id.pp(abc) == "Id.TestFlags.NONE")
end
--]]
-- stylua: ignore
-----------------------------
-- Struct
-----------------------------
Id.Struct = enum.with_id "Id.Struct" {
    __NONE           = iota(Id.Kind.Struct, 0),
    MissionNode      = iota'',
    ObjectiveSetNode = iota'',
    Objective        = iota'',
}
KIND_TO_ENUM[Id.Kind.Struct] = Id.Struct
export type Struct = typeof(Id.Struct)

-- stylua: ignore
-----------------------------
-- Boost
-----------------------------
Id.Boost = enum.with_id "Id.Boost" {
    NONE                = iota(Id.Kind.Boost, 0),
    ADD_CLONE           = iota'',
    BULLET_SPEED_MULT   = iota'',
    CHANGE_WEAPON       = iota'',
}
KIND_TO_ENUM[Id.Kind.Boost] = Id.Boost
export type Boost = typeof(Id.Boost)

-- stylua: ignore
-----------------------------
-- Pet
-----------------------------
Id.Pet = enum.with_id "Id.Pet" {
    NONE = iota(Id.Kind.Pet, 0)
}
KIND_TO_ENUM[Id.Kind.Pet] = Id.Pet
export type Pet = typeof(Id.Pet)

-- stylua: ignore
-----------------------------
-- Egg
-----------------------------
Id.Egg = enum.with_id "Id.Egg" {
    NONE = iota(Id.Kind.Egg, 0),
}
KIND_TO_ENUM[Id.Kind.Egg] = Id.Egg
export type Egg = typeof(Id.Egg)


-- stylua: ignore
-----------------------------
-- Area
-----------------------------
Id.Area = enum.with_id "Id.Area" {
    __HEAVEN = iota(Id.Kind.Area, 200),
    STORE    = iota''
}
KIND_TO_ENUM[Id.Kind.Area] = Id.Area
export type Area = typeof(Id.Area)


-- stylua: ignore
-----------------------------
-- Effect
-----------------------------
Id.Effect = enum.with_id "Id.Effect" {
    NONE           = iota(Id.Kind.Effect, 0),
    GEM_DROP       = iota'',
    GEM_DROP_TEAM  = iota'',
    COIN_DROP      = iota'',
    COIN_DROP_TEAM = iota'',
    SPEED          = iota'',
    SPEED_TEAM     = iota'',
    HIT_SPEED      = iota'',
    HIT_SPEED_TEAM = iota'',
}
KIND_TO_ENUM[Id.Kind.Effect] = Id.Effect
export type Effect = typeof(Id.Effect)

-- stylua: ignore
-----------------------------
-- Ability
-----------------------------
Id.Ability = enum.with_id "Id.Ability" {
    NONE   = iota(Id.Kind.Ability, 0),
    COIN_1 = iota'',
    GEM_1  = iota'',
}
KIND_TO_ENUM[Id.Kind.Ability] = Id.Ability
export type Ability = typeof(Id.Ability)

-- stylua: ignore
-----------------------------
-- Pass
-----------------------------
Id.Pass = enum.with_id "Id.Pass" {
    NONE = iota(Id.Kind.Pass, 0),
}
KIND_TO_ENUM[Id.Kind.Pass] = Id.Pass
export type Pass = typeof(Id.Pass)


-- stylua: ignore
-----------------------------
-- PassF
-----------------------------
Id.PassF = enum.with_id "Id.PassF" {
    NONE    = flag(Id.Kind.PassF),
    BOUGHT  = flag'',
    GRANTED = flag'',
    TEMP    = flag'',
}
KIND_TO_ENUM[Id.Kind.PassF] = Id.PassF
export type PassF = typeof(Id.PassF)

-- stylua: ignore
-----------------------------
-- Product
-----------------------------
Id.Product = enum.with_id "Id.Product" {
    NONE = iota(Id.Kind.Product, 0),
}
KIND_TO_ENUM[Id.Kind.Product] = Id.Product
export type Product = typeof(Id.Product)

-- stylua: ignore
-----------------------------
-- Countable
-----------------------------
Id.Countable = enum.with_id "Id.Countable" {
    _NONE = iota(Id.Kind.Countable, 0),
    COIN = iota'',
}
KIND_TO_ENUM[Id.Kind.Countable] = Id.Countable
export type Countable = typeof(Id.Countable)

-- stylua: ignore
-----------------------------
-- Weapon
-----------------------------
Id.Weapon = enum.with_id "Id.Weapon" {
    _NONE   = iota(Id.Kind.Weapon, 0),
    DEFAULT = iota'',
    BASIC   = iota'',
}
KIND_TO_ENUM[Id.Kind.Weapon] = Id.Weapon
export type Weapon = typeof(Id.Weapon)

-- stylua: ignore
-----------------------------
-- Timed event
-----------------------------
Id.TimedEvent = enum.with_id "Id.TimedEvent" {
    _NONE           = iota(Id.Kind.TimedEvent, 0),
    WEAPON_COOLDOWN = iota'',
}
KIND_TO_ENUM[Id.Kind.TimedEvent] = Id.TimedEvent
export type TimedEvent = typeof(Id.TimedEvent)

-- stylua: ignore
-----------------------------
-- Animation
-----------------------------
Id.Animation = enum.with_id "Id.Animation" {
    _NONE   = iota(Id.Kind.Animation, 0),
    HOLD    = iota'',
}
KIND_TO_ENUM[Id.Kind.Animation] = Id.Animation
export type Animation = typeof(Id.Animation)

-- stylua: ignore
-----------------------------
-- Player stats
-----------------------------
Id.PlayerStats = enum.with_id "Id.PlayerStats" {
    _NONE   = iota(Id.Kind.PlayerStats, 0),
    WEAPON  = iota'',
}
KIND_TO_ENUM[Id.Kind.PlayerStats] = Id.PlayerStats
export type PlayerStats = typeof(Id.PlayerStats)

-- stylua: ignore
-----------------------------
-- ServerError
-----------------------------
Id.ServerError = enum.with_id "Id.ServerError" {
    NONE       = iota(Id.Kind.ServerError, 0),
    NOT_ENOUGH = iota''
}
KIND_TO_ENUM[Id.Kind.ServerError] = Id.ServerError
export type ServerError = typeof(Id.ServerError)

-- stylua: ignore
-----------------------------
-- STMState
-----------------------------
Id.STMState = enum.with_id "Id.STMState" {
    _NONE             = iota(Id.Kind.STMState, 0),
    INGAME            = iota'',
    ACHIEVEMENTS      = iota'',
    BOOSTS            = iota'',
    DIALOGUE          = iota'',
    INVENTORY         = iota'',
    INVENTORY_COFFINS = iota'',
    INVENTORY_TOOLS   = iota'',
    LEVELING          = iota'',
    PET_ENCHANT       = iota'',
    PET_HATCHING      = iota'',
    PET_UPGRADE       = iota'',
    RAFFLE            = iota'',
    SETTINGS          = iota'',
    SHOP              = iota'',
    TELEPORT          = iota'',
}
KIND_TO_ENUM[Id.Kind.STMState] = Id.STMState
export type STMState = typeof(Id.STMState)
-----------------------------
-----------------------------
-- Protocols
-----------------------------
-----------------------------
-- stylua: ignore
-----------------------------
-- S2S
-----------------------------
Id.S2S = enum.with_id "Id.S2S" {
    _NONE = iota(Id.Kind.S2S, 0),
    PASS_GRANTED      = iota'',
    PURCHASE_FINISHED = iota'',
}
KIND_TO_ENUM[Id.Kind.S2S] = Id.S2S
export type S2S = typeof(Id.S2S)

-- stylua: ignore
-----------------------------
-- C2S
-----------------------------
Id.C2S = enum.with_id "Id.C2S" {
    _NONE              = iota(Id.Kind.C2S, 0),
    BOOSTER_HIT        = iota'',               -- booster_guid
    BULLET_SHOT        = iota'',               -- pos

}
KIND_TO_ENUM[Id.Kind.C2S] = Id.C2S
export type C2S = typeof(Id.C2S)

-- stylua: ignore
-----------------------------
-- S2C
-----------------------------
Id.S2C = enum.with_id "Id.S2C" {
    _NONE         = iota(Id.Kind.S2C, 0),
    UPDATE_STATE  = iota'',
    INIT_WORLD    = iota'',
    UPDATE_WORLD  = iota'',
}
KIND_TO_ENUM[Id.Kind.S2C] = Id.S2C
export type S2C = typeof(Id.S2C)

-- stylua: ignore
-----------------------------
-- S2CC
-----------------------------
Id.S2CC = enum.with_id "Id.S2CC" {
    _NONE                   = iota(Id.Kind.S2CC, 0),
    PLAYER_STARTED_SESSION  = iota'', -- player_id
    PLAYER_STOPPED_SESSION  = iota'', -- player_id
    PLAYER_CHANGED_WEAPON   = iota'', -- player_id, weapon_id
}
KIND_TO_ENUM[Id.Kind.S2CC] = Id.S2CC
export type S2CC = typeof(Id.S2CC)

-----------------------------
-- Quick test
-----------------------------
--[[
local log = logger.create("Id-test")
    :set_prettifier(Id.pp)
    :set_level(logger.LOG_LEVELS.DEBUG)
    :set_output(warn)
    :set_delimiter(", ")
local trace = log:make_level_logger("trace")
local _cr = struct.define(Id.Struct.MissionNode) {
    A = 1,
    B = 2,
}
local _id = Id.cast_id_to_kind(Id.Pet.NONE, Id.Kind.Egg)
trace(_id, 32768, _cr { A = _id, B = 32768 }, Vector3.new(math.pi, math.pi, math.pi), roflake.monob())
local m = log:get_metrics()
print(logger.format_metrics(m))
local start = os.clock()
local _ = logger.internal.format_message(Id.pp, ", ", "~~> ", _id, 32768, _cr { A = _id, B = 32768 }, Vector3.new(math.pi, math.pi, math.pi), roflake.monob())
local elapsed = os.clock() - start
print(elapsed)
start = os.clock()
print(_)
elapsed = os.clock() - start
print(elapsed)
logger.global:set_level(logger.LOG_LEVELS.DEBUG)
logger.set_global_level(logger.LOG_LEVELS.DEBUG)
--]]

warn("[Id -- ok]")

return Id

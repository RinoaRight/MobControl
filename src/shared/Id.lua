--!strict
-- MIT License
-- Copyright (c) 2024 Andrew Zhilin (https://github.com/zoon)

--[[ stylua: ignore]] script = script or require'./script'
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
    NONE                         = enum.iota(idk.MIN_KIND, 1, idk.MAX_KIND),
    Struct                       = enum.iota'',
    ServerError                  = enum.iota'',
    Boost                        = enum.iota'',
    Bomb                         = enum.iota'',
    Achievement                  = enum.iota'',
    Animation                    = enum.iota'',
    Product                      = enum.iota'',
    Pass                         = enum.iota'',
    PassF                        = enum.iota'',
    PlayerF                      = enum.iota'',
    WorldF                       = enum.iota'',
    EnemyF                       = enum.iota'',
    PlayerUpgradePersistent      = enum.iota'',
    PlayerUpgradeNonPersistent   = enum.iota'',
    CountablePersistent          = enum.iota'',
    CountableNonPersistent       = enum.iota'',
    Clone                        = enum.iota'',
    Weapon                       = enum.iota'',
    Enemy                        = enum.iota'',
    EnemyFlying                  = enum.iota'',
    Obstacle                     = enum.iota'',
    PlayerSpecs                  = enum.iota'',
    WorldSpecs                   = enum.iota'',
    TimedEvent                   = enum.iota'',
    Sound                        = enum.iota'',
    VFX                          = enum.iota'',
    STMState                     = enum.iota'',
    -- protocol:
    S2S                          = enum.iota(110, 1, idk.MAX_KIND),
    S2C                          = enum.iota'',
    S2CC                         = enum.iota'',
    C2S                          = enum.iota'',
    C2C                          = enum.iota'',
    US2SS                        = enum.iota'', -- unreliable broadcast
    RS2SS                        = enum.iota'', -- reliable broadcast
    -- states:
    Quest                        = "Quest",
    TestF                        = enum.iota''
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
    _NONE                = iota(Id.Kind.Boost, 0),
    ADD_CLONE           = iota'',
    -- BULLET_SPEED_MULT   = iota'',
    CHANGE_WEAPON       = iota'',
    FIRST_AID_KIT       = iota'',
}
KIND_TO_ENUM[Id.Kind.Boost] = Id.Boost
export type Boost = typeof(Id.Boost)

-- stylua: ignore
-----------------------------
-- PlayerUpgradePersistent
-----------------------------
Id.PlayerUpgradePersistent = enum.with_id "Id.PlayerUpgradePersistent" {
    _NONE               = iota(Id.Kind.PlayerUpgradePersistent, 0),
    FIREPOWER_1        = iota'',
    FIREPOWER_2        = iota'',
    FIREPOWER_3        = iota'',
    FIREPOWER_4        = iota'',
    FIREPOWER_5        = iota'',
    HITPOINTS_1        = iota'',
    HITPOINTS_2        = iota'',
    HITPOINTS_3        = iota'',
    HITPOINTS_4        = iota'',
    HITPOINTS_5        = iota'',
    INIT_CLONE_1       = iota'',
    INIT_CLONE_2       = iota'',
    INIT_CLONE_3       = iota'',
    XP_MULT              = iota'',
}
-- TODO: add all-players upgrades? weapon unlocks? drones?
KIND_TO_ENUM[Id.Kind.PlayerUpgradePersistent] = Id.PlayerUpgradePersistent
export type PlayerUpgradePersistent = typeof(Id.PlayerUpgradePersistent)

-- stylua: ignore
-----------------------------
-- PlayerUpgradeNonPersistent
-----------------------------
Id.PlayerUpgradeNonPersistent = enum.with_id "Id.PlayerUpgradeNonPersistent" {
    _NONE                 = iota(Id.Kind.PlayerUpgradeNonPersistent, 0),
    INVINCIBILITY        = iota'',
    FIREPOWER            = iota'',
    SHIELD               = iota'',
    -- DRONES               = iota'',
    BULLET_SPEED_MULT    = iota'',
    CLONE_FACTORY        = iota'',
    -- TODO: the rest of the upgrades
    SHIELD_RECHARGE      = iota'',
    SHIELD_DAMAGE        = iota'',
    SHIELD_COOLDOWN_MULT = iota'',
}
-- TODO: add all-players upgrades? weapon unlocks? drones?
KIND_TO_ENUM[Id.Kind.PlayerUpgradeNonPersistent] = Id.PlayerUpgradeNonPersistent
export type PlayerUpgradeNonPersistent = typeof(Id.PlayerUpgradeNonPersistent)

-- stylua: ignore
-----------------------------
-- Pass
-----------------------------
Id.Pass = enum.with_id "Id.Pass" {
    _NONE = iota(Id.Kind.Pass, 0),
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
-- PlayerF
-----------------------------
Id.PlayerF = enum.with_id "Id.PlayerF" {
    _NONE                 = flag(Id.Kind.PlayerF),
    _PERSISTENT          = flag'', 
    OTHER_BULLETS_ON     = flag'',
    OTHER_CLONES_ON      = flag'',
    _NON_PERSISTENT      = flag'', 
    READY                = flag'',
    BOOSTER_TOUCHED      = flag'',
    PERK_ACQUIRED        = flag'',
    PERK_ACTIVE          = flag'',
}
KIND_TO_ENUM[Id.Kind.PlayerF] = Id.PlayerF
export type PlayerF = typeof(Id.PlayerF)
--[[
```luau
-- usage:
local flags = Id.flag_or(Id.PlayerF.BOUGHT, Id.PlayerF.GRANTED, Id.PlayerF.TEMP)
warn("flags", Id.pp(flags), Id.flag_test(flags, Id.PlayerF.BOUGHT))
```
--]]

-- stylua: ignore
-----------------------------
-- EnemyF
-----------------------------
Id.EnemyF = enum.with_id "Id.EnemyF" {
    NONE                     = flag(Id.Kind.EnemyF),
    SEEK_ACTIVATED           = flag'',
}
KIND_TO_ENUM[Id.Kind.EnemyF] = Id.EnemyF
export type EnemyF = typeof(Id.EnemyF)

-- stylua: ignore
-----------------------------
-- WorldF
-----------------------------
Id.WorldF = enum.with_id "Id.WorldF" {
    _NONE                     = flag(Id.Kind.WorldF),
    -- SEEK_ACTIVATED           = flag'',
}
KIND_TO_ENUM[Id.Kind.WorldF] = Id.WorldF
export type WorldF = typeof(Id.WorldF)

-- stylua: ignore
-----------------------------
-- Product
-----------------------------
Id.Product = enum.with_id "Id.Product" {
    _NONE = iota(Id.Kind.Product, 0),
}
KIND_TO_ENUM[Id.Kind.Product] = Id.Product
export type Product = typeof(Id.Product)

-- stylua: ignore
-----------------------------
-- CountablePersistent
-----------------------------
Id.CountablePersistent = enum.with_id "Id.CountablePersistent" {
    _NONE = iota(Id.Kind.CountablePersistent, 0),
    COIN = iota'',
}
KIND_TO_ENUM[Id.Kind.CountablePersistent] = Id.CountablePersistent
export type CountablePersistent = typeof(Id.CountablePersistent)

-- stylua: ignore
-----------------------------
-- CountableNonPersistent
-----------------------------
Id.CountableNonPersistent = enum.with_id "Id.CountableNonPersistent" {
    _NONE = iota(Id.Kind.CountableNonPersistent, 0),
    CLONE = iota'',
    -- XP    = iota'',
}
KIND_TO_ENUM[Id.Kind.CountableNonPersistent] = Id.CountableNonPersistent
export type CountableNonPersistent = typeof(Id.CountableNonPersistent)

-- stylua: ignore
-----------------------------
-- Achievement
-----------------------------
Id.Achievement = enum.with_id "Id.Achievement" {
    _NONE        = iota(Id.Kind.Achievement, 0),
    BOSS_KILLER  = iota'',
    MOST_DAMAGE  = iota'',
    MOST_ENEMIES = iota'',
}
KIND_TO_ENUM[Id.Kind.Achievement] = Id.Achievement
export type Achievement = typeof(Id.Achievement)

-- stylua: ignore
-----------------------------
-- Clone
-----------------------------
Id.Clone = enum.with_id "Id.Clone" {
    _NONE   = iota(Id.Kind.Clone, 0),
    REGULAR = iota'',
}
KIND_TO_ENUM[Id.Kind.Clone] = Id.Clone
export type Clone = typeof(Id.Clone)

-- stylua: ignore
-----------------------------
-- Weapon
-----------------------------
Id.Weapon = enum.with_id "Id.Weapon" {
    _NONE    = iota(Id.Kind.Weapon, 0),
    DEFAULT  = iota'',
    BASIC    = iota'',
    SMG      = iota'',
    SPRAYGUN = iota'',
    ROCKET   = iota'',
}
KIND_TO_ENUM[Id.Kind.Weapon] = Id.Weapon
export type Weapon = typeof(Id.Weapon)

-- stylua: ignore
-----------------------------
-- Enemy
-----------------------------
Id.Enemy = enum.with_id "Id.Enemy" {
    _NONE      = iota(Id.Kind.Enemy, 0),
    BASIC      = iota'',
    CRAZOMBIE  = iota'',
    OCTOBOSS   = iota'',
}
KIND_TO_ENUM[Id.Kind.Enemy] = Id.Enemy
export type Enemy = typeof(Id.Enemy)

-- stylua: ignore
-----------------------------
-- EnemyFlying
-----------------------------
Id.EnemyFlying = enum.with_id "Id.EnemyFlying" {
    _NONE      = iota(Id.Kind.EnemyFlying, 0),
    ZOMBALLOON = iota'',
}
KIND_TO_ENUM[Id.Kind.EnemyFlying] = Id.EnemyFlying
export type EnemyFlying = typeof(Id.EnemyFlying)

-- stylua: ignore
-----------------------------
-- Obstacle
-----------------------------
Id.Obstacle = enum.with_id "Id.Obstacle" {
    _NONE      = iota(Id.Kind.Obstacle, 0),
    GRAVE      = iota'',
}
KIND_TO_ENUM[Id.Kind.Obstacle] = Id.Obstacle
export type Obstacle = typeof(Id.Obstacle)

-- stylua: ignore
-----------------------------
-- Bomb
-----------------------------
Id.Bomb = enum.with_id "Id.Bomb" {
    _NONE = iota(Id.Kind.Bomb, 0),
    ZOMBALLOON_BOMB = iota'',
}
KIND_TO_ENUM[Id.Kind.Bomb] = Id.Bomb
export type Bomb = typeof(Id.Bomb)

-- stylua: ignore
-- Timed event
-----------------------------
Id.TimedEvent = enum.with_id "Id.TimedEvent" {
    _NONE           = iota(Id.Kind.TimedEvent, 0),
    -- WEAPON_COOLDOWN = iota'',
}
KIND_TO_ENUM[Id.Kind.TimedEvent] = Id.TimedEvent
export type TimedEvent = typeof(Id.TimedEvent)

-- stylua: ignore
-----------------------------
-- Animation
-----------------------------
Id.Animation = enum.with_id "Id.Animation" {
    _NONE   = iota(Id.Kind.Animation, 0),
    DANCE   = iota'',
    HOLD    = iota'',
}
KIND_TO_ENUM[Id.Kind.Animation] = Id.Animation
export type Animation = typeof(Id.Animation)

-- stylua: ignore
-----------------------------
-- Sound
-----------------------------
Id.Sound = enum.with_id "Id.Sound" {
    _NONE                 = iota(Id.Kind.Sound, 0),
    BELL                  = iota'',
    BELL_SUCCESS          = iota'',
    CLICK                 = iota'',
    COIN_DROP             = iota'',
    CREAK_METAL           = iota'',
    CRYSTAL_DING          = iota'',
    ENERGY_SHIELD_HIT     = iota'',
    ERROR                 = iota'',
    FIRE_PISTOL           = iota'',
    FIRE_PISTOL_LOCALIZED = iota'',
    POP                   = iota'',
    RELOAD                = iota'',
    SCREAM                = iota'',
    SCREAM_LOCALIZED_HIGH = iota'',
    SCREAM_LOCALIZED_REG  = iota'',
    THUMP                 = iota'',
    THUMP_LOCALIZED       = iota'',
}
KIND_TO_ENUM[Id.Kind.Sound] = Id.Sound
export type Sound = typeof(Id.Sound)

-- stylua: ignore
-----------------------------
-- VFX
-----------------------------
Id.VFX = enum.with_id "Id.VFX" {
    _NONE                 = iota(Id.Kind.VFX, 0),
    EXPLOSION             = iota'',
    INVINCIBILITY_AURA    = iota'',
}
KIND_TO_ENUM[Id.Kind.VFX] = Id.VFX
export type VFX = typeof(Id.VFX)

-- stylua: ignore
-----------------------------
-- Player specs
-----------------------------
Id.PlayerSpecs = enum.with_id "Id.PlayerSpecs" {
    _NONE                = iota(Id.Kind.PlayerSpecs, 0),
    GAME_SESSION_PARAMS  = iota'',
    XP_PROGRESS          = iota'',
    SESSION_DAMAGE       = iota'',
    SESSION_ENEMY_KILLS  = iota'',
}
KIND_TO_ENUM[Id.Kind.PlayerSpecs] = Id.PlayerSpecs
export type PlayerStats = typeof(Id.PlayerSpecs)

-- stylua: ignore
-----------------------------
-- World specs
-----------------------------
Id.WorldSpecs = enum.with_id "Id.WorldSpecs" {
    _NONE                        = iota(Id.Kind.WorldSpecs, 0),
    GAME_SESSION_IN_PROGRESS     = iota'',
    BOOST_WAVE_COUNT             = iota'', -- number
    OBSTACLE_WAVE_COUNT          = iota'', -- number
    ENEMY_WAVE_COUNT             = iota'', -- number
    BOSS_FIGHT_ON                = iota'', -- bool
}
KIND_TO_ENUM[Id.Kind.WorldSpecs] = Id.WorldSpecs
export type WorldSpecs = typeof(Id.WorldSpecs)

-- stylua: ignore
-----------------------------
-- ServerError
-----------------------------
Id.ServerError = enum.with_id "Id.ServerError" {
    _NONE       = iota(Id.Kind.ServerError, 0),
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
    _NONE                     = iota(Id.Kind.S2S, 0),
    PASS_GRANTED              = iota'',
    PURCHASE_FINISHED         = iota'',
    CHANGE_WEAPON             = iota'', -- weapon_id
    PLAYER_DIED               = iota'', -- int (player damage)?, cause_id\uid?
    RANK_UP                   = iota'', -- player_state, next_rank, next_xp
    -- FINAL_BOSS_KILLED         = iota'',
    -- STOP_GAME_SESSION         = iota'',
}
KIND_TO_ENUM[Id.Kind.S2S] = Id.S2S
export type S2S = typeof(Id.S2S)

-- stylua: ignore
-----------------------------
-- C2C
-----------------------------
Id.C2C = enum.with_id "Id.C2C" {
    _NONE               = iota(Id.Kind.C2C, 0),
    NEW_BOOSTER_ADDED   = iota'', -- world_state, player_state, booster_guid
    NEW_ENEMY_ADDED     = iota'', -- world_state, player_state, enemy_guid
    SHOW_CLONES_TOGGLED = iota'', -- bool
    SHOW_POPUP_CLIENT   = iota'', -- {params}
}
KIND_TO_ENUM[Id.Kind.C2C] = Id.C2C
export type C2C = typeof(Id.C2C)

-- stylua: ignore
-----------------------------
-- C2S
-----------------------------
Id.C2S = enum.with_id "Id.C2S" {
    _NONE                             = iota(Id.Kind.C2S, 0),
    BULLET_SHOT                       = iota'', -- {bullet_guids}, bullet_weapon_id
    BUY_PLAYER_UPGRADE_PERS           = iota'', -- upgrade_id           
    REQUEST_PLAYER_UPGRADE_NON_PERS   = iota'', -- upgrade_id           
    TARGET_HIT                        = iota'', -- {enemy_guids}, bullet_guid
    TOGGLE_PLAYER_FLAG                = iota'', -- bool, flag_id
    PERK_SELECTED                     = iota'', -- 1 or 2
    PLAYER_READY_TO_START             = iota'',               
}
KIND_TO_ENUM[Id.Kind.C2S] = Id.C2S
export type C2S = typeof(Id.C2S)

-- stylua: ignore
-----------------------------
-- S2C
-----------------------------
Id.S2C = enum.with_id "Id.S2C" {
    _NONE             = iota(Id.Kind.S2C, 0),
    UPDATE_STATE      = iota'',
    BOOSTER_DESTROYED = iota'', -- boost_ref_id, value, boost_content_id
    INIT_WORLD        = iota'',
    UPDATE_WORLD      = iota'',
    PLAYER_DAMAGED    = iota'', -- int (player damage), cause_id\uid?
    PLAYER_DIED       = iota'', -- int (player damage), cause_id\uid?
    SHOW_POPUP_SERVER = iota'', -- event_id
}
KIND_TO_ENUM[Id.Kind.S2C] = Id.S2C
export type S2C = typeof(Id.S2C)

-- stylua: ignore
-----------------------------
-- S2CC
-----------------------------
Id.S2CC = enum.with_id "Id.S2CC" {
    _NONE                   = iota(Id.Kind.S2CC, 0),
    PLAYER_STARTED_SESSION     = iota'', -- player_id, player_hp
    PLAYER_STOPPED_SESSION     = iota'', -- player_id
    PLAYER_CHANGED_WEAPON      = iota'', -- player_id, weapon_id
    -- SPAWN_BOMB                 = iota'', -- enemy_guid
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

--[[ Flags
local logger = require(script.Parent.logger)
local lg = logger.create("Flags"):set_prettifier(Id.pp):set_delimiter(" ")
local flags = Id.PlayerF.NONE
local nonPersFlags = Id.PlayerF.NONE
-- lg:trace(flags, "-- flags = Id.PlayerF.NONE")
flags = Id.flag_or(nonPersFlags, Id.PlayerF.READY)
-- lg:trace(flags, "-- Id.flag_or(nonPersFlags, Id.PlayerF.READY)")
flags = Id.flag_set(flags, Id.PlayerF.OTHER_BULLETS_ON, true)
-- lg:trace(flags, "-- Id.flag_set(flags, Id.PlayerF.OTHER_BULLETS_ON, true)")
flags = Id.flag_set(flags, Id.PlayerF.READY, false)
-- lg:trace(flags, "-- Id.flag_set(flags, Id.PlayerF.READY, false)")

--]]

warn("[Id -- ok]")

return Id

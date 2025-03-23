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
type u5 = uint
type u3 = uint
type id = int
type cid = u5
type op = u3
type array<a> = { a }
type table = { [any]: any }
type map<k, v> = { [k]: v }
type fun = (...any) -> ...any
local _fmt = string.format

-----------------------------
-- Module
-----------------------------
local m = {}
m.__index = m
-- stylua: ignore
if not game then (function() script = require("script") :: any end)() end
local Id = require(script.Parent.Id)
local En = require(script.Parent.enum)
local iota = En.iota
local state = require(script.Parent.state)
local disposer = require(script.Parent.disposer)

m.BULLET_BASE_DISTANCE = 240 -- == distance, in units (always positive)
m.PLAYER_BASE_HP = 100
m.CONTROL_DISTANCE_TO_TARGET = 1 -- == distance, in units (always positive)
m.BULLET_RAYCAST_START_MULT = 2
-- TODO: revert to normal value
m.BOSS_WAVE_NUMBER = 21
m.MOVEMENT_LINEAR_VELOCITY_REG = 30
m.MOVEMENT_LINEAR_VELOCITY_BOSS = 15
m.BOOSTERS_IN_UNIT = 12
m.MAX_PLAYERS_IN_SESSION = m.BOOSTERS_IN_UNIT
m.ENEMY_WAVE_DELAY = 7
m.REGULAR_ENEMY_HITBOX_RADIUS = 2
m.BOOSTER_DEPTH = 10 -- units
m.CLONES_IN_A_ROW = 5
m.INTERCLONES_DISTANCE = 5
m.ROCKET_SELF_HARM_MULT = .2
m.DEFAULT_HP_GUI_TEXT = " "
m.CLONES_FOLDER_NAME = "Clones"
m.PLAYER_HITBOX_NAME = "Hitbox"
m.PLAYER_ALIGN_CONSTR_NAME = "PlayerAlignConstraint"
m.CLONE_ATTACHMENT_NAME = "CloneGuideAtt"
m.RUN_ANIMATION_NAME = "RunAnim"
m.BULLET_ATTRIBUTE_NAME = "BulletOwner"
m.BULLET_COLLIDABLE_COLLISION_GROUP_NAME = "BulletCollidable"
m.DEFAULT_WEAPON_ID = Id.Weapon.BASIC
m.DISTANCE_FROM_MID_TO_BOOSTER = 50
m.DEFAULT_PLAYER_ID = -100
m.ENEMY_SIGHT_RADIUS = 100
m.STARTING_CLONE_AMOUNT = 0
m.DRIVING_BOX_STARTING_POS = Vector3.new(0, 50, 255)
m.ATTRIBUTES_NAMES = {
    [Id.Kind.Boost] = "BOOST",
}

-----------------------------
-- WorldState
-----------------------------
-------------------
-- Archetypes
-------------------
local World = {}
m.World = World

-- stylua: ignore
-----------------------------
-- WorldCid
-----------------------------
-- stylua: ignore
World.CId = En.with_id("World.CId") {
    RefId          = iota(1),  -- id (of self)
    Value          = iota'',   -- number
    HP             = iota'',   -- number
    BoostContentId = iota'',   -- id
    Position       = iota'',   -- vector3
    ServerInstance = iota'',   -- Instance
    PlayerId       = iota'',   -- number
    WeaponId       = iota'',   -- id
    TTL            = iota'',   -- epoch
    Bitset         = iota'',   -- flag
    Total          = iota'',   -- number
    -- non-replicated
    ClientInstance = iota'',   -- Instance, not replicated
}
export type WorldCId = typeof(World.CId)
local W = World.CId

-- stylua: ignore
do
    local main_config, repl = state.ConfigBuilder.create()
        :set_component_names(W)
        :set_pretty_printer(Id.pp)
        :set_replication_flag(W.RefId, W.Value, W.HP, W.BoostContentId, W.Position, W.PlayerId, W.WeaponId, W.TTL, W.Bitset)
        :set_destructor(W.ServerInstance, disposer.dispose)
        :build_with_replica()

    World.main_config = main_config
    World.replica_config = repl
        :set_destructor(W.ClientInstance, disposer.dispose)
        :build()
    print("---- World ----")
    warn("W", state.Util.format_config(World.main_config))
    warn("W", state.Util.format_config(World.replica_config))
end

-----------------------------
-- PlayerState
-----------------------------
local PlayerState = {}
m.PlayerState = PlayerState

-- stylua: ignore
-------------------
-- Components
-------------------
PlayerState.CId = En.with_id("PlayerState.Cid") {
    RefId                = iota(0, 1, 31),
    -- timers
    TTL                  = iota'', -- epoch
    TTE                  = iota'', -- sec (*1)
    -- values
    Value                = iota'', -- number
    Total                = iota'', -- number
    Bitset               = iota'', -- flag
    Instance             = iota'', -- Instance(client)
    WorldGui             = iota'', -- any
    -- client-only
    ClientWeaponId       = iota'', -- number
    ClientFlags          = iota'', -- bool
    ClientTTE            = iota'', -- sec (*1)
}
-- *1) TTL(sec) decremented by dt until 0 only during game session. For wall clock TTL, use expiration TTE(epoch).
--     NOTE: W.TTL is a wall time
export type PlayerStateCId = typeof(PlayerState.CId)

-- stylua: ignore
do
    local C = PlayerState.CId
    local main_config, repl = state.ConfigBuilder.create()
        :set_component_names(C)
        :set_pretty_printer(Id.pp)
        :set_replication_flag(C.RefId, C.TTL, C.TTE, C.Value, C.Total, C.Bitset)
        -- :set_persistent_flag(C.RefId, C.TTL, C.TTE, C.Value, C.Total, C.Bitset)
        :set_persistent_flag(C.Total, C.Bitset)
        :build_with_replica()

    PlayerState.main_config = main_config
    PlayerState.replica_config = repl:build()
    print("---- PlayerState ----")
    warn("Components: ", C)
    warn(state.Util.format_config(PlayerState.main_config))
    warn(state.Util.format_config(PlayerState.replica_config))
end

-- place serialized datastore here
m.Save = [[
]]

-----------------------------
-- Quick test
-----------------------------

return m

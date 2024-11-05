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
local Disposer = require(script.Parent.disposer)
local Id = require(script.Parent.Id)
local En = require(script.Parent.enum)
local iota = En.iota
local _flag = En.flag
local Ecs = require(script.Parent.goap)
local logic = require(script.Parent.logic)
local state = require(script.Parent.state)

-----------------------------
-- WorldState
-----------------------------
-------------------
-- Archetypes
-------------------
-- TODO: archetypes
local World = {}
m.World = World
-------------------
-- Components
-------------------
-- stylua: ignore
-----------------------------
-- WorldStateCid
-----------------------------
-- stylua: ignore
World.CId = En.with_id("World.CId") {
    Position  = iota(0), -- vector
}
export type WorldCId = typeof(World.CId)

local W = World.CId
-- stylua: ignore
do
    local main_config, repl = state.ConfigBuilder.create()
        :set_component_names(W)
        :set_pretty_printer(Id.pp)
        :set_replication_flag(W.Position)
        :build_with_replica()

    World.main_config = main_config
    World.replica_config = repl:build()

    warn(state.Util.format_config(World.main_config))
    warn(state.Util.format_config(World.replica_config))
end

-----------------------------
-- PlayerState
-----------------------------
local PlayerState = {}

-- stylua: ignore
-------------------
-- Components
-------------------
PlayerState.CId = En.with_id("PlayerState.Cid") {
    Id              = iota(0, 1, 31),
    -- timers
    TTL             = iota'', -- sec (*1)
    TTE             = iota'', -- epoch
    -- values
    Value           = iota'', -- number
    Bitset          = iota'', -- uint32
    Instance        = iota'', -- Instance(client)
    WorldGui        = iota'', -- any
}
-- *1) TTL(sec) decremented by dt until 0 only during game session. For wall clock TTL, use expiration TTE(epoch).
--     NOTE: W.TTL is a wall time


export type PlayerStateCId = typeof(PlayerState.CId)
---[[ stylua: ignore]] print(PlayerState.CId, #PlayerState.CId)

-- stylua: ignore

-- PlayerState.client_config = Ecs.create_config()
--     :component_names(PlayerState.CId:to_map())
--     :set_destructor(PlayerState.CId.Instance, Disposer.dispose)
--     :finalize()

m.PlayerState = PlayerState
-----------------------------
-- Config
-----------------------------

-----------------------------
-- Quick test
-----------------------------

return m

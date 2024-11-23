--!strict

type str = string
type bool = boolean
type num = number
type integer = num
type uint = integer
type int = integer
type u32 = uint
type i32 = int
type u8 = uint
type id = int
type array<a> = { a }
type table = { [any]: any }
type map<k, v> = { [k]: v }
type fun = (...any) -> ...any
type dim = id | int
local _fmt = string.format
--[[ stylua: ignore]] game = game or require'game'
local shared = game.ReplicatedStorage.shared
local _luapp = require(shared.luapp)
local logger = require(shared.logger)
local Id = require(shared.Id)
local log = logger.create("server"):set_delimiter(" "):set_prettifier(Id.pp)
local _data_table = require(shared.data_table)
local supervisor = require(shared.supervisor)
local Remote = require(shared.Remote)
-- server
local server = game.ServerScriptService.server
local PSS = require(server.PlayerStateService)
local _Market = require(server.Market)
local WorldService = require(server.WorldService)
local TaskPool = require(shared.TaskPool)
type PlayerState = PSS.PlayerState
local _AbilityCVS = require(server.data.Ability)
local _STMCSV = require(server.data.STM)
local GameModule = require(server.GameModule)
local RunService = game:GetService("RunService")
local Players = game:GetService("Players")

if game.PhysicsService then
    local phys = game.PhysicsService
    log:debug("PhysicsService:IsCollisionGroupRegistered('Clones')", phys.IsCollisionGroupRegistered, phys, "Clones")
end
-- stylua: ignore

--[[
_luapp.set_id_resolver(Id.pp)
print(">>", _luapp.pp(data_table.load(_AbilityCVS.csv)))
print(">>", _luapp.pp(data_table.load(_STMCSV.csv)))
--]]
-----------------------------
-- Server
-----------------------------
local STATES = {} :: { [number]: PlayerState }

local function get_state(player_id: int): PlayerState?
    return STATES[player_id]
end

if not workspace then
    log:warn("Server can't be started without Roblox -- exit")
    return
end

-----------------------------
-- Update Loops
-----------------------------
local ServerSupervisor = supervisor.create(0.1)
local _loop_update_states = ServerSupervisor:start(function(_dt)
    for _, state in STATES do
        local update_state_log = state.state:flash()
        local update_world_log = WorldService.world:flash()
        if update_state_log then
            state:NotifyClient(Id.S2C.UPDATE_STATE, update_state_log)
        end
        if not state.state:env("WORLD_READY") then
            state:NotifyClient(Id.S2C.INIT_WORLD, WorldService.world:snapshot())
            state.state:env("WORLD_READY", true)
        elseif update_world_log then
            state:NotifyClient(Id.S2C.UPDATE_WORLD, update_world_log)
        end
    end
end)

----------------------------
-- Event Handling
-----------------------------
-----------------------------
-- C2S
-----------------------------
local on = {} :: Remote.OnRemoteEvent<PlayerState>

on[Id.C2S._NONE] = function(player_state, event_id, ...)
    log:debug(Id.C2S._NONE, player_state.player_id, event_id, ...)
end

on[Id.C2S.BULLET_SHOT] = function(player_state, event_id, bullet_starting_pos, ...)
    -- log:debug(Id.C2S._NONE, player_state.player_id, event_id, ...)
    -- TODO: call verify that the bullet collides and after <bullet speed> time, reduce hp from the booster
    -- TODO: if the bullet doesn't collide, do nothing
    -- TODO: after hp <= 0, remove the booster and add the boost
end

-------------------
-- S2S
-------------------
local s2s = {} :: map<id, (PlayerState, ...any) -> ()>
s2s[Id.S2S._NONE] = function(player_state, ...)
    log:debug(Id.S2S._NONE, player_state.player_id, ...)
end
s2s[Id.S2S.PASS_GRANTED] = function(player_state, event_id, player_id)
    log:error(Id.S2S.PASS_GRANTED, "TODO")
end

s2s[Id.S2S.PURCHASE_FINISHED] = function(player_state, ...)
    log:error(Id.S2S.PURCHASE_FINISHED, "TODO")
end

GameModule.init(WorldService.world, get_state)
local _ = ServerSupervisor:start(GameModule.StartMainLoop(WorldService.world))

local function onPlayerAdded(player)
end

for _, player in Players:GetPlayers() do
    onPlayerAdded(player)
end
Players.PlayerAdded:Connect(onPlayerAdded)

-----------------------------
-- Player Connect
-----------------------------
-- place here all the logic that needs to be executed on player connect
local function init_player(player_state: PlayerState)
    return function()
        -- TODO:
    end
end

game.Players.PlayerAdded:Connect(function(player)
    log:debug("PlayerAdded %* id: %*", player, player.UserId)
    local _fire_client, disposer, state = Remote.Server.Handshake(player, PSS.load, on)
    STATES[player.UserId] = state :: PlayerState
    state.maid.remote_disposer = disposer
    -- WorldService.AddPlayer(state)
    -- Market.CheckPassesOnInit(state.player_id, function(store_id) error("TODO") end)
    TaskPool.defer(init_player(state))
end)

-----------------------------
-- Player Disconnect
-----------------------------
game.Players.PlayerRemoving:Connect(function(player)
    -- TODO: remove his clones from CLONES of other's players' clients
    local state = STATES[player.UserId]
    if not state then
        return
    end
    STATES[player.UserId] = nil
    TaskPool.call(function()
        state:Save()
        task.wait()
        -- WorldService.RemovePlayer(state)
        state:Destroy()
    end)
end)

warn("[server -- started]")

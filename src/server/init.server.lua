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
type guid = str
type uid = guid | id
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
local SharedConfig = require(shared.SharedConfig)
local C = SharedConfig.PlayerState.CId
local W = SharedConfig.World.CId
local S = require(shared.StaticData)
local Misc = require(shared.Misc)
local NumFormat = require(shared.num_format)
local Signal = require(shared.signal)
local disposer = require(shared.disposer)

local workerMaid = disposer.new()

if game.PhysicsService then
    local phys = game.PhysicsService
    log:debug("PhysicsService:IsCollisionGroupRegistered('Clones')", phys.IsCollisionGroupRegistered, phys, "Clones")
    log:debug("PhysicsService:IsCollisionGroupRegistered('BulletCollidable')", phys.IsCollisionGroupRegistered, phys, "BulletCollidable")
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

local function change_weapon(player_state, weapon_id: id)
    player_state:ChangeWeapon(weapon_id)
    WorldService.ChangeWeapon(player_state, player_state.player_id, weapon_id)
end

local function cleanUpWorldState(player_state, this_player_id: int)
    -- clean up clones
    for uid, ref_id, player_id in WorldService.world:select(W.RefId, W.PLayerId) do
        if Id.kind(ref_id) == Id.Kind.Clone and player_id == this_player_id then
            WorldService.RemoveEntity(uid)
        end
    end
    -- clean up weapon
    if WorldService.world:has(this_player_id) then
        WorldService.ChangeWeapon(player_state, this_player_id, Id.Weapon._NONE)
    end
end

local function onPlayerDead(player_state: PSS.PlayerState)
    player_state:NotifyClient(Id.S2C.PLAYER_DIED)
    local lobby_spawn = assert(workspace:FindFirstChild("Lobby"):FindFirstChild("SpawnLocation"))
    player_state.root.CFrame = lobby_spawn.CFrame
    local constraint = player_state.character:FindFirstChild(SharedConfig.PLAYER_ALIGN_CONSTR_NAME)
    if constraint then
        constraint:Destroy()
    end
    workerMaid.playerLoop = nil -- stop updating weapon ttl
    player_state.state:set(Id.PlayerStats.GAME_SESSION, C.RefId, Id.Weapon._NONE)
    player_state.state:set(Id.PlayerStats.GAME_SESSION, C.TTL, 0)
    player_state.state:set(Id.PlayerStats.GAME_SESSION, C.Value, 0)
    local flags = player_state.state:get(Id.PlayerStats.GAME_SESSION, C.Bitset)
    player_state.state:set(Id.PlayerStats.GAME_SESSION, C.Bitset, Id.flag_set(flags, Id.PlayerF.READY, false))

    cleanUpWorldState(player_state, player_state.player_id)
    Remote.Server.Broadcast(Id.S2CC.PLAYER_STOPPED_SESSION, player_state.player_id)
end

-----------------------------
-- Update Loops
-----------------------------
local ServerSupervisor = supervisor.create(0.1)
local _loop_update_states = ServerSupervisor:start(function(_dt)
    local update_world_log = WorldService.world:flash()
    for _, state in STATES do
        local update_state_log = state.state:flash()
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

on[Id.C2S._NONE] = function(player_state, ...)
    log:debug(Id.C2S._NONE, player_state.player_id, ...)
end

on[Id.C2S.BOOSTER_HIT] = function(player_state, booster_guid, ...)
    -- check if a booster is about to be hit
    local humanoidRootPart = player_state.character:FindFirstChild("HumanoidRootPart") :: BasePart
    if humanoidRootPart then
        local pos = humanoidRootPart.Position + humanoidRootPart.CFrame.LookVector * SharedConfig.BULLET_RAYCAST_START_MULT
        local current_weapon_id = player_state.state:get(Id.PlayerStats.GAME_SESSION, C.RefId) or Id.Weapon.BASIC
        local boosterToHit, _distance = Misc.IsBoosterToHit(pos)
        if boosterToHit and boosterToHit.Name == booster_guid and WorldService.world:has(booster_guid) then
            -- the hit is legit
            local dmg = S.Weapon[current_weapon_id].damage
            local booster_hp = WorldService.world:get(boosterToHit.Name, W.HP)
            local new_hp = booster_hp - dmg
            local boosterGui = boosterToHit:FindFirstChildWhichIsA("SurfaceGui")
            boosterGui.TextLabel.Text = NumFormat.format_damage(new_hp)
            if new_hp <= 0 then
                -- give boost to the player who killed the booster
                local boostRefId = WorldService.world:get(boosterToHit.Name, W.RefId)
                local boostContentId = WorldService.world:get(boosterToHit.Name, W.BoostContentId)
                local value = WorldService.world:get(boosterToHit.Name, W.Value)
                WorldService.world:delete(boosterToHit.Name)
                if player_state.state:has(boosterToHit.Name) then
                    player_state.state:delete(boosterToHit.Name)
                end

                GameModule.HandleBoosterDeath(player_state, boosterToHit.Name, boostRefId, value, boostContentId)
            else
                WorldService.world:set(boosterToHit.Name, W.HP, booster_hp - dmg)
            end
        end
    end
end

on[Id.C2S.BULLET_SHOT] = function(player_state, event_id, bullet_starting_pos, ...)
    log:debug(Id.C2S.BULLET_SHOT, player_state.player_id, event_id, ...)
    local current_weapon_id = player_state.state:get(Id.PlayerStats.GAME_SESSION, C.RefId)
    if not current_weapon_id or current_weapon_id == Id.Weapon._NONE then
        return 
    end
    local cooldown = S.Weapon[current_weapon_id].cooldown
    player_state.state:set(Id.PlayerStats.GAME_SESSION, C.TTL, cooldown)
end

on[Id.C2S.PLAYER_COLLIDED_W_BOOSTER] = function(player_state, booster_guid: str, triggerer_id: num | str, ...)
    if not triggerer_id then
        log:error("Collision triggerer id is not defined")
    end
    local isPlayer = type(triggerer_id) == "number"

    local booster_hp = WorldService.world:get(booster_guid, W.HP)
    local player_hp = player_state.state:get(Id.PlayerStats.GAME_SESSION, C.Value)

    if isPlayer then
        -- TODO: update player_hp GUI
        -- TODO: SFX
        if player_hp - booster_hp <= 0 then
            onPlayerDead(player_state)
        else
            player_state:DeductHp(booster_hp)
        end
    else
        -- delete clone
        WorldService.world:delete(triggerer_id)
    end
end

on[Id.C2S.PLAYER_READY_TO_START] = function(player_state, ...)
    local total_players = Players:GetPlayers()
    local players_already_in_session = 1 -- including this player
    for _, player in ipairs(total_players) do
        local playerState = get_state(player)
        if playerState then
            local f = playerState.state:get(Id.PlayerStats.GAME_SESSION, C.Bitset)
            local isReady = Id.flag_test(f, Id.PlayerF.READY)
            if isReady then
                players_already_in_session += 1
            end
        end
    end

    change_weapon(player_state, SharedConfig.DEFAULT_WEAPON_ID)

    GameModule.CreatePlayerHpGui(player_state)

    local _main_loop_player_handler = ServerSupervisor:start(GameModule.StartMainLoopPlayer(player_state))
    workerMaid.playerLoop = function()
        ServerSupervisor:cancel(_main_loop_player_handler)
    end
    GameModule.OnPlayerReadyToPlay(player_state, players_already_in_session)
    Remote.Server.Broadcast(Id.S2CC.PLAYER_STARTED_SESSION, player_state.player_id)
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

-- initialize main game loop
do
    TaskPool.spawn(function()
        GameModule.Init(WorldService.world, get_state)

        local playerState
        repeat
            task.wait()
            playerState = get_state(next(STATES) :: int)
        until playerState ~= nil
        log:info("playerState", playerState, playerState and playerState.player_id)
        assert(playerState, "sanity check failed, no player state found")
        
        -- TODO: this is a hack, we should have a better way to do this
        -- wait until at least 1 player is ready to join the session
        local isReady = false
        repeat
            task.wait(0.1)
            for _, thisState in pairs(STATES) do
                local flags = thisState.state:get(Id.PlayerStats.GAME_SESSION, C.Bitset)
                flags = thisState.state:get(Id.PlayerStats.GAME_SESSION, C.Bitset)
                if not flags then
                    continue
                end
                isReady = Id.flag_test(flags, Id.PlayerF.READY)
                if isReady then
                    break
                end
            end
        until isReady
        local _ = ServerSupervisor:start(GameModule.StartMainLoopWorld(WorldService.world))
    end)
end

-----------------------------
-- Player Connect
-----------------------------
-- place here all the logic that needs to be executed on player connect
local function init_player(player_state: PlayerState)
    return function()
        local _game_session_params = player_state.state:constructor(C.RefId, C.TTL, C.Value, C.Bitset) -- weapon_id, weapon_ttl, hp, is_active
        _game_session_params(Id.PlayerStats.GAME_SESSION, Id.Weapon._NONE, 0, SharedConfig.STARTING_HP, Id.PlayerF.NONE)
    end
end

game.Players.PlayerAdded:Connect(function(player)
    log:debug("PlayerAdded %* id: %*", player, player.UserId)
    local _fire_client, disposer, state = Remote.Server.Handshake(player, PSS.load, on)
    STATES[player.UserId] = state :: PlayerState
    state.maid.remote_disposer = disposer
    WorldService.AddPlayer(state)
    -- Market.CheckPassesOnInit(state.player_id, function(store_id) error("TODO") end)
    TaskPool.defer(init_player(state))
end)

-----------------------------
-- Player Disconnect
-----------------------------
game.Players.PlayerRemoving:Connect(function(player)
    local state = STATES[player.UserId]
    if not state then
        return
    end
    STATES[player.UserId] = nil
    TaskPool.call(function()
        state:Save()
        task.wait()
        -- TODO: correct exit
        -- WorldService.RemovePlayer(state)
        state:Destroy()
        cleanUpWorldState(state, player.UserId)
    end)
end)

-----------------------------
-- Connect S2S
-----------------------------
for _, id in Id.S2S:ids() do
    local handler = s2s[id] or function(_: PlayerState, ...)
        log:error("no handler for: ", id)
    end
    local _ = Signal.Connect(id, function(player_id: int, ...)
        assert(typeof(player_id) == "number", "first arg must be a player id")
        local state: PlayerState
        for i = 1, 5 do -- 5 tries, 1 sec each
            state = STATES[player_id]
            if state then
                local ok, err: str? = pcall(handler, state, ...)
                if not ok then
                    log:error("ERROR in S2S handler for: ", id, "\n", err)
                end
                break
            else
                task.wait(1.0)
            end
        end
    end)
end

warn("[server -- started]")

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
--[[ stylua: ignore]] game = game --or require'game'
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
local Leaderboards = require(server.Leaderboards)
local Obstacles = require(server.Obstacles)
local BoosterServer = require(server.BoosterServer)
local roflake = require(shared.roflake)
local workerMaid = disposer.new()
local ClonesServer = require(server.ClonesServer)
local Perks = require(server.DynamicPerks)
local TweenService = game:GetService("TweenService")
if game.PhysicsService then
    local phys = game.PhysicsService
    log:debug("PhysicsService:IsCollisionGroupRegistered('Clones')", phys.IsCollisionGroupRegistered, phys, "Clones")
    log:debug("PhysicsService:IsCollisionGroupRegistered('BulletCollidable')", phys.IsCollisionGroupRegistered, phys, "BulletCollidable")
end

local stopGameSession -- forward declaration

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
    if type(player_id) ~= "number" then
        log:error("Parameter is not a player id", player_id, debug.traceback())
        return nil
    end
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
GameModule.StartDamageThrottleSupervisor(get_state)
-----------------------------

local function changeWeapon(player_state, weapon_id: id)
    player_state:ChangeWeapon(weapon_id)
    WorldService.ChangeWeapon(player_state, player_state.player_id, weapon_id)
end

local function resetHp(player_state)
    local hp = SharedConfig.PLAYER_BASE_HP
    local currentHandicap = WorldService.world:get(Id.WorldSpecs.HANDICAP, W.Value) :: id
    if currentHandicap == Id.Handicap.DOUBLE_HP then
        hp *= SharedConfig.HP_HANDICAP_MULT
    end

    -- check for hp upgrades
    local hpUpgrade = Misc.IsHpUpgrade(player_state) :: num
    if hpUpgrade and S.PlayerUpgradePersistent[hpUpgrade].value then
        hp *= S.PlayerUpgradePersistent[hpUpgrade].value
    end

    player_state.state:set(Id.PlayerSpecs.GAME_SESSION_PARAMS, C.ValueNonPers, hp)
    WorldService.world:set(player_state.player_id, W.HP, hp)

    return hp
end

local function cleanUpWorldState(player_state, this_player_id: int)
    -- reset world player
    WorldService.world:set(this_player_id, W.Value, 0)
    WorldService.world:set(this_player_id, W.WeaponId, Id.Weapon._NONE)
    WorldService.world:set(this_player_id, W.HP, SharedConfig.PLAYER_BASE_HP)
    WorldService.world:set(this_player_id, W.ServerInstance, nil)
    WorldService.world:set(this_player_id, W.TTE, 0)
    -- clean up clones
    for uid, ref_id, player_id in WorldService.world:select(W.RefId, W.PlayerId) do
        if Id.kind(ref_id) == Id.Kind.Clone and player_id == this_player_id then
            WorldService.RemoveEntity(uid)
        end
    end
    -- clean up weapon
    if WorldService.world:has(this_player_id) then
        WorldService.ChangeWeapon(player_state, this_player_id, Id.Weapon._NONE)
    end
end

local function onPlayerSessionFinishedWorld(player_state, playerId)
    cleanUpWorldState(player_state, playerId)
    Remote.Server.Broadcast(Id.S2CC.PLAYER_STOPPED_SESSION, playerId)

    -- check if any player is still in the session. If not, stop the session altogether.
    local isAnyoneInSession = false
    for playerId, playerState in pairs(STATES) do
        local thisPlayerNonPersFlags = playerState.state:get(Id.PlayerSpecs.GAME_SESSION_PARAMS, C.BitsetNonPers)
        if thisPlayerNonPersFlags then
            if Id.flag_test(thisPlayerNonPersFlags, Id.PlayerF.READY) then
                isAnyoneInSession = true
                break
            end
        end
    end
    if not isAnyoneInSession then
        stopGameSession(playerId)
    end
end

local function onPlayerSessionFinishedPlayerState(player_state: PSS.PlayerState, deducted_hp: int?, cause_id: id | uid?)
    -- check if the player is not already dead
    local nonPersFlags = player_state.state:get(Id.PlayerSpecs.GAME_SESSION_PARAMS, C.BitsetNonPers)
    if nonPersFlags and not Id.flag_test(nonPersFlags, Id.PlayerF.READY) then
        return
    end

    print("Player dead")

    local attachement = player_state.root:FindFirstChild(SharedConfig.CLONE_ATTACHMENT_NAME)
    if attachement then
        attachement:Destroy()
    end

    player_state:NotifyClient(Id.S2C.PLAYER_DIED, deducted_hp, cause_id)
    local lobby_spawns = {}
    for _, child in workspace:FindFirstChild("Lobby"):GetChildren() do
        if child.Name == "SpawnLocation" then
            table.insert(lobby_spawns, child)
        end
    end
    local spawn_index = math.random(1, #lobby_spawns)
    local lobby_spawn = lobby_spawns[spawn_index]
    player_state.root.CFrame = lobby_spawn.CFrame

    player_state.humanoid.AutoRotate = true

    GameModule.UnconstrainPlayer(player_state)

    player_state.state:set(Id.PlayerSpecs.GAME_SESSION_PARAMS, C.RefId, Id.Weapon._NONE)
    player_state.state:set(Id.PlayerSpecs.GAME_SESSION_PARAMS, C.TTE, 0)
    player_state.state:set(Id.PlayerSpecs.GAME_SESSION_PARAMS, C.ValueNonPers, 0)
    -- reset player flags
    for _, player_flag_id in Id.PlayerF:ids() do
        if player_flag_id > Id.PlayerF._NON_PERSISTENT then
            player_state:set_flag(Id.PlayerSpecs.GAME_SESSION_PARAMS, C.BitsetNonPers, player_flag_id, false)
        end
    end

    onPlayerSessionFinishedWorld(player_state, player_state.player_id)
end

local function doCleanup(exception_player_id: num?)
    WorldService.SetGameSessionOff()
    WorldService.SetBossFightOff()
    WorldService.SetPvPTimeOff()
    -- WorldService.ResetBoosterWaveCount()
    WorldService.ResetEnemyWaveCount()
    WorldService.ResetObstacleWaveCount()
    WorldService.ResetHandicap()

    -- kill remaining enemies and obstacles
    for guid, refId, _pos in WorldService.world:select(W.RefId, W.Position) do
        if Id.kind(refId) == Id.Kind.Enemy or Id.kind(refId) == Id.Kind.EnemyFlying then
            local thisGuid = guid :: guid
            GameModule.DestroyEnemy(thisGuid)
        elseif Id.kind(refId) == Id.Kind.Obstacle then
            local thisGuid = guid :: guid
            WorldService.RemoveEntity(thisGuid)
        end
    end

    -- remove remaining ground units and reset driving box
    GameModule.Cleanup()
    -- task.wait(0.1)
    -- log:info("Game session stopped")
    -- log:info(">", WorldService.world:format_state("*"))
end

local function unacquirePerks(playerState: PSS.PlayerState)
    for _, perk_id in Id.PlayerUpgradeNonPersistent:ids() do
        -- unacquire the perk
        local flags = playerState.state:get(perk_id, C.Bitset)
        playerState.state:set(perk_id, C.Bitset, Id.flag_set(flags, Id.PlayerF.PERK_ACQUIRED, false))
        playerState.state:set(perk_id, C.ValueNonPers, 0)
        -- reset the perk
        playerState:DeactivatePlayerUpgradeNonPers(perk_id)
    end
end

local function startGameSession()
    TaskPool.spawn(function()
        WorldService.SetGameSessionOn()
        Leaderboards.ResetLeaderboards()

        local handicapIds = Id.Handicap:ids()
        local handicapId = Random.new():NextInteger(handicapIds[1], handicapIds[#handicapIds])
        -- local handicapId = Id.Handicap.BOMBS
        WorldService.SetHandicap(handicapId)

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
            for _, thisPlayerState in pairs(STATES) do
                local nonPersFlags = thisPlayerState.state:get(Id.PlayerSpecs.GAME_SESSION_PARAMS, C.BitsetNonPers)
                if not nonPersFlags then
                    continue
                end
                isReady = Id.flag_test(nonPersFlags, Id.PlayerF.READY)
                if isReady then
                    break
                end
            end
        until isReady
        WorldService.ResetBoosterWaveCount()
        WorldService.SetBossFightOff()

        local _main_loop_world_handler = ServerSupervisor:start(GameModule.StartMainLoopWorld(WorldService.world, get_state))
        log:trace("world loop started")
        workerMaid.worldLoop = function()
            task.defer(function()
                ServerSupervisor:cancel(_main_loop_world_handler)
                doCleanup(playerState.player_id)
                log:trace("world loop canceled")
            end)
        end
    end)
end

stopGameSession = function(exception_player_id: num?)
    for playerId, playerState in pairs(STATES) do
        -- reset xp  for all players
        playerState:ResetPlayerXP()
        -- reset perks for all players
        for _, perk_id in Id.PlayerUpgradeNonPersistent:ids() do
            unacquirePerks(playerState)
        end
        -- kill off everyone who's alive; skip the player who ended the session to avoid recursion
        if exception_player_id and playerId ~= exception_player_id then
            continue
        end
        playerState:DeductHp(playerState.state:get(Id.PlayerSpecs.GAME_SESSION_PARAMS, C.ValueNonPers))
    end

    workerMaid.worldLoop = nil
end

local function onFinalBossKilledByPlayer(boss_killer_player_state)
    -- TODO: congratulatory effects

    stopGameSession()

    -- boss killer leaderboard
    Leaderboards.SpawnWinner(boss_killer_player_state, Id.Achievement.BOSS_KILLER)
    -- local total_players = Players:GetPlayers()

    -- most damage leaderboard
    local playerWithMostDamageState
    local mostDamageInflicted = 0
    -- for _, player in ipairs(total_players) do
    --     local thisPlayerState = get_state(player.UserId)
    --     if thisPlayerState then
    --         local damage = thisPlayerState.state:get(Id.PlayerSpecs.SESSION_DAMAGE, C.ValueNonPers)
    --         if damage and (damage > mostDamageInflicted) then
    --             mostDamageInflicted = damage
    --             playerWithMostDamageState = thisPlayerState
    --         end
    --     end
    -- end
    for playerId, playerState in pairs(STATES) do
        local damage = playerState.state:get(Id.PlayerSpecs.SESSION_DAMAGE, C.ValueNonPers)
        if damage and (damage > mostDamageInflicted) then
            mostDamageInflicted = damage
            playerWithMostDamageState = playerState
        end
    end
    if playerWithMostDamageState then
        Leaderboards.SpawnWinner(playerWithMostDamageState, Id.Achievement.MOST_DAMAGE)
    end

    -- most enemies leaderboard
    local playerWithMostKillsState
    local mostKills = 0
    -- for _, player in ipairs(total_players) do
    --     local thisPlayerState = get_state(player.UserId)
    --     if thisPlayerState then
    --         local kills = thisPlayerState.state:get(Id.PlayerSpecs.SESSION_ENEMY_KILLS, C.ValueNonPers)
    --         if kills and (kills > mostKills) then
    --             mostKills = kills
    --             playerWithMostKillsState = thisPlayerState
    --         end
    --     end
    -- end
    for playerId, playerState in pairs(STATES) do
        local kills = playerState.state:get(Id.PlayerSpecs.SESSION_ENEMY_KILLS, C.ValueNonPers)
        if kills and (kills > mostKills) then
            mostKills = kills
            playerWithMostKillsState = playerState
        end
    end
    if playerWithMostKillsState then
        Leaderboards.SpawnWinner(playerWithMostKillsState, Id.Achievement.MOST_ENEMIES)
    end
end

local function acquirePlayerUpgradeNonPers(player_state, perk_id: id)
    local perkStage = player_state.state:get(perk_id, C.ValueNonPers)
    if perkStage < S.PlayerUpgradeNonPersistent[perk_id].maxStage and S.PlayerUpgradeNonPersistent[perk_id].maxStage ~= 0 then
        player_state.state:set(perk_id, C.ValueNonPers, perkStage + 1)
    end
    player_state:ActivatePlayerUpgradeNonPers(perk_id)
end

local function updatePlayerXP(playerState: PSS.PlayerState, received_xp: int): (int, int)
    local current_rank = playerState.state:get(Id.PlayerSpecs.XP_PROGRESS, C.PlayerRank)
    local current_xp = playerState.state:get(Id.PlayerSpecs.XP_PROGRESS, C.ValueNonPers)
    local next_rank = current_rank
    local next_xp = current_xp + received_xp
    local xp_required = SharedConfig.PLAYER_RANK_XP_REQUIRED + current_rank * SharedConfig.PLAYER_RANK_XP_INCREMENT
    if next_xp >= xp_required then
        -- rank up
        next_rank = current_rank + 1
        next_xp = next_xp - xp_required
        local choice = Perks.SelectPerks(playerState)
        playerState.state:set(Id.PlayerSpecs.XP_PROGRESS, C.V3, choice)
    end
    playerState.state:set(Id.PlayerSpecs.XP_PROGRESS, C.PlayerRank, next_rank)
    playerState.state:set(Id.PlayerSpecs.XP_PROGRESS, C.ValueNonPers, next_xp)
    return next_rank, next_xp
end

local function onTargetHit(playerState: PSS.PlayerState, targetGuid: string, dmg: num)
    local targetRefId = WorldService.world:get(targetGuid, W.RefId)
    if Id.kind(targetRefId) == Id.Kind.Boost then
        local boosterServerInstance = WorldService.world:get(targetGuid, W.ServerInstance)
        local booster_hp = WorldService.world:get(targetGuid, W.HP)
        local new_hp = booster_hp - dmg
        local boosterGui = boosterServerInstance:FindFirstChildWhichIsA("SurfaceGui")
        if boosterGui then
            boosterGui.TextLabel.Text = NumFormat.format_damage(new_hp)
        end
        if new_hp <= 0 then
            -- give boost to the player who killed the booster
            local boostContentId = WorldService.world:get(targetGuid, W.BoostContentId)
            local value = WorldService.world:get(targetGuid, W.Value)
            BoosterServer.DeleteBooster(WorldService.world, targetGuid :: str, get_state)
            local _ = playerState:UpdateSessionDamageStats(booster_hp)

            -- give reward for killing booster
            local reward = S.Boost[targetRefId].baseReward or 0
            playerState:AddCountablePersistent(Id.CountablePersistent.COIN, reward)

            -- give XP for killing booster
            local xp = S.Boost[targetRefId].xp or 0
            updatePlayerXP(playerState, xp)

            GameModule.HandleBoosterDeath(playerState, targetGuid :: str, targetRefId, value, boostContentId)
        else
            local _ = playerState:UpdateSessionDamageStats(dmg)
            WorldService.world:set(targetGuid, W.HP, booster_hp - dmg)
        end
    elseif Id.kind(targetRefId) == Id.Kind.Enemy then
        local enemyHP = WorldService.world:get(targetGuid, W.HP)
        local newHP = enemyHP - dmg

        if enemyHP - dmg <= 0 then
            local _ = playerState:UpdateSessionDamageStats(enemyHP)
            local _ = playerState:UpdateSessionEnemyKills()

            -- add reward for killing enemies
            local bounty = 0
            if S.Enemy[targetRefId].reward then
                bounty = S.Enemy[targetRefId].reward
            end
            playerState:AddCountablePersistent(Id.CountablePersistent.COIN, bounty)

            -- give XP for killing enemies
            local xp = S.Enemy[targetRefId].xp or 0
            updatePlayerXP(playerState, xp)

            -- if enemy is still alive, kill off the enemy
            if WorldService.world:has(targetGuid) then
                GameModule.DestroyEnemy(targetGuid :: str, playerState.player_id)
            end

            -- check if the enemy was the final boss, if yes, finish round
            if targetRefId == Id.Enemy.OCTOBOSS then
                if WorldService.world:get(Id.WorldSpecs.BOSS_FIGHT_ON, W.Value) then -- we are checking player_id, other checks are redundant
                    WorldService.SetBossFightOff()
                    onFinalBossKilledByPlayer(playerState)
                end
            end
        else
            local _ = playerState:UpdateSessionDamageStats(dmg)
            WorldService.world:set(targetGuid, W.HP, newHP)
        end
    elseif Id.kind(targetRefId) == Id.Kind.Obstacle then
        local obstacleHP = WorldService.world:get(targetGuid, W.HP)
        local newHP = obstacleHP - dmg
        if newHP <= 0 then
            local _ = playerState:UpdateSessionDamageStats(newHP)
            -- give reward for destroying obstacle
            local reward = S.Obstacle[targetRefId].reward or 0
            playerState:AddCountablePersistent(Id.CountablePersistent.COIN, reward)
            -- if obstacle is still alive, destroy it
            if WorldService.world:has(targetGuid) then
                WorldService.world:delete(targetGuid)
            end

            -- give XP for destroying obstacle
            local xp = S.Obstacle[targetRefId].xp or 0
            updatePlayerXP(playerState, xp)
        else
            local _ = playerState:UpdateSessionDamageStats(dmg)
            WorldService.world:set(targetGuid, W.HP, newHP)
        end
    end
end

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

-- local preiousWeaponsInfo = {}
on[Id.C2S.BULLET_SHOT] = function(player_state, bullet_guids: { uid }, bullet_weapon_id, ...)
    local current_weapon_id = player_state.state:get(Id.PlayerSpecs.GAME_SESSION_PARAMS, C.RefId)
    if not current_weapon_id or current_weapon_id == Id.Weapon._NONE then
        return
    end

    -- check the legitimacy of the shot
    local currentTTE = player_state.state:get(Id.PlayerSpecs.GAME_SESSION_PARAMS, C.TTE)
    local tolerance = 0.1
    if current_weapon_id == bullet_weapon_id then
        if currentTTE and currentTTE > tolerance then
            log:error("The shot happened faster than the weapon's cooldown lets it", currentTTE)
            return
        end
    end

    -- play SFX
    local weaponServerInstance = WorldService.world:get(player_state.player_id, W.ServerInstance)
    local sound = weaponServerInstance:FindFirstChild("Fired", true)
    if sound then
        sound:Play()
    end

    -- reset  weapon's cooldown
    local cooldown = S.Weapon[current_weapon_id].cooldown
    player_state.state:set(Id.PlayerSpecs.GAME_SESSION_PARAMS, C.TTE, cooldown)

    local playerRoot = player_state.root
    -- TODO: refactor to coordinate this with the client ->
    local bulletStartPos = playerRoot.Position + playerRoot.CFrame.LookVector * SharedConfig.BULLET_RAYCAST_START_MULT

    for i = 1, #bullet_guids do
        WorldService.AddBulletToState(player_state, bullet_guids[i], current_weapon_id, bulletStartPos, player_state.player_id)
    end
end

on[Id.C2S.BUY_PLAYER_UPGRADE_PERS] = function(player_state, upgrade_id: id, ...)
    -- check if it is a valid upgrade id
    if Id.kind(upgrade_id) ~= Id.Kind.PlayerUpgradePersistent then
        log:error("Not a player upgrade", upgrade_id, debug.traceback())
        return
    end

    local itemPrice = assert(S.PlayerUpgradePersistent[upgrade_id].price)
    local currencyId = assert(S.PlayerUpgradePersistent[upgrade_id].currency)

    -- check if the previous upgrade of the same kind has been bought
    local previousUpgradeId = Misc.IsUpgradePreviousTier(upgrade_id)
    if previousUpgradeId then
        local isBoughtPrevious
        local prevUpgradeflags = player_state.state:get(previousUpgradeId, C.Bitset)
        isBoughtPrevious = Id.flag_test(prevUpgradeflags, Id.PlayerF.PERK_ACQUIRED)
        if not isBoughtPrevious then
            log:error("Previous upgrade not bought", previousUpgradeId, debug.traceback())
            return
        end
    end

    -- check if the player already has this upgrade
    local flags = player_state.state:get(upgrade_id, C.Bitset)
    local isAcquired = Id.flag_test(flags, Id.PlayerF.PERK_ACQUIRED)
    if isAcquired then
        return
    end

    -- check if there is enough funds
    if not Misc.IsEnoughFunds(player_state.state, itemPrice, currencyId) then
        player_state:NotifyClient(Id.S2C.SHOW_POPUP_SERVER, Id.C2S.BUY_PLAYER_UPGRADE_PERS)
        return
    end

    -- all checks done, buy upgrade
    player_state:DeductCountablePersistent(currencyId, itemPrice)
    player_state.state:set(upgrade_id, C.Bitset, Id.flag_or(flags, Id.PlayerF.PERK_ACQUIRED))
end

on[Id.C2S.TARGET_HIT] = function(playerState: PSS.PlayerState, targetGuids: { uid }, bulletGuid: uid, ...)
    -- NOTE: calculating bullet hit on client, verifying on server because it is cheaper (?)
    local playerFlags = playerState.state:get(Id.PlayerSpecs.GAME_SESSION_PARAMS, C.BitsetNonPers)
    local isPlayerInSession = playerFlags and Id.flag_test(playerFlags, Id.PlayerF.READY)
    if not isPlayerInSession then
        return
    end

    if not WorldService.world:has(bulletGuid) then
        return
    end
    local bulletStartPos = WorldService.world:get(bulletGuid, W.Position)
    local bulletWeaponId = WorldService.world:get(bulletGuid, W.WeaponId)
    local bulletWeaponDataEntry = S.Weapon[bulletWeaponId]

    if bulletWeaponId ~= Id.Weapon.ROCKET and #targetGuids > 1 then
        -- only rocket missile can hit multiple targets
        return
    end

    for _, targetGuid in ipairs(targetGuids) do
        if WorldService.world:has(targetGuid) then
            local targetRefId = WorldService.world:get(targetGuid, W.RefId)
            local targetPos
            local boosterServerInstance

            if Id.kind(targetRefId) == Id.Kind.Enemy then
                targetPos = WorldService.world:get(targetGuid, W.Position)
            elseif Id.kind(targetRefId) == Id.Kind.Boost then
                boosterServerInstance = WorldService.world:get(targetGuid, W.ServerInstance)
                targetPos = boosterServerInstance.Position
            elseif Id.kind(targetRefId) == Id.Kind.Obstacle then
                targetPos = WorldService.world:get(targetGuid, W.Position)
            end

            if not targetPos then
                return
            end

            -- TODO: FIXIT: spraygun bullets. Are they handled at all?

            local distance = (bulletStartPos - targetPos).Magnitude
            if bulletWeaponId == Id.Weapon.ROCKET then
                distance -= bulletWeaponDataEntry.explosionSize.Z
            end

            -- check for the range hacks
            local range = SharedConfig.BULLET_BASE_DISTANCE
            if bulletWeaponDataEntry.range then
                range = bulletWeaponDataEntry.range
            end
            local tolerance = 20
            if targetRefId == Id.Enemy.OCTOBOSS then
                tolerance = 50
            end
            if range + tolerance < distance then
                -- if math.abs(range - distance) > tolerance then
                log:error("Weapon's range is smaller than the distance of the bullet", range, distance, targetPos, debug.traceback)
                return
            end

            -- check for persistent firepower upgrades
            local firepowerBonus = 1
            local firepowerIdPers = Misc.IsFirepowerUpgrade(playerState)
            if firepowerIdPers then
                firepowerBonus = assert(S.PlayerUpgradePersistent[firepowerIdPers].value)
            end

            -- check for non-persistent firepower upgrades
            local firepowerNonPersFlags = playerState.state:get(Id.PlayerUpgradeNonPersistent.FIREPOWER, C.Bitset)
            if Id.flag_test(firepowerNonPersFlags, Id.PlayerF.PERK_ACTIVE) then
                local firepowerNonPersStage = playerState.state:get(Id.PlayerUpgradeNonPersistent.FIREPOWER, C.ValueNonPers)
                local bonusDmgPercent =
                    assert(S.PlayerUpgradeNonPersistent[Id.PlayerUpgradeNonPersistent.FIREPOWER].multiplier * firepowerNonPersStage)
                firepowerBonus += bonusDmgPercent
            end

            if Id.kind(targetRefId) == Id.Kind.Enemy then
                -- local enemyHP = WorldService.world:get(targetGuid, W.HP)
                local dmg = 0
                if bulletWeaponDataEntry and bulletWeaponDataEntry.damage then
                    dmg = math.floor(bulletWeaponDataEntry.damage * firepowerBonus)
                end
                onTargetHit(playerState, targetGuid :: str, dmg)
            elseif Id.kind(targetRefId) == Id.Kind.Boost then
                local dmg = math.floor(S.Weapon[bulletWeaponId].damage + firepowerBonus)
                onTargetHit(playerState, targetGuid :: str, dmg)
            elseif Id.kind(targetRefId) == Id.Kind.Obstacle then
                local dmg = math.floor(S.Weapon[bulletWeaponId].damage + firepowerBonus)
                onTargetHit(playerState, targetGuid :: str, dmg)
            else
                return
            end
        end
    end

    -- delete bullet entity
    WorldService.RemoveEntity(bulletGuid)
end

on[Id.C2S.PLAYER_READY_TO_START] = function(player_state, ...)
    local playerId = player_state.player_id
    local total_players = Players:GetPlayers()
    local players_already_in_session = 0
    if #total_players > 1 then
        for _, player in ipairs(total_players) do
            local thisPlayerState = get_state(player.UserId)
            if thisPlayerState then
                local nonPersF = thisPlayerState.state:get(Id.PlayerSpecs.GAME_SESSION_PARAMS, C.BitsetNonPers)
                local isReady = Id.flag_test(nonPersF, Id.PlayerF.READY)
                -- NOTE: player's own READY flag is set below, in GameModule.SpawnPlayer
                if isReady then
                    players_already_in_session += 1
                end
            end
        end
    end

    if players_already_in_session >= SharedConfig.MAX_PLAYERS_IN_SESSION then
        player_state:NotifyClient(Id.S2C.SHOW_POPUP_SERVER, Id.C2S.PLAYER_READY_TO_START)
        return
    end

    -- initialize main game loop if it is not initialized yet
    local isGameSessionInProgress = WorldService.world:get(Id.WorldSpecs.GAME_SESSION_IN_PROGRESS, W.Value)
    if not isGameSessionInProgress then
        startGameSession()
    end

    local playerHp = resetHp(player_state)
    changeWeapon(player_state, SharedConfig.DEFAULT_WEAPON_ID)

    GameModule.SpawnPlayer(player_state, players_already_in_session)
    Remote.Server.Broadcast(Id.S2CC.PLAYER_STARTED_SESSION, player_state.player_id, playerHp)

    -- give invincibility upgrade
    acquirePlayerUpgradeNonPers(player_state, Id.PlayerUpgradeNonPersistent.INVINCIBILITY)

    -- initialize player clones if any
    local cloneUpgradeId = Misc.IsCloneUpgrade(player_state)
    if cloneUpgradeId then
        local value = S.PlayerUpgradePersistent[cloneUpgradeId].value
        if value then
            for i = 1, value do
                local _cloneGuid = WorldService.AddClone(Id.Clone.REGULAR, playerId)
            end
        end
    end
end

on[Id.C2S.PERK_SELECTED] = function(player_state, whichPerk, ...)
    local playerFlags = player_state.state:get(Id.PlayerSpecs.GAME_SESSION_PARAMS, C.BitsetNonPers)
    -- check if player is in still session
    local isPlayerInSession = playerFlags and Id.flag_test(playerFlags, Id.PlayerF.READY)
    if not isPlayerInSession then
        return
    end

    if whichPerk == 0 then
        log:error("Invalid perk number", whichPerk, debug.traceback())
        return
    end
    local currentPerkSelection = player_state.state:get(Id.PlayerSpecs.XP_PROGRESS, C.V3) :: Vector3
    local perkId
    if whichPerk == 1 then
        perkId = currentPerkSelection.X
    elseif whichPerk == 2 then
        perkId = currentPerkSelection.Y
    end
    if perkId then
        acquirePlayerUpgradeNonPers(player_state, perkId)
    else
        log:error("No perk id, failure to set perk", debug.traceback())
        return
    end
end

on[Id.C2S.TOGGLE_PLAYER_FLAG] = function(player_state, isToSwitchOn, flag_id, ...)
    local flags = player_state.state:get(Id.PlayerSpecs.GAME_SESSION_PARAMS, C.Bitset)
    player_state.state:set(Id.PlayerSpecs.GAME_SESSION_PARAMS, C.Bitset, Id.flag_set(flags, flag_id, isToSwitchOn))
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

s2s[Id.S2S.CHANGE_WEAPON] = function(player_state, weapon_id, ...)
    changeWeapon(player_state, weapon_id)
end

s2s[Id.S2S.PLAYER_DIED] = function(player_state, deducted_hp: int, cause_id: id | uid?, ...)
    onPlayerSessionFinishedPlayerState(player_state, deducted_hp, cause_id)
end

s2s[Id.S2S.SHIELD_DAMAGE_SERVER] = function(player_state, target_guid: str, damage: int, ...)
    if damage > 0 then
        player_state:NotifyClient(Id.S2C.SHIELD_DAMAGE, damage)
    end
    onTargetHit(player_state, target_guid, damage)
end
-----------------------------
-- Player Connect
-----------------------------
-- place here all the logic that needs to be executed on player connect
local function init_player(player_state: PlayerState)
    return function()
        local _playerRank = player_state.state:constructor(C.ValueNonPers, C.PlayerRank, C.V3)
        _playerRank(Id.PlayerSpecs.XP_PROGRESS, 0, 0, Vector3.new(0, 0, 0))
        local _session_enemy_kills = player_state.state:constructor(C.ValueNonPers)
        _session_enemy_kills(Id.PlayerSpecs.SESSION_ENEMY_KILLS, 0)
        local _session_damage_stats = player_state.state:constructor(C.ValueNonPers)
        _session_damage_stats(Id.PlayerSpecs.SESSION_DAMAGE, 0)
        local _damage_throttle = player_state.state:constructor(C.TTE)
        _damage_throttle(Id.PlayerSpecs.DAMAGE_THROTTLE, 0)
        local persFlags = player_state.state:get(Id.PlayerSpecs.GAME_SESSION_PARAMS, C.Bitset)
        persFlags = Id.flag_or(persFlags, Id.PlayerF.OTHER_BULLETS_ON)
        persFlags = Id.flag_or(persFlags, Id.PlayerF.OTHER_CLONES_ON)
        player_state.state:set(Id.PlayerSpecs.GAME_SESSION_PARAMS, C.Bitset, persFlags)
        -- NOTE: not needed currently, this is for future purposes
        -- player_state:ResetCountable(Id.Countable.COIN)
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
        state:Destroy()
        onPlayerSessionFinishedWorld(state, state.player_id)
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

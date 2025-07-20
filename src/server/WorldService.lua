type str = string
type bool = boolean
type num = number
type integer = num
type uint = integer
type int = integer
type id = int
type guid = str
type uid = guid | id
type eid = int
type u32 = uint
type player_id = number
type i32 = int
type u8 = uint
type array<a> = { a }
type table = { [any]: any }
type fun = (...any) -> ...any
type map<k, v> = { [k]: v }
local _fmt = string.format

type v3 = Vector3
type cf = CFrame
local ZERO = Vector3.new(0, 0, 0)

local __DEV__ = not workspace or game:GetService("RunService"):IsStudio()
--[[ stylua: ignore]] game = game or require'game'
local shared = game.ReplicatedStorage.shared
local server = game.ServerScriptService.server

local Id = require(shared.Id)
local SharedConfig = require(shared.SharedConfig)
local W = SharedConfig.World.CId
local state = require(shared.state)
local _disposer = require(shared.disposer)
local _Remote = require(shared.Remote)
local _signal = require(shared.signal)
local _roflake = require(shared.roflake)
local S = require(shared.StaticData)
local logger = require(shared.logger)
local log = logger.create("WorldService"):set_delimiter(" "):set_prettifier(Id.pp)
local Remote = require(shared.Remote)
local Misc = require(shared.Misc)
local C = SharedConfig.PlayerState.CId
local Rand = require(shared.rand)

local WeaponsFolder = workspace.Weapons

local PSS = require(server.PlayerStateService)
type PlayerState = PSS.PlayerState
type GetState = (player_id) -> PlayerState?

-----------------------------
-- World
-----------------------------
local m = {}
m.W = W
m.world = state.main(SharedConfig.World.main_config)
m.nullary_transient = m.world:constructor("transient")

function m.ftest(guid: uid, flag: id): bool
    local flags = m.world:get(guid, W.Bitset)
    if not flags then
        log:error("flags not found for guid: ", guid, debug.traceback)
        return false
    end
    if Id.kind(flags) ~= Id.kind(flag) then
        log:error("flags and flag have different kinds: ", guid, flags, flag, debug.traceback)
        return false
    end
    return Id.flag_test(flags, flag)
end

function m.fset(guid: uid, flag: id, value: bool): ()
    local flags = m.world:get(guid, W.Bitset)
    if not flags then
        log:error("flags not found for guid: ", guid, debug.traceback)
        return
    end
    if Id.kind(flags) ~= Id.kind(flag) then
        log:error("flags and flag have different kinds: ", guid, flags, flag, debug.traceback)
        return
    end
    m.world:set(guid, W.Bitset, Id.flag_set(flags, flag, value))
end

function m.fflags(guid): Id.flag?
    local flags = m.world:get(guid, W.Bitset)
    if not flags then
        log:error("flags not found for guid: ", guid, debug.traceback)
    end
    return flags
end

function m.ChangeWeapon(player_state, player_id, weapon_id)
    if weapon_id == Id.Weapon._NONE then
        m.world:set(player_id, W.WeaponId, Id.Weapon._NONE)
        m.world:set(player_id, W.ServerInstance, nil)
    elseif m.world:get(player_id, W.WeaponId) ~= weapon_id then
        -- spawn instance and parent it to the player
        local char = player_state.character
        local weapon_instance = Misc.EquipWeaponModel(char, weapon_id)

        m.world:set(player_id, W.WeaponId, weapon_id)
        m.world:set(player_id, W.ServerInstance, weapon_instance)

        local sound = weapon_instance:FindFirstChild("Reload", true)
        if sound then
            sound:Play()
        end
    end
    Remote.Server.Broadcast(Id.S2CC.PLAYER_CHANGED_WEAPON, player_id, weapon_id)
end

local _playerEntity = m.world:constructor(W.Value, W.HP, W.ServerInstance, W.WeaponId) -- num of clones, player hp, weapon instance, weapon id
function m.AddPlayer(state)
    local player_id = state.player_id
    if m.world:has(player_id) then
        log:error("non-unique uid: ", player_id, m.world.format_row, m.world, player_id)
    end
    return _playerEntity(player_id, 0, SharedConfig.PLAYER_BASE_HP, nil, Id.Weapon._NONE)
end

function m.RemovePlayer(uid: uid)
    -- TODO: ?
end

function m.RemoveEntity(uid: uid)
    -- clones
    local refId = m.world:get(uid, W.RefId)
    if refId and Id.kind(refId) == Id.Kind.Clone then
        local playerId = m.world:get(uid, W.PlayerId)
        if not playerId then
            log:error("player id not found for clone: ", uid)
        end
        local playerClonesCount = m.world:get(playerId, W.Value)
        if not playerClonesCount then
            log:error("player clones count not found for player: ", playerId)
        else
            m.world:set(playerId, W.Value, playerClonesCount - 1)
        end
    end

    -- everything
    m.world:delete(uid)
end

local _booster = m.world:constructor(W.RefId, W.Value, W.HP, W.BoostContentId, W.ServerInstance)
function m.AddBooster(serverInstance: any, boostRefid: id, value: num, hp: num, boostContentId: id | bool)
    local guid = _roflake.uida()
    serverInstance.Name = guid
    local _ = _booster(guid, boostRefid, value, hp, boostContentId, serverInstance) :: str
    return guid
end

local _booster_wave_count = m.world:constructor(W.Value)
function m.UpdateBoosterWaveCount()
    local wavesTotal = m.world:get(Id.WorldSpecs.BOOST_WAVE_COUNT, W.Value)
    if not wavesTotal then
        local _ = _booster_wave_count(Id.WorldSpecs.BOOST_WAVE_COUNT, 1)
    else
        m.world:set(Id.WorldSpecs.BOOST_WAVE_COUNT, W.Value, wavesTotal + 1)
    end
end
function m.ResetBoosterWaveCount()
    local wavesTotal = m.world:get(Id.WorldSpecs.BOOST_WAVE_COUNT, W.Value)
    if not wavesTotal then
        local _ = _booster_wave_count(Id.WorldSpecs.BOOST_WAVE_COUNT, 0)
    else
        m.world:set(Id.WorldSpecs.BOOST_WAVE_COUNT, W.Value, 0)
    end
end

local _boss_fight_on = m.world:constructor(W.Value)
function m.SetBossFightOn(enemyGuid: guid)
    local refId = m.world:get(enemyGuid, W.RefId)
    if Id.kind(refId) ~= Id.Kind.Enemy then
        log:error("enemy guid is not an enemy: ", enemyGuid)
        return
    end
    local flags = m.world:get(enemyGuid, W.Bitset)
    m.world:set(enemyGuid, W.Bitset, Id.flag_or(flags, Id.EnemyF.IS_BOSS))

    -- if refId == Id.Enemy.OCTOBOSS then
    --     local tte = assert(S.Enemy[refId].tte) :: number
    --     m.world:set(enemyGuid, W.TTE, tte)
    --     local ttl = _roflake.time() + assert(S.Enemy[refId].jumpUpDuration) + assert(S.Enemy[refId].jumpDownDuration)
    --     m.world:set(enemyGuid, W.TTL, ttl)
    -- end

    local value = m.world:get(Id.WorldSpecs.BOSS_FIGHT_ON, W.Value)
    if value == nil then
        _boss_fight_on(Id.WorldSpecs.BOSS_FIGHT_ON, true)
    else
        m.world:set(Id.WorldSpecs.BOSS_FIGHT_ON, W.Value, true)
    end
end
function m.SetBossFightOff()
    local value = m.world:get(Id.WorldSpecs.BOSS_FIGHT_ON, W.Value)
    if value == nil then
        _boss_fight_on(Id.WorldSpecs.BOSS_FIGHT_ON, false)
    else
        m.world:set(Id.WorldSpecs.BOSS_FIGHT_ON, W.Value, false)
    end
end

local _game_session = m.world:constructor(W.Value)
function m.SetGameSessionOn()
    local value = m.world:get(Id.WorldSpecs.GAME_SESSION_IN_PROGRESS, W.Value)
    if value == nil then
        _game_session(Id.WorldSpecs.GAME_SESSION_IN_PROGRESS, true)
    else
        m.world:set(Id.WorldSpecs.GAME_SESSION_IN_PROGRESS, W.Value, true)
    end
end
function m.SetGameSessionOff()
    local value = m.world:get(Id.WorldSpecs.GAME_SESSION_IN_PROGRESS, W.Value)
    if value == nil then
        _game_session(Id.WorldSpecs.GAME_SESSION_IN_PROGRESS, false)
    else
        m.world:set(Id.WorldSpecs.GAME_SESSION_IN_PROGRESS, W.Value, false)
    end
end

local _pvp_time = m.world:constructor(W.Value)
function m.SetPvPTimeOn()
    local value = m.world:get(Id.WorldSpecs.PVP_TIME, W.Value)
    if value == nil then
        _pvp_time(Id.WorldSpecs.PVP_TIME, true)
    else
        m.world:set(Id.WorldSpecs.PVP_TIME, W.Value, true)
    end
end
function m.SetPvPTimeOff()
    local value = m.world:get(Id.WorldSpecs.PVP_TIME, W.Value)
    if value == nil then
        _pvp_time(Id.WorldSpecs.PVP_TIME, false)
    else
        m.world:set(Id.WorldSpecs.PVP_TIME, W.Value, false)
    end
end

function m.AddClone(id: id, player_id: int)
    local guid = m.nullary_transient(_roflake.uida())
    m.world:set(guid, W.RefId, id)
    m.world:set(guid, W.PlayerId, player_id)
    local isPlayerEntity = m.world:has(player_id)
    if not isPlayerEntity then
        log:error("player entity not found for player id: ", player_id)
    else
        local playerClonesCount = m.world:get(player_id, W.Value)
        local newCount = playerClonesCount + 1
        -- set clone index number to clone entity
        m.world:set(guid, W.Value, newCount)
        -- set new clone count to player entity
        m.world:set(player_id, W.Value, newCount)
    end
    return guid
end

local _enemy = m.world:constructor(W.RefId, W.HP, W.Position, W.PlayerId, W.TTL,W.TTE, W.Bitset)
function m.AddEnemyToState(id: id, pos)
    local hp = S.Enemy[id].health
    local guid = _roflake.uida()
    local tte = 0
    if S.Enemy[id].tte then
        tte = S.Enemy[id].tte :: number
    end
    _enemy(guid, id, hp, pos, SharedConfig.DEFAULT_PLAYER_ID, 0xffff_ffff, tte, Id.EnemyF.NONE)
    return guid
end

local _enemy_flying = m.world:constructor(W.RefId, W.HP, W.Position, W.PlayerId, W.TTE, W.Bitset)
function m.AddEnemyFlyingToState(id: id, pos: v3)
    local hp = S.EnemyFlying[id].health
    local guid = _roflake.uida()
    local period = assert(S.EnemyFlying[id].period)
    local tte = _roflake.time() + SharedConfig.FIRST_BOMB_DELAY + Rand.uniform(period.X, period.Y)
    _enemy_flying(guid, id, hp, pos, SharedConfig.DEFAULT_PLAYER_ID, tte, Id.EnemyF.NONE)
    return guid
end

local _bomb = m.world:constructor(W.RefId, W.Position, W.OwnerGuid)
function m.AddBombToState(id: id, pos: v3, ownerGuid: uid)
    local guid = _roflake.uida()
    _bomb(guid, id, pos, ownerGuid)
    return guid
end

local _obstacle = m.world:constructor(W.RefId, W.HP, W.Position)
function m.AddObstacleToWorldState(id: id, pos: v3)
    local guid = _roflake.uida()
    local hp = assert(S.Obstacle[id].hp)
    _obstacle(guid, id, hp, pos)
    return guid
end

local _obstacle_wave_count = m.world:constructor(W.Value)
function m.UpdateObstacleWaveCount()
    local wavesTotal = m.world:get(Id.WorldSpecs.OBSTACLE_WAVE_COUNT, W.Value)
    if not wavesTotal then
        local _ = _obstacle_wave_count(Id.WorldSpecs.OBSTACLE_WAVE_COUNT, 1)
    else
        m.world:set(Id.WorldSpecs.OBSTACLE_WAVE_COUNT, W.Value, wavesTotal + 1)
    end
end
function m.ResetObstacleWaveCount()
    local wavesTotal = m.world:get(Id.WorldSpecs.OBSTACLE_WAVE_COUNT, W.Value)
    if not wavesTotal then
        local _ = _obstacle_wave_count(Id.WorldSpecs.OBSTACLE_WAVE_COUNT, 0)
    else
        m.world:set(Id.WorldSpecs.OBSTACLE_WAVE_COUNT, W.Value, 0)
    end
end

local _bullet = m.world:constructor(W.Position, W.PlayerId, W.WeaponId, W.TTL) -- starting pos, owner's id, weapon_id, ttl
function m.AddBulletToState(playerState: PlayerState, guid, weaponId, startingPos, playerId)
    local range = SharedConfig.BULLET_BASE_DISTANCE
    if S.Weapon[weaponId].range then
        range = S.Weapon[weaponId].range
    end
    local speed = assert(S.Weapon[weaponId].baseSpeed)
    -- check for a bulletspeed perk
    local speedPerkFlags = playerState.state:get(Id.PlayerUpgradeNonPersistent.BULLET_SPEED_MULT, C.Bitset)
    local isSpeedPerkActive = Id.flag_test(speedPerkFlags, Id.PlayerF.PERK_ACTIVE)
    if isSpeedPerkActive then
        local mult = assert(S.PlayerUpgradeNonPersistent[Id.PlayerUpgradeNonPersistent.BULLET_SPEED_MULT].multiplier)
        local stage = playerState.state:get(Id.PlayerUpgradeNonPersistent.BULLET_SPEED_MULT, C.ValueNonPers) or 1
        speed *= 1 + mult * stage
    end
    local ttl = _roflake.time() + range / speed
    _bullet(guid, startingPos, playerId, weaponId, ttl)
end

local _enemyCounter = m.world:constructor(W.Value) -- enemy wave count
function m.GetEnemyWaveNumber()
    local currentNum = m.world:get(Id.WorldSpecs.ENEMY_WAVE_COUNT, W.Value)
    if not currentNum then
        currentNum = 0
        _enemyCounter(Id.WorldSpecs.ENEMY_WAVE_COUNT, currentNum)
    end
    return currentNum
end
function m.UpdateEnemyWaveCount()
    local newNum = m.GetEnemyWaveNumber() + 1
    m.world:set(Id.WorldSpecs.ENEMY_WAVE_COUNT, W.Value, newNum)
    return newNum
end
function m.ResetEnemyWaveCount()
    local _ = m.GetEnemyWaveNumber() -- to make sure that the entity is created
    m.world:set(Id.WorldSpecs.ENEMY_WAVE_COUNT, W.Value, 0)
end

-- function m.ResetTTL(guid: uid)
--     m.world:set(guid, W.TTL, 0xffff_ffff)
-- end

-------------------
-- Methods
-------------------

return m

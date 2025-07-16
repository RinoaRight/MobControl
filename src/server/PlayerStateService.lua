--!strict
--!native
-- MIT License
-- Copyright (c) 2024 Andrew Zhilin (https://github.com/zoon)

--[=[
    Header
    Usage:
    ```lua
    local x = ...
    ```
--]=]

local MOCK_DATASTORE_IN_STUDIO_FLAG = true
local IS_ROBLOX = not not game

local _USE_MOCK_DATASTORE = not IS_ROBLOX or MOCK_DATASTORE_IN_STUDIO_FLAG
local _DUMP_AFTER_SESSION = true

type str = string
type uid = string
type bool = boolean
type num = number
type integer = num
type uint = integer
type int = integer
type u32 = uint
type u8 = uint
type id = int
type array<a> = { a }
type map<k, v> = { [k]: v }
local fmt = string.format

--[[ stylua: ignore]] game = game or require("game")
local shared = game.ReplicatedStorage.shared
local server = game.ServerScriptService.server
local enum = require(shared.enum)
local _iota = enum.iota
local Id = require(shared.Id)
local lpack = require(shared.lpack)
local SharedConfig = require(shared.SharedConfig)
local state = require(shared.state)
local Signal = require(shared.signal)
local _ulid = require(shared.ulid)
local _roflake = require(shared.roflake)
local Remote = require(shared.Remote)
local disposer = require(shared.disposer)
local logger = require(shared.logger)
local log = logger.create("PlayerStateService"):set_prettifier(Id.pp)
local str = require(shared.str)
local C = SharedConfig.PlayerState.CId
local S = require(shared.StaticData)

-------------------
-- Server Modules
-------------------
local server = game.ServerScriptService.server
local _Market = require(server.Market)

local STORE_ID = "test"
local TIMEOUT = 15.00 -- sec

local STORE
if workspace and not _USE_MOCK_DATASTORE then
    local DataStoreService = game:GetService("DataStoreService")
    STORE = DataStoreService:GetDataStore(STORE_ID)
else
    local MockDataStore = require(shared.MockDataStore)
    MockDataStore.InitState(SharedConfig.Save) -- <== load from b64 encoded store
    type DataStore = MockDataStore.DataStore
    STORE = MockDataStore:GetDataStore(STORE_ID)
end

-------------------
-- Types
-------------------
type enum = enum.Enum
type disposer = disposer.Disposer

export type PlayerStateService = {
    load: (Player, Remote.FireClient) -> (PlayerState, array<any>),
    format: (PlayerState) -> str,
}

export type PlayerState = {
    player_id: int,
    state_store_key: str,
    state: state.Main,
    character: Model,
    humanoid: Humanoid,
    root: BasePart,
    maid: disposer,
    fire_client: Remote.FireClient,
    Save: (self: PlayerState) -> (),
    Destroy: (self: PlayerState) -> (),
    NotifyClient: (self: PlayerState, event_id: id, ...any) -> (),
    AddBooster: (self: PlayerState, instanceGuid: string) -> (),
    AddObstacle: (self: PlayerState, refId: id, pos: Vector3) -> uid,
    AddCountableNonPersistent: (self: PlayerState, id: id, count: int) -> (),
    AddCountablePersistent: (self: PlayerState, id: id, count: int) -> (),
    AddHp: (self: PlayerState, amount: num) -> (num, num),
    DeductCountableNonPersistent: (self: PlayerState, id: id, amount: int) -> (bool, id?, id?),
    DeductCountablePersistent: (self: PlayerState, id: id, amount: int) -> (bool, id?, id?),
    ResetCountable: (self: PlayerState, id: id) -> (),
    DeactivatePlayerUpgradeNonPers: (self: PlayerState, id: id) -> (),
    ActivatePlayerUpgradeNonPers: (self: PlayerState, id: id) -> (),
    DeductHp: (self: PlayerState, amount: num, cause: id | uid?) -> num,
    ChangeWeapon: (self: PlayerState, weapon_id: id) -> (),
    GetCloneAmount: (self: PlayerState, id: id) -> int,
    -- UpdatePlayerXP: (self: PlayerState, xp: int) -> (int, int),
    ResetPlayerXP: (self: PlayerState) -> (),
    UpdateSessionDamageStats: (self: PlayerState, dmg: num) -> int,
    UpdateSessionEnemyKills: (self: PlayerState) -> int,
    nullary_local: (state.uid_or_gen) -> uid,
    nullary_transient: (state.uid_or_gen) -> uid,
    __index: any,
    __tostring: (self: PlayerState) -> str,
    set_flag: (self: PlayerState, uid: state.uid, comp: state.cid, flag: Id.flag, val: bool) -> (),
    test_flag: (self: PlayerState, uid: state.uid, comp: state.cid, flag: Id.flag) -> bool,
}

-- note: was warm_up cache
local function update_ids(main: state.Main)
    local function merge(ids: enum.Enum, ctor: (id) -> (), limit: id?)
        for _, id in ids:ids() do
            if limit and id > limit then
                break
            end
            -- fill with default values if not set
            if not main:has(id) then
                ctor(id)
            end
        end
    end

    local _countable_non_persistent = main:constructor(C.ValueNonPers, C.Total)
    merge(Id.CountableNonPersistent, function(id)
        _countable_non_persistent(id, 0, 0)
    end)

    local _countable_persistent = main:constructor(C.ValuePers, C.Total)
    merge(Id.CountablePersistent, function(id)
        _countable_persistent(id, 0, 0)
    end)

    -- weapon_id, intended_pos_time_stamp, weapon_tte, hp, pers_flags, non_pers_flags, intended_pos
    local _game_session_params = main:constructor(C.RefId, C.TTL, C.TTE, C.ValueNonPers, C.Bitset, C.BitsetNonPers, C.V3)
    merge(Id.PlayerSpecs, function()
        _game_session_params(
            Id.PlayerSpecs.GAME_SESSION_PARAMS,
            Id.Weapon._NONE,
            0,
            0,
            SharedConfig.PLAYER_BASE_HP,
            Id.PlayerF._NONE,
            Id.PlayerF._NONE,
            Vector3.new(0, 0, 0)
        )
    end, Id.PlayerSpecs.GAME_SESSION_PARAMS)

    local _player_perk_non_persistent = main:constructor(C.TTL, C.TTE, C.ValueNonPers, C.Bitset, C.HP) -- ttl, stage number, flag, hp
    merge(Id.PlayerUpgradeNonPersistent, function(id)
        _player_perk_non_persistent(id, 0xffff_ffff, 0, 0, Id.PlayerF._NONE, 0)
    end)

    local _player_upgrade_persistent = main:constructor(C.Bitset) -- flag
    merge(Id.PlayerUpgradePersistent, function(id)
        _player_upgrade_persistent(id, Id.PlayerF._NONE)
    end)
end

local function create_state(player_state: PlayerState)
    log:trace("~~ Making initial state for player:", player_state.player_id)
    update_ids(player_state.state)
end

local function fill_state(player_state: PlayerState)
    log:assert(not player_state.state:env("READY"), "already loaded")
    local data, info = STORE:GetAsync(player_state.state_store_key)
    if info then -- save found
        log:trace("~~ store info-key ", info)
    end
    if data then
        local ok, err0 = pcall(function()
            local ok, save_or_err: str? = pcall(lpack.unpack, data, "base64" :: any)
            if not ok then
                log:throw(save_or_err :: str)
            else
                log:assert(type(save_or_err) == "table", "wrong data layout")
                player_state.state:load(save_or_err :: any)
            end
        end)
        if ok then
            update_ids(player_state.state)
        else
            -- NOTE: remove damaged state, kick player
            -- TODO: use hexify instead of '%q;
            STORE:RemoveVersionAsync(player_state.state_store_key, info.Version)
            log:error("damaged save for player id: %*, error: %*", player_state.player_id, err0)
            log:error(info.CreatedTime, info.UpdatedTime, info.Version, info:GetUserIds(), info:GetMetadata())
            log:error(str.hexify(data))
            local player = game:GetService("Players"):GetPlayerByUserId(player_state.player_id)
            if player then
                local msg = fmt("Error during loading save file: %*, error: %*", player_state.state_store_key, err0)
                player:Kick(msg)
            end
        end
    else -- no save found
        create_state(player_state)
    end
end

-----------------------------
-- Module
-----------------------------
local m = {}
m.__index = m
local PlayerState = {} :: PlayerState
PlayerState.__index = PlayerState

function m.load(player: Player, fire_client: Remote.FireClient): (PlayerState, array<any>)
    local state = state.main(SharedConfig.PlayerState.main_config)
    local char = player.Character or player.CharacterAdded:Wait()

    char.Archivable = true

    local player_state: PlayerState = table.freeze(setmetatable({
        player_id = player.UserId,
        state_store_key = tostring(player.UserId),
        state = state,
        character = char,
        humanoid = char:WaitForChild("Humanoid", TIMEOUT) :: Humanoid,
        root = char:WaitForChild("HumanoidRootPart", TIMEOUT) :: BasePart,
        intended_pos = Vector3.new(0, 0, 0),
        maid = disposer.new(),
        Remote.Server.US2CC.OnServerEvent:Connect(function(player, event_id, intended_pos, timestamp)
            if event_id == Id.C2S.PLAYER_INTENDED_POS then
                    -- if new timestamp is older than the previous, the event is expired, disregard
                    local previous_timestamp = state:get(Id.PlayerSpecs.GAME_SESSION_PARAMS, C.TTL)
                    if previous_timestamp > timestamp then
                        return
                    end
                    state:set(Id.PlayerSpecs.GAME_SESSION_PARAMS, C.V3, intended_pos)
                    state:set(Id.PlayerSpecs.GAME_SESSION_PARAMS, C.TTL, timestamp)
            end
        end),

        fire_client = fire_client,
        nullary_local = state:constructor("local", "transient"),
        nullary_transient = state:constructor("transient"),
    }, PlayerState)) :: any
    fill_state(player_state)
    log:trace("~~~> server\n", player_state, debug.traceback)
    local snapshot = state:snapshot("discard-log")
    return player_state, snapshot
end

-----------------------------
-- PlayerState
-----------------------------

function PlayerState.Save(self: PlayerState): ()
    local store_key = self.state_store_key
    local save = self.state:save()
    local data = lpack.pack(save, "base64")
    ---[[DEBUG:]] _debug(data)
    log:info("Saving state ...")
    local info = STORE:SetAsync(store_key, data)
    log:info("State saved", info)
    if _USE_MOCK_DATASTORE and _DUMP_AFTER_SESSION then
        local out = STORE:DumpStore()
        --- @note warn for use in production
        log:warn(">>> MockDataStore:", "\n", out)
    end
end

function PlayerState.Destroy(self: PlayerState): ()
    self.maid:Destroy()
end

function PlayerState.NotifyClient(self: PlayerState, event_id: id, ...: any): ()
    self.fire_client(event_id, nil, ...)
end

function PlayerState.AddCountableNonPersistent(self: PlayerState, countable_id: id, amount: int): ()
    log:assert(Id.kind(countable_id) == Id.Kind.CountableNonPersistent, "not a countable id", countable_id)
    log:assert(type(amount) == "number", "count must be a number")
    if amount == 0 then
        return -- do nothing
    end
    log:assert(amount > 0, "count always positive number")
    local current = self.state:get(countable_id, C.ValueNonPers)
    local total = self.state:get(countable_id, C.Total)
    self.state:set(countable_id, C.ValueNonPers, current + amount)
    self.state:set(countable_id, C.Total, total + amount)
end

function PlayerState.AddCountablePersistent(self: PlayerState, countable_id: id, amount: int): ()
    log:assert(Id.kind(countable_id) == Id.Kind.CountablePersistent, "not a countable id", countable_id)
    log:assert(type(amount) == "number", "count must be a number")
    if amount == 0 then
        return -- do nothing
    end
    log:assert(amount > 0, "count always positive number")
    local current = self.state:get(countable_id, C.ValuePers)
    local total = self.state:get(countable_id, C.Total)
    self.state:set(countable_id, C.ValuePers, current + amount)
    self.state:set(countable_id, C.Total, total + amount)
end

function PlayerState.DeductCountableNonPersistent(self: PlayerState, countable_id: id, amount: int): (bool, id?, id?)
    log:assert(Id.kind(countable_id) == Id.Kind.CountablePersistent, "not a countable id", countable_id)
    log:assert(type(amount) == "number", "count must be a number")
    if amount == 0 then
        return true
    end
    log:assert(amount > 0, "count always positive number")
    local current = self.state:get(countable_id, C.ValueNonPers)
    if current < amount then
        return false, Id.ServerError.NOT_ENOUGH, countable_id
    end
    self.state:set(countable_id, current - amount)
    return true
end

function PlayerState.DeductCountablePersistent(self: PlayerState, countable_id: id, amount: int): (bool, id?, id?)
    log:assert(Id.kind(countable_id) == Id.Kind.CountablePersistent, "not a countable id", countable_id)
    log:assert(type(amount) == "number", "count must be a number")
    if amount == 0 then
        return true
    end
    log:assert(amount > 0, "count always positive number")
    local current = self.state:get(countable_id, C.ValuePers)
    if current < amount then
        return false, Id.ServerError.NOT_ENOUGH, countable_id
    end
    self.state:set(countable_id, C.ValuePers, current - amount)
    return true
end

function PlayerState.ResetCountable(self: PlayerState, countable_id: id): ()
    self.state:set(countable_id, 0)
end

function PlayerState.DeactivatePlayerUpgradeNonPers(self: PlayerState, upgrade_id: id): ()
    -- all value are set back to default, except PERK_ACQUIRED flag and perk stage
    -- they reset only when player is dead and all perks are unacquired
    local flags = self.state:get(upgrade_id, C.Bitset)
    self.state:set(upgrade_id, C.Bitset, Id.flag_set(flags, Id.PlayerF.PERK_ACTIVE, false))
    self.state:set(upgrade_id, C.TTL, 0xffff_ffff)
    self.state:set(upgrade_id, C.TTE, 0)
    self.state:set(upgrade_id, C.HP, 0)
end

function PlayerState.ActivatePlayerUpgradeNonPers(self: PlayerState, perk_id: id): ()
    local flags = self.state:get(perk_id, C.Bitset)
    local duration
    if S.PlayerUpgradeNonPersistent[perk_id].period then
        duration = S.PlayerUpgradeNonPersistent[perk_id].period
    end

    -- set ttl
    local ttl
    if S.PlayerUpgradeNonPersistent[perk_id].isExpirable then
        if duration then
            ttl = _roflake.time() + duration
        else
            ttl = 0xffff_ffff
        end
        self.state:set(perk_id, C.TTL, ttl)
    end

    -- set tte
    if S.PlayerUpgradeNonPersistent[perk_id].isLooped then
        -- local tte = S.PlayerUpgradeNonPersistent[perk_id].period
        self.state:set(perk_id, C.TTE, 0)
    end

    self.state:set(perk_id, C.Bitset, Id.flag_or(flags, Id.PlayerF.PERK_ACQUIRED, Id.PlayerF.PERK_ACTIVE))
    if S.PlayerUpgradeNonPersistent[perk_id].hp then
        self.state:set(perk_id, C.HP, S.PlayerUpgradeNonPersistent[perk_id].hp)
    end
end

function PlayerState.ChangeWeapon(self: PlayerState, weapon_id: id)
    self.state:set(Id.PlayerSpecs.GAME_SESSION_PARAMS, C.RefId, weapon_id)
    local tte = 0
    if weapon_id ~= Id.Weapon._NONE then
        tte = S.Weapon[weapon_id].cooldown
    elseif not self.state:get(Id.PlayerSpecs.GAME_SESSION_PARAMS, C.TTE) then
        self.state:set(Id.PlayerSpecs.GAME_SESSION_PARAMS, C.TTE, tte)
    end
end

function PlayerState.AddHp(self: PlayerState, howMuch: num)
    local current = self.state:get(Id.PlayerSpecs.GAME_SESSION_PARAMS, C.ValueNonPers)
    local new_hp = math.min(current + howMuch, SharedConfig.PLAYER_BASE_HP)
    self.state:set(Id.PlayerSpecs.GAME_SESSION_PARAMS, C.ValueNonPers, new_hp)
    return current, new_hp
end

function PlayerState.DeductHp(self: PlayerState, howMuch: num, cause: id | uid?)
    -- check if player is invincible
    local flags = self.state:get(Id.PlayerUpgradeNonPersistent.INVINCIBILITY, C.Bitset)
    local isInvincible = Id.flag_test(flags, Id.PlayerF.PERK_ACTIVE)
    if isInvincible then
        -- no further checks, no damage, no state changes
        return 0
    end

    -- check if player has shield
    local shield_hp = self.state:get(Id.PlayerUpgradeNonPersistent.SHIELD, C.HP)
    local shield_flags = self.state:get(Id.PlayerUpgradeNonPersistent.SHIELD, C.Bitset)
    local isShieldActive = Id.flag_test(shield_flags, Id.PlayerF.PERK_ACTIVE)
    if isShieldActive and shield_hp > 0 then
        local new_shield_hp = math.max(shield_hp - howMuch, 0)
        self.state:set(Id.PlayerUpgradeNonPersistent.SHIELD, C.HP, new_shield_hp)
        if new_shield_hp <= 0 then
            self:DeactivatePlayerUpgradeNonPers(Id.PlayerUpgradeNonPersistent.SHIELD)
            howMuch -= shield_hp
        else
            -- no further checks, no damage, no state changes
            return 0
        end
    end

    -- check if player has armor
    local armor_flags = self.state:get(Id.PlayerUpgradeNonPersistent.ARMOR, C.Bitset)
    local isArmorActive = Id.flag_test(armor_flags, Id.PlayerF.PERK_ACTIVE)
    if isArmorActive then
        local armor_stage = self.state:get(Id.PlayerUpgradeNonPersistent.ARMOR, C.ValueNonPers)
        local armor_multiplier = S.PlayerUpgradeNonPersistent[Id.PlayerUpgradeNonPersistent.ARMOR].multiplier * armor_stage
        howMuch = math.floor(howMuch * (1 - armor_multiplier))
    end

    local current_hp = self.state:get(Id.PlayerSpecs.GAME_SESSION_PARAMS, C.ValueNonPers)
    local new_hp = math.max(current_hp - howMuch, 0)
    self.state:set(Id.PlayerSpecs.GAME_SESSION_PARAMS, C.ValueNonPers, new_hp)
    if new_hp <= 0 then
        Signal.Fire(Id.S2S.PLAYER_DIED, self.player_id, current_hp, cause)
    else
        self:NotifyClient(Id.S2C.PLAYER_DAMAGED, -howMuch, cause)
    end
    return new_hp
end

function PlayerState.UpdateSessionDamageStats(self: PlayerState, dmg: num): int
    local oldVal = self.state:get(Id.PlayerSpecs.GAME_SESSION_PARAMS, C.ValueNonPers)
    local newVal = oldVal + dmg
    self.state:set(Id.PlayerSpecs.SESSION_DAMAGE, C.ValueNonPers, newVal)
    return newVal
end

function PlayerState.UpdateSessionEnemyKills(self: PlayerState): int
    local oldVal = self.state:get(Id.PlayerSpecs.SESSION_ENEMY_KILLS, C.ValueNonPers)
    local newVal = oldVal + 1
    self.state:set(Id.PlayerSpecs.SESSION_ENEMY_KILLS, C.ValueNonPers, newVal)
    return newVal
end

-- function PlayerState.UpdatePlayerXP(self: PlayerState, received_xp: int): (int, int)
--     local current_rank = self.state:get(Id.PlayerSpecs.XP_PROGRESS, C.PlayerRank)
--     local current_xp = self.state:get(Id.PlayerSpecs.XP_PROGRESS, C.ValueNonPers)
--     local next_rank = current_rank
--     local next_xp = current_xp + received_xp
--     local xp_required = SharedConfig.PLAYER_RANK_XP_REQUIRED + current_rank * SharedConfig.PLAYER_RANK_XP_INCREMENT
--     if next_xp >= xp_required then
--         -- rank up
--         next_rank = current_rank + 1
--         next_xp = next_xp - xp_required
--         Signal.Fire(Id.S2S.RANK_UP, self.player_id, next_rank, next_xp)
--     end
--     self.state:set(Id.PlayerSpecs.XP_PROGRESS, C.PlayerRank, next_rank)
--     self.state:set(Id.PlayerSpecs.XP_PROGRESS, C.ValueNonPers, next_xp)
--     return next_rank, next_xp
-- end

function PlayerState.ResetPlayerXP(self: PlayerState): ()
    self.state:set(Id.PlayerSpecs.XP_PROGRESS, C.PlayerRank, 0)
    self.state:set(Id.PlayerSpecs.XP_PROGRESS, C.ValueNonPers, 0)
end

function PlayerState.GetCloneAmount(self: PlayerState, id: id): int
    local clonesAmount = 0
    for guid, id in self.state:select(C.RefId) do
        if Id.kind(id) == Id.Kind.Clone then
            clonesAmount += 1
        end
    end
    return clonesAmount
end

function PlayerState.set_flag(self: PlayerState, uid: state.uid, comp:state.cid, flag: Id.flag, value: bool)
    assert(comp == C.Bitset or comp == C.BitsetNonPers, "not Bitset of BitsetNonPers")
    local flags = self.state:get(uid, comp)
    if not flags then
        log:error("no component", uid, comp, debug.traceback)
        return
    end
    if Id.kind(flags) ~= Id.kind(flag) then
        log:error("different kinds", flags, flag, debug.traceback)
        return
    end
    self.state:set(uid, comp, Id.flag_set(flags, flag, value))
end
function PlayerState.test_flag(self: PlayerState, uid: state.uid, comp:state.cid, flag: Id.flag): bool
    assert(comp == C.Bitset or comp == C.BitsetNonPers, "not Bitset of BitsetNonPers")
    local flags = self.state:get(uid, comp)
    if not flags then
        log:error("no component", uid, comp, debug.traceback)
        return false
    end
    if Id.kind(flags) ~= Id.kind(flag) then
        log:error("different kinds", flags, flag, debug.traceback)
        return false
    end
    return Id.flag_test(flags, flag)
end

function PlayerState.AddBooster(self: PlayerState, instanceGuid: string): ()
    local _booster = self.state:constructor(C.BitsetNonPers)
    _booster(instanceGuid, Id.PlayerF._NONE)
end

function PlayerState.__tostring(self: PlayerState): str
    return fmt("PlayerState(%*)\n=====\n%*\n====\n", self.player_id, self.state:format_state("*"))
end
-----------------------------
-- Quick test
-----------------------------

warn("[PlayerStateService -- ok]")
return m

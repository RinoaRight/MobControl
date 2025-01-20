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

function m.ChangeWeapon(player_state, player_id, weapon_id)
    if weapon_id == Id.Weapon._NONE then
        m.world:set(player_id, W.WeaponId, Id.Weapon._NONE)
        m.world:set(player_id, W.ServerInstance, nil)
    else
        -- spawn instance and parent it to the player
        local char = player_state.character
        local weapon_instance = Misc.EquipWeaponModel(char, weapon_id)

        m.world:set(player_id, W.WeaponId, weapon_id)
        m.world:set(player_id, W.ServerInstance, weapon_instance)
    end
    Remote.Server.Broadcast(Id.S2CC.PLAYER_CHANGED_WEAPON, player_id, weapon_id)
end

local _playerEntity = m.world:constructor(W.HP, W.ServerInstance, W.WeaponId) -- player hp, weapon instance, weapon id
function m.AddPlayer(state)
    local player_id = state.player_id
    if m.world:has(player_id) then
        log:error("non-unique uid: ", player_id, m.world.format_row, m.world, player_id)
    end
    return _playerEntity(player_id, SharedConfig.PLAYER_BASE_HP, nil, Id.Weapon._NONE)
end

function m.RemovePlayer(uid: uid)
    -- TODO: ?
end

function m.RemoveEntity(uid: uid)
    m.world:delete(uid)
end

local _booster = m.world:constructor(W.RefId, W.Value, W.HP, W.BoostContentId, W.ServerInstance)
function m.AddBooster(serverInstance: any, boostRefid: id, value: num, hp: num, boostContentId: id | bool)
    local guid = _booster(_roflake.uida, boostRefid, value, hp, boostContentId, serverInstance) :: str
    serverInstance.Name = guid
    return guid
end

function m.AddClone(id: id, player_id: int)
    local guid = m.nullary_transient(_roflake.uida)
    m.world:set(guid, W.RefId, id)
    m.world:set(guid, W.PLayerId, player_id)
    return guid
end

local _enemy = m.world:constructor(W.RefId, W.HP, W.Position, W.ServerInstance, W.PLayerId, W.Bitset)
function m.AddEnemyToState(id: id, pos, serverInstance)
    local hp = S.Enemy[id].health
    local guid = _enemy(_roflake.uida, id, hp, pos, serverInstance, SharedConfig.DEFAULT_PLAYER_ID, Id.EnemyF.NONE)
    return guid
end

-------------------
-- Methods
-------------------

return m

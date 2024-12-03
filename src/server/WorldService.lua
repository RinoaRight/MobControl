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

-- TODO: loop that will check bullet ttl and collisions and do stuff corresponding to the booster destroyed
-- if boostRefid == _Id.Boost.ADD_CLONE then
--     -- TODO: set to playerstate
-- elseif boostRefid == _Id.Boost.BULLET_SPEED_MULT then
--     -- TODO: set to playerstate
-- elseif boostRefid == _Id.Boost.CHANGE_WEAPON then
--     if not boostContentId then
--         boostContentId = _Id.Weapon.DEFAULT
--     end
--     -- TODO: set to playerstate, equip tool, load animation if there is not one, stop the one if there is, then play again
--     local template = assert(S.Weapon[boostContentId].instance, "weapon model id not found")
--     template:Clone().Parent = WeaponsFolder

-- end
function m.SetTTL(player_id, ttl: num)
    m.world:set(player_id, W.TTL, ttl)
end

function m.ChangeWeapon(player_id, weapon_id)
    local weapon_instance = S.Weapon[weapon_id].instance
    -- TODO: spawn instance and parent it to the player
    m.world:set(player_id, W.WeaponId, weapon_id)
    m.world:set(player_id, W.ServerInstance, weapon_instance)
    m.SetTTL(player_id, S.Weapon[weapon_id].cooldown)
end

local _playerEntity = m.world:constructor(W.HP, W.ServerInstance, W.WeaponId, W.TTL)
function m.AddPlayer(state)
    local player_id = state.player_id
    local weapon_instance = S.Weapon[Id.Weapon.BASIC].instance
    if m.world:has(player_id) then
        log:error("non-unique uid: ", player_id, m.world.format_row, m.world, player_id)
    end
    return _playerEntity(player_id, SharedConfig.PLAYER_BASE_HP, weapon_instance, Id.Weapon.BASIC, S.Weapon[Id.Weapon.BASIC].cooldown)
end

function m.RemovePlayer(guid: guid)
    -- TODO: remove weapon instance? (if necessary)
end

function m.RemoveEntity(guid: guid)
    m.world:delete(guid)
end

local _booster = m.world:constructor(W.RefId, W.Value, W.HP, W.BoostContentId, W.ServerInstance)
function m.AddBooster(serverInstance: any, boostRefid: id, value: num, hp: num, boostContentId: id)
    local guid = _booster(_roflake.uida, boostRefid, value, hp, boostContentId, serverInstance) :: str
    serverInstance.Name = guid
    return guid
end

-------------------
-- Methods
-------------------

return m

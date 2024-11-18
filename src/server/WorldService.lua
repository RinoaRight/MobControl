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

local _Id = require(shared.Id)
local SharedConfig = require(shared.SharedConfig)
local W = SharedConfig.World.CId
local state = require(shared.state)
local _disposer = require(shared.disposer)
local _Remote = require(shared.Remote)
local _signal = require(shared.signal)
local _roflake = require(shared.roflake)

local PSS = require(server.PlayerStateService)
type PlayerState = PSS.PlayerState
type GetState = (player_id) -> PlayerState?

-----------------------------
-- World
-----------------------------
local m = {}
m.W = W
m.world = state.main(SharedConfig.World.main_config)

local _booster = m.world:constructor(W.RefId, W.Value, W.HP, W.WeaponRefID)
function m.addBooster(serverInstance: any, boostRefid: id, value: num, hp: num, gunId: id)
	local guid = _roflake.uida
	serverInstance.Name = guid
	if not gunId then
		gunId = _Id.Weapon.DEFAULT
	end
	if boostRefid == _Id.Boost.ADD_CLONE then
		-- TODO: set to playerstate
	elseif boostRefid == _Id.Boost.BULLET_SPEED_MULT then
		-- TODO: set to playerstate
	elseif boostRefid == _Id.Boost.CHANGE_WEAPON then
		-- TODO: set to playerstate
	end
	return _booster(guid, boostRefid, value, hp, gunId) :: str | id
end
-------------------
-- Methods
-------------------

return m

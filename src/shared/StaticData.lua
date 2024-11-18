type str = string
type bool = boolean
type num = number
type integer = num
type uint = integer
type int = integer
type id = int
type u32 = uint
type i32 = int
type u8 = uint
type array<a> = { a }
type table = { [any]: any }
type map<k, v> = { [k]: v }
type fun = (...any) -> ...any
type guid = str
type uid = str | id
local _fmt = string.format

local shared = game.ReplicatedStorage.shared
local Id = require(shared.Id)
-----------------------------
-- Module
-----------------------------
local m = {}
m.__index = m

m.Weapon = {
	[Id.Weapon.BASIC] = { baseSpeed = 20, damage = 10, cooldown = 1 }, -- units/sec, hp, secs
}

-- stylua: ignore
m.Boost = {
    [Id.Boost.ADD_CLONE]         = {valueRange = {1, 4}, hpRange = {50, 100}}, 
    [Id.Boost.BULLET_SPEED_MULT] = {valueRange = {50, 100}, hpRange = {50, 100}}, 
}

return m

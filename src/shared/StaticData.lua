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

local ReplicatedStorage = game.ReplicatedStorage
local shared = ReplicatedStorage.shared
local Id = require(shared.Id)
-----------------------------
-- Module
-----------------------------
local m = {}
m.__index = m

m.Animation = {
    [Id.Animation.HOLD] = "rbxassetid://14928151227"
}

m.Weapon = {
	[Id.Weapon.BASIC] = { baseSpeed = 40, damage = 10, cooldown = .5, instance = ReplicatedStorage.Weapons.Pistol }, -- units/sec, hp, secs
}

-- stylua: ignore
-- TODO: real values
m.Boost = {
    [Id.Boost.ADD_CLONE]         = {valueRange = {2,2}, hpRange = {50, 100}}, 
    [Id.Boost.BULLET_SPEED_MULT] = {valueRange = {50, 100}, hpRange = {50, 100}}, 
}

return m

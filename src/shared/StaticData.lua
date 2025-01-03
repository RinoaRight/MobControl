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

local SoundService = game:GetService("SoundService")
local SOUNDS_ROOT = assert(SoundService:WaitForChild("SFX"))
local LOCALIZED_SOUNDS_ROOT = assert(ReplicatedStorage:WaitForChild("Sounds"))
-----------------------------
-- Module
-----------------------------
local m = {}
m.__index = m

m.Animation = {
    [Id.Animation.HOLD] = "rbxassetid://14928151227",
}

m.Weapon = {
    [Id.Weapon.BASIC] = {
        baseSpeed = 40,
        damage = 10,
        cooldown = .5,
        instance = ReplicatedStorage.Weapons.PistolModel,
        name = "Pistol",
    }, -- units/sec, hp, secs
}

-- stylua: ignore
-- TODO: real values
m.Boost = {
    [Id.Boost.ADD_CLONE]         = {valueRange = {2,2}, hpRange = {50, 100}}, 
    [Id.Boost.BULLET_SPEED_MULT] = {valueRange = {50, 100}, hpRange = {50, 100}}, 
}

m.Sound = {
    [Id.Sound.FIRE_PISTOL]           = assert(SOUNDS_ROOT:WaitForChild("Fired")),
    [Id.Sound.FIRE_PISTOL_LOCALIZED] = assert(LOCALIZED_SOUNDS_ROOT:WaitForChild("FiredOther")),
    [Id.Sound.RELOAD]                = assert(SOUNDS_ROOT:WaitForChild("Reload")),
    [Id.Sound.SCREAM]                = assert(SOUNDS_ROOT:WaitForChild("Scream")),
    [Id.Sound.SCREAM_LOCALIZED]      = assert(LOCALIZED_SOUNDS_ROOT:WaitForChild("Scream")),
}

return m

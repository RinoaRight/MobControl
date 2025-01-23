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
local ENEMIES_TEMPLATE_FOLDER = ReplicatedStorage:WaitForChild("Enemies")
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
        cooldown = 0.5,
        instance = ReplicatedStorage.Weapons.PistolModel,
        name = "Pistol",
    }, -- units/sec, hp, secs
    [Id.Weapon.SMG] = {
        baseSpeed = 80,
        damage = 5,
        cooldown = 0.2,
        -- TODO: change model
        instance = ReplicatedStorage.Weapons.PistolModel,
        name = "SMG",
    }, -- units/sec, hp, secs
}

-- stylua: ignore
m.Boost = {
    -- TODO: real values
    [Id.Boost.ADD_CLONE]         = {valueRange = {2,2}, hpRange = {50, 100}},
    [Id.Boost.CHANGE_WEAPON]     = {valueRange = {0, 0}, hpRange = {50, 100}, contentsRange = {Id.Weapon.SMG, Id.Weapon.SMG}},
    -- [Id.Boost.BULLET_SPEED_MULT] = {valueRange = {50, 100}, hpRange = {50, 100}},
}

m.Enemy = {
    [Id.Enemy.BASIC] = { damage = 10, health = 10, speed = 30.0, meshTemplate = ENEMIES_TEMPLATE_FOLDER:WaitForChild("Pet_zombie_1") }, -- hp, hp, studs/sec, assetId
}

m.Sound = {
    [Id.Sound.FIRE_PISTOL] = assert(SOUNDS_ROOT:WaitForChild("Fired")),
    [Id.Sound.FIRE_PISTOL_LOCALIZED] = assert(LOCALIZED_SOUNDS_ROOT:WaitForChild("FiredOther")),
    [Id.Sound.RELOAD] = assert(SOUNDS_ROOT:WaitForChild("Reload")),
    [Id.Sound.SCREAM] = assert(SOUNDS_ROOT:WaitForChild("Scream")),
    [Id.Sound.SCREAM_LOCALIZED] = assert(LOCALIZED_SOUNDS_ROOT:WaitForChild("Scream")),
}

return m

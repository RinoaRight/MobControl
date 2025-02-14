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
local WEAPONS_ROOT = ReplicatedStorage:WaitForChild("Weapons")
local VFX_ROOT = ReplicatedStorage:WaitForChild("VFX")
-----------------------------
-- Module
-----------------------------
local m = {}
m.__index = m

m.Animation = {
    [Id.Animation.HOLD] = "rbxassetid://14928151227",
}

m.Weapon = {
    -- TODO: real sizes
    [Id.Weapon.BASIC] = {
        baseSpeed = 50, -- units/sec
        range = 240, -- units
        damage = 10,
        cooldown = 0.5, --sec
        bulletSize = Vector3.new(1.5, 1.5, 1.5),
        instance = WEAPONS_ROOT.PistolModel,
        name = "Pistol",
    },
    [Id.Weapon.SMG] = {
        baseSpeed = 50,
        range = 200, -- units
        damage = 5,
        cooldown = 0.2,
        bulletSize = Vector3.new(1, 1, 1),
        -- TODO: change model
        instance = WEAPONS_ROOT.PistolModel,
        name = "SMG",
    },
    [Id.Weapon.SPRAYGUN] = {
        baseSpeed = 50,
        range = 100, -- units
        damage = 5,
        cooldown = 0.7,
        bulletSize = Vector3.new(1.5, 1.5, 1.5),
        -- TODO: change model
        instance = WEAPONS_ROOT.PistolModel,
        name = "Spraygun",
    },
    [Id.Weapon.ROCKET] = {
        baseSpeed = 50,
        range = 200, -- units
        damage = 50,
        cooldown = 1.2,
        bulletSize = Vector3.new(4, 4, 6),
        explosionSize = Vector3.new(10, 10, 10),
        -- TODO: change model
        instance = WEAPONS_ROOT.PistolModel,
        name = "Rocket",
    },
}

-- stylua: ignore
m.Boost = {
    -- TODO: real values
    [Id.Boost.ADD_CLONE]         = {valueRange = {2,2}, hpRange = {50, 100}},
    [Id.Boost.CHANGE_WEAPON]     = {valueRange = {0, 0}, hpRange = {50, 100}, contentsRange = {Id.Weapon.SMG, Id.Weapon.ROCKET}},
    [Id.Boost.FIRST_AID_KIT]     = {valueRange = {20, 50}, hpRange = {50, 100}},
    -- [Id.Boost.BULLET_SPEED_MULT] = {valueRange = {50, 100}, hpRange = {50, 100}},
}

m.Enemy = {
    [Id.Enemy.BASIC] = { damage = 10, health = 10, speed = 30.0, meshTemplate = ENEMIES_TEMPLATE_FOLDER:WaitForChild("Pet_zombie_1") }, -- hp, hp, studs/sec, assetId
    [Id.Enemy.CRAZY] = { damage = 15, health = 15, speed = 40.0, meshTemplate = ENEMIES_TEMPLATE_FOLDER:WaitForChild("Pet_zombie_3") }, -- hp, hp, studs/sec, assetId
}

m.Sound = {
    [Id.Sound.FIRE_PISTOL] = assert(SOUNDS_ROOT:WaitForChild("Fired")),
    [Id.Sound.FIRE_PISTOL_LOCALIZED] = assert(LOCALIZED_SOUNDS_ROOT:WaitForChild("FiredOther")),
    [Id.Sound.RELOAD] = assert(SOUNDS_ROOT:WaitForChild("Reload")),
    [Id.Sound.SCREAM] = assert(SOUNDS_ROOT:WaitForChild("Scream")),
    [Id.Sound.SCREAM_LOCALIZED] = assert(LOCALIZED_SOUNDS_ROOT:WaitForChild("Scream")),
}

m.VFX = {
    -- TODO: FIXIT. Explosion doesn't appear in Replicate dStorage of a player outside the editor
    -- [Id.VFX.EXPLOSION] = assert(VFX_ROOT:WaitForChild("Explosion")),
}

return m

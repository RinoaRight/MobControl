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
local GRAVES_TEMPLATE_FOLDER = ReplicatedStorage:WaitForChild("Graves")
local WEAPONS_ROOT = ReplicatedStorage:WaitForChild("Weapons")
local VFX_ROOT = ReplicatedStorage:WaitForChild("VFX")
-----------------------------
-- Module
-----------------------------
local m = {}
m.__index = m

m.Animation = {
    [Id.Animation.DANCE] = "rbxassetid://507771019",
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
    [Id.Boost.ADD_CLONE]         = {valueRange = {2, 2}, baseReward = 1, hpRange = {50, 100}},
    [Id.Boost.CHANGE_WEAPON]     = {valueRange = {0, 0}, baseReward = 1, hpRange = {50, 100}, contentsRange = {Id.Weapon.SMG, Id.Weapon.ROCKET}},
    [Id.Boost.FIRST_AID_KIT]     = {valueRange = {20, 50}, baseReward = 1, hpRange = {50, 100}},
    -- [Id.Boost.BULLET_SPEED_MULT] = {valueRange = {50, 100}, hpRange = {50, 100}},
}

m.Countable = {
    [Id.Countable.COIN] = {
        name = "Token",
    },
}

m.Enemy = {
    [Id.Enemy.BASIC] = {
        damage = 10,
        health = 10,
        speed = 30.0,
        reward = 1,
        meshTemplate = ENEMIES_TEMPLATE_FOLDER:WaitForChild("Pet_zombie_1"),
    }, -- hp, hp, studs/sec, coins, assetId
    [Id.Enemy.CRAZOMBIE] = {
        damage = 15,
        health = 15,
        speed = 40.0,
        reward = 1,
        meshTemplate = ENEMIES_TEMPLATE_FOLDER:WaitForChild("Pet_zombie_3"),
    },
    [Id.Enemy.OCTOBOSS] = {
        damage = 30,
        health = 1000,
        speed = 20.0,
        reward = 10,
        meshTemplate = ENEMIES_TEMPLATE_FOLDER:WaitForChild("Octoboss"),
    },
}

m.EnemyFlying = {
    [Id.EnemyFlying.ZOMBALLOON] = {
        damage = 20,
        health = 10,
        speed = 30.0,
        reward = 3,
        meshTemplate = ENEMIES_TEMPLATE_FOLDER:WaitForChild("Pet_zombie_9"),
    },
}

local function getValuePercent(val: num)
    local percent = (val * 100 - 100)
    return percent
end

m.Obstacle = {
    [Id.Obstacle.GRAVE] = {
        damage = 20,
        hp = 20,
        reward = 1,
        meshTemplateFull = GRAVES_TEMPLATE_FOLDER:WaitForChild("Enemy_GraveSmall1"),
        meshTemplateHalf = GRAVES_TEMPLATE_FOLDER:WaitForChild("Enemy_GraveSmall2"),
        meshTemplateLast = GRAVES_TEMPLATE_FOLDER:WaitForChild("Enemy_GraveSmall3"),
    },
}

m.PlayerUpgrade = {
    [Id.PlayerUpgrade.FIREPOWER_1] = {
        value = 1.1, -- %
        price = 50,
        currency = Id.Countable.COIN,
        name = "Firepower I",
        descr = string.format("+%d%% firepower", getValuePercent(1.1)),
    },
    [Id.PlayerUpgrade.FIREPOWER_2] = {
        value = 1.2, -- %
        price = 120,
        currency = Id.Countable.COIN,
        name = "Firepower II",
        descr = string.format("+%d%% firepower", getValuePercent(1.2)),
    },
    [Id.PlayerUpgrade.FIREPOWER_3] = {
        value = 1.3, -- %
        price = 250,
        currency = Id.Countable.COIN,
        name = "Firepower III",
        descr = string.format("+%d%% firepower", getValuePercent(1.3)),
    },
    [Id.PlayerUpgrade.FIREPOWER_4] = {
        value = 1.4, -- %
        price = 500,
        currency = Id.Countable.COIN,
        name = "Firepower IV",
        descr = string.format("+%d%% firepower", getValuePercent(1.4)),
    },
    [Id.PlayerUpgrade.FIREPOWER_5] = {
        value = 1.5, -- %
        price = 800,
        currency = Id.Countable.COIN,
        name = "Firepower V",
        descr = string.format("+%d%% firepower", getValuePercent(1.5)),
    },
    [Id.PlayerUpgrade.HITPOINTS_1] = {
        value = 1.1, -- %
        price = 40,
        currency = Id.Countable.COIN,
        name = "Hitpoints I",
        descr = string.format("+%d%% hitpoints", getValuePercent(1.1)),
    },
    [Id.PlayerUpgrade.HITPOINTS_2] = {
        value = 1.2, -- %
        price = 100,
        currency = Id.Countable.COIN,
        name = "Hitpoints II",
        descr = string.format("+%d%% hitpoints", getValuePercent(1.2)),
    },
    [Id.PlayerUpgrade.HITPOINTS_3] = {
        value = 1.3, -- %
        price = 200,
        currency = Id.Countable.COIN,
        name = "Hitpoints III",
        descr = string.format("+%d%% hitpoints", getValuePercent(1.3)),
    },
    [Id.PlayerUpgrade.HITPOINTS_4] = {
        value = 1.4, -- %
        price = 400,
        currency = Id.Countable.COIN,
        name = "Hitpoints IV",
        descr = string.format("+%d%% hitpoints", getValuePercent(1.4)),
    },
    [Id.PlayerUpgrade.HITPOINTS_5] = {
        value = 1.5, -- %
        price = 700,
        currency = Id.Countable.COIN,
        name = "Hitpoints V",
        descr = string.format("+%d%% hitpoints", getValuePercent(1.5)),
    },
    [Id.PlayerUpgrade.INIT_CLONE_1] = {
        value = 1, -- unit
        price = 100,
        currency = Id.Countable.COIN,
        name = "Clones I",
        descr = string.format("1 clone at the start"),
    },
    [Id.PlayerUpgrade.INIT_CLONE_2] = {
        value = 2, -- unit
        price = 300,
        currency = Id.Countable.COIN,
        name = "Clones II",
        descr = string.format("2 clones at the start"),
    },
    [Id.PlayerUpgrade.INIT_CLONE_3] = {
        value = 3, -- unit
        price = 600,
        currency = Id.Countable.COIN,
        name = "Clones III",
        descr = string.format("3 clones at the start"),
    },
}

m.Sound = {
    [Id.Sound.BELL] = assert(SOUNDS_ROOT:WaitForChild("Bell")),
    [Id.Sound.CLICK] = assert(SOUNDS_ROOT:WaitForChild("Click")),
    [Id.Sound.COIN_DROP] = assert(SOUNDS_ROOT:WaitForChild("CoinDrop")),
    [Id.Sound.CREAK_METAL] = assert(SOUNDS_ROOT:WaitForChild("CreakMetalHeavy")),
    [Id.Sound.ERROR] = assert(SOUNDS_ROOT:WaitForChild("ErrorZap")),
    [Id.Sound.FIRE_PISTOL] = assert(SOUNDS_ROOT:WaitForChild("Fired")),
    [Id.Sound.RELOAD] = assert(SOUNDS_ROOT:WaitForChild("Reload")),
    [Id.Sound.SCREAM] = assert(SOUNDS_ROOT:WaitForChild("Scream")),
    [Id.Sound.THUMP] = assert(SOUNDS_ROOT:WaitForChild("Thump")),
    -- localized sounds
    [Id.Sound.FIRE_PISTOL_LOCALIZED] = assert(LOCALIZED_SOUNDS_ROOT:WaitForChild("FiredOther")),
    [Id.Sound.SCREAM_LOCALIZED_HIGH] = assert(LOCALIZED_SOUNDS_ROOT:WaitForChild("ScreamHigh")),
    [Id.Sound.SCREAM_LOCALIZED_REG] = assert(LOCALIZED_SOUNDS_ROOT:WaitForChild("ScreamReg")),
    [Id.Sound.THUMP_LOCALIZED] = assert(LOCALIZED_SOUNDS_ROOT:WaitForChild("Thump")),
}

m.VFX = {
    -- TODO: FIXIT. Explosion doesn't appear in Replicated Storage of a player outside the editor
    -- [Id.VFX.EXPLOSION] = assert(VFX_ROOT:WaitForChild("Explosion")),
}

return m

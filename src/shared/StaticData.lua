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
local ZOMBIES_TEMPLATE_FOLDER = assert(ENEMIES_TEMPLATE_FOLDER:WaitForChild("Zombies"))
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
    [Id.Animation.RIFLE_AIM] = "rbxassetid://3972164452",
}

m.Weapon = {
    -- TODO: real sizes
    [Id.Weapon.BASIC] = {
        baseSpeed = 50, -- units/sec
        range = 240, -- units
        damage = 10,
        cooldown = 0.5, --sec
        bulletSize = Vector3.new(1.5, 1.5, 1.5),
        barrelLength = 1,
        magazineSize = 100,
        instance = WEAPONS_ROOT.PistolModel,
        name = "Pistol",
    },
    [Id.Weapon.SMG] = {
        baseSpeed = 50,
        range = 200, -- units
        damage = 5,
        cooldown = 0.2,
        bulletSize = Vector3.new(1, 1, 1),
        barrelLength = 1.5,
        magazineSize = 250,
        instance = WEAPONS_ROOT.SMGModel,
        name = "SMG",
    },
    [Id.Weapon.SPRAYGUN] = {
        baseSpeed = 50,
        range = 100, -- units
        damage = 5,
        cooldown = 0.7,
        bulletSize = Vector3.new(1.5, 1.5, 1.5),
        barrelLength = 2.5,
        magazineSize = 70,
        instance = WEAPONS_ROOT.ShotgunModel,
        name = "Spraygun",
    },
    [Id.Weapon.ROCKET] = {
        baseSpeed = 50,
        range = 200, -- units
        damage = 50,
        cooldown = 1.2,
        bulletSize = Vector3.new(4, 4, 6),
        barrelLength = 3,
        magazineSize = 30,
        explosionSize = Vector3.new(20, 20, 20),
        instance = WEAPONS_ROOT.RocketLauncherModel,
        name = "Rocket",
    },
}

m.Bomb = {
    [Id.Bomb.ZOMBALLOON_BOMB] = {
        bombSpeed = 1,
        damage = 40,
        explosionSize = Vector3.new(30, 30, 30),
    },
}

-- stylua: ignore
m.Boost = {
    [Id.Boost.ADD_CLONE]         = {valueRange = Vector2.new(1, 2), baseReward = 1, xp = 1, hpRange = Vector2.new(50, 100)},
    [Id.Boost.CHANGE_WEAPON]     = {valueRange = Vector2.new(0, 0), baseReward = 1, xp = 1, hpRange = Vector2.new(50, 100), contentsRange = {Id.Weapon.SMG, Id.Weapon.ROCKET}},
    [Id.Boost.FIRST_AID_KIT]     = {valueRange = Vector2.new(20, 50), baseReward = 1, xp = 1, hpRange = Vector2.new(50, 100)},
}

m.Countable = {
    [Id.CountablePersistent.COIN] = {
        name = "Token",
    },
}

m.Enemy = {
    [Id.Enemy.BASIC] = {
        damage = 10,
        health = 10,
        speed = 30.0, -- studs/sec
        reward = 1,
        xp = 1,
        meshTemplate = ZOMBIES_TEMPLATE_FOLDER:WaitForChild("Pet_zombie_1"),
    }, -- hp, hp, studs/sec, coins, xp, assetId
    [Id.Enemy.CRAZOMBIE] = {
        damage = 15,
        health = 15,
        speed = 40.0,
        reward = 1,
        xp = 1,
        meshTemplate = ZOMBIES_TEMPLATE_FOLDER:WaitForChild("Pet_zombie_3"),
    },
    [Id.Enemy.CONEHEAD] = {
        damage = 15,
        health = 30,
        armor = 15, -- of total hp
        speed = 20.0,
        reward = 2,
        xp = 2,
        meshTemplate = ZOMBIES_TEMPLATE_FOLDER:WaitForChild("Pet_zombie_6"),
        meshTemplateNoArmor = ZOMBIES_TEMPLATE_FOLDER:WaitForChild("Pet_zombie_1"),
    },
    [Id.Enemy.ZOMBUCKET] = {
        damage = 20,
        health = 45,
        armor = 30, -- of total hp
        speed = 10.0,
        reward = 3,
        xp = 3,
        meshTemplate = ZOMBIES_TEMPLATE_FOLDER:WaitForChild("Pet_zombie_7"),
        meshTemplateNoArmor = ZOMBIES_TEMPLATE_FOLDER:WaitForChild("Pet_zombie_1"),
    },
    [Id.Enemy.OCTOBOSS] = {
        damage = 30,
        health = 10000,
        speed = 10.0,
        reward = 10,
        xp = 10,
        animationDur = 2.1,
        ttl = 5.0, -- time for which the enemy is locked on 1 player
        tte = 4, -- NOTE: should be greater than jump animation duration
        hitThrottleDuration = .5,
        specialAttackRange = 55,
        ultDamage = 20,
        meshTemplate = ZOMBIES_TEMPLATE_FOLDER:WaitForChild("Octoboss"),
    },
}

m.EnemyFlying = {
    [Id.EnemyFlying.ZOMBALLOON] = {
        -- damage = 40,
        health = 10,
        period = Vector2.new(2.5, 3.5),
        -- bombSpeed = 1,
        flyerHeight = 50,
        reward = 3,
        xp = 10,
        -- explosionSize = Vector3.new(20, 20, 20),
        meshTemplate = ZOMBIES_TEMPLATE_FOLDER:WaitForChild("Pet_zombie_9"),
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
        xp = 1,
        meshTemplateFull = GRAVES_TEMPLATE_FOLDER:WaitForChild("Enemy_GraveSmall1"),
        meshTemplateHalf = GRAVES_TEMPLATE_FOLDER:WaitForChild("Enemy_GraveSmall2"),
        meshTemplateLast = GRAVES_TEMPLATE_FOLDER:WaitForChild("Enemy_GraveSmall3"),
    },
    [Id.Obstacle.GRAVE_MED] = {
        damage = 25,
        hp = 30,
        reward = 1,
        xp = 1,
        meshTemplateFull = GRAVES_TEMPLATE_FOLDER:WaitForChild("Enemy_GraveMedium1"),
        meshTemplateHalf = GRAVES_TEMPLATE_FOLDER:WaitForChild("Enemy_GraveMedium2"),
        meshTemplateLast = GRAVES_TEMPLATE_FOLDER:WaitForChild("Enemy_GraveMedium3"),
    },
    [Id.Obstacle.GRAVE_LARGE] = {
        damage = 30,
        hp = 40,
        reward = 1,
        xp = 1,
        meshTemplateFull = GRAVES_TEMPLATE_FOLDER:WaitForChild("Enemy_GraveLarge1"),
        meshTemplateHalf = GRAVES_TEMPLATE_FOLDER:WaitForChild("Enemy_GraveLarge2"),
        meshTemplateLast = GRAVES_TEMPLATE_FOLDER:WaitForChild("Enemy_GraveLarge3"),
    },
    [Id.Obstacle.CROSS] = {
        damage = 35,
        hp = 50,
        reward = 1,
        xp = 2,
        meshTemplateFull = GRAVES_TEMPLATE_FOLDER:WaitForChild("Enemy_Cross1"),
        meshTemplateHalf = GRAVES_TEMPLATE_FOLDER:WaitForChild("Enemy_Cross2"),
        meshTemplateLast = GRAVES_TEMPLATE_FOLDER:WaitForChild("Enemy_Cross3"),
    },
    [Id.Obstacle.CELTIC_CROSS] = {
        damage = 40,
        hp = 60,
        reward = 1,
        xp = 2,
        meshTemplateFull = GRAVES_TEMPLATE_FOLDER:WaitForChild("Enemy_CelticCross1"),
        meshTemplateHalf = GRAVES_TEMPLATE_FOLDER:WaitForChild("Enemy_CelticCross2"),
        meshTemplateLast = GRAVES_TEMPLATE_FOLDER:WaitForChild("Enemy_CelticCross3"),
    },
}

m.Handicap = {
    [Id.Handicap.BOMBS] = {
        -- double bombs
        name = "Double bombs, armored clones",
        color = Color3.fromRGB(255, 0, 0),
    },
    [Id.Handicap.GRAVES] = {
        name = "Double obstacles",
        color = Color3.fromRGB(208, 0, 255),
    },
    [Id.Handicap.DOUBLE_HP] = {
        -- enemies and players receive double HP
        name = "Double HP enemies and players",
        color = Color3.fromRGB(255, 162, 0),
    },
    [Id.Handicap.FINITE_AMMO] = {
        -- players have finite ammo
        name = "No infinite ammo",
        color = Color3.fromRGB(0, 162, 255),
    },
}

m.PlayerUpgradePersistent = {
    [Id.PlayerUpgradePersistent.FIREPOWER_1] = {
        value = 1.1, -- %
        price = 50,
        currency = Id.CountablePersistent.COIN,
        name = "Firepower I",
        descr = string.format("+%d%% firepower", getValuePercent(1.1)),
    },
    [Id.PlayerUpgradePersistent.FIREPOWER_2] = {
        value = 1.2, -- %
        price = 120,
        currency = Id.CountablePersistent.COIN,
        name = "Firepower II",
        descr = string.format("+%d%% firepower", getValuePercent(1.2)),
    },
    [Id.PlayerUpgradePersistent.FIREPOWER_3] = {
        value = 1.3, -- %
        price = 250,
        currency = Id.CountablePersistent.COIN,
        name = "Firepower III",
        descr = string.format("+%d%% firepower", getValuePercent(1.3)),
    },
    [Id.PlayerUpgradePersistent.FIREPOWER_4] = {
        value = 1.4, -- %
        price = 500,
        currency = Id.CountablePersistent.COIN,
        name = "Firepower IV",
        descr = string.format("+%d%% firepower", getValuePercent(1.4)),
    },
    [Id.PlayerUpgradePersistent.FIREPOWER_5] = {
        value = 1.5, -- %
        price = 800,
        currency = Id.CountablePersistent.COIN,
        name = "Firepower V",
        descr = string.format("+%d%% firepower", getValuePercent(1.5)),
    },
    [Id.PlayerUpgradePersistent.HITPOINTS_1] = {
        value = 1.1, -- %
        price = 40,
        currency = Id.CountablePersistent.COIN,
        name = "Hitpoints I",
        descr = string.format("+%d%% hitpoints", getValuePercent(1.1)),
    },
    [Id.PlayerUpgradePersistent.HITPOINTS_2] = {
        value = 1.2, -- %
        price = 100,
        currency = Id.CountablePersistent.COIN,
        name = "Hitpoints II",
        descr = string.format("+%d%% hitpoints", getValuePercent(1.2)),
    },
    [Id.PlayerUpgradePersistent.HITPOINTS_3] = {
        value = 1.3, -- %
        price = 200,
        currency = Id.CountablePersistent.COIN,
        name = "Hitpoints III",
        descr = string.format("+%d%% hitpoints", getValuePercent(1.3)),
    },
    [Id.PlayerUpgradePersistent.HITPOINTS_4] = {
        value = 1.4, -- %
        price = 400,
        currency = Id.CountablePersistent.COIN,
        name = "Hitpoints IV",
        descr = string.format("+%d%% hitpoints", getValuePercent(1.4)),
    },
    [Id.PlayerUpgradePersistent.HITPOINTS_5] = {
        value = 1.5, -- %
        price = 700,
        currency = Id.CountablePersistent.COIN,
        name = "Hitpoints V",
        descr = string.format("+%d%% hitpoints", getValuePercent(1.5)),
    },
    [Id.PlayerUpgradePersistent.INIT_CLONE_1] = {
        value = 1, -- unit
        price = 100,
        currency = Id.CountablePersistent.COIN,
        name = "Clones I",
        descr = string.format("1 clone at the start"),
    },
    [Id.PlayerUpgradePersistent.INIT_CLONE_2] = {
        value = 2, -- unit
        price = 300,
        currency = Id.CountablePersistent.COIN,
        name = "Clones II",
        descr = string.format("2 clones at the start"),
    },
    [Id.PlayerUpgradePersistent.INIT_CLONE_3] = {
        value = 3, -- unit
        price = 600,
        currency = Id.CountablePersistent.COIN,
        name = "Clones III",
        descr = string.format("3 clones at the start"),
    },
    [Id.PlayerUpgradePersistent.XP_MULT] = {
        value = 1.1, -- %
        price = 100,
        currency = Id.CountablePersistent.COIN,
        name = "XP Multiplier",
        descr = string.format("+%d%% XP", getValuePercent(1.1)),
    },
}

m.PlayerUpgradeNonPersistent = {
    [Id.PlayerUpgradeNonPersistent.INVINCIBILITY] = {
        period = 2, -- sec
        maxStage = 0, 
        isRenewable = true,
        isLooped = false, -- is always active or not
        isExpirable = true,
        color = Color3.fromRGB(0, 255, 255),
    },
    [Id.PlayerUpgradeNonPersistent.FIREPOWER] = {
        period = 0xffff_ffff, 
        maxStage = 5, 
        isRenewable = false,
        isLooped = false,
        isExpirable = false,
        multiplier = .1, -- percent
        color = Color3.fromRGB(255, 0, 0),
    },
    [Id.PlayerUpgradeNonPersistent.SHIELD] = {
        period = 10,
        maxStage = 0,
        isRenewable = true,
        isLooped = false,
        isExpirable = true,
        hp = 80,
        color = Color3.fromRGB(171, 19, 163),
    },
    -- [Id.PlayerUpgradeNonPersistent.DRONES] = {
    --     ttl = 0,
    --     maxStage = 0,
    --     prerequisite = 0,
    -- },
    [Id.PlayerUpgradeNonPersistent.BULLET_SPEED_MULT] = {
        period = 0xffff_ffff,
        maxStage = 3,
        isRenewable = false,
        isLooped = false,
        isExpirable = false,
        multiplier = .1,
        color = Color3.fromRGB(0, 255, 0),
    },
    [Id.PlayerUpgradeNonPersistent.CLONE_FACTORY] = {
        -- + 1 for every stage every ttl seconds
        period = 10,
        maxStage = 3,
        isRenewable = false,
        isLooped = true,
        isExpirable = false,
        color = Color3.fromRGB(0, 0, 255),
    },
    [Id.PlayerUpgradeNonPersistent.SHIELD_RECHARGE] = {
        period = 10,
        maxStage = 0,
        isRenewable = false,
        isLooped = true,
        isExpirable = false,
        color = Color3.fromRGB(255, 165, 0),
    },
    [Id.PlayerUpgradeNonPersistent.SHIELD_DAMAGE] = {
        period = 0xffff_ffff,
        maxStage = 3,
        isRenewable = false,
        isLooped = false,
        isExpirable = false,
        damage = 5,
        color = Color3.fromRGB(255, 0, 0),
    },
    [Id.PlayerUpgradeNonPersistent.SHIELD_COOLDOWN_MULT] = {
        period = 0xffff_ffff,
        maxStage = 0,
        isRenewable = false,
        isLooped = false,
        isExpirable = false,
        multiplier = .5,
        color = Color3.fromRGB(255, 165, 0),
    },
    [Id.PlayerUpgradeNonPersistent.ARMOR] = {
        period = 0xffff_ffff,
        maxStage = 3,
        isRenewable = false,
        isLooped = false,
        isExpirable = false,
        multiplier = .9, -- 10% damage reduction
        color = Color3.fromRGB(220, 194, 1),
    },
}

m.Sound = {
    [Id.Sound.ARMOR_HIT] = assert(SOUNDS_ROOT:WaitForChild("ArmorImpact")),
    [Id.Sound.BELL] = assert(SOUNDS_ROOT:WaitForChild("Bell")),
    [Id.Sound.BELL_SUCCESS] = assert(SOUNDS_ROOT:WaitForChild("BellSuccess")),
    [Id.Sound.CLICK] = assert(SOUNDS_ROOT:WaitForChild("Click")),
    [Id.Sound.COIN_DROP] = assert(SOUNDS_ROOT:WaitForChild("CoinDrop")),
    [Id.Sound.CREAK_METAL] = assert(SOUNDS_ROOT:WaitForChild("CreakMetalHeavy")),
    [Id.Sound.CRYSTAL_DING] = assert(SOUNDS_ROOT:WaitForChild("CrystalDing")),
    [Id.Sound.ENERGY_SHIELD_HIT] = assert(SOUNDS_ROOT:WaitForChild("EnergyShieldHit")),
    [Id.Sound.ENERGY_SWEEP] = assert(SOUNDS_ROOT:WaitForChild("EnergySweep")),
    [Id.Sound.ERROR] = assert(SOUNDS_ROOT:WaitForChild("ErrorZap")),
    [Id.Sound.EXPLOSION_SHORT] = assert(SOUNDS_ROOT:WaitForChild("ExplosionShort")),
    [Id.Sound.FIRE_PISTOL] = assert(SOUNDS_ROOT:WaitForChild("Fired")),
    [Id.Sound.HISS] = assert(SOUNDS_ROOT:WaitForChild("Hiss")),
    [Id.Sound.HURT] = assert(SOUNDS_ROOT:WaitForChild("Hurt")),
    [Id.Sound.IMPACT] = assert(SOUNDS_ROOT:WaitForChild("Impact")),
    [Id.Sound.METAL_BUCKET] = assert(SOUNDS_ROOT:WaitForChild("MetalBucket")),
    [Id.Sound.POP] = assert(SOUNDS_ROOT:WaitForChild("Pop")),
    [Id.Sound.POP_LOW] = assert(SOUNDS_ROOT:WaitForChild("PopLow")),
    [Id.Sound.RELOAD_CLICK] = assert(SOUNDS_ROOT:WaitForChild("ReloadClick")),
    [Id.Sound.RELOAD_PISTOL] = assert(SOUNDS_ROOT:WaitForChild("ReloadPistol")),
    [Id.Sound.SCREAM] = assert(SOUNDS_ROOT:WaitForChild("Scream")),
    [Id.Sound.SCREAM_HIGH] = assert(SOUNDS_ROOT:WaitForChild("ScreamHigh")),
    [Id.Sound.THUMP] = assert(SOUNDS_ROOT:WaitForChild("Thump")),
    [Id.Sound.WEAK_BULLET] = assert(SOUNDS_ROOT:WaitForChild("WeakBullet")),
    [Id.Sound.WHEEL_SPIN] = assert(SOUNDS_ROOT:WaitForChild("WheelSpin")),
    -- localized sounds
    [Id.Sound.FIRE_PISTOL_LOCALIZED] = assert(LOCALIZED_SOUNDS_ROOT:WaitForChild("FiredOther")),
    [Id.Sound.EXPLOSION_SHORT_LOCALIZED] = assert(LOCALIZED_SOUNDS_ROOT:WaitForChild("ExplosionShort")),
    [Id.Sound.IMPACT_LOCALIZED] = assert(LOCALIZED_SOUNDS_ROOT:WaitForChild("Impact")),
    [Id.Sound.METAL_BUCKET_LOCALIZED] = assert(LOCALIZED_SOUNDS_ROOT:WaitForChild("MetalBucket")),
    [Id.Sound.POP_LOW_LOCALIZED] = assert(LOCALIZED_SOUNDS_ROOT:WaitForChild("PopLow")),
    [Id.Sound.RELOAD_CLICK_LOCALIZED] = assert(LOCALIZED_SOUNDS_ROOT:WaitForChild("ReloadClick")),
    [Id.Sound.SCREAM_LOCALIZED_HIGH] = assert(LOCALIZED_SOUNDS_ROOT:WaitForChild("ScreamHigh")),
    [Id.Sound.SCREAM_LOCALIZED_REG] = assert(LOCALIZED_SOUNDS_ROOT:WaitForChild("ScreamReg")),
    [Id.Sound.STOMP_LOCALIZED] = assert(LOCALIZED_SOUNDS_ROOT:WaitForChild("Stomp")),
    [Id.Sound.THUMP_LOCALIZED] = assert(LOCALIZED_SOUNDS_ROOT:WaitForChild("Thump")),
}

m.VFX = {
    [Id.VFX.INVINCIBILITY_AURA] = assert(VFX_ROOT:WaitForChild("InvinvibilityAuraTemplate")),
}

return m

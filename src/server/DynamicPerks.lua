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

local __DEV__ = not workspace or game:GetService("RunService"):IsStudio()

--[[ stylua: ignore]] if not game then(function() game = require("game") end)() end
local shared = game.ReplicatedStorage.shared
local server = game.ServerScriptService.server
local Id = require(shared.Id)
local Logger = require(shared.logger)
local log = Logger.create(script and script.Name or "GameModule"):set_prettifier(Id.pp):set_delimiter(" ")
local TaskPool = require(shared.TaskPool)
local PSS = require(server.PlayerStateService)
local Signal = require(shared.signal)
local En = require(shared.enum)
local Array = require(shared.array)
local _iota = En.iota
local _flag = En.flag
local disposer = require(shared.disposer)
local SharedConfig = require(shared.SharedConfig)
local W = SharedConfig.World.CId
local state = require(shared.state)
local roflake = require(shared.roflake)
local WorldService = require(server.WorldService)
local S = require(shared.StaticData)
local C = SharedConfig.PlayerState.CId
local Misc = require(shared.Misc)
local NumFormat = require(shared.num_format)
local SharedUtils = require(shared.util)
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Rand = require(shared.rand)
local _roflake = require(shared.roflake)
local Remote = require(shared.Remote)
local TweenService = game:GetService("TweenService")
local Players = game:GetService("Players")

local isMax = function(playerState: PSS.PlayerState, perkId: id)
    local perkStage = playerState.state:get(perkId, C.ValueNonPers)
    if perkStage < S.PlayerUpgradeNonPersistent[perkId].maxStage then
        return false
    end
    return true
end

-- NOTE: Shield should not be suggested after shield recharge is purchased
local function selectPerks(playerState: PSS.PlayerState)
    local selectedPerks = Vector3.new(0, 0, 0)
    -- if shield is not yet selected, suggest it and nothing more
    local shieldFlags = playerState.state:get(Id.PlayerUpgradeNonPersistent.SHIELD, C.Bitset)
    local isShieldAlreadySelected = Id.flag_test(shieldFlags, Id.PlayerF.PERK_ACQUIRED)
    if not isShieldAlreadySelected then
        selectedPerks = Vector3.new(Id.PlayerUpgradeNonPersistent.SHIELD, 0, 0)
        return selectedPerks
    end

    -- if shield is already acquired, suggest a choice of 2 perks

    -- default pool
    local pool = {}

    -- insert non-maxed perks
    for _, perkId in
        {
            Id.PlayerUpgradeNonPersistent.FIREPOWER,
            Id.PlayerUpgradeNonPersistent.SHIELD_RECHARGE,
            Id.PlayerUpgradeNonPersistent.BULLET_SPEED_MULT,
            Id.PlayerUpgradeNonPersistent.CLONE_FACTORY,
        }
    do
        if not isMax(playerState, perkId) or S.PlayerUpgradeNonPersistent[perkId].isRenewable then
            table.insert(pool, perkId)
        end
    end

    local shieldRechargeFlags = playerState.state:get(Id.PlayerUpgradeNonPersistent.SHIELD, C.Bitset)
    local isShieldRechargable = Id.flag_test(shieldRechargeFlags, Id.PlayerF.PERK_ACQUIRED)

    local shieldDamageFlags = playerState.state:get(Id.PlayerUpgradeNonPersistent.SHIELD, C.Bitset)

    -- add shield to the pool, if shield is not rechargeable yet
    if not isShieldRechargable then
        table.insert(pool, Id.PlayerUpgradeNonPersistent.SHIELD)
    end

    -- add invincibility to the pool, if shield is not rechargeable yet
    if not isShieldRechargable then
        table.insert(pool, Id.PlayerUpgradeNonPersistent.INVINCIBILITY)
    end

    local perk1 = pool[math.random(1, #pool)]
    local perk2 = pool[math.random(1, #pool)]
    local attempts = 0
    while perk1 == perk2 do
        if attempts > 10 then
            -- if there is nothing to choose from, set the second perk to 0
            perk2 = 0
            break
        end
        -- reroll the second perk if it's the same as the first
        perk2 = pool[math.random(1, #pool)]
        while perk1 == Id.PlayerUpgradeNonPersistent.SHIELD_RECHARGE and perk2 == Id.PlayerUpgradeNonPersistent.SHIELD do
            -- reroll the second perk if it is shield, and shield_recharge has been already selected as the 1st perk
            perk2 = pool[math.random(1, #pool)]
        end
        attempts = attempts + 1
    end

    selectedPerks = Vector3.new(perk1, perk2, 0)
    return selectedPerks
end

local m = {}

return m

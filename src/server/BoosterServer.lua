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

local m = {}

m.BOOSTER_DATA_TABLE = {
    {
        boost_gacha = { [Id.Boost.ADD_CLONE] = 65, [Id.Boost.CHANGE_WEAPON] = 35 },
        weapon_gacha = { [Id.Weapon.SMG] = 55, [Id.Weapon.SPRAYGUN] = 40, [Id.Weapon.ROCKET] = 5 },
    },
    {
        boost_gacha = { [Id.Boost.ADD_CLONE] = 50, [Id.Boost.CHANGE_WEAPON] = 35, [Id.Boost.FIRST_AID_KIT] = 15 },
        weapon_gacha = { [Id.Weapon.SMG] = 55, [Id.Weapon.SPRAYGUN] = 40, [Id.Weapon.ROCKET] = 5 },
    },
}

function m.SetBoosterValue(worldState: state.Main)
    local boosterRefId = Id.Boost.ADD_CLONE
    local weaponRefId = Id.Weapon.BASIC
    local wavesTotal = worldState:get(Id.WorldSpecs.BOOST_WAVE_COUNT, W.Value) or 1 -- default value is for the first booster wave

    if wavesTotal > #m.BOOSTER_DATA_TABLE then
        wavesTotal = #m.BOOSTER_DATA_TABLE
    end

    -- define booster id
    local boostGacha = m.BOOSTER_DATA_TABLE[wavesTotal].boost_gacha
    boosterRefId = Rand.weighted_choice(boostGacha)
    if boosterRefId == Id.Boost.CHANGE_WEAPON then
        -- define weapon id
        local weaponGacha = m.BOOSTER_DATA_TABLE[wavesTotal].weapon_gacha
        weaponRefId = Rand.weighted_choice(weaponGacha)
    end

    return boosterRefId, weaponRefId
end

function m.GetCurrentBoosterHpMult(worldState: state.Main)
    local currentBoosterWaveNum = worldState:get(Id.WorldSpecs.BOOST_WAVE_COUNT, W.Value) or 0
    if currentBoosterWaveNum > #m.BOOSTER_DATA_TABLE then
        currentBoosterWaveNum = #m.BOOSTER_DATA_TABLE
    end
    local mult = 1 + .1 * currentBoosterWaveNum
    return mult
end

return m
-- TODO: clone bosster hp should be dependent on the number of clones
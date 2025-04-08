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
local BASE_HP_MULT = 0.1
local workerMaid = disposer.new()

local m = {}

-- TODO: others
m.BOOSTER_DATA_TABLE = {
    {
        boost_gacha = { [Id.Boost.ADD_CLONE] = 65, [Id.Boost.CHANGE_WEAPON] = 35 },
        weapon_gacha = { [Id.Weapon.SMG] = 55, [Id.Weapon.SPRAYGUN] = 40, [Id.Weapon.ROCKET] = 5 },
    },
    {
        boost_gacha = { [Id.Boost.ADD_CLONE] = 55, [Id.Boost.CHANGE_WEAPON] = 35, [Id.Boost.FIRST_AID_KIT] = 10 },
        weapon_gacha = { [Id.Weapon.SMG] = 55, [Id.Weapon.SPRAYGUN] = 40, [Id.Weapon.ROCKET] = 5 },
    },
}

m.SubscribeBooster = function(worldState: state.Main, get_state: (int) -> PSS.PlayerState?, instanceGuid: string, refId: id, instance: BasePart)
    workerMaid[instanceGuid] = instance.Touched:Connect(function(triggerer)
        if triggerer.Name ~= "HumanoidRootPart" then
            return
        end

        local character = assert(triggerer.Parent)
        assert(character:IsA("Model")) -- sanity check
        if not worldState then
            return
        end

        if not worldState:has(instanceGuid) then
            log:error("worldState is nil for this guid %s", instanceGuid)
            return
        end

        local player = game:GetService("Players"):GetPlayerFromCharacter(character)
        if not player then
            return
        end
        local playerId = player.UserId
        local playerState = get_state(playerId)
        if not playerState then
            return
        end

        local flags = playerState.state:get(instanceGuid, C.BitsetNonPers)
        if Id.flag_test(flags, Id.PlayerF.BOOSTER_TOUCHED) then
            return
        end

        -- player collided with the booster for the first time, set the flag for the check above
        playerState.state:set(instanceGuid, flags, Id.flag_set(flags, Id.PlayerF.BOOSTER_TOUCHED, true))
    end)
end

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
    local mult = 1 + BASE_HP_MULT * currentBoosterWaveNum
    return mult
end

function m.DeleteBooster(worldState: state.Main, instanceGuid: string, get_state: (int) -> PSS.PlayerState?)
    if worldState:has(instanceGuid) then
        WorldService.RemoveEntity(instanceGuid)
    end
    local players = game:GetService("Players")
    for _, player in ipairs(players:GetPlayers()) do
    local playerId = player.UserId
    local playerState = get_state(playerId)
        if not playerState then
            continue
        end
        if playerState.state:has(instanceGuid) then
            playerState.state:delete(instanceGuid)
        end
    end
    if workerMaid[instanceGuid] then
        workerMaid[instanceGuid] = nil
    end
end

return m
-- TODO: clone booster hp should be dependent on the number of clones

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
local Logger = require(shared.logger)
local log = Logger.create(script and script.Name or "Boosters"):set_prettifier(Id.pp):set_delimiter(" ")
local Signal = require(shared.signal)
local En = require(shared.enum)
local _iota = En.iota
local _flag = En.flag
local disposer = require(shared.disposer)
local state = require(shared.state)
local SharedConfig = require(shared.SharedConfig)
local C = SharedConfig.PlayerState.CId
local W = SharedConfig.World.CId
local SharedConfig = require(shared.SharedConfig)
local GROUND_UNITS_FOLDER = assert(workspace.GroundUnits)
local workerMaid = disposer.new()
local LOCAL_PLAYER = game.Players.LocalPlayer
local PlayerService = game:GetService("Players")
local Misc = require(shared.Misc)
local S = require(shared.StaticData)
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local PLAYER_GUI = assert(LOCAL_PLAYER:WaitForChild("PlayerGui"))
local START_GUI = PLAYER_GUI:WaitForChild("StartSessionGUI")
local PLAYER_HP_GUI = assert(PLAYER_GUI.PlayerHpGui)
local PLAYER_HP_TEXT_BOX = assert(PLAYER_HP_GUI.TextLabel)

local function onBoosterAdded(worldState, playerState: state.Replica, boosterGuid)
    local instance = workspace:FindFirstChild(boosterGuid, true)
    workerMaid[boosterGuid] = instance.Touched:Connect(function(triggerer)
        if triggerer.Name ~= "HumanoidRootPart" then
            return
        end

        local character = triggerer.Parent
        assert(character:IsA("Model")) -- sanity check
        -- check if this player already collided with this booster.
        if not playerState then
            return
        end
        if not playerState:has(boosterGuid) then
            log:error("playerState is nil for booster %s", boosterGuid)
            return
        end
        -- if the player already collided with this booster, do nothing
        if playerState:get(boosterGuid, C.ClientFlags) then
            return
        end

        -- local player has not yet collided with this booster, do the checks
        local triggererId
        if character.Parent.Name == SharedConfig.CLONES_FOLDER_NAME then
            -- player's clone collided with the booster, check if it the local player's clone
            Misc.SoundLocalizedAudio(S.Sound[Id.Sound.SCREAM_LOCALIZED], triggerer.Position, 0)
            character:Destroy()
        elseif PlayerService:GetPlayerFromCharacter(character) == LOCAL_PLAYER then
            -- player themselves collided with the booster
            triggererId = LOCAL_PLAYER.UserId
            S.Sound[Id.Sound.SCREAM]:Play()
        end

        if triggererId then
            -- local player has collided with this booster for the first time, set it to the state
            playerState:set(boosterGuid, C.ClientFlags, true)
            Signal.Fire(Id.C2S.PLAYER_COLLIDED_W_BOOSTER, boosterGuid, triggererId)
            local playerHP = playerState:get(Id.PlayerStats.GAME_SESSION, C.Value)
            local boosterHP = worldState:get(boosterGuid, W.HP)
            local remainingHP = playerHP - boosterHP
            if remainingHP > 0 then
                Misc.FlickerPlayerHPGui(PLAYER_HP_TEXT_BOX, 1.5, -boosterHP)
                -- TODO: pain animation
            end
        end
    end)
end

local m = {}

workerMaid.sub = Signal.Connect(Id.C2C.NEW_BOOSTER_ADDED, onBoosterAdded)

return m

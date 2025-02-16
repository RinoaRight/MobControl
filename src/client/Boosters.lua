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
local SFX = require(script.Parent.SFX)

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
        local isClone, playerId = Misc.CloneOrLocalPlayer(worldState, character)
        if playerId and playerId == LOCAL_PLAYER.UserId then
            if isClone then
                -- player's clone collided with the booster
                Misc.DestroyClientClone(character)
                triggererId = character.Name
            else
                -- player themselves collided with the booster for the first time, set the flag for the check above
                playerState:set(boosterGuid, C.ClientFlags, true)
                triggererId = LOCAL_PLAYER.UserId
                -- NOTE: legacy. Audio is played in on_Player_damaged
                -- local audio = S.Sound[Id.Sound.SCREAM]
                -- if audio then
                --     SFX.PLAY_SOUND(audio)
                -- end
            end
            Signal.Fire(Id.C2S.PLAYER_COLLIDED_W_BOOSTER, boosterGuid, triggererId)
        end

        if triggererId then
        end
    end)
end

local m = {}

workerMaid.sub = Signal.Connect(Id.C2C.NEW_BOOSTER_ADDED, onBoosterAdded)

return m

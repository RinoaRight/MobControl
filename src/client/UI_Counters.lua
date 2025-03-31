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
local NumFormat = require(shared.num_format)
local SharedConfig = require(shared.SharedConfig)
local GROUND_UNITS_FOLDER = assert(workspace.GroundUnits)
local LOCAL_PLAYER = game.Players.LocalPlayer
local PlayerService = game:GetService("Players")
local Misc = require(shared.Misc)
local Sounds = require(script.Parent.SFX)
local S = require(shared.StaticData)
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local COIN_TEXTBOX
local COIN_IMG

local _maid = disposer.new()

local DEFAULT_SCALE_MONEY_TEXTBOX = UDim2.fromScale(1, 1)
local DEFAULT_SCALE_MONEY_IMG = UDim2.fromScale(.7, .7)
local TARGET_SCALE = UDim2.fromScale(DEFAULT_SCALE_MONEY_TEXTBOX.X.Scale, DEFAULT_SCALE_MONEY_TEXTBOX.Y.Scale * 1.5)

local m = {}
m.__index = m

m.Init = function(playerState: state.Replica, guiPanel)
    local coinFrame = assert(guiPanel:WaitForChild("MoneyFrame"))
    COIN_TEXTBOX = assert(coinFrame.BG.TextLabel)
    COIN_IMG = assert(coinFrame.MoneyIcon)
    local coinsValue = playerState:get(Id.Countable.COIN, C.Value)
    COIN_TEXTBOX.Text = NumFormat.format_ectos(coinsValue)

    for _, refId in Id.Countable:ids() do
        local currentValue = playerState:get(refId, C.Value)
        playerState:set(refId, C.ValueView, currentValue)
    end
end

m.OnStateUpdate = function(playerState: state.Replica)
    for _, refId in Id.Countable:ids() do
        local valueView = playerState:get(refId, C.ValueView)
        local value = playerState:get(refId, C.Value)

        if value == valueView then
            continue
        elseif value > valueView then
            if refId == Id.Countable.COIN then
                Sounds.PLAY_SOUND(Id.Sound.COIN_DROP)
            end
        elseif value < valueView then
            Sounds.PLAY_SOUND(Id.Sound.BELL)
        end

        -- flicker textbox's scale
        local currency = Id.name(refId)
        if not _maid[currency] and value ~= valueView then
            _maid[currency] = task.spawn(function()
                COIN_TEXTBOX:TweenSize(TARGET_SCALE, Enum.EasingDirection.In, Enum.EasingStyle.Sine, 0.1)
                COIN_IMG:TweenSize(TARGET_SCALE, Enum.EasingDirection.In, Enum.EasingStyle.Sine, 0.1)
                task.wait(0.15)
                COIN_TEXTBOX:TweenSize(DEFAULT_SCALE_MONEY_TEXTBOX, Enum.EasingDirection.In, Enum.EasingStyle.Sine, 0.1)
                COIN_IMG:TweenSize(DEFAULT_SCALE_MONEY_IMG, Enum.EasingDirection.In, Enum.EasingStyle.Sine, 0.1)
                task.wait(0.15)
                _maid[currency] = nil
            end)
        end

        COIN_TEXTBOX.Text = NumFormat.format_ectos(value)

        playerState:set(refId, C.ValueView, value)
    end
end
return m

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
local TweenService = game:GetService("TweenService")
local TaskPool = require(shared.TaskPool)

local m = {}

m.OnPlayerConnected = function(handicapTextBox, activeHandicap: id)
    handicapTextBox.Text = string.upper(S.Handicap[activeHandicap].name)
end

m.OnHandicapModified = function(handicapGui: ScreenGui, handicapTextBox, activeHandicap: id)
    -- if handicap is set to none, clear the text box
    if not activeHandicap or activeHandicap == Id.Handicap._NONE then
        handicapTextBox.Text = " "
        return
    end

-- TODO: animate bigger

    -- if the handicap was just set, play animation
    local parentPanel = handicapGui:WaitForChild("TopRightPanel"):WaitForChild("HandicapFrame")
    local textBoxTemplate = parentPanel:WaitForChild("TextLabel") :: TextLabel
    local allEntriesTable = S.Handicap
    local orderedArrayOfTextBoxes = {}
    local orderedArrayOfTweens = {}
    for id, data in allEntriesTable do
        local textBox = textBoxTemplate:Clone()
        textBox.Name = data.name
        textBox.Text = string.upper(data.name)
        textBox.Parent = parentPanel
        textBox.Position = UDim2.fromScale(0, -0.5)
        local tweenInfo = TweenInfo.new(0.2, Enum.EasingStyle.Linear, Enum.EasingDirection.InOut)
        local tween
        if id == activeHandicap then
            tween = TweenService:Create(textBox, tweenInfo, { Position = UDim2.fromScale(0, 0.5) })
            table.insert(orderedArrayOfTextBoxes, 1, textBox)
            table.insert(orderedArrayOfTweens, 1, tween)
        else
            tween = TweenService:Create(textBox, tweenInfo, { Position = UDim2.fromScale(0, 1.5) })
            table.insert(orderedArrayOfTextBoxes, textBox)
            table.insert(orderedArrayOfTweens, tween)
        end
    end
    TaskPool.spawn(function()
        for i = #orderedArrayOfTweens, 1, -1 do
            local t = orderedArrayOfTweens[i]
            t:Play()
            t.Completed:Wait()
            if i == 1 then
                -- show text of the active handicap in the permanent text box, destroy the animated text boxes
                handicapTextBox.Text = string.upper(S.Handicap[activeHandicap].name)
            end
            orderedArrayOfTextBoxes[i]:Destroy()
        end
    end)
end

return m

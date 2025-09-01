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

local GUI_START_POS
local GUI_TARGET_POS = UDim2.new(0.99, 0, 0.03, 0)
local GUI_START_SCALE = UDim2.new(0.64, 0, 0.64, 0)
local GUI_TARGET_SCALE = UDim2.new(0.45, 0, 0.45, 0)
local ROTATING_SLOT_START_POS = UDim2.fromScale(0.5, -0.5)
local ROTATING_SLOT_CENTER_POS = UDim2.fromScale(0.5, 0.5)
local ROTATING_SLOT_BOTTOM_POS = UDim2.fromScale(0.5, 1.5)
local HANDICAP_GUI_PARENT_PANEL
local HANDICAP_GUI_MAIN_FRAME
local HANDICAP_GUI_TEXT_FRAME
local HANDICAP_INCRIPTION_TEXT_LABEL

local m = {}

m.Init = function(worldState: state.Replica, playerState: state.Replica, mainGui: ScreenGui)
    local activeHandicap = worldState:get(Id.WorldSpecs.HANDICAP, W.Value) :: id
    -- initialize slots
    HANDICAP_GUI_PARENT_PANEL = mainGui:WaitForChild("TopRightPanel") :: Frame
    HANDICAP_GUI_MAIN_FRAME = HANDICAP_GUI_PARENT_PANEL:WaitForChild("HandicapFrame")
    HANDICAP_GUI_TEXT_FRAME = HANDICAP_GUI_MAIN_FRAME:WaitForChild("TextFrame") :: Frame
    HANDICAP_INCRIPTION_TEXT_LABEL = HANDICAP_GUI_TEXT_FRAME:WaitForChild("Handicap") :: Frame
    -- local animGuiBorder = anumGuiMainFrame:WaitForChild("Border") :: Frame
    local allEntriesTable = S.Handicap
    local textBoxTemplate = assert(HANDICAP_GUI_TEXT_FRAME:WaitForChild("TextLabel")) :: TextLabel
    for handicapId, data in allEntriesTable do
        local textBox = textBoxTemplate:Clone()
        textBox.Name = data.name
        if data.color then
            textBox.TextColor3 = data.color
        end
        textBox.Text = string.upper(data.name)
        textBox.Parent = HANDICAP_GUI_TEXT_FRAME
        local pos = ROTATING_SLOT_START_POS
        if activeHandicap and activeHandicap ~= Id.Handicap._NONE then
            pos = ROTATING_SLOT_CENTER_POS
        end
        textBox.Position = pos
        local _handicap = playerState:constructor(C.Instance)
        _handicap(handicapId, textBox)
        playerState:set(handicapId, C.Instance, textBox)
    end
end

m.OnHandicapModified = function(playerState: state.Replica, mainGui: ScreenGui, activeHandicapId: id)
    -- handicap is set to none, reset the slot's position
    if not activeHandicapId or activeHandicapId == Id.Handicap._NONE then
        local allSlots = HANDICAP_GUI_TEXT_FRAME:GetChildren()
        for _, slot in ipairs(allSlots) do
            if slot:IsA("TextLabel") then
                slot.Position = ROTATING_SLOT_START_POS
            end
        end
        HANDICAP_INCRIPTION_TEXT_LABEL.Position = ROTATING_SLOT_CENTER_POS
        HANDICAP_INCRIPTION_TEXT_LABEL.Visible = true
        return
    end

    -- if the handicap was just set, play animation
    -- local animGuiParentPanel = mainGui:WaitForChild("TopRightPanel") :: Frame
    -- local anumGuiMainFrame = animGuiParentPanel:WaitForChild("HandicapFrame")
    -- local animGuiTextFrame = anumGuiMainFrame:WaitForChild("TextFrame") :: Frame
    -- local animGuiBorder = anumGuiMainFrame:WaitForChild("Border") :: Frame

    -- animGuiParentPanel.Size = GUI_START_SCALE
    -- local objAbsSize = animGuiParentPanel.AbsoluteSize
    -- -- since the anchor point is (1,0) we need to recenter the panel
    -- GUI_START_POS = UDim2.new(0.5, objAbsSize.X / 2, 0.8, 0)
    -- local textBoxTemplate = animGuiTextFrame:WaitForChild("TextLabel") :: TextLabel
    -- animGuiParentPanel.Position = GUI_START_POS

    -- if handicap is being set, show animation
    HANDICAP_INCRIPTION_TEXT_LABEL.Visible = false
    local allEntriesTable = S.Handicap
    local orderedArrayOfTextBoxes = {}
    for id, data in allEntriesTable do
        local textBox = assert(playerState:get(id :: num, C.Instance))
        if id == activeHandicapId then
            table.insert(orderedArrayOfTextBoxes, 1, textBox)
        else
            table.insert(orderedArrayOfTextBoxes, textBox)
        end
    end
    TaskPool.spawn(function()
        local durFast = 0.3
        local durSlow = 0.4
        local sound = S.Sound[Id.Sound.WHEEL_SPIN]
        local soundDur = math.floor(sound.TimeLength * 10) / 10 -- currently == 5.2
        local howMany = math.floor((soundDur - durSlow * #orderedArrayOfTextBoxes) / durFast / #orderedArrayOfTextBoxes)
        if howMany < 1 then
            howMany = 1
        end

        Misc.PlaySound(Id.Sound.WHEEL_SPIN)

        -- animGuiBorder.Visible = true

        for rollCount = 1, howMany do
            for slotIndex = #orderedArrayOfTextBoxes, 1, -1 do
                local currentDur = 0
                if rollCount < howMany then
                    currentDur = durFast
                else
                    currentDur = durSlow
                end

                local tweenInfo = TweenInfo.new(currentDur, Enum.EasingStyle.Linear, Enum.EasingDirection.InOut)

                -- define tween for non-final position
                local tween = TweenService:Create(orderedArrayOfTextBoxes[slotIndex], tweenInfo, { Position = ROTATING_SLOT_BOTTOM_POS })
                if slotIndex == 1 and rollCount == howMany then
                    -- define tween for final position
                    tween = TweenService:Create(orderedArrayOfTextBoxes[slotIndex], tweenInfo, { Position = ROTATING_SLOT_CENTER_POS })
                end

                tween:Play()
                tween.Completed:Wait()

                if rollCount < howMany then
                    -- the roll is yet to be repeated, move slot back to starting pos
                    orderedArrayOfTextBoxes[slotIndex].Position = ROTATING_SLOT_START_POS
                else
                    if slotIndex ~= 1 then
                        -- the roll is over, move all except the active to starting pos
                        orderedArrayOfTextBoxes[slotIndex].Position = ROTATING_SLOT_START_POS

                        -- the roll is over, finalize animation
                        -- if slotIndex == 1 then
                        -- animGuiBorder.Visible = false
                        -- local finalTweenInfo = TweenInfo.new(0.6, Enum.EasingStyle.Linear, Enum.EasingDirection.InOut)
                        -- local finalTween =
                        --     TweenService:Create(animGuiParentPanel, finalTweenInfo, { Position = GUI_TARGET_POS, Size = GUI_TARGET_SCALE })
                        -- finalTween:Play()
                        -- finalTween.Completed:Wait()
                        -- show text of the active handicap in the permanent text box
                        -- m.OnPlayerConnected(handicapPermTextBox, activeHandicap)
                        -- reset the panel
                        -- animGuiParentPanel.Position = GUI_START_POS
                        -- animGuiParentPanel.Size = GUI_START_SCALE
                        -- end
                        -- destroy the slot that has been already shown
                        -- orderedArrayOfTextBoxes[slotIndex]:Destroy()
                    end
                end
            end
        end
    end)
end

return m

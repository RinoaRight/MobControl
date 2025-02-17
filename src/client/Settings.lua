type str = string
type bool = boolean
type num = number
type integer = num
type uint = integer
type int = integer
type id = int
type ulid = str
type guid = id | ulid
type u32 = uint
type i32 = int
type u8 = uint
type array<a> = { a }
type table = { [any]: any }
type map<k, v> = { [k]: v }
type fun = (...any) -> ...any

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local shared = ReplicatedStorage.shared
local Disposer = require(shared.disposer)
local Signal = require(shared.signal)
local Id = require(shared.Id)
local S = require(shared.StaticData)
local SFX = require(script.Parent.SFX)
local SharedConfig = require(shared.SharedConfig)
local C = SharedConfig.PlayerState.CId
local SharedUtils = require(shared.util)
local state = require(shared.state)
local UserInputService = game:GetService("UserInputService")
local Misc = require(shared.Misc)
local TaskPool = require(shared.TaskPool)
local TweenService = game:GetService("TweenService")

-- local _state
local _maid = Disposer.new(script)
local _tempMaid = Disposer.new(script)

-- Settings Button GUI elements
local SETTINGS_BTN_GUI
local GEAR_RIM
local GEAR_BUTTON
-- Settings Menu GUI elements
local SETTINGS_MENU_GUI
local SETTINGS_CONTAINER
local BULLETS_BTN
local BULLETS_BTN_BG
local BULLETS_TEXT_BOX
local CLONES_BTN
local CLONES_BTN_BG
local CLONES_TEXT_BOX
local GEAR_TRANSPARENCY_UNHOVER = 0.3
local GEAR_TRANSPARENCY_HOVER = 0

local SETTINGS_MENU_POS_HIDDEN = UDim2.fromScale(0.5, -1)
local SETTINGS_MENU_POS_REVEALED = UDim2.fromScale(0.5, 0)

local COLOR_OFF_BG = Color3.fromHex("ff5500")
local COLOR_OFF_TXT = Color3.fromHex("216c6c")
local COLOR_ON_BG = Color3.fromHex("4ee726")
local COLOR_ON_TXT = Color3.fromHex("38b4b6")
local COLOR_STROKE_OFF = Color3.fromHex("ff8686")

-----------------------------
-- Music and Sounds
-----------------------------
local function updateOnOffButton(btn, isToTurnOn)
    local textbox = assert(btn.Parent.TextLabel) :: TextLabel
    local bg = assert(btn.Parent.BG) :: GuiObject
    local textStroke = assert(textbox:FindFirstChild("UIStroke")) :: UIStroke

    if isToTurnOn then
        bg.BackgroundColor3 = COLOR_ON_BG
        textbox.TextColor3 = COLOR_ON_TXT
        textbox.Text = "ON"
        textStroke.Color = COLOR_OFF_TXT
    else
        bg.BackgroundColor3 = COLOR_OFF_BG
        textbox.TextColor3 = COLOR_OFF_TXT
        textbox.Text = "OFF"
        textStroke.Color = COLOR_STROKE_OFF
    end
end

local function onMenuBtnPressed(playerState, btn: any)
    local audio = S.Sound[Id.Sound.CLICK]
    if audio then
        SFX.PLAY_SOUND(audio)
    end
    local currentFlags = playerState:get(Id.PlayerStats.GAME_SESSION, C.Bitset)
    if not currentFlags then
        return
    end

    if btn == BULLETS_BTN then
        local statId = Id.PlayerF.OTHER_BULLETS_ON
        local bulletsFlag = Id.flag_test(currentFlags, Id.PlayerF.OTHER_BULLETS_ON)
        Signal.Broadcast(Id.C2S.TOGGLE_PLAYER_FLAG, not bulletsFlag, statId)
        updateOnOffButton(btn, not currentFlags)
    elseif btn == CLONES_BTN then
        local statId = Id.PlayerF.OTHER_CLONES_ON
        local clonesFlag = Id.flag_test(currentFlags, Id.PlayerF.OTHER_CLONES_ON)
        Signal.Broadcast(Id.C2S.TOGGLE_PLAYER_FLAG, not clonesFlag, statId)
        Signal.Broadcast(Id.C2C.SHOW_CLONES_TOGGLED, not clonesFlag)
        updateOnOffButton(btn, not currentFlags)
    end
end

local function toggleGearTransparency(isHovered: boolean)
    local t
    if isHovered then
        t = GEAR_TRANSPARENCY_HOVER
        if _maid.hover then
            _maid.hover = nil
        end
        _maid.unhover = SharedUtils.ConnectThrottled(GEAR_BUTTON.MouseLeave, 0.5, function()
            toggleGearTransparency(false)
        end)
    else
        if _maid.unhover then
            _maid.unhover = nil
        end
        _maid.hover = SharedUtils.ConnectThrottled(GEAR_BUTTON.MouseEnter, 0.5, function()
            toggleGearTransparency(true)
        end)
        t = GEAR_TRANSPARENCY_UNHOVER
    end
    GEAR_BUTTON.ImageTransparency = t
end

local function initBtnAppearances(playerState: state.Replica)
    local currentFlags = playerState:get(Id.PlayerStats.GAME_SESSION, C.Bitset)
    if not currentFlags then
        return
    end
    local bulletsFlag = Id.flag_test(currentFlags, Id.PlayerF.OTHER_BULLETS_ON)
    updateOnOffButton(BULLETS_BTN, bulletsFlag)
    local clonesFlag = Id.flag_test(currentFlags, Id.PlayerF.OTHER_CLONES_ON)
    updateOnOffButton(CLONES_BTN, clonesFlag)
end

local function onExit()
    local tweenTimeUp = 0.5
    local tweenUpInfo = TweenInfo.new(tweenTimeUp, Enum.EasingStyle.Quart, Enum.EasingDirection.In)
    local tweenUp = TweenService:Create(SETTINGS_CONTAINER, tweenUpInfo, { Position = SETTINGS_MENU_POS_HIDDEN })
    TaskPool.spawn(function()
        tweenUp:Play()
        task.wait(tweenTimeUp + 0.1)
        _tempMaid:Destroy()
        SETTINGS_MENU_GUI.Enabled = false
        SETTINGS_BTN_GUI.Visible = true
    end)
end

local function onEnter(playerState: state.Replica, playerGui)
    initBtnAppearances(playerState)

    SETTINGS_BTN_GUI.Visible = false
    SETTINGS_MENU_GUI.Enabled = true
    toggleGearTransparency(false)
    _tempMaid.waitingForExit = UserInputService.InputBegan:Connect(function(input, gameProcessed)
        Misc.OnUIElementNotClickedDo(input, playerGui, SETTINGS_CONTAINER.SettingsPanel, onExit)
    end)
    _tempMaid.musicBtn = SharedUtils.ConnectThrottled(BULLETS_BTN.Activated, 0.3, function()
        onMenuBtnPressed(playerState, BULLETS_BTN)
    end)
    _tempMaid.soundsBtn = SharedUtils.ConnectThrottled(CLONES_BTN.Activated, 0.3, function()
        onMenuBtnPressed(playerState, CLONES_BTN)
    end)
    local tweenTimeDown = 1.2
    local tweenDownInfo = TweenInfo.new(tweenTimeDown, Enum.EasingStyle.Elastic, Enum.EasingDirection.Out)
    local tweenDown = TweenService:Create(SETTINGS_CONTAINER, tweenDownInfo, { Position = SETTINGS_MENU_POS_REVEALED })
    TaskPool.spawn(function()
        tweenDown:Play()
        task.wait(tweenTimeDown)
    end)
end

local m = {}
-----------------------------
-- Module
-----------------------------
function m.Init(state: state.Replica, playerGui: StarterGui, settingsBtnGUI: ScreenGui, settingsMenuGUI: ScreenGui)
    SETTINGS_BTN_GUI = assert(settingsBtnGUI) :: any
    SETTINGS_MENU_GUI = assert(settingsMenuGUI) :: any

    GEAR_RIM = assert(SETTINGS_BTN_GUI.Rim)
    GEAR_BUTTON = assert(GEAR_RIM.GearButton)
    SETTINGS_CONTAINER = assert(SETTINGS_MENU_GUI.ContainerFrame)
    local bulletsSlot = assert(SETTINGS_CONTAINER:FindFirstChild("1", true))
    BULLETS_BTN = assert(bulletsSlot.InfoFrame.ToggleButtonFrame.TextButton)
    local clonesSlot = assert(SETTINGS_CONTAINER:FindFirstChild("2", true))
    CLONES_BTN = assert(clonesSlot.InfoFrame.ToggleButtonFrame.TextButton)

    SETTINGS_CONTAINER.Position = SETTINGS_MENU_POS_HIDDEN
    SETTINGS_MENU_GUI.Enabled = false

    _maid.hover = SharedUtils.ConnectThrottled(GEAR_BUTTON.MouseEnter, 0.5, function()
        toggleGearTransparency(true)
    end)

    _maid.gearBtn = SharedUtils.ConnectThrottled(GEAR_BUTTON.Activated, 0.5, function()
        local audio = S.Sound[Id.Sound.CLICK]
        if audio then
            SFX.PLAY_SOUND(audio)
        end
        onEnter(state, playerGui)
    end)
end

return m

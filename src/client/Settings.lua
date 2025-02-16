-- type str = string
-- type bool = boolean
-- type num = number
-- type integer = num
-- type uint = integer
-- type int = integer
-- type id = int
-- type ulid = str
-- type guid = id | ulid
-- type u32 = uint
-- type i32 = int
-- type u8 = uint
-- type array<a> = { a }
-- type table = { [any]: any }
-- type map<k, v> = { [k]: v }
-- type fun = (...any) -> ...any

-- local ReplicatedStorage = game:GetService("ReplicatedStorage")
-- local shared = ReplicatedStorage.shared
-- local Disposer = require(shared.disposer)
-- local Signal = require(shared.signal)
-- local Id = require(shared.Id)
-- local S = require(shared.StaticData)
-- local SFX = require(script.Parent.SFX)
-- local SharedConfig = require(shared.SharedConfig)
-- local C = SharedConfig.PlayerState.CId
-- local SharedUtils = require(shared.util)

-- -- local _state
-- local _maid = Disposer.new(script)
-- local _tempMaid = Disposer.new(script)

-- -- Settings Button GUI elements
-- local SETTINGS_BTN_GUI
-- local GEAR_RIM
-- local GEAR_BUTTON
-- -- Settings Menu GUI elements
-- local SETTINGS_MENU_GUI
-- local SETTINGS_CONTAINER
-- local BULLETS_BTN
-- local BULLETS_BTN_BG
-- local BULLETS_TEXT_BOX
-- local CLONES_BTN
-- local CLONES_BTN_BG
-- local CLONES_TEXT_BOX

-- local GEAR_TRANSPARENCY_UNHOVER = 0.3
-- local GEAR_TRANSPARENCY_HOVER = 0

-- local SETTINGS_MENU_POS_HIDDEN = UDim2.fromScale(0.5, -1)
-- local SETTINGS_MENU_POS_REVEALED = UDim2.fromScale(0.5, 0.05)

-- local COLOR_OFF_BG = Color3.fromHex("ff5500")
-- local COLOR_OFF_TXT = Color3.fromHex("216c6c")
-- local COLOR_ON_BG = Color3.fromHex("4ee726")
-- local COLOR_ON_TXT = Color3.fromHex("38b4b6")
-- local COLOR_STROKE_OFF = Color3.fromHex("ff8686")

-- -----------------------------
-- -- Music and Sounds
-- -----------------------------
-- local function updateOnOffButton(btn, isToTurnOn)
--     local textbox = assert(btn.Parent.TextLabel) :: TextLabel
--     local bg = assert(btn.Parent.BG) :: GuiObject
--     local textStroke = assert(textbox:FindFirstChild("UIStroke")) :: UIStroke

--     if isToTurnOn then
--         bg.BackgroundColor3 = COLOR_ON_BG
--         textbox.TextColor3 = COLOR_ON_TXT
--         textbox.Text = "ON"
--         textStroke.Color = COLOR_OFF_TXT
--     else
--         bg.BackgroundColor3 = COLOR_OFF_BG
--         textbox.TextColor3 = COLOR_OFF_TXT
--         textbox.Text = "OFF"
--         textStroke.Color = COLOR_STROKE_OFF
--     end
-- end

-- local function onMenuBtnPressed(playerState, btn: any)
--     local audio = S.Sound[Id.Sound.CLICK]
--     if audio then
--         SFX.PLAY_SOUND(audio)
--     end
--     local statId
--     local currentFlags = playerState:get_resolved(statId, C.Bitset)
--     local bulletsFlag = Id.flag_test(currentFlags, Id.PlayerF.OTHER_BULLETS_ON) or true
--     local clonesFlag = Id.flag_test(currentFlags, Id.PlayerF.OTHER_CLONES_ON) or true

--     if btn == BULLETS_BTN then
--         statId = Id.PlayerF.OTHER_BULLETS_ON
--         Signal.Broadcast(Id.C2S.TOGGLE_PLAYER_FLAG, not bulletsFlag, statId)
--         updateOnOffButton(btn, not currentFlags)
--     elseif btn == CLONES_BTN then
--         statId = Id.PlayerF.OTHER_CLONES_ON
--         Signal.Broadcast(Id.C2S.TOGGLE_PLAYER_FLAG, not clonesFlag, statId)
--         updateOnOffButton(btn, not currentFlags)
--     end
-- end

-- local function toggleGearTransparency(isHovered: boolean)
--     local t
--     if isHovered then
--         t = GEAR_TRANSPARENCY_HOVER
--         if _maid.hover then
--             _maid.hover = nil
--         end
--         _maid.unhover = SharedUtils.ConnectThrottled(GEAR_BUTTON.MouseLeave, 0.5, function()
--             toggleGearTransparency(false)
--         end)
--     else
--         if _maid.unhover then
--             _maid.unhover = nil
--         end
--         _maid.hover = SharedUtils.ConnectThrottled(GEAR_BUTTON.MouseEnter, 0.5, function()
--             toggleGearTransparency(true)
--         end)
--         t = GEAR_TRANSPARENCY_UNHOVER
--     end
--     GEAR_BUTTON.ImageTransparency = t
-- end

-- local function initGUI()
--     local statValue: any

--     statValue = _state:get_resolved(Id.Flags.MUSIC_ON, C.Value)
--     updateOnOffButton(BULLETS_BTN, statValue)

--     statValue = _state:get_resolved(Id.Flags.SFX_ON, C.Value)
--     updateOnOffButton(CLONES_BTN, statValue)

--     statValue = _state:get_resolved(Id.Stats.AMBIENT_TUNE, C.Value)
--     -- server setter is handled by SFX script
--     updateTunesBtn(statValue)

--     statValue = _state:get_resolved(Id.Flags.SKIP_ANIMATION_ON, C.Value)
--     updateOnOffButton(SKIP_ANIM_BTN, statValue)

--     statValue = _state:get_resolved(Id.Flags.AUTO_OPEN_ON, C.Value)
--     updateOnOffButton(AUTOMATON_BTN, statValue)
-- end

-- type Ecs = Ecs.Ecs
-- type UIModule = Types.UIModule

-- local m = {} :: UIModule
-- -----------------------------
-- -- Module
-- -----------------------------
-- function m.Init(self: UIModule, state: Ecs, settingsBtnGUI: GuiObject?, settingsMenuGUI: GuiObject?): UIModule
--     _state = state
--     self.state = state

--     SETTINGS_BTN_GUI = assert(settingsBtnGUI) :: any
--     SETTINGS_MENU_GUI = assert(settingsMenuGUI) :: any

--     GEAR_RIM = assert(SETTINGS_BTN_GUI.Rim)
--     GEAR_BUTTON = assert(GEAR_RIM.GearButton)
--     SETTINGS_CONTAINER = assert(SETTINGS_MENU_GUI.ContainerFrame)
--     BULLETS_BTN = assert(SETTINGS_CONTAINER.SettingsPanel.ContainerFrame.SettingsScrollingFrame.MusicSlot.InfoFrame.ToggleButtonFrame.TextButton)
--     CLONES_BTN = assert(SETTINGS_CONTAINER.SettingsPanel.ContainerFrame.SettingsScrollingFrame.SoundsSlot.InfoFrame.ToggleButtonFrame.TextButton)
--     TUNE_CHANGE_BTN =
--         assert(SETTINGS_CONTAINER.SettingsPanel.ContainerFrame.SettingsScrollingFrame.TuneChangeSlot.InfoFrame.ToggleButtonFrame.TextButton)
--     SKIP_ANIM_BTN = assert(SETTINGS_CONTAINER.SettingsPanel.ContainerFrame.SettingsScrollingFrame.SkipAnimSlot.InfoFrame.ToggleButtonFrame.TextButton)
--     AUTOMATON_BTN = assert(SETTINGS_CONTAINER.SettingsPanel.ContainerFrame.SettingsScrollingFrame.AutoOpenSlot.InfoFrame.ToggleButtonFrame.TextButton)

--     SETTINGS_CONTAINER.Position = SETTINGS_MENU_POS_HIDDEN
--     SETTINGS_MENU_GUI.Enabled = false

--     _maid.hover = Util.ConnectThrottled(GEAR_BUTTON.MouseEnter, 0.5, function()
--         toggleGearTransparency(true)
--     end)

--     _maid.gearBtn = Util.ConnectThrottled(GEAR_BUTTON.Activated, 0.5, function()
--         Signal.Broadcast(Id.C2C.PLAY_AUDIO, Sounds.CLICK_SFX)
--         Signal.Broadcast(Id.C2C.GO_TO_SETTINGS)
--     end)

--     return self
-- end

-- function m:OnEnter()
--     initGUI()

--     SETTINGS_MENU_GUI.Enabled = true
--     toggleGearTransparency(false)
--     _tempMaid.waitingForExit = UserInputService.InputBegan:Connect(function(input, gameProcessed)
--         Misc.OnUIElementNotClickedDo(input, SETTINGS_CONTAINER.SettingsPanel, function()
--             Signal.Broadcast(Id.C2C.BREAK_TO_INGAME)
--         end)
--     end)
--     _tempMaid.musicBtn = Util.ConnectThrottled(BULLETS_BTN.Activated, 0.3, function()
--         onMenuBtnPressed(BULLETS_BTN)
--     end)
--     _tempMaid.soundsBtn = Util.ConnectThrottled(CLONES_BTN.Activated, 0.3, function()
--         onMenuBtnPressed(CLONES_BTN)
--     end)
--     _tempMaid.tuneBtn = Util.ConnectThrottled(TUNE_CHANGE_BTN.Activated, 0.3, function()
--         onMenuBtnPressed(TUNE_CHANGE_BTN)
--     end)
--     _tempMaid.skipAnimBtn = Util.ConnectThrottled(SKIP_ANIM_BTN.Activated, 0.3, function()
--         onMenuBtnPressed(SKIP_ANIM_BTN)
--     end)
--     _tempMaid.automatonmBtn = Util.ConnectThrottled(AUTOMATON_BTN.Activated, 0.3, function()
--         onMenuBtnPressed(AUTOMATON_BTN)
--     end)
--     local tweenTimeDown = 1.2
--     local tweenDownInfo = TweenInfo.new(tweenTimeDown, Enum.EasingStyle.Elastic, Enum.EasingDirection.Out)
--     local tweenDown = TweenService:Create(SETTINGS_CONTAINER, tweenDownInfo, { Position = SETTINGS_MENU_POS_REVEALED })
--     TaskPool.spawn(function()
--         tweenDown:Play()
--         task.wait(tweenTimeDown)
--     end)
-- end

-- -- function m.OnStateUpdate(self: UIModule, state: Ecs, world_state: Ecs) end
-- -- function m.OnHeartbeat(self: UIModule, state: Ecs, world_state: Ecs, dt: num) end

-- function m.OnInfrequentUpdate(self: UIModule, state: Ecs, world_state: Ecs, dt: num)
--     local isSkipAnimOn = state:get_resolved(Id.Flags.SKIP_ANIMATION_ON, C.Value)
--     updateOnOffButton(SKIP_ANIM_BTN, isSkipAnimOn)

--     local isAutoOpenOn = state:get_resolved(Id.Flags.AUTO_OPEN_ON, C.Value)
--     updateOnOffButton(AUTOMATON_BTN, isAutoOpenOn)
-- end

-- function m:OnExit()
--     local tweenTimeUp = 0.5
--     local tweenUpInfo = TweenInfo.new(tweenTimeUp, Enum.EasingStyle.Quart, Enum.EasingDirection.In)
--     local tweenUp = TweenService:Create(SETTINGS_CONTAINER, tweenUpInfo, { Position = SETTINGS_MENU_POS_HIDDEN })
--     TaskPool.spawn(function()
--         tweenUp:Play()
--         task.wait(tweenTimeUp + 0.1)
--         _tempMaid:Destroy()
--         SETTINGS_MENU_GUI.Enabled = false
--     end)
-- end

-- return m :: UIModule

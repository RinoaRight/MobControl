--!nolint
--!strict

local __DEV__ = not workspace or game:GetService("RunService"):IsStudio()
print("dev mode: ", __DEV__)
local __TUTORIAL__ = not __DEV__ or false

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
type uid = str
local fmt = string.format

type base64 = str

local DEBUG = false

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ReplicatedFirst = game:GetService("ReplicatedFirst")
local shared = ReplicatedStorage.shared
local Array = require(shared.array)
local Id = require(shared.Id)
type flag = Id.flag
local S = require(shared.StaticData)

local logger = require(shared.logger)

local log = logger.create("init.client"):set_delimiter(" "):set_prettifier(Id.pp)
local trace = log:make_level_logger("trace")

local perfn = require(shared.perfn)
local roflake = require(shared.roflake)
local state = require(shared.state)
local Remote = require(shared.Remote)
local RemoteClient = Remote.Client :: Remote.Client<state.Replica>
type FireServer = Remote.FireServer
local SharedConfig = require(shared.SharedConfig)
local Disposer = require(shared.disposer)
local lpack = require(shared.lpack)
local base64 = lpack.base64
local En = require(shared.enum)
local iota = En.iota
local Stm = require(shared.STM)
local Signal = require(shared.signal)
local supervisor = require(shared.supervisor)
local Misc = require(shared.Misc)
local SoundService = game:GetService("SoundService")
local RunService = game:GetService("RunService")
local ContentProvider = game:GetService("ContentProvider")
local UserInputService = game:GetService("UserInputService")
local Clones = require(script.Clones)
-- local Boosters = require(script.BoosterClient)
local Obstacles = require(script.ObstaclesClient)
local EnemiesClient = require(script.EnemiesClient)
local UICounters = require(script.UI_Counters)
local UIPlayerUpgrades = require(script.UI_PlayerUpgrades)
local NumFormat = require(shared.num_format)
local Popup = require(script.UI_Popup)
local TaskPool = require(shared.TaskPool)
local Settings = require(script.Settings)
local EnemiesFlying = require(script.EnemiesFlyingClient)
local PlayerUtils = require(script.PlayerUtils)
local Handicaps = require(script.Handicaps)

local ENV_READY = "READY"
local ENV_FIRE_SERVER = "FIRE_SERVER"
local ENV_WORLD_READY = "WORLD_READY"

local ENEMIES_FOLDER = assert(workspace:WaitForChild("Enemies"))
local ENEMY_FLYERS_FOLDER = assert(workspace:WaitForChild("EnemiesFlying"))

local ACTIVE_BULLETS_REPOSITORY = assert(workspace:WaitForChild("Bullets"))
-- Misc.AddInstanceToRaycastFilter(ACTIVE_BULLETS_REPOSITORY)
local INACTIVE_BULLETS_REPOSITORY = assert(ReplicatedStorage:WaitForChild("BulletsPool"))
local activeBulletsDataTable = {} :: { table }
local NIL_TABLE = table.freeze { "NIL" }

-----------------------------
-- States
-----------------------------
local PLAYER_STATE = state.replica(SharedConfig.PlayerState.replica_config)
local C = SharedConfig.PlayerState.CId
PLAYER_STATE:env(ENV_READY, false)
local WORLD = state.replica(SharedConfig.World.replica_config)
local W = SharedConfig.World.CId
WORLD:env(ENV_WORLD_READY, false)
-----------------------------

-- device detection
local isPC = UserInputService.TouchEnabled == false
local isMobileDevice = UserInputService.TouchEnabled == true and UserInputService.KeyboardEnabled == false
local isTouchingScreen = false
-- detect if the user is touching the screen (for mobile devices)
UserInputService.TouchStarted:Connect(function()
    isTouchingScreen = true
end)
UserInputService.TouchEnded:Connect(function()
    isTouchingScreen = false
end)
local isPressingEKey = false
local isPressingQKey = false
-- subscribe to user input
UserInputService.InputBegan:Connect(function(input, gameProcessed)
    if gameProcessed then
        return
    end
    if input.UserInputType == Enum.UserInputType.Keyboard then
        if input.KeyCode == Enum.KeyCode.Q then
            isPressingEKey = true
            UIPlayerUpgrades.OnEQPressed(PLAYER_STATE, Enum.KeyCode.Q)
        elseif input.KeyCode == Enum.KeyCode.E then
            isPressingQKey = true
            UIPlayerUpgrades.OnEQPressed(PLAYER_STATE, Enum.KeyCode.E)
        end
    end
end)
UserInputService.InputEnded:Connect(function(input, gameProcessed)
    if gameProcessed then
        return
    end
    if input.UserInputType == Enum.UserInputType.Keyboard then
        if input.KeyCode == Enum.KeyCode.E then
            isPressingEKey = false
        elseif input.KeyCode == Enum.KeyCode.Q then
            isPressingQKey = false
        end
    end
end)

local MAIN_CAMERA = workspace.CurrentCamera :: Camera
-- local SHOULDER_OFFSET = Vector3.new(2, 1.5, 6)
local SHOULDER_OFFSET = Vector3.new(3, 1.5, 12)
-- MAIN_CAMERA.CameraType = Enum.CameraType.Scriptable

local Players = game:GetService("Players")
local LOCAL_PLAYER = Players.LocalPlayer
repeat
    wait()
until LOCAL_PLAYER.Character
local LOCAL_CHARACTER = LOCAL_PLAYER.Character
local LOCAL_HUMANOID = LOCAL_PLAYER.Character:WaitForChild("Humanoid")
local LOCAL_HUMANOID_ROOT_PART = assert(LOCAL_PLAYER.Character:WaitForChild("HumanoidRootPart"))
local LOCAL_HUMANOID_HEAD = assert(LOCAL_PLAYER.Character:WaitForChild("Head"))
-- for _, child in LOCAL_PLAYER.Character:GetDescendants() do
--     if child:IsA("BasePart") then
--         Misc.AddInstanceToRaycastFilter(child)
--     end
-- end

local PLAYER_GUI = assert(LOCAL_PLAYER:WaitForChild("PlayerGui"))
local START_GUI = PLAYER_GUI:WaitForChild("StartSessionGUI")
local PLAYER_HP_GUI = assert(PLAYER_GUI.PlayerHpGui)
local PLAYER_HP_TEXT_BOX = assert(PLAYER_HP_GUI.TextLabel)

local POPUP_GUI = assert(PLAYER_GUI:WaitForChild("PopupGUI"))
local SETTINGS_MENU_GUI = assert(PLAYER_GUI:WaitForChild("SettingsMenuGUI"))
local TOKEN_SHOP_GUI = assert(PLAYER_GUI:WaitForChild("TokenShopGUI"))

local MAIN_GUI = assert(PLAYER_GUI:WaitForChild("MainGUI"))
local SETTINGS_BTN_PANEL = assert(MAIN_GUI.GearPanel)
local TOP_RIGHT_PANEL = assert(MAIN_GUI:WaitForChild("TopRightPanel"))
-- local HANDICAP_TEXT_BOX = assert(TOP_RIGHT_PANEL:WaitForChild("HandicapFrame"):WaitForChild("TextLabel"))

local ANNOUNCEMENT_GUI = assert(PLAYER_GUI:WaitForChild("AnnouncementGUI"))

local COLLIDABLES_HP_GUI_NAME = "CollidableHpGui"
local COLLIDABLES_HP_GUI_TEMPLATE = assert(PLAYER_GUI:WaitForChild(COLLIDABLES_HP_GUI_NAME)) :: BillboardGui

local PERK_SELECTION_GUI = assert(PLAYER_GUI:WaitForChild("PerkSelectionGUI"))
-- local HANDICAP_ANIM_GUI = assert(PLAYER_GUI:WaitForChild("HandicapGUI"))

-- forward declarations
local playRunAnimTrack
local startRunAnim

local function stopRunAnim(character)
    local humanoid = character:WaitForChild("Humanoid")
    for _, v in ipairs(humanoid:GetPlayingAnimationTracks()) do
        if v.Name == SharedConfig.RUN_ANIMATION_NAME then
            v:Stop()
        end
    end
end

local _player = PLAYER_STATE:constructor(C.ClientWeaponId, C.ClientTTE)
local function setPlayerToClientState(player_id, weapon_id)
    -- if PLAYER_STATE:has(player_id) or player_id == LOCAL_PLAYER.UserId then
    local tte = 0
    if weapon_id ~= Id.Weapon._NONE then
        tte = S.Weapon[weapon_id].cooldown
    end
    if PLAYER_STATE:has(player_id) then
        PLAYER_STATE:set(player_id, C.ClientWeaponId, weapon_id)
        PLAYER_STATE:set(player_id, C.ClientTTE, tte)
    else
        _player(player_id, weapon_id, tte)
    end
end

local function handleGunHoldingAnimation(character, weapon_id: int)
    local activeHoldAnimTrack

    if weapon_id == Id.Weapon.BASIC or weapon_id == Id.Weapon.SMG then
        local animId = S.Animation[Id.Animation.HOLD]
        activeHoldAnimTrack = Misc.PlayCharacterAnim(character, animId, false)
    else
        local animId = S.Animation[Id.Animation.RIFLE_AIM]
        activeHoldAnimTrack = Misc.PlayCharacterAnim(character, animId, false)
        activeHoldAnimTrack.TimePosition = activeHoldAnimTrack.Length - 0.8
        activeHoldAnimTrack:AdjustSpeed(0)
    end

    -- if weapon got unequipped, stop active weapon animation
    if weapon_id == Id.Weapon._NONE then
        activeHoldAnimTrack:Stop()
    end
end

local function onStateUpdate(playerState: state.Replica)
    UICounters.OnStateUpdate(playerState)
    UIPlayerUpgrades.OnStateUpdate(playerState, WORLD, LOCAL_CHARACTER)
end

local function onPlayerDamaged(deducted_hp: int, cause: id | uid?)
    if deducted_hp <= 0 then
        return
    end
    Misc.FlickerPlayerHPGui(PLAYER_HP_TEXT_BOX, 1.5, deducted_hp)
    local soundId = Id.Sound.SCREAM
    if cause == Id.Handicap.HP_DRAIN then
        soundId = Id.Sound.SCREAM_SQUEAK
    end
    Misc.PlaySound(soundId)
    if cause then
        local causeRefId
        if type(cause) == "string" then
            -- cause type is uid
            if WORLD:has(cause) then
                causeRefId = WORLD:get(cause, W.RefId)
            elseif PLAYER_STATE:has(cause) then
                causeRefId = PLAYER_STATE:get(cause, C.RefId)
            else
                log:error("cause is not a valid uid or id", cause)
            end
        else
            -- cause type is refId
            causeRefId = cause
        end
        if Id.kind(causeRefId) == Id.Kind.Obstacle then
            local obstacleGuid = assert(cause :: uid)
            Obstacles.OnCollisionWithObstacle(WORLD, obstacleGuid)
        elseif causeRefId == Id.WorldSpecs.BOSS_FIGHT_ON then
            if not S.Sound[Id.Sound.HISS].Playing then
                Misc.PlaySound(Id.Sound.HISS)
            end
        end
    end
end

-----------------------------
-- Net handlers
-----------------------------
-- Server Events
local on = {} :: Remote.OnRemoteEvent<state.Replica>

on[Id.S2C.UPDATE_STATE] = function(state: state.Replica, update_log)
    state:update(update_log)
    onStateUpdate(state)
end

on[Id.S2C.INIT_WORLD] = function(state: state.Replica, world_snapshot)
    WORLD:init(world_snapshot)
    WORLD:env(ENV_WORLD_READY, true)
    log:info("world ready")
end

on[Id.S2C.UPDATE_WORLD] = function(state: state.Replica, update_log)
    WORLD:update(update_log)
end

on[Id.S2C.PLAYER_DAMAGED] = function(state: state.Replica, deducted_hp: int, cause: id?)
    onPlayerDamaged(deducted_hp, cause)
end

on[Id.S2C.BOOSTER_DESTROYED] = function(state: state.Replica, boost_ref_id: id, value: num, boost_content_id: id)
    if boost_ref_id == Id.Boost.FIRST_AID_KIT then
        Misc.FlickerPlayerHPGui(PLAYER_HP_TEXT_BOX, 1.5, value)
    end
end

on[Id.S2C.PLAYER_DIED] = function(state: state.Replica, deducted_hp: int, cause: id?)
    UIPlayerUpgrades.OnPlayerDead(state, LOCAL_CHARACTER)
    MAIN_CAMERA.CameraType = Enum.CameraType.Custom
    if cause ~= Id.S2C.GAMES_SESSION_ENDED then
        -- player died because they were damaged, otherwise it's the session finished
        onPlayerDamaged(-deducted_hp, cause)
    end

    LOCAL_HUMANOID.JumpPower = 50
    for _, v in ipairs(LOCAL_HUMANOID:GetPlayingAnimationTracks()) do
        if v.Name == SharedConfig.RUN_ANIMATION_NAME then
            v.Looped = false
            v:Stop()
        end
    end
    handleGunHoldingAnimation(LOCAL_CHARACTER, Id.Weapon._NONE)
    -- kill his clones
    local clonesFolder = LOCAL_CHARACTER:FindFirstChild(SharedConfig.CLONES_FOLDER_NAME)
    if clonesFolder then
        clonesFolder:Destroy()
    end

    UICounters.ToggleAmmoFrame(false)
end

on[Id.S2C.SHOW_POPUP_SERVER] = function(state: state.Replica, event_id: id)
    if event_id == Id.C2S.PLAYER_READY_TO_START then
        Signal.Broadcast(Id.C2C.SHOW_POPUP_CLIENT, {
            text = "Max number of players reached =(\nWait for the next round!",
            ok = function() end,
        })
    elseif event_id == Id.C2S.BUY_PLAYER_UPGRADE_PERS then
        Signal.Broadcast(Id.C2C.SHOW_POPUP_CLIENT, {
            text = "You can't buy this upgrade :(\n\n",
            ok = function() end,
        })
    elseif event_id == Id.C2S.REQUEST_PLAYER_UPGRADE_NON_PERS then
        Signal.Broadcast(Id.C2C.SHOW_POPUP_CLIENT, {
            text = "This perk is maxed out :(\n\n",
            ok = function() end,
        })
    end
end

on[Id.S2C.SHIELD_DAMAGE] = function(state: state.Replica, damage: int)
    UIPlayerUpgrades.FlickerShield(PLAYER_STATE, LOCAL_CHARACTER)
end

on[Id.S2C.BOMB_HIT] = function(state: state.Replica, bomb_guid: id, pos: Vector3)
    Misc.PlaySound(Id.Sound.EXPLOSION_SHORT)
end

-- Server Broadcasts
local on_cc = {} :: { [id]: (...any) -> () }

on_cc[Id.S2CC.SESSION_HANDICAP_MODIFIED] = function(currentHandicapId: id)
    -- show current session handicap
    Handicaps.OnHandicapModified(PLAYER_STATE, MAIN_GUI, currentHandicapId)
end

on_cc[Id.S2CC.PLAYER_STARTED_SESSION] = function(player_id: id, player_hp: int)
    local weapon_id = SharedConfig.DEFAULT_WEAPON_ID
    local player = game.Players:GetPlayerByUserId(player_id)

    if player == LOCAL_PLAYER then
        weapon_id = PLAYER_STATE:get(Id.PlayerSpecs.GAME_SESSION_PARAMS, C.RefId)
    else
        weapon_id = PLAYER_STATE:get(player.UserId, C.ClientWeaponId)
    end
    if not weapon_id then
        weapon_id = SharedConfig.DEFAULT_WEAPON_ID
    end

    if player_id == LOCAL_PLAYER.UserId then
        -- disable jumping
        LOCAL_HUMANOID.JumpPower = 0

        -- start running animation
        startRunAnim(LOCAL_CHARACTER)

        Misc.FlickerPlayerHPGui(PLAYER_HP_TEXT_BOX, 1.5, player_hp)
    else
        local player = Players:GetPlayerByUserId(player_id)
        local character = player.Character or player:WaitForChild("Character", 10)
        if not character then
            return
        end
        local humanoid = character:WaitForChild("Humanoid")
        local _ = startRunAnim(character)
    end

    setPlayerToClientState(player_id, weapon_id)

    local activeHandicapId = WORLD:get(Id.WorldSpecs.HANDICAP, W.Value) :: id
    -- if the handicap has been already defined, show the ammo bar, otherwise it will be shown on [Id.S2CC.SESSION_HANDICAP_MODIFIED]
    if activeHandicapId and activeHandicapId == Id.Handicap.FINITE_AMMO then
        UICounters.ToggleAmmoFrame(true)
    end
end

on_cc[Id.S2CC.PLAYER_STOPPED_SESSION] = function(player_id: id)
    if player_id == LOCAL_PLAYER.UserId then
        -- NOTE: the logic is already done in on[Id.S2C.PLAYER_DIED]
        return
    else
        local player = Players:GetPlayerByUserId(player_id)
        if not player then
            return
        end
        local character = player.Character or player:WaitForChild("Character", 10)
        if not character then
            return
        end

        stopRunAnim(character)

        -- kill his clones
        local clonesFolder = character:FindFirstChild(SharedConfig.CLONES_FOLDER_NAME)
        if clonesFolder then
            clonesFolder:Destroy()
        end
    end
end

on_cc[Id.S2CC.PLAYER_CHANGED_WEAPON] = function(player_id: id, weapon_id: id)
    -- handle hold_anim for player
    local playerChar
    if player_id == LOCAL_PLAYER.UserId then
        playerChar = LOCAL_CHARACTER
    else
        local player = Players:GetPlayerByUserId(player_id)
        if not player then
            PLAYER_STATE:delete(player_id)
            return
        end
        playerChar = player.Character
    end

    handleGunHoldingAnimation(playerChar, weapon_id)

    -- handle hold_anim and weapon_instance for clones
    local playerRootPart = assert(playerChar.HumanoidRootPart) :: Part
    local clonesFolder = playerChar:FindFirstChild(SharedConfig.CLONES_FOLDER_NAME)
    if clonesFolder then
        local clones = clonesFolder:GetChildren()
        if clones and #clones > 0 then
            for i, clone in ipairs(clones) do
                -- handle weapon instance for clones
                handleGunHoldingAnimation(clone, weapon_id)
                local gunHand = clone:FindFirstChild("RightHand")
                local weaponInstance = gunHand:FindFirstChildWhichIsA("Model")

                if weapon_id == Id.Weapon._NONE then
                    -- player has removed weapon, remove it for clones as well
                    if weaponInstance then
                        weaponInstance:Destroy()
                    end
                else
                    -- player has equipped weapon, equip it for clones as well
                    if not weaponInstance then
                        -- clone doesn't yet have weapon, equip it
                        Misc.EquipWeaponModel(clone, weapon_id)
                    elseif weaponInstance and weaponInstance.Name ~= S.Weapon[weapon_id].name then
                        -- clone is carrying different weapon than the player, change it
                        weaponInstance:Destroy()
                        Misc.EquipWeaponModel(clone, weapon_id)
                    end
                end
            end
        end
    end

    -- SFX and initial bullet TTE
    -- if player_id == LOCAL_PLAYER.UserId then
    --     if weapon_id ~= Id.Weapon._NONE then
    --         SFX.PLAY_SOUND(Id.Sound.RELOAD_PISTOL)
    --     end
    -- else

    -- set initial TTE for other players' weapons
    if player_id ~= LOCAL_PLAYER.UserId then
        local tte = S.Weapon[Id.Weapon.BASIC].cooldown
        if weapon_id ~= Id.Weapon._NONE then
            tte = S.Weapon[weapon_id].cooldown
        end
        if not PLAYER_STATE:has(player_id) then
            log:error("No entity for this player_id in player's state", player_id)
            return
        end
        PLAYER_STATE:set(player_id, C.ClientWeaponId, weapon_id)
        if not PLAYER_STATE:get(player_id, C.ClientTTE) then
            PLAYER_STATE:set(player_id, C.ClientTTE, tte)
        end
    end
end

on_cc[Id.S2CC.BOSS_KILLED_BY_PLAYER] = function()
    Misc.PlaySound(Id.Sound.FANFARE_1)
    local font = Enum.Font.FredokaOne
    local color = Color3.fromHex("00ff00")
    Misc.ShowAnnouncement("Boss defeated!", ANNOUNCEMENT_GUI, font, color)
end

on_cc[Id.S2CC.PVP_STARTED] = function()
    -- TODO: stop run animations for all players
    local players = Players:GetPlayers()
    for _, player in ipairs(players) do
        local character = player.Character
        if character then
            stopRunAnim(character)
        end
    end
end

-----------------------------
-- Handshake
-----------------------------
local maid = Disposer.new()
local load = function(fire: FireServer, snapshot)
    local state = PLAYER_STATE
    PLAYER_STATE:init(snapshot)
    PLAYER_STATE:env(ENV_FIRE_SERVER, fire)
    PLAYER_STATE:env(ENV_READY, true)
    log:info("~~~> client\n", PLAYER_STATE:format_state("*"))
    RemoteClient.ConnectToBroadcast(on_cc)
    for _, id in Id.C2S:ids() do
        maid:Add(Signal.Connect(id, function(...)
            fire(id, ...)
        end))
    end
    Settings.Init(state, PLAYER_GUI, SETTINGS_BTN_PANEL, SETTINGS_MENU_GUI)
    Popup:Init(POPUP_GUI)
    UICounters.Init(state, TOP_RIGHT_PANEL)
    UIPlayerUpgrades.Init(PLAYER_STATE, WORLD, TOKEN_SHOP_GUI, PERK_SELECTION_GUI, LOCAL_HUMANOID_ROOT_PART, isMobileDevice)
    Handicaps.Init(WORLD, PLAYER_STATE, MAIN_GUI)

    MAIN_GUI.Enabled = true

    return state
end

local fire_server, disposable, state, us2cc = RemoteClient.Handshake(load, on)

-----------------------------
-- Supervisor
-----------------------------
-- local throttleSupervisor = supervisor.create()
-- throttleSupervisor:start(function()
--     -- if boss fight is on, check for poison belt overlap
--     if not WORLD:get(Id.WorldSpecs.BOSS_FIGHT_ON, W.Value) then
--         return
--     end
--     local parts = workspace:GetPartBoundsInBox(LOCAL_HUMANOID_ROOT_PART.CFrame, LOCAL_HUMANOID_ROOT_PART.Size)
--     local isOverlapping = false
--     for _, part in ipairs(parts) do
--         if part.Parent.Name == SharedConfig.POISON_BELT_NAME_SERVER then
--             isOverlapping = true
--             break
--         end
--     end
--     if isOverlapping then
--         if not S.Sound[Id.Sound.HISS].Playing then
--             SFX.PLAY_SOUND(Id.Sound.HISS, true)
--         end
--     else
--         S.Sound[Id.Sound.HISS]:Stop()
--     end
-- end, 0.5)

local DRIVING_BOX_INSTANCE = workspace:WaitForChild("DrivingBoxModel")
repeat
    wait()
until DRIVING_BOX_INSTANCE
local DRIVING_BOX_BACK_PART = DRIVING_BOX_INSTANCE:FindFirstChild("DrivingBoxBackPart")
-- Misc.AddInstanceToRaycastFilter(DRIVING_BOX_BACK_PART)
local DRIVING_BOX_FRONT = DRIVING_BOX_INSTANCE.PartFront
local LOCAL_PLAYER = game.Players.LocalPlayer
local DRIVING_BOX_ATT = DRIVING_BOX_FRONT.Attachment

-- load run animation
local animateScript = LOCAL_CHARACTER:WaitForChild("Animate")
local RUN_ANIM = animateScript:WaitForChild("run"):WaitForChild(SharedConfig.RUN_ANIMATION_NAME)

playRunAnimTrack = function(runAnimTrack)
    runAnimTrack:Play(0.100000001, 1, 2)
    runAnimTrack.Priority = Enum.AnimationPriority.Action3
end

startRunAnim = function(character)
    local runAnimTrack = character.Humanoid.Animator:LoadAnimation(RUN_ANIM)
    runAnimTrack.Priority = Enum.AnimationPriority.Action3
    playRunAnimTrack(runAnimTrack)
    return runAnimTrack
end

local function subscribeStartCollider()
    local SESSION_STARTER_COLLIDER = assert(workspace:WaitForChild("SessionStarter"):FindFirstChild("Collider"))
    local START_BTN = START_GUI:FindFirstChild("OKButton", true)
    maid.StartCollider = SESSION_STARTER_COLLIDER.Touched:Connect(function(other)
        if other == LOCAL_HUMANOID_ROOT_PART then
            local isBossFightOn = WORLD:get(Id.WorldSpecs.BOSS_FIGHT_ON, W.Value)
            local isPvPModeOn = WORLD:get(Id.WorldSpecs.PVP_TIME, W.Value)
            if not isBossFightOn and not isPvPModeOn then
                -- interaction with the button is possible only when the boss fight is off
                START_GUI.Enabled = true
                maid.StartBtn = START_BTN.MouseButton1Click:Connect(function()
                    START_GUI.Enabled = false
                    fire_server(Id.C2S.PLAYER_READY_TO_START)
                    maid.StartBtn = nil
                end)
            else
                -- show a message
                Signal.Fire(Id.C2C.SHOW_POPUP_CLIENT, {
                    text = "Wait for the next round!\n",
                    ok = function() end,
                })
            end
            maid.StartCollider = SESSION_STARTER_COLLIDER.TouchEnded:Connect(function(other)
                if other == LOCAL_HUMANOID_ROOT_PART then
                    START_GUI.Enabled = false
                    subscribeStartCollider()
                end
            end)
        end
    end)
end

-- TODO: test out clones and bullets visibility on/off
local function createCloneInstance(playerId, guid)
    local newInstance = Clones.CreateCloneInstance(WORLD, playerId, guid)
    local weaponId
    if playerId == LOCAL_PLAYER.UserId then
        weaponId = PLAYER_STATE:get(Id.PlayerSpecs.GAME_SESSION_PARAMS, C.RefId)
    else
        weaponId = PLAYER_STATE:get(playerId, C.ClientWeaponId)
    end
    handleGunHoldingAnimation(newInstance, weaponId)
    if not newInstance then
        log:error("failed to create clone for player " .. playerId)
        return
    end
end

local function onShowClonesToggled(isTurnedOn)
    if isTurnedOn then
        -- option to show others' clones is turned on
        for guid, refId, playerId in WORLD:select(W.RefId, W.PlayerId) do
            if playerId == LOCAL_PLAYER.UserId then
                continue
            end
            if Id.kind(refId) == Id.Kind.Clone then
                createCloneInstance(playerId, guid)
            end
        end
    else
        -- option to show others' clones is turned off
        local players = Players:GetPlayers()
        for _, player in ipairs(players) do
            if player == LOCAL_PLAYER then
                continue
            end
            local char = player.Character
            local clonesFolder = char:FindFirstChild(SharedConfig.CLONES_FOLDER_NAME)
            if not clonesFolder then
                continue
            else
                clonesFolder:Destroy()
            end
        end
    end
end

-- TODO: sights when player is in session, hide sights when player is not in session and make it dynamic. And change it for different weapons

-- Initialization
do
    TaskPool.spawn(function()
        -- initial subscription of the start button
        subscribeStartCollider()
        Signal.Connect(Id.C2C.SHOW_CLONES_TOGGLED, onShowClonesToggled)

        -- initialization of other players to the player_state
        local allPlayers = Players:GetPlayers()
        for _, player in ipairs(allPlayers) do
            if player == LOCAL_PLAYER then
                -- NOTE: initialization of the local player is set in on PLAYER_STARTED_SESSION
                continue
            end
            local player_id = player.UserId
            repeat
                task.wait()
            until WORLD:has(player_id)

            local weapon_id = WORLD:get(player_id, W.WeaponId)
            if not weapon_id then
                -- player is not in session, initialization is going to be set in on PLAYER_STARTED_SESSION
                continue
            end

            setPlayerToClientState(player_id, weapon_id)
        end
        -- initialize player's hp GUI
        PLAYER_HP_GUI.Adornee = LOCAL_HUMANOID_HEAD
        PLAYER_HP_TEXT_BOX.Text = SharedConfig.DEFAULT_HP_GUI_TEXT
    end)
end

local function getBulletDirection(rootPart: BasePart, humanoid: Humanoid): Vector3
    local moveDir = humanoid.MoveDirection
    -- local z = rootPart.CFrame.LookVector.Z
    local facing = Vector3.new(rootPart.CFrame.LookVector.X, 0, rootPart.CFrame.LookVector.Z)
    if not WORLD:get(Id.WorldSpecs.BOSS_FIGHT_ON, W.Value) and not WORLD:get(Id.WorldSpecs.PVP_TIME, W.Value) then
        -- if boss fight or pvp is not on, then shoot straight ahead
        -- z = -1
        facing = Vector3.new(0, 0, -1)
    end
    -- local flatMove = Vector3.new(moveDir.X, 0, z)
    -- local facing = Vector3.new(rootPart.CFrame.LookVector.X, 0, z)

    -- if flatMove.Magnitude > 0.1 then
    --     local crossMag = flatMove.Unit:Cross(facing.Unit).Magnitude
    --     if crossMag < 0.5 then
    --         -- Movement is mostly forward (less side motion)
    --         return flatMove.Unit
    --     end
    -- end

    -- Fallback to facing direction
    return facing.Unit
end

local function defineBulletCframe(rootPart: BasePart, bulletInstance: BasePart, weapon_id: id, humanoid: Humanoid)
    local direction = getBulletDirection(rootPart, humanoid)
    local bulletInstanceSize = Vector3.new(1, 1, 1)
    if S.Weapon[weapon_id].bulletInstanceSize then
        bulletInstanceSize = S.Weapon[weapon_id].bulletInstanceSize
    end
    local barrelLength = S.Weapon[weapon_id].barrelLength or 2
    local displacement = direction * (bulletInstanceSize.Z / 2 + barrelLength + SharedConfig.BULLET_RAYCAST_START_MULT)
    local targetPos = Vector3.new(rootPart.Position.X + 1.2, rootPart.Position.Y, rootPart.Position.Z) + displacement
    local newCFrame = CFrame.new(targetPos, targetPos + direction)
    return newCFrame
end

local function spawnBullet(player, rootPart: BasePart, weapon_id: id, rotation: CFrame?)
    local bullet
    local pos
    if INACTIVE_BULLETS_REPOSITORY:FindFirstChild("Bullet") then
        bullet = INACTIVE_BULLETS_REPOSITORY:FindFirstChild("Bullet")
    else
        bullet = ReplicatedStorage.Bullet:Clone() :: BasePart
    end
    local guid = roflake.uida()
    bullet.Name = guid

    -- set bullet properties
    bullet.CollisionGroup = "Bullet"
    bullet.CanCollide = false
    bullet.Anchored = true
    bullet:SetAttribute(SharedConfig.BULLET_ATTRIBUTE_NAME, player.UserId)

    local bulletInstaceSize = Vector3.new(1, 1, 1)
    if S.Weapon[weapon_id].bulletInstanceSize then
        bulletInstaceSize = S.Weapon[weapon_id].bulletInstanceSize
    end
    bullet.Size = bulletInstaceSize
    bullet.Color = Color3.fromHex("#ffffff")

    -- set bullet's position
    bullet.Parent = ACTIVE_BULLETS_REPOSITORY
    local speedPerkFlags = PLAYER_STATE:get(Id.PlayerUpgradeNonPersistent.BULLET_SPEED_MULT, C.Bitset)
    local isSpeedPerkActive = Id.flag_test(speedPerkFlags, Id.PlayerF.PERK_ACTIVE)
    local speed = S.Weapon[weapon_id].baseSpeed + rootPart.AssemblyLinearVelocity.Magnitude
    -- check for a bullet speed perk
    if isSpeedPerkActive then
        local mult = assert(S.PlayerUpgradeNonPersistent[Id.PlayerUpgradeNonPersistent.BULLET_SPEED_MULT].multiplier)
        local stage = PLAYER_STATE:get(Id.PlayerUpgradeNonPersistent.BULLET_SPEED_MULT, C.ValueNonPers) or 1
        speed *= 1 + mult * stage
    end
    local range = SharedConfig.BULLET_BASE_DISTANCE
    if S.Weapon[weapon_id].range then
        range = S.Weapon[weapon_id].range
    end
    local bulletTTL = roflake.time() + range / speed

    bullet.CFrame = defineBulletCframe(rootPart, bullet, weapon_id, LOCAL_HUMANOID)
    if rotation then
        -- spraygun bullets
        bullet.CFrame = bullet.CFrame * rotation
    end
    pos = bullet.Position

    -- NOTE: not an instance size, a hitbox size, for raycast below
    local bulletSize = Vector3.new(1, 1, 1)
    if S.Weapon[weapon_id].bulletSize then
        bulletSize = S.Weapon[weapon_id].bulletSize
    end

    table.insert(activeBulletsDataTable, {
        bullet = bullet,
        speed = speed,
        ttl = bulletTTL,
        owner = player,
        weapon_id = weapon_id,
        range = range,
        size = bulletSize,
    })

    local indexInTable = #activeBulletsDataTable

    return bullet, pos, indexInTable, guid
end

local function spawnSpraygunBullets(player, playerRootPart, weapon_id)
    -- generate multiple bullets and set different rotation for each of them to the data table of active bullets
    local pos
    local guids = {}
    for i = 1, 5 do
        local yRot = 0
        if i == 2 then
            yRot = 2
        elseif i == 3 then
            yRot = 4
        elseif i == 4 then
            yRot = -2
        elseif i == 5 then
            yRot = -4
        end
        local bullet, _bulletPos, _indexInTable, guid = spawnBullet(player, playerRootPart, weapon_id, CFrame.Angles(0, math.rad(yRot), 0))
        table.insert(guids, guid)
    end
    return pos, guids
end

local function fireBullet(player)
    local player_char = player.Character
    local playerRootPart = assert(player_char.HumanoidRootPart) :: BasePart
    local weapon_id

    if player == LOCAL_PLAYER then
        weapon_id = PLAYER_STATE:get(Id.PlayerSpecs.GAME_SESSION_PARAMS, C.RefId)
    else
        weapon_id = PLAYER_STATE:get(player.UserId, C.ClientWeaponId)
    end
    if not weapon_id or weapon_id == Id.Weapon._NONE then
        return
    end

    -- player's fire
    local pos
    local bulletGuids = {}
    if weapon_id == Id.Weapon.SPRAYGUN then
        local startingPos, newGuids = spawnSpraygunBullets(player, playerRootPart, weapon_id)
        pos = startingPos
        table.move(newGuids, 1, #newGuids, #bulletGuids + 1, bulletGuids)
    else
        local bullet, startingPos, _, newGuid = spawnBullet(player, playerRootPart, weapon_id)
        pos = startingPos
        table.insert(bulletGuids, newGuid)
    end

    -- clones' fire (is handled as an additional local player's fire)
    local clones_folder = player_char:FindFirstChild(SharedConfig.CLONES_FOLDER_NAME)
    if clones_folder then
        for _, clone in ipairs(clones_folder:GetChildren()) do
            local rootPart = clone.HumanoidRootPart
            if weapon_id == Id.Weapon.SPRAYGUN then
                local startingPos, newGuids = spawnSpraygunBullets(player, rootPart, weapon_id)
                pos = startingPos
                table.move(newGuids, 1, #newGuids, #bulletGuids + 1, bulletGuids)
            else
                local bulletInstance, startingPos, _, newGuid = spawnBullet(player, rootPart, weapon_id)
                pos = startingPos
                if player == LOCAL_PLAYER then
                    -- insert guids of clones' bullets to pass them to server to set to world state
                    table.insert(bulletGuids, newGuid)
                end
            end
        end
    end

    -- reset ttl for fake fire on the client for all and send to change it on server for the local client
    local weapon_id
    if player == LOCAL_PLAYER then
        weapon_id = PLAYER_STATE:get(Id.PlayerSpecs.GAME_SESSION_PARAMS, C.RefId)
        -- reset tte server-side
        fire_server(Id.C2S.BULLET_SHOT, bulletGuids, weapon_id)
        -- TODO: change sound for each type of weapon
        -- SFX.PLAY_SOUND(Id.Sound.FIRE_PISTOL)
    else
        weapon_id = PLAYER_STATE:get(player.UserId, C.ClientWeaponId)
        -- TODO: change sound for each type of weapon
        Misc.SoundLocalizedAudio(S.Sound[Id.Sound.FIRE_PISTOL_LOCALIZED], pos, 0)
    end
    local tte
    if weapon_id and weapon_id ~= Id.Weapon._NONE then
        tte = S.Weapon[weapon_id].cooldown
    end
    PLAYER_STATE:set(player.UserId, C.ClientTTE, tte)

    -- if current handicap == finite ammo and ammo count == 0, then play empty sound
    local currentHandicap = WORLD:get(Id.WorldSpecs.HANDICAP, W.Value)
    if currentHandicap == Id.Handicap.FINITE_AMMO then
        local ammoCount = PLAYER_STATE:get(Id.PlayerSpecs.GAME_SESSION_PARAMS, C.ValueNonPers) or 0
        if ammoCount == 1 then -- last bullet was just fired
            local audioId = Id.Sound.RELOAD_CLICK
            local audio = S.Sound[audioId]
            TaskPool.spawn(function()
                Misc.PlaySound(audioId)
                task.wait(audio.TimeLength + 0.1)
                Misc.PlaySound(audioId)
            end)
        end
    end
end

local function getCollisionSpecifics(bullet: BasePart, raycast_length, bullet_size)
    local bulletCFrame = bullet.CFrame
    local target, _dist = Misc.IsBulletCollidableToHit(bulletCFrame, raycast_length, bullet_size)
    local targetThickness
    local targetRefId
    local isTargetKillable
    if target and WORLD:has(target.Name) then
        targetRefId = WORLD:get(target.Name, W.RefId)
        if not targetRefId then
            log:error("no refId or instance for the bullet target", targetRefId, target.ClassName)
            return nil, false, 0, 0
        end
        if Id.kind(targetRefId) == Id.Kind.Boost then
            targetThickness = SharedConfig.BOOSTER_DEPTH
            isTargetKillable = true
        elseif Id.kind(targetRefId) == Id.Kind.Enemy then
            targetThickness = target.Size.Z
            isTargetKillable = true
        elseif Id.kind(targetRefId) == Id.Kind.Obstacle then
            targetThickness = target.Size.Z
            isTargetKillable = true
        elseif Id.kind(targetRefId) == Id.Kind.Clone then
            targetThickness = target.Size.Z
            -- check the owner of the clone
            local cloneOwnerId = WORLD:get(target.Name, W.PlayerId)
            local isOwnClone = cloneOwnerId == LOCAL_PLAYER.UserId
            -- check is PVP is on
            local isPvPModeOn = WORLD:get(Id.WorldSpecs.PVP_TIME, W.Value)
            if not isPvPModeOn or isOwnClone then
                return nil, false, 0, 0
            end
        end
    elseif target and target.Parent and target.Parent:FindFirstChildWhichIsA("Humanoid") then
        -- target is a player
        -- check if it's not the local player
        if target.Parent == LOCAL_CHARACTER then
            return nil, false, 0, 0
        end
        -- check is PVP is on
        local isPvPModeOn = WORLD:get(Id.WorldSpecs.PVP_TIME, W.Value)
        if not isPvPModeOn then
            return nil, false, 0, 0
        end
        targetRefId = target.Parent.Name
        targetThickness = target.Size.Z
        isTargetKillable = true
    end
    return target, isTargetKillable, targetThickness, targetRefId
end

-- local function applyShoulderOffset()
--     if MAIN_CAMERA.CameraSubject and MAIN_CAMERA.CameraType == Enum.CameraType.Custom then
--         local camCF = MAIN_CAMERA.CFrame

--         -- Get right and up vectors from current camera orientation
--         local right = camCF.RightVector
--         local up = camCF.UpVector

--         -- Calculate offset position (no back/forward)
--         local offset = right * SHOULDER_OFFSET.X + up * SHOULDER_OFFSET.Y + camCF.LookVector * SHOULDER_OFFSET.Z

--         MAIN_CAMERA.CFrame = camCF + offset
--     end
-- end

-- RunService:BindToRenderStep("CameraShoulderOffset", Enum.RenderPriority.Camera.Value + 1, applyShoulderOffset)

local function definePlayerOrientation()
    local lookVector = Vector3.new(0, 0, -1)
    if isTouchingScreen then
        -- Orient towards mouse/touch world position
        local mousePos
        if UserInputService.TouchEnabled and #UserInputService:GetTouches() > 0 then
            mousePos = UserInputService:GetTouches()[1].Position
        else
            mousePos = Vector2.new(UserInputService:GetMouseLocation().X, UserInputService:GetMouseLocation().Y)
        end

        local unitRay = MAIN_CAMERA:ScreenPointToRay(mousePos.X, mousePos.Y)
        local raycastParams = RaycastParams.new()
        raycastParams.FilterDescendantsInstances = { LOCAL_CHARACTER }
        raycastParams.FilterType = Enum.RaycastFilterType.Exclude

        local raycastResult = workspace:Raycast(unitRay.Origin, unitRay.Direction * 1000, raycastParams)
        if raycastResult then
            local lookPoint = raycastResult.Position
            lookVector = (lookPoint - LOCAL_HUMANOID_ROOT_PART.Position) * Vector3.new(1, 0, 1)
        end
    else
        -- Orient according to movement
        lookVector = LOCAL_HUMANOID.MoveDirection
    end
    return lookVector
end

-- MAIN LOOP
RunService.Heartbeat:Connect(function(dt)
    local players = game:GetService("Players"):GetPlayers()
    if #players < 1 then
        return
    end

    local isBossFight = WORLD:get(Id.WorldSpecs.BOSS_FIGHT_ON, W.Value)
    local isPvPModeOn = WORLD:get(Id.WorldSpecs.PVP_TIME, W.Value)

    local gameSessionFlags
    local isPlayerInSession
    if PLAYER_STATE:has(Id.PlayerSpecs.GAME_SESSION_PARAMS) then
        gameSessionFlags = PLAYER_STATE:get(Id.PlayerSpecs.GAME_SESSION_PARAMS, C.BitsetNonPers)
        isPlayerInSession = gameSessionFlags and Id.flag_test(gameSessionFlags, Id.PlayerF.READY)
    end

    if isPlayerInSession then
        local intendedPos = PlayerUtils.GetPredictedPositionWithVelocity(dt)
        -- TODO: do we need this orientation thingie? Currently it is not used for anything
        local lookVector = definePlayerOrientation()
        us2cc:FireServer(Id.C2S.PLAYER_INTENDED_POS, intendedPos, lookVector, roflake.time())
    end

    -- move clones
    local clonesRootParts = {}
    local clonesTargets = {}
    local playerRootPart
    for _, player in ipairs(players) do
        local char = player.Character
        if not char then
            return
        end
        playerRootPart = assert(char.HumanoidRootPart) :: Part
        if not playerRootPart then
            return
        end
        local clonesFolder = char:FindFirstChild(SharedConfig.CLONES_FOLDER_NAME)
        if not clonesFolder then
            continue
        end
        local clones = clonesFolder:GetChildren()
        if clones and #clones < 1 then
            continue
        end
        for i, clone in ipairs(clones) do
            local pos = playerRootPart.Position
            local cloneRootPart = clone:FindFirstChild("HumanoidRootPart")
            if not cloneRootPart then
                continue
            end
            local isCloneRunAnimActive = false
            local cloneAnimTracks = clone.Humanoid:GetPlayingAnimationTracks()
            for _, v in ipairs(cloneAnimTracks) do
                if v.Name == SharedConfig.RUN_ANIMATION_NAME then
                    isCloneRunAnimActive = true
                    break
                end
            end
            if not isCloneRunAnimActive and not isPvPModeOn then
                -- if not pvp, clones should be running
                startRunAnim(clone)
            elseif isPvPModeOn then
                -- if pvp is on, they should be running only if the player is running
                local playerIsRunAnimActive = false
                local playerAnimTracks = char.Humanoid:GetPlayingAnimationTracks()
                for _, v in ipairs(playerAnimTracks) do
                    if v.Name == SharedConfig.RUN_ANIMATION_NAME then
                        playerIsRunAnimActive = true
                        break
                    end
                end
                if not isCloneRunAnimActive and playerIsRunAnimActive then
                    print("LLLLLLLL start")
                    startRunAnim(clone)
                elseif isCloneRunAnimActive and not playerIsRunAnimActive then
                    print("LLLLLLLL stop")
                    stopRunAnim(clone)
                end
            end

            local alreadyInCol = (i - 1) % SharedConfig.CLONES_IN_A_ROW
            local row = math.floor((i - 1) / SharedConfig.CLONES_IN_A_ROW) + 1
            local cloneCFrame = Misc.GetCloneCFrame(playerRootPart.CFrame, alreadyInCol, row)
            local playerLook = playerRootPart.CFrame.LookVector
            -- local cloneTargetCFrame = CFrame.lookAlong(cloneCFrame.Position, playerLook, Vector3.yAxis)
            -- if boss fight is on, clone orientation == playerLook, else it's straight ahead along the z axis
            local cloneTargetCFrame

            if isBossFight or isPvPModeOn then
                cloneTargetCFrame = CFrame.lookAlong(cloneCFrame.Position, playerLook, Vector3.yAxis)
            else
                cloneTargetCFrame = CFrame.new(cloneCFrame.Position, cloneCFrame.Position + Vector3.new(0, 0, -1))
            end
            table.insert(clonesRootParts, cloneRootPart)
            table.insert(clonesTargets, cloneTargetCFrame)
            workspace:BulkMoveTo(clonesRootParts, clonesTargets, Enum.BulkMoveMode.FireCFrameChanged)
        end
    end

    -- move enemies and bombs
    local enemies = {}
    local enemyTargets = {}
    for guid, refId, newPos, tte in WORLD:select(W.RefId, W.Position, W.TTE) do
        if Id.kind(refId) == Id.Kind.Enemy then
            local enemyInstance = WORLD:get(guid, W.ClientInstance)
            if not enemyInstance then
                continue
            end
            -- check if animation is not in progress already, if not, move the enemy
            if WORLD:get(guid, W.ClientFlags) then
                continue
            end
            local currentPos: Vector3 = enemyInstance.Position
            table.insert(enemies, enemyInstance)
            local lookAt = Vector3.new(currentPos.X, currentPos.Y, currentPos.Z + 5)

            -- enemy is already locked on target, define lookAt
            local playerId = WORLD:get(enemyInstance.Name, W.PlayerId)
            local player = game.Players:GetPlayerByUserId(playerId)
            if player then
                local playerRoot = player.Character:FindFirstChild("HumanoidRootPart")
                lookAt = playerRoot.Position
            end
            local y = Misc.DefineObjectY(enemyInstance)
            newPos = Vector3.new(newPos.X, y, newPos.Z) -- lock Y axis for pos
            lookAt = Vector3.new(lookAt.X, newPos.Y, lookAt.Z) -- lock Y axis for look
            local newCframe = CFrame.new(newPos, lookAt) * CFrame.Angles(0, math.pi, 0)
            table.insert(enemyTargets, newCframe)
        elseif Id.kind(refId) == Id.Kind.Bomb then
            local bombInstance = WORLD:get(guid, W.ClientInstance)
            if not bombInstance then
                continue
            end
            bombInstance.Position = newPos
            -- spawn explosion if the bomb is below the player root
            if newPos.Y < playerRootPart.Position.Y and not WORLD:get(guid, W.ClientFlags) then
                local explosionSize = assert(S.Weapon[Id.Weapon.ROCKET].explosionSize)
                Misc.SpawnExplosion(newPos, explosionSize)
                WORLD:set(guid, W.ClientFlags, true)
            end
        end
    end
    if #enemies > 0 then
        workspace:BulkMoveTo(enemies, enemyTargets, Enum.BulkMoveMode.FireCFrameChanged)
    end

    -- move existing bullets
    local activeBullets = {}
    local bulletsTargetCFrames = {}
    local now = roflake.time()
    for i, bulletData in ipairs(activeBulletsDataTable) do
        -- check for collisions
        local bullet = bulletData.bullet :: Part
        local owner = bulletData.owner
        local ttl = bulletData.ttl
        local weapon_id = bulletData.weapon_id
        local speed = bulletData.speed
        local start_pos = bulletData.start_pos
        local bullet_range = bulletData.range
        -- enlarge Y axis to check for collisions with obstacles  (graves) when they are partly destroyed already
        local sizeTolerance = 2
        local raycast_size = Vector3.new(bulletData.size.X + sizeTolerance, 5, bulletData.size.Z + sizeTolerance)
        local newBulletCframe = bullet.CFrame + bullet.CFrame.LookVector * (speed * dt)

        -- check for collisions
        local raycast_length = raycast_size.Z / 2 + (speed * dt)
        local target, isTargetKillable, targetThickness, targetRefId = getCollisionSpecifics(bullet, raycast_length, raycast_size)

        local hit_z
        if target and isTargetKillable then
            local target_pos
            if Id.kind(targetRefId) == Id.Kind.Enemy then
                target_pos = WORLD:get(target.Name, W.Position)
            elseif Id.kind(targetRefId) == Id.Kind.Boost then
                target_pos = target.Position
            elseif Id.kind(targetRefId) == Id.Kind.Obstacle then
                target_pos = WORLD:get(target.Name, W.Position)
            elseif targetRefId == target.Parent.Name then
                -- target is a player
                target_pos = target.Position
            else
                log:error("no refId or instance for the bullet target", targetRefId, target.ClassName)
                return
            end
            hit_z = target_pos.Z + targetThickness + 1
            if weapon_id == Id.Weapon.ROCKET then
                local bulletWeaponDataEntry = assert(S.Weapon[weapon_id], "Weapon data entry not found for weapon")
                assert(bulletWeaponDataEntry.explosionSize, "Rocket weapon data entry must have explosion size")
                hit_z += bulletWeaponDataEntry.explosionSize.Z
            end
        end

        if target and isTargetKillable and hit_z and hit_z >= bullet.Position.Z then
            -- bullet collided with a bullet-killable target
            if owner == LOCAL_PLAYER then
                if
                    Id.kind(targetRefId) == Id.Kind.Boost
                    or Id.kind(targetRefId) == Id.Kind.Enemy
                    or Id.kind(targetRefId) == Id.Kind.Obstacle
                    or Id.kind(targetRefId) == Id.Kind.Clone
                    or targetRefId == target.Parent.Name -- target is a player
                then
                    local firstTargetGuid = target.Name
                    if Id.kind(targetRefId) == Id.Kind.Obstacle then
                        Obstacles.OnCollisionWithObstacle(WORLD, target.Name)
                    elseif Id.kind(targetRefId) == Id.Kind.Enemy then
                        EnemiesClient.OnEnemyHit(WORLD, target.Name, targetRefId, 0, 0)
                    elseif targetRefId == target.Parent.Name then
                        -- target is a player
                        local character = target.Parent
                        assert(character:IsA("Model"))
                        local isClone, playerId = Misc.CloneOrPlayer(WORLD, character)
                        if isClone then
                            firstTargetGuid = target.Name
                        elseif playerId then
                            firstTargetGuid = playerId
                        end
                    end
                    local targetGuids = { firstTargetGuid } :: { string }
                    if weapon_id == Id.Weapon.ROCKET then
                        -- animate the explosion
                        local explosionSize = assert(S.Weapon[weapon_id].explosionSize)
                        Misc.SpawnExplosion(target.Position, explosionSize)

                        -- check if there other targets hit by the explosion
                        local otherTargets = Misc.GetBulletCollidablesInRadius(target.CFrame, explosionSize)
                        if otherTargets and #otherTargets > 0 then
                            for _, otherTarget in ipairs(otherTargets) do
                                if otherTarget and WORLD:has(otherTarget.Name) then
                                    local otherTargetRefId = WORLD:get(otherTarget.Name, W.RefId)
                                    if Id.kind(otherTargetRefId) == Id.Kind.Boost or Id.kind(otherTargetRefId) == Id.Kind.Enemy then
                                        table.insert(targetGuids, otherTarget.Name)
                                    elseif Id.kind(otherTargetRefId) == Id.Kind.Clone then
                                        local cloneOwnerId = WORLD:get(otherTarget.Name, W.PlayerId)
                                        if cloneOwnerId ~= LOCAL_PLAYER.UserId then
                                            table.insert(targetGuids, otherTarget.Name)
                                        end
                                    elseif Id.kind(otherTargetRefId) == Id.Kind.Obstacle then
                                        table.insert(targetGuids, otherTarget.Name)
                                        Obstacles.OnCollisionWithObstacle(WORLD, otherTarget.Name)
                                    end
                                elseif otherTarget.Parent:FindFirstChildWhichIsA("Humanoid") then
                                    -- target is a player (not a clone, clone is handled above)
                                    local character = otherTarget.Parent
                                    local playerId = Players:GetPlayerFromCharacter(character).UserId
                                    if playerId and playerId ~= LOCAL_PLAYER.UserId then
                                        table.insert(targetGuids, playerId)
                                    end
                                end
                            end
                        end
                    end
                    fire_server(Id.C2S.TARGET_HIT, targetGuids, bullet.Name)
                end
            end
            -- remove bullet instance
            activeBulletsDataTable[i] = NIL_TABLE
            bullet.Parent = INACTIVE_BULLETS_REPOSITORY
        elseif now >= ttl then
            -- bullet timed-out, delete it. NOTE: server takes care of the corresponding uid independently
            activeBulletsDataTable[i] = NIL_TABLE
            bullet.Parent = INACTIVE_BULLETS_REPOSITORY
        else
            table.insert(activeBullets, bullet)
            table.insert(bulletsTargetCFrames, newBulletCframe)
        end
    end
    -- remove all NIL_TABLEs from the table
    local activeBulletsDataTableTemp = table.clone(activeBulletsDataTable)
    table.clear(activeBulletsDataTable)
    for i, bulletData in ipairs(activeBulletsDataTableTemp) do
        if bulletData ~= NIL_TABLE then
            table.insert(activeBulletsDataTable, bulletData)
        end
    end

    workspace:BulkMoveTo(activeBullets, bulletsTargetCFrames, Enum.BulkMoveMode.FireCFrameChanged)

    -- fire bullets for the local player + move camera
    -- local nonPersFlags = PLAYER_STATE:get(Id.PlayerSpecs.GAME_SESSION_PARAMS, C.BitsetNonPers)
    if isPlayerInSession then
        -- move camera
        -- local lookCF = LOCAL_HUMANOID_HEAD.CFrame
        -- local _, y, _ = LOCAL_HUMANOID_HEAD.CFrame:ToEulerAnglesYXZ()
        -- local pos = LOCAL_HUMANOID_HEAD.Position
        -- local yawCFrame = CFrame.new(pos) * CFrame.Angles(0, y, 0)
        -- -- Calculate camera position: offset is in local space (right, up, back)
        -- local cameraPosition = (yawCFrame * CFrame.new(SHOULDER_OFFSET)).Position
        -- -- Look horizontally forward, lock at player's Y-level (no vertical tilt)
        -- local lookAt = pos + yawCFrame.LookVector * 100
        -- MAIN_CAMERA.CFrame = CFrame.new(cameraPosition, Vector3.new(lookAt.X, cameraPosition.Y, lookAt.Z))

        -- fire bullets
        local weaponId = PLAYER_STATE:get(Id.PlayerSpecs.GAME_SESSION_PARAMS, C.RefId)
        if not weaponId or weaponId == Id.Weapon._NONE then
            return
        end
        local shot_tte = PLAYER_STATE:get(LOCAL_PLAYER.UserId, C.ClientTTE) :: num
        if shot_tte then
            shot_tte -= dt
            if shot_tte <= 0 then
                if UserInputService:IsMouseButtonPressed(Enum.UserInputType.MouseButton1) or isTouchingScreen then
                    fireBullet(LOCAL_PLAYER)
                end
            else
                PLAYER_STATE:set(LOCAL_PLAYER.UserId, C.ClientTTE, math.max(shot_tte, 0))
            end
        end
    end

    -- fake bullets' animation for other players (if the options to others' bullets is on)

    local bulletsFlag = Id.flag_test(gameSessionFlags, Id.PlayerF.OTHER_BULLETS_ON)
    if bulletsFlag then
        for _, player in ipairs(players) do
            if player == LOCAL_PLAYER then
                continue
            end
            if not WORLD:env(ENV_WORLD_READY) then
                log:warn("WORLD is not ready yet")
                continue
            end
            local playerId = player.UserId
            if PLAYER_STATE:has(playerId) then
                local weapon_id = PLAYER_STATE:get(playerId, C.ClientWeaponId)
                if weapon_id and weapon_id ~= Id.Weapon._NONE then
                    -- player is inside the game session, fire bullets
                    local shot_tte = PLAYER_STATE:get(playerId, C.ClientTTE)
                    if shot_tte then
                        shot_tte -= dt
                        if shot_tte <= 0 then
                            fireBullet(player)
                        else
                            PLAYER_STATE:set(playerId, C.ClientTTE, math.max(shot_tte, 0))
                        end
                    end
                end
            end
        end
    end
end)

WORLD:set_on_attach(W.RefId, function(guid: guid, newValue: num)
    -- log:trace("~~~>", guid, newValue)
    if not Id.is(newValue) then
        log:error("Invalid value for RefId", newValue, WORLD:format_row(guid))
    end
    if Id.kind(newValue) == Id.Kind.Obstacle then
        -- initialize client values for obstacle
        WORLD:set(guid, W.ClientFlags, false)
        WORLD:set(guid, W.ValueView, 1)
        WORLD:set(guid, W.ClientInstance, nil)
        local obstacleGuid = guid :: string
        Obstacles.onObstacleAdded(WORLD, obstacleGuid, LOCAL_HUMANOID_ROOT_PART)
    elseif Id.kind(newValue) == Id.Kind.Enemy and WORLD:get(guid, W.PlayerId) then
        local flags = WORLD:get(guid, W.Bitset)
        local isBoss = Id.flag_test(flags, Id.EnemyF.IS_BOSS)
        EnemiesClient.OnEnemyAdded(WORLD, PLAYER_STATE, guid :: string, isBoss, DRIVING_BOX_BACK_PART, LOCAL_HUMANOID_ROOT_PART)
        if isBoss then
            local font = Enum.Font.Creepster
            local color = Color3.fromHex("ff5500")
            Misc.ShowAnnouncement("BOSS INCOMING! POISON GAS RELEASED", ANNOUNCEMENT_GUI, font, color)
        end
    elseif Id.kind(newValue) == Id.Kind.EnemyFlying and WORLD:get(guid, W.PlayerId) then
        EnemiesFlying.OnFlyerAdded(WORLD, PLAYER_STATE, guid :: string, LOCAL_HUMANOID_ROOT_PART)
    elseif Id.kind(newValue) == Id.Kind.Bomb and WORLD:get(guid, W.OwnerGuid) then
        EnemiesFlying.OnBombActivated(WORLD, guid :: string)
    elseif Id.kind(newValue) == Id.Kind.Clone and WORLD:get(guid, W.PlayerId) then
        -- create clones if any new clones appeared (if the option for others' clones is turned off, for local player only)
        local playerId = WORLD:get(guid, W.PlayerId)
        local player = Players:GetPlayerByUserId(playerId)
        local cloneFolder = player.Character:FindFirstChild(SharedConfig.CLONES_FOLDER_NAME)
        local clientInstance
        if cloneFolder then
            clientInstance = cloneFolder:FindFirstChild(guid, true)
        end
        if not clientInstance then
            local currentFlags = PLAYER_STATE:get(Id.PlayerSpecs.GAME_SESSION_PARAMS, C.Bitset)
            if currentFlags then
                local clonesFlag = Id.flag_test(currentFlags, Id.PlayerF.OTHER_CLONES_ON)
                if clonesFlag or playerId == LOCAL_PLAYER.UserId then
                    createCloneInstance(playerId, guid)
                end
            end
        end
    end
end)

-- set newly connected players to the player state
WORLD:set_on_attach(W.WeaponId, function(guid: guid, newValue: num)
    log:debug("~~~>", guid)
    -- check if it is the player entity that has been added
    if type(guid) == "number" and WORLD:get(guid, W.HP) and WORLD:get(guid, W.WeaponId) and not WORLD:get(guid, W.BoostContentId) then
        -- new player connected to the server
        setPlayerToClientState(guid, newValue)
        log:trace("set new player to player state")
    end
end)

WORLD:set_on_detach(W.RefId, function(guid: guid, oldValue: num)
    if Id.kind(oldValue) == Id.Kind.Clone then
        -- if the player is in the game session, play a scream sound
        local nonPersF = PLAYER_STATE:get(Id.PlayerSpecs.GAME_SESSION_PARAMS, C.BitsetNonPers)
        local isReady = Id.flag_test(nonPersF, Id.PlayerF.READY)
        if isReady then
            Misc.PlaySound(Id.Sound.SCREAM_HIGH)
        end
    elseif Id.kind(oldValue) == Id.Kind.Obstacle then
        local instanceGuid = guid :: string
        Obstacles.CleanupClientObstacle(WORLD, instanceGuid)
    elseif Id.kind(oldValue) == Id.Kind.Enemy then
        local clientInstance = ENEMIES_FOLDER:FindFirstChild(guid)
        if clientInstance then
            clientInstance:Destroy()
        end
        if oldValue == Id.Enemy.OCTOBOSS then
            -- TODO: others bosses (we cannot check IS_BOSS flag, 'cuz the entity is already deleted)
            EnemiesClient.OnBossDestroyed(WORLD, guid :: string)
        end
    elseif Id.kind(oldValue) == Id.Kind.EnemyFlying then
        local clientInstance = ENEMY_FLYERS_FOLDER:FindFirstChild(guid)
        if clientInstance then
            clientInstance:Destroy()
        end
        EnemiesFlying.CleanupClientFlyer(WORLD, guid :: string)
    elseif Id.kind(oldValue) == Id.Kind.Bomb then
        local clientInstance = ENEMY_FLYERS_FOLDER:FindFirstChild(guid, true)
        if clientInstance then
            clientInstance:Destroy()
        end
    end
end)

WORLD:set_on_modify(W.TTE, function(guid: guid, newValue: num, oldValue: num)
    local refId = WORLD:get(guid, W.RefId)
    if Id.kind(refId) == Id.Kind.Enemy then
        if newValue > oldValue and newValue > 0 then -- tte has just been reset
            EnemiesClient.OnTTEReset(WORLD, guid :: string, refId, LOCAL_HUMANOID_ROOT_PART)
        end
    end
end)

WORLD:set_on_modify(W.HP, function(guid: guid, newValue: num, oldValue: num)
    local refId = WORLD:get(guid, W.RefId)
    if Id.kind(refId) == Id.Kind.Enemy then
        if newValue < oldValue and newValue > 0 then
            EnemiesClient.OnEnemyHpDecreased(WORLD, guid :: string, refId, newValue, oldValue)
        end
    elseif Id.kind(refId) == Id.Kind.Clone then
        if newValue < oldValue and newValue > 0 then
            Misc.PlaySound(Id.Sound.ENERGY_SHIELD_HIT)
        end
    end
end)

PLAYER_STATE:set_on_attach(C.RefId, function(guid: guid, newValue: num)
    if Id.kind(newValue) == Id.Kind.PlayerUpgradeNonPersistent then
        -- set the flag for when the aura is being destroyed
        PLAYER_STATE:set(guid, C.ClientFlags, false)
    end
end)

PLAYER_STATE:set_on_modify(C.Bitset, function(guid: guid, newValue: flag, oldValue: flag)
    if type(guid) == "number" then
        if Id.kind(guid) == Id.Kind.PlayerUpgradeNonPersistent then
            UIPlayerUpgrades.OnModifyBitset(PLAYER_STATE, LOCAL_CHARACTER, guid, newValue, oldValue)
        end
    end
end)

PLAYER_STATE:set_on_modify(C.HP, function(guid: guid, newValue: flag, oldValue: flag)
    if type(guid) == "number" then
        if Id.kind(guid) == Id.Kind.PlayerUpgradeNonPersistent then
            UIPlayerUpgrades.OnModifyHP(PLAYER_STATE, LOCAL_CHARACTER, guid, newValue, oldValue)
        end
    end
end)

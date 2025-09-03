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
type flag = Id.flag
local S = require(shared.StaticData)
local SharedConfig = require(shared.SharedConfig)
local C = SharedConfig.PlayerState.CId
local SharedUtils = require(shared.util)
local state = require(shared.state)
local UserInputService = game:GetService("UserInputService")
local Misc = require(shared.Misc)
local TaskPool = require(shared.TaskPool)
local TweenService = game:GetService("TweenService")
local NumFormat = require(shared.num_format)
local Logger = require(shared.logger)
local log = Logger.create(script and script.Name or "UI_PlayerUpgrades"):set_prettifier(Id.pp):set_delimiter(" ")
local roflake = require(shared.roflake)

-- local _state
local _maid = Disposer.new(script)
local _shopMaid = Disposer.new(script)

local isFlickering = false

local SHOP_ROOT_PANEL
local SHOP_SCROLLING_FRAME
local X_BTN
local upgradesData = {}

local PERK_SELECTION_GUI
local PERK_SELECTION_GUI_PANEL
local PERK_1_SLOT
local PERK_1_SLOT_BG
local PERK_1_SLOT_BTN: TextButton
local PERK_1_SLOT_IMG
local PERK_2_SLOT
local PERK_2_SLOT_BG
local PERK_2_SLOT_BTN: TextButton
local PERK_2_SLOT_IMG

local closeShopGui -- forward declaration

local function openShopGui(playerState, worldState, gui, localRoot)
    _shopMaid.xTab = X_BTN.Activated:Connect(function()
        Misc.PlaySound(Id.Sound.CLICK)
        closeShopGui(playerState, worldState, gui, localRoot)
    end)
end

local subscribeTokenShopCollider = function(playerState: state.Replica, worldState: state.Replica, gui, localRoot: BasePart)
    local TOKEN_SHOP_COLLIDER = assert(workspace:WaitForChild("TokenShop"):FindFirstChild("Collider"))
    -- local START_BTN = gui:FindFirstChild("OKButton", true)
    _maid.StartCollider = TOKEN_SHOP_COLLIDER.Touched:Connect(function(other: BasePart)
        if other == localRoot then
            gui.Enabled = true
            openShopGui(playerState, worldState, gui, localRoot)
            _maid.StartCollider = TOKEN_SHOP_COLLIDER.TouchEnded:Connect(function(other: BasePart)
                if other == localRoot then
                    closeShopGui(playerState, worldState, gui, localRoot)
                end
            end)
        end
    end)
end

closeShopGui = function(playerState, worldState, gui, localRoot)
    _shopMaid:Destroy()
    gui.Enabled = false
    subscribeTokenShopCollider(playerState, worldState, gui, localRoot)
end

local function onPurchaseBtnPressed(playerState, upgradeId)
    Misc.PlaySound(Id.Sound.CLICK)
    local itemPrice = assert(S.PlayerUpgradePersistent[upgradeId].price)
    local currencyId = assert(S.PlayerUpgradePersistent[upgradeId].currency)

    -- check if player already has this upgrade
    local flags = playerState:get(upgradeId, C.Bitset)
    local isBoughtAlready = Id.flag_test(flags, Id.PlayerF.PERK_ACQUIRED)
    if isBoughtAlready then
        Misc.PlaySound(Id.Sound.ERROR)
        local msg = "You already bought this upgrade!\n\n"
        Signal.Fire(Id.C2C.SHOW_POPUP_CLIENT, {
            text = msg,
            ok = function() end,
        })
        return
    end

    -- check if player has enough funds
    if Misc.IsEnoughFunds(playerState, itemPrice, currencyId) then
        Signal.Fire(Id.C2S.BUY_PLAYER_UPGRADE_PERS, upgradeId)

        -- hide the slot for the tier player bought, show the next one, if any
        local nextTierId = Misc.IsUpgradeNextTier(upgradeId)
        upgradesData[upgradeId].slot.Visible = false
        if nextTierId then
            upgradesData[nextTierId].slot.Visible = true
        end
    else
        Misc.PlaySound(Id.Sound.ERROR)
        local currencyName = assert(S.Countable[currencyId].name)
        local msg = string.format("Not enough %ss :(\n\n\n", string.lower(currencyName))
        Signal.Fire(Id.C2C.SHOW_POPUP_CLIENT, {
            text = msg,
            ok = function() end,
        })
    end
end

local function isAura(playerState: state.Replica, localCharacter: Model, perk_id: id): (boolean, BasePart)
    local aura
    local isAura
    if perk_id == Id.PlayerUpgradeNonPersistent.INVINCIBILITY then
        aura = localCharacter:FindFirstChild(SharedConfig.INVINCIBILITY_AURA_NAME) :: BasePart
    elseif perk_id == Id.PlayerUpgradeNonPersistent.SHIELD then
        aura = localCharacter:FindFirstChild(SharedConfig.SHIELD_AURA_NAME) :: BasePart
    elseif perk_id == Id.PlayerUpgradeNonPersistent.ARMOR then
        aura = localCharacter:FindFirstChild(SharedConfig.ARMOR_AURA_NAME) :: BasePart
    end
    if aura then
        isAura = true
    end

    return isAura, aura
end

local function stopFlickering()
    _maid.flickerShield = nil
    isFlickering = false
end

local function destroyAuraFast(playerState: state.Replica, localCharacter: Model, perk_id: id)
    local _, aura = isAura(playerState, localCharacter, perk_id)
    local isAuraBeingDestroyedAlready = playerState:get(perk_id, C.ClientFlags)
    if aura and not isAuraBeingDestroyedAlready then
        stopFlickering()
        Misc.PlaySound(Id.Sound.POP)
        aura:Destroy()
        playerState:set(perk_id, C.ClientFlags, false)
    end
end

local function createAura(playerState: state.Replica, localCharacter: Model, perk_id: id)
    local localPlayer = game.Players.LocalPlayer
    local playerCharacter = localPlayer.Character or localPlayer.CharacterAdded:Wait()

    -- check if there is already an aura, if it is, destroy it
    destroyAuraFast(playerState, localCharacter, perk_id)

    -- create a new aura
    local aura = S.VFX[Id.VFX.INVINCIBILITY_AURA]:Clone()
    local color = assert(S.PlayerUpgradeNonPersistent[perk_id].color)
    local name
    if perk_id == Id.PlayerUpgradeNonPersistent.INVINCIBILITY then
        name = SharedConfig.INVINCIBILITY_AURA_NAME
    elseif perk_id == Id.PlayerUpgradeNonPersistent.SHIELD then
        name = SharedConfig.SHIELD_AURA_NAME
        Misc.PlaySound(Id.Sound.ENERGY_SWEEP)
    elseif perk_id == Id.PlayerUpgradeNonPersistent.ARMOR then
        name = SharedConfig.ARMOR_AURA_NAME
        aura.Transparency = 0.85
    end
    aura.Color = color
    aura.Name = name

    aura.Parent = playerCharacter
    local upperTorso = playerCharacter:FindFirstChild("UpperTorso")
    local constraint = Instance.new("WeldConstraint")
    constraint.Parent = aura
    constraint.Part0 = upperTorso
    constraint.Part1 = aura
    aura.Position = upperTorso.Position
    aura:SetAttribute(SharedConfig.ATTRIBUTES_NAMES[Id.Kind.VFX], localPlayer.UserId)
end

local total = SharedConfig.AURA_DESTROY_DURATION
local times1 = 4
local times2 = 8
local dur1 = total / 2 / times1 / 2
local dur2 = total / 2 / times2 / 2
local tweenInfo1 = TweenInfo.new(dur1, Enum.EasingStyle.Linear)
local tweenInfo2 = TweenInfo.new(dur2, Enum.EasingStyle.Linear)
local function destroyAuraSlow(playerState: state.Replica, localCharacter: Model, perk_id: id)
    local _, aura = isAura(playerState, localCharacter, perk_id)
    if aura then
        stopFlickering()

        local initTransparency = aura.Transparency
        local targetTransparency = 1
        local tween1 = TweenService:Create(aura, tweenInfo1, { Transparency = targetTransparency })
        local tween2 = TweenService:Create(aura, tweenInfo1, { Transparency = initTransparency })
        local tween3 = TweenService:Create(aura, tweenInfo2, { Transparency = targetTransparency })
        local tween4 = TweenService:Create(aura, tweenInfo2, { Transparency = initTransparency })
        -- flicker then destroy
        _maid.destroyAuraSlow = TaskPool.spawn(function()
            playerState:set(perk_id, C.ClientFlags, true)
            for i = 1, 4 do
                tween1:Play()
                task.wait(dur1)
                tween2:Play()
                task.wait(dur2)
            end
            for i = 1, 8 do
                tween3:Play()
                task.wait(dur2)
                tween4:Play()
                task.wait(dur2)
            end
            Misc.PlaySound(Id.Sound.POP)
            aura:Destroy()
            playerState:set(perk_id, C.ClientFlags, false)
        end)
    end
end

local function hidePerkPanel()
    local tweenTimeUp = 0.5
    local tweenUpInfo = TweenInfo.new(tweenTimeUp, Enum.EasingStyle.Quart, Enum.EasingDirection.In)
    local tweenUp = TweenService:Create(PERK_SELECTION_GUI_PANEL, tweenUpInfo, { Position = UDim2.fromScale(0.5, 0) })
    TaskPool.spawn(function()
        tweenUp:Play()
        task.wait(tweenTimeUp + 0.1)
        _maid.waitingToClosePerkPanel = nil
        PERK_SELECTION_GUI.Enabled = false
    end)
end

local function onPerkBtnPressed(state: state.Replica, whichBtn: TextButton)
    _maid.waitingToClosePerkPanel = nil
    Misc.PlaySound(Id.Sound.CLICK)
    -- TODO: flicker scale of the selected perk
    local whichPerk = 0
    if whichBtn == PERK_1_SLOT_BTN then
        whichPerk = 1
    elseif whichBtn == PERK_2_SLOT_BTN then
        whichPerk = 2
    end

    Signal.Fire(Id.C2S.PERK_SELECTED, whichPerk)

    hidePerkPanel()
end

local function fillPerkInfo(playerState: state.Replica, perkId: id, descr1Box: TextLabel, descr2Box: TextLabel)
    -- TODO: color coding?
    local entry = S.PlayerUpgradeNonPersistent[perkId]
    if not entry then
        return
    end
    local period = entry.period
    local currentStage = playerState:get(perkId, C.ValueNonPers)
    local nextStageRoman = NumFormat.roman(currentStage + 1)
    local text1 = " "
    local text2 = " "
    if perkId == Id.PlayerUpgradeNonPersistent.INVINCIBILITY then
        text1 = string.format("%d sec", period)
        text2 = "invincibility"
    elseif perkId == Id.PlayerUpgradeNonPersistent.FIREPOWER then
        text1 = string.format("firepower %s", nextStageRoman)
    elseif perkId == Id.PlayerUpgradeNonPersistent.SHIELD then
        text1 = string.format("%d sec", period)
        text2 = "shield"
    elseif perkId == Id.PlayerUpgradeNonPersistent.BULLET_SPEED_MULT then
        text1 = "bullet"
        text2 = string.format("speed %s", nextStageRoman)
    elseif perkId == Id.PlayerUpgradeNonPersistent.CLONE_FACTORY then
        text1 = string.format("%d clone(s)", 1 * (currentStage + 1))
        text2 = string.format("every %d sec", period)
    elseif perkId == Id.PlayerUpgradeNonPersistent.SHIELD_RECHARGE then
        text1 = "shield"
        text2 = "recharge"
    elseif perkId == Id.PlayerUpgradeNonPersistent.SHIELD_DAMAGE then
        text1 = "shield"
        text2 = string.format("damage %s", nextStageRoman)
    elseif perkId == Id.PlayerUpgradeNonPersistent.SHIELD_COOLDOWN_MULT then
        text1 = "fast shield"
        text2 = "recharge"
    elseif perkId == Id.PlayerUpgradeNonPersistent.ARMOR then
        text1 = "armor"
        text1 = string.format("armor %s", nextStageRoman)
    end
    descr1Box.Text = string.upper(text1)
    descr2Box.Text = string.upper(text2)
end

local m = {}

function m.Init(playerState: state.Replica, worldState: state.Replica, shopGui, perkSelectionGui, localRoot)
    shopGui.Enabled = false
    SHOP_ROOT_PANEL = assert(shopGui:FindFirstChild("ContainerFrame"):FindFirstChild("ShopPanel"))
    SHOP_SCROLLING_FRAME = assert(SHOP_ROOT_PANEL:FindFirstChild("ContainerFrame"):FindFirstChild("ScrollingFrame")) :: ScrollingFrame
    X_BTN = assert(SHOP_ROOT_PANEL:FindFirstChild("XButtonRim"):FindFirstChild("ImageLabel"):FindFirstChild("TextButton"))

    PERK_SELECTION_GUI = perkSelectionGui
    PERK_SELECTION_GUI_PANEL = assert(PERK_SELECTION_GUI:WaitForChild("ContainerFrame"))
    local PERK_FRAME = assert(PERK_SELECTION_GUI_PANEL:WaitForChild("Frame"))
    PERK_1_SLOT = assert(PERK_FRAME:WaitForChild("1"))
    PERK_1_SLOT_BG = assert(PERK_1_SLOT:WaitForChild("BG"))
    PERK_1_SLOT_BTN = assert(PERK_1_SLOT:WaitForChild("SelectButton")) :: TextButton
    PERK_1_SLOT_IMG = assert(PERK_1_SLOT_BG:WaitForChild("ImageLabel"))
    PERK_2_SLOT = assert(PERK_FRAME:WaitForChild("2"))
    PERK_2_SLOT_BG = assert(PERK_2_SLOT:WaitForChild("BG"))
    PERK_2_SLOT_BTN = assert(PERK_2_SLOT:WaitForChild("SelectButton")) :: TextButton
    PERK_2_SLOT_IMG = assert(PERK_2_SLOT_BG:WaitForChild("ImageLabel"))

    hidePerkPanel()

    -- initialize player HP value view
    local playerHP = playerState:get(Id.PlayerSpecs.GAME_SESSION_PARAMS, C.HP)
    playerState:set(Id.PlayerSpecs.GAME_SESSION_PARAMS, C.ValueView, playerHP)

    _maid.slot1Btn = PERK_1_SLOT_BTN.Activated:Connect(function()
        onPerkBtnPressed(playerState, PERK_1_SLOT_BTN)
    end)
    _maid.slot2Btn = PERK_2_SLOT_BTN.Activated:Connect(function()
        onPerkBtnPressed(playerState, PERK_2_SLOT_BTN)
    end)

    -- fill in data for permanent upgrades
    -- TODO: others
    upgradesData = {
        [Id.PlayerUpgradePersistent.FIREPOWER_1] = {
            panel = assert(SHOP_SCROLLING_FRAME:FindFirstChild("A_Upgrades_1")),
            slot = assert(SHOP_SCROLLING_FRAME:FindFirstChild("Frame_1_Firepower", true)),
            isName = true,
            isDescription = true,
        },
        [Id.PlayerUpgradePersistent.FIREPOWER_2] = {
            panel = assert(SHOP_SCROLLING_FRAME:FindFirstChild("A_Upgrades_1")),
            slot = assert(SHOP_SCROLLING_FRAME:FindFirstChild("Frame_2_Firepower", true)),
            isName = true,
            isDescription = true,
        },
        [Id.PlayerUpgradePersistent.FIREPOWER_3] = {
            panel = assert(SHOP_SCROLLING_FRAME:FindFirstChild("A_Upgrades_1")),
            slot = assert(SHOP_SCROLLING_FRAME:FindFirstChild("Frame_3_Firepower", true)),
            isName = true,
            isDescription = true,
        },
        [Id.PlayerUpgradePersistent.FIREPOWER_4] = {
            panel = assert(SHOP_SCROLLING_FRAME:FindFirstChild("A_Upgrades_1")),
            slot = assert(SHOP_SCROLLING_FRAME:FindFirstChild("Frame_4_Firepower", true)),
            isName = true,
            isDescription = true,
        },
        [Id.PlayerUpgradePersistent.FIREPOWER_5] = {
            panel = assert(SHOP_SCROLLING_FRAME:FindFirstChild("A_Upgrades_1")),
            slot = assert(SHOP_SCROLLING_FRAME:FindFirstChild("Frame_5_Firepower", true)),
            isName = true,
            isDescription = true,
        },
        [Id.PlayerUpgradePersistent.HITPOINTS_1] = {
            panel = assert(SHOP_SCROLLING_FRAME:FindFirstChild("A_Upgrades_1")),
            slot = assert(SHOP_SCROLLING_FRAME:FindFirstChild("Frame_1_Hitpoints", true)),
            isName = true,
            isDescription = true,
        },
        [Id.PlayerUpgradePersistent.HITPOINTS_2] = {
            panel = assert(SHOP_SCROLLING_FRAME:FindFirstChild("A_Upgrades_1")),
            slot = assert(SHOP_SCROLLING_FRAME:FindFirstChild("Frame_2_Hitpoints", true)),
            isName = true,
            isDescription = true,
        },
        [Id.PlayerUpgradePersistent.HITPOINTS_3] = {
            panel = assert(SHOP_SCROLLING_FRAME:FindFirstChild("A_Upgrades_1")),
            slot = assert(SHOP_SCROLLING_FRAME:FindFirstChild("Frame_3_Hitpoints", true)),
            isName = true,
            isDescription = true,
        },
        [Id.PlayerUpgradePersistent.HITPOINTS_4] = {
            panel = assert(SHOP_SCROLLING_FRAME:FindFirstChild("A_Upgrades_1")),
            slot = assert(SHOP_SCROLLING_FRAME:FindFirstChild("Frame_4_Hitpoints", true)),
            isName = true,
            isDescription = true,
        },
        [Id.PlayerUpgradePersistent.HITPOINTS_5] = {
            panel = assert(SHOP_SCROLLING_FRAME:FindFirstChild("A_Upgrades_1")),
            slot = assert(SHOP_SCROLLING_FRAME:FindFirstChild("Frame_5_Hitpoints", true)),
            isName = true,
            isDescription = true,
        },
        [Id.PlayerUpgradePersistent.INIT_CLONE_1] = {
            panel = assert(SHOP_SCROLLING_FRAME:FindFirstChild("A_Upgrades_1")),
            slot = assert(SHOP_SCROLLING_FRAME:FindFirstChild("Frame_1_Clones", true)),
            isName = true,
            isDescription = true,
        },
        [Id.PlayerUpgradePersistent.INIT_CLONE_2] = {
            panel = assert(SHOP_SCROLLING_FRAME:FindFirstChild("A_Upgrades_1")),
            slot = assert(SHOP_SCROLLING_FRAME:FindFirstChild("Frame_2_Clones", true)),
            isName = true,
            isDescription = true,
        },
        [Id.PlayerUpgradePersistent.INIT_CLONE_3] = {
            panel = assert(SHOP_SCROLLING_FRAME:FindFirstChild("A_Upgrades_1")),
            slot = assert(SHOP_SCROLLING_FRAME:FindFirstChild("Frame_3_Clones", true)),
            isName = true,
            isDescription = true,
        },
    }

    -- fill in info
    for id, v in pairs(upgradesData) do
        local entry = S.PlayerUpgradePersistent[id]
        if not entry then
            log:error("No entry for upgrade id %s", id, debug.traceback())
            return
        end

        local root
        if upgradesData[id].slot then
            root = upgradesData[id].slot
        else
            root = upgradesData[id].panel
        end

        -- check if there is the need to fill in the name
        if upgradesData[id].isName then
            local nameBox = assert(root.BG.PassName)
            nameBox.Text = string.upper(entry.name)
        end

        -- check if there is the need to fill in the description, and how many lines it takes
        if upgradesData[id].isDescription then
            local descrBox = assert(root.BG.PassDescription)
            descrBox.Text = entry.descr
        end

        -- locate and fill in purchase buttons
        upgradesData[id].purchaseBtn = root:FindFirstChild("BuyButton", true)
        local purchaseBtnTextBox = upgradesData[id].purchaseBtn:FindFirstChild("TextLabel")
        purchaseBtnTextBox.Text = assert(entry.price)

        -- subscribe purchase buttons
        _maid:Add(SharedUtils.ConnectThrottled(upgradesData[id].purchaseBtn.Activated, 0.3, function()
            onPurchaseBtnPressed(playerState, id)
            -- TODO: add possibility to press Q and E for desktop players
        end))

        -- define which upgrades to show
        -- TODO: others
        if
            id == Id.PlayerUpgradePersistent.FIREPOWER_1
            or id == Id.PlayerUpgradePersistent.HITPOINTS_1
            or id == Id.PlayerUpgradePersistent.INIT_CLONE_1
        then
            upgradesData[id].slot.Visible = true
        else
            upgradesData[id].slot.Visible = false
        end
    end

    subscribeTokenShopCollider(playerState, worldState, shopGui, localRoot)
end

function m.OnModifyBitset(playerState: state.Replica, localCharacter, guid: guid, newValue: flag, oldValue: flag)
    local _isAcquiredNow = Id.flag_test(newValue, Id.PlayerF.PERK_ACQUIRED)
    local isActiveNow = Id.flag_test(newValue, Id.PlayerF.PERK_ACTIVE)
    local _isAcquiredBefore = Id.flag_test(oldValue, Id.PlayerF.PERK_ACQUIRED)
    local isActiveBefore = Id.flag_test(oldValue, Id.PlayerF.PERK_ACTIVE)
    if
        guid == Id.PlayerUpgradeNonPersistent.INVINCIBILITY
        or guid == Id.PlayerUpgradeNonPersistent.SHIELD
        or guid == Id.PlayerUpgradeNonPersistent.ARMOR
    then
        -- if isAcquiredNow and isActiveNow then
        --     createAura(playerState, localCharacter, guid :: id)
        -- elseif not isActiveNow then
        --     local isAuraBeingDestroyedAlready = playerState:get(guid, C.ClientFlags)
        --     if not isAuraBeingDestroyedAlready then
        --         destroyAuraFast(playerState, localCharacter, guid :: id)
        --     end
        -- end
        if isActiveNow and not isActiveBefore then
            createAura(playerState, localCharacter, guid :: id)
        elseif not isActiveNow and isActiveBefore then
            local isAuraBeingDestroyedAlready = playerState:get(guid, C.ClientFlags)
            if not isAuraBeingDestroyedAlready then
                destroyAuraFast(playerState, localCharacter, guid :: id)
            end
        end
    end
end

function m.OnModifyHP(playerState: state.Replica, localCharacter, guid: guid, newValue: number, oldValue: number)
    if guid == Id.PlayerUpgradeNonPersistent.SHIELD then
        if newValue < oldValue and newValue ~= 0 then
            Misc.PlaySound(Id.Sound.ENERGY_SHIELD_HIT)
        end
    end
end

function m.FlickerShield(playerState: state.Replica, localCharacter)
    local _, aura = isAura(playerState, localCharacter, Id.PlayerUpgradeNonPersistent.SHIELD)
    if aura and not isFlickering then
        _maid.flickerShield = TaskPool.spawn(function()
            -- TODO: SFX
            isFlickering = true
            aura.Color = Color3.fromRGB(255, 255, 255)
            local dur = 0.05
            local tweenInfo = TweenInfo.new(dur, Enum.EasingStyle.Linear)
            local origScale = aura.Size
            local targetScale = origScale * 1.5
            local tween1 = TweenService:Create(aura, tweenInfo, { Size = targetScale })
            local tween2 = TweenService:Create(aura, tweenInfo, { Size = origScale })
            tween1:Play()
            task.wait(dur)
            tween2:Play()
            isFlickering = false
            aura.Color = S.PlayerUpgradeNonPersistent[Id.PlayerUpgradeNonPersistent.SHIELD].color
        end)
    end
end

function m.OnStateUpdate(playerState: state.Replica, localCharacter)
    local isInvincible = Id.flag_test(playerState:get(Id.PlayerUpgradeNonPersistent.INVINCIBILITY, C.Bitset), Id.PlayerF.PERK_ACTIVE)
    local isShield = Id.flag_test(playerState:get(Id.PlayerUpgradeNonPersistent.SHIELD, C.Bitset), Id.PlayerF.PERK_ACTIVE)
    local isArmor = Id.flag_test(playerState:get(Id.PlayerUpgradeNonPersistent.ARMOR, C.Bitset), Id.PlayerF.PERK_ACTIVE)
    local playerHPValueView = playerState:get(Id.PlayerSpecs.GAME_SESSION_PARAMS, C.ValueView)
    local playerHP = playerState:get(Id.PlayerSpecs.GAME_SESSION_PARAMS, C.HP)
    local playerFlags = playerState:get(Id.PlayerSpecs.GAME_SESSION_PARAMS, C.BitsetNonPers)
    local isPlayerInSession = playerFlags and Id.flag_test(playerFlags, Id.PlayerF.READY)

    if isInvincible then
        local ttl = playerState:get(Id.PlayerUpgradeNonPersistent.INVINCIBILITY, C.TTL)
        local isAuraBeingDestroyedAlready = playerState:get(Id.PlayerUpgradeNonPersistent.INVINCIBILITY, C.ClientFlags)
        if ttl <= roflake.time() + SharedConfig.AURA_DESTROY_DURATION and not isAuraBeingDestroyedAlready then
            destroyAuraSlow(playerState, localCharacter, Id.PlayerUpgradeNonPersistent.INVINCIBILITY)
        end
    elseif isShield then
        local ttl = playerState:get(Id.PlayerUpgradeNonPersistent.SHIELD, C.TTL)
        local isAuraBeingDestroyedAlready = playerState:get(Id.PlayerUpgradeNonPersistent.SHIELD, C.ClientFlags)
        if ttl <= roflake.time() + SharedConfig.AURA_DESTROY_DURATION and not isAuraBeingDestroyedAlready then
            destroyAuraSlow(playerState, localCharacter, Id.PlayerUpgradeNonPersistent.SHIELD)
        end
    elseif isArmor then
        -- SFX for ARMOR
        if playerHPValueView > playerHP and isPlayerInSession then
            Misc.PlaySound(Id.Sound.ARMOR_HIT)
        end
    end

    playerState:set(Id.PlayerSpecs.GAME_SESSION_PARAMS, C.ValueView, playerHP)
end

function m.OnPlayerRankUpdate(state: state.Replica)
    -- TODO: sound a sound
    local choice = state:get(Id.PlayerSpecs.XP_PROGRESS, C.V3)
    local perk1 = choice.X
    local perk2 = choice.Y
    if perk1 ~= 0 or perk2 ~= 0 then
        -- TODO: change image
        if perk1 ~= 0 then
            fillPerkInfo(state, perk1, PERK_1_SLOT_BG.PassDescription, PERK_1_SLOT_BG.PassDescription2)
            PERK_1_SLOT.Visible = true
        else
            PERK_1_SLOT.Visible = false
        end
        if perk2 ~= 0 then
            fillPerkInfo(state, perk2, PERK_2_SLOT_BG.PassDescription, PERK_2_SLOT_BG.PassDescription2)
            PERK_2_SLOT.Visible = true
        else
            PERK_2_SLOT.Visible = false
        end
    end

    PERK_SELECTION_GUI.Enabled = true

    local tweenTimeDown = 1.2
    local tweenDownInfo = TweenInfo.new(tweenTimeDown, Enum.EasingStyle.Elastic, Enum.EasingDirection.Out)
    local tweenDown = TweenService:Create(PERK_SELECTION_GUI_PANEL, tweenDownInfo, { Position = UDim2.fromScale(0.5, 0.5) })
    _maid.waitingToClosePerkPanel = TaskPool.spawn(function()
        tweenDown:Play()
        task.wait(tweenTimeDown)
        -- close the panel after some time
        task.wait(5)
        if PERK_SELECTION_GUI.Enabled then
            hidePerkPanel()
        end
    end)
end

function m.OnPlayerDead(playerState: state.Replica, localCharacter)
    -- cleanup
    hidePerkPanel()
    stopFlickering()
    for _, child in localCharacter:GetChildren() do
        if
            child.Name == SharedConfig.INVINCIBILITY_AURA_NAME
            or child.Name == SharedConfig.SHIELD_AURA_NAME
            or child.Name == SharedConfig.ARMOR_AURA_NAME
        then
            child:Destroy()
        end
    end
end

return m

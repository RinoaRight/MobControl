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
local Logger = require(shared.logger)
local log = Logger.create(script and script.Name or "UI_PlayerUpgrades"):set_prettifier(Id.pp):set_delimiter(" ")

-- local _state
local _maid = Disposer.new(script)
local _workerMaid = Disposer.new(script)

local SHOP_ROOT_PANEL
local SHOP_SCROLLING_FRAME
local X_BTN
local upgradesData = {}

local closeShopGui -- forward declaration

local function openShopGui(playerState, worldState, gui, localRoot)
    _workerMaid.xTab = X_BTN.Activated:Connect(function()
        SFX.PLAY_SOUND(Id.Sound.CLICK)
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
    _workerMaid:Destroy()
    gui.Enabled = false
    subscribeTokenShopCollider(playerState, worldState, gui, localRoot)
end

local function onPurchaseBtnPressed(playerState, upgradeId)
    SFX.PLAY_SOUND(Id.Sound.CLICK)
    local itemPrice = assert(S.PlayerUpgrade[upgradeId].price)
    local currencyId = assert(S.PlayerUpgrade[upgradeId].currency)

    -- check if player already has this upgrade
    local isBoughtAlready = playerState:get(upgradeId, C.Value)
    if isBoughtAlready then
        SFX.PLAY_SOUND(Id.Sound.ERROR)
        local msg = "You already bought this upgrade!\n\n"
        Signal.Fire(Id.C2C.SHOW_POPUP_CLIENT, {
            text = msg,
            ok = function() end,
        })
        return
    end

    -- check if player has enough funds
    if Misc.IsEnoughFunds(playerState, itemPrice, currencyId) then
        Signal.Fire(Id.C2S.BUY_PLAYER_UPGRADE, upgradeId)

        -- hide the slot for the tier player bought, show the next one, if any
        local nextTierId = Misc.IsUpgradeNextTier(upgradeId)
        upgradesData[upgradeId].slot.Visible = false
        if nextTierId then
            upgradesData[nextTierId].slot.Visible = true
        end

    else
        SFX.PLAY_SOUND(Id.Sound.ERROR)
        local currencyName = assert(S.Countable[currencyId].name)
        local msg = string.format("Not enough %ss :(\n\n\n", string.lower(currencyName))
        Signal.Fire(Id.C2C.SHOW_POPUP_CLIENT, {
            text = msg,
            ok = function() end,
        })
    end
end

local m = {}

function m.Init(playerState: state.Replica, worldState: state.Replica, shopGui, localRoot)
    shopGui.Enabled = false
    SHOP_ROOT_PANEL = assert(shopGui:FindFirstChild("ContainerFrame"):FindFirstChild("ShopPanel"))
    SHOP_SCROLLING_FRAME = assert(SHOP_ROOT_PANEL:FindFirstChild("ContainerFrame"):FindFirstChild("ScrollingFrame")) :: ScrollingFrame
    X_BTN = assert(SHOP_ROOT_PANEL:FindFirstChild("XButtonRim"):FindFirstChild("ImageLabel"):FindFirstChild("TextButton"))

    -- fill in data
    -- TODO: others
    upgradesData = {
        [Id.PlayerUpgrade.FIREPOWER_1] = {
            panel = assert(SHOP_SCROLLING_FRAME:FindFirstChild("A_Upgrades_1")),
            slot = assert(SHOP_SCROLLING_FRAME:FindFirstChild("Frame_1_Firepower", true)),
            isName = true,
            isDescription = true,
        },
        [Id.PlayerUpgrade.FIREPOWER_2] = {
            panel = assert(SHOP_SCROLLING_FRAME:FindFirstChild("A_Upgrades_1")),
            slot = assert(SHOP_SCROLLING_FRAME:FindFirstChild("Frame_2_Firepower", true)),
            isName = true,
            isDescription = true,
        },
        [Id.PlayerUpgrade.FIREPOWER_3] = {
            panel = assert(SHOP_SCROLLING_FRAME:FindFirstChild("A_Upgrades_1")),
            slot = assert(SHOP_SCROLLING_FRAME:FindFirstChild("Frame_3_Firepower", true)),
            isName = true,
            isDescription = true,
        },
        [Id.PlayerUpgrade.FIREPOWER_4] = {
            panel = assert(SHOP_SCROLLING_FRAME:FindFirstChild("A_Upgrades_1")),
            slot = assert(SHOP_SCROLLING_FRAME:FindFirstChild("Frame_4_Firepower", true)),
            isName = true,
            isDescription = true,
        },
        [Id.PlayerUpgrade.FIREPOWER_5] = {
            panel = assert(SHOP_SCROLLING_FRAME:FindFirstChild("A_Upgrades_1")),
            slot = assert(SHOP_SCROLLING_FRAME:FindFirstChild("Frame_5_Firepower", true)),
            isName = true,
            isDescription = true,
        },
        [Id.PlayerUpgrade.HITPOINTS_1] = {
            panel = assert(SHOP_SCROLLING_FRAME:FindFirstChild("A_Upgrades_1")),
            slot = assert(SHOP_SCROLLING_FRAME:FindFirstChild("Frame_1_Hitpoints", true)),
            isName = true,
            isDescription = true,
        },
        [Id.PlayerUpgrade.HITPOINTS_2] = {
            panel = assert(SHOP_SCROLLING_FRAME:FindFirstChild("A_Upgrades_1")),
            slot = assert(SHOP_SCROLLING_FRAME:FindFirstChild("Frame_2_Hitpoints", true)),
            isName = true,
            isDescription = true,
        },
        [Id.PlayerUpgrade.HITPOINTS_3] = {
            panel = assert(SHOP_SCROLLING_FRAME:FindFirstChild("A_Upgrades_1")),
            slot = assert(SHOP_SCROLLING_FRAME:FindFirstChild("Frame_3_Hitpoints", true)),
            isName = true,
            isDescription = true,
        },
        [Id.PlayerUpgrade.HITPOINTS_4] = {
            panel = assert(SHOP_SCROLLING_FRAME:FindFirstChild("A_Upgrades_1")),
            slot = assert(SHOP_SCROLLING_FRAME:FindFirstChild("Frame_4_Hitpoints", true)),
            isName = true,
            isDescription = true,
        },
        [Id.PlayerUpgrade.HITPOINTS_5] = {
            panel = assert(SHOP_SCROLLING_FRAME:FindFirstChild("A_Upgrades_1")),
            slot = assert(SHOP_SCROLLING_FRAME:FindFirstChild("Frame_5_Hitpoints", true)),
            isName = true,
            isDescription = true,
        },
        [Id.PlayerUpgrade.INIT_CLONE_1] = {
            panel = assert(SHOP_SCROLLING_FRAME:FindFirstChild("A_Upgrades_1")),
            slot = assert(SHOP_SCROLLING_FRAME:FindFirstChild("Frame_1_Clones", true)),
            isName = true,
            isDescription = true,
        },
        [Id.PlayerUpgrade.INIT_CLONE_2] = {
            panel = assert(SHOP_SCROLLING_FRAME:FindFirstChild("A_Upgrades_1")),
            slot = assert(SHOP_SCROLLING_FRAME:FindFirstChild("Frame_2_Clones", true)),
            isName = true,
            isDescription = true,
        },
        [Id.PlayerUpgrade.INIT_CLONE_3] = {
            panel = assert(SHOP_SCROLLING_FRAME:FindFirstChild("A_Upgrades_1")),
            slot = assert(SHOP_SCROLLING_FRAME:FindFirstChild("Frame_3_Clones", true)),
            isName = true,
            isDescription = true,
        },
    }

    -- fill in info
    for id, v in pairs(upgradesData) do
        local entry = S.PlayerUpgrade[id]
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
        end))

        -- define which upgrades to show
        -- TODO: others
        if id == Id.PlayerUpgrade.FIREPOWER_1 then
            upgradesData[id].slot.Visible = true
        elseif id == Id.PlayerUpgrade.FIREPOWER_2 then
            upgradesData[id].slot.Visible = false
        elseif id == Id.PlayerUpgrade.FIREPOWER_3 then
            upgradesData[id].slot.Visible = false
        elseif id == Id.PlayerUpgrade.FIREPOWER_4 then
            upgradesData[id].slot.Visible = false
        elseif id == Id.PlayerUpgrade.FIREPOWER_5 then
            upgradesData[id].slot.Visible = false
        end
    end

    subscribeTokenShopCollider(playerState, worldState, shopGui, localRoot)
end

return m

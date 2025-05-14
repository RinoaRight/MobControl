--!strict
-- MIT License
-- Copyright (c) 2022 Andrew Zhilin (https://github.com/zoon)

--[=[
    Header
    Usage:
    ```lua
    local x = ...
    ```
--]=]

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

--[[ stylua: ignore]] if not game then(function() game = require("game") end)() end
local shared = game.ReplicatedStorage.shared
local Id = require(shared.Id)
local Logger = require(shared.logger)
local log = Logger.create("Market"):set_prettifier(Id.pp):set_delimiter(" ")
local TaskPool = require(shared.TaskPool)
local Signal = require(shared.signal)
local En = require(shared.enum)
local _iota = En.iota
local _flag = En.flag

local MarketplaceService = game.MarketplaceService
export type Receipt = {
    CurrencySpent: int, -- always Robux
    PurchaseId: guid, -- UUID-like "edd4223f0d2c7a08dd8bdb57187568bd"
    PlayerId: id,
    ProductId: id,
    PlaceIdWherePurchased: id,
}
export type IdCount = {
    count: int,
    id: uid,
    area_id: id?,
    level: int?,
}

-- stylua: ignore

local Products:map<id, IdCount> = table.freeze {
    -- Countables
    [Id.Product.NONE] = { id = Id.CountablePersistent._NONE; count = 1},
    -- TODO: add other products
} :: any

-----------------------------
-- Module
-----------------------------
local m = {}
m.__index = m
m.Products = Products

-- call it from init.server
function m.CheckPassesOnInit(player_id, get_store_id: (id) -> int)
    for _, pass_id in Id.Pass:iterate() do
        local store_id = get_store_id(pass_id)
        TaskPool.call(function()
            local has_pass = false
            -- TODO: refactor.
            local ok, err = pcall(function()
                has_pass = MarketplaceService:UserOwnsGamePassAsync(player_id, store_id)
            end)
            if not ok then
                log:error("PassService", err)
            end
            log:info("PASS STATUS ON INIT: %* %-20s: %*", player_id, Id.name(pass_id), has_pass)
            if has_pass then
                Signal.Broadcast(Id.S2S.PASS_GRANTED, player_id, pass_id, Id.PassF.BOUGHT)
            end
        end)
    end
end

-- call it from init.server
function m.PurchasedFinishedFactory(get_pass_id: (int) -> id)
    return MarketplaceService.PromptGamePassPurchaseFinished:Connect(function(player, store_id, success)
        if success and player then
            local pass_id = get_pass_id(store_id)
            Signal.Broadcast(Id.S2S.PASS_GRANTED, player.UserId, pass_id, Id.PassF.BOUGHT)
            Signal.Broadcast(Id.S2S.PURCHASE_FINISHED, player.UserId, pass_id)
        end
    end)
end

-- call it from init.server
function m.ConnectProcessReceipt<state>(get_state: (player_id: int) -> state)
    assert(MarketplaceService.ProcessReceipt == nil, "callback already connected")
    MarketplaceService.ProcessReceipt = function(receipt)
        if not (receipt and receipt.PlayerId) then
            return Enum.ProductPurchaseDecision.NotProcessedYet
        end
        local state = get_state(receipt.PlayerId)
        if state then
            assert(type(state) == "table")
            return state:HandleReceipt(receipt)
        end
        return Enum.ProductPurchaseDecision.NotProcessedYet
    end
end

--[[ state:HandleReceipt PSEUDOCODE @ref: https://create.roblox.com/docs/reference/engine/classes/MarketplaceService#ProcessReceipt
```lua
function _HandleReceipt<state>(self: state, receipt: Receipt): Enum.ProductPurchaseDecision
    if self:find(receipt.PurchaseId) then
        self:delete(receipt.PurchaseId)
        return Enum.ProductPurchaseDecision.PurchaseGranted
    end
    -- here, give goodies by PurchaseId
    self:add(receipt.PurchaseId)
    return Enum.ProductPurchaseDecision.NotProcessedYet
end
```
--]]

return m

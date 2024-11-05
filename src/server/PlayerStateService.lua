--!strict
--!native
-- MIT License
-- Copyright (c) 2024 Andrew Zhilin (https://github.com/zoon)

--[=[
    Header
    Usage:
    ```lua
    local x = ...
    ```
--]=]

local MOCK_DATASTORE_IN_STUDIO_FLAG = true
local IS_ROBLOX = not not game

local _USE_MOCK_DATASTORE = not IS_ROBLOX or MOCK_DATASTORE_IN_STUDIO_FLAG
local _DUMP_AFTER_SESSION = true

type str = string
type bool = boolean
type num = number
type integer = num
type uint = integer
type int = integer
type u32 = uint
type u8 = uint
type id = int
type array<a> = { a }
type map<k, v> = { [k]: v }
local _fmt = string.format

--[[ stylua: ignore]] game = game or require("game")
local shared = game.ReplicatedStorage.shared
local enum = require(shared.enum)
local _iota = enum.iota
local Id = require(shared.Id)
local SharedConfig = require(shared.SharedConfig)
local state = require(shared.state)
local _signal = require(shared.signal)
local _ulid = require(shared.ulid)
local _roflake = require(shared.roflake)
local remote = require(shared.Remote)
local disposer = require(shared.disposer)
local logger = require(shared.logger)
local log = logger.create("PlayerStateService"):set_prettifier(Id.pp)

-------------------
-- Server Modules
-------------------
local server = game.ServerScriptService.server
local _Market = require(server.Market)

local STORE_ID = "test"

local STORE
if workspace and not _USE_MOCK_DATASTORE then
    local DataStoreService = game:GetService("DataStoreService")
    STORE = DataStoreService:GetDataStore(STORE_ID)
else
    local MockDataStore = require(shared.MockDataStore)
    MockDataStore.InitState(SharedConfig.Save) -- <== load from b64 encoded store
    type DataStore = MockDataStore.DataStore
    STORE = MockDataStore:GetDataStore(STORE_ID)
end

-------------------
-- Types
-------------------
type State = state.Main
type enum = enum.Enum
type disposer = disposer.Disposer

export type PlayerStateService = {
    load: (Player, remote.FireClient) -> (PlayerState, array<any>),
    format: (PlayerState) -> str,
}

export type PlayerState = {
    player_id: int,
    state_store_key: str,
    state: State,
    disposer: disposer,
    fire_client: remote.FireClient,
    Save: (self: PlayerState) -> (),
    Destroy: (self: PlayerState) -> (),
    AddCountable: (self: PlayerState, id: id, count: int) -> (),
    __index: any,
}

local function fill_state(player_state: PlayerState)
    log:assert(not player_state.state:env("READY"), "already loaded")
    local data, info = STORE:GetAsync(player_state.state_store_key)
end

-----------------------------
-- Module
-----------------------------
local m = {}
m.__index = m
local PlayerState = {} :: PlayerState
PlayerState.__index = PlayerState

function m.load(player: Player, fire_client: remote.FireClient): (PlayerState, array<any>)
    local state = state.main() --- @todo: config
    local player_state: PlayerState = table.freeze(setmetatable({
        player_id = player.UserId,
        state = state, -- TODO:
        disposer = disposer.new(),
        fire_client = fire_client,
    }, PlayerState)) :: any
    -- fill_state(player_state)
    local snapshot = state:snapshot("discard-log")
    return player_state, snapshot
end

-----------------------------
-- PlayerState
-----------------------------

-----------------------------
-- Quick test
-----------------------------

warn("[PlayerStateService -- ok]")
return m

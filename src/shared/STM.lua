--!strict
-- MIT License
-- Copyright (c) 2022 Andrew Zhilin (https://github.com/zoon)
local DEBUG = true
--[=[
    Notes:
    - connect to transition
        TODO: add self as a first arg of observer
        stage := Exit***
        Connect: (FSM_EVENTS, prev_state_id, prev_state_name)
        stage: = Enter***
        Connect: (FSM_EVENTS, state_id, state_name)
    - actions on state: Check?, Enter, Update?, Exit will be called on fsm:GoTo(state, ...:any)
    fsm:AddAction(state_id, action_id, ???)
    - event handling per state: (commonly call GoTo within handler)
    fsm:Fire(event_id, ...:any) -- note: not a Signal.Broadcast!
    fsm:AddEventHandler(state_id, event_id, ???)
--]=]

type str = string
type bool = boolean
type num = number
type integer = num
type uint = integer
type int = integer
type u32 = uint
type i32 = int
type u8 = uint
type array<a> = { a }
type table = { [any]: any }
type map<k, v> = { [k]: v }
type fun = (...any) -> ...any
local fmt = string.format

type StateId = int
type StateName = str
type ActionId = int
type HandlerId = int
type EventId = int
type StmEventId = int
type StmEventName = str
type EventName = str
type EventGuid = str
type DeltaTime = num
type Handler = (State, ...any) -> ()

if game then
    assert(game:GetService("RunService"):IsClient(), "STM for client only!")
end

--[[ stylua: ignore]] script = script or require'script'
local roflake = require(script.Parent.roflake)
local Disposer = require(script.Parent.disposer)
local Signal = require(script.Parent.signal)
local En = require(script.Parent.enum)
type En = En.Enum
local iota = En.iota
local _flag = En.flag
local noop = function() end :: fun
local truthy = function()
    return true
end :: fun

local function spawn_update_for_state(state: State, update: fun?): RBXScriptConnection?
    if not update then
        return nil
    end
    if not not game and update then
        return game:GetService("RunService").Heartbeat:Connect(function(dt)
            update(state, dt)
        end)
    end
    return nil
end

---@note: `kid` already in [0x8000..0xffff]
-- stylua: ignore
-----------------------------
-- STM_ACTIONS
-----------------------------
local MIN_ACTION = 0xffff_001
local STM_ACTIONS = En.with_id "STM_ACTIONS" {
    Check = iota(MIN_ACTION),
    Enter = iota "",
    Update = iota "",
    Exit = iota "",
}
export type FSM_ACTIONS = typeof(STM_ACTIONS)

-- stylua: ignore
-----------------------------
-- STM_EVENTS
-----------------------------
local MIN_EVENT = 0xffff_f01
local STM_EVENTS = En.with_id "STM_EVENTS" {
    Entering = iota(MIN_EVENT),
    Entered = iota "",
    Exiting = iota "",
    Exited = iota "",
}
export type STM_EVENTS = typeof(STM_EVENTS)

-----------------------------
-- Module
-----------------------------
type StmObserver = (State, StmEventId, StmEventName) -> ()
export type Stm = {
    name: str,
    props: table,
    GetState: (self: Stm, StateId) -> State,
    CurrentState: (self: Stm) -> StateId,
    Connect: (self: Stm, StmObserver) -> Signal.Connection,
    AddStateAction: (self: Stm, StateId, ActionId, Handler) -> (), -- throws
    GoTo: (self: Stm, StateId, ...any) -> (), -- args passed to `Enter` after prev. StateId
    FireEvent: (self: Stm, EventId, ...any) -> (),
    AddEventHandler: (self: Stm, StateId, EventId, Handler) -> (),
    Transition: (self: Stm, from: StateId, event_id: EventId, to: StateId) -> (),
    AddToAll: (self: Stm, EventId, handler: Handler) -> (),
    AddToAllBut: (self: Stm, EventId, handler: Handler, ...StateId) -> (),
    ConnectSignals: (self: Stm, protocol: En) -> (),
    -- TODO: to StmInternal
    -- internal
    _maid: Disposer.Disposer,
    _states: { [StateId]: State, _current_state: State },
    _states_enum: En.Enum,
    _events_enum: En.Enum,
    _current_state: State,
    _subj: Signal.Subject<State, StmEventId, StmEventName>,
    _event_mapping: map<EventId, EventGuid>,
    _default_handlers: map<int, Handler>,
}

export type State = {
    id: StateId,
    name: StateName,
    stm: Stm,
    props: table,
    _handlers: { [StmEventId | EventId]: Handler },
}

-----------------------------
-- Stm
-----------------------------
local m = {}
m.__index = m

m.ACTIONS = STM_ACTIONS
m.EVENTS = STM_EVENTS

function m:__tostring()
    return self.id or "<STM>"
end
-------------------
-- State
-------------------
local State = {}
State.__index = State
function State.new(stm: Stm, id: StateId, name: StateName): State
    return table.freeze(setmetatable({
        stm = stm,
        id = id,
        name = name,
        props = {} :: table,
        _handlers = setmetatable({}, stm._default_handlers),
    }, State)) :: any
end

function State.__tostring(self: State)
    return self.stm.name .. ":" .. self.name
end

local START_STATE = State.new({ name = "*" } :: any, -1, "START")

-----------------------------
-- FSM
-----------------------------

export type StmConfig = {
    default_actions: { Handler },
    legacy_events: bool,
}

local DEFAULT_CONFIG = table.freeze {
    default_actions = {
        [STM_ACTIONS.Check] = truthy,
        [STM_ACTIONS.Enter] = noop,
        [STM_ACTIONS.Exit] = noop,
    },
    legacy_events = true,
}

function m.new(name: str, state_ids: En, event_ids: En, config: StmConfig?): Stm
    assert(En.is(state_ids))
    assert(En.is(event_ids))
    local conf = config or DEFAULT_CONFIG
    local self = {}
    self.name = name
    -- default handlers
    local default_handlers = {}
    default_handlers.__index = default_handlers
    for id, handler in pairs((conf :: StmConfig).default_actions) do
        assert(STM_ACTIONS:peek(id), "wrong id for default action")
        assert(type(handler) == "function", "not a function")
        default_handlers[id] = handler
    end
    self._default_handlers = default_handlers

    self._states = { _current_state = START_STATE } :: { [StateId]: State, _current_state: State }
    for state_name, state_id in state_ids:iterate() do
        self._states[state_id] = State.new(self :: any, state_id, state_name)
    end

    local maid = Disposer.new()
    self._maid = maid
    self._states_enum = state_ids
    self._events_enum = event_ids
    self._subj = (Signal.Subject() :: any) :: Signal.Subject<State, StmEventId, StmEventName>
    self._event_mapping = {} :: map<EventId, EventGuid>
    for event_name, event_id in event_ids:iterate() do
        local event_uid = roflake.gen()
        self._event_mapping[event_id] = event_uid
        -- stylua: ignore
        maid:Add(Signal.Connect(event_uid, function(...: any)
            local state = self._states._current_state
            if state == START_STATE then return end
            local handler = state._handlers[event_id]
            -- we can add/remove handlers runtime
            if handler then
                handler(state, ...)
            end
        end))
    end
    if conf.legacy_events then
        self._subj:Connect(function(state, _, stm_event_name)
            local event = tostring(state) .. ":" .. stm_event_name
            warn(state, event)
            Signal.Broadcast(event, state)
        end)
    end
    return table.freeze(setmetatable(self, m)) :: any
end

function m.AddStateAction(self: Stm, state_id, action_id, action: Handler)
    assert(self._states_enum:has(state_id), "there is no such state id")
    assert(STM_ACTIONS:peek(action_id), "not in STM_ACTION")
    local state = self._states[state_id]
    local handlers = state._handlers
    if rawget(handlers, action_id) then
        error(fmt("Error: '%s':'%s' already set.", state.name, STM_ACTIONS:get(action_id) :: str))
    end
    handlers[action_id] = action
end

function m.AddEventHandler(self: Stm, state_id, event_id, handler: Handler)
    assert(not STM_ACTIONS:peek(event_id), "Stm action id instead of event id")
    assert(self._states_enum:peek(state_id), "not a state id")
    assert(self._events_enum:peek(event_id), "not an event id")
    assert(type(handler) == "function" or type(handler) == "table" and handler.__call)
    local state = self._states[state_id]
    if state._handlers[event_id] then
        error(fmt("Error: '%s':'%s' already set.", state.name, self._events_enum[event_id]))
    end
    if DEBUG then
        print("  | add handler: " .. tostring(state) .. ":" .. self._events_enum[event_id] :: str)
    end
    state._handlers[event_id] = handler
end

function m.Transition(self: Stm, from_state_id, event_id, to_state_id)
    self:AddEventHandler(from_state_id, event_id, function(state, ...)
        self:GoTo(to_state_id, ...)
    end)
end

-- TODO:
-- 1. handle: CLIENT_STM:Transition(GS.INGAME, GE.GO_TO_ACHIEVEMENTS, GS.ACHIEVEMENTS) ...
-- 2. handle: CLIENT_STM:AddToAllBut(GE.BREAK_TO_INGAME, function(...) CLIENT_STM:GoTo(GS.INGAME, ...) end, GS.INGAME)

function m.AddToAll(self: Stm, event_id, handler: Handler)
    for _, state_id in self._states_enum:iterate() do
        self:AddEventHandler(state_id, event_id, handler)
    end
end

function m.AddToAllBut(self: Stm, event_id, handler: Handler, ...: StateId)
    local not_count = select("#", ...)
    if not_count == 0 then
        self:AddToAll(event_id, handler)
    else
        local not_set = {}
        for i = 1, not_count do
            not_set[select(i, ...)] = true
        end
        for _, state_id in self._states_enum:iterate() do
            if not_set[state_id] then
                continue
            end
            self:AddEventHandler(state_id, event_id, handler)
        end
    end
end

function m.CurrentState(self: Stm): StateId
    return self._states._current_state.id
end

function m:Connect(observer: StmObserver)
    return self._subj:Connect(observer)
end

function m.GoTo(self: Stm, state_id, ...)
    assert(self._states_enum[state_id])
    local to_state = self._states[state_id]
    local from_state = self._states._current_state

    if from_state == to_state then
        return
    end

    local check = to_state._handlers[STM_ACTIONS.Check] :: fun
    local ok = check()
    if not ok then
        if ok == nil then
            error(tostring(to_state) .. " STM_ACTIONS.Check handler do not return bool", 3)
        else
            if DEBUG then
                warn("INFO", to_state, "not ready")
            end
            return -- not ready
        end
    end

    local subject = self._subj
    -- exit previous state
    if from_state ~= START_STATE then
        subject:Update(from_state, STM_EVENTS:get_id_name(STM_EVENTS.Exiting))
        from_state._handlers[STM_ACTIONS.Exit](from_state)
        subject:Update(from_state, STM_EVENTS:get_id_name(STM_EVENTS.Exited))
    end
    -- start new state
    self._states._current_state = to_state
    subject:Update(to_state, STM_EVENTS:get_id_name(STM_EVENTS.Entering))
    to_state._handlers[STM_ACTIONS.Enter](to_state, ...)
    subject:Update(to_state, STM_EVENTS:get_id_name(STM_EVENTS.Entered))
    -- always cancels previous update task
    local update: (State, ...any) -> any? = to_state._handlers[STM_ACTIONS.Update]
    self._maid.update = spawn_update_for_state(to_state, update)
end

function m.FireEvent(self: Stm, event_id: EventId, ...: any)
    assert(self._events_enum[event_id])
    local event_guid = self._event_mapping[event_id]
    assert(event_guid, "mapping error")
    Signal.Broadcast(event_guid, ...)
end

function m.ConnectSignals(self: Stm, protocol: En)
    for re_name, re_id in protocol:iterate() do
        if self._events_enum:peek(re_name) then
            local event = self._events_enum:get(re_name) :: int
            self._maid:Add(Signal.Connect(re_id, function(...)
                self:FireEvent(event, ...)
            end))
        else
            warn(self, "drop", re_name)
        end
    end
end

-----------------------------
-- Quick test
-----------------------------
--[[
local _debug = DEBUG
---@type ETab
local S = En.new { Idle = 1, IdleWait = 2, Negotiate = 3, Wait = 4, Ready = 5, Stop = 6 }

---@type ETab
local E = En.new {
    AskForTrade = 1,
    AcceptATrade = 2,
    OfferItems = 3,
    RetractAnOffer = 4,
    DeclareSelfAsReady = 5,
    BrutallyCancelTheTrade = 6,
}

local stm = m.new("test", S, E)

stm:AddEventHandler(S.IdleWait, E.BrutallyCancelTheTrade, function(state, ...)
    -- print("~> Brutal?", ...)
    stm:GoTo(S.Idle)
end)

stm:AddToAllBut(E.RetractAnOffer, function(state)
    -- warn(state, "<~", (E :: any)[E.RetractAnOffer])
end, S.Idle)

stm:AddEventHandler(S.Idle, E.RetractAnOffer, function(state, ...)
    -- print("~> Retract?", ...)
    stm:GoTo(S.Idle)
end)

stm:Connect(function(state, event_id, ...)
    -- print(state, ...)
end)

stm:GoTo(S.Idle)
stm:GoTo(S.IdleWait)
stm:FireEvent(E.RetractAnOffer, "Retract!")

stm:FireEvent(E.BrutallyCancelTheTrade, "Brutal!")
stm:FireEvent(E.RetractAnOffer, "Retract!")
assert(stm:CurrentState() == S.Idle)
DEBUG = _debug
--]]
return m

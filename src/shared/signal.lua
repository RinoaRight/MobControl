---@ref: https://github.com/stravant/goodsignal/blob/master/src/ini t.lua

--!strict
-- MIT License
-- Copyright (c) 2022 Andrew Zhilin (https://github.com/zoon)

--[=[
    TODO:
    - Behaviors only, No subjects
    - Thread pool for fire events with waits
    - threads + Wait (https://github.com/Reselim/Flipper/blob/master/src/Signal.lua)
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
type u32 = uint
type i32 = int
type u8 = uint
type array<a> = { a }
type table = { [any]: any }
type packed = { n: int, [int]: any }
type map<k, v> = { [k]: v }
type fun = (...any) -> ...any
local fmt = string.format
local noop = function() end

type observer<a...> = (a...) -> ()

-- NB: `SignalModule` will be *error-type*  for sum type
export type Signal = any -- int | str | table | Instance

local DEBUG = true

local ROBLOX = not not game
local MAIN_THREAD = coroutine.running()

--[[ stylua: ignore]] script = script or require'script'
local Queue = require(script.Parent.queue)
local TaskPool = require(script.Parent.TaskPool)

local _subscriptions = {} :: { [Connection]: Signal }
local _observers = {} :: { [Signal]: { [Connection]: observer<...any> } }
local _throttle_period = {} :: { [Signal]: num }
local _throttle_tte = {} :: { [Signal]: num }
local _signals_trampoline = Queue.new() :: Queue.Queue<packed>
local _in_trampoline = false

export type Connection = {
    Disconnect: (self: Connection) -> (),
    IsConnected: (self: Connection) -> bool,
    __tostring: (self: Connection) -> str,
}

-- TODO: Wait
type SignalModule = {
    IsConnected: (Signal) -> bool,
    Connect: <a...>(Signal, observer<a...>) -> Connection,
    ConnectOnce: <a...>(Signal, observer<a...>) -> Connection,
    ConnectThrottled: <a...>(Signal, period: num, observer<a...>) -> Connection,
    Broadcast: <a...>(Signal, a...) -> (),
    Fire: <a...>(Signal, a...) -> (),
    Wait: (Signal, timeout: num?) -> ...any,
    DisconnectAll: (Signal) -> (),
    Subject: <a>(id: str?) -> Subject<a>,
    Behavior: <a...>(a...) -> Behavior<a...>,
}

local create_connection: () -> Connection
do
    local connection_mt = {}
    connection_mt.__index = connection_mt

    function connection_mt:__tostring()
        local signal = _subscriptions[self]
        return if signal then fmt("Connection: connected to <%*>", signal) else "Connection: disconnected"
    end

    function connection_mt:IsConnected()
        return not not _subscriptions[self]
    end

    function connection_mt:Disconnect()
        local signal = _subscriptions[self]
        if not signal then
            warn("already disconnected")
            return
        end
        _subscriptions[self] = nil
        local observers = _observers[signal]
        assert(observers, "something went wrong")
        observers[self] = nil
        if not next(observers) then
            _observers[signal] = nil
        end
    end

    create_connection = function()
        return (setmetatable({}, connection_mt) :: any) :: Connection
    end
end

-----------------------------
-- Module
-----------------------------
local m = {}
m.__index = m

---@static
function m.IsConnected(signal: Signal): bool
    assert(signal ~= m, "remove `:` from call")
    return not not _observers[signal]
end

---@static
function m.Connect<a...>(signal: Signal, observer: observer<a...>): Connection
    if signal == nil then
        error("'signal' can't be a `nil`", 2)
    end
    assert(signal ~= m, "remove `:` from call")
    if not _observers[signal] then
        _observers[signal] = {}
    end
    local observers = _observers[signal]
    if DEBUG then
        for _, o in pairs(observers) do
            -- NOTE: `==` sometimes gives false positive with `luau -O1`
            if rawequal(o, observer) then
                warn(debug.traceback("WARN: this observer connects twice", 2))
            end
        end
    end
    local connection = create_connection()
    observers[connection] = observer :: any
    _subscriptions[connection] = signal
    return connection
end

function m.ConnectThrottled<a...>(signal: Signal, period: num, observer: observer<a...>): Connection
    if signal == nil then
        error("'signal' can't be a `nil`", 2)
    end
    assert(signal ~= m, "remove `:` from call")
    if period > 0 then
        -- TODO: throttle per connection
        if _throttle_period[signal] and _throttle_period[signal] ~= period then
            warn("(!) override throttle period: ", _throttle_period[signal], "->", period)
        end
        _throttle_period[signal] = period
    end
    if not _observers[signal] then
        _observers[signal] = {}
    end
    local observers = _observers[signal]
    if DEBUG then
        for _, o in pairs(observers) do
            -- NOTE: `==` sometimes gives false positive with `luau -O1`
            if rawequal(o, observer) then
                warn(debug.traceback("WARN: this observer connects twice", 2))
            end
        end
    end
    local connection = create_connection()
    observers[connection] = observer :: any
    _subscriptions[connection] = signal
    return connection
end

function m.ConnectOnce<a...>(signal: Signal, observer: observer<a...>): Connection
    local connection
    connection = m.Connect(signal, function(...: a...)
        connection:Disconnect()
        observer(...)
    end)
    return connection
end

function m.DisconnectAll(signal: Signal)
    assert(signal, "no signal")
    local observers = _observers[signal]
    _observers[signal] = nil
    _throttle_period[signal] = nil
    _throttle_tte[signal] = nil
    if not observers then
        return
    end
    local connection: any, observer = next(observers)
    while observer ~= nil do
        observers[connection] = nil
        _subscriptions[connection] = nil
        connection, observer = next(observers)
    end
end

-----------------------------
-- DO BROADCAST
-----------------------------
local do_broadcast: <a...>(signal: Signal, a...) -> ()
do
    local _temp_observers = {}

    local function do_broadcast_task<a...>(signal: Signal, ...: a...)
        local event_observers = _observers[signal]
        if not event_observers then
            return
        end
        -- throttling
        if _throttle_period[signal] and (_throttle_tte[signal] or 0) > os.clock() then
            return
        end
        assert(#_temp_observers == 0)
        for _conn, observer in pairs(event_observers) do
            table.insert(_temp_observers, observer)
        end
        for _, o in ipairs(_temp_observers) do
            local observer = (o :: any) :: (a...) -> any;
            (TaskPool.call :: fun)(observer, ...)
        end
        table.clear(_temp_observers)
        if _throttle_period[signal] then
            _throttle_tte[signal] = os.clock() + _throttle_period[signal]
        end
    end

    local function do_broadcast_immediate<a...>(signal: Signal, ...: a...)
        local event_observers = _observers[signal]
        if not event_observers then
            return
        end
        -- throttling
        if _throttle_period[signal] and (_throttle_tte[signal] or 0) > os.clock() then
            return
        end
        assert(#_temp_observers == 0)
        for _conn, observer in pairs(event_observers) do
            table.insert(_temp_observers, observer)
        end
        for _, o in ipairs(_temp_observers) do
            local observer = (o :: any) :: (a...) -> any
            local ok, err = pcall(observer, ...)
            if not ok then
                warn("Broadcast ERROR:", signal, observer, err)
            end
        end
        table.clear(_temp_observers)
        if _throttle_period[signal] then
            _throttle_tte[signal] = os.clock() + _throttle_period[signal]
        end
    end
    -- fallback to immediate scheduling for vanilla luau
    do_broadcast = if ROBLOX then do_broadcast_task else do_broadcast_immediate
end
---@static
function m.Broadcast<a...>(signal: Signal, ...: a...)
    if signal == nil then
        error("'signal' can't be a `nil`", 2)
    end
    assert(signal ~= m, "remove `:` from Broadcast call")
    if _in_trampoline then
        local package = table.pack(signal, ...)
        _signals_trampoline:Push(package)
        return
    else
        _in_trampoline = true
        do_broadcast(signal, ...)
    end
    while _signals_trampoline:Peek() do
        local package = _signals_trampoline:Pop() :: packed
        do_broadcast(table.unpack(package, 1, package.n))
    end
    _in_trampoline = false
end

---@deprecated
m.Fire = m.Broadcast

if ROBLOX then
    function m.Wait(signal: Signal, timeout: num?): ...any
        local waiting_thread = coroutine.running()
        assert(waiting_thread ~= MAIN_THREAD)
        local connection, timeout_connection
        connection = m.Connect(signal, function(...)
            connection:Disconnect()
            if timeout_connection then
                task.cancel(timeout_connection)
            end
            local ok, err = coroutine.resume(waiting_thread, ...)
            if not ok then
                warn("Signal.Wait:Error:", err)
            end
        end)
        if timeout then
            timeout_connection = task.delay(timeout :: num, function()
                connection:Disconnect()
                local ok, err = coroutine.resume(waiting_thread)
                if not ok then
                    warn("Signal.Wait:Error (timeout thread):", err)
                end
            end)
        end
        return coroutine.yield(waiting_thread)
    end
else
    function m.Wait(signal: Signal, timeout: num?)
        error("immediate events can't Wait")
    end
end

-----------------------------
-- Subject
-----------------------------
local Subject = {}
Subject.__index = Subject

export type Subject<a...> = {
    Connect: (self: Subject<a...>, observer<a...>) -> Connection,
    DisconnectAll: (self: Subject<a...>) -> (),
    Update: (self: Subject<a...>, a...) -> (),
    Wait: (self: Subject<a...>, timeout: num?) -> Subject<a...>,
}

do
    local function new<a...>(id: str?): Subject<a...>
        return setmetatable({ id = id }, Subject) :: any
    end
    m.Subject = new
end

function Subject:__tostring()
    local inner = self :: any
    return if inner.id then "Subject: " .. inner.id else "Subject"
end

function Subject:Connect<a...>(callback: observer<a...>)
    return m.Connect(self, callback :: any)
end

function Subject:Update<a...>(...: a...)
    m.Broadcast(self, ...)
end

function Subject:Wait(timeout: num?)
    return m.Wait(self, timeout)
end

function Subject:DisconnectAll()
    m.DisconnectAll(self)
end

-- maid alias
Subject.Disconnect = Subject.DisconnectAll

-----------------------------
-- Behavior
-----------------------------
local Behavior = {}
Behavior.__index = Behavior

export type Behavior<a...> = {
    Connect: (self: Behavior<a...>, observer<a...>) -> Connection,
    DisconnectAll: (self: Behavior<a...>) -> (),
    Update: (self: Behavior<a...>, a...) -> (),
    UpdateIfDistinct: (self: Behavior<a...>, a...) -> (),
    ---@note: hacky method to push state to observers (e.g. you mutated ref-type)
    ForceUpdate: (self: Behavior<a...>) -> (),
}

do
    local function new<a...>(...: a...): Behavior<a...>
        local self = table.pack(...)
        return setmetatable(self, Behavior) :: any
    end
    m.Behavior = new
end

function Behavior.Connect<a...>(self: Behavior<a...>, observer: observer<a...>)
    local obs = (observer :: any) :: fun
    local state = self :: table
    local connection = m.Connect(self, obs)
    local ok, err = pcall(obs, table.unpack(state, 1, state.n))
    if not ok then
        local msg = debug.traceback("ERROR: " .. err, 2)
        if DEBUG then
            error(msg)
        else
            warn(msg)
        end
    end
    return connection
end

function Behavior:DisconnectAll()
    m.DisconnectAll(self)
end

-- maid alias
Behavior.Disconnect = Behavior.DisconnectAll

function Behavior.Update<a...>(self: Behavior<a...>, ...: a...)
    local state = self :: table
    local n = select("#", ...)
    assert(state.n == n, "args count mismatch")
    for i = 1, n do
        state[i] = select(i, ...)
    end
    m.Broadcast(self, ...)
end

function Behavior.UpdateIfDistinct<a...>(self: Behavior<a...>, ...: a...)
    local state = self :: table
    local n = select("#", ...)
    assert(state.n == n, "args count mismatch")
    local distinct = false
    -- stylua: ignore
    for i=1, n do
        if state[i] == (select(i, ...)) then continue end
        distinct = true
        break
    end
    if distinct then
        for i = 1, n do
            state[i] = select(i, ...)
        end
        m.Broadcast(self, ...)
    end
end

function Behavior.ForceUpdate<a...>(self: Behavior<a...>)
    local state = self :: table
    m.Broadcast(self, table.unpack(state, 1, state.n))
end

-----------------------------
-- Quick test
-----------------------------
local function assert_cleanup(hint: str?)
    local h = hint or ""
    if next(_subscriptions) then
        error(h .. "_subscriptions are not cleaned up", 2)
    end
    if next(_observers) then
        error(h .. "_observers are not cleaned up", 2)
    end
end

local function test_event_listener()
    local sub = m.Connect("x", noop)
    assert(sub:IsConnected())
    sub:Disconnect()
    assert(not sub:IsConnected())
    assert_cleanup()
    print("  test_event_listener -- ok")
end

local function test_signals()
    local out = {}
    local ev1 = m.Connect("A", function()
        m.Broadcast("B", "A")
        m.Broadcast("C", "A")
        out[#out + 1] = "A"
    end)
    local ev2 = m.Connect("B", function()
        m.Broadcast("C", "B")
        out[#out + 1] = "B"
    end)
    local ev3 = m.Connect("C", function()
        out[#out + 1] = "C"
    end)
    m.Broadcast("A")
    assert(out[1] == "A" and out[2] == "B" and out[3] == "C" and out[4] == "C")
    assert(ev1:IsConnected())
    assert(ev2:IsConnected())
    assert(ev3:IsConnected())
    ev1:Disconnect()
    ev2:Disconnect()
    ev3:Disconnect()
    assert_cleanup()
    --
    print("  test_signals -- ok")
end

do
    local c = 0
    local connection = m.ConnectOnce("A", function(_)
        c += 1
    end)
    m.Broadcast("A", "hello")
    m.Broadcast("A", "hello")
    m.Broadcast("A", "hello")
    assert(not connection:IsConnected())
    assert(c == 1)
end

do
    local c = 0
    local connection = m.ConnectThrottled("A", 0.00001, function(_)
        c += 1
    end)
    m.Broadcast("A", "hello")
    m.Broadcast("A", "hello")
    m.Broadcast("A", "hello")
    assert(c == 1)
    repeat
        m.Broadcast("A", "hello")
    until c > 1
    assert(c > 1)
    connection:Disconnect()
end

local function test_recursion()
    local sub1, sub2
    local out = {}
    local function insert(tag: str, x, y)
        table.insert(out, tag)
        table.insert(out, x)
        table.insert(out, y)
    end
    sub1 = m.Connect("A", function(x, y)
        insert("sub1-1", x, y)
        sub1:Disconnect()
        sub1 = m.Connect("A", function(a, b)
            insert("sub1-2", a, b)
            assert(a and b)
        end)
        m.Broadcast("A", 11, 22)
    end)
    sub2 = m.Connect("A", function(x, y)
        insert("sub2-1", x, y)
        sub2:Disconnect()
        sub2 = m.Connect("A", function(a, b)
            insert("sub2-2", a, b)
            assert(a and b)
        end)
        m.Broadcast("A", 33, 44)
    end)
    m.Broadcast("A", 1, 2)
    sub1:Disconnect()
    sub2:Disconnect()
    assert_cleanup()
    for i = 1, #out, 6 do
        local t1, a1, b1, t2, a2, b2 = table.unpack(out, i, i + 5)
        -- print(t1, a1, b1, t2, a2, b2)
        assert(t1 and t2)
        assert(a1 == a2)
        assert(b1 == b2)
    end
    --
    print("  test_recursion -- ok")
end

local function test_subjects()
    local subject = m.Subject() :: Subject<int, int, int>
    local res1 = {}
    local res2 = {}
    local count = 0
    local function observer(t: array<int>): (int, int, int) -> ()
        return function(x: int, y: int, z: int)
            count = count + 1
            t[1] = x
            t[2] = y
            t[3] = z
        end
    end
    local sub1 = subject:Connect(observer(res1))
    assert(#res1 == 0)
    local sub2 = subject:Connect(observer(res2))
    assert(#res2 == 0)
    subject:Update(1, 2, 3)
    assert(#res1 == 3)
    assert(#res2 == 3)
    sub2:Disconnect()
    subject:Update(11, 22, 33)
    assert(res1[1] == 11)
    assert(res2[1] == 1)
    subject:DisconnectAll()
    assert(not sub1:IsConnected())
    assert_cleanup()
    print("  test_subjects -- ok")
end

local function test_behaviors()
    local beh = m.Behavior(1, 2, 3)
    local res1 = {}
    local res2 = {}
    local count = 0
    local function observer(t)
        return function(x, y, z)
            count = count + 1
            t[1] = x
            t[2] = y
            t[3] = z
        end
    end
    local sub1 = beh:Connect(observer(res1))
    assert(#res1 == 3 and res1[1] == 1)
    beh:Update(11, 22, 33)
    assert(#res1 == 3 and res1[2] == 22)
    local sub2 = beh:Connect(observer(res2))
    assert(#res2 == 3 and res2[3] == 33)
    sub2:Disconnect()
    assert(not sub2:IsConnected())
    beh:Update(33, 44, 55)
    assert(#res2 == 3 and res2[3] == 33)
    assert(#res1 == 3 and res1[3] == 55)
    sub1:Disconnect()
    assert(not sub1:IsConnected())
    beh:Update(0, 0, 0)
    assert(#res1 == 3 and res1[3] == 55)
    beh:DisconnectAll()
    local c = count
    res1 = {}
    beh = m.Behavior(0, 0, 0)
    local _ = beh:Connect(observer(res1))
    assert(count == c + 1)
    beh:UpdateIfDistinct(0, 0, 0)
    assert(count == c + 1)
    beh:DisconnectAll()
    assert_cleanup()
    --
    print("  test_behaviors -- ok")
end

-- test
local function self_test()
    print("[Signals]")
    test_event_listener()
    test_signals()
    test_recursion()
    test_subjects()
    test_behaviors()
    warn("[Signal -- ok]")
end

self_test()

if ROBLOX then
    local SIG = "___%123%___"
    local t1, t2
    TaskPool.call(function()
        t1 = os.clock()
        m.Wait(SIG)
        t2 = os.clock()
        local dt = t2 - t1
        assert(dt > 0.5, "test fail")
    end)
    TaskPool.delay(1, function()
        m.Fire(SIG)
    end)
    local subj = m.Subject() :: Subject<str>
    local dead_subj = m.Subject()
    task.spawn(function()
        subj:Wait()
    end)
    local c = 0
    task.spawn(function()
        dead_subj:Wait(1)
        c += 1
    end)
    task.delay(2, function()
        assert(c == 1, "test fail")
    end)
    subj:Update("")
end

return (m :: any) :: SignalModule

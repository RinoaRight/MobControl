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
type u32 = uint
type i32 = int
type u8 = uint
type array<a> = { a }
type table = { [any]: any }
type map<k, v> = { [k]: v }
type fun = (...any) -> ...any
local fmt = string.format

local DBG = {} :: {[thread]: str}

-----------------------------
-- Connection
-----------------------------
export type Connection = {
    Disconnect: (self: Connection) -> (),
    IsConnected: (self: Connection) -> bool,
    __tostring: (self: Connection) -> str,
}

local _thread_to_connection: { [thread]: Connection } = {}
local _connection_to_thread: { [Connection]: thread } = {}

local function remove_thread(thread)
    local connection = _thread_to_connection[thread]
    if connection then
        _connection_to_thread[connection] = nil
    end
    _thread_to_connection[thread] = nil
end

local create_connection: (thread) -> Connection
do
    local connection_mt = {}
    connection_mt.__index = connection_mt

    function connection_mt:__tostring()
        local thread = _connection_to_thread[self]
        return if thread then fmt("Connection: connected to <%*>", thread) else "Connection: disconnected"
    end

    function connection_mt:IsConnected()
        return not not _connection_to_thread[self]
    end

    -- TODO: connection:CanDisconnect()
    -- TODO: spin wait to disconnect Suspended

    function connection_mt:Disconnect()
        local thread = _connection_to_thread[self]
        if not thread then -- already disconnected
            return
        end
        remove_thread(thread)
        local status = coroutine.status(thread)
        if status == "normal" or status == "running" then
            error(debug.traceback(("Can't close: '"..  status .. "' thread")))
        end
        local ok, err: str? = pcall(task.cancel, thread)
        if not ok then
            error(debug.traceback("Cancellation error: " .. err :: str))
        end
    end

    create_connection = function(thread)
        local connection = table.freeze(setmetatable({}, connection_mt)) :: any
        _connection_to_thread[connection] = thread
        _thread_to_connection[thread] = connection
        return connection
    end
end

-----------------------------
-- Module
-----------------------------
local MAX_POOL = 16
local m = {}
m.__index = m
m.MAIN_THREAD = coroutine.running()

local acquire: () -> thread
do
    local _thread_pool = {} :: { thread }
    local _allocated = 0

    m.allocated = function()
        return _allocated, #_thread_pool, MAX_POOL
    end

    local function release(thread)
        if #_thread_pool < MAX_POOL then
            table.insert(_thread_pool, thread)
            _allocated -= 1
        end
    end

    local function call(fn: fun, ...: any)
        local thread = coroutine.running()
        assert(thread ~= m.MAIN_THREAD)
        local ok, err = pcall(fn, ...)
        if not ok then
            warn("ERROR:", thread, err, DBG[thread] or "<?>")
        end
        remove_thread(thread)
        release(thread)
    end

    local function worker(fn, ...)
        call(fn, ...)
        while true do
            call(coroutine.yield())
        end
    end

    acquire = function()
        local thread: thread
        if #_thread_pool == 0 then
            thread = coroutine.create(worker)
            _allocated += 1
        else
            thread = table.remove(_thread_pool) :: thread
        end
        if _G.__DEV__ then
            DBG[thread] = debug.traceback("traceback:")
        end
        return thread
    end
end

---@summary: spawn without connection
function m.call(fn: fun, ...: any): ()
    assert(type(fn) == "function", "arg#1 must be a function")
    local thread = acquire()
    task.spawn(thread, fn, ...)
end

function m.spawn(fn: fun, ...: any): Connection
    assert(type(fn) == "function", "arg#1 must be a function")
    local thread = acquire()
    local connection = create_connection(thread)
    task.spawn(thread, fn, ...)
    return connection
end

function m.delay(delay: num, fn: fun, ...: any): Connection
    assert(type(fn) == "function", "arg#2 must be a function")
    local thread = acquire()
    local connection = create_connection(thread)
    task.delay(delay, thread, fn, ...)
    return connection
end

function m.defer(fn: fun, ...: any): Connection
    assert(type(fn) == "function", "arg#1 must be a function")
    local thread = acquire()
    local connection = create_connection(thread)
    task.defer(thread, fn, ...)
    return connection
end

local ROBLOX = not not game
if not ROBLOX then
    warn("[TaskPool -- can't be tested in luau]")
    return m
end

-----------------------------
-- Quick test
-----------------------------
do
    local c = 0
    m.spawn(function()
        task.wait(0.1)
        c += 1
    end)
    m.delay(2, function()
        c += 1
    end)
    local con = m.delay(3, function()
        c += 1
    end)
    task.delay(1, function()
        con:Disconnect()
        assert(c == 1)
    end)
    task.delay(3, function()
        assert(c == 2)
        warn("[TaskPool -- ok]")
    end)
end

return m

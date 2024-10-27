--!strict
--!native
-- MIT License
-- Copyright (c) 2022 Andrew Zhilin (https://github.com/zoon)

--[=[
    Spawn periodic job.
    Usage:
    ```lua
    local S = require("supervisor")
    local handle = S.new(function(dt) print(dt), 3)
    ..
    S.cancel(handle)
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
type uid = str

type worker = (dt: num) -> ()

--[[ stylua: ignore]] script = script or require'script'
local roflake = require(script.Parent.roflake)

local SUPERVISOR_DEFAULT_PERIOD = 1.0
-----------------------------
-- Module
-----------------------------

type loop_record = {
    worker: worker,
    working: bool,
    id: str,
    name: str?,
    period: num,
    thread: thread?,
    restarts: int,
}

export type supervisor = {
    name: (supervisor, id: uid?) -> str,
    start: (supervisor, worker, period: num, name: str?) -> uid,
    cancel: (supervisor, uid) -> bool,
    _super_id: uid,
    _name: str?,
    _loops: map<uid, loop_record>,
}

local function restart(self: supervisor, r: loop_record)
    r.restarts += 1
    print("restart", r.id, r.restarts)
    local function loop()
        local thread = task.defer(function()
            local last_time = os.clock()
            while r.working do
                task.wait(r.period)
                local now = os.clock()
                local ok, err: str? = pcall(r.worker, now - last_time)
                last_time = now
                if not ok then
                    error("Loop error@" .. self:name(r.id) .. "(" .. tostring(r.restarts) .. ")\n" .. tostring(err))
                end
            end
            self._loops[r.id] = nil
        end)
        return thread
    end
    r.thread = loop()
end

local m = {}
m.__index = m

local supervisor = {}
supervisor.__index = supervisor

function m.create(period: num?, name: str?): supervisor
    local self = {
        _loops = {} :: map<uid, loop_record>,
        _name = name,
    }
    self._super_id = supervisor.start(self :: any, function(dt)
        for id, r in self._loops do
            if r.thread and coroutine.status(r.thread) == "dead" then
                restart(self :: any, r)
            elseif not r.thread then
                print("no thread", r.id)
            end
        end
    end, period or SUPERVISOR_DEFAULT_PERIOD)
    return table.freeze(setmetatable(self, supervisor)) :: any
end

function supervisor.name(self: supervisor, id: uid?)
    local r = self._loops[id or self._super_id]
    if not r then
        return "<?>"
    end
    return if r.name then r.id .. "(" .. r.name .. ")" else r.id
end

function supervisor.start(self: supervisor, worker: worker, period: num?, name: str?)
    local r: loop_record = {
        worker = worker,
        working = true,
        period = period or 0,
        id = roflake.gen(),
        restarts = -1,
        name = name,
    }
    self._loops[r.id] = r
    restart(self, r)
    return r.id
end

function supervisor.cancel(self: supervisor, loop_id: uid): bool
    local rec = self._loops[loop_id]
    self._loops[loop_id] = nil
    if not rec then
        return false
    end
    rec.working = false
    local thread = rec.thread
    rec.thread = nil
    if thread and coroutine.status(thread) ~= "running" then
        task.cancel(thread)
    end
    return true
end

-----------------------------
-- Quick test
-----------------------------
--[[
do
    if game and game:GetService("RunService"):IsServer() then
        local S = m.create(1)
        local count = 0
        local h = S:start(function(dt)
            print("========")
            count += dt
            if count > 6 then
                print(count)
                count = 0
                error("halt!")
            end
        end, 3, "halt test")
        local h2
        h2 = S:start(function(dt)
            local ok = S:cancel(h)
            if not ok then
                print("exit from", S:name(h2))
                return
            end
            print("cancel", h, ok)
        end, 13, "stopper test")
    end
end
--]]

warn("[supervisor] -- ok")
return m

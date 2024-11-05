--!strict
-- MIT License
-- Copyright (c) 2022 Andrew Zhilin (https://github.com/zoon)

-- ref: https://github.com/Fraktality/Destructor/blob/main/Destructor.lua

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

local ROBLOX = not not game
local ERR_PREFIX = "Error: Disposer: "

-- NB: `Disposer` will be *error-type*  for sum type
export type disposable = Instance | RBXScriptConnection | fun | table | thread
type inner = map<any, disposable?>

--[[ stylua: ignore]] script = script or require'script'
local roflake = require(script.Parent.roflake)

local cant_dispose = function(val: any)
    warn("Can't dispose: ", typeof(val))
end

local function cleanup_table(t)
    if t.Destroy then
        t.Destroy(t)
    elseif t.Disconnect then
        t.Disconnect(t)
    elseif t.Cancel then
        t.Cancel(t)
    end
end

local function cleanup_function(f)
    local ok, err = pcall(f)
    if not ok then
        warn(ERR_PREFIX .. "function call was erroneous:", err)
    end
end

local disconnect: (RBXScriptConnection) -> () = cant_dispose
local destroy: (Instance) -> () = cant_dispose
if ROBLOX then
    disconnect = Instance.new("BindableEvent").Event:Connect(function() end).Disconnect
    destroy = game.Destroy
end

local function task_cancel(thread: thread)
    if coroutine.status(thread) == "running" then
        task.defer(task.cancel, thread)
    else
        local ok, err = pcall(task.cancel :: any, thread)
        if not ok then
            warn(ERR_PREFIX .. err, coroutine.status(thread))
        end
    end
end

local DESTRUCTORS = setmetatable({
    ["function"] = cleanup_function,
    ["Instance"] = destroy,
    ["RBXScriptConnection"] = disconnect,
    ["table"] = cleanup_table,
    ["thread"] = task_cancel,
}, { __index = cant_dispose })

-----------------------------
-- Module
-----------------------------
local m = {}
local DATA_KEY = newproxy(true)
-- stylua: ignore
getmetatable(DATA_KEY).__tostring = function() return "`(DATA_KEY)" end

export type Disposer = {
    [str]: disposable?,
    DATA_KEY: inner,
    Add: (self: Disposer, disposable) -> disposable,
    AddWithHandle: (self: Disposer, disposable) -> (disposable, str),
    Destroy: (self: Disposer) -> (),
    iterate: (self: Disposer) -> (Disposer?, any?) -> (any?, disposable?),
    __index: (self: Disposer, any: any) -> any,
    Get: (self:Disposer, key:any) -> any
}

function m.Get(self: Disposer, key: any):any
    return self[key] :: any
end

local function dispose(d: disposable?)
    if d == nil then
        return
    end
    local ok, err = pcall(DESTRUCTORS[typeof(d)], d)
    if not ok then
        warn("error during disposing of", typeof(d), err)
    end
end

function m.Destroy(self: Disposer)
    local inner = self[DATA_KEY] :: inner
    local k, d = next(inner)
    while d ~= nil do
        inner[k] = nil
        dispose(d)
        k, d = next(inner)
    end
end

function m.new(bind_to: Instance?): Disposer
    local inner = {} :: inner
    local self = (setmetatable({ [DATA_KEY] = inner }, m) :: any) :: Disposer
    if bind_to then
        local destroying_evt = (bind_to :: Instance).Destroying
        table.insert(
            inner,
            destroying_evt:Connect(function()
                self:Destroy()
            end)
        )
    end
    return self
end

function m.Add(self: Disposer, disposable: disposable): disposable
    assert(disposable ~= nil, "disposable is nil")
    table.insert(self[DATA_KEY] :: table, disposable)
    return disposable
end

function m.AddWithHandle(self: Disposer, disposable: disposable): (disposable, str)
    assert(disposable ~= nil, "disposable is nil")
    local handle = roflake.gen()
    local inner = self[DATA_KEY] :: inner
    inner[handle] = disposable
    return disposable, handle
end

function m.__newindex(self: Disposer, k: any, value: disposable?): ()
    if type(k) == "number" then
        error("Disposer key can't be a number", 2)
    end
    local inner = self[DATA_KEY] :: inner
    local old = inner[k]
    if old == value then
        return
    end
    inner[k] = value
    dispose(old)
end

function m.iterate(self: Disposer)
    local inner = self[DATA_KEY] :: inner
    return function(_, k)
        return next(inner, k)
    end, nil
end

function m.__index(self: Disposer, key)
    return rawget(m, key) or rawget(self[DATA_KEY] :: table, key)
end

m.dispose = dispose

-----------------------------
-- Quick test
-----------------------------

do -- basic
    local dumper = m.new()
    local x = 0
    local callback = function()
        x += 1
    end
    local res = dumper:Add(callback)
    assert(res == callback)
    assert(x == 0)
    dumper.test = callback -- __newindex
    dumper.test = callback -- should be ignored
    assert(dumper.test == callback) -- __index
    assert(x == 0, x)
    local c = 0
    for k, v in dumper:iterate() do
        c += 1
    end
    assert(c == 2)
    dumper:Destroy()
    assert(x == 2, x)
end

do
    local f, uid = m.new():AddWithHandle(function() end)
    assert(type(f) == "function")
    assert(roflake.is(uid))
end

do -- recursion
    local dumper = m.new()
    local inner1, inner2
    dumper:Add {
        Destroy = function()
            inner1 = true
            dumper.new_field = function()
                inner2 = true
            end
        end,
    }
    dumper:Destroy()
    assert(inner1)
    assert(inner2)
end

do
    local dumper = m.new()
    local count = 0
    dumper.a = function()
        count += 1
        dumper:Destroy()
    end
    dumper.b = function()
        count += 1
    end
    dumper.a = nil
    assert(count == 2)
end

if _G.__DEV__ and game and game:GetService("RunService"):IsServer() then
    local p1 = Instance.new("Part")
    p1.Name = "aaa"
    local p2 = Instance.new("Part")
    p2.Name = "aaa"
    local count = 0
    local dis = m.new()
    dis["aaa"] = p1
    p1.Destroying:Connect(function(x) print(x);count +=1 end)
    dis["aaa"] = p2
    task.defer(function()
        assert(count == 1, "=== Disposer test fail")
    end)
end

warn("[disposer -- ok]")

return m

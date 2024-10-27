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
type id = int
type array<a> = { a }
type table = { [any]: any }
type props<a> = { [str]: a }
type map<k, v> = { [k]: v }
type fun = (...any) -> ...any
local _fmt = string.format

--[[ stylua: ignore]] script = script or require'script'
local lpack = require(script.Parent.lpack)

-----------------------------
-- Module
-----------------------------
local m = {}
m.__index = m

local M = {} :: map<id, table>

local function make_index(def)
    return function(self, k)
        local idx = rawget(def, k)
        if not idx then
            error(`no such field: '{k}'`, 2)
        end
        if type(idx) == "number" then
            return rawget(self, idx)
        else
            return idx -- not an index
        end
    end
end

local function readonly(_)
    error("struct is read-only")
end

local function _make_newindex(def)
    return function(self, k, v)
        local idx = rawget(def, k)
        local frozen = table.isfrozen(self)
        if type(idx) == "number" then
            if frozen then
                error("struct is read-only", 2)
            else
                rawset(self, idx, v)
            end
        elseif frozen then
        else
            error(`no such field '{k}'`, 2)
        end
    end
end

-- stylua: ignore
local function check_def(def: map<str, int>, n:int)
    local min, max = math.huge, -math.huge
    for k, v in def do
        if type(k) ~= "string" then error(`def contain a non string key: '{k}'`, 3) end
        if type(v) ~= "number" or bit32.bor(v) ~= v then error(`def contain a non integer value: '{v}'`, 3) end
        min, max = math.min(min, v), math.max(max, v)
    end
    if min ~= 1 then error("first index should be 1", 3) end
    if max ~= n then error(`last index should be {n}`, 3) end
end

-- NOTE: in luau the _eq metamethod only gets called if the two objects have the
-- same metatable.
--0@perf: ~10..100ns
local function struct_eq(l: any, r: any)
    if rawequal(l, r) then
        return true
    end
    for i = 1, rawlen(l) - 1 do
        if l[i] ~= r[i] then
            return false
        end
    end
    return true
end

local function set_props(self, mt, props)
    for k, v in props do
        local idx = rawget(mt, k)
        if idx then
            self[idx] = v
        elseif _G.__DEV__ then
            warn(`(!) struct has no such key: '{k}' {debug.traceback("", 2)}`)
        end
    end
end

function m.define<A>(tag: id)
    type S = A & { set: (self: A, props: props<num>) -> A } & { num }
    return function(def: A): ((props: A?) -> S, (o: any) -> S)
        local mt = def :: any
        local n = 0
        for _, _ in mt do
            n += 1
        end
        check_def(mt, n)
        -- after check! add reversed keys for pp
        for k, v in mt do
            mt[v] = k
        end
        mt.__index = make_index(mt)
        mt.__newindex = readonly
        mt.__len = function(_)
            return n
        end
        mt.__eq = struct_eq
        mt.set = function(self, props)
            local o = table.clone(self :: any)
            set_props(o, mt, props)
            return table.freeze(setmetatable(o, mt)) :: any
        end
        M[tag] = table.freeze(mt)
        return function(props) -- ctor
            local self = table.create(n + 1, 0)
            self[n + 1] = tag
            if props then
                set_props(self, mt, props)
            end
            return table.freeze(setmetatable(self, mt)) :: any
        end, function(o) -- cast
            local ok = m.is(o)
            if not ok then
                error(`wrong type: {type(o)}`)
            end
            return o :: S
        end
    end
end

function m.is(o: any)
    if type(o) == "table" then
        local mt = getmetatable(o)
        if not mt then
            return false
        end
        local tag = o[#o + 1] -- by creation
        return tag and M[tag] == mt
    end
    return false
end

function m.pack(o)
    return lpack.pack(o)
end

function m.unpack<a>(s: str)
    local o = lpack.unpack(s)
    if type(o) ~= "table" or #o <= 1 then
        error(`not a struct: type:{type(o)}`, 2)
    end
    local tag = o[#o]
    local mt = M[tag]
    if not mt or not rawget(mt, "__index") then
        error(`no suitable metatable`, 2)
    end
    return table.freeze(setmetatable(o, mt))
end

function m.unpack_typed<A>(s: str, cast: (any) -> A)
    local o = lpack.unpack(s)
    if type(o) ~= "table" or #o <= 1 then
        error(`not a struct: type:{type(o)}`, 2)
    end
    local tag = o[#o]
    local mt = M[tag]
    if not mt or not rawget(mt, "__index") then
        error(`no suitable metatable`, 2)
    end
    return (table.freeze(setmetatable(o, mt)) :: any) :: A
end

do
    local _current: int
    function m.iota(from: any?)
        if type(from) == "number" then
            assert(from == 1, "first index in struct must be 1")
            _current = 1
        else
            _current += 1
        end
        return _current
    end
end

-----------------------------
-- Quick test
-----------------------------
_G.__DEV__ = not game
do
    local cr, cast = m.define(901) {
        One = 1,
        Two = 2,
        Three = 3,
    }
    local x = cr { One = 11, Two = 22, Three = math.pi }
    assert(m.is(x))
    local ser = m.pack(x)
    -- print(#ser)
    local xx = m.unpack_typed(ser, cast)
    assert(m.is(xx))
    assert(xx.Two == 22)
    assert(math.abs(xx.Three - math.pi) < 1e-6)
    assert(not pcall(function()
        xx.Two = 14
    end))
    local y = x:set { One = 42, Three = 11 }
    -- print(y.One)
    assert(x ~= y)
    local z = cr { One = 1, Two = 2, Three = x.Three }
    assert(z.One == 1)

    local a = cr { One = 1, Two = 2, Three = 3 }
    local b = cr { One = 1, Two = 2, Three = 3 }
    assert(a == b)
end

warn("[struct -- ok]")
return m

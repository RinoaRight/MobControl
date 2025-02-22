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

--[[ stylua: ignore]] script = script or require'./script'
local lpack = require(script.Parent.lpack)

-----------------------------
-- Module
-----------------------------
local m = {}
m.__index = m

-- map of struct id to corresponding struct's metatable
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
    type S = A & { set: (self: S, props: props<num>) -> S }-- & { num }
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
        mt.set = function(self: S, props)
            local o = table.clone(self :: any)
            set_props(o, mt, props)
            return (table.freeze(setmetatable(o, mt)) :: any) :: S
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

--- Packs a struct to a binary string representation.
---
--- This function uses the `lpack` library
---
--- @param o table The Lua table to pack.
--- @return string The binary string representation of the input table.
function m.pack(o)
    return lpack.pack(o)
end

--- Unpacks a binary string representation of a struct into a table.
---
--- This function uses the `lpack` library to unpack the binary string into a Lua table.
--- The unpacked table is then wrapped in a metatable that provides read-only access to the struct fields.
---
--- @param s str The binary string representation of the struct.
--- @return table The table representing the unpacked struct.
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

--- Unpacks a binary string representation of a struct into a typed table.
---
--- This function uses the `lpack` library to unpack the binary string into a Lua table.
--- The unpacked table is then wrapped in a metatable that provides read-only access to the struct fields.
--- The `cast` function is used to convert the unpacked table to the desired type `A`.
---
--- @param s str The binary string representation of the struct.
--- @param cast (any) -> A The function to cast the unpacked table to the desired type.
--- @return A The table representing the unpacked struct, cast to the desired type.
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
            assert(_current ~= nil, "first index in struct must be 1")
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
    local TAG = 901
    local cr, cast = m.define(TAG) {
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
    assert(y.One == 42)
    assert(x ~= y)
    local z = cr { One = 1, Two = 2, Three = x.Three }
    assert(z.One == 1)

    local a = cr { One = 1, Two = 2, Three = 3 }
    local b = cr { One = 1, Two = 2, Three = 3 }
    assert(a == b)
    b = b:set{ One = 11 }
    assert(b.One == 11)
    assert(b[#b+1] == TAG)
end

warn("[struct -- ok]")
return m

--!strict
local DEBUG = true
local fmt = string.format
local MAX_VAL = 2 ^ 31 - 1

local ENUM_PREFIX = "Enum"
local MAX_INLINE = 8

local EMPTY_ENUM_TEMPLATE = { NONE = 0 }

local FIST_CHAR_SKIP_PAT = nil

-- HACKY: skip value during iteration when name begins with "_"
FIST_CHAR_SKIP_PAT = string.byte("_")

-----------------------------
-- Types
-----------------------------
type bool = boolean
type str = string
type num = number
type integer = num
type int = integer
type id = int
type u32 = integer
type i32 = integer
type less<a> = (lhs: a, rhs: a) -> bool
type table = { [any]: any }
type array<T> = { T }
type fun = (...any) -> ...any
type map<k, v> = { [k]: v }

type Internal = {
    [str]: int,
    _size: u32,
    _next: map<str, str>,
    _first: str,
    _last: str,
    _id: str?,
    _descending: bool,
    _ids: { int },
}

-- stylua: ignore
type Static = {
    is             : (any) -> bool,
    iota           : (first: num | any, step: num?, last: num?) -> num,
    flag           : (int | any, int?, int?) -> int,
    cast           : (e: any) -> Enum, -- throws
    -- constructors:
    new            : <T>(tab: T, id: str?, min: int?, max: int?) -> EnumEx<T>,
    with_id        : (str) -> <T>(tab: T, min: int?, max: int?) -> EnumEx<T>,
    gt             : <T>(tab: T, id: str?, max: int?, min: int?) -> EnumEx<T>, -- for reversed enum
    create         : (map<str, int>, id: str?, min: int?, max: int?) -> Enum,
}

-- stylua: ignore
export type Enum = {
    [int]: str,
    get                  : (self: Enum, any) -> str | int,           -- throws
    key                  : (self: Enum, int) -> str,                 -- throws
    value_by_key_of      : (self: Enum, other:Enum, id: int) -> int, -- throws
    val                  : (self: Enum, str) -> int,                 -- throws
    has                  : (self: Enum, any) -> bool,
    peek                 : (self: Enum, any) -> (str | int)?,
    get_key_val          : (self: Enum, any) -> (str, int),          -- throws
    get_id_name          : (self: Enum, any) -> (int, str),
    iterate              : (self: Enum) -> ((self: Enum, k: any) -> (str, int), table),
    cast                 : (self: any, any) -> Enum,                 -- throws (deprecated)
    enum                 : (self: any, any) -> Enum,                 -- throws
    first                : (self: Enum) -> int,
    last                 : (self: Enum) -> int,
    min                  : (self: Enum) -> int,
    max                  : (self: Enum) -> int,
    is_descending        : (self: Enum) -> bool,
    full_name            : (self: Enum, int?) -> str,
    keys                 : (self: Enum) -> array<str>,               -- allocates
    values               : (self: Enum) -> array<id>,
    ids                  : (self: Enum) -> array<id>,                -- 'values' alias
    to_map               : (self: Enum) -> map<str, int>,            -- allocates
    to_array             : (self: Enum) -> array<str | int>,
    check_all_keys       : (self: Enum, table, til: id?) -> (bool, str?),
    format_id            : (self: Enum, int|str) -> str,             -- throws
    next                 : (self: Enum, v: int) -> int?,             -- throws
    cycle                : (self: Enum, v: int) -> int,
    contains_keys        : (self: Enum, other: Enum) -> bool,
    is_in                : (self: Enum, from: int, to: int?) -> bool,
    random               : (self: Enum, min:int?, max:int?) -> int,
}

export type EnumEx<T> = Enum & T

-----------------------------
-- Util
-----------------------------
local function get_prefix(self: table): str
    local id = rawget(self, "_id")
    return (id and id or ENUM_PREFIX)
end

local lt: less<int> = function(x, y)
    return x < y
end
local gt: less<int> = function(x, y)
    return y < x
end

local function insertion_sort(keys: array<str>, kv: map<str, int>, less: less<int>)
    local n = #keys
    for i = 2, n do
        local key = keys[i]
        local j = i - 1
        while j > 0 and less(kv[key], kv[keys[j]]) do
            keys[j + 1] = keys[j]
            j = j - 1
        end
        keys[j + 1] = key
    end
end

local function check_pair(k: str, v: any, self: table, prefix: str)
    if type(k) ~= "string" or tonumber(k) then
        error(fmt("%s: key '[%*] = %*' must be a string id", prefix, k, v), 3)
    end
    if type(v) ~= "number" then
        error(fmt("%s: '%s = %*': value must be number", prefix, k, v), 3)
    end
    if self[v] then
        error(fmt("%s: duplicated value: '%*' for keys: '%s', '%*'", prefix, v, k, self[v]), 4)
    end
end

-----------------------------
-- Module
-----------------------------
local strict = {
    __index = function(_, k)
        error(fmt("'%*' is a not valid member of %s", k, ENUM_PREFIX), 2)
    end,
}
local m = setmetatable({}, strict)
m.__index = m

m._type = "Enum"

function m.is(a: any): bool
    return type(a) == "table" and getmetatable(a) == m
end

function m:is_descending()
    return self._descending
end

function m:enum(e: any): Enum
    if m.is(e) then
        return e :: Enum
    elseif m.is(self) then
        return self :: Enum
    else
        error(fmt("'%*' is not an Enum", e or self))
    end
end
m.cast = m.enum

function m:first()
    return self[self._first]
end

function m:last()
    return self[self._last]
end

function m:min(): int
    return ((if self:is_descending() then self[self._last] else self[self._first]) :: any) :: int
end

function m:max(): int
    return ((if self:is_descending() then self[self._first] else self[self._last]) :: any) :: int
end

---@throws
function m:format_id(id: int | str): str
    local name: str, id1 = self:get_key_val(id)
    return name .. " (" .. tostring(id1) .. ")"
end

function m:contains_keys(other: Enum)
    for name, id in other:iterate() do
        if not self:peek(name) then
            return false
        end
    end
    return true
end

function m:is_in(from: int, to: int?): bool
    return if to then from <= self:min() and self:max() <= to else from <= self:min()
end

-----------------------------
-- Constructors
-----------------------------
function m.new<T>(tab: T, id: str?, descending: any?)
    return m.create((tab :: any) :: map<str, int>, id, descending) :: EnumEx<T>
end

local _keys_temp = table.create(8) :: array<str>

function m.create(tab: map<str, int>, id: str?, descending: any?): Enum
    if not next(tab) then
        tab = EMPTY_ENUM_TEMPLATE
        if DEBUG then
            warn("empty enum: " .. (id or ""))
        end
    end
    local count = 0
    table.clear(_keys_temp)
    local self = {} :: table
    self._id = id
    self._descending = (not not descending) :: bool
    local prefix = get_prefix(self)
    for key, val in tab do
        check_pair(key, val, self, prefix)
        self[key] = val -- enum table have all keys
        self[val] = key
        if FIST_CHAR_SKIP_PAT and string.byte(key) == FIST_CHAR_SKIP_PAT then -- skip pair
            continue
        end
        count += 1
        table.insert(_keys_temp, key)
    end
    insertion_sort(_keys_temp, self, self._descending and gt or lt)
    local internal = (self :: any) :: Internal
    internal._first = _keys_temp[1]
    internal._last = _keys_temp[#_keys_temp]
    internal._next = {}
    internal._size = count
    internal._ids = table.create(count)
    for i, k in ipairs(_keys_temp) do
        internal._next[k] = _keys_temp[i + 1]
        table.insert(internal._ids, self[k])
    end
    table.freeze(internal._ids)
    table.freeze(internal._next)
    return (table.freeze(setmetatable(self, m)) :: any) :: Enum
end

function m.with_id(id: str)
    return function<T>(t: T, descending: any?)
        return m.new(t, id, descending)
    end
end

---@summary: ctor for reversed enum (greater first)
function m.gt<T>(t: T, id: str?)
    return m.new(t, id, true)
end

do
    local _out_of_range = function()
        error("out-of-range", 2)
    end

    local _iota_iter: fun = _out_of_range
    function m.iota(first: num | any, step: num?, last: num?)
        if type(first) == "number" then
            step = step or 1
            last = last or math.sign(step :: num) * MAX_VAL
            _iota_iter = coroutine.wrap(function()
                for i = first, last :: num, step :: num do
                    coroutine.yield(i)
                end
                error("")
            end)
        end
        local ok, i = pcall(_iota_iter)
        if not ok then
            _out_of_range()
        end
        return i
    end

    local _flag_iter: fun = _out_of_range
    function m.flag(first: int | any, step: int?, last: int?)
        if type(first) == "number" then
            assert(math.floor(first) == first)
            step = step or 1
            assert(math.floor(step :: int) == step and step ~= 0)
            if not last then
                last = math.sign(step :: int) < 0 and 0 or 31
            end
            assert(math.floor(last :: int) == last)
            _flag_iter = coroutine.wrap(function()
                for i = first, last :: num, step :: num do
                    if i < 0 or i > 31 then
                        error("only 32-bit (0 .. 31) supported")
                    end
                    coroutine.yield(2 ^ i)
                end
                error("")
            end)
        end
        local ok, i = pcall(_flag_iter)
        if not ok then
            _out_of_range()
        end
        return i
    end
end

---@throws
function m:get(k_or_v: any): any
    local result = rawget((self :: any) :: table, k_or_v)
    if not result then
        error(fmt("%*: has no key nor value: '%*'", self:full_name(), k_or_v), 3)
    end
    return result
end

function m:key(val: any)
    return self:get(val) :: str
end

function m:val(key: any)
    return self:get(key) :: int
end

function m:value_by_key_of(other: Enum, id: int): int
    local k = other:key(id)
    return self:val(k)
end

function m:has(k: any): bool
    return not not rawget(self, k)
end

function m:peek(k: any): any
    return rawget(self, k)
end

---@compatibility: gives TypeError in strict mode, one-way op
m.__div = m.peek

---@throws
function m:get_key_val(k_or_v: any): (str, int)
    local result = self:get(k_or_v)
    if type(result) == "string" then
        return result, k_or_v
    else
        return k_or_v, result
    end
end

---@note: return in [v_min, v_max]
function m:random(v_min: id?, v_max: id?)
    local id_min = v_min or self._first
    local id_max = v_max or self._last
    if id_min > id_max then
        id_min, id_max = id_max, id_min
    end
    local n = #self._ids
    local v: id
    repeat
        v = self._ids[math.random(1, n)]
    until id_min <= v and v <= id_max
    return v
end

---@throws
function m:get_id_name(k_or_v: any): (int, str)
    local name, id = self:get_key_val(k_or_v)
    return id, name
end

-- TODO: rename to `name`
function m:full_name(value: int?)
    local name = get_prefix(self :: any)
    if not value then
        return name
    else
        local key = self[value]
        if not key then
            warn(name, "has no value:", value)
            return name
        end
        return name .. "." .. key
    end
end

---@note: returns frozen array
function m:values(): array<id>
    return self._ids
end

m.ids = m.values

function m:keys(): array<str>
    local out = table.create(self._size)
    for k in self:iterate() do
        table.insert(out, k)
    end
    return out
end

-- preserves order (descending or not)
function m:to_array(): array<str | int>
    local n = self._size
    local out: array<str | int> = table.create(2 * n, "")
    local i = 1
    for name, value in self:iterate() do
        out[i] = name
        out[n + i] = value
        i += 1
    end
    return out
end

function m:to_map(): map<str, int>
    local out = {}
    for name, value in self:iterate() do
        out[name] = value
    end
    return out
end

function m:__len()
    return self._size
end

local function enum_next(enum: Enum, k: str?): (str, int)
    local e = (enum :: any) :: Internal
    local key: any = if k then e._next[k] else e._first
    -- if FIST_CHAR_SKIP_PAT and key and string.byte(key) == FIST_CHAR_SKIP_PAT then -- skip pair
    --     return enum_next(enum, key)
    -- end
    return key, key and e[key]
end

function m.next(self: Enum, id: int): int?
    local key = self[id]
    local e = (self :: any) :: Internal
    local next_key = e._next[key]
    return next_key and e[next_key]
end

function m.cycle(self: Enum, id: int): int
    return self:next(id) or self:first()
end

---@compatibility: gives TypeError if self is EnumEx<T>, workaround: `:iterate()` alias or cast to `table`
function m.iterate(self: Enum): ((self: Enum, k: str?) -> (str, int), Enum)
    return enum_next, self
end
-- alias
m.__iter = m.iterate

function m:__tostring()
    local n = #self
    local out = {}
    table.insert(out, get_prefix(self))
    table.insert(out, ": [")
    for k, v in self:iterate() do
        if n <= MAX_INLINE then
            table.insert(out, string.format("%s: %*", k, v))
            table.insert(out, ", ")
        else
            table.insert(out, string.format("\n   %s: %*", k, v))
            table.insert(out, "")
        end
    end
    if #out > 1 then
        if n <= MAX_INLINE then
            out[#out] = "]"
        else
            out[#out] = "\n]"
        end
    end
    return table.concat(out)
end

-----------------------------
-- Utils
-----------------------------
function m:check_all_keys(some_table: table, til: id?): (bool, str?)
    for name, id in self:iterate() do
        ---@note: not for descending enums
        if til and id > til then
            return true
        end
        if not some_table[id] then
            return false, " table has no key: " .. self:full_name() :: str .. "." .. name
        end
    end
    return true
end

-----------------------------
-- Quick test
-----------------------------
do
    local e = m.new({
        A = 0,
        B = 31,
    }, "id", "descending")

    assert(e:is_in(0, 31))
end

do -- operations
    local E = (m :: any) :: Static
    --stylua: ignore
    local e1 = E.with_id "Id.Rarity" ({
        COMMON    = E.iota(1),
        UNCOMMON  = E.iota'',
        EPIC      = E.iota'',
        LEGENDARY = E.iota'',
        MYTHICAL  = E.iota'',
    }, 5, 1) -- will be a `descending` Enum
    assert(e1:has(e1.COMMON))
    assert(e1:is_descending())
    assert(e1:full_name() == "Id.Rarity")
    assert(e1:min() == 1)
    assert(e1:max() == 5)
    assert(#e1 == 5)
    assert(tostring(e1) == "Id.Rarity: [MYTHICAL: 5, LEGENDARY: 4, EPIC: 3, UNCOMMON: 2, COMMON: 1]")
    assert(e1:peek(1) == "COMMON")
    assert(e1:get(5) == "MYTHICAL")
    assert(not pcall(m.get, e1, e1:max() + 1))

    local vals = table.concat(e1:values())
    assert(vals == "54321")

    local names = e1:keys()
    assert(table.concat(names, " ") == "MYTHICAL LEGENDARY EPIC UNCOMMON COMMON")

    local sum = 0
    for _, val in e1:iterate() do
        sum += val
    end
    assert(sum == 15)

    assert(e1:cast()[e1.COMMON] == "COMMON")
    assert(E.cast(e1)[e1.COMMON] == "COMMON")
    -- local _ = e1[e1.COMMON] -- TODO: create luau issue: TypeError: Expected type table ...
    local nvs = e1:to_array()
    assert(#nvs % 2 == 0)
    assert(nvs[1] == "MYTHICAL")
    assert(nvs[#nvs] == 1)
    assert(e1:key(e1.COMMON) == "COMMON")
end

do -- checks
    local E = (m :: any) :: Static
    assert(not pcall(E.new, { A = "math.pi" }))
    assert(not pcall(E.new, { [1] = 1 }))
    assert(not pcall(E.new, { A = 1, B = 1 }))
end

do -- flags
    assert(m.flag(1, -1) == 2)
    assert(m.flag("") == 1)
    assert(not pcall(m.flag, ""))
end

do -- misc
    local e = m.new {
        ONE = m.iota(1),
        _SKIP = m.iota(""),
        TWO = m.iota(""),
    }
    assert(#e == 2)
    -- but:
    assert(e._SKIP)
    assert(e:enum(e._SKIP))
end

do -- cycle
    local e = m.new ({
        ONE = m.iota(1),
        _SKIP = m.iota(""),
        TWO = m.iota(""),
    }, "id", "descending")
    assert(#e == 2)
    local n = e:last()
    assert(if e:is_descending() then n == 1 else n == 3)
    assert(e:cycle(3) == 1)
    assert(e:cycle(1) == 3)

    for i = 1, 100 do
        local id = e:random(e.ONE, e.TWO)
        assert(e.ONE <= id and id <= e.TWO)
        assert(id ~= e._SKIP)
    end
end

warn("[Enum -- ok]")

return (m :: any) :: Static

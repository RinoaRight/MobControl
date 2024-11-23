--!strict
--!optimize 2
-- no sense to use !native directive, it's not faster

-- MIT License
-- Copyright (c) 2024 Andrew Zhilin (https://github.com/zoon)

local __DEV__: unknown

type str = string
type bool = boolean
type num = number
type uint = num
type int = num
type u32 = uint
type u8 = uint
type u5 = uint
type u3 = uint
type id = int
type array<a> = { a }
type map<k, v> = { [k]: v }
local fmt = string.format

type op = u8
export type uid = str | id
export type cid = u5
export type mask = u32
export type meta = mask
export type masks = map<uid, mask>
export type metas = map<uid, meta>
export type component = any -- components should be treated as immutable value, though luau cannot enforce this
export type transactions = { uid | op | cid | component }
export type pp = (any) -> str

export type getter = (uid) -> component
export type setter = (uid, component) -> ()

export type column = { [uid]: component }
export type storage = { [cid]: column }
export type setters = { [cid]: setter }
export type names = { [cid]: str }
export type query = cid | "not"
export type attribute = "local" | "transient"
export type mode = "main" | "replica"
export type gen = () -> uid
export type destructor = (component) -> ()
export type destructors = { [cid]: destructor }
-- general for on_xxx callback type
export type on_changes = (uid, component, component?) -> ()
export type on_modify = (uid, new: component, old: component) -> ()
export type on_attach = (uid, new: component) -> ()
export type on_detach = (uid, old: component) -> ()

--- @perf: micro optimizations notes:
--- - while mask ~= 0 do ... performance 4x slower then `for i=0, 32`, but for popcount < 8 its faster
--- - bit32.replace(mask, 0, cid, 1) is slightly (10%) faster then bit32.bxor(mask, bit32.lshift(1, cid))

local PACKED_OP_MASK = 0b_111_00000
local PACKED_CID_MASK = 0b_000_11111

--[=[ `op, uid, mask, ...` ]=]
local OP_CREATE = 0b_001_00000
--[=[ `op, uid` ]=]
local OP_DELETE = 0b_010_00000
--[=[ `(op,cid), uid` ]=]
local OP_DETACH = 0b_011_00000
--[=[ `(op,cid), uid, component` ]=]
local OP_ATTACH = 0b_100_00000
--[=[ `(op,cid), uid,  component`]=]
local OP_MODIFY = 0b_101_00000

-- stylua: ignore
local OPS = setmetatable({
    [OP_CREATE] = "CREATE",
    [OP_DELETE] = "DELETE",
    [OP_DETACH] = "DETACH",
    [OP_ATTACH] = "ATTACH",
    [OP_MODIFY] = "MODIFY",
}, { __index = function(_, k)
        return "unknown op:'" .. tostring(k) .. "'"
    end
})

--- @readonly `(uid, mask, meta, ...component)*`
local HEADER_SAVE = ".sv"
--- @readonly `(uid, mask, ...component)*`
local HEADER_SNAPSHOT = ".ss"

--------------------------------
-- entity(uid) level meta flags
--------------------------------
--[=[ `main: not replicated (local), replica: not used (default)` ]=]
local META_INTERNAL = 0b_001
--[=[ `main: not persistent, replica: not used (default)` ]=]
local META_TRANSIENT = 0b_010
--[=[ `main: replicate entity deletion, replica: main state controls entity deletion` ]=]
local META_SHARED = 0b_100

local scratch_buf = buffer.create(32)

-----------------------------
-- Types
-----------------------------

-- stylua: ignore

-- This type `Common<Self>` defines a set of common functionality for both the
-- `Main` and `Replica` types. It provides methods for interacting with the
-- state, such as getting and setting components, selecting entities based on
-- queries, and formatting the state for debugging purposes.

-- The `env` method allows accessing and optionally updating the environment
-- associated with the state.

-- The `has`, `get`, and `getter` methods provide ways to check if an entity
-- exists, retrieve a component, and create a getter function for components.

-- The `set` and `setter` methods allow setting a component on an entity and
-- creating a setter function for components.

-- The `size` method returns the number of entities and components in the state.

-- The `select` method provides a way to query the state and iterate over the
-- resulting entities and components.

-- The `format_*` methods provide various ways to format the state for debugging
-- purposes, such as formatting individual entities, the entire state, and the
-- transaction log.

-- The `names` method returns the names of the components in the state.
type Common<Self> = {
    env:          (self: Self, key: str, new_value: any?) -> any,
    has:          (self: Self, uid, cid?) -> bool,
    get:          (self: Self, uid, cid) -> component,
    getter:       (self: Self, ...cid) -> (uid) -> ...component,
    set:          (self: Self, uid, cid, component) -> (),
    setter:       (self: Self, ...cid) -> (uid, ...component) -> (),
    size:         (self: Self) -> (int, int), -- (rows, components)
    select:       (self: Self, ...query) -> ((Index<uid>, uid?) -> (uid?, ...component), Index<uid>), -- iterator
    -- debugging
    format_cid:   (self: Self, cid: cid) -> str,
    format_mask:  (self: Self, mask: mask) -> str,
    format_uid:   (self: Self, uid: uid) -> str,
    format_row:   (self: Self, uid: uid, mask?) -> str,
    format_log:   (self: Self, transactions?) -> str, -- transactions? only for main mode
    format_state: (self: Self, opt: "*" | "h" | num | nil) -> str,
    format_rows:  (self: Self, ...query) -> str,
    format_query: (self: Self, ...query) -> str,
    names:        (self: Self) -> names,
}

-- stylua: ignore
type CommonInternal<Self> = Common<Self> & {
    _config: Config,
    _environment: map<str, any>,
    _masks: masks,
    _metas: metas,
    _setters: setters,
    _storage: storage,
}

---  The `Main` type represents the main state of the application. It extends the
--- `Common` type and provides additional functionality for constructing the
--- state, managing snapshots and saves, and deleting entities.
---
---  The `constructor` method is used to create a new instance of the `Main`
--- state, taking a list of component IDs or attributes as arguments. It returns
--- a tuple containing a function to create new entities and a mask representing
--- the components in the state.
---
---  The `flash` method is used to move the internal replication log out of the
--- state, returning the log as a transactions object.
---
---  The `snapshot` method is used to create a snapshot of the current state,
--- which can be used for replication purposes. It takes an optional
--- "discard-log" parameter to indicate that the replication log should be
--- discarded after the snapshot is created.
---
---  The `save` method is used to create a save of the current state, which can
--- be used for persistence purposes. It returns the transactions that represent
--- the save.
---
---  The `load` method is used to load a saved state, taking the transactions
--- representing the saved state as an argument. It returns a new instance of
--- the `Main` state with the loaded data.
---
---  The `delete` method is used to delete an entity from the state, taking the
--- unique identifier (UID) of the entity as an argument. stylua: ignore
export type Main = Common<Main> & {
    constructor: (self: MainSelf, ...cid | attribute) -> ((uid | gen, ...component) -> uid, mask),
    --- Flushes the log of the main state and returns a shallow copy of the log.
    ---
    --- This function is only available in the "main" mode of the state. If the log is
    --- empty, this function will return `nil`.
    ---
    --- @return transactions? A shallow copy of the log, or `nil` if the log is empty.
    flash: (self: MainSelf) -> transactions?, -- move internal replication log out of state
    snapshot: (self: MainSelf, opt: "discard-log"?) -> transactions, -- create snapshot (replication)
    save: (self: MainSelf) -> transactions, -- create save (persistence)
    load: (self: MainSelf, transactions) -> MainSelf, -- load save
    delete: (self: MainSelf, uid) -> (),
}

type MainInternal = Main & CommonInternal<MainSelf> & {
    _log: transactions,
}
-- stylua: ignore
export type Replica = Common<Replica> & {
    constructor:   (self: ReplicaSelf, ...cid) -> ((uid | gen, ...component) -> uid, mask),
    init:          (self: ReplicaSelf, transactions) -> (), -- load snapshot
    update:        (self: ReplicaSelf, transactions) -> (), -- replica accept replication log + events
    delete:        (self: ReplicaSelf, uid) -> (), -- remove entity
    set_on_attach: (self: ReplicaSelf, cid, on_attach?) -> ReplicaSelf,
    set_on_modify: (self: ReplicaSelf, cid, on_modify?) -> ReplicaSelf,
    set_on_detach: (self: ReplicaSelf, cid, on_detach?) -> ReplicaSelf,
}

type ReplicaInternal = Replica & CommonInternal<ReplicaSelf> & {
    _on_attach: map<cid, false | on_attach>,
    _on_modify: map<cid, false | on_modify>,
    _on_detach: map<cid, false | on_detach>,
    --- @todo: callback setters should set the respectful masks
    _callback_masks: { mask },
    -- array of triplets (op|cid, uid, old_component)
    _deferred_changes: { any },
    _setter_in_use: bool, -- flag to prevent calling set from callbacks (to prevent infinite recursion)
}

--[[ dev mode
__DEV__ = true
type MainSelf = CommonInternal<MainSelf> & MainInternal
local MainState = {} :: MainSelf;
(MainState :: any).__index = MainState
type ReplicaSelf = CommonInternal<ReplicaSelf> & ReplicaInternal
local ReplicaState = {} :: ReplicaSelf;
(ReplicaState :: any).__index = ReplicaState
--]]

---[[ prod mode
__DEV__ = true or _G.__DEV__
type MainSelf = Common<MainSelf> & Main
local MainState = {}
MainState.__index = MainState
type ReplicaSelf = Common<ReplicaSelf> & Replica
local ReplicaState = {}
ReplicaState.__index = ReplicaState
--]]

export type Config = {
    _mode: mode,
    _pretty_printer: pp,
    _is_replicating: mask,
    _is_persistent: mask,
    _is_read_only: mask,
    _component_names: names,
    _destructors: destructors,
}

-- set_replication_flag

export type ConfigBuilder = {
    create: (mode?) -> ConfigBuilder,
    proto: Config,
    set_destructor: (self: ConfigBuilder, cid: cid, dtor: Destroy<any>) -> ConfigBuilder,
    set_pretty_printer: (self: ConfigBuilder, pp: pp) -> ConfigBuilder,
    set_replication_flag: (self: ConfigBuilder, ...cid) -> ConfigBuilder, -- cid level replication
    set_persistent_flag: (self: ConfigBuilder, ...cid) -> ConfigBuilder, -- cid level persistence
    set_read_only_flag: (self: ConfigBuilder, ...cid) -> ConfigBuilder, -- cid level write protection
    set_component_names: (self: ConfigBuilder, names: map<any, any>) -> ConfigBuilder,
    build_with_replica: (self: ConfigBuilder) -> (Config, ConfigBuilder),
    build: (self: ConfigBuilder) -> Config,
    reset: (Config) -> ConfigBuilder, -- static, create new builder from config
}

export type Destroy<T> = (self: T) -> ()

export type Index<T> = { Release: Destroy<Index<T>>, count: () -> int } & { T }

export type Query = {
    iterate_index: (Common<any>, Index<uid>, mask) -> ((Index<uid>, uid?) -> (uid?, ...component), Index<uid>),
    query: (Common<any>, ...query) -> (Index<uid>, mask),
}

-----------------------------
-- Utility
-----------------------------
local function is_cid(x: any)
    return type(x) == "number" and x // 1 == x and 0 <= x and x <= 31
end

local function check_cid(c: cid): cid
    if is_cid(c) then
        return c
    end
    error("not a cid: " .. tostring(c), 2)
end

local function args2mask0(acc: u32, c: cid, ...: cid): mask
    if c == nil then
        return acc
    end
    return args2mask0(bit32.bor(acc, bit32.lshift(1, c)), ...)
end

local function args2mask(c: cid, ...: cid): mask
    return args2mask0(0, c, ...)
end

local function keys2mask(keys: { [cid]: any }): mask
    local mask = 0
    for cid, _ in keys do
        mask = bit32.bor(mask, bit32.lshift(1, cid))
    end
    return mask
end

local function args_take(from: uint, to: uint, ...: any): ...any
    if from <= to then
        return select(from, ...), args_take(from + 1, to, ...)
    end
end

-- Counts the number of 1 bits in a 32-bit integer
local function popcount32(x: u32): u32
    x = x - bit32.band(bit32.rshift(x, 1), 0x55555555)
    x = bit32.band(x, 0x33333333) + bit32.band(bit32.rshift(x, 2), 0x33333333)
    x = bit32.band(x + bit32.rshift(x, 4), 0x0F0F0F0F)
    return bit32.rshift(bit32.band(x * 0x01010101, 0xFFFFFFFF), 24)
end

-- Performs a deep clone of a table, userdata, or value type
-- @param obj: The object to clone
-- @return A deep copy of the input object
local function deep_clone<T>(obj: T): T
    if type(obj) == "table" then
        obj = table.clone(obj) :: typeof(obj)
        for k, v in pairs(obj) do
            obj[k] = deep_clone(v)
        end
    elseif type(obj) == "userdata" then
        if obj.Clone then
            return obj.Clone()
        else
            error("userdata doesn't implement `Clone` method", 2)
        end
    end
    -- value type
    return obj
end

-- Recursively freezes a table and all nested tables
-- @param obj: The object to freeze
-- @return The frozen object
local function deep_freeze<T>(obj: T): T
    if type(obj) == "table" and not table.isfrozen(obj) then
        for k, v in pairs(obj) do
            obj[k] = deep_freeze(v)
        end
        obj = table.freeze(obj) :: typeof(obj)
    end
    return obj
end

-- Checks if a table is an array (consecutive numeric indices)
-- @param o: The table to check
-- @return boolean indicating if the table is an array
local function is_array(o: any)
    if type(o) ~= "table" then
        return false
    end
    local n, len = #o, 0
    for _ in o do
        len += 1
    end
    return len == n
end

local function wrong_order(a: any, suspect: num?, ...: cid?): cid?
    return if suspect == nil or suspect <= a then suspect else wrong_order(suspect, ...)
end

--- Formats a component ID with optional name lookup
--- @param cid: Component ID
--- @param names: Optional map of component IDs to names
--- @return Formatted string representation
local function format_cid(cid: cid, names: names?)
    check_cid(cid)
    return names and names[cid] or fmt("#%.2d", cid)
end

--- Formats metadata bits into a string representation
---
--- 's': shared, 'i': internal, 't': transient
--- @param meta: Metadata bitmask
--- @return String in format "sit" where each position shows - or corresponded letter
local function format_meta(meta: mask)
    assert(meta == bit32.band(meta, 0b_111), "too many bits in meta")
    buffer.fill(scratch_buf, 0, 0)
    local shared = bit32.btest(meta, META_SHARED)
    local internal = bit32.btest(meta, META_INTERNAL)
    local transient = bit32.btest(meta, META_TRANSIENT)
    assert(not (shared and internal), "shared and internal cannot be set together")
    buffer.writestring(scratch_buf, 2, if transient then "t" else "-")
    buffer.writestring(scratch_buf, 1, if internal then "i" else "-")
    buffer.writestring(scratch_buf, 0, if shared then "s" else "-")
    return buffer.readstring(scratch_buf, 0, 3)
end

local function format_uid(uid: uid, pp: pp?): str
    if pp then
        return pp(uid)
    end
    if type(uid) == "string" then
        --- @note: uid can be binary string, it might be a good idea to use pp
        -- (and hexify in it)
        return fmt("'%q'", uid)
    else
        return tostring(uid)
    end
end

local function format_mask(mask: mask, names: names?)
    local out = {}
    while mask ~= 0 do
        local cid = bit32.countrz(mask)
        table.insert(out, format_cid(cid, names))
        mask = bit32.replace(mask, 0, cid, 1)
    end
    return "[" .. table.concat(out, ", ") .. "]"
end

local function format_config(c: Config, out: { str }?): { str }
    out = out or {}
    assert(out)
    if c._is_replicating ~= 0 then
        table.insert(out, "  > replicating: " .. format_mask(c._is_replicating, c._component_names))
    end
    if c._is_persistent ~= 0 then
        table.insert(out, "  > persistent: " .. format_mask(c._is_persistent, c._component_names))
    end
    if c._is_read_only ~= 0 then
        table.insert(out, "  > read_only: " .. format_mask(c._is_read_only, c._component_names))
    end
    if next(c._destructors) then
        table.insert(out, "  > destructors: " .. format_mask(keys2mask(c._destructors), c._component_names))
    end
    return out
end

local function select_from<a>(array: array<a>, head: num?, ...: num?): ...a
    if head then
        return array[head], select_from(array, ...)
    end
end

local function mask2args(mask: mask): ...cid
    if mask ~= 0 then
        local cid = bit32.countrz(mask)
        return cid, mask2args(bit32.bxor(mask, bit32.lshift(1, cid)))
    end
end

local function get_many_ref(uid: uid, storage: storage, i, cids: { cid }): ...component
    if i <= #cids then
        return storage[cids[i]][uid], get_many_ref(uid, storage, i + 1, cids)
    end
end
-- stylua: ignore
local function get_many_factory(storage: storage, ...: cid): (uid: uid) -> ...component
    local n = select("#", ...)
    assert(n > 0, "should have at least one component")
    if n == 1 then
        local c1 = storage[(...)]
        return function(uid) return c1[uid] end
    elseif n == 2 then
        local c1, c2 = select_from(storage, ...)
        return function(uid) return c1[uid], c2[uid] end
    elseif n == 3 then
        local c1, c2, c3 = select_from(storage, ...)
        return function(uid) return c1[uid], c2[uid], c3[uid] end
    elseif n == 4 then
        local c1, c2, c3, c4 = select_from(storage, ...)
        return function(uid) return c1[uid], c2[uid], c3[uid], c4[uid] end
    elseif n == 5 then
        local c1, c2, c3, c4, c5 = select_from(storage, ...)
        return function(uid) return c1[uid], c2[uid], c3[uid], c4[uid], c5[uid] end
    elseif n == 6 then
        local c1, c2, c3, c4, c5, c6 = select_from(storage, ...)
        return function(uid) return c1[uid], c2[uid], c3[uid], c4[uid], c5[uid], c6[uid] end
    elseif n == 7 then
        local c1, c2, c3, c4, c5, c6, c7 = select_from(storage, ...)
        return function(uid) return c1[uid], c2[uid], c3[uid], c4[uid], c5[uid], c6[uid], c7[uid] end
    end
    -- reference version for 8+ components
    local cids = { ... }
    return function(uid)
        return get_many_ref(uid, storage, 1, cids)
    end
end

-- stylua: ignore
--- @todo: pass n
local function set_many_factory(setters: setters, ...: cid): ((uid, ...component) -> (), int)
    local n = select("#", ...)
    if n == 1 then
        local s1 = setters[(...)]
        return function(uid, a) s1(uid, a) end, n
    elseif n == 2 then
        local s1, s2 = select_from(setters, ...)
        return function(uid, a, b) s1(uid, a); s2(uid, b) end, n
    elseif n == 3 then
        local s1, s2, s3 = select_from(setters, ...)
        return function(uid, a, b, c) s1(uid, a); s2(uid, b); s3(uid, c) end, n
    elseif n == 4 then
        local s1, s2, s3, s4 = select_from(setters, ...)
        return function(uid, a, b, c, d) s1(uid, a); s2(uid, b); s3(uid, c); s4(uid, d) end, n
    elseif n == 5 then
        local s1, s2, s3, s4, s5 = select_from(setters, ...)
        return function(uid, a, b, c, d, e) s1(uid, a); s2(uid, b); s3(uid, c); s4(uid, d); s5(uid, e) end, n
    elseif n == 6 then
        local s1, s2, s3, s4, s5, s6 = select_from(setters, ...)
        return function(uid, a, b, c, d, e, f) s1(uid, a); s2(uid, b); s3(uid, c); s4(uid, d); s5(uid, e); s6(uid, f) end, n
    elseif n == 7 then
        local s1, s2, s3, s4, s5, s6, s7 = select_from(setters, ...)
        return function(uid, a, b, c, d, e, f, g) s1(uid, a); s2(uid, b); s3(uid, c); s4(uid, d); s5(uid, e); s6(uid, f); s7(uid, g) end, n
    end
    -- reference version for 8+ components
    local cids = { ... }
    return function(uid, ...: component)
        for i, cid in cids do
            local component = select(i, ...)
            setters[cid](uid, component)
        end
    end, n
end

-- stylua: ignore
local function attach_many_factory(storage: storage, ...: cid): ((uid, ...component) -> (), int)
    local n = select("#", ...)
    if n == 1 then
        local c1 = storage[(...)]
        return function(uid, a) c1[uid] = a end, n
    elseif n == 2 then
        local c1, c2 = select_from(storage, ...)
        return function(uid, a, b) c1[uid] = a; c2[uid] = b end, n
    elseif n == 3 then
        local c1, c2, c3 = select_from(storage, ...)
        return function(uid, a, b, c) c1[uid] = a; c2[uid] = b; c3[uid] = c end, n
    elseif n == 4 then
        local c1, c2, c3, c4 = select_from(storage, ...)
        return function(uid, a, b, c, d) c1[uid] = a; c2[uid] = b; c3[uid] = c; c4[uid] = d end, n
    elseif n == 5 then
        local c1, c2, c3, c4, c5 = select_from(storage, ...)
        return function(uid, a, b, c, d, e) c1[uid] = a; c2[uid] = b; c3[uid] = c; c4[uid] = d; c5[uid] = e end, n
    elseif n == 6 then
        local c1, c2, c3, c4, c5, c6 = select_from(storage, ...)
        return function(uid, a, b, c, d, e, f) c1[uid] = a; c2[uid] = b; c3[uid] = c; c4[uid] = d; c5[uid] = e; c6[uid] = f end, n
    elseif n == 7 then
        local c1, c2, c3, c4, c5, c6, c7 = select_from(storage, ...)
        return function(uid, a, b, c, d, e, f, g) c1[uid] = a; c2[uid] = b; c3[uid] = c; c4[uid] = d; c5[uid] = e; c6[uid] = f; c7[uid] = g end, n
    end
    -- reference version for 8+ components
    local cids = { ... }
    return function(uid, ...: component)
        for i, cid in cids do
            local component = select(i, ...)
            storage[cid][uid] = component
        end
    end, n
end

--- @note: use it before or after write to storage, according to operator:
--- after ON_ATTACH, before ON_DETACH or ON_MODIFY
local function defer_many_op(uid: uid, op: op, changes: transactions, storage: storage, cids: array<cid>)
    for _, cid in cids do
        local component = storage[cid][uid]
        table.insert(changes, bit32.bor(cid, op))
        table.insert(changes, uid)
        table.insert(changes, component)
    end
end

local function pcall_destructor(cid: cid, names: names, dtor: (any) -> (), component: any)
    local ok, err: str? = pcall(dtor, component)
    if not ok then
        warn(fmt("ERROR: destructor fail, cid: %*\n%*'", format_cid(cid, names), err), 3)
    end
end

local function detach_all(uid, storage: storage, destructors: destructors, names: names, mask: mask)
    while mask ~= 0 do
        local cid = bit32.countrz(mask)
        mask = bit32.bxor(mask, bit32.lshift(1, cid))
        if destructors[cid] then
            local value = storage[cid][uid]
            pcall_destructor(cid, names, destructors[cid], value)
        end
        storage[cid][uid] = nil
    end
end

--- @note: not intended for for trow in production
local function pcall_callback(uid: uid, cid: cid, op: op, config: Config, callback: on_changes, c1: component, c2: component?)
    if __DEV__ and not callback then
        local names = config._component_names
        error(fmt("uid:%* cid:%* op:%*: callback not found", format_uid(uid, config._pretty_printer), format_cid(cid, names), OPS[op]))
    end
    local ok, err: str?
    if c2 ~= nil then
        ok, err = pcall(callback, uid, c1, c2)
    else
        ok, err = pcall(callback, uid, c1)
    end
    if not ok then
        local names = config._component_names
        local pp = config._pretty_printer
        warn(fmt("ERROR: op:%* callback fail, uid: %* cid: %* \n%*'", OPS[op], format_uid(uid, pp), format_cid(cid, names), err), 3)
    end
end

-- stylua: ignore
local function process_deferred_changes(self: ReplicaInternal)
    local changes = self._deferred_changes
    local config = self._config
    local n = #changes
    if n == 0 then
        return
    end
    local on_attach = self._on_attach
    local on_detach = self._on_detach
    local on_modify = self._on_modify
    local storage = self._storage
    local p = 1
    while p < n do
        local header, uid, component = unpack(changes, p, p + 2); p += 3
        assert(type(header) == "number", "invalid header")
        local cid = bit32.band(header, PACKED_CID_MASK)
        local op = bit32.band(header, PACKED_OP_MASK)
        if op == OP_ATTACH then
            pcall_callback(uid, cid, op, config, on_attach[cid] :: on_changes, component)
        elseif op == OP_DETACH then
            pcall_callback(uid, cid, op, config, on_detach[cid] :: on_changes, component)
        elseif op == OP_MODIFY then
            local new = storage[cid][uid]
            pcall_callback(uid, cid, op, config, on_modify[cid] :: on_changes, new, component)
        else
            error("invalid op:" .. OPS[op])
        end
    end
    assert(p >= n, "sanity check")
    table.clear(changes)
end

local function format_component(c: component, pp: pp?)
    if not is_array(c) then
        return pp and pp(c) or tostring(c)
    end
    local out = {}
    for _, v in ipairs(c :: any) do
        table.insert(out, if pp then pp(v) else tostring(v))
    end
    return "[" .. table.concat(out, ", ") .. "]"
end

local function log_component(log: transactions, component: component)
    if __DEV__ then
        assert(type(component) ~= "userdata", "we cannot replicate or save `userdata`")
        assert(component ~= nil, "component in log must not be nil")
    end
    table.insert(log, component)
end

--- @note: result intended to be memoized
local function save_by_mask_factory(log: transactions, storage: storage, mask: mask): (uid, mask?) -> ()
    assert(mask ~= 0)
    local columns = {} :: { column }
    local temp_mask = mask
    while temp_mask ~= 0 do
        local cid = bit32.countrz(temp_mask)
        temp_mask = bit32.bxor(temp_mask, bit32.lshift(1, cid))
        table.insert(columns, storage[cid])
    end
    return function(uid, meta: meta?)
        table.insert(log, uid)
        table.insert(log, mask)
        --- @note: snapshot do not have meta, save do
        if meta then
            table.insert(log, meta)
        end
        for _, column in columns do
            local component = column[uid]
            if __DEV__ then
                assert(component ~= nil, "component in log must not be nil")
            end
            log_component(log, component)
        end
    end
end

local function read_only_setter(cid: cid, names: names): (uid, component) -> ()
    return function(uid, component)
        error(`column {format_cid(cid, names)} is read-only`, 3)
    end
end

local function dump_snapshot(log: transactions?, names: map<cid, str>?, pp: pp?): str
    if not log or #log <= 1 then
        return "------ empty log"
    end
    local header = log[1]
    local stride
    if header == HEADER_SAVE then
        stride = 3
    elseif header == HEADER_SNAPSHOT then
        -- snapshot has no meta, so we have to skip it
        stride = 2
    else
        error("invalid log (header)", 3)
    end
    local inc = stride - 1
    local n, p, row = #log, 2, 0 -- we read snapshot from position after header
    local out = {} :: { str }
    -- stylua: ignore
    while p < n do
        row += 1
        local uid, mask, m = table.unpack(log, p, p + inc); p += stride
        local meta = m or 0
        assert(type(mask) == "number" and bit32.bor(mask) == mask, "invalid log (mask)")
        assert(type(meta) == "number" and bit32.bor(meta) == meta, "invalid log (meta)")
        assert(type(uid) == "number" or type(uid) == "string", "invalid log (uid)")
        local uid_str = format_uid(uid, pp)
        local meta_str = format_meta(meta)
        local op_str = OPS[OP_CREATE] -- implicit OP_CREATE
        while mask ~= 0 do
            local cid = bit32.countrz(mask)
            mask = bit32.bxor(mask, bit32.lshift(1, cid))
            local value = log[p]; p += 1
            local cid_str = format_cid(cid, names)
            local component_str = format_component(value, pp)
            table.insert(out, fmt("%.4d | %* %* uid:%-16s cid:%-16s := %*", row, op_str, meta_str, uid_str, cid_str, component_str))
        end
    end
    assert(p >= n, "excessive log entries")
    return table.concat(out, "\n")
end

local function format_log(log: transactions?, names: map<cid, str>?, pp: pp?)
    if not log or #log <= 1 then
        return "------ empty log"
    end
    local header_byte = log[1]
    if header_byte == HEADER_SNAPSHOT then
        return dump_snapshot(log, names, pp)
    end
    local out = { "-----+------ log:" } :: { str }
    local n, p, i = #log, 1, 0
    -- stylua: ignore
    while p < n do
        i += 1
        local header, uid = table.unpack(log, p, p + 1); p += 2
        local uid_str = format_uid(uid, pp)
        assert(type(header) == "number")
        assert(uid, "invalid log")
        local op = bit32.band(header, PACKED_OP_MASK)
        local op_str = OPS[op]
        if op == OP_DETACH or op == OP_ATTACH or op == OP_MODIFY then
            local cid = bit32.band(header, PACKED_CID_MASK)
            if op == OP_DETACH then
                table.insert(out, fmt("%4d | %-6s uid:%-16s cid:%-16s", i, op_str, uid_str, format_cid(cid, names)))
            else -- OP_ATTACH or OP_MODIFY
                local component = log[p]; p += 1
                table.insert(out, fmt("%4d | %-6s uid:%-16s cid:%-16s := %*", i, op_str, uid_str, format_cid(cid, names), format_component(component, pp)))
            end
        elseif op == OP_CREATE then
            local mask = log[p]; p += 1
            assert(type(mask) == "number" and bit32.bor(mask) == mask)
            while mask ~= 0 do
                local cid = bit32.countrz(mask)
                mask = bit32.bxor(mask, bit32.lshift(1, cid))
                local value = log[p]; p += 1
                table.insert(out, fmt("%4d | %-6s uid:%-16s cid:%-16s := %*", i, op_str, uid_str, format_cid(cid, names), format_component(value, pp)))
            end
        elseif op == OP_DELETE then
            table.insert(out, fmt("%4d | %-6s uid:%-16s", i, op_str, uid_str))
        else
            error("invalid op: " .. OPS[op])
        end
    end
    assert(log[p] == nil, "excessive log entries")
    return table.concat(out, "\n")
end

local function args2str(names: names?, ...): str
    local out = {}
    for i = 1, select("#", ...) do
        local el = select(i, ...)
        if type(el) == "number" then
            local name = names and names[el] or "cid"
            table.insert(out, fmt("'%*(%d)'", name, el))
        else
            table.insert(out, el)
        end
    end
    return table.concat(out, ", ")
end

local function toy_pp(o: any)
    local t = type(o)
    if t == "string" then
        return fmt("%q", o)
    elseif t == "number" then
        return fmt("%.7g", o)
    end
    return tostring(o)
end

--- @note: META
local ATTR: map<attribute, int> = {
    transient = META_TRANSIENT,
    ["local"] = META_INTERNAL,
}

local function parse_constructor_args(names: names, ...: cid | attribute): (mask, meta, int)
    local mask, meta, arity = 0, 0, 0
    for i = 1, select("#", ...) do
        local x = select(i, ...)
        if ATTR[x] or is_cid(x) then
            if ATTR[x] then
                meta = bit32.bor(meta, ATTR[x])
            elseif bit32.countlz(mask) < 32 - x then
                error(fmt("cid: '%*' is out of order in: %*", format_cid(x, names), args2str(names, ...)))
            else -- we good
                mask = bit32.bor(mask, bit32.lshift(1, x))
                arity += 1
            end
        else
            error(fmt("wrong argument #%d in: %*", i, args2str(names, ...)))
        end
    end
    return mask, meta, arity
end

-----------------------------
-- Index
-----------------------------
local Index = {}
Index.__index = Index
do
    local MAX_INDEX_POOL = 3
    local __index_pool = {} :: { Index<any> }
    function Index.acquire(): Index<any>
        if #__index_pool == 0 then
            return setmetatable(table.create(4096), Index) :: any
        end
        return table.remove(__index_pool) :: any
    end
    function Index.Release(self: Index<any>)
        if #self == 0 and table.find(__index_pool, self) then
            return -- already released
        end
        if #__index_pool > MAX_INDEX_POOL then
            return -- too many indexes
        end
        table.clear(self)
        table.insert(__index_pool, self)
    end
    -- alias for Maid
    Index.Delete = Index.Release
    Index.count = function()
        return #__index_pool
    end
end

-----------------------------
-- Config Builder
-----------------------------
local DEFAULT_CONFIG: Config = table.freeze {
    _mode = "main" :: mode,
    _pretty_printer = toy_pp,
    _is_replicating = 0,
    _is_persistent = 0,
    _is_read_only = 0,
    _component_names = {},
    _destructors = {},
}
local ConfigBuilder = {} :: ConfigBuilder;
(ConfigBuilder :: any).__index = ConfigBuilder

function ConfigBuilder.reset(config: Config): ConfigBuilder
    return setmetatable({ proto = deep_clone(config) }, ConfigBuilder) :: any
end

function ConfigBuilder.create(mode: mode?): ConfigBuilder
    local proto = deep_clone(DEFAULT_CONFIG)
    proto._mode = mode or "main"
    return setmetatable({ proto = proto }, ConfigBuilder) :: any
end

function ConfigBuilder.set_pretty_printer(self: ConfigBuilder, pp: pp)
    assert(getmetatable(self :: any) == ConfigBuilder, "add `:` to call")
    assert(type(pp) == "function" and type(pp()) == "string", "incorrect pretty-printer")
    self.proto._pretty_printer = pp
    return self
end
function ConfigBuilder.set_destructor(self: ConfigBuilder, cid: cid, dtor: (any) -> ())
    assert(getmetatable(self :: any) == ConfigBuilder, "add `:` to call")
    assert(type(dtor) == "function", "incorrect destructor")
    self.proto._destructors[cid] = dtor
    return self
end

function ConfigBuilder.set_replication_flag(self: ConfigBuilder, ...: cid)
    assert(getmetatable(self :: any) == ConfigBuilder, "add `:` to call")
    assert(self.proto._mode == "main", "cannot set replicated components in 'replica' mode")
    self.proto._is_replicating = args2mask0(self.proto._is_replicating, ...)
    return self
end
function ConfigBuilder.set_read_only_flag(self: ConfigBuilder, ...: cid)
    assert(getmetatable(self :: any) == ConfigBuilder, "add `:` to call")
    self.proto._is_read_only = args2mask0(self.proto._is_read_only, ...)
    return self
end
function ConfigBuilder.set_persistent_flag(self: ConfigBuilder, ...: cid)
    assert(getmetatable(self :: any) == ConfigBuilder, "add `:` to call")
    assert(self.proto._mode == "main", "cannot set persistent components in 'replica' mode")
    self.proto._is_persistent = args2mask0(self.proto._is_persistent, ...)
    return self
end
function ConfigBuilder.set_component_names(self: ConfigBuilder, names: { [any]: any })
    assert(getmetatable(self :: any) == ConfigBuilder, "add `:` to call")
    local tab = self.proto._component_names :: any
    assert(next(tab) == nil, "component names have already been defined")
    for key, val in names do
        --- @note: kludges to be compatible with enums
        if type(val) == "number" and is_cid(val) and type(key) == "string" then
            assert(tab[val] == nil, "duplicated value")
            tab[val] = key
            assert(tab[key] == nil, "duplicated name")
            tab[key] = val
        end
    end
    return self
end

function ConfigBuilder.build_with_replica(self: ConfigBuilder): (Config, ConfigBuilder)
    local replica = ConfigBuilder.reset(self.proto)
    replica.proto._mode = "replica"
    replica.proto._destructors = {}
    replica.proto._is_replicating = 0
    replica.proto._is_persistent = 0
    -- all fields marked for replication will be read-only in the replica
    replica.proto._is_read_only = bit32.bor(self.proto._is_replicating, self.proto._is_read_only)
    return deep_freeze(self.proto), replica
end
function ConfigBuilder.build(self: ConfigBuilder): Config
    local mode = self.proto._mode
    if mode == "replica" then
        assert(self.proto._is_replicating == 0, "replica do not supports replication flags")
        assert(self.proto._is_persistent == 0, "replica do not supports persistent flags")
    end
    return deep_freeze(self.proto)
end

-----------------------------
-- Query
-----------------------------
local Query = {}

local function op_cids(from: int, ...): (int, mask)
    local p = from
    while type((select(p, ...))) == "number" do
        p += 1
    end
    if p > from then
        return p, args2mask(args_take(from, p - 1, ...))
    end
    return p, 0
end

local function op_not(from: int, ...): (int, mask)
    if select(from, ...) == "not" then
        return op_cids(from + 1, ...)
    end
    return from, 0
end

--- `grammar: cid* ',' "not"? ',' cid*`
local function parse_query(names: names, ...: query): (mask, mask)
    local p, mask = op_cids(1, ...)
    local n = select("#", ...)
    -- optimization for plain select query (-150ns)
    if p > n then
        return mask, 0
    end
    local select_mask = mask
    p, mask = op_not(p, ...)
    if p <= n then
        error(fmt("malformed query (exceeding input: '%*')", (select(math.min(n, p + 1), ...))), 2)
    end
    local intersect = bit32.band(select_mask, mask)
    if intersect ~= 0 then -- error branch
        local cids = { mask2args(intersect) } :: { any }
        for i = 1, #cids do
            cids[i] = names[cids[i]]
        end
        error(fmt("malformed query ('select' mask intersects with 'not' mask: %*)", table.concat(cids, ", ")), 2)
    end
    return select_mask, mask
end

local function assert_query_order(names: names?, ...: query)
    -- we only care about selection part of the query
    local p = op_cids(1, ...)
    local culprit = wrong_order(args_take(1, p - 1, ...))
    if culprit then
        local name = format_cid(culprit, names)
        error(fmt("cid: '%*' is out of order in query: %*", name, args2str(names, args_take(1, p - 1, ...))))
    end
end
local function assert_write_permission(mask: mask?, names: names, read_only: mask, ...: cid)
    -- we only care about selection part of the query
    local selection_mask = mask or args2mask(...)
    assert(mask ~= nil or select("#", ...) > 0, "you should pass mask OR cids 1")
    local intersects = bit32.band(selection_mask, read_only)
    if intersects ~= 0 then
        local cid = bit32.countrz(intersects)
        local msg
        if select("#", ...) == 1 then
            msg = fmt("column %* is read-only", args2str(names, cid))
        else
            msg = fmt("column '%*' is read-only in: %*", format_cid(cid, names), args2str(names, mask2args(selection_mask)))
        end
        error(msg, 3)
    end
end

function Query.query(state: Common<any>, ...: query): (Index<uid>, mask)
    local masks = (state :: CommonInternal<any>)._masks
    local config = (state :: CommonInternal<any>)._config
    local selection_mask, not_mask = parse_query(config._component_names, ...)
    local index: Index<uid> = Index.acquire()
    -- simple query
    if not_mask == 0 then
        if selection_mask == 0 then -- get all
            for uid, _ in masks do
                table.insert(index, uid)
            end
        else -- get by select mask
            for uid, mask in masks do
                if bit32.band(mask, selection_mask) == selection_mask then
                    table.insert(index, uid)
                end
            end
        end
        return index, selection_mask
    end
    assert(not_mask ~= 0)
    -- complex query
    if selection_mask == 0 then -- get all but not
        for uid, mask in masks do
            if bit32.btest(mask, not_mask) then
                continue
            end
            table.insert(index, uid)
        end
    else -- select_mask ~= 0
        for uid, mask in masks do
            if bit32.band(mask, selection_mask) ~= selection_mask then
                continue
            end
            if bit32.btest(mask, not_mask) then
                continue
            end
            table.insert(index, uid)
        end
    end
    return index, selection_mask
end

function Query.iterate_index(state: Common<any>, index: Index<uid>, mask: mask): ((Index<uid>, uid?) -> (uid?, ...component), Index<uid>)
    local storage = (state :: CommonInternal<any>)._storage
    local get_many = get_many_factory(storage, mask2args(mask))
    local idx = 0
    local iter = function(a: Index<uid>, uid: uid?): (uid?, ...component)
        idx += 1
        uid = a[idx]
        if uid ~= nil then
            return uid, get_many(uid)
        else
            --- @note: If the iteration is stopped prematurely (e.g., due to a break statement),
            --- the Index won't be immediately released. It will be cleaned up
            --- during the next garbage collection cycle. This isn't ideal, but it's not a significant issue.
            --- @todo: Consider to return index from iterator (uid, index, ...) and release it manually.
            Index.Release(index)
            return nil
        end
    end
    return iter, index
end

-----------------------------
-- State
-----------------------------
local State = {} :: CommonInternal<any>
function State.env(self: CommonInternal<any>, key: str, value: any?): any
    if value ~= nil then -- set
        self._environment[key] = value
        return value
    end
    return self._environment[key]
end

function State.has(self: CommonInternal<any>, uid: uid, cid: cid?)
    if cid == nil then
        return self._masks[uid] ~= nil
    end
    if __DEV__ then
        check_cid(cid)
    end
    return bit32.btest(self._masks[uid], bit32.lshift(1, cid))
end

function State.get(self: CommonInternal<any>, uid: uid, cid: cid)
    if __DEV__ then
        check_cid(cid)
        assert(self._config._component_names[cid] ~= nil, "cid not found " .. cid)
    end
    local column = self._storage[cid]
    return column[uid]
end

function State.getter(self: CommonInternal<any>, ...: cid)
    if __DEV__ then
        assert_query_order(self._config._component_names, ...)
    end
    return get_many_factory(self._storage, ...)
end

function State.set(self: CommonInternal<any>, uid: uid, cid: cid, c: component): ()
    if __DEV__ then
        check_cid(cid)
        assert_write_permission(nil, self._config._component_names, self._config._is_read_only, cid)
        local mask = self._masks[uid]
        if mask == nil then
            warn(`uid: {format_uid(uid, self._config._pretty_printer)} not found`)
        end
    end
    local setter = self._setters[cid]
    if not setter then
        check_cid(cid)
    end
    setter(uid, c)
end

function State.setter(self: CommonInternal<any>, ...: cid): (uid, ...component) -> ()
    if __DEV__ then
        assert_query_order(self._config._component_names, ...)
        assert_write_permission(nil, self._config._component_names, self._config._is_read_only, ...)
    end
    return set_many_factory(self._setters, ...)
end

function State.size(self: CommonInternal<any>)
    local uids, components = 0, 0
    for _, mask in self._masks do
        uids += 1
        components += popcount32(mask)
    end
    return uids, components
end

function State.select(self: CommonInternal<any>, ...: query)
    assert_query_order(self._config._component_names, ...)
    local index, select_mask = Query.query(self, ...)
    return Query.iterate_index(self, index, select_mask)
end

-------------------
-- Format
-------------------

function State.format_uid(self: CommonInternal<any>, uid: uid)
    return format_uid(uid, self._config._pretty_printer)
end

function State.format_row(self: CommonInternal<any>, uid: uid, mask: mask?)
    mask = mask or self._masks[uid]
    assert(type(mask) == "number" and bit32.bor(mask) == mask, "invalid mask")
    -- uid can be binary string (unsafe)
    local uid_str = State.format_uid(self, uid)
    if not mask then
        return fmt("uid: '%*' not in the state", uid_str)
    end
    local out = { fmt("%* %-16s", format_meta(self._metas[uid]), uid_str) }
    for _, cid in { mask2args(mask) } do
        table.insert(out, fmt(" %*: %* ", State.format_cid(self, cid), self._config._pretty_printer(self:get(uid, cid))))
    end
    return table.concat(out, "|")
end

function State.format_state(self: CommonInternal<any>, opt)
    local max_rows = 0
    local header = false
    if opt == nil then
        header = false
        max_rows = math.huge
    elseif opt == "*" then
        header = true
        max_rows = math.huge
    elseif opt == "h" then
        header = true
        max_rows = 0
    elseif type(opt) == "number" then
        header = true
        max_rows = opt
    end
    local out = {}

    if header then
        table.insert(out, fmt("=== State(%*): (rows: %d, components: %d)", self._config._mode, self:size()))
        local pp = self._config._pretty_printer
        format_config(self._config, out)
        if next(self._environment) then
            table.insert(out, "Environment:")
        end
        for k, v in self._environment do
            table.insert(out, "  " .. tostring(k) .. " := " .. pp(v))
        end
    end
    if header and max_rows > 0 then
        table.insert(out, "------ rows: --")
    end
    local rows = {}
    for uid in self._masks do
        table.insert(rows, State.format_row(self, uid))
    end
    table.sort(rows)
    table.move(rows, 1, math.min(#rows, max_rows), #out + 1, out)
    if #rows > max_rows then
        table.insert(out, fmt("... (%d more rows)", #rows - max_rows))
    end
    return table.concat(out, "\n")
end

function State.format_cid(self: CommonInternal<any>, cid: cid)
    return format_cid(cid, self._config._component_names)
end

function State.format_mask(self: CommonInternal<any>, mask: mask)
    return format_mask(mask, self._config._component_names)
end

function State.names(self: CommonInternal<any>): names
    return self._config._component_names
end

local function format_rows(state: CommonInternal<any>, opt: "respect-mask"?, ...: query)
    local index, select_mask = Query.query(state, ...)
    local rows = index :: { any }
    if opt == "respect-mask" then
        for i, uid in rows do
            rows[i] = State.format_row(state, uid, select_mask)
        end
    else
        for i, uid in rows do
            rows[i] = State.format_row(state, uid)
        end
    end
    local out = table.concat(index, "\n")
    index:Release()
    return out
end

function State.format_rows(self: CommonInternal<any>, ...: query)
    return format_rows(self, nil, ...)
end

function State.format_query(self: CommonInternal<any>, ...: query)
    return format_rows(self, "respect-mask", ...)
end

function State.format_log(self: CommonInternal<any>, log: transactions?)
    if log == nil then
        if self._config._mode == "main" then
            log = (self :: any)._log
        elseif self._config._mode == "replica" then
            warn("for replica state `log` parameter is mandatory")
        end
    end
    return format_log(log, self._config._component_names, self._config._pretty_printer)
end

-----------------------------
-- Main State
-----------------------------
-- state
MainState.env = State.env
MainState.has = State.has
MainState.get = State.get
MainState.getter = State.getter
MainState.set = State.set
MainState.setter = State.setter
MainState.size = State.size
MainState.select = State.select
-- format
MainState.format_cid = State.format_cid
MainState.format_uid = State.format_uid
MainState.format_mask = State.format_mask
MainState.format_row = State.format_row
MainState.format_state = State.format_state
MainState.format_rows = State.format_rows
MainState.format_query = State.format_query
MainState.format_log = State.format_log
MainState.names = State.names

function MainState.constructor(self: MainInternal, ...: cid | attribute)
    local mask, meta, arity = parse_constructor_args(self._config._component_names, ...)
    local attach_n, _count = attach_many_factory(self._storage, mask2args(mask))
    assert(arity == _count, "arity mismatch")
    local replication_mask = bit32.band(mask, self._config._is_replicating)
    local log, args_indices_to_log, log_n
    if replication_mask ~= 0 and not bit32.btest(meta, META_INTERNAL) then
        log = self._log
        args_indices_to_log = {}
        meta = bit32.bor(meta, META_SHARED)
        local temp_mask = mask
        for i = 1, arity do
            local cid = bit32.countrz(temp_mask)
            local cid_bit = bit32.lshift(1, cid)
            temp_mask = bit32.bxor(temp_mask, cid_bit)
            if bit32.btest(cid_bit, replication_mask) then
                table.insert(args_indices_to_log, i)
            end
        end
        assert(temp_mask == 0)
        log_n = function(uid, ...)
            table.insert(log, OP_CREATE)
            table.insert(log, uid)
            table.insert(log, replication_mask)
            for _, i in args_indices_to_log do
                table.insert(log, (select(i, ...)))
            end
        end
    end
    local function ctor(u: uid | gen, ...: component): uid
        local n = select("#", ...)
        if n ~= arity then
            error(`{arity} args after 'uid' expected, got {n}`)
        end
        local uid = if type(u) == "function" then u() else u
        assert(uid ~= nil, "uid is nil")
        assert(not self._masks[uid], "non-unique uid")
        self._masks[uid] = mask
        self._metas[uid] = meta
        attach_n(uid, ...)
        if log_n then
            log_n(uid, ...)
        end
        return uid
    end
    return ctor, mask
end


function MainState.flash(self: MainInternal): transactions?
    assert(self._config._mode == "main", "only main state can have a log")
    if #self._log == 0 then
        return nil
    end
    --- @note: shallow copy for future serialization
    local out = table.clone(self._log)
    table.clear(self._log)
    return out
end

function MainState.snapshot(self: MainInternal, opt: "discard-log"?): transactions
    assert(self._config._mode == "main", "only main state can be source of a snapshot")
    if opt == "discard-log" then
        table.clear(self._log)
    end
    local replicating_mask = self._config._is_replicating
    local metas = self._metas
    local cache = {}
    local snapshot = { HEADER_SNAPSHOT } :: transactions
    for uid, mask in self._masks do
        local write_mask = bit32.band(mask, replicating_mask)
        if write_mask == 0 or bit32.btest(metas[uid], META_INTERNAL) then
            continue
        end
        if not cache[write_mask] then
            cache[write_mask] = save_by_mask_factory(snapshot, self._storage, write_mask)
        end
        cache[write_mask](uid, nil)
    end
    return snapshot
end

function MainState.delete(self: MainInternal, uid: uid)
    local mask = self._masks[uid]
    if not mask then
        if __DEV__ then
            warn(`UID: {self:format_uid(uid)} does not exist`)
        end
        return
    end
    -- note main state can `delete` without write permission
    local meta = self._metas[uid]
    detach_all(uid, self._storage, self._config._destructors, self._config._component_names, mask)
    self._masks[uid] = nil
    self._metas[uid] = nil
    if bit32.btest(meta, META_SHARED) then
        table.insert(self._log, OP_DELETE)
        table.insert(self._log, uid)
    end
end

function MainState.save(self: MainInternal): transactions
    assert(self._config._mode == "main", "only main state can be persistent")
    local persistent_mask = self._config._is_persistent
    local metas = self._metas
    local cache = {}
    local save = { HEADER_SAVE } :: transactions
    for uid, mask in self._masks do
        local meta = metas[uid]
        local write_mask = bit32.band(mask, persistent_mask)
        if write_mask == 0 or bit32.btest(meta, META_TRANSIENT) then
            continue
        end
        if not cache[write_mask] then
            cache[write_mask] = save_by_mask_factory(save, self._storage, write_mask)
        end
        cache[write_mask](uid, meta)
    end
    return save
end
-- stylua: ignore
--- @note: `load` do not write to log at all, you must use `snapshot` to initialize replica state
function MainState.load(self: MainInternal, save: transactions): MainSelf
    assert(type(save) == "table", "invalid save (type)")
    assert(self:size() == 0, "acceptor state must be empty")
    if save == nil or #save == 0 then
        return self -- do nothing
    end
    local header = save[1]
    assert(header == HEADER_SAVE, "invalid save (header)")
    assert(self:size() == 0, "acceptor state must be empty")
    local metas = self._metas
    local masks = self._masks
    local cache = {}
    local n, p = #save, 2
    while p < n do
        local uid, mask, meta = table.unpack(save, p, p + 2); p += 3
        --- @note: inline assertions are also used for type coercion
        assert(type(mask) == "number" and bit32.bor(mask) == mask, "invalid save (mask)")
        assert(type(meta) == "number" and bit32.bor(meta) == meta, "invalid save (meta)")
        masks[uid] = mask
        metas[uid] = meta
        if not cache[mask] then
            local attach_n, count = attach_many_factory(self._storage, mask2args(mask))
            cache[mask] = function(uid: uid, from: int): int
                local to = from + count - 1
                attach_n(uid, table.unpack(save, from, to))
                return to + 1
            end
        end
        p = cache[mask](uid :: uid, p)
    end
    assert(p >= n, "save entries exceed expected count")
    return self
end

-----------------------------
-- Replica
-----------------------------
local ON_ATTACH_MASK_IDX = 1
local ON_MODIFY_MASK_IDX = 2
local ON_DETACH_MASK_IDX = 3

-- state
ReplicaState.env = State.env
ReplicaState.has = State.has
ReplicaState.get = State.get
ReplicaState.getter = State.getter
ReplicaState.set = State.set
ReplicaState.setter = State.setter
ReplicaState.size = State.size
ReplicaState.select = State.select
-- format
ReplicaState.format_cid = State.format_cid
ReplicaState.format_uid = State.format_uid
ReplicaState.format_mask = State.format_mask
ReplicaState.format_row = State.format_row
ReplicaState.format_state = State.format_state
ReplicaState.format_rows = State.format_rows
ReplicaState.format_query = State.format_query
ReplicaState.format_log = State.format_log
ReplicaState.names = State.names
-- replica
--- @note all entities created by replica are local and transient by default
function ReplicaState.constructor(self: ReplicaInternal, ...: cid | attribute)
    local mask, meta, arity = parse_constructor_args(self._config._component_names, ...)
    if meta ~= 0 then
        warn(debug.traceback("WARNING: replica do not support constructor attributes", 2))
    end
    local attach_n, _count = attach_many_factory(self._storage, mask2args(mask))
    assert(arity == _count, "arity mismatch")
    local changes = self._deferred_changes
    assert(#changes == 0, "deferred changes must be empty")
    local storage = self._storage
    local to_defer_mask = bit32.band(mask, self._callback_masks[ON_ATTACH_MASK_IDX])
    local to_defer_cids = if to_defer_mask ~= 0 then { mask2args(to_defer_mask) } else nil
    local function ctor(u: uid | gen, ...: component): uid
        assert(select("#", ...) == arity, "insufficient args, remainder: fist arg must be `uid` or `uid-factory`")
        local uid = if type(u) == "function" then u() else u
        assert(uid ~= nil, "uid is nil")
        assert(not self._masks[uid], "non-unique uid")
        self._masks[uid] = mask
        self._metas[uid] = meta
        attach_n(uid, ...)
        if to_defer_cids then
            defer_many_op(uid, OP_ATTACH, changes, storage, to_defer_cids)
        end
        return uid
    end
    return ctor, mask
end

local function replica_delete(self: ReplicaInternal, uid: uid, opt: "respect-meta"?)
    local mask = self._masks[uid]
    if not mask then
        if __DEV__ then
            warn(fmt("UID: %* not in this state", self:format_uid(uid)))
        end
        return
    end
    if opt == "respect-meta" then
        local meta = self._metas[uid]
        if bit32.btest(meta, META_SHARED) then
            error(`{self:format_uid(uid)}: cannot delete shared entity from replica`, 3)
        end
    end
    local to_defer_mask = bit32.band(mask, self._callback_masks[ON_DETACH_MASK_IDX])
    local to_defer_cids = if to_defer_mask ~= 0 then { mask2args(to_defer_mask) } else nil
    if to_defer_cids then
        defer_many_op(uid, OP_DETACH, self._deferred_changes, self._storage, to_defer_cids)
    end
    detach_all(uid, self._storage, self._config._destructors, self._config._component_names, mask)
    self._masks[uid] = nil
    self._metas[uid] = nil
end

local function replica_create_factory(self: ReplicaInternal, mask: mask, log: transactions)
    local storage = self._storage
    local changes = self._deferred_changes
    local attach_n, count = attach_many_factory(storage, mask2args(mask))
    local to_defer_mask = bit32.band(mask, self._callback_masks[ON_ATTACH_MASK_IDX])
    local to_defer_cids = if to_defer_mask ~= 0 then { mask2args(to_defer_mask) } else nil
    return function(uid: uid, from: int): int
        local to = from + count - 1
        attach_n(uid, table.unpack(log, from, to))
        if to_defer_cids then
            defer_many_op(uid, OP_ATTACH, changes, storage, to_defer_cids)
        end
        return to + 1
    end
end

-- stylua: ignore
--- Initializes a replica state from a snapshot
--- @param snapshot: Transaction log containing initial state
--- @return self for method chaining
function ReplicaState.init(self: ReplicaInternal, snapshot: transactions)
    assert(type(snapshot) == "table", "invalid snapshot (type)")
    assert(self:size() == 0, "acceptor state must be empty")
    if snapshot == nil or #snapshot == 0 then
        return self -- do nothing
    end
    local header = snapshot[1]
    assert(header == HEADER_SNAPSHOT, "invalid snapshot (header)")
    local masks = self._masks
    local metas = self._metas
    local changes = self._deferred_changes
    assert(#changes == 0, "deferred changes must be empty")
    local cache = {}
    local n, p = #snapshot, 2
    while p < n do
        local uid, mask = table.unpack(snapshot, p, p + 1); p += 2
        assert(type(mask) == "number" and bit32.bor(mask) == mask, "invalid snapshot (mask)")
        if __DEV__ then
            assert(type(uid) == "number" or type(uid) == "string", "invalid snapshot (uid)")
        end
        masks[uid] = mask
        metas[uid] = META_SHARED
        if not cache[mask] then
            cache[mask] = replica_create_factory(self, mask, snapshot)
        end
        p = cache[mask](uid :: uid, p)
    end
    assert(p >= n, "snapshot entries exceed expected count")
    process_deferred_changes(self)
    return self
end

-- stylua: ignore
--- Updates replica state by applying a transaction log
--- @param log: Optional transaction log to apply
function ReplicaState.update(self: ReplicaInternal, log: transactions?)
    if not log or #log == 0 then
        return
    end
    local changes = self._deferred_changes
    local storage = self._storage
    local masks = self._masks
    local create_cache = {}
    local on_attach_mask = self._callback_masks[ON_ATTACH_MASK_IDX]
    local on_detach_mask = self._callback_masks[ON_DETACH_MASK_IDX]
    local on_modify_mask = self._callback_masks[ON_MODIFY_MASK_IDX]
    local p, n = 1, #log
    while p < n do
        local header, uid = table.unpack(log, p, p + 1); p += 2
        assert(type(header) == "number" and bit32.bor(header) == header, "invalid log (header)")
        self._metas[uid] = META_SHARED
        local mask = masks[uid] or 0
        local op = bit32.band(header, PACKED_OP_MASK)
        if op == OP_ATTACH then
            local value = log[p]; p += 1
            local cid = bit32.band(header, PACKED_CID_MASK)
            local bit = bit32.lshift(1, cid)
            masks[uid] = bit32.bor(mask, bit)
            storage[cid][uid] = value
            if bit32.btest(on_attach_mask, bit) then
                table.insert(changes, header)
                table.insert(changes, uid)
                table.insert(changes, value) -- new
            end
        elseif op == OP_DETACH then
            local cid = bit32.band(header, PACKED_CID_MASK)
            local bit = bit32.lshift(1, cid)
            if __DEV__ then
                assert(mask, "missing mask")
                assert(bit32.btest(mask, bit), "mask bit not set")
                assert(storage[cid][uid] ~= nil, "missing old value")
            end
            if bit32.btest(on_detach_mask, bit) then
                table.insert(changes, header)
                table.insert(changes, uid)
                table.insert(changes, storage[cid][uid]) -- old
            end
            masks[uid] = bit32.replace(mask, 0, cid, 1)
            storage[cid][uid] = nil
        elseif op == OP_MODIFY then
            local value = log[p]; p += 1
            local cid = bit32.band(header, PACKED_CID_MASK)
            local bit = bit32.lshift(1, cid)
            if __DEV__ then
                assert(bit32.btest(mask, bit), "mask bit not set")
                assert(storage[cid][uid] ~= nil, "missing old value")
            end
            if bit32.btest(on_modify_mask, bit) then
                table.insert(changes, header)
                table.insert(changes, uid)
                table.insert(changes, storage[cid][uid]) -- old
            end
            storage[cid][uid] = value
        elseif op == OP_CREATE then
            local m = log[p]; p += 1
            assert(type(m) == "number" and bit32.bor(m) == m, "invalid mask")
            mask = m
            if not create_cache[mask] then
                create_cache[mask] = replica_create_factory(self, mask, log)
            end
            p = create_cache[mask](uid, p)
        elseif op == OP_DELETE then
            replica_delete(self, uid)
        end
    end -- while
    assert(p >= n, "log entries exceed expected count")
    process_deferred_changes(self) -- we apply changes after state is stabilized
end

function ReplicaState.delete(self: ReplicaInternal, uid: uid)
    replica_delete(self, uid, "respect-meta")
    process_deferred_changes(self) -- we apply changes after state is stabilized
end

local function replica_set_callback(self: ReplicaInternal, cid: cid, mask: mask, callbacks: map<cid, on_changes | false>, callback: on_changes?): mask
    check_cid(cid)
    local bit = bit32.lshift(1, cid)
    if callback then
        if bit32.btest(mask, bit) then
            error("callback already set for cid: " .. self:format_cid(cid))
        end
        assert(type(callback) == "function", "invalid callback type")
        callbacks[cid] = callback
        return bit32.replace(mask, 1, cid, 1)
    elseif not bit32.btest(mask, bit) then
        warn("callback was not set for cid: " .. self:format_cid(cid))
        return mask
    else
        callbacks[cid] = false
        return bit32.replace(mask, 0, cid, 1)
    end
end

function ReplicaState.set_on_attach(self: ReplicaInternal, cid: cid, callback: on_attach?)
    self._callback_masks[ON_ATTACH_MASK_IDX] = replica_set_callback(self, cid, self._callback_masks[ON_ATTACH_MASK_IDX], self._on_attach, callback)
    return self
end
function ReplicaState.set_on_modify(self: ReplicaInternal, cid: cid, callback: on_modify?)
    self._callback_masks[ON_MODIFY_MASK_IDX] = replica_set_callback(self, cid, self._callback_masks[ON_MODIFY_MASK_IDX], self._on_modify, callback)
    return self
end
function ReplicaState.set_on_detach(self: ReplicaInternal, cid: cid, callback: on_detach?)
    self._callback_masks[ON_DETACH_MASK_IDX] = replica_set_callback(self, cid, self._callback_masks[ON_DETACH_MASK_IDX], self._on_detach, callback)
    return self
end

-----------------------------
-- Module
-----------------------------
local m = {}

function m.main(config: Config?): MainSelf
    config = config or DEFAULT_CONFIG
    assert(config, "type coercion")
    assert(config._mode == "main", "mode mismatch")
    local component_names = config._component_names
    --- @note: optimization tip: avoid using `cid = 0` ^_^. We pad the array with
    -- false to avoid the hash part. Accessing is slightly faster.
    local storage = (table.create(31, false) :: any) :: storage
    local setters = (table.create(31, false) :: any) :: setters
    local log = {} :: transactions
    local masks = {} :: masks
    local metas = {} :: metas
    for cid = 0, 31 do
        --- @note: we create columns only for named components (config)
        if not config._component_names[cid] then
            continue
        end
        local column = {}
        storage[cid] = column
        local bit = bit32.lshift(1, cid)
        local is_read_only = bit32.btest(config._is_read_only, bit)

        --- @note: readonly assumes there is no `set`,
        if is_read_only then
            setters[cid] = read_only_setter(cid, component_names)
            continue
        end

        local is_local = not bit32.btest(config._is_replicating, bit)
        local destructor = config._destructors[cid]
        setters[cid] = function(uid: uid, value: component)
            --- @note: we can create entity without constructor just by the setter
            local mask = masks[uid] or 0
            local meta = metas[uid] or 0
            local is_replicable = not (is_local or bit32.btest(meta, META_INTERNAL))
            local old = column[uid]
            if old == value then
                if __DEV__ and is_replicable then
                    --- @note: The user can modify the object and reassign it to the
                    --- component, expecting this operation to be replicated, but
                    --- that won't happen. It's generally a bad idea to store mutable data in state.
                    --- The only exception is Instance, but it should not be is_replicable.
                    local t = type(value)
                    --- @todo: should we be more strict?
                    if (t == "table" and not table.isfrozen(value :: any)) or (t == "userdata") then
                        local fmt_str = "cid: %*: reassigning the same object of the reference's type: '%*'."
                        error(fmt(fmt_str, format_cid(cid, config._component_names), typeof(value)), 3)
                    end
                end
                return -- early return
            end
            if value == nil then
                if bit32.btest(mask, bit) then
                    if __DEV__ then
                        assert(column[uid] ~= nil, "sanity check")
                    end
                    masks[uid] = bit32.replace(mask, 0, cid, 1)
                    if is_replicable then
                        table.insert(log, bit32.bor(OP_DETACH, cid))
                        table.insert(log, uid)
                    end
                else -- if value == nil and mask not set for this cid: we do nothing
                    assert(old == nil, "sanity check")
                end
            else -- assume old ~= value
                masks[uid] = bit32.bor(mask, bit)
                if is_replicable then
                    table.insert(log, bit32.bor(if old == nil then OP_ATTACH else OP_MODIFY, cid))
                    table.insert(log, uid)
                    log_component(log, value)
                    meta = bit32.bor(meta, META_SHARED)
                end
            end
            metas[uid] = meta
            column[uid] = value
            if old ~= nil and destructor then
                pcall_destructor(cid, component_names, destructor, old)
            end
        end
    end
    local self = {} :: MainInternal
    self._config = config
    self._environment = {}
    self._masks = masks
    self._metas = metas
    self._setters = setters
    self._storage = storage
    self._log = log
    return table.freeze(setmetatable(self, MainState)) :: any
end

function m.replica(config: Config?): ReplicaSelf
    config = config or DEFAULT_CONFIG
    assert(config, "type coercion")
    assert(config._mode == "replica", "mode mismatch")
    assert(config._is_persistent == 0, "persistent mode not supported")
    assert(config._is_replicating == 0, "replicating mode not supported")

    local component_names = config._component_names
    --- @todo: can we keep setters/getters array without hash part? or just convention: do not use cid=0
    local setters = (table.create(31, false) :: any) :: setters
    --- @note: deleters and inserters do not suppose to change mask and meta
    local storage = (table.create(31, false) :: any) :: storage
    local masks = {} :: masks
    local metas = {} :: metas

    --- @note: for performance reasons callback storage will be an array of functions|false
    local on_attach = (table.create(31, false) :: any) :: { on_attach }
    local on_detach = (table.create(31, false) :: any) :: { on_detach }
    local on_modify = (table.create(31, false) :: any) :: { on_modify }
    local setter_in_use = false
    for cid = 0, 31 do
        --- @note: we create columns only for named components (config)
        if not config._component_names[cid] then
            continue
        end
        local column = {}
        storage[cid] = column
        local bit = bit32.lshift(1, cid)
        local is_read_only = bit32.btest(config._is_read_only, bit)
        --- @note: readonly assumes there is no `set`,
        if is_read_only then
            setters[cid] = read_only_setter(cid, component_names)
            continue
        end
        local destructor = config._destructors[cid]
        setters[cid] = function(uid: uid, value: component)
            if setter_in_use then
                error("setter called recursively", 3)
            end
            setter_in_use = true
            --- @note: we can create entity without constructor just by the setter
            local mask = masks[uid] or 0
            local old = column[uid]
            if value == nil then
                if bit32.btest(mask, bit) then
                    if __DEV__ then
                        assert(old ~= nil, "sanity check")
                    end
                    masks[uid] = bit32.bxor(mask, bit) -- assume bit was set
                    column[uid] = nil
                    --- @note: on_detach is a dynamic method, unlike the destructor
                    if on_detach[cid] then
                        pcall_callback(uid, cid, OP_DETACH, config, on_detach[cid], old, nil)
                    end
                    if destructor then
                        pcall_destructor(cid, component_names, destructor, old)
                    end
                else
                    -- if value == nil and mask not set for this cid: we do nothing
                end
            else -- value ~= nil
                column[uid] = value
                masks[uid] = bit32.bor(mask, bit)
                if old == nil and on_attach[cid] then
                    pcall_callback(uid, cid, OP_ATTACH, config, on_attach[cid], value, nil)
                elseif old ~= nil and on_modify[cid] then
                    pcall_callback(uid, cid, OP_MODIFY, config, on_modify[cid], value, old)
                end
            end
            setter_in_use = false
        end
    end
    local self = {} :: ReplicaInternal
    self._config = config
    self._environment = {}
    self._masks = masks
    self._metas = metas
    self._setters = setters
    self._storage = storage
    self._on_attach = on_attach
    self._on_detach = on_detach
    self._on_modify = on_modify
    self._callback_masks = { 0, 0, 0 }
    self._deferred_changes = {}
    return table.freeze(setmetatable(self, ReplicaState)) :: any
end

-----------------------------
-- Quick Test
-----------------------------
---[[
-- component names
local C = {
    Id = 1,
    A = 10,
    B = 11,
    C = 12,
    X = 21,
    QQ = 29,
    RR = 30,
    SS = 31,
}

-- stylua: ignore
local _Id = {
    GEM    = 10_001,
    GOLD   = 10_002,
    SILVER = 10_003,
}

local _fresh = 0
local function _toy_uid(): str
    _fresh += 1
    return fmt("fresh!%.4d", _fresh)
end

local function _toy_destructor(o: component)
    print("destructor", o)
end

local _test_main_config, repl = ConfigBuilder.create()
    :set_component_names(C)
    :set_persistent_flag(C.Id, C.A, C.B, C.C, C.X)
    :set_replication_flag(C.Id, C.A, C.B, C.C)
    :set_destructor(C.SS, _toy_destructor)
    :set_read_only_flag(C.Id)
    :build_with_replica()
local _test_replica_conf = repl:build()
--]]

---[[ operations
do
    local st = m.main(_test_main_config)
    local sta = st :: any
    for name, id in C do
        assert(sta._config._component_names[id] == name, "sanity check")
        assert(sta._storage[id] ~= nil, "sanity check")
    end
    local row = st:constructor(C.Id, C.A, C.B)
    local uid1 = row("GEMS", _Id.GEM, 10, 100)
    local uid2 = row("GOLD", _Id.GOLD, 100, 1000)
    local uid3 = row("SILVER", _Id.SILVER, 1000, 10000)
    local snap = st:snapshot()
    print("log after snap")
    print(st:format_log())
    print(st:format_state("*"))
    -- print(st:format_log(snap))
    print(st:get(uid1, C.Id))
    do -- read-only field
        local ok, err: any = pcall(st.set, st, uid1, C.Id, 100)
        assert(not ok and err:find("read.only"))
    end
    st:set(uid1, C.A, 111)
    st:set(uid1, C.B, nil)
    st:set(uid2, C.B, 2000)
    st:delete(uid3)
    local repl1 = m.replica(_test_replica_conf)
        :set_on_attach(C.Id, function(...)
            print("Id on_attach", ...)
        end)
        :set_on_detach(C.Id, function(...)
            print("Id on_detach", ...)
        end)
        :set_on_modify(C.B, function(uid, new, old)
            print("on modify", uid, "C.B", old, "->", new)
        end)
    repl1:init(snap)
    print(repl1:format_state("*"))
    repl1:update(st:flash() or {})
    print(repl1:format_state("*"))
    local r_row, r_row_mask = repl1:constructor(C.Id, C.X)
    print(repl1:format_mask(r_row_mask))
    local r_uid1 = r_row("G-x", 2000, "xxx")
    local r_uid2 = r_row("G-y", 3000, "yyy")
    repl1:delete(r_uid2)
    repl1:set(r_uid1, C.X, 10000)
    print(repl1:format_state("*"))
    warn("--")
    for uid, id, a in st:select(C.Id, C.A, "not", C.SS) do
        print(">", uid, "id", id, "A", a)
        st:set(uid, C.SS, "+ss " .. uid)
    end
    for uid, id, a, ss in st:select(C.Id, C.A, C.SS) do
        print(">>", uid, "id", id, "A", a, "ss", ss)
    end
    for uid, id, a, ss in st:select(C.Id, C.A, C.SS) do
        st:delete(uid)
    end
    repl1:update(st:flash() or {})
    repl1:set_on_modify(C.SS, function(uid, new, old)
        repl1:set(uid, C.SS, "A")
    end)
    local r_ctor = repl1:constructor(C.SS)
    r_ctor("id001", "A")
    repl1:set("id001", C.SS, "B") --> pcall ERROR
end
--]]

--[=[ performance
--[[ stylua: ignore]] script = script or require'script'
local perfn = require(script.Parent.perfn)
local N = 1000
local M = 10
local _test_main_conf1, repl1 = ConfigBuilder.create()
    :set_component_names(C)
    :set_persistent_flag(C.Id, C.A, C.B, C.C, C.X)
    :set_destructor(C.SS, function(o) print("call destructor", o) end)
    :set_read_only_flag(C.Id)
    :build_with_replica()
local _test_replica_conf1 = repl1:build()

local _st1 = m.main(_test_main_conf1)
local ctor3 = _st1:constructor(C.A, C.B, C.C)

for i = 1, N do
    ctor3(_toy_uid, 1, 2, 3)
end
local sum = 0
perfn()
perfn("new", function(i)
    local _ = m.main(_test_main_config)
end, M)
perfn("new+1K ctor3", function(i)
    local st1 = m.main(_test_main_config)
    local ctor3 = st1:constructor(C.A, C.B, C.C)
    for i = 1, N do
        ctor3(_toy_uid, 1, 2, 3)
    end
end, M)

perfn("select3-1K", function()
    sum = 0
    for uid, a, b, c in _st1:select(C.A, C.B, C.C) do
        sum += (a + b + c)
    end
end, M)
assert(sum == 6 * N)

local get3 = _st1:getter(C.A, C.B, C.C)
local set3 = _st1:setter(C.A, C.B, C.C)
perfn("index3-1K", function()
    sum = 0
    local index = Query.query(_st1, C.A, C.B, C.C)
    for _, uid in ipairs(index) do
        local a, b, c = get3(uid)
        sum += (a + b + c)
    end
    index:Release()
end, M)
assert(sum == 6 * N)
perfn("index3-1K+set3", function()
    sum = 0
    local index = Query.query(_st1, C.A, C.B, C.C)
    for _, uid in ipairs(index) do
        local a, b, c = get3(uid)
        sum += (a + b + c)
        set3(uid, c, b, a)
    end
    index:Release()
end, M)
perfn("index0-1K", function()
    sum = 0
    local get1 = _st1:getter(C.A)
    local index = Query.query(_st1)
    for _, uid in ipairs(index) do
        sum += get1(uid)
    end
    index:Release()
end, M)

local _count = 0
perfn("3K insert in Index", function()
    local arr = Index.acquire()
    for i = 1, 3 * N do
        table.insert(arr, i)
    end
    arr:Release()
end, M)
--]=]

-----------------------------
-- Exports
-----------------------------

m.Index = Index
m.ConfigBuilder = ConfigBuilder
m.Query = Query
m.Util = {
    mask2args = mask2args,
    args2mask = args2mask,
    format_config = function(c: Config)
        local out = { "Config: " .. c._mode }
        return table.concat(format_config(c, out), "\n")
    end,
}
warn("[state -- ok]")
return m

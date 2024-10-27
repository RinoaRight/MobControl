--!strict
---@class Array
local m = {}

local remove = table.remove
local fmt = string.format

type bool = boolean
type str = string
type num = number
type integer = number
type int = integer
type u32 = integer
type i32 = integer
type u8 = integer
export type array<a> = { [integer]: a }
type heap<a> = array<a>
type ordered<a> = array<a>
type less<a, b = a> = (a, b) -> bool
type eq<a, b = a> = (a, b) -> bool
type predicate<a> = (a) -> bool
type comparable = array<num | str> -- non empty array

-----------------------------------------------------------
-- Predicates to lexicographically sort arrays of arrays
-----------------------------------------------------------
function m.lt(a: comparable, b: comparable): bool
    if _G.__DEV__ then
        assert(#a > 0 and #a == #b, "contract violation")
    end
    if (a[1] :: num) < (b[1] :: num) then
        return true
    end
    for i = 1, #b do
        if (a[i] :: num) < (b[i] :: num) then
            return true
        end
    end
    return false
end

function m.gt(a: comparable, b: comparable): bool
    if _G.__DEV__ then
        assert(#a > 0 and #a == #b, "contract violation")
    end
    if (b[1] :: num) < (b[1] :: num) then
        return true
    end
    for i = 1, #b do
        if (b[i] :: num) < (a[i] :: num) then
            return true
        end
    end
    return false
end
function m.eq(a: comparable, b: comparable): bool
    if _G.__DEV__ then
        assert(#a > 0 and #a == #b, "contract violation")
    end
    if (b[1] :: num) ~= (b[1] :: num) then
        return false
    end
    for i = 1, #b do
        if (b[i] :: num) ~= (a[i] :: num) then
            return false
        end
    end
    return true
end

assert(m.lt({ "A", 2, 3 }, { "B", 2, 3 }))
assert(m.lt({ "A", 2, 3 }, { "A", 3, 3 }))
assert(m.lt({ "A", 2, 3 }, { "A", 2, 4 }))
assert(m.gt({ "B", 2, 3 }, { "A", 2, 3 }))
assert(m.gt({ "A", 3, 3 }, { "A", 2, 3 }))
assert(m.gt({ "A", 2, 4 }, { "A", 2, 3 }))

function m.last<a>(a: array<a>)
    return a[#a]
end

---@deprecated use table.clone
---@param source any[]
---@param dest? any[] @ will be overridden
local function copy<a>(source: array<a>, dest: array<a>?)
    if dest then
        table.clear(dest)
    end
    local out: array<a> = dest or table.create(#source)
    for i, v in ipairs(source) do
        out[i] = v
    end
    return out
end
m.copy = copy

---@deprecated use table.clone
local function copy0<a>(source: array<a>, dest: array<a>?): array<a>
    if dest then
        table.clear(dest)
    end
    local out: array<a> = dest or table.create(#source)
    out[0] = source[0]
    for i = 1, #source do
        out[i] = source[i]
    end
    return out
end
m.copy0 = copy0

---@nodiscard
---@param array any[] @ 1-indexed array
---@param prev_idx? integer @ in [0, max_integer]
---@return any element, integer index
local function cyclic(array, prev_idx)
    local n = #array
    if n == 0 then
        return nil, 0
    end
    prev_idx = prev_idx or 0
    local i = prev_idx % n + 1
    return array[i], i
end
m.cyclic = cyclic

---@nodiscard
---@param array0 any[] @ 0-indexed array
---@param prev_idx? integer @ in [-1, max_integer]
---@return any element, integer index
local function cyclic0(array0, prev_idx)
    prev_idx = prev_idx or -1
    local i = (prev_idx + 1) % (#array0 + 1)
    return array0[i], i
end
m.cyclic0 = cyclic0

local function equals(a1, a2)
    if a1 == a2 then
        return true
    end
    if #a1 ~= #a2 then
        return false
    end
    for i = 1, #a1 do
        if a1[i] ~= a2[i] then
            return false
        end
    end
    return true
end
m.equals = equals

---@param n integer
---@param val? any
---@return any[]
local function make0<a>(n: u32, val: a): array<a>
    local out = table.create(n - 1, val)
    out[0] = val
    return out
end
m.make0 = make0

-- remove at idx and swap with last element of array, O(1) and 10x faster then table.remove. Doesn't retain original order
---@param array any[]
---@param idx integer
---@return any
local function swap_remove<a>(array: array<a>, idx: u32): a
    local value = array[idx]
    local n = #array
    array[idx], array[n] = array[n], nil
    return value
end

m.swap_remove = swap_remove

function m.concat<a>(...: array<a>): array<a>
    local out = {}
    for i = 1, select("#", ...) do
        for _, v in select(i, ...) do
            table.insert(out, v)
        end
    end
    return out
end

function m.is(a: any)
    if type(a) ~= "table" then
        return false
    end
    local c = 0
    for _ in a do
        c += 1
    end
    return c == #a
end

---@generic T
---@param array T[]
---@param some T
---@return integer?
function m.remove<a>(array: array<a>, some: a): i32?
    local i = table.find(array, some)
    if i then
        local _ = remove(array, i)
        return i
    end
    return nil
end

---@param array any[]
---@param reset fun(a:any):any
---@return any[]
function m.reset<a>(array: { a }, reset: (a) -> a): { a }
    assert(reset)
    for i = 1, #array do
        array[i] = reset(array[i])
    end
    return array
end

local function swap<a>(a: array<a>, i, j)
    a[i], a[j] = a[j], a[i]
end

m.swap = swap
local function swap2<a>(a: array<a>, i: u32, t: array<a>, j: u32)
    t[j], a[i] = a[i], t[j]
end
m.swap2 = swap2

---@summary: in-place array reverse, perf: ~10us for 1K array
local function reverse<a>(a: array<a>)
    local i = 1
    local n = #a
    while i < n do
        -- swap(a, i, n)
        a[i], a[n] = a[n], a[i]
        i += 1
        n -= 1
    end
end
m.reverse = reverse

function m.sum(a: array<num>)
    local result = 0
    for _, v in ipairs(a) do
        result += v
    end
    return result
end

function m.to_set<a>(a: array<a>): { [a]: bool }
    local out = {}
    for _, v in ipairs(a) do
        out[v] = true
    end
    return out
end

---@summary: insertion sort: stable, good for near-sorted arrays
local function insertion_sort<a>(array: array<a>, less: less<a>)
    local n = #array
    for i = 2, n do
        local val = array[i]
        local j = i - 1
        while j > 0 and less(val, array[j]) do
            array[j + 1] = array[j]
            j = j - 1
        end
        array[j + 1] = val
    end
    return array
end
m.insertion_sort = insertion_sort

local function is_sorted<a>(array: array<a>, less: less<a>, max_count: int?): (bool, int)
    local n = #array
    local count = 0
    max_count = max_count or 4
    for i = 2, n do
        local j = i - 1
        if not less(array[j], array[i]) then
            count += 1
            if count >= max_count :: int then
                return false, count
            end
        end
    end
    return count == 0, count
end
m.is_sorted = is_sorted

-- insertion sort: stable, good for near-sorted arrays
local function insertion_sort_num(array: { number })
    local n = #array
    for i = 2, n do
        local val = array[i]
        local j = i - 1
        while j > 0 and (val < array[j]) do
            array[j + 1] = array[j]
            j = j - 1
        end
        array[j + 1] = val
    end
    return array
end
m.insertion_sort_num = insertion_sort_num

---@param array any[]
---@param key any
local function insertion_sort_by_key(array: array<any>, key: any)
    local n = #array
    if n < 2 then
        return array
    end
    for i = 2, n do
        local x = array[i]
        local val = x[key]
        local j = i - 1
        while j > 0 and val < array[j][key] do
            array[j + 1] = array[j]
            j = j - 1
        end
        array[j + 1] = x
    end
    return array
end
m.insertion_sort_by_key = insertion_sort_by_key

---@param array any[]
---@param key any
local function insertion_sort_by_key_gt(array, key)
    local n = #array
    if n < 2 then
        return array
    end
    for i = 2, n do
        local x = array[i]
        local val = x[key] :: num
        local j = i - 1
        while j > 0 and array[j][key] < val do
            array[j + 1] = array[j]
            j = j - 1
        end
        array[j + 1] = x
    end
    return array
end
m.insertion_sort_by_key_gt = insertion_sort_by_key_gt

---@summary: leftmost binary search with .Net return style (index or ~index)
-- returns >= 1 --> leftmost match
-- return  <= 0 --> -index of first larger element
---@param presorted any[] @ sorted!
---@param value any
---@param less fun(a:any, b:any):boolean
local function binsearch<a>(presorted: ordered<a>, value: a, less: less<a>): i32
    local lo = 1
    local hi = #presorted
    while lo <= hi do
        local pivot = lo + bit32.rshift(hi - lo, 1)
        local el = presorted[pivot]
        if less(el, value) then
            lo = pivot + 1
        elseif less(value, el) then
            hi = pivot - 1
        else
            return pivot
        end
    end
    return -lo
end
m.binsearch = binsearch

---@summary: leftmost binary search with (index or -index) return style
-- returns >= 1 --> leftmost match
-- returns  < 0 --> negated index of first larger element
---@param presorted number[] @ sorted!
---@param value number
---@return integer
local function binsearch_num(presorted: ordered<num>, value: num)
    local lo = 1
    local hi = #presorted
    while lo <= hi do
        local pivot = lo + bit32.rshift(hi - lo, 1)
        local el = presorted[pivot]
        if el < value then
            lo = pivot + 1
        elseif value < el then
            hi = pivot - 1
        else
            return pivot
        end
    end
    return -lo
end
m.binsearch_num = binsearch_num

---@summary: rightmost binary search with (index or -index) return style
-- returns >= 1 --> rightmost match
-- return   < 0 --> -index of first larger element
---@param a any[] @ sorted!
---@param value any
---@param less? fun(a:any, b:any):boolean
---@return integer
local function binsearch_rightmost<a>(a: ordered<a>, value: a, less: less<a>, eq: eq<a>?): i32
    local lo = 0
    local hi = #a
    while lo < hi do
        local pivot = lo + bit32.rshift(hi - lo, 1)
        if less(value, a[pivot + 1]) then
            hi = pivot
        else
            lo = pivot + 1
        end
    end

    if eq then
        return eq(a[hi], value) and hi or -(hi + 1)
    end
    return a[hi] == value and hi or -(hi + 1)
end
m.binsearch_rightmost = binsearch_rightmost

---@summary: inserts value in presorted array
---@perf: ~ 5us/1K, 100x faster then `push + table.sort`, 5x faster then `push + insertion sort`
local function ordered_push<a>(presorted: ordered<a>, value: a, less: less<a>)
    local i: int = binsearch(presorted, value, less)
    table.insert(presorted, math.abs(i), value)
end
m.ordered_push = ordered_push

---@summary: inserts value in presorted array
---@perf: like `ordered_push`
local function ordered_push_rightmost<a>(presorted: ordered<a>, value: a, less: less<a>, eq: eq<a>?)
    local i: int = binsearch_rightmost(presorted, value, less, eq)
    if i < 0 then
        i = -i
    else
        i += 1
    end
    table.insert(presorted, i, value)
end
m.ordered_push_rightmost = ordered_push_rightmost

function m.remove_less<a>(a: array<a>, less: less<a>)
    local lo_idx = 1
    local lo: a = a[lo_idx]
    for i, v in ipairs(a) do
        if less(v, lo) then
            lo_idx = i
            lo = v
        end
    end
    return swap_remove(a, lo_idx)
end

---@summary array mutation that will retain it's order and identity
---@param a any[]
---@param indices_to_remove integer[] @ unsorted *unique* indices to remove from array
local function remove_indices<a>(a: array<a>, indices_to_remove: array<u32>): ()
    if not indices_to_remove or #indices_to_remove == 0 then
        return
    end
    for _, v in ipairs(indices_to_remove) do
        assert(0 < v and v <= #a, "index out of bound")
    end
    local n = #indices_to_remove
    if n == 0 then
        return
    else
        table.sort(indices_to_remove)
    end
    local write = 0
    local i = 1
    for read = 1, #a do
        if i > n or read < indices_to_remove[i] then
            write += 1
            a[write] = a[read]
        else
            i += 1
        end
    end
    -- clear tail
    for clear = write + 1, #a do
        a[clear] = nil
    end
end
m.remove_indices = remove_indices

local function shuffle<a>(a: array<a>)
    for i = #a, 2, -1 do
        local r = math.random(i)
        swap(a, r, i)
    end
    return a
end
m.shuffle = shuffle

-----------------------------
-- Frozen array
-----------------------------
m.frozen = {}

function m.frozen.is(a: any)
    return table.isfrozen(a)
end

function m.freeze<a>(x: array<a>): array<a>
    if type(x) == "table" and not table.isfrozen(x) then
        return table.freeze(x)
    end
    return x
end

function m.frozen.copy<a>(a: array<a>): array<a>
    return table.clone(a)
end

function m.frozen.with<a>(a: array<a>, idx: int, val: any)
    if a[idx] == nil then
        error("bad indexing: " .. idx)
    end
    local dirty = a[idx] ~= val
    if dirty then
        a = table.clone(a)
        a[idx] = val
    end
    return m.freeze(a)
end

-----------------------------
-- immutable vector 1..4
-----------------------------
do -- vec
    -- stylua: ignore
    export type vec<a> = {
        X: a, x: a, R: a, r: a, U: a, u: a,
        Y: a, y: a, G: a, g: a, V: a, v: a,
        Z: a, z: a, B: a, b: a,
        W: a, w: a, A: a, a: a,
        with: (self: vec<a>, { [str]: a } | str, a?) -> vec<a>
    }

    -- stylua: ignore
    local convert_key = setmetatable({
        X = 1, x = 1, R = 1, r = 1, U = 1, u = 1,
        Y = 2, y = 2, G = 2, g = 2, V = 2, v = 2,
        Z = 3, z = 3, B = 3, b = 3,
        W = 4, w = 4, A = 4, a = 4,
    }, { __index = function(_, k) return k end })

    local vec = {}
    function vec.__index<a>(self: vec<a>, k: any)
        return rawget(self, convert_key[k]) or vec[k] or error(fmt("no such key: '%*'", k))
    end

    function vec.__newindex<a>(self: vec<a>, k, val)
        warn("~", self, k, val)
        error(fmt("readonly and has no key: '%*'", k), 3)
    end

    function vec.with<a>(self: vec<a>, vals_or_key: { [str]: a } | str, val: a?): vec<a>
        local clone = table.clone(self)
        if type(vals_or_key) == "string" then -- key
            clone[convert_key[vals_or_key]] = val
        else
            for k: str, v: a in pairs(vals_or_key) do
                clone[convert_key[k]] = v
            end
        end
        return table.freeze(clone)
    end

    function m.wrap<a>(a: array<a>): vec<a>
        return (table.freeze(setmetatable(a, vec)) :: any) :: vec<a>
    end
end

function m.pp<a>(a:array<a>, to_string: ((a)-> str)?)
    if to_string then
        local ret = {}
        for i, v in a do
            ret[i] = to_string(v)
        end
        return table.concat(ret, ", ")
    end
    return table.concat(a, ", ")
end
-----------------
-- Test
-----------------
local DELIM = " "

local function join(a: array<any>)
    return table.concat(a, " ")
end


local function split(a: str): array<num>
    local out = {} :: array<num>
    for i, v in ipairs(a:split(DELIM)) do
        out[i] = assert(tonumber(v))
    end
    return out
end

local function _ppa<a>(a: array<a>, ...)
    print(join(a), ...)
end

do -- split/join
    local a: str = "1 3 2 7 6 4 5"
    assert(join(split(a)) == a)
end

local function test_sorted_push()
    -- only first char matter
    local lt = function(a: str, b: str)
        return a:byte() < b:byte()
    end

    -- only first char matter
    local eq = function(a: str, b: str)
        return a:byte() == b:byte()
    end

    local a = { "A", "B", "C" }
    ordered_push(a, "AA", lt)
    -- _ppa(a)
    ordered_push_rightmost(a, "BB", lt, eq)
    -- _ppa(a)
    assert(join(a) == "AA A B BB C")
    -- _ppa(a)
    local b = { "A" }
    -- _ppa(b)
    ordered_push_rightmost(b, "AA", lt, eq)
    -- _ppa(b)
    ordered_push_rightmost(b, "AAA", lt, eq)
    -- _ppa(b)
    assert(join(b) == "A AA AAA")
    -- _ppa(a)
end

local function test_vec()
    local a = { 1, 2, 3 }
    local v = m.wrap(a)
    assert(v.x == 1)
    assert(v.z == 3)
    v = v:with { z = 5 }
    assert(v.z == 5)
    v = v:with("R", 42)
    assert(v.x == v.R and v.R == 42)
end

local function test_frozen()
    local b = { 1, 2, 3 }
    local ib = m.freeze(b)
    ib = m.frozen.with(ib, 1, 11)
    assert(not pcall(function()
        b[1] = 11
    end))
    assert(not pcall(function()
        ib[1] = 11
    end))
    assert(ib[1] == 11)

    local jb = m.freeze { 11, 2, 3 }
    assert(m.equals(jb, ib))
    assert(not m.equals(jb, m.freeze { 1, 2, 3 }))
    assert(not m.frozen.is(m.frozen.copy(jb)))
end

local function test_binsearch()
    local a = { 1, 2, 4, 4, 5 }
    assert(binsearch_num(a, 1) == 1)
    assert(binsearch_num(a, 2) == 2)
    assert(binsearch_num(a, 4) == 3) -- leftmost
    assert(binsearch_num(a, 5) == 5)
    assert(binsearch_num(a, 3) == -3)
    assert(binsearch_num(a, 100) == -6)
    assert(binsearch_num(a, 0) == -1)
    assert(binsearch_num({}, 1) == -1)
end

local function test_binsearch_rightmost()
    local function lt(a: num, b: num)
        return a < b
    end
    local a = { 1, 2, 4, 4, 5 }
    assert(binsearch_rightmost(a, 1, lt) == 1)
    assert(binsearch_rightmost(a, 2, lt) == 2)
    assert(binsearch_rightmost(a, 4, lt) == 4) -- rightmost
    assert(binsearch_rightmost(a, 5, lt) == 5)
    assert(binsearch_rightmost(a, 3, lt) == -3)
    assert(binsearch_rightmost(a, 1e2, lt) == -6)
    assert(binsearch_rightmost(a, 0, lt) == -1)
    assert(binsearch_rightmost({}, 1, lt) == -1)
end

local function test_insertion_sort()
    local function lt(a: num, b: num)
        return a < b
    end
    local a = { 5, 2, 3, 4, 1 }
    m.insertion_sort(a, lt)
    for i = 1, #a do
        assert(i == a[i])
    end
end

do -- is_sorted
    local function lt(a: num, b: num)
        return a < b
    end
    local a = { 0, 1, 3, 2, 4 }
    assert(not is_sorted(a, lt))
end

local function test_insertion_sort_by_key()
    local a = { { 5 }, { 2 }, { 3 }, { 4 }, { 1 } }
    m.insertion_sort_by_key(a, 1)
    for i = 1, #a do
        assert(i == a[i][1])
    end
end

local function test_remove_indices()
    local a = { 1, 2, 3, 4, 5, 6, 7, 8, 9, 0 }
    m.remove_indices(a, {})
    assert(join(a) == "1 2 3 4 5 6 7 8 9 0")
    m.remove_indices(a, { 10 })
    -- _ppa(a)
    assert(join(a) == "1 2 3 4 5 6 7 8 9")
    m.remove_indices(a, { 1, 7, 9, 8 })
    assert(join(a) == "2 3 4 5 6")
    -- _ppa(a)
    assert(not pcall(m.remove_indices, a, { 0 }))
    -- _ppa(a)
    assert(join(a) == "2 3 4 5 6")
end

local function self_test()
    test_vec()
    test_frozen()
    test_sorted_push()
    test_binsearch()
    test_binsearch_rightmost()
    test_insertion_sort()
    test_insertion_sort_by_key()
    test_remove_indices()

    warn("[array -- ok]")
end
self_test()

return m

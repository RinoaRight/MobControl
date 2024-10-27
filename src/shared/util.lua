--!strict
type str = string
type bool = boolean
type num = number
type integer = num
type uint = integer
type int = integer
type u32 = uint
type u5 = uint
type i32 = int
type u53 = integer
type i53 = integer
type u8 = uint
type array<a> = { a }
type table = { [any]: any }
type tab = table
type map<k, v> = { [k]: v }
type fun = (...any) -> ...any
type funk<a> = () -> a
local _fmt = string.format

local MAX_INT = 2 ^ 53
local MIN_INT = -MAX_INT

local m = {}
m.__index = m

local function is_int53(x)
    return x == math.floor(x) and MIN_INT <= x and x <= MAX_INT
end
m.is_int53 = is_int53

---@note: beware cycles!
local function deep_eq(t1: any, t2: any, ignore_mt: bool?)
    local ty1 = typeof(t1)
    local ty2 = typeof(t2)
    if ty1 ~= ty2 then
        return false
    end
    -- non-table types can be directly compared
    if ty1 ~= "table" and ty2 ~= "table" then
        return t1 == t2
    end
    -- as well as tables which have the metamethod __eq
    local mt = getmetatable(t1)
    if not ignore_mt and mt and mt.__eq then
        return t1 :: any == t2
    end
    for k1, v1 in pairs(t1) do
        local v2 = t2[k1]
        if v2 == nil or not deep_eq(v1, v2) then
            return false
        end
    end
    for k2, v2 in pairs(t2) do
        local v1 = t1[k2]
        if v1 == nil or not deep_eq(v1, v2) then
            return false
        end
    end
    return true
end
m.deep_eq = deep_eq

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

m.deep_clone = deep_clone

local function deep_freeze<T>(obj: T): T
    if type(obj) == "table" and not table.isfrozen(obj) then
        for k, v in pairs(obj) do
            obj[k] = deep_freeze(v)
        end
        obj = table.freeze(obj) :: typeof(obj)
    end
    return obj
end

m.deep_freeze = deep_freeze

function m.default<a>(val: a): map<any, a>
    return (setmetatable({}, {
        __index = function(_)
            return val
        end,
    }) :: any) :: map<any, a>
end


function m.retryAsync<a>(fn: funk<a>, max_attempts: num?, pause: num?, exp: num?): (bool, a)
    -- Using separate variables to satisfy the type checker
    local p: number = pause or 0.1
    local e: number = exp or 1.1
    local max = max_attempts or 5

    local n = 0
    local ok: boolean, result: a

    while n < max do
        n += 1
        ok, result = pcall(fn)
        if ok then
            break
        end
        if n < max then
            task.wait(p + (e ^ n))
        end
    end

    if ok then
        return ok, result
    else
        return false, result :: any
    end
end

-----------------------------
-- Quick test
-----------------------------
do
    local o = { { { inner = {} } } }
    local o1 = deep_freeze(o)
    assert(o == o1)
    assert(table.isfrozen(o1[1][1].inner))
end

local NUMBER_EPSILON: num = 2 ^ -52
m.EPSILON = NUMBER_EPSILON
do
    local guess = 1
    local eps: num
    while 1 + guess ~= 1 do
        eps = guess
        guess /= 2
    end
    if NUMBER_EPSILON ~= eps then
        warn("machine epsilon = ", eps)
        NUMBER_EPSILON = eps
    end
end
assert(NUMBER_EPSILON == 2 ^ -52)

function m.num_eq(a: num, b: num): bool
    return a == b or math.abs(a - b) <= NUMBER_EPSILON
end

do
    local _throttle_tte = {}

    function m.ConnectThrottled<a...>(event: RBXScriptSignal, period: num, listener: (a...) -> ()): () -> ()
        local h = (listener :: any) :: (...any) -> ()
        local connection = event:Connect(function(...: any)
            if _throttle_tte[event] and _throttle_tte[event] > os.clock() then
                return
            end
            _throttle_tte[event] = os.clock() + period
            h(...)
        end)
        return function()
            _throttle_tte[event] = nil
            connection:Disconnect()
        end
    end
end

warn("[util -- ok]")

return m

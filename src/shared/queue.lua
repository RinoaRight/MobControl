--!strict
type int = number
type bool = boolean
local m = {}
m.__index = m

export type Queue<A> = {
    _write: int,
    _read: int,
    IsEmpty: (self: Queue<A>) -> bool,
    Peek: (self: Queue<A>) -> A?,
    Pop: (self: Queue<A>) -> A, -- throws
    Push: (self: Queue<A>, v: A) -> Queue<A>,
    -- extra:
    Clear: (self: Queue<A>) -> (),
    Contains: (self: Queue<A>, v: A) -> A,
    Reduce: <B>(Queue<A>, seed: B, reducer: (B, A) -> B) -> B,
}

function m.new<A>()
    local self = {
        _write = 0 :: int,
        _read = 0 :: int,
    }
    return (setmetatable(self, m) :: any) :: Queue<A> & { any }
end

function m:IsEmpty()
    return self._read == self._write
end

local function len(self: Queue<any>)
    return self._write - self._read
end

m.__len = len

function m.Peek<A>(self: Queue<A>): A?
    return self[self._read]
end

function m.Push<A>(self: Queue<A>, v: A)
    self[self._write] = v
    self._write += 1
    return self
end

function m.Pop<A>(self: Queue<A>): A
    local r = self._read
    if r == self._write then
        error("attempt tp pop from empty queue", 2)
    end
    local v = self[r]
    self[r] = nil
    self._read += 1
    return v
end

-----------------------------
-- Extra methods
-----------------------------
function m.Clear<A>(self: Queue<A>)
    while len(self) > 0 do
        self:Pop()
    end
end

function m.Contains<A>(self: Queue<A>, value: A): boolean
    for i = self._write - 1, self._read, -1 do
        if self[i] == value then
            return true
        end
    end
    return false
end

function m.Reduce<a, b>(self: Queue<a>, seed: b, reducer: (b, a) -> b)
    for i = self._write - 1,  self._read, -1 do
        seed = reducer(seed, self[i])
    end
    return seed
end

-----------------------------
-- Quack test
-----------------------------
do -- basic
    local q = m.new()
    q:Push("aaa"):Push("bbb")
    assert((q :: any).__len(q) == 2)
    assert(#q == 2)
    assert(q:Pop() == "aaa")
    assert(#q == 1)
    q:Push("ccc")
    assert(#q == 2)
    assert(q:Pop() == "bbb")
    assert(q:Pop() == "ccc")
    assert(q:IsEmpty())
    assert(not pcall(q.Pop, q)) -- throws
    assert(#q == 0)
end

do -- extra
    local q = m.new()
    assert(#q == 0)
    assert(q:IsEmpty())
    q:Push(1)
    assert(#q == 1)
    assert(q:Peek() == 1)
    assert(q:Pop() == 1)
    assert(not q:Peek())

    for i = 1, 100 do
        q:Push(i)
        assert(#q == i)
    end
    -- warn("q", q._read, q._write, len(q))

    assert(q:Contains(1))
    assert(q:Contains(100))
    assert(not q:Contains(0))
    assert(not q:Contains(101))

    for i = 1, 100 do
        local v = q:Pop()
        assert(v == i, "" .. i .. " " .. tostring(v))
    end
    assert(#q == 0)
    for i = 0, q._read do
        assert((q :: any)[i] == nil)
    end

    for i = 1, 100 do
        q:Push(i)
        assert(#q == i)
    end
    assert(#q == 100)
    q:Clear()
    assert(#q == 0)
    for i = 0, q._read do
        assert((q :: any)[i] == nil)
    end
end

do -- Reduce
    local q:Queue<int> = m.new()
    q:Push(1):Push(2):Push(3)
    -- warn("q", q._read, q._write, len(q))

    local six = q:Reduce(0, function(s:int, a:int)
        -- print(s, a)
        return s + a
    end)
    assert(six == 6)
end

warn("[Queue -- ok]")

return m

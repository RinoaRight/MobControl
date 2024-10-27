--!strict
-- MIT License
-- Copyright (c) 2022 Andrew Zhilin (https://github.com/zoon)
_G.__DEV__  = true
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
type u16 = uint
type i32 = int
type u8 = uint
type id = int
type array<a> = { a }
type table = { [any]: any }
type map<k, v> = { [k]: v }
type fun = (...any) -> ...any
local _fmt = string.format

-----------------------------
-- Module
-----------------------------
type cell = u32

local CELL_BYTES = 4
local m = {}
m.__index = m
-- x:column, y:row, z:layer: top-top-left order
function m.new(x_dim: int, y_dim: int, z_dim: int)
    assert(x_dim >= 1 and y_dim >= 1 and z_dim >= 1)
    local count = x_dim * y_dim * z_dim
    return table.freeze(setmetatable({
        _data = buffer.create(CELL_BYTES * count),
        _x_dim = x_dim,
        _y_dim = y_dim,
        _z_dim = z_dim,
        _xy_dim = x_dim * y_dim,
        _len = count,
    }, m))
end

export type Grid = typeof(m.new(1, 1, 1))

local function idx2coords(self: Grid, idx: int): (int, int, int)
    local x = idx % self._x_dim
    local y = math.floor(idx / self._x_dim) % self._y_dim
    local z = math.floor(idx / self._xy_dim)
    return x, y, z
end

local function coords2idx(self: Grid, x: int, y: int, z: int): int
    if _G.__DEV__ then
        if x >= self._x_dim then
            error("x out of bound: " .. self._x_dim)
        elseif y >= self._y_dim then
            error("y out of bound: " .. self._y_dim)
        elseif z >= self._z_dim then
            error("z out of bound (" .. self._z_dim .. ")")
        end
    end
    return x + y * self._x_dim + z * self._xy_dim
end

function m.get_cell(self: Grid, x: int, y: int, z: int): cell
    return buffer.readu32(self._data, 4 * coords2idx(self, x, y, z))
end

function m.set_cell(self: Grid, x: int, y: int, z: int, c: cell): cell
    if _G.__DEV__ or true then
        if x >= self._x_dim then
            error("x out of bound: " .. self._x_dim)
        elseif y >= self._y_dim then
            error("y out of bound: " .. self._y_dim)
        elseif z >= self._z_dim then
            error("z out of bound (" .. self._z_dim .. ")")
        end
    end
    local idx = coords2idx(self, x, y, z)
    assert(idx < self._len)
    local data = self._data
    idx *= CELL_BYTES
    local old = buffer.readu32(data, idx)
    buffer.writeu32(data, idx, c)
    return old
end

-- TODO: NeighborsXY8

-----------------------------
-- Quick test
-----------------------------
local g = m.new(64, 64, 4)
do
    warn(buffer.len(g._data) / 4)
    for i = 0, g._len - 1 do
        local x, y, z = idx2coords(g, i)
        local o = g:set_cell(x, y, z, i)
        local ii = coords2idx(g, x, y, z)
        if ii ~= i then
            warn("error", x, y, z, "idx", i, ii)
        end
        assert(o == 0)
        print(x, y, z, "idx", i)
    end
end

for k = 0, g._z_dim - 1 do
    for j = 0, g._y_dim - 1 do
        for i = 0, g._x_dim - 1 do
            local ii = coords2idx(g, i, j, k)
            warn("~", ii, i, j, k)
        end
    end
end
return m

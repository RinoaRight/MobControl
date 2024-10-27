--!strict
-- MIT License
-- Copyright (c) 2022 Andrew Zhilin (https://github.com/zoon)

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
type map<k, v> = { [k]: v }
type fun = (...any) -> ...any
type dim = id | int
local _fmt = string.format

--[[ stylua: ignore]] script = script or require'script'
local luapp = require(script.Parent.luapp)
local Id = require(script.Parent.Id)
local En = require(script.Parent.enum)

export type DataTable = {
    row: En.Enum?,
    col: En.Enum?,
    width: int,
    height: int,
    [dim]: { num | string | bool},
}

local function deep_freeze<T>(obj: T): T
    if type(obj) == "table" and not table.isfrozen(obj) then
        for k, v in pairs(obj) do
            obj[k] = deep_freeze(v)
        end
    end
    return obj
end

local BOOL_DECODER = {
    Yes = true,
    True = true,
    [""] = false,
    No = false,
    False = false,
} :: map<str, bool>
for k, v in BOOL_DECODER do
    BOOL_DECODER[string.lower(k)] = v
    BOOL_DECODER[string.upper(k)] = v
end

local function format_value(value: str, discard_falsy: bool): id | num | bool | str | nil
    local n = tonumber(value)
    if n then
        return n
    end
    local b = BOOL_DECODER[value]
    if b ~= nil then
        return if discard_falsy then (b or nil) else b
    end
    local id = Id.parse(value)
    if id ~= nil then
        return id
    end
    return value
end

-----------------------------
-- Module
-----------------------------
local m = {}
m.__index = m
function m.dump(data: any)
    return luapp.pp(data, nil, 80, 0.80)
end

local CACHE = {} :: map<str, DataTable>

function m.load(csv: str, opt: "keep-falsy"?): DataTable
    -- print("-- CSV BEGIN")
    -- print(csv .. "-- CSV END")
    if not CACHE[csv] then
        assert(type(csv) == "string" and csv:byte(#csv) == ("\n"):byte())
        local rows = {} :: { { str } }
        for line in csv:gmatch "(.-)\r?\n" do
            table.insert(rows, string.split(line, ","))
        end
        local dims = string.split(assert(rows[1][1], "no data"), "/")
        assert(#dims == 2, "first cell must be like X/Y")
        local row_dim: str, col_dim: str = table.unpack(string.split(assert(rows[1][1], "first cell must be like X/Y"), "/"))
        local data: DataTable = {
            col = Id.lookup_by_kind_name(col_dim),
            row = Id.lookup_by_kind_name(row_dim),
            height = #rows - 1,
            width = #rows[1] - 1,
        }
        assert(#rows > 0, "empty table")

        local header = rows[1]
        -- fill ids instead of column names
        local column_ids = table.create(#header, 0)
        for i, col_name in header do
            if i == 1 then
                continue -- skip first column
            end
            local col_id: id = nil
            if data.col then
                col_id = data.col:get(col_name) :: any
                assert(type(col_id) == "number", "can't resolve: " .. col_name)
            else -- col name can be ord
                col_id = tonumber(col_name) :: any
                assert(col_id, "column name must be `id`  or `ord`" .. header[i])
            end
            column_ids[i] = col_id
        end
        for i, row in rows do
            if i == 1 then
                continue -- skip first row
            end
            local row_id = if data.row then data.row:get(row[1]) else tonumber(row[1])
            assert(type(row_id) == "number", "row name must be `id`  or `ord`")
            data[row_id] = {}
            for i, cell in row do
                if i == 1 then
                    continue -- skip first column
                end
                local col_id = column_ids[i]
                local val = format_value(cell, opt ~= "keep-falsy")
                if val ~= nil then
                    data[row_id][col_id] = val
                end
            end
        end
        CACHE[csv] = deep_freeze(setmetatable(data, m)) :: any
    end
    return CACHE[csv]
end

function m.pp(self: DataTable)
    local c = table.clone(self)
    c.row = nil
    c.col = nil
    return luapp.pp(c, nil, 80, 0.80)
end

-----------------------------
-- Quick test
-----------------------------
--[[
local AbilityCSV = require("../server/data/Ability")
luapp.set_id_resolver(Id.pp)
local data = m.load(AbilityCSV.csv)
-- print("-- RESULT:")
-- print(m.pp(data))
assert(data[Id.Ability.GEM_1][Id.Effect.GEM_DROP] == 0.1)
--
local TestCSV = require("../server/data/Test")
local _test_data = m.load(TestCSV.csv)
-- print(m.pp(_test_data))
--]]

warn("[data_table -- ok]")

return m

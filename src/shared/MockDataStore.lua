--!strict
-- MIT License
-- Copyright (c) 2022 Andrew Zhilin (https://github.com/zoon)

---@ref: https://create.roblox.com/docs/scripting/data/data-stores

-----------------------------
-- Imports
-----------------------------

--[[ stylua: ignore]]script = script or require'script'
local lpack = require(script.Parent.lpack)
local str = require(script.Parent.str)
local base64 = lpack.base64
local fmt = string.format

-----------------------------
-- Flags & Constants
-----------------------------
local DO_NOT_YIELD_IN_STUDIO = true

local YIELD_MIN = 0.2
local YIELD_MAX = 0.5

-----------------------------
-- Types
-----------------------------
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

type Version = str
type key = str
type Timestamp = int -- 100 ns
type UserId = int

-- val, info -> new_val
type transform = (str?, DataStoreKeyInfo?) -> str?

export type DataStoreKeyInfo = {
    CreatedTime: Timestamp,
    UpdatedTime: Timestamp,
    Version: Version,
    GetMetadata: (self: DataStoreKeyInfo) -> table,
    GetUserIds: (self: DataStoreKeyInfo) -> { UserId },
    tombstone: (self: DataStoreKeyInfo) -> DataStoreKeyInfo,
    deleted: (self: DataStoreKeyInfo) -> bool,
}

type DataStoreKeyInfoInternal = DataStoreKeyInfo & {
    _ids: { int },
    _meta: table,
    _tombstone: bool,
}

export type DataStore = {
    GetAsync: (self: DataStore, key: str) -> (str?, DataStoreKeyInfo?),
    SetAsync: (self: DataStore, key: str, value: str, user_ids: { int }?) -> DataStoreKeyInfo,
    UpdateAsync: (self: DataStore, key: str, transform) -> str?,
    RemoveAsync: (self: DataStore, key: str) -> (str?, DataStoreKeyInfo?),
    RemoveVersionAsync: (self: DataStore, key: str, version: str) -> (),
    Destroy: (self: DataStore) -> (),
}

type DataStoreInternal = {
    _id: str,
    _ds_key_infos: { [str]: { DataStoreKeyInfo } },
    _data: { [Version?]: str? },
}

----------------------------
-- DataStoreKeyInfo
-----------------------------
local DataStoreKeyInfo = {}
DataStoreKeyInfo.__index = DataStoreKeyInfo

function DataStoreKeyInfo.new(cts: Timestamp, uts: Timestamp, ver: str, ids: { int }?, deleted: bool?): DataStoreKeyInfo
    local self = {}
    self.CreatedTime = cts
    self.UpdatedTime = uts
    self.Version = ver
    self._tombstone = not not deleted
    self._ids = table.freeze(ids and table.clone(ids) or {})
    self._meta = table.freeze {}
    return table.freeze(setmetatable(self, DataStoreKeyInfo)) :: any
end

function DataStoreKeyInfo.tombstone(self: DataStoreKeyInfo): DataStoreKeyInfo
    local deleted = table.clone(self) :: table
    deleted._tombstone = true
    return table.freeze(deleted)
end
function DataStoreKeyInfo.deleted(self: DataStoreKeyInfoInternal): bool
    return self._tombstone
end

function DataStoreKeyInfo.GetUserIds(self: DataStoreKeyInfoInternal)
    return self._ids
end

function DataStoreKeyInfo.GetMetadata(self: DataStoreKeyInfoInternal)
    return self._meta
end

local function iso8601(ts: Timestamp): str
    return fmt("%s.%07dZ", os.date("!%Y-%m-%dT%H:%M:%S", math.floor(ts / 1e7)) :: str, ts % 1e7)
end

local function dump_key_info(info: DataStoreKeyInfo)
    return fmt(
        "version: %q, createdTime: %*, updatedTime: %*,  deleted: %*",
        info.Version,
        iso8601(info.CreatedTime),
        iso8601(info.UpdatedTime),
        info:deleted()
    )
end

function DataStoreKeyInfo:__tostring()
    return dump_key_info(self)
end

-----------------------------
-- Module
-----------------------------
local m = {}
m.__index = m

m.iso8601 = iso8601
m.dump_key_info = dump_key_info

local function datastore_new(id: str, key_info: { DataStoreKeyInfo }?, data: table?): DataStore
    return table.freeze(setmetatable({
        _id = id,
        _ds_key_infos = key_info or {},
        _data = data or {},
    }, m)) :: any
end

-----------------------------
-- STATE
-----------------------------
local DATA_STORE_STATE: { [str]: DataStore } = {}

local function emulate_yield()
    if not game then
        return
    end
    if game:GetService("RunService"):IsStudio() and DO_NOT_YIELD_IN_STUDIO then
        return
    end
    local t = math.random()
    task.wait(YIELD_MIN * (1 - t) + t * YIELD_MAX)
end

local function mock_timestamp(): Timestamp
    local _, ms = math.modf(os.clock())
    return math.floor((os.time() + ms) * 1e7)
end

local function next_key_info(prev: DataStoreKeyInfo?, ids: { int }?): DataStoreKeyInfo
    local ts_update = mock_timestamp()
    local ts_create, temp_split: array<str>
    if prev then
        assert(prev.Version)
        ts_create = prev.CreatedTime
        temp_split = string.split(prev.Version, ".")
        temp_split[2] = fmt("%.10d", tonumber(temp_split[2]) :: int + 1)
        temp_split[3] = fmt("%.16X", ts_update)
    else
        ts_create = ts_update
        local ts = fmt("%.16X", ts_create)
        temp_split = { ts, fmt("%.10d", 1), ts, "01" }
    end
    return DataStoreKeyInfo.new(ts_create, ts_update, table.concat(temp_split, "."), ids)
end

function m:GetDataStore(id: str): DataStore
    if not DATA_STORE_STATE[id] then
        DATA_STORE_STATE[id] = datastore_new(id)
    end
    return DATA_STORE_STATE[id]
end

function m.GetAsync(self: DataStoreInternal, key: str): (str?, DataStoreKeyInfo?)
    assert(key, "no key")
    emulate_yield()
    assert(DATA_STORE_STATE and DATA_STORE_STATE[self._id], "datastore deleted")
    local infos = self._ds_key_infos[key]
    local last_info = infos and infos[#infos] or nil
    if last_info and not last_info:deleted() then
        return self._data[last_info.Version], last_info
    end
    return nil, nil
end

function m.SetAsync(self: DataStoreInternal, key: str, value: str, ids: { int }?): DataStoreKeyInfo
    assert(key, "no key")
    assert(value, "no data")
    emulate_yield()
    assert(DATA_STORE_STATE and DATA_STORE_STATE[self._id], "datastore deleted")
    if not self._ds_key_infos[key] then
        self._ds_key_infos[key] = {}
    end
    local infos = self._ds_key_infos[key]
    local info = next_key_info(infos[#infos], ids)
    self._data[info.Version] = value
    table.insert(infos, info)
    return info
end

---@note: very basic implementation
function m.UpdateAsync(self: DataStoreInternal, key: str, transform: transform): str?
    local val, info = m.GetAsync(self, key)
    local new_val = transform(val, info)
    if new_val ~= nil then
        local _info = m.SetAsync(self, key, new_val)
    end
    return val
end

function m.RemoveAsync(self: DataStoreInternal, key: str): (str?, DataStoreKeyInfo?)
    assert(key, "no key")
    assert(DATA_STORE_STATE and DATA_STORE_STATE[self._id], "datastore deleted")
    local infos = self._ds_key_infos[key]
    local last_info = table.remove(infos) :: DataStoreKeyInfo
    if last_info then
        local tombstone = last_info:tombstone()
        table.insert(infos, tombstone)
        local value = self._data[last_info.Version]
        return value, tombstone
    end
    return nil, nil
end

function m.RemoveVersionAsync(self: DataStoreInternal, key: str, version: str)
    assert(key, "no key")
    assert(version, "no version")
    assert(DATA_STORE_STATE and DATA_STORE_STATE[self._id], "datastore deleted")
    local infos = self._ds_key_infos[key]
    for i, info in ipairs(infos) do
        if info.Version == version then
            table.remove(infos, i)
            local internal_ds = (self :: any) :: DataStoreInternal
            internal_ds._data[version] = nil
            break
        end
    end
end

local EMPTY_STATE_STR = base64.encode(lpack.pack {}) -- "kA=="

function m.DumpStore(_: DataStore?): str
    local out = base64.encode(lpack.pack(DATA_STORE_STATE))
    if out == EMPTY_STATE_STR then
        return ""
    end
    return str.wrap(out, 78)
end

---@semantic: reset state to empty, dump state
function m.ResetState(_: DataStore?): str
    local out = m.DumpStore()
    DATA_STORE_STATE = {}
    return out
end

-- alias for maid
m.Destroy = m.ResetState

function m.InitState(seed: str)
    assert(seed and type(seed) == "string", "there must be encoded MockDataStore state (MessagePack + Base64)")
    local decoded = base64.decode(seed, "remove-whitespace")
    if decoded ~= "" then
        local state = lpack.unpack(decoded)
        assert(type(state) == "table", "DATA_STORE_SEED corrupt")
        -- intrusively add metatables to props subtables
        for id, ds in pairs(state) do
            for key, infos in pairs(ds._ds_key_infos) do
                for i, info in ipairs(infos) do
                    infos[i] = DataStoreKeyInfo.new(info.CreatedTime, info.UpdatedTime, info.Version, assert(info._ids), info._tombstone)
                    assert(type(info._tombstone) == "boolean")
                    assert(info._meta)
                end
            end
            state[id] = datastore_new(id, assert(ds._ds_key_infos), assert(ds._data))
        end
        DATA_STORE_STATE = state :: any
    else
        warn("empty seed", seed)
    end
end

-----------------------------
-- Quick test
-----------------------------
--[[
do -- next_key_info
    local info: DataStoreKeyInfo
    local ts = os.clock()
    for i = 1, 3 do
        info = next_key_info(info)
        print(info)
        while os.clock() - ts < 0.001 do
            -- noop
        end
        ts = os.clock()
    end
end
--]]

--[[
do
    local ds = m:GetDataStore("test")
    local KEY = "key01"
    local VALUE_I = "12345"
    assert(not ds:GetAsync(KEY))
    local x = ds:SetAsync(KEY, VALUE_I)
    assert(x and not x:deleted())
    -- print(x)
    local y = ds:SetAsync(KEY, VALUE_I)
    assert(y and not y:deleted())
    -- print(y)
    -- re-init
    local VALUE_II = "67890"
    ds:SetAsync(KEY, VALUE_II)
    local serialized = m.ResetState()
    -- print(serialized)
    local _data = tpack.unpack(base64.decode(serialized, "remove ws"))
    m.InitState([====[
        gaR0ZXN0g61fZHNfa2V5X2luZm9zgaVrZXkwMZOGq0NyZWF0ZWRUaW1ly0NOiZc/wtrKq1VwZGF0ZW
        RUaW1ly0NOiZc/wtrKp1ZlcnNpb27ZLzAwM0QxMzJFN0Y4NUI1OTQuMDAwMDAwMDAwMS4wMDNEMTMy
        RTdGODVCNTk0LjAxpV9tZXRhkKpfdG9tYnN0b25lwqRfaWRzkIarQ3JlYXRlZFRpbWXLQ06Jlz/C2s
        qrVXBkYXRlZFRpbWXLQ06Jlz/C2yGnVmVyc2lvbtkvMDAzRDEzMkU3Rjg1QjU5NC4wMDAwMDAwMDAy
        LjAwM0QxMzJFN0Y4NUI2NDIuMDGlX21ldGGQql90b21ic3RvbmXCpF9pZHOQhqtDcmVhdGVkVGltZc
        tDTomXP8LayqtVcGRhdGVkVGltZctDTomXP8LbjadWZXJzaW9u2S8wMDNEMTMyRTdGODVCNTk0LjAw
        MDAwMDAwMDMuMDAzRDEzMkU3Rjg1QjcxQS4wMaVfbWV0YZCqX3RvbWJzdG9uZcKkX2lkc5ClX2RhdG
        GD2S8wMDNEMTMyRTdGODVCNTk0LjAwMDAwMDAwMDEuMDAzRDEzMkU3Rjg1QjU5NC4wMaUxMjM0Ndkv
        MDAzRDEzMkU3Rjg1QjU5NC4wMDAwMDAwMDAyLjAwM0QxMzJFN0Y4NUI2NDIuMDGlMTIzNDXZLzAwM0
        QxMzJFN0Y4NUI1OTQuMDAwMDAwMDAwMy4wMDNEMTMyRTdGODVCNzFBLjAxpTY3ODkwo19pZKR0ZXN0
    ]====])
    -- (!) get datastore again
    ds = m:GetDataStore("test")
    local val0, info1 = ds:GetAsync(KEY)
    assert(val0 == VALUE_II)
    assert(getmetatable(info1::any) == DataStoreKeyInfo)
    assert(not (info1::any):deleted())
    local val, info = ds:RemoveAsync(KEY)
    assert(val == VALUE_II)
    assert((info::any):deleted())
end
--]]

warn("[mock data store] -- ok")

return m

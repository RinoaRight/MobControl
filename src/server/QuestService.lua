--!strict
-- MIT License
-- Copyright (c) 2022 Andrew Zhilin (https://github.com/zoon)

--[=[
    Header
    Usage:
    ```lua
    local x = ...
    ```
    NOTE: single, double, triple, quadruple, quintuple, sextuple, septuple, octuple, nonuple, decuple
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
type map<k, v> = { [k]: v }
type fun = (...any) -> ...any
local _fmt = string.format

--[[ stylua: ignore]] if not game then (function() game = require("game") end)() end
local idk = require(game.ReplicatedStorage.shared.id1919)
local enum = require(game.ReplicatedStorage.shared.enum)
local iota = idk.iota
local roflake = require(game.ReplicatedStorage.shared.roflake)
local st = require(game.ReplicatedStorage.shared.state)
local struct = require(game.ReplicatedStorage.shared.struct)

export type Kind = { [str]: num | str }
type En = enum.Enum
-----------------------------
-- Module
-----------------------------
local Id = {}
Id.__index = Id

local ENUMS = {} :: map<any, En>
-------------------
-- Kind
-------------------
-- stylua: ignore
Id.Kind = table.freeze {
    MishId     = enum.iota(idk.MIN_KIND, 1, idk.MAX_KIND),
    MishGiver  = enum.iota'',
    MishState  = enum.iota'',
    ObjId      = enum.iota'',
    Objective  = enum.iota'',
    ObjSetId   = enum.iota'',
    ObjState   = enum.iota'',
    -- states:
    QState = "QState",
    WState = "WState",
    PState = "PState"
}

local _id_full_name_cache = {} :: { [id]: str }

function Id:lookup_by_kind_name(name: str): En
    if self ~= Id then
        name = self :: any
    end
    local kind_id = (Id.Kind :: any)[name] :: id
    return kind_id and ENUMS[kind_id] or error("can't find: " .. name)
end

function Id:name(id: any): str
    if self ~= Id then
        id = self
    end
    if not idk.is(id) then
        return tostring(id)
    end
    if not _id_full_name_cache[id] then
        local k, _ = idk.decode(id)
        local en = ENUMS[k]
        if not en or not en:peek(id) then
            return "?" .. tostring(id)
        end
        _id_full_name_cache[id] = en:full_name(id)
    end
    return _id_full_name_cache[id]
end

function Id:pp(o: any): str
    if self ~= Id then
        o = self
    end
    if idk.is(o) then
        return Id:name(o)
    elseif roflake.plausible(o) then
        return roflake.pp(o)
    elseif struct.is(o) then
        local out = {}
        local mt = assert(getmetatable(o))
        local tag_id = o[#o + 1]
        for i = 1, #o do
            table.insert(out, _fmt("%*=%*", Id.pp(mt[i]), Id.pp(o[i])))
        end
        return _fmt("%*:[%*]", Id.pp(tag_id), table.concat(out, ", "))
    elseif type(o) == "number" then
        return _fmt("%.7g", o)
    end
    return tostring(o)
end


-- stylua: ignore
-----------------------------
-- ObjectiveState
-----------------------------
Id.ObjState = enum.with_id "Id.ObjState" {
    NONE = iota(Id.Kind.ObjState, 0),
    INCOMPLETE = iota'',
    COMPLETE   = iota'',
}
ENUMS[Id.Kind.ObjState] = Id.ObjState
export type ObjectiveState = typeof(Id.ObjState)

-- stylua: ignore
-----------------------------
-- QuestState
-----------------------------
local Q = enum.with_id "QuestState" {
    Id            = enum.iota(0), -- Id.Mission, Id.Objective, ObjectiveSet
    MishState     = enum.iota'', -- id: Complete, Started, Active, ReadyToTurnIn, Failed
    Object        = enum.iota'', -- id
    Action        = enum.iota'', -- id -- what
    Count         = enum.iota'', -- num
    TargetCount   = enum.iota'', -- num
    MishGiver     = enum.iota'', -- id
    InitObjSet    = enum.iota'', -- uid
    NextMish1     = enum.iota'', -- uid
    NextMish2     = enum.iota'', -- uid
    NextMish3     = enum.iota'', -- uid
    Obj1          = enum.iota'', -- uid
    Obj2          = enum.iota'', -- uid
    Obj3          = enum.iota'', -- uid
    Obj4          = enum.iota'', -- uid
    Obj5          = enum.iota'', -- uid
    NextObjSet    = enum.iota'', -- uid
    ObjState      = enum.iota'', -- id: Incomplete, Complete
}

ENUMS.QState = Q
Id.QState = Q
export type Q = typeof(Q)

print(Id:lookup_by_kind_name("QState"))

-- stylua: ignore
-----------------------------
-- MishId
-----------------------------
Id.MishId = enum.with_id "Id.MishId" {
    NONE = iota(Id.Kind.MishId, 0),
}
ENUMS[Id.Kind.MishId] = Id.MishId
export type MishId = typeof(Id.MishId)

-- stylua: ignore
-----------------------------
-- ObjId
-----------------------------
Id.ObjId = enum.with_id "Id.ObjId" {
    NONE = iota(Id.Kind.ObjId, 0),
}
ENUMS[Id.Kind.ObjId] = Id.ObjId
export type ObjId = typeof(Id.ObjId)


-- stylua: ignore
-----------------------------
-- ObjSetId
-----------------------------
Id.ObjSetId = enum.with_id "Id.ObjSetId" {
    NONE = iota(Id.Kind.ObjSetId, 0),
}
ENUMS[Id.Kind.ObjSetId] = Id.ObjSetId
export type ObjSetId = typeof(Id.ObjSetId)

-- stylua: ignore
-----------------------------
-- MissionState (flags?)
-----------------------------
Id.MishState = enum.with_id "Id.MissionState" {
    __NONE           = iota(Id.Kind.MishState, 0),
    NOT_STARTED      = iota'',
    ACTIVE           = iota'',
    READY_TO_TURN_IN = iota'',
    COMPLETE         = iota'',
    FAILED           = iota'',
}

ENUMS[Id.Kind.MishState] = Id.MishState
export type MissionState = typeof(Id.MishState)
-- stylua: ignore
-----------------------------
-- Object
-----------------------------
Id.Objective = enum.with_id "Id.Object" {
    NONE = iota(Id.Kind.Objective, 0),
}
ENUMS[Id.Kind.Objective] = Id.Objective
export type Object = typeof(Id.Objective)

local SMissionsConfig, repl = st.ConfigBuilder
    .create()
    :set_component_names(Q)
    :set_pretty_printer(Id.pp)
    :set_replication_flag(Q.Id)
    :set_replication_flag(Q.Object, Q.Action, Q.Count, Q.TargetCount, Q.ObjState)
    :set_replication_flag(Q.MishGiver, Q.MishState, Q.InitObjSet, Q.NextMish1, Q.NextMish2, Q.NextMish3)
    :set_replication_flag(Q.Obj1, Q.Obj2, Q.Obj3, Q.Obj4, Q.Obj5, Q.NextObjSet)
    :set_persistent_flag(Q.Id)
    :set_persistent_flag(Q.Object, Q.Action, Q.Count, Q.TargetCount, Q.ObjState)
    :set_persistent_flag(Q.MishGiver, Q.MishState, Q.InitObjSet, Q.NextMish1, Q.NextMish2, Q.NextMish3)
    :set_persistent_flag(Q.Obj1, Q.Obj2, Q.Obj3, Q.Obj4, Q.Obj5, Q.NextObjSet)
    :build_with_replica()

-- stylua: ignore
local ClientConf = repl
    :set_destructor(Q.Obj1, function(x) end)
    :build()

local st_mish = st.main(SMissionsConfig)
local _objective = st_mish:constructor(Q.Id, Q.Object, Q.Action, Q.Count, Q.TargetCount, Q.ObjState)
print(st_mish:format_state("h"))

print(st.Util.format_config(ClientConf))

-----------------------------
-- Quick test
-----------------------------
do -- pp
    local cr, _cast = struct.define(Id.MishState.FAILED) {
        A = 1,
        B = 2,
        C = 3,
    }
    local x = cr { A = 11, B = 22, C = 33 }
    assert(Id.pp(x) == "Id.MissionState.FAILED:[A=11, B=22, C=33]")
    print(Id.name(Id.MishState.FAILED))
end
warn("[QuestService -- ok]")
return Id

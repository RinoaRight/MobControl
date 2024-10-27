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
type map<k, v> = { [k]: v }
type fun = (...any) -> ...any
local _fmt = string.format

--[[ stylua: ignore]] script = script or require'script'
-- local En = require(game.ReplicatedStorage.shared.Enum)
---[[ stylua: ignore]] if not game then (function() game = require("game") end)() end
local struct = require(script.Parent.struct)
local iota = struct.iota
local Id = require(script.Parent.Id)

-----------------------------
-- Module
-----------------------------
local m = {}
m.__index = m

-- stylua: ignore
-----------------------------
-- MissionNode
-----------------------------
m.createMissionNode, m.castToMissionNode = struct.define(Id.Struct.MissionNode) {
    GIVER             = iota(1),  -- TODO:
    PARENT            = iota'', -- Id.MissionId
    NEXT              = iota'',  -- Id.MissionId
    STATE             = iota'',  -- Id.MissionState
    OBJECTIVE_SET     = iota'',  -- Id.ObjectiveSet
    UNLOCK_1          = iota'',  -- Id.ObjectiveSet
    UNLOCK_2          = iota'',  -- Id.ObjectiveSet
    UNLOCK_3          = iota'',  -- Id.ObjectiveSet
    UNLOCK_4          = iota'',  -- Id.ObjectiveSet
    UNLOCK_5          = iota'',  -- Id.ObjectiveSet
}
export type MissionNode = typeof(m.castToMissionNode(''))

-- stylua: ignore
-----------------------------
-- ObjectiveSetNode
-----------------------------
m.createObjectiveSetNode, m.castToObjectiveSetNode = struct.define(Id.Struct.ObjectiveSetNode) {
    OBJECTIVE_1 = iota(1), -- Id.Objective
    OBJECTIVE_2 = iota'',  -- Id.Objective
    OBJECTIVE_3 = iota'',  -- Id.Objective
    OBJECTIVE_4 = iota'',  -- Id.Objective
    OBJECTIVE_5 = iota'',  -- Id.Objective
}
export type ObjectiveSetNode = typeof(m.castToObjectiveSetNode(''))


-- stylua: ignore
-----------------------------
-- Objective
-----------------------------
m.createObjective, m.castToObjective = struct.define(Id.Struct.Objective) {
    STATE    = iota(1),
    PROGRESS = iota''
}
export type Objective = typeof(m.castToObjective(''))

-----------------------------
-- Quick test
-----------------------------



warn("[module -- ok]")
return m
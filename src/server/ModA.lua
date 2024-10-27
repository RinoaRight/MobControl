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

--[[ stylua: ignore]] if not game then(function() game = require("game") end)() end

local En = require(game.ReplicatedStorage.shared.enum)
local _iota = En.iota
local _flag = En.flag

local data_table = require(game.ReplicatedStorage.shared.data_table)

local _ModB = require(game.ServerScriptService.server.ModB)
local _Ability = data_table.load(require(game.ServerScriptService.server.data.Ability).csv)

-----------------------------
-- Module
-----------------------------
local m = {}
m.__index = m

-----------------------------
-- Quick test
-----------------------------

return m

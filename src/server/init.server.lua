--!strict

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
--[[ stylua: ignore]] game = game or require'game'
local shared = game.ReplicatedStorage.shared
local luapp = require(shared.luapp)
local logger = require(shared.logger)
local Id = require(shared.Id)
local log = logger.create("server"):set_delimiter(" "):set_prettifier(Id.pp)
local data_table = require(shared.data_table)
-- server
local server = game.ServerScriptService.server
local _AbilityCVS = require(server.data.Ability)
local _STMCSV = require(server.data.STM)
-- stylua: ignore

--[[
luapp.set_id_resolver(Id.pp)
print(">>", luapp.pp(data_table.load(_AbilityCVS.csv)))
print(">>", luapp.pp(data_table.load(_STMCSV.csv)))
--]]
warn("[server -- started]")

--!strict
-- MIT License
-- Copyright (c) 2022 Andrew Zhilin (https://github.com/zoon)
type str = string
type bin = string
type base64 = str
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
type thunk = () -> ()
export type callback = (...any) -> ()
export type handler<state> = (state, ...any) -> ()
export type OnRemoteEvent<state> = { [id]: handler<state> }
type arg = string | number | boolean | table | Vector3
type snapshot = array<any>


--[[ stylua: ignore]] if not game then script = require("script") end
local disposer = require(script.Parent.disposer)
type Disposable = disposer.disposable

local lpack = require(script.Parent.lpack)
local Id = require(script.Parent.Id)

local HANDSHAKE_PREFIX = "🤝"
local BROADCAST_PREFIX = "📣"

local TIMEOUT = 20.0 -- sec

-- stylua: ignore
local function pack_args(...: arg): array<arg>
    local n = select("#", ...)
    local out = {...}
    if #out ~= n then
        local i = 1
        while select(i, ...) ~= nil do i += 1 end
        error("arg is `nil` at index: " .. i, 3)
    end
    return out
end

local function encode_packet(...: arg): bin
    return lpack.pack(pack_args(...))
end

local function decode_packet(data: bin): (array<arg>?, str)
    local ok, result = pcall(lpack.unpack, data)
    if not ok then
        return nil, "lpack: unpack error: " .. result
    end
    return (result :: any) :: array<arg>, "ok"
end


--- @fixme use lpack.tuple8
local function wait_on_event(event: RBXScriptSignal, timeout: num, on_fail: Disposable?): ...any
    local result: array<any>
    local sub = event:Once(function(...)
        result = pack_args(...)
    end)
    local t = os.clock()
    repeat
        task.wait(0.1)
    until result or os.clock() - t >= timeout
    if result then
        return table.unpack(result)
    end
    disposer.dispose(on_fail)
    disposer.dispose(sub)
    error("wait_on_event: timeout")
end

export type FireClient = (event: id, Instance?, ...arg) -> ()
export type FireServer = (event: id, ...arg) -> ()

-- stylua: ignore
export type Server<state> = {
    ---@yields
    Handshake: (Player, load: (Player, FireClient) -> (state, snapshot), on: OnRemoteEvent<state>) -> (FireClient, Disposable, state),
    Broadcast: (event: id, ...arg) -> (),
    US2CC: UnreliableRemoteEvent
}

export type Client<state> = {
    ---@yields
    Handshake: (load: (FireServer, snapshot) -> state, on: OnRemoteEvent<state>) -> (FireServer, Disposable, state, UnreliableRemoteEvent),
    ---@yields
    ConnectToBroadcast: (on: { [id]: callback }) -> Disposable,
}

-----------------------------
-- Module
-----------------------------
local m = {} :: {
    Server: Server<any>,
    Client: Client<any>,
    DecodePacket: (data: bin) -> (array<arg>?, str),
    EncodePacket: (...arg) -> bin,
}

if game and game.RunService:IsServer() then
    local US2CC = Instance.new("UnreliableRemoteEvent")
    US2CC.Parent = script
    US2CC.Name = "US2CC"

    local function create_remote_event(name: str)
        local evt = Instance.new("RemoteEvent")
        evt.Name = name
        evt.Parent = script
        return evt
    end

    local _broadcast_rtx = create_remote_event(BROADCAST_PREFIX)

    m.Server = {} :: Server<any>
    m.Server.US2CC = US2CC
    function m.Server.Broadcast(event: id, ...: arg)
        if _G.__DEV__ then
            local ok, err: any? = pcall(pack_args, ...)
            if not ok then
                print(err, "Server.Broadcast", Id.name(event), "args:", ...)
            end
        end
        local packet = encode_packet(...)
        _broadcast_rtx:FireAllClients(event, packet)
    end

    function m.Server.Handshake(player, load, on)
        assert(player, "no player")
        local player_id = player.UserId
        local hsh = create_remote_event(HANDSHAKE_PREFIX .. player_id)
        local rtx = create_remote_event("*")
        local nonce0 = math.random(0xff, 0xfff_ffff)
        local fire_client = function(event: id, inst: Instance?, ...)
            assert(inst == nil or typeof(inst) == "Instance", "first arg must be an Instance? type")
            local packet = encode_packet(...)
            rtx:FireClient(player, event :: any, inst, packet)
        end
        -- yields
        local ok, state, data = pcall(load, player, fire_client)
        if not ok then
            disposer.dispose(rtx)
            disposer.dispose(hsh)
            error("load state error: " .. state :: str)
        end
        local rtx_sub = rtx.OnServerEvent:Connect(function(p: Player, event: id, packet: base64)
            assert(p == player, "wrong player using rtx")
            local args, decode_err = decode_packet(packet)
            if not args then
                error(decode_err)
            else
                local handler = on[event] or error("no handler for event id:" .. event)
                handler(state, table.unpack(args))
            end
        end)
        local dispose = function()
            disposer.dispose(rtx_sub)
            disposer.dispose(rtx)
        end
        hsh:FireClient(player, rtx, US2CC, encode_packet(data, nonce0))
        -- yields
        local p, nonce = wait_on_event(hsh.OnServerEvent, TIMEOUT, function()
            dispose()
            disposer.dispose(hsh)
        end)
        disposer.dispose(hsh)
        assert(nonce == nonce0, "bad nonce")
        assert(p == player, "bad player")
        warn("INFO: handshake: server ready", player)
        return fire_client, dispose, state -- state for using elsewhere
    end
else -- CLIENT
    m.Client = {} :: Client<any>

    m.Client.Handshake = function(load, on)
        local hsh = script:WaitForChild(HANDSHAKE_PREFIX .. game.Players.LocalPlayer.UserId, TIMEOUT) :: RemoteEvent
        assert(hsh, "remote event (handshake) timed out")
        -- yields
        local rtx, us2cc, packet = wait_on_event(hsh.OnClientEvent, TIMEOUT)
        assert(rtx and typeof(rtx) == "Instance" and rtx:IsA("RemoteEvent"), "bad rtx")
        assert(us2cc and typeof(us2cc) == "Instance" and us2cc:IsA("UnreliableRemoteEvent"), "bad us2cc")
        local fire_server: FireServer = function(event: id, ...: arg)
            local packet = encode_packet(...)
            rtx:FireServer(event, packet)
        end
        local args, decode_err = decode_packet(packet)
        if not args then
            error(decode_err)
        end
        local state_snapshot: array<any>, nonce: int = table.unpack(args :: array<any>)
        -- yields
        local ok, state = pcall(load, fire_server, state_snapshot)
        if not ok then
            error("load error: " .. state :: str)
        end
        local rtx_sub = rtx.OnClientEvent:Connect(function(event: id, inst: Instance?, packet: base64)
            local args, decode_err = decode_packet(packet)
            if not args then
                error(decode_err)
            else
                local handler = on[event] or error("no handler for event id:" .. event)
                if inst == nil then
                    handler(state, table.unpack(args))
                else
                    handler(state, inst, table.unpack(args))
                end
            end
        end)
        hsh:FireServer(nonce) -- server, we are ready
        return fire_server, rtx_sub, state, us2cc
    end

    ---@note: can be used several times
    function m.Client.ConnectToBroadcast(on: { [id]: callback })
        local broadcast = script:WaitForChild(BROADCAST_PREFIX, TIMEOUT) :: RemoteEvent
        assert(broadcast, "remote event (broadcast) timed out")
        return broadcast.OnClientEvent:Connect(function(event: id, packet: base64)
            local callback = on[event]
            if not callback then
                if _G.__DEV__ then
                    warn("no handler for: " .. Id.name(event))
                end
                return
            end
            local args, decode_err = decode_packet(packet)
            if not args then
                error(decode_err)
            end
            assert(args)
            callback(table.unpack(args))
        end)
    end
end

m.EncodePacket = encode_packet
m.DecodePacket = decode_packet

warn("[remote -- ok]")
return table.freeze(m)

type buf = buffer
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
type f32 = num
type id = u8
type array<a> = { a }
type table = { [any]: any }
type map<k, v> = { [k]: v }
type fun = (...any) -> ...any
local _fmt = string.format
type offset = int

-------------------
-- NOTES:
-------------------
-- 1) this naive implementations 4x faster then `nodes as a buffer`
-- 2) TODO: better api + validate action etc.
-- 3) TODO: for bits use nifty recursions from EcsLite

-- Nano GOAP
-- very simple implementation of GOAP, where state is described in only 16-bit flags
-- state & care is a u16 packed to u32
export type State = u32
export type Context = State
export type AtomId = id
export type ActionId = id
export type ContextId = id
export type Cost = f32

type defs = buffer

local ru32 = buffer.readu32
local wu32 = buffer.writeu32
local _ri32 = buffer.readi32
local _wi32 = buffer.writei32
local rf32 = buffer.readf32
local wf32 = buffer.writef32

type bu32 = buffer
type bf32 = buffer


--[[ stylua: ignore]] script = script or require'script'
local perfn = require(script.Parent.perfn)
local bits = require(script.Parent.bits)
local En = require(script.Parent.enum)
local iota = En.iota

export type Planner = {
    id: str,
    defs: defs, -- mutable!
    atoms: En.Enum,
    actions: En.Enum,
    context: En.Enum,
    action_ids: bu32,
    costs: bf32,
    to_states: bu32,
}

-------------------
-- to inline
-------------------
-- value 16 LSB
local function wsv(s: State): u16
    return bit32.band(0x0000_ffff, s)
end
-- care 16 MSB
local function wsc(s: State): u16
    return bit32.rshift(s, 16)
end

local function split(s: State): (u16, u16)
    return wsv(s), wsc(s)
end

local function dontcare(s: State): u16
    return wsc(bit32.bxor(s, -1))
end

local function state(v: u16, c: u16)
    return bit32.replace(v, c, 16, 16)
end

local function set_bit(s: State, bit, val)
    s = bit32.replace(s, val, bit, 1)
    s = bit32.replace(s, 1, bit + 16, 1)
    return s
end

local function get_vc_bit(s: State, bit)
    return bit32.extract(s, bit, 1), bit32.extract(s, bit + 16, 1)
end

local _raw = bits.make_bit_printer(32, 16, "01|", "(c|v)")

local function _state_pp(s: State)
    local out = { "ws: " }
    for i = 0, 15 do
        local val, care = get_vc_bit(s, i)
        if care == 1 then
            table.insert(out, _fmt(if val == 1 then "%2d* " else _fmt("%2d- ", i), i))
        end
    end
    return table.concat(out)
end

local function do_action(eff: State, fr: State): State
    local affected = wsc(eff)
    local unaffected = dontcare(eff)
    local v = bit32.bor(bit32.band(wsv(fr), unaffected), bit32.band(wsv(eff), affected))
    return state(v, bit32.bor(affected, wsc(fr)))
end

local function _set_defs_bit(s: buffer, bit: int, value: int, offset: int)
    assert(bit and 0 <= bit and bit <= 15)
    local ws = buffer.readu32(s, offset)
    ws = set_bit(ws, bit, value)
    buffer.writeu32(s, offset, ws)
end

local function truthy2bit(b: any)
    return if not b or b == 0 then 0 else 1
end

local function bit2bool(c: int)
    assert(c == 0 or c == 1)
    return c ~= 0
end

-----------------------------
-- Helpers
-----------------------------
export type ActionDescriptions = map<ActionId, ActionSettings>
export type ActionSettings = {
    cost: num?,
    precedence: num?,
    precondition: { [AtomId]: bool },
    effect: { [AtomId]: bool },
    context: { [ContextId]: bool }?,
}

type DField = "cst" | "ctx" | "pre" | "eff"
local _def_struct: map<DField, int> = {
    cst = 0,
    ctx = 4,
    pre = 8,
    eff = 12,
}
local DEF_STRIDE = 16

local function set_definition(field: DField, defs: defs, action: id, value: num, n: int?)
    local offset = DEF_STRIDE * action + assert(_def_struct[field], field)
    if field == "cst" then
        wf32(defs, offset, value)
    elseif n then
        _set_defs_bit(defs, n, value, offset)
    else
        error("args:" .. `|{value}|{n}|`, 3)
    end
end

local function unpack_definition(defs: defs, o: offset) -- cst, ctx, pre, eff
    return rf32(defs, o), ru32(defs, o + 4), ru32(defs, o + 8), ru32(defs, o + 12)
end

local function unpack_cst(defs: defs, o: offset)
    return rf32(defs, o)
end

local function unpack_ctx(defs: defs, o: offset)
    return ru32(defs, o + 4)
end

local function unpack_pre(defs: defs, o: offset)
    return ru32(defs, o + 8)
end

local function unpack_eff(defs, o: offset)
    return ru32(defs, o + 12)
end

local function popcnt32(x: int)
    x = x - bit32.band(bit32.rshift(x, 1), 0x55555555)
    x = bit32.band(x, 0x33333333) + bit32.band(bit32.rshift(x, 2), 0x33333333)
    x = bit32.band(x + bit32.rshift(x, 4), 0x0F0F0F0F)
    return bit32.rshift(bit32.band(x * 0x01010101, 0xFFFFFFFF), 24)
end

-- Hamming weight of nodes diff
local function heuristic(fr: State, to: State)
    local care = wsc(to)
    local diff = bit32.bxor(bit32.band(wsv(fr), care), bit32.band(wsv(to), care))
    return popcnt32(diff)
end

-----------------------------
-- Module
-----------------------------
local m = {}

function m.dump_state(p: Planner, s: State)
    local out = {}
    for _, id in p.atoms:ids() do
        local v, c = get_vc_bit(s, id)
        if c == 1 then
            table.insert(out, v == 0 and p.atoms[id] or string.upper(p.atoms[id]))
        end
    end
    return table.concat(out, "|")
end

function m.dump(p: Planner)
    local out = { "@" .. tostring(p.id) }
    for _, aid in p.actions:ids() do
        local o = aid * DEF_STRIDE
        local cst, ctx, pre, eff = unpack_definition(p.defs, o)
        table.insert(out, _fmt("%.2d: %-16s (cost: %5.2f)", aid, p.actions[aid], cst))
        local ctx_c = wsc(ctx)
        if ctx_c ~= 0 then
            table.insert(out, "  * context:")
            for _, cid in p.context:ids() do
                local val, care = get_vc_bit(ctx, cid)
                if care == 1 then
                    table.insert(out, _fmt("    + %s is %*", p.context[cid], bit2bool(val)))
                end
            end
        end
        table.insert(out, "  * preconditions:")
        for _, pid in p.atoms:ids() do
            local val, care = get_vc_bit(pre, pid)
            if care == 1 then
                table.insert(out, _fmt("    + %s == %*", p.atoms[pid], bit2bool(val)))
            end
        end
        table.insert(out, "  * effects:")
        for _, eid in p.atoms:ids() do
            local val, care = get_vc_bit(eff, eid)
            if care == 1 then
                table.insert(out, _fmt("    + %s <- %*", p.atoms[eid], bit2bool(val)))
            end
        end
    end
    return table.concat(out, "\n")
end

function m.new(id: str, actions: En.Enum, atoms: En.Enum, context: En.Enum): Planner
    assert(actions:is_in(0), "wrong actions")
    assert(atoms:is_in(0, 15), "wrong atoms")
    assert(context:is_in(0, 15), "wrong context")
    local n = #actions
    local defs: defs = buffer.create(n * DEF_STRIDE)
    return table.freeze {
        id = id,
        defs = defs,
        actions = actions,
        atoms = atoms,
        context = context,
        action_ids = buffer.create(4 * n), -- i32
        costs = buffer.create(4 * n), -- f32
        to_states = buffer.create(4 * n), -- State
    }
end

local DEFAULT_COST = 1
function m.set_definitions(self: Planner): (ActionDescriptions) -> Planner
    local p = table.clone(self)
    p.defs = buffer.create(buffer.len(self.defs))
    table.freeze(p)
    return function(data)
        for action_id, settings in data do
            m.set_action(p, action_id, settings)
        end
        return p
    end
end

function m.set_action(p: Planner, action_id: id, settings: ActionSettings)
    local cost = (settings.cost or DEFAULT_COST) + 0.001 * (settings.precedence or 0)
    set_definition("cst", p.defs, action_id, cost)
    if settings.context then
        for ctx, bool in settings.context do
            set_definition("ctx", p.defs, action_id, truthy2bit(bool), ctx)
        end
    end
    if settings.precondition then
        for atom, bool in settings.precondition do
            set_definition("pre", p.defs, action_id, truthy2bit(bool), atom)
        end
    end
    if settings.effect then
        for atom, bool in settings.effect do
            set_definition("eff", p.defs, action_id, truthy2bit(bool), atom)
        end
    end
end

local function neighbors(p: Planner, fr: State, env: State): int
    local count = 0
    local ids = p.action_ids
    local to = p.to_states
    local env_v = wsv(env)
    for _, aid in p.actions:ids() do
        local offset = aid * DEF_STRIDE
        local ctx = unpack_ctx(p.defs, offset)
        local care = wsc(ctx)
        local not_ctx_met = bit32.band(wsv(ctx), care) ~= bit32.band(env_v, care)
        if not_ctx_met then
            -- warn("context pruning", p.actions[aid])
            continue
        end
        local pre = unpack_pre(p.defs, offset)
        care = wsc(pre)
        local pre_met = bit32.band(wsv(pre), care) == bit32.band(wsv(fr), care)
        if pre_met then
            local o = 4 * count
            wu32(ids, o, aid)
            wu32(to, o, do_action(unpack_eff(p.defs, offset), fr))
            count += 1
        end
    end
    return count
end

function m.set_world_state(p: Planner, s: State, atom: id, val: bool): State
    assert(p.atoms[atom])
    return set_bit(s, atom, truthy2bit(val))
end

function m.set_world_env(p: Planner, s: State, ctx: id, val: bool): State
    assert(p.context[ctx])
    return set_bit(s, ctx, truthy2bit(val))
end

-- planner
do
    type action_id = id
    local cl = table.clear
    local front = {} -- ws->f
    local parent = {}
    local by_action = {} :: map<State, action_id>
    local g_cost = {}

    local function result(start: State, last: State): ...action_id
        if last ~= start then
            return by_action[last], result(start, parent[last])
        end
    end
    local function reverse<a>(n: int?, ...): ...a
        n = n or select("#", ...)
        if n and n > 0 then
            return select(n, ...), reverse(n - 1, ...)
        end
    end
    function m.plan(p: Planner, env: State, start: State, goal: State): ...action_id?
        cl(front) -- open
        cl(parent)
        cl(g_cost) -- close
        cl(by_action)
        front[start] = 0
        g_cost[start] = 0
        local goal_val, goal_care = split(goal)
        -- warn("start:")
        -- warn(m.dump_state(p, start), "<- start state")
        while next(front) do
            local cur_f = math.huge
            local cur
            for ws, f in front do
                if f < cur_f then
                    cur_f = f
                    cur = ws
                end
            end
            local match = bit32.band(wsv(cur), goal_care) == goal_val
            if match then
                return reverse(nil, result(start, cur))
            end
            front[cur] = nil
            local n_count = neighbors(p, cur, env)
            local cur_g = g_cost[cur]
            for i = 0, n_count - 1 do
                local offset = i * 4
                local aid = ru32(p.action_ids, offset)
                local cost = unpack_cst(p.defs, aid * DEF_STRIDE)
                local g_next = cur_g + cost
                local ws_next = ru32(p.to_states, offset)
                -- warn(m.dump_state(p, next))
                if not g_cost[ws_next] or g_next < g_cost[ws_next] then
                    g_cost[ws_next] = g_next
                    front[ws_next] = g_next + heuristic(ws_next, goal)
                    parent[ws_next] = cur
                    by_action[ws_next] = aid
                end
            end
        end
        return nil
    end
end

-----------------------------
-- Quick test
-----------------------------
do
    -- stylua: ignore
    local actions = En.with_id "actions" {
        scout     = iota(0),
        aim       = iota'',
        shoot     = iota'',
        load      = iota'',
        detonate  = iota'',
        flee      = iota'',
        approach  = iota'',
        dark_jump = iota'',
    }
    -- stylua: ignore
    local atoms = En.with_id "atoms" {
        enemy_visible   = iota(0),
        armed_with_gun  = iota'',
        weapon_loaded   = iota'',
        enemy_lineup    = iota'',
        enemy_alive     = iota'',
        armed_with_bomb = iota'',
        near_enemy      = iota'',
        alive           = iota'',
    }

    -- stylua: ignore
    local context = En.with_id "context" {
        night = iota(0),
        fog   = iota""
    }

    local planner = m.new("Grunt", actions, atoms, context)
    planner = m.set_definitions(planner) {
        [actions.scout] = {
            precondition = { [atoms.armed_with_gun] = true },
            effect = { [atoms.enemy_visible] = true },
        },
        [actions.aim] = {
            precondition = { [atoms.enemy_visible] = true, [atoms.weapon_loaded] = true },
            effect = { [atoms.enemy_lineup] = true },
        },
        [actions.shoot] = {
            precondition = { [atoms.enemy_lineup] = true },
            effect = { [atoms.enemy_alive] = false },
        },
        [actions.load] = {
            precondition = { [atoms.armed_with_gun] = true },
            effect = { [atoms.weapon_loaded] = true },
        },
        [actions.detonate] = {
            cost = 5,
            precondition = { [atoms.armed_with_bomb] = true, [atoms.near_enemy] = true },
            effect = { [atoms.alive] = false, [atoms.enemy_alive] = false, [atoms.armed_with_bomb] = false },
        },
        [actions.flee] = {
            precondition = { [atoms.enemy_visible] = true },
            effect = { [atoms.near_enemy] = false },
        },
        [actions.approach] = {
            precedence = 50,
            precondition = { [atoms.enemy_visible] = true },
            effect = { [atoms.near_enemy] = true },
        },
        [actions.dark_jump] = {
            precedence = 10,
            precondition = { [atoms.enemy_visible] = true },
            effect = { [atoms.near_enemy] = true },
            context = { [context.night] = true },
        },
    }
    -- print(m.dump(planner))
    -- print("start ::")
    local st = m.set_world_state(planner, 0, atoms.enemy_visible, false)
    st = m.set_world_state(planner, st, atoms.enemy_visible, false)
    st = m.set_world_state(planner, st, atoms.armed_with_gun, true)
    st = m.set_world_state(planner, st, atoms.weapon_loaded, false)
    st = m.set_world_state(planner, st, atoms.enemy_lineup, false)
    st = m.set_world_state(planner, st, atoms.enemy_alive, true)
    st = m.set_world_state(planner, st, atoms.armed_with_bomb, true)
    st = m.set_world_state(planner, st, atoms.near_enemy, false)
    st = m.set_world_state(planner, st, atoms.alive, true)
    local goal = m.set_world_state(planner, 0, atoms.enemy_alive, false)
    -- print(m.dump_state(planner, st), "st")
    -- print(m.dump_state(planner, goal), "goal")
    -- print(m.plan(planner, 0, st, goal))
    -------------------
    -- PERF
    -------------------
    ---[[
    perfn()
    local a1, a2, a3, a4
    perfn("4 step", function()
        a1, a2, a3, a4 = m.plan(planner, 0, st, goal)
    end, 1000)

    assert(a1 and actions:key(a1) == "load")
    assert(a2 and actions:key(a2) == "scout")
    assert(a3 and actions:key(a3) == "aim")
    assert(a4 and actions:key(a4) == "shoot")
    --]]
    warn("[goap -- ok]")
    return m
end

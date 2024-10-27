--!strict
--!nolint
---@diagnostic disable: deprecated
--[=[
    Performance measure util.
    Usage:
    ```lua
    perfn()
    perfn("Test section")
    perfn("math.sin", function()
        local _ = math.sin(math.pi)
    end)
    ```
-- +----------------------+----------+----------+----------+----------------------+
-- | # Test section                                                               |
-- +----------------------+----------+----------+----------+----------------------+
-- | math.sin             | μ   1000 |   24 ns  |   0.0 B  | Σ   34 μs ,   0.0 B  |
-- +----------------------+----------+----------+----------+----------------------+

    Public Domain.
    Copyright (C) 2021-2022 Andrew Zhilin (https://github.com/zoon)

--]=]

local LONG_FORM = false

-- NB: "Luau+" is custom build of Luau with more modes available to
-- `collectgarbage`.
local INEXACT_GC = _VERSION ~= "Luau+"

local HEADER = LONG_FORM and "-- | # %-81s |" or "-- | # %-58s |"
-- stylua: ignore
local FOOTER = LONG_FORM
   and "-- +----------------------------+-----------+----------+----------+----------------------+"
    or "-- +----------------------------+-----------+----------+----------+"

type num = number
type bool = boolean
type str = string

local clock = os.clock
local log = math.log
local gcinfo = gcinfo

local MAX_ITER = 1e6
local DEFAULT_ITER = 1000
assert(DEFAULT_ITER <= MAX_ITER)

local CORRECTION_PER_ITERATION = 10 * 1e-9 -- ~10 ns per iteration

local function trim(s: string)
    local _, i1 = s:find("^%s*")
    local i2 = s:find("%s*$") :: num
    return s:sub(i1 :: num + 1, i2 - 1)
end

-- stylua: ignore
local TIERS = { " B ", " KB", " MB", " GB", " TB", " QB", }
local FMT = "%5.1f%s"

local function fmt_bytes(bytes)
    if bytes < 1 then
        return FMT:format(0, TIERS[1])
    end
    local tier = math.floor(log(bytes, 10) / 3)
    bytes = bytes / 10 ^ (3 * tier)
    return FMT:format(bytes, TIERS[tier + 1])
end

local TIME_SUFFIXES = { " ps", " ns", " μs", " ms", " s " }
local function fmt_time(sec: num) -- 8 chars sharp
    local ps = sec * 1e12
    -- returns `0.0 ns` for sub-picoseconds
    if ps <= 1 then
        return FMT:format(0.0, TIME_SUFFIXES[2]), 0
    end
    local tier = math.floor(log(ps, 10) / 3)
    if tier + 1 < 4 then -- less then 'μs'
        ps = math.round(ps / 10 ^ (3 * tier))
        return (" %3d%s "):format(math.round(ps), TIME_SUFFIXES[tier + 1]), ps
    end
    ps = ps / 10 ^ (3 * tier)
    return FMT:format(ps, TIME_SUFFIXES[tier + 1]), ps
end
local function probe(from: number, to: number, pass_idx: boolean, thunk: (number) -> ())
    local m1
    if not INEXACT_GC then
        collectgarbage("collect" :: any)
        collectgarbage("stop" :: any)
        m1 = collectgarbage("countb" :: any)
    else
        m1 = 1024 * collectgarbage("count")
    end
    local t1, t2
    t1 = clock()
    for i = from, to do
        thunk(i)
    end
    t2 = clock()
    local m2
    if not INEXACT_GC then
        m2 = collectgarbage("countb" :: any)
    else
        m2 = 1024 * collectgarbage("count")
    end
    local gc_time = 0
    if not INEXACT_GC then
        local t3 = clock()
        collectgarbage("collect" :: any)
        local t4 = clock()
        gc_time = t4 - t3
        collectgarbage("restart" :: any)
    end
    return m2 - m1, t2 - t1, gc_time
end

local function perfn(tag: string?, thunk: (number) -> ()?, times: number?, tostr: boolean | str?): str?
    local report = nil
    if not thunk then
        report = if not tag then "" else HEADER:format(tag)
    else
        assert(tag)
        times = times and math.round(times) or 1000
        assert(times)
        times = math.max(1, math.min(times, MAX_ITER))
        local d_bytes, dt, dgc = probe(1, times, true, thunk)
        local avg_time = math.max(0, dt / times - CORRECTION_PER_ITERATION)
        local dbytes = d_bytes
        local avg_bytes = dbytes / times

        local gc_remark = ""
        if INEXACT_GC and d_bytes > 1 then
            gc_remark = " ~"
        elseif d_bytes > 1 and dgc ~= 0 then
            local tstr, ps = fmt_time(dgc / times)
            if ps > 0 then
                gc_remark = (" gc: %s"):format(trim(tstr))
            end
        end
        report = if LONG_FORM
            then ("-- | %-26s | μ %7g | %s | %s | Σ %s, %s |%s"):format(
                tag,
                times,
                fmt_time(avg_time),
                fmt_bytes(avg_bytes),
                fmt_time(dt),
                fmt_bytes(dbytes),
                gc_remark
            )
            else ("-- | %-26s | μ %7g | %s | %s |%s"):format(
                tag,
                times,
                fmt_time(avg_time),
                fmt_bytes(avg_bytes),
                gc_remark
            )
    end
    if tostr then
        return report
    elseif report and report ~= "" then
        print(report)
        print(FOOTER)
    elseif not thunk then
        print(FOOTER)
    end
    return nil
end
-----------------------------
-- self-test
-----------------------------
local c = 0
local _ = perfn("c", function(i)
    c = c + (i or 0)
end, 64, "tostr")
assert(c == 2080) -- Sum(1..=64)

--[[ print test
perfn()
perfn("Summation")
perfn("I", function(i)
    c = c + (i or 0)
end, 64)
perfn("II", function(i)
    c = c + (i or 0)
end, 12345678978)
local function fib(n)
    if n < 3 then
        return 1
    end
    return fib(n - 1) + fib(n - 2)
end
perfn("Fibonacci")
perfn("fib30", function(i)
    local _ = fib(30)
end, 10)
perfn("Allocations")
perfn("alloc array 100x10", function(i)
    for _ = 1, 100 do
        local _ = { 1, 2, 3, 4, 5, 6, 7, 8, 9, 0 }
    end
end)
--]]

warn("[perfn -- ok]")

return perfn

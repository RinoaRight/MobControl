--!strict
--!native
-- MIT License
-- Copyright (c) 2024 Andrew Zhilin (https://github.com/zoon)

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
type u8 = uint
type id = int
type buf = buffer
type array<a> = { a }
type map<k, v> = { [k]: v }
local fmt = string.format
local byte = string.byte

local _scratch_buffer = buffer.create(0x4000)

local function grow(b: buf, c: int): buf
    if c < buffer.len(b) then
        return b
    end
    local size = buffer.len(b)
    -- to next power of 2
    size = bit32.lshift(1, 32 - bit32.countlz(math.max(c, 2 * size) - 1))
    local fresh = buffer.create(size)
    buffer.copy(fresh, 0, b)
    -- warn("grow to:", size)
    return fresh
end

-------------------
-- Hexify string
-------------------
local BIN_TO_HEX = buffer.create(4 * 256) -- A -> \x41
local BACK_SLASH_ESCAPE = buffer.create(2 * 256) -- \r -> \\r
-- stylua: ignore
do -- fill lookups
    local scratch = buffer.create(4)
    local wi = 0
    for i = 0, 255 do
        local c = fmt("\\x%02x", i)
        buffer.writestring(scratch, 0, c, 4)
        buffer.writeu32(BIN_TO_HEX, wi, buffer.readu32(scratch, 0))
        wi += 4
    end
    buffer.writeu16(BACK_SLASH_ESCAPE, 2 * byte("\\"), 0x100 * byte("\\") + byte("\\"))
    buffer.writeu16(BACK_SLASH_ESCAPE, 2 * byte('"' ), 0x100 * byte('"' ) + byte("\\"))
    buffer.writeu16(BACK_SLASH_ESCAPE, 2 * byte("'" ), 0x100 * byte("'" ) + byte("\\"))
    buffer.writeu16(BACK_SLASH_ESCAPE, 2 * byte("\n"), 0x100 * byte("n" ) + byte("\\"))
    buffer.writeu16(BACK_SLASH_ESCAPE, 2 * byte("\r"), 0x100 * byte("r" ) + byte("\\"))
    buffer.writeu16(BACK_SLASH_ESCAPE, 2 * byte("\t"), 0x100 * byte("t" ) + byte("\\"))
end

-- TODO: wrapper
-- TODO: grow to 5x and use one scratch buffer for in and out
--@perf 15x faster then gsub
local function _hexify(s: str, scratch: buf, opt: "all"?): str
    local strlen = #s
    scratch = grow(scratch, 5 * strlen)
    buffer.writestring(scratch, 0, s, strlen)
    local wi = strlen
    if opt == "all" then
        for i = 0, strlen - 1 do
            local c = buffer.readu8(scratch, i)
            buffer.writeu32(scratch, wi, buffer.readu32(BIN_TO_HEX, 4 * c))
            wi += 4
        end
    else -- only unreadable and escape
        for i = 0, strlen - 1 do
            local c = buffer.readu8(scratch, i)
            local esc = buffer.readu16(BACK_SLASH_ESCAPE, 2 * c)
            if esc ~= 0 then
                buffer.writeu16(scratch, wi, esc)
                wi += 2
            elseif 31 < c and c < 127 then
                buffer.writeu8(scratch, wi, c)
                wi += 1
            else
                buffer.writeu32(scratch, wi, buffer.readu32(BIN_TO_HEX, 4 * c))
                wi += 4
            end
        end
    end
    return buffer.readstring(scratch, strlen, wi - strlen)
end

-----------------------------
-- Module
-----------------------------
local m = {}
m.__index = m

--- Converts a string to a hexadecimal representation (`\x00`).
---
--- @param s str The input string to convert.
--- @param opt "all"? An optional parameter to specify that all characters should be converted to hex, rather than just non-printable and escaped characters.
--- @return str The hexadecimal representation of the input string.
function m.hexify(s: str, opt: "all"?): str
    return _hexify(s, _scratch_buffer, opt)
end

--- Generates a random string of the specified length, with characters chosen from either the ASCII printable range (32-126) or the full 8-bit range (0-255).
---
--- @param len int The length of the string to generate.
--- @param opt "ascii"? An optional parameter to specify that the string should only contain ASCII printable characters.
--- @return str The generated random string.
function m.gen(len: int, opt: "ascii"?): str
    assert(len > 0)
    local b = grow(_scratch_buffer, len)
    local min, max
    if opt == "ascii" then
        min = 32
        max = 126
    else
        min = 0
        max = 255
    end
    for i = 0, len - 1 do
        buffer.writeu8(b, i, math.random(min, max))
    end
    return buffer.readstring(b, 0, len)
end

---@note: pretty slow function (0.3ms per 32KB) for testing purposes or using in Studio
local function wrap_ref(s: str, col: uint?): str
    col = col or 78
    if #s < col :: uint then
        return s
    end
    return (string.gsub(s, string.rep(".", col :: uint), "%1\n"))
end

--- Wraps a string to the specified number of columns.
---
--- - Note: 5x faster then gsub, ~50μs per 32KB
---
--- @param s str The input string to wrap.
--- @param columns uint? The number of columns to wrap the string to. If not provided, defaults to 78.
--- @return str The wrapped string.
function m.wrap(s: str, columns: uint?): str
    local col = columns or 78
    local len = #s
    local lines = len // col
    if lines < 1 then
        return s
    end
    local b = grow(_scratch_buffer, 2*len + lines)
    buffer.writestring(b, 0, s)
    local ro, wo = 0, len
    local lines_len = lines * col
    while ro < lines_len do
        buffer.copy(b, wo, b, ro, col)
        ro += col
        wo += col
        buffer.writeu8(b, wo, 0xA) -- \n
        wo += 1
    end
    if lines_len < len then
        local tail = len - lines_len
        buffer.copy(b, wo, b, ro, tail)
        wo += tail
    end
    return buffer.readstring(b, len, wo - len)
end


--[=[
    ---@snippet: there is no utf8.graphemes iterator in vanilla luau, use utf8.codes instead
    ```lua
    local s = "😍hello✔"
    -- rune === codepoint === int32
    for pos, rune in utf8.codes(s) do
        print(utf8.char(rune))
    end
    ```
    returns:
    -- 😍
    -- h
    -- e
    -- l
    -- l
    -- o
    -- ✔
]=]


-----------------------------
-- Quick test
-----------------------------
do -- hexify test
    local s = "hello world!"
    assert(#_hexify(s, _scratch_buffer, "all") == 48)
    assert(_hexify(s, _scratch_buffer, "all") == "\\x68\\x65\\x6c\\x6c\\x6f\\x20\\x77\\x6f\\x72\\x6c\\x64\\x21")
end

---[[ wrap test
local N = 10   -- 1000
local M = 1024 -- 0x8000
for i = 1, N do
    local data = m.gen(M, "ascii")
    local col = math.random(10, 100)
    assert(m.wrap(data, col) == wrap_ref(data, col))
end
--]]

print("[str -- ok]")
return m

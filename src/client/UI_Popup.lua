--!nocheck
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
type array<a> = { a }
type table = { [any]: any }
type map<k, v> = { [k]: v }
type fun = (...any) -> ...any
type callback = () -> ()
local _fmt = string.format
local noop: callback = function() end

local ReplicatedStorage = game.ReplicatedStorage
local shared = ReplicatedStorage.shared
local Id = require(shared.Id)
local En = require(shared.enum)
local iota = En.iota
local _flag = En.flag
local Disposer = require(shared.disposer)
local Queue = require(shared.queue)
local Signal = require(shared.signal)
local Misc = require(shared.Misc)

type Queue<A> = Queue.Queue<A>

export type Entry = {
    text: str?,
    yes: callback?,
    no: callback?,
    ok: callback?,
    on_close: callback?,
}

-----------------------------
-- Module
-----------------------------
local m = {} :: Popup
m.__index = m

-- stylua: ignore
-----------------------------
-- Elements
-----------------------------
local Elements = En.with_id "Popup.Elements" {
    X         = iota(1000, 1),
    YES       = iota'',
    NO        = iota'',
    OK        = iota'',
    TEXT      = iota'',
}

local function el(panel: ScreenGui, id): GuiObject
    local unique = assert(panel:GetAttribute(Elements:get(id) :: str), "no " .. Elements:get(id))
    return panel:FindFirstChild(unique, true) :: any
end

local function show_cursor(show: bool)
    noop() -- TODO: ?
end

local function show_panel(self: InternalPopup)
    assert(self._vacant)
    self._vacant = false
    show_cursor(true)
    self._panel.Enabled = true
end

local function hide_panel()
    local self: InternalPopup = m :: any
    Misc:PlaySound(Id.Sound.CLICK)
    self._maid:Destroy()
    self._panel.Enabled = false
    show_cursor(false)
    self._vacant = true
    if self._queue:Peek() then
        self:Show(self._queue:Pop())
    end
end

local function show_element(el: any, bool)
    el.Parent.Visible = bool
end

local function do_show_popup(self: InternalPopup, entry: Entry)
    self._text.Text = entry.text or "Lorem ipsum dolor sit amet, elit."
    assert(not (entry.yes and entry.ok), "'yes' and 'ok' are mutually exclusive")
    self._maid.on_close = entry.on_close
    self._maid.on_yes = self._yes.Activated:Connect(entry.yes or noop)
    self._maid.on_no = self._no.Activated:Connect(entry.no or noop)
    self._maid.on_ok = self._ok.Activated:Connect(entry.ok or noop)
    self._maid.on_x = self._x.Activated:Connect(entry.ok or entry.no or noop)
    local is_yes_no: bool = not not entry.yes
    show_element(self._yes, is_yes_no)
    show_element(self._no, is_yes_no)
    show_element(self._ok, not is_yes_no)
    show_panel(self)
end

export type Popup = {
    Init: (self: Popup, ScreenGui) -> (),
    Show: (self: Popup, Entry) -> (),
}

-- module

-- stylua: ignore
function m.Init(self: Popup, panel: ScreenGui)
    m._maid      = Disposer.new()
    m._queue     = Queue.new() :: Queue<Entry>
    m._x         = el(panel, Elements.X)    :: GuiButton
    m._yes       = el(panel, Elements.YES)  :: GuiButton
    m._no        = el(panel, Elements.NO)   :: GuiButton
    m._ok        = el(panel, Elements.OK)   :: GuiButton
    m._text      = el(panel, Elements.TEXT) :: TextLabel
    m._vacant    = true
    m._panel     = panel
    m._x.Activated:Connect(hide_panel)
    m._yes.Activated:Connect(hide_panel)
    m._no.Activated:Connect(hide_panel)
    m._ok.Activated:Connect(hide_panel)
    -- once
    m.Init = function(_, _) end
end

function m.Show(self: Popup, entry: Entry)
    assert(type(entry) == "table")
    if self._vacant then
        do_show_popup(self, entry)
    else
        self._queue:Push(entry)
    end
end

export type InternalPopup = typeof(m)

Signal.Connect(Id.C2C.SHOW_POPUP_CLIENT, function(entry)
    m:Show(entry)
end)

-----------------------------
-- Quick test
-----------------------------
--[=[ example
```lua
local function _test()
    warn("[Popup]")
    task.wait(3)
    Signal.Broadcast(Id.Protocol.C2C.SHOW_POPUP, {
        ok = function()
            trace("@@@ Test OK")
        end,
        text = "Test OK",
    })
    Signal.Broadcast(Id.Protocol.C2C.SHOW_POPUP, {
        yes = function()
            trace("@@@ Test Yes/No")
        end,
        text = "Test Yes/No",
    })
    Signal.Broadcast(Id.Protocol.C2C.SHOW_POPUP, {
        ok = function()
            trace("@@@ Another OK")
        end,
        text = "Another OK",
    })
end
task.spawn(_test)
```
--]=]

return m :: Popup

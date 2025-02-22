--[=[
    Ad-hoc module to locally fake `require(script.Parent.XXX)`
    Usage:
        ```lua
        script = script or require("script")
        local E = require(script.Parent.Enum)
        ```
]=]

return table.freeze(setmetatable({}, {
    __index = function(self, key)
        return key == "Parent" and self or ("./" .. key)
    end
}))
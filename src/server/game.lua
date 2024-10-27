
--[=[
    Ad-hoc module to locally fake `require(game.ReplicatedStorage.shared.XXX)`
    Note: consider to turn-off `luau-lsp.diagnostics.strictDatamodelTypes`
]=]
local mt = {}

local shared = setmetatable({}, mt) :: any
local server_data = setmetatable({}, mt) :: any
local server = setmetatable({ data = server_data }, mt) :: any

function mt:__index(k)
    if self == server then
        return "../server/" .. k
    elseif self == shared then
        return "../shared/" .. k
    elseif self == server_data then
        return "../server/data/" .. k
    end
    return k
end

local m = table.freeze {
    ReplicatedStorage = { shared = shared },
    ServerScriptService = { server = server },
}
print(m.ServerScriptService.server.data.AbilityCSV)
return (m :: any) :: typeof(game)

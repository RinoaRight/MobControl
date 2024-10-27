--[=[
  Usage:
```lua
    local describe = require('lspec')
    describe('Test function', function (it)
        it('should print out this failure', function ()
        assert(1 == 2, '1 should equal 2!')
    end)
--]=]
local function describe(name, descriptor)
    local errors = {}
    local successes = {}

    function it(spec_line, spec)
        local status = xpcall(spec, function(err)
            table.insert(errors, string.format("\t%s\n\t\t%s\n", spec_line, err))
        end)

        if status then
            table.insert(successes, string.format("\t%s\n", spec_line))
        end
    end

    local _status = xpcall(descriptor, function(err)
        table.insert(errors, err)
    end, it)

    print(name)
    if #errors > 0 then
        print("Failures:")
        print(table.concat(errors))
    end

    if #successes > 0 then
        print("Successes:")
        print(table.concat(successes))
    end
end



return describe

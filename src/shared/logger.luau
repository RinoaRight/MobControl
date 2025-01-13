--!strict

-- Copyright (c) 2024 Andrew Zhilin (https://github.com/zoon)
-- License: MIT

--- @todo:
--- - add set_global_prettifier
--  - add set_global_delimiter


--[=[
    Logger Module for luau/Roblox

    A flexible and efficient logging solution for Luau applications.

    Features:
    - Multiple log levels: DEBUG, TRACE, INFO, WARN, ERROR, FATAL
    - Customizable output and formatting
    - Lazy evaluation of log arguments for improved performance
    - Metrics tracking for log counts and execution time
    - Global and per-logger configuration

    Basic Usage:
    ```lua
    local Logger = require("logger")

    -- Create a new logger
    local log = Logger.create("MyLogger")

    -- Set the log level (default is INFO)
    log:set_level("debug")

    -- Log messages
    log:debug("This is a debug message")
    log:info("Hello, %s!", "World")
    log:warn("Warning: %d errors found", 3)

    -- Use lazy evaluation for expensive operations
    log:debug("Expensive calculation: ", function() return expensive_calculation() end)
    ```

    Advanced Usage:
    ```lua
    -- Customize output
    log:set_output(function(msg) print("[CUSTOM]", msg) end)

    -- Set a custom delimiter for non-formatted messages
    log:set_delimiter(" | ")

    -- Set a custom prettifier for non-string values
    log:set_prettifier(function(v) return type(v) == "table" and JSON.encode(v) or tostring(v) end)

    -- Create a level-specific logger
    local error_log = log:make_level_logger("error")
    error_log("This will always log at ERROR level")

    -- Get and format metrics
    local metrics = log:get_metrics()
    print(Logger.format_metrics(metrics))
    ```

    Global Configuration:
    ```lua
    -- Set global log level
    Logger.set_global_level("warn")

    -- Get global metrics
    local global_metrics = Logger.get_global_metrics()
    ```

    Notes:
    - In production environments, set __DEV__ to false for optimized performance
    - Use Logger.global for quick logging without creating a new logger instance
    - For comprehensive API documentation, refer to the inline comments for each method
]=]

local __DEV__ = _G.__DEV__ or true
local __GLOBAL_LOG_LEVEL__: int = _G.__LOG_LEVEL__ or 2

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
type prettifier = (any) -> str
type output = (str) -> ()
type level = int | level_name

--- @note: standard luau distribution does not have `warn`, so we fallback to `print`
local _warn = warn or print

local MAX_FORMAT_STRING_LEN = 128

-- type for auto-completion
type level_name = "debug" | "trace" | "info" | "warn" | "error" | "fatal"

local LOG_LEVELS = table.freeze {
    DEBUG = 1,
    TRACE = 2,
    INFO = 3,
    WARN = 4,
    ERROR = 5,
    FATAL = 6,
}

type Metrics = {
    count: array<int>,
    time: array<num>,
}

export type Logger = {
    --[=[
    Logger name, appears in the log message.
    ]=]
    name: str,

    --[=[
    Logs a debug-level message. Arguments are lazily evaluated, allowing for
    efficient logging even when debug logs are filtered out.

    @param self Logger The logger instance.
    @param fmt any The format string or first argument of the log message.
    @param ... any Additional arguments. Can include functions for lazy evaluation.

    Note: You can include stack traces in your log messages by passing debug.traceback
    as an argument. It will be called with appropriate parameters to generate a stack trace.

    Example:
    ```lua
    logger:debug("An error occurred", debug.traceback)
    ```
    ]=]
    debug: (self: Logger, fmt: any, ...any) -> (),

    --[=[
    Logs a trace-level message. Arguments are lazily evaluated, allowing for
    efficient logging even when debug logs are filtered out.

    @param self Logger The logger instance.
    @param fmt any The format string or first argument of the log message.
    @param ... any Additional arguments. Can include functions for lazy evaluation.

    Note: You can include stack traces in your log messages by passing debug.traceback
    as an argument. It will be called with appropriate parameters to generate a stack trace.

    Example:
    ```lua
    logger:trace("Function called", debug.traceback)
    ```
    ]=]
    trace: (self: Logger, fmt: any, ...any) -> (),

    --[=[
    Logs a info-level message. Arguments are lazily evaluated, allowing for
    efficient logging even when debug logs are filtered out.

    @param self Logger The logger instance.
    @param fmt any The format string or first argument of the log message.
    @param ... any Additional arguments. Can include functions for lazy evaluation.

    Note: You can include stack traces in your log messages by passing debug.traceback
    as an argument. It will be called with appropriate parameters to generate a stack trace.

    Example:
    ```lua
    logger:info("Operation completed", debug.traceback)
    ```
    ]=]
    info: (self: Logger, fmt: any, ...any) -> (),

    --[=[
    Logs a warn-level message. Arguments are lazily evaluated, allowing for
    efficient logging even when debug logs are filtered out.

    @param self Logger The logger instance.
    @param fmt any The format string or first argument of the log message.
    @param ... any Additional arguments. Can include functions for lazy evaluation.

    Note: You can include stack traces in your log messages by passing debug.traceback
    as an argument. It will be called with appropriate parameters to generate a stack trace.

    Example:
    ```lua
    logger:warn("Potential issue detected", debug.traceback)
    ```
    ]=]
    warn: (self: Logger, fmt: any, ...any) -> (),

    --[=[
    Logs a error-level message. Arguments are lazily evaluated, allowing for
    efficient logging even when debug logs are filtered out.

    @param self Logger The logger instance.
    @param fmt any The format string or first argument of the log message.
    @param ... any Additional arguments. Can include functions for lazy evaluation.

    Note: You can include stack traces in your log messages by passing debug.traceback
    as an argument. It will be called with appropriate parameters to generate a stack trace.

    Example:
    ```lua
    logger:error("An error occurred", debug.traceback)
    ```
    ]=]
    error: (self: Logger, fmt: any, ...any) -> (),

    --[=[
    Logs a fatal-level message. Arguments are lazily evaluated, allowing for
    efficient logging even when debug logs are filtered out.

    @param self Logger The logger instance.
    @param fmt any The format string or first argument of the log message.
    @param ... any Additional arguments. Can include functions for lazy evaluation.

    Note: You can include stack traces in your log messages by passing debug.traceback
    as an argument. It will be called with appropriate parameters to generate a stack trace.

    Example:
    ```lua
    logger:fatal("Critical error", debug.traceback)
    ```
    ]=]
    fatal: (self: Logger, fmt: any, ...any) -> (),

    --[=[
    Method of the logger is used for throwing formatted errors.

    @param self Logger The logger instance.
    @param fmt any The format string or first argument of the log message.
    @param ... any Additional arguments. Can include functions for lazy evaluation.
    ]=]
    throw: (self: Logger, fmt: any, ...any) -> (),

    --[=[
    Method of the logger is used for throwing formatted errors.

    @param self Logger The logger instance.
    @param condition bool The condition to check.
    @param fmt any The format string or first argument of the log message.
    @param ... any Additional arguments. Can include functions for lazy evaluation.
    ]=]
    assert: <a>(self: Logger, condition: a, fmt: any, ...any) -> a,

    --[=[
    Creates a logging function for a specific log level. The returned function
    incorporates lazy evaluation of its arguments.

    @param self Logger The logger instance.
    @param level level The log level (can be a number 1-6 or a string like "debug", "info", etc.)
    @return function A new function that logs messages at the specified level with lazy evaluation.
    ]=]
    make_level_logger: (self: Logger, level: level) -> (fmt: any, ...any) -> (),

    --[=[
    Sets the logging level for this logger instance.

    The log level determines which messages are output and which are ignored.
    Messages with a severity lower than the set level will not be logged.

    @param self Logger The logger instance.
    @param level level The new log level. Can be either an integer (1-6) or a string ("debug", "trace", "info", "warn", "error", "fatal").
    @return Logger The logger instance, allowing for method chaining.

    @usage
    ```lua
    local logger = Logger.create("MyLogger")
    logger:set_level("warn")  -- Only warnings and more severe messages will be logged
    -- or
    logger:set_level(Logger.LOG_LEVELS.WARN)  -- Same effect, using the numeric constant
    ```
    ]=]
    set_level: (self: Logger, level: level) -> Logger,

    --[=[
    Sets the delimiter used to separate log message components.

    This delimiter is used when concatenating multiple arguments in a log message
    that doesn't use a format string.

    @param self Logger The logger instance.
    @param delimiter string? The delimiter to use. If nil, defaults to "\t" (tab character).
    @return Logger The logger instance, allowing for method chaining.

    @usage
    ```lua
    local logger = Logger.create("MyLogger")
    logger:set_delimiter(" | ")  -- Use a pipe with spaces as delimiter
    logger:info("User", "John", "logged in")  -- Will output: [MyLogger] INFO -- User | John | logged in
    ```
    ]=]
    set_delimiter: (self: Logger, delimiter: str?) -> Logger,

    --[=[
    Sets the prettifier function for this logger instance.

    The prettifier function is used to format non-string values in log messages.
    This allows for custom formatting of complex data types in logs.

    @param self Logger The logger instance.
    @param prettifier function? The prettifier function to use for formatting log messages. If nil, defaults to `tostring`.
    @return Logger The logger instance, allowing for method chaining.

    @usage
    ```lua
    local logger = Logger.create("MyLogger")
    logger:set_prettifier(function(value)
        if type(value) == "table" then
            -- Custom formatting for tables
            return JSON.encode(value)
        else
            return tostring(value)
        end
    end)
    ```
    ]=]
    set_prettifier: (self: Logger, pp: prettifier?) -> Logger,

    --[=[
    Sets the output function for this logger instance.

    The output function is used to write log messages. This allows for custom
    handling of log output, such as writing to a file or sending to a remote server.

    @param self Logger The logger instance.
    @param output function? The output function to use for writing log messages.
    If nil, reverts to the default (print for debug/trace/info, warn for warn/error/fatal).
    @return Logger The logger instance, allowing for method chaining.

    @usage
    ```lua
    local logger = Logger.create("MyLogger")
    logger:set_output(function(msg)
        -- Custom output function that prepends a timestamp
        print(os.date("%Y-%m-%d %H:%M:%S") .. " " .. msg)
    end)
    ```
    ]=]
    set_output: (self: Logger, output: output?) -> Logger,

    --[=[
    Retrieves the current metrics for this logger instance.

    Metrics include the count of log messages and the total time spent logging for each log level.
    This can be useful for analyzing logging patterns and performance impact.

    @param self Logger The logger instance.
    @return Metrics A frozen table containing two arrays:
        - count: An array where each index corresponds to a log level (1-6),
        containing the number of log messages at that level.
        - time: An array where each index corresponds to a log level (1-6),
        containing the total time spent logging at that level (in seconds).
    @usage
    ```lua
    local logger = Logger.create("MyLogger")
    -- ... some logging operations ...
    local metrics = logger:get_metrics()
    print(Logger.format_metrics(metrics))
    ```
    ]=]
    get_metrics: (self: Logger) -> Metrics,

    --[=[
    Resets the metrics for this logger instance.

    This method sets the count and time metrics for each log level back to zero.
    It's useful for starting a new logging session or resetting stats after analysis.

    @param self Logger The logger instance.
    @return Logger The logger instance, allowing for method chaining.

    @usage
    ```lua
    local logger = Logger.create("MyLogger")
    -- ... some logging operations ...
    local before_metrics = logger:get_metrics()
    logger:reset_metrics()
    -- ... more logging operations ...
    local after_metrics = logger:get_metrics()
    -- 'after_metrics' will only include data from operations after the reset
    ```
    ]=]
    reset_metrics: (self: Logger) -> Logger,

    _internal: {
        _level: int,
        _metrics_count: array<int>,
        _metrics_time: array<num>,
        _delimiter: str,
        _prettifier: prettifier,
        _output: output?,
        _level_loggers_cache: map<int, (fmt: any, ...any) -> ()>,
    },
}

type Module = {

    --[=[
    Defines the available log levels and their corresponding numeric values.

    The log levels are ordered from least severe (DEBUG) to most severe (FATAL).
    Each level is assigned a unique integer value, which is used internally
    for comparisons and filtering of log messages.

    Levels:
    - DEBUG (1): Detailed information, typically of interest only when diagnosing problems.
    - TRACE (2): Finer-grained informational events than DEBUG.
    - INFO (3): Confirmation that things are working as expected.
    - WARN (4): An indication that something unexpected happened, or indicative of some problem in the near future.
    - ERROR (5): Due to a more serious problem, the software has not been able to perform some function.
    - FATAL (6): A very severe error event that will presumably lead the application to abort.

    This table is frozen to prevent accidental modifications during runtime.

    Usage:
    - To set log levels: logger:set_level(Logger.LOG_LEVELS.WARN)
    - To compare levels: if current_level >= Logger.LOG_LEVELS.ERROR then ... end
    ]=]
    LOG_LEVELS: typeof(LOG_LEVELS),

    --[=[
    Creates a new logger instance.

    Each logger instance can have its own configuration (level, output function, etc.)
    while still respecting the global settings.

    - Note:
        - If a logger with the given name already exists, this method will append "*" to the name until it's unique.
        - The new logger initially uses the global log level, but this can be changed using the set_level method.

    @param name? string The name for the new logger. If not provided, defaults to the script's name or "unknown".
    @return Logger A new logger instance.

    Usage:
    ```lua
    local Logger = require("logger")
    local my_logger = Logger.create("MyModule")
    my_logger:info("MyModule initialized")
    ```
    ]=]
    create: (name: str?) -> Logger,

    --[=[
    Sets the initial global logging level. This method can only be called once.

    The global log level serves as the default level for all newly created logger instances.
    It determines which messages are output by default and which are ignored.

    - throws error if called more than once.
    - Note: this method should typically be called early in your application's initialization process.

    @param level The log level to set. Can be either an integer (1-6) or a string ("debug", "trace", "info", "warn", "error", "fatal").
    Usage:
    ```lua
    local Logger = require("logger")
    Logger.set_global_level("info")  -- Sets global level to INFO
    -- or
    Logger.set_global_level(Logger.LOG_LEVELS.INFO)  -- Same effect, using the numeric constant
    ```
   ]=]
    set_global_level: (level: level) -> (),

    --[=[
    Retrieves the name of the current global logging level.
    - Note: This method is useful for checking the current global logging configuration.

    @return str The name of the current global log level

    Usage
    ```lua
    local Logger = require("logger")
    print(`Current global log level: {Logger.get_current_global_level()}`)
    ```
    ]=]
    get_global_level: () -> str,

    --[=[
    Retrieves the aggregated metrics from all logger instances.

    This function combines the metrics from all active loggers, providing
    a global view of logging activity across the entire application.

    @return Metrics A table containing aggregated count and time for each log level
    ]=]
    get_global_metrics: () -> Metrics,

    --[=[
    Resets the metrics for all logger instances.

    This function sets the count and time metrics back to zero for every
    logger instance. It's useful for starting a new logging session or
    resetting stats across the entire application.
    ]=]
    reset_global_metrics: () -> (),

    --[=[
    Formats a Metrics table into a human-readable string.

    This function takes a Metrics table (as returned by get_global_metrics
    or Logger:get_metrics) and converts it into a formatted string for
    easy reading and analysis.

    @param metrics Metrics The metrics to format
    @return string A multi-line string containing formatted metrics information
    ]=]
    format_metrics: (metrics: Metrics) -> str,

    --[=[
    The global logger instance.

    This is a pre-created logger instance that can be used for quick logging without creating a new logger.

    - Note: While convenient, it's often better to create specific loggers for different modules or
    components of your application for more granular control and clearer log output.

    Usage:
    ```lua
    local Logger = require("logger")
    Logger.global:info("Application started")
    ```
    ]=]
    global: Logger,

    internal: {
        check_fmt: (fmt: any, ...any) -> (bool, num, str?),
        format_message: (prettifier, delim: str, prefix: str, fmt: any, ...any) -> str,
        push_args: <a>(coerce: (any) -> a, args: array<any>, ...any) -> array<a>,
    },
}

-----------------------------
-- Util
-----------------------------

-- Create a reverse mapping of log levels to their names
local LEVEL_NAMES = {} :: array<str>
for k, v in pairs(LOG_LEVELS) do
    LEVEL_NAMES[v] = k
end
table.freeze(LEVEL_NAMES)

local METHOD_NAMES = {} :: map<int, level_name>
for k, v in pairs(LOG_LEVELS) do
    METHOD_NAMES[v] = string.lower(k) :: level_name
end

do -- Validate that all log levels have corresponding names
    for i = LOG_LEVELS.DEBUG, LOG_LEVELS.FATAL do
        assert(LEVEL_NAMES[i], `invalid log level: {i}`)
    end
end

--[=[
    Converts a log level to its corresponding numeric value.

    - throws string If the provided log level is invalid.
    @param level level The log level to convert, either as a string or a number.
    @return int The numeric value of the log level.
]=]
local function level_to_numeric(level: level): int
    if type(level) == "number" then
        assert(LEVEL_NAMES[level], `invalid log level: {level}`)
        return level
    elseif type(level) == "string" then
        local name = string.upper(level)
        return assert(LOG_LEVELS[name], `invalid log level: {level}`)
    else
        error(`invalid log level type: {level}`)
    end
end

--[=[
    Creates a new Metrics table with optional count and time arrays.

    @param count? array<int> An optional array of counts for each log level.
    @param time? array<num> An optional array of times for each log level.
    @return Metrics A new Metrics table with the provided count and time arrays.
]=]
local function create_metrics(count: array<int>?, time: array<num>?): Metrics
    return table.freeze({
        count = count and table.clone(count) or table.create(LOG_LEVELS.FATAL, 0),
        time = time and table.clone(time) or table.create(LOG_LEVELS.FATAL, 0.0),
    }) :: any
end

--[=[
    This function processes a list of arguments, evaluating them lazily. If it encounters a function,
    it calls the function with the remaining arguments and returns the result.

    Behavior:
    - Processes arguments from left to right.
    - If a non-function argument is encountered, it is returned as-is.
    - If debug.traceback is encountered, it is called with the remaining arguments.
    - If a function is encountered, it is called with all subsequent arguments.
    - If the function call is successful, all its return values are returned.
    - If the function call fails, an error message is returned.

    @param ... Any number of arguments of any type.
    @return If no function is found, returns all input arguments.
    @return If a function is found and successfully called, returns its results.
    @return If a function call fails, returns an error message.

    Usage:
    ```lua
    print(evaluate_args(1, 2, function(a: num, b: num) return a + b, a - b end, 3, 4))  -- Output: 1 2 7 -1
    local error_msg = evaluate_args(1, function() error("Test error") end, 2)
    print(error_msg)  -- Output: Forcing lazy evaluation failed: Test error
    ```
]=]
local evaluate_args: (...any) -> ...any
do
    local function handle_traceback(index: int, ...): str
        if __DEV__ and select("#", ...) > 2 then
            error(`debug.traceback accepts 0..2 arguments, got: {select("#", ...)}`)
        end
        local msg = select(1, ...) or "\ntraceback:"
        --- We intentionally limit the stack trace depth to avoid empty
        --- tracebacks and exclude non-informative stack frames from the logger
        --- itself.
        --- - The stack depth calculation is as follows:
        ---   - recurse(index): Current depth in the argument processing
        ---   - handle_traceback(1): This function call
        ---   - process_args(1): The parent function call
        ---   - log(1): The internal logging function
        ---   - logger.method(1): The public logging method (e.g., debug, info)
        ---   - call-site(1): The user's code where the logger is called
        --- This results in a total depth of index + 5, ensuring we capture the
        --- relevant stack frames. If the user pass greater value, we will cap it
        --- to max_level to prevent empty tracebacks. User still can pass lesser
        --- value, but that's on them. Best practice is to pass nothing.
        local max_level = index + 5
        local min_level = 1
        local level = select(2, ...) or max_level
        level = math.max(math.min(level, max_level), min_level)
        return debug.traceback(msg, level)
    end
    local function handle_pcall_results(success, ...)
        if success then
            return ...
        else
            return "Forcing lazy evaluation failed: " .. "\n" .. select(1, ...)
        end
    end
    local function recurse(index: int, count: int, ...: any): ...any
        if index > count then
            return
        end
        local arg = select(index, ...)
        if type(arg) == "function" then
            if arg == debug.traceback then
                return handle_traceback(index, select(index + 1, ...))
            end
            return handle_pcall_results(pcall(arg, select(index + 1, ...)))
        else
            return arg, recurse(index + 1, count, ...)
        end
    end
    evaluate_args = function(...)
        local args_count = select("#", ...)
        return recurse(1, args_count, ...)
    end
end

--[=[
    Creates a set from string characters for quick checking
    @param str: string from which to create the set
    @return table where keys are byte values of characters and values are true
]=]
local function make_set(str)
    local set = {}
    for i = 1, #str do
        set[string.byte(str, i)] = true
    end
    return set
end

local BYTE_PERCENT = string.byte("%")
local BYTE_PERIOD = string.byte(".")
local BYTE_0 = string.byte("0")
local BYTE_9 = string.byte("9")

local FMT_FLAGS = make_set("-+ #0")
local FMT_OPTIONS = make_set("cdi*ouxXeEfgGqs")

local _scratch_buffer = buffer.create(MAX_FORMAT_STRING_LEN)
local _scratch_array = table.create(16)

--- Checks if a byte represents a digit
--- @param byte: byte value of a character
local function is_digit(byte: u8): bool
    return byte >= BYTE_0 and byte <= BYTE_9
end

--[=[
    Checks the correctness of a format string and the matching number of
    arguments. Almost stolen from luau-language codebase.

    Performance: ~500 ns, buffer access is 1.5x faster than string.byte implementation

    @param fmt: format string or any
    @param ...: arguments for formatting
    @return success, number of specifiers, error message
]=]
local function check_fmt(fmt: any, ...: any): (bool, int, str?)
    if type(fmt) ~= "string" or #fmt < 2 then
        return true, 0
    elseif #fmt > MAX_FORMAT_STRING_LEN then
        if __DEV__ then
            print(`INFO: fmt arg exceeds maximum length: {#fmt} (limit: {MAX_FORMAT_STRING_LEN})`)
        end
        return true, 0
    end
    local len = #fmt
    local buf = _scratch_buffer
    local byte = buffer.readu8
    buffer.writestring(buf, 0, fmt)
    local i = 0
    local specifier_count = 0
    while i < len do
        local ch = byte(buf, i)
        if ch == BYTE_PERCENT then
            i += 1
            specifier_count += 1
            -- Escaped % doesn't allow for flags/etc.
            if i < len and byte(buf, i) == BYTE_PERCENT then
                i += 1
                continue
            end
            -- Skip flag
            while i < len and FMT_FLAGS[byte(buf, i)] do
                i += 1
            end
            -- Skip width (up to two digits)
            if i < len and is_digit(byte(buf, i)) then
                i += 1
                if i < len and is_digit(byte(buf, i)) then
                    i += 1
                end
            end
            -- Skip precision (up to two digits)
            if i < len and byte(buf, i) == BYTE_PERIOD then
                i += 1
                if i < len and is_digit(byte(buf, i)) then
                    i += 1
                    if i < len and is_digit(byte(buf, i)) then
                        i += 1
                    end
                end
            end
            if i >= len then
                return false, specifier_count, "unfinished format specifier"
            end
            if not FMT_OPTIONS[byte(buf, i)] then
                local invalid_opt = string.char(byte(buf, i))
                return false, specifier_count, `invalid format specifier: '%{invalid_opt}'`
            end
        end
        i += 1
    end
    local args_count = select("#", ...)
    if specifier_count > 0 and specifier_count ~= args_count then
        return false, specifier_count, `invalid format: {specifier_count} format specifier(s), {args_count} arg(s)`
    end
    return true, specifier_count, nil
end
--[=[
    Pushes the given arguments into the provided array, coercing each argument to the specified type.
    @param coerce: a function to coerce each argument to the desired type
    @param a: the array to push the arguments into
    @param ...: the arguments to push into the array
    @return the modified array
]=]
local function push_args<a>(coerce: (any) -> a, a: array<a>, ...: any): array<a>
    for i = 1, select("#", ...) do
        local v = select(i, ...)
        table.insert(a, coerce(v))
    end
    return a
end

-----------------------------
-- Logger
-----------------------------
local Logger = {} :: Logger;
(Logger :: any).__index = Logger

--[=[
    Formats a message with the given format string and arguments.
    @param prettifier: function to prettify the output
    @param delimiter: list delimiter
    @param prefix: prefix for the message
    @param fmt: format string or the first argument of the message (evaluated lazily)
    @param ...: arguments for formatting or additional parts of the message (evaluated lazily)
    @return formatted error string
]=]
local function format_message(prettifier: prettifier, delimiter: str, prefix: str, fmt: any, ...: any): str
    local ok, count, err = check_fmt(fmt, ...)
    -- We format the string only if we have correct specifiers. In production,
    -- if we encounter incorrect specifiers, we fallback to concatenating all
    -- arguments and silently ignore the format error.
    if not ok and __DEV__ then
        error(err, 4)
    end
    if ok and count > 0 then
        return prefix .. string.format(fmt, ...)
    else
        table.clear(_scratch_array)
        local args = push_args(prettifier, _scratch_array, fmt, ...)
        return prefix .. table.concat(args, delimiter)
    end
end

--[=[
    Formats the prefix for a log message, including the logger name and the log severity.
    @param name: the name of the logger
    @param severity: string representation of the log severity
    @return the formatted prefix
]=]
local function format_prefix(name: str, severity: str): str
    return string.format("[%s] %s -- ", name, severity)
end

--[=[
    Main internal logging function, supports lazy evaluation of arguments.
    @param self: logger instance
    @param level: logging level
    @param output: function for output
    @param fmt: format string or the first argument of the message
    @param ...: arguments for formatting or additional parts of the message
]=]
local function log(self: Logger, level: int, output: output, fmt: any, ...: any): ()
    if self._internal._level > level then
        return
    else
        local start_time = os.clock()
        local pp = self._internal._prettifier
        local prefix = format_prefix(self.name, LEVEL_NAMES[level])
        local delim = self._internal._delimiter
        output(format_message(pp, delim, prefix, evaluate_args(fmt, ...)))
        local elapsed = os.clock() - start_time
        self._internal._metrics_count[level] += 1
        self._internal._metrics_time[level] += elapsed
    end
end

-----------------------------
-- Logger methods
-----------------------------
function Logger.debug(self: Logger, fmt: any, ...: any): ()
    log(self, LOG_LEVELS.DEBUG, self._internal._output or print, fmt, ...)
end

function Logger.trace(self: Logger, fmt: any, ...: any): ()
    log(self, LOG_LEVELS.TRACE, self._internal._output or print, fmt, ...)
end

function Logger.info(self: Logger, fmt: any, ...: any): ()
    log(self, LOG_LEVELS.INFO, self._internal._output or print, fmt, ...)
end

function Logger.warn(self: Logger, fmt: any, ...: any): ()
    log(self, LOG_LEVELS.WARN, self._internal._output or _warn, fmt, ...)
end

function Logger.error(self: Logger, fmt: any, ...: any): ()
    log(self, LOG_LEVELS.ERROR, self._internal._output or _warn, fmt, ...)
end

function Logger.fatal(self: Logger, fmt: any, ...: any): ()
    log(self, LOG_LEVELS.FATAL, self._internal._output or _warn, fmt, ...)
end

function Logger.make_level_logger(self: Logger, level: level): (fmt: any, ...any) -> ()
    local log_level = level_to_numeric(level)
    if not self._internal._level_loggers_cache[log_level] then
        local method_name = METHOD_NAMES[log_level]
        -- we use the fact that methods name is a level name in lower case
        local method: (Logger, ...any) -> () = assert(Logger[method_name], `Logger has no {method_name} method`)
        self._internal._level_loggers_cache[log_level] = function(fmt: any, ...: any)
            method(self, fmt, ...)
        end
    end
    return self._internal._level_loggers_cache[log_level]
end

function Logger.throw(self: Logger, fmt: any, ...: any): ()
    local prefix = format_prefix(self.name, LEVEL_NAMES[LOG_LEVELS.ERROR])
    local pp = self._internal._prettifier
    local delim = self._internal._delimiter
    error(format_message(pp, delim, prefix, evaluate_args(fmt, ...)), 3)
end

function Logger.assert<a>(self: Logger, condition: a, fmt: any, ...: any): a
    if condition then
        return condition
    end
    local prefix = format_prefix(self.name, "ASSERTION FAILED")
    local pp = self._internal._prettifier
    local delim = self._internal._delimiter
    error(format_message(pp, delim, prefix, evaluate_args(fmt, ...)), 2)
end

function Logger.set_level(self: Logger, level: level): Logger
    local new_level = level_to_numeric(level)
    local previous_level = self._internal._level
    if new_level ~= previous_level then
        self._internal._level = new_level
        print(debug.traceback(`(!) Logger '{self.name}': log level changed from *{LEVEL_NAMES[previous_level]}* to *{LEVEL_NAMES[new_level]}*`, 2))
    end
    return self
end

function Logger.set_output(self: Logger, output: output?): Logger
    self._internal._output = output
    return self
end

function Logger.set_prettifier(self: Logger, prettifier: prettifier?): Logger
    self._internal._prettifier = prettifier or tostring -- mus be not nil
    return self
end

function Logger.set_delimiter(self: Logger, delimiter: str?): Logger
    self._internal._delimiter = delimiter or " "
    return self
end

function Logger.get_metrics(self: Logger): Metrics
    return create_metrics(self._internal._metrics_count, self._internal._metrics_time)
end

function Logger.reset_metrics(self: Logger): Logger
    for i = LOG_LEVELS.DEBUG, LOG_LEVELS.FATAL do
        self._internal._metrics_count[i] = 0
        self._internal._metrics_time[i] = 0.0
    end
    return self
end

-----------------------------
-- Module
-----------------------------
local m = {} :: Module
m.LOG_LEVELS = LOG_LEVELS
local _initial_set: str? = nil

local _weak_value_mt = table.freeze { __mode = "v" }

local _loggers = (setmetatable({}, _weak_value_mt) :: any) :: map<str, Logger>

function m.set_global_level(level: level): ()
    if _initial_set then
        error("ERROR -- initial log level already set:\n-----\n" .. _initial_set, 3)
    end
    local log_level = level_to_numeric(level)
    __GLOBAL_LOG_LEVEL__ = log_level
    _initial_set = debug.traceback(`Logger: global log level set to {LEVEL_NAMES[log_level]}`, 2)
end

function m.get_global_level(): str
    return LEVEL_NAMES[__GLOBAL_LOG_LEVEL__]
end

function m.get_global_metrics(): Metrics
    local metrics = create_metrics()
    for _, logger in pairs(_loggers) do
        for i = LOG_LEVELS.DEBUG, LOG_LEVELS.FATAL do
            metrics.count[i] += logger._internal._metrics_count[i]
            metrics.time[i] += logger._internal._metrics_time[i]
        end
    end
    return metrics
end

function m.reset_global_metrics(): ()
    for _, logger in pairs(_loggers) do
        logger:reset_metrics()
    end
end

function m.format_metrics(metrics: Metrics): string
    local lines = {
        "Logger Metrics:",
        "---------------",
    }
    local total_count = 0
    local total_time = 0

    for level, name in ipairs(LEVEL_NAMES) do
        local count = metrics.count[level]
        local time = metrics.time[level]
        total_count += count
        total_time += time

        if count > 0 then
            local avg_time = time / count
            table.insert(lines, string.format("%5s: %4d logs, %9.6f seconds (avg: %.6f s/log)", name, count, time, avg_time))
        end
    end

    local avg_total_time = total_count > 0 and total_time / total_count or 0
    table.insert(lines, string.format("------------------------"))
    table.insert(lines, string.format("Total: %4d logs, %9.6f seconds (avg: %.6f s/log)", total_count, total_time, avg_total_time))

    return table.concat(lines, "\n")
end

function m.create(name: string?): Logger
    name = name or "unknown"
    assert(name, "type coercion")
    while _loggers[name] ~= nil do
        name = name .. "*"
    end
    local logger = table.freeze(setmetatable({
        name = name :: string,
        _internal = {
            _level = __GLOBAL_LOG_LEVEL__,
            _metrics_count = table.create(LOG_LEVELS.FATAL, 0),
            _metrics_time = table.create(LOG_LEVELS.FATAL, 0.0),
            _delimiter = "\t",
            _prettifier = tostring,
            _output = nil,
            _level_loggers_cache = setmetatable({}, _weak_value_mt),
        },
    }, Logger)) :: any
    _loggers[name] = logger :: Logger
    return logger
end

-------------------
-- exports
-------------------
m.internal = {
    check_fmt = check_fmt,
    format_message = format_message,
    push_args = push_args,
}
m.global = m.create("global")

--[[ test
m.global:debug("debug", debug.traceback)
m.global:trace("trace", debug.traceback)
m.global:info("info", debug.traceback)
m.global:warn("warn", debug.traceback)
m.global:error("error", debug.traceback)
m.global:fatal("fatal", debug.traceback)

m.global:debug("debug %s", "test")
m.global:trace("trace %s", "test")
m.global:info("info %s", "test")
m.global:warn("warn %s", "test")
m.global:error("error %s", "test")
m.global:fatal("fatal %s", "test")
-- m.global:assert(false, "assert", debug.traceback)
--]]

print(`[logger] development mode: {if __DEV__ then "ON" else "OFF"}, global log level: {m.get_global_level()}`)

return (table.freeze(m) :: any) :: Module

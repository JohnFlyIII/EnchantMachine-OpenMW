-- Debug and logging system for Dwemer Enchanting Machine
-- Provides development tools, logging, and diagnostics

local storage = require('openmw.storage')
local core = require('openmw.core')
local types = require('openmw.types')
local util = require('openmw.util')

-- Debug storage
local debugData = storage.globalSection('EnchantMachine_Debug')

-- Configuration
local DEBUG_ENABLED = true
local LOG_LEVELS = {
    ERROR = 1,
    WARN = 2,
    INFO = 3,
    DEBUG = 4,
    TRACE = 5,
}

local currentLogLevel = LOG_LEVELS.INFO

-- Initialize debug data
local function ensureDebugStructure()
    if not debugData:get('logs') then
        debugData:set('logs', {})
    end
    if not debugData:get('metrics') then
        debugData:set('metrics', {
            totalDeposits = 0,
            totalRecharges = 0,
            totalUpgrades = 0,
            totalSoulPowerAdded = 0,
            totalSoulPowerSpent = 0,
            errors = {},
        })
    end
    if not debugData:get('performance') then
        debugData:set('performance', {})
    end
end

-- Get timestamp
local function getTimestamp()
    return os.date("%Y-%m-%d %H:%M:%S")
end

-- Log message
local function log(level, category, message, data)
    if not DEBUG_ENABLED then return end
    if level > currentLogLevel then return end

    ensureDebugStructure()

    local levelNames = {"ERROR", "WARN", "INFO", "DEBUG", "TRACE"}
    local levelName = levelNames[level] or "UNKNOWN"

    local logEntry = {
        timestamp = getTimestamp(),
        level = levelName,
        category = category,
        message = message,
        data = data,
    }

    -- Add to log buffer
    local logs = debugData:get('logs')
    if not logs or type(logs) ~= 'table' then
        logs = {}
    end

    table.insert(logs, logEntry)

    -- Keep only last 100 entries
    if #logs > 100 then
        table.remove(logs, 1)
    end

    -- Make a copy to ensure it's saved properly
    debugData:set('logs', logs)

    -- Print to console
    print(string.format("[EnchantMachine][%s][%s] %s", levelName, category, message))
    if data then
        print("  Data: " .. tostring(data))
    end
end

-- Convenience logging functions
local function error(category, message, data)
    log(LOG_LEVELS.ERROR, category, message, data)
end

local function warn(category, message, data)
    log(LOG_LEVELS.WARN, category, message, data)
end

local function info(category, message, data)
    log(LOG_LEVELS.INFO, category, message, data)
end

local function debug(category, message, data)
    log(LOG_LEVELS.DEBUG, category, message, data)
end

local function trace(category, message, data)
    log(LOG_LEVELS.TRACE, category, message, data)
end

-- Track metrics
local function trackMetric(metricName, value)
    ensureDebugStructure()
    local metrics = debugData:get('metrics')
    if not metrics or type(metrics) ~= 'table' then
        metrics = {}
    end
    metrics[metricName] = (metrics[metricName] or 0) + value
    debugData:set('metrics', metrics)
end

local function incrementMetric(metricName)
    trackMetric(metricName, 1)
end

local function recordError(category, errorMessage, context)
    ensureDebugStructure()
    local metrics = debugData:get('metrics')
    if not metrics or type(metrics) ~= 'table' then
        metrics = {}
    end
    local errors = metrics.errors or {}

    table.insert(errors, {
        timestamp = getTimestamp(),
        category = category,
        message = errorMessage,
        context = context,
    })

    metrics.errors = errors
    debugData:set('metrics', metrics)

    error(category, errorMessage, context)
end

-- Performance tracking
local performanceTimers = {}

local function startTimer(timerName)
    performanceTimers[timerName] = core.getRealTime()
end

local function endTimer(timerName)
    if not performanceTimers[timerName] then
        warn("Performance", "Timer not started: " .. timerName)
        return 0
    end

    local elapsed = core.getRealTime() - performanceTimers[timerName]
    performanceTimers[timerName] = nil

    ensureDebugStructure()
    local perf = debugData:get('performance')
    if not perf or type(perf) ~= 'table' then
        perf = {}
    end

    if not perf[timerName] then
        perf[timerName] = {
            count = 0,
            totalTime = 0,
            minTime = elapsed,
            maxTime = elapsed,
        }
    end

    local perfData = perf[timerName]
    perfData.count = perfData.count + 1
    perfData.totalTime = perfData.totalTime + elapsed
    perfData.minTime = math.min(perfData.minTime, elapsed)
    perfData.maxTime = math.max(perfData.maxTime, elapsed)
    perfData.avgTime = perfData.totalTime / perfData.count

    perf[timerName] = perfData
    debugData:set('performance', perf)

    trace("Performance", string.format("%s completed in %.4fs", timerName, elapsed))

    return elapsed
end

-- Get all logs
local function getLogs()
    ensureDebugStructure()
    return debugData:get('logs') or {}
end

-- Get metrics
local function getMetrics()
    ensureDebugStructure()
    return debugData:get('metrics') or {}
end

-- Get performance data
local function getPerformance()
    ensureDebugStructure()
    return debugData:get('performance') or {}
end

-- Clear logs
local function clearLogs()
    debugData:set('logs', {})
    info("Debug", "Logs cleared")
end

-- Clear metrics
local function clearMetrics()
    debugData:set('metrics', {
        totalDeposits = 0,
        totalRecharges = 0,
        totalUpgrades = 0,
        totalSoulPowerAdded = 0,
        totalSoulPowerSpent = 0,
        errors = {},
    })
    info("Debug", "Metrics cleared")
end

-- Clear performance data
local function clearPerformance()
    debugData:set('performance', {})
    info("Debug", "Performance data cleared")
end

-- Generate debug report
local function generateReport()
    local report = {
        timestamp = getTimestamp(),
        logs = getLogs(),
        metrics = getMetrics(),
        performance = getPerformance(),
    }
    return report
end

-- Format report as string
local function formatReport()
    local report = generateReport()
    local output = {}

    table.insert(output, "=== ENCHANTING MACHINE DEBUG REPORT ===")
    table.insert(output, "Generated: " .. report.timestamp)
    table.insert(output, "")

    -- Metrics
    table.insert(output, "--- METRICS ---")
    local metrics = report.metrics
    table.insert(output, string.format("Total Deposits: %d", metrics.totalDeposits or 0))
    table.insert(output, string.format("Total Recharges: %d", metrics.totalRecharges or 0))
    table.insert(output, string.format("Total Upgrades: %d", metrics.totalUpgrades or 0))
    table.insert(output, string.format("Soul Power Added: %d", metrics.totalSoulPowerAdded or 0))
    table.insert(output, string.format("Soul Power Spent: %d", metrics.totalSoulPowerSpent or 0))
    table.insert(output, string.format("Errors Recorded: %d", #(metrics.errors or {})))
    table.insert(output, "")

    -- Performance
    table.insert(output, "--- PERFORMANCE ---")
    for timerName, perfData in pairs(report.performance) do
        table.insert(output, string.format("%s:", timerName))
        table.insert(output, string.format("  Calls: %d", perfData.count))
        table.insert(output, string.format("  Avg: %.4fs", perfData.avgTime or 0))
        table.insert(output, string.format("  Min: %.4fs", perfData.minTime or 0))
        table.insert(output, string.format("  Max: %.4fs", perfData.maxTime or 0))
    end
    table.insert(output, "")

    -- Recent errors
    if metrics.errors and #metrics.errors > 0 then
        table.insert(output, "--- RECENT ERRORS ---")
        local errorCount = math.min(10, #metrics.errors)
        for i = #metrics.errors - errorCount + 1, #metrics.errors do
            local err = metrics.errors[i]
            table.insert(output, string.format("[%s] %s: %s", err.timestamp, err.category, err.message))
        end
        table.insert(output, "")
    end

    -- Recent logs
    table.insert(output, "--- RECENT LOGS (last 20) ---")
    local logs = report.logs
    local logCount = math.min(20, #logs)
    for i = #logs - logCount + 1, #logs do
        local logEntry = logs[i]
        table.insert(output, string.format("[%s][%s][%s] %s",
            logEntry.timestamp, logEntry.level, logEntry.category, logEntry.message))
    end

    return table.concat(output, "\n")
end

-- Validate system state
local function validateSystemState(machineInterface)
    local issues = {}

    -- Check soul power
    local soulPower = machineInterface.getSoulPower()
    if soulPower < 0 then
        table.insert(issues, "CRITICAL: Negative soul power detected: " .. soulPower)
    end

    -- Check settings
    local settings = machineInterface.getSettings()
    if not settings.enableMachine then
        table.insert(issues, "WARNING: Machine is disabled")
    end
    if settings.enchantMultiplier < 1 or settings.enchantMultiplier > 100 then
        table.insert(issues, "WARNING: Enchant multiplier out of range: " .. settings.enchantMultiplier)
    end
    if settings.upgradeRatio < 10 or settings.upgradeRatio > 1000 then
        table.insert(issues, "WARNING: Upgrade ratio out of range: " .. settings.upgradeRatio)
    end

    if #issues == 0 then
        info("Validation", "System state validated successfully")
        return true, "All checks passed"
    else
        warn("Validation", "System state has issues")
        return false, table.concat(issues, "\n")
    end
end

-- Set log level
local function setLogLevel(level)
    if type(level) == "string" then
        level = LOG_LEVELS[level:upper()]
    end
    if level and level >= LOG_LEVELS.ERROR and level <= LOG_LEVELS.TRACE then
        currentLogLevel = level
        info("Debug", "Log level set to " .. level)
    else
        warn("Debug", "Invalid log level")
    end
end

-- Enable/disable debug
local function setDebugEnabled(enabled)
    DEBUG_ENABLED = enabled
    if enabled then
        info("Debug", "Debug mode enabled")
    end
end

-- Export interface
return {
    interfaceName = 'EnchantMachineDebug',
    interface = {
        -- Logging
        error = error,
        warn = warn,
        info = info,
        debug = debug,
        trace = trace,
        setLogLevel = setLogLevel,
        getLogs = getLogs,
        clearLogs = clearLogs,

        -- Metrics
        trackMetric = trackMetric,
        incrementMetric = incrementMetric,
        recordError = recordError,
        getMetrics = getMetrics,
        clearMetrics = clearMetrics,

        -- Performance
        startTimer = startTimer,
        endTimer = endTimer,
        getPerformance = getPerformance,
        clearPerformance = clearPerformance,

        -- Reporting
        generateReport = generateReport,
        formatReport = formatReport,

        -- Validation
        validateSystemState = validateSystemState,

        -- Configuration
        setDebugEnabled = setDebugEnabled,
    },
}

--[[
  StacyDash - Full screen heli dashboard for EdgeTX 2.12 (800x480)
  Layout: telemetry stack on the left, model image top-right, battery bar bottom-right.
  Model image: /IMAGES/<ModelName>.png (falls back to /WIDGETS/StacyDash/default.png)
]]

local appName = "StacyDash"

local function rgb(r, g, b)
    return lcd.RGB(r, g, b)
end

local COLOR_WHITE = WHITE or rgb(0xFF, 0xFF, 0xFF)
local COLOR_GREEN = rgb(0x00, 0xFF, 0x55)
local COLOR_BLUE = rgb(0x00, 0xB6, 0xFF)
local COLOR_RED = rgb(0xFF, 0x30, 0x30)
local COLOR_GRAY = rgb(0x5D, 0x67, 0x74)
local COLOR_TOPBAR_BG = rgb(0x24, 0x24, 0x24)
-- Pre-computed colors (avoid per-frame lcd.RGB allocations)
local COLOR_BAR_RED    = COLOR_RED        -- same as COLOR_RED, avoids duplicate rgb()
local COLOR_BAR_ORANGE = rgb(0xFF, 0xD0, 0x40)
local COLOR_BAR_GREEN  = rgb(0x40, 0xD8, 0x60)
local COLOR_BATT_BORDER = rgb(0x9A, 0x9A, 0x9A)
local COLOR_BATT_DARK   = rgb(0x22, 0x22, 0x22)
local COLOR_BATT_TOP_BORDER = rgb(0xD5, 0xDD, 0xE9)
local COLOR_BATT_TOP_INNER  = rgb(0x0B, 0x16, 0x21)

local function normalizeTextColor(c)
    if c == nil then return COLOR_WHITE end
    local n = tonumber(c)
    if n ~= nil and n == 0 then
        return COLOR_WHITE
    end
    return c
end

-- Convert 1-based CHOICE value to 0-based index.
local function choiceIndex(v, maxIndex)
    local n = tonumber(v) or 0
    n = n - 1
    if n < 0 then n = 0 end
    if maxIndex ~= nil and n > maxIndex then n = maxIndex end
    return n
end

local MODEL_FALLBACKS = {
    "/WIDGETS/StacyDash/default.png", -- user-provided default
    "/IMAGES/default.png",
    "/IMAGES/defaultmodel.png"
}

local FLIGHTS_COUNT_PATH = "/flights-count.csv"
local TOP_BAR_H_800 = 56
local TOP_BAR_RIGHT_PAD_800 = 8
local TOP_BAR_MODEL_GAP_800 = 14
local TOP_BAR_GROUP_START_800 = 320
local TOP_BAR_GAP_TO_RADIO_800 = 12
local TOP_BAR_RADIO_H_800 = 38
local LEFT_STACK_PAD = 12
local METRIC_VALUE_X_RATIO = 0.90
local TOPBAR_MIN_DUR_DEFAULT = 60

local function safeObjField(obj, key)
    if obj == nil then return nil end
    local t = type(obj)
    if t == "table" then
        return obj[key]  -- plain table: direct index, no closure needed
    end
    if t ~= "userdata" then return nil end
    local ok, value = pcall(function() return obj[key] end)
    if not ok then return nil end
    return value
end

local function safeFieldInfo(src)
    if src == nil or src == 0 then return nil end
    local ok, info = pcall(getFieldInfo, src)
    if not ok then return nil end
    return info
end

local function findSourceId(candidates)
    for _, name in ipairs(candidates) do
        local fi = safeFieldInfo(name)
        local id = safeObjField(fi, "id")
        if id then return id end
    end
    return 0
end

local function defaultSgSwitchId()
    if not getVersion then return 132 end
    local ok, _, _, maj, minor = pcall(getVersion)
    if not ok or maj == nil or minor == nil then return 132 end
    local ver = string.format("%d.%d", maj, minor)
    local map = { ["2.10"] = 132, ["2.11"] = 132, ["2.12"] = 132 }
    return map[ver] or 132
end

local DEFAULT_CURR_SOURCE = findSourceId({"Amp", "AMP", "amp"})
local DEFAULT_VOLT_SOURCE = findSourceId({"Volt", "VOLT", "volt"})
local DEFAULT_CELLSRC_SOURCE = findSourceId({"Cel#", "CEL#", "cel#", "Cells"})
local DEFAULT_ESCTEMP_SOURCE = findSourceId({"Temp", "TEMP", "temp"})
local DEFAULT_BEC_SOURCE = findSourceId({"BEC", "bec"})
local DEFAULT_RPM_SOURCE = findSourceId({"RPM", "rpm"})
local DEFAULT_TRPM_SOURCE = findSourceId({"TRPM", "trpm", "TailRPM"})
local DEFAULT_PERCENT_SOURCE = findSourceId({"Bat%", "BAT%", "bat%"})
local DEFAULT_MAH_SOURCE = findSourceId({"Capa", "CAPA", "capa"})
local DEFAULT_GOV_SOURCE = findSourceId({"Gov", "GOV", "gov"})
local DEFAULT_SG_SWITCH = findSourceId({"SG", "sg"})
local DEFAULT_ACCX_SOURCE = findSourceId({"AccX", "ACCX", "accx"})
local DEFAULT_ACCZ_SOURCE = findSourceId({"AccZ", "ACCZ", "accz"})
local DEFAULT_TOP_ARM_SOURCE = findSourceId({"SG", "sg"})
if DEFAULT_SG_SWITCH == 0 then
    DEFAULT_SG_SWITCH = defaultSgSwitchId()
end
if DEFAULT_TOP_ARM_SOURCE == 0 then
    DEFAULT_TOP_ARM_SOURCE = DEFAULT_SG_SWITCH
end

local TOPBAR_VALUE_LABEL = "Status"
local CH5_ARM_SPLIT = 0

-- Widget options (user-selectable telemetry sources)
local options = {
    { "Mode",     CHOICE, 0, { "Electric", "Nitro" } }, -- 0=Electric, 1=Nitro
    -- Electric sources
    { "Curr",     SOURCE, DEFAULT_CURR_SOURCE },            -- Battery current (A)
    { "Volt",     SOURCE, DEFAULT_VOLT_SOURCE },            -- Pack voltage (V)
    { "Cells",    VALUE, 0, 0, 14 },      -- Manual cell count; 0 = use telemetry
    { "CellSrc",  SOURCE, DEFAULT_CELLSRC_SOURCE },            -- Telemetry cell-count sensor
    { "ESCtemp",  SOURCE, DEFAULT_ESCTEMP_SOURCE },            -- ESC temperature (°C)
    { "BECvolt",  SOURCE, DEFAULT_BEC_SOURCE },            -- BEC output voltage (V)
    { "RPM",      SOURCE, DEFAULT_RPM_SOURCE },            -- Main rotor RPM
    { "TailRPM",  SOURCE, DEFAULT_TRPM_SOURCE },            -- Tail rotor RPM
    { "Percent",  SOURCE, DEFAULT_PERCENT_SOURCE },            -- Battery percentage (0-100)
    { "mAh",      SOURCE, DEFAULT_MAH_SOURCE },            -- mAh consumed
    { "Reserve",  VALUE, 20, 0, 50 },     -- Reserve percent to subtract from usable
    { "BattVoice", BOOL, 0 },             -- Electric battery voice alerts on/off
    -- Nitro sources
    { "RxBatt",   SOURCE, 0 },            -- Receiver battery voltage (2S)
    { "AccZ",     SOURCE, DEFAULT_ACCZ_SOURCE }, -- Accel Z telemetry source
    { "AccX",     SOURCE, DEFAULT_ACCX_SOURCE }, -- Accel X telemetry source
    { "GovState", SOURCE, DEFAULT_GOV_SOURCE },            -- Governor state / throttle mode
    -- Top bar sources
    { "TopArmSw", SOURCE, DEFAULT_TOP_ARM_SOURCE },  -- Flights arm switch
    { "Min. Flight Time (sec)", VALUE, TOPBAR_MIN_DUR_DEFAULT, -30, 120 }, -- Timer1 threshold sec for flight count
    { "TopArmInv", BOOL, 0 },                    -- 0=arm when switch<0, 1=arm when switch>0
    { "TopUseTel", BOOL, 0 },                    -- Flights uses telemetry
    { "TextColor", COLOR, COLOR_WHITE },  -- User-selected text color
    { "TopBarPos", BOOL, 1 },                    -- 1=keep current topbar content position, 0=nudge down
    { "LblShadow", BOOL, 0 },                    -- 1=shadow left telemetry labels
    { "TopCPU",   BOOL, 1 },                     -- 1=show CPU in top bar, 0=hide and reflow
    { "TxBatType", CHOICE, 0, { "LiPo", "Li-Ion" } }, -- 0=LiPo 2S (6.6-8.4V), 1=Li-Ion 2S (6.0-8.4V)
    { "ValStyle", CHOICE, 0, { "Both Mid", "Big Val", "Big Lbl", "Small Lbl" } }, -- Label/value font emphasis
}

-- Simple helpers --------------------------------------------------------------
local function safeGetValue(src)
    if not src or src == 0 then return nil end
    local ok, v = pcall(getValue, src)
    if not ok then return nil end
    if type(v) == "table" then
        v = v.value
    end
    if v == nil then return nil end
    return tonumber(v)  -- ensure numeric; non-numbers become nil (crash-safe)
end

local function toChannelPercent(raw)
    local n = tonumber(raw)
    if n == nil then return nil end
    local a = math.abs(n)
    if a <= 100 then
        return n
    end
    if a <= 1024 then
        return (n * 100) / 1024
    end
    return n
end

-- Pre-built channel candidate tables (avoid per-frame table allocation)
local channelCandidates = {}
for i = 1, 16 do
    channelCandidates[i] = {
        "ch" .. tostring(i), "CH" .. tostring(i),
        string.format("ch%02d", i), string.format("CH%02d", i),
        "ch" .. tostring(i) .. "%", "CH" .. tostring(i) .. "%",
    }
end

local function readChannelPercent(ch)
    local n = math.floor(tonumber(ch) or 0)
    if n < 1 or n > 16 then return nil end
    for _, src in ipairs(channelCandidates[n]) do
        local fi = safeFieldInfo(src)
        local hasField = (safeObjField(fi, "id") ~= nil)
        local v = safeGetValue(src)
        if v ~= nil then
            -- Some invalid source strings resolve to 0; only accept 0 when the source exists.
            local vn = tonumber(v)
            if hasField or (vn ~= nil and vn ~= 0) then
                local p = toChannelPercent(v)
                if p ~= nil then
                    return p
                end
            end
        end
    end
    return nil
end

local function readChannel5Percent()
    return readChannelPercent(5)
end

local function readChannel6Percent()
    return readChannelPercent(6)
end

local function isCh5Disarmed(ch5Percent)
    local p = tonumber(ch5Percent)
    if p == nil then return false end
    return p <= CH5_ARM_SPLIT
end

local function statusFromCh5(ch5Percent)
    local p = tonumber(ch5Percent)
    if p == nil then return false end
    return p > CH5_ARM_SPLIT
end

local function isVoltageUnit(unit)
    if unit == 1 then return true end
    if type(unit) == "string" then
        local u = string.upper(unit)
        if u == "V" or u == "VOLT" or u == "VOLTS" then
            return true
        end
    end
    return false
end

local function voltageTextExact(v, suffix)
    if v == nil then return "--" end
    local n = tonumber(v)
    if n == nil then return "--" end
    return string.format("%.2f", n) .. (suffix or "V")
end

local function calculateAdjustedPercent(actual, threshold)
    if not actual or actual <= 0 then return 0 end
    if threshold >= 100 then return 0 end
    local usable = 100 - threshold
    local adj = ((actual - threshold) / usable) * 100
    if adj < 0 then adj = 0 end
    if adj > 100 then adj = 100 end
    return adj
end

local function getBarColor(percent)
    if percent < 30 then
        return COLOR_BAR_RED
    elseif percent < 70 then
        return COLOR_BAR_ORANGE
    else
        return COLOR_BAR_GREEN
    end
end

local COLOR_WARN  = COLOR_BAR_ORANGE       -- alias, avoids duplicate rgb()
local COLOR_CRIT  = COLOR_RED              -- alias, avoids duplicate rgb()

-- ESC temperature color: normal ≤100°C, orange 101-120°C, red >120°C
local function escTempColor(val)
    if val == nil then return nil end
    if val > 120 then return COLOR_CRIT end
    if val > 100 then return COLOR_WARN end
    return nil
end

-- BEC voltage color: red < 4.8V, yellow 4.8-5.1V, normal above
local function becColor(val)
    if val == nil then return nil end
    if val < 4.8 then return COLOR_CRIT end
    if val < 5.1 then return COLOR_WARN end
    return nil
end

local function percentFromVoltage(volts, cells, isLiHV)
    if not volts or volts <= 0 or not cells or cells <= 0 then return 0 end
    local perCell = volts / cells
    local minV = 3.3
    local maxV = isLiHV and 4.35 or 4.2
    local pct = (perCell - minV) / (maxV - minV) * 100
    if pct < 0 then pct = 0 end
    if pct > 100 then pct = 100 end
    return pct
end

local BATTERY_ALERT_UNIT_PERCENT = UNIT_PERCENT or 13
local BATTERY_ALERT_COOLDOWN_TICKS = 220
local BATTERY_ALERT_HAPTIC_THRESHOLD = 10
local LINKLOSS_HAPTIC_COOLDOWN_TICKS = 90

local function playBatteryRemainingAlert(level)
    local n = tonumber(level)
    if n == nil then return end

    -- Optional custom voice files (e.g. "50 battery remaining") if user provides them.
    if playFile then
        local customPath = string.format("/WIDGETS/StacyDash/%d_battery_remaining.wav", n)
        local f = io.open(customPath, "r")
        if f then
            pcall(io.close, f)
            pcall(playFile, customPath)
            return
        end
    end

    if playNumber then
        pcall(playNumber, n, BATTERY_ALERT_UNIT_PERCENT, 0)
    end
end

local function playBatteryHaptic()
    if not playHaptic then return end
    local modeNow = PLAY_NOW or 0
    pcall(playHaptic, 100, 0, modeNow)
end

local function resetBatteryAlertState(wgt)
    if not wgt then return end
    wgt.battAlert50Played = false
    wgt.battAlert10Played = false
    wgt.battAlert0Played = false
    wgt.battAlert5HapticPlayed = false
    wgt.battAlertNextTick = 0
end

local function updateBatteryAlertState(wgt, percent, hasData, voiceEnabled)
    if not wgt or not hasData then return end
    local p = tonumber(percent)
    if p == nil then return end
    if p < 0 then p = 0 end
    if p > 100 then p = 100 end

    local prev = tonumber(wgt.battAlertPrevPct)
    if prev == nil then
        wgt.battAlertPrevPct = p
        return
    end

    -- Battery was likely swapped/recharged; re-arm all notifications.
    if (p >= 95 and prev < 80) or ((p - prev) >= 25 and p >= 60) then
        resetBatteryAlertState(wgt)
    end

    local now = getTime and getTime() or 0
    local nextTick = tonumber(wgt.battAlertNextTick) or 0
    if now >= nextTick then
        local played = false

        if (not wgt.battAlert0Played) and prev > 0 and p <= 0 then
            if voiceEnabled then playBatteryRemainingAlert(0) end
            wgt.battAlert0Played = true
            wgt.battAlert10Played = true
            wgt.battAlert50Played = true
            played = true
        elseif (not wgt.battAlert10Played) and prev > 10 and p <= 10 then
            if voiceEnabled then playBatteryRemainingAlert(10) end
            wgt.battAlert10Played = true
            wgt.battAlert50Played = true
            played = true
        elseif (not wgt.battAlert50Played) and prev > 50 and p <= 50 then
            if voiceEnabled then playBatteryRemainingAlert(50) end
            wgt.battAlert50Played = true
            played = true
        end

        if played then
            wgt.battAlertNextTick = now + BATTERY_ALERT_COOLDOWN_TICKS
        end
    end

    if (not wgt.battAlert5HapticPlayed) and prev > BATTERY_ALERT_HAPTIC_THRESHOLD and p <= BATTERY_ALERT_HAPTIC_THRESHOLD then
        playBatteryHaptic()
        wgt.battAlert5HapticPlayed = true
    end

    wgt.battAlertPrevPct = p
end

local bitmapCache = {}
local bitmapCacheKeys = {}
local BITMAP_CACHE_MAX = 10

local function bitmapCacheKey(path, w, h)
    local ww = tonumber(w) or 0
    local hh = tonumber(h) or 0
    return path .. "@" .. ww .. "x" .. hh
end

local function bitmapCacheEvict()
    while #bitmapCacheKeys > BITMAP_CACHE_MAX do
        local oldest = table.remove(bitmapCacheKeys, 1)
        bitmapCache[oldest] = nil
    end
end

local function tryLoadBitmap(path, w, h)
    if type(path) ~= "string" or path == "" then return nil end
    local key = bitmapCacheKey(path, w, h)
    local cached = bitmapCache[key]
    if cached then
        return cached
    end

    local f = io.open(path, "r")
    if not f then
        return nil
    end
    pcall(io.close, f)

    local okOpen, img = pcall(Bitmap.open, path)
    if not okOpen or not img then
        return nil
    end

    if w and h and w > 0 and h > 0 then
        local okResize, resized = pcall(Bitmap.resize, img, w, h)
        if okResize and resized then
            img = resized
        end
    end

    bitmapCache[key] = img
    bitmapCacheKeys[#bitmapCacheKeys + 1] = key
    bitmapCacheEvict()
    return img
end

local function sanitizeModelNameForFile(name)
    if type(name) ~= "string" then return "" end
    local out = string.gsub(name, "[\\/:*?\"<>|]", "_")
    out = string.gsub(out, "^%s*(.-)%s*$", "%1")
    return out
end

-- Shared formatters (module-level to avoid per-frame closure allocation)
local function fmtVal(val, fmtStr)
    if val == nil then return "--" end
    return string.format(fmtStr, val)
end

local function fmtAcc(val)
    local n = tonumber(val)
    if n == nil then return "--" end
    return string.format("%.2f", n)
end

local function clamp(v, lo, hi)
    if v < lo then return lo end
    if v > hi then return hi end
    return v
end

local function trimText(s)
    if type(s) ~= "string" then return "" end
    return (string.gsub(s, "^%s*(.-)%s*$", "%1"))
end

local function safeGetNamedValue(name)
    if type(name) ~= "string" or name == "" then return nil end
    local ok, v = pcall(getValue, name)
    if not ok then return nil end
    if type(v) == "table" then
        v = safeObjField(v, "value")
    end
    return tonumber(v)
end

local function formatSourceValue(src)
    if not src or src == 0 then return "--" end
    local ok, raw = pcall(getValue, src)
    if not ok or raw == nil then return "--" end

    if type(raw) == "table" then
        local value = safeObjField(raw, "value")
        local unit = safeObjField(raw, "unit")
        local prec = safeObjField(raw, "prec")
        if prec == nil then prec = safeObjField(raw, "precision") end
        if type(value) == "number" then
            local dp = clamp(tonumber(prec) or 0, 0, 2)
            local txt = string.format("%." .. tostring(dp) .. "f", value)
            if type(unit) == "string" and #unit > 0 then
                txt = txt .. unit
            end
            return txt
        end
        if value ~= nil then return tostring(value) end
        return "--"
    end

    if type(raw) == "number" then
        local a = math.abs(raw)
        if a >= 100 then return string.format("%.0f", raw) end
        if a >= 10 then return string.format("%.1f", raw) end
        return string.format("%.2f", raw)
    end

    return tostring(raw)
end

local function roundNearestInt(n)
    if n >= 0 then
        return math.floor(n + 0.5)
    end
    return math.ceil(n - 0.5)
end

local function formatTopValue(src)
    if not src or src == 0 then return "--" end
    local ok, raw = pcall(getValue, src)
    if not ok then return "--" end
    if raw == nil then return "--" end

    if type(raw) == "table" then
        local value = safeObjField(raw, "value")
        local unit = safeObjField(raw, "unit")
        if type(value) == "number" then
            if isVoltageUnit(unit) then
                local unitSuffix = (type(unit) == "string" and #unit > 0) and unit or "V"
                return voltageTextExact(value, unitSuffix)
            end
            local txt = tostring(roundNearestInt(value))
            if type(unit) == "string" and #unit > 0 then
                txt = txt .. unit
            end
            return txt
        end
        if value ~= nil then return tostring(value) end
        return "--"
    end

    if type(raw) == "number" then
        local fi = safeFieldInfo(src)
        local fiUnit = safeObjField(fi, "unit")
        if isVoltageUnit(fiUnit) then
            return voltageTextExact(raw, "V")
        end
        return tostring(roundNearestInt(raw))
    end
    return tostring(raw)
end

local function timerValueSeconds(timerIdx)
    local idx = clamp(math.floor((tonumber(timerIdx) or 1) - 1), 0, 2)
    local ok, timer = pcall(model.getTimer, idx)
    if not ok then return nil end
    local value = safeObjField(timer, "value")
    if value == nil then value = tonumber(timer) end
    return tonumber(value)
end

local function formatTimerText(timerIdx)
    local value = timerValueSeconds(timerIdx)
    if value == nil then return "--:--" end

    local sign = ""
    if value < 0 then
        sign = "-"
        value = -value
    end
    local h = math.floor(value / 3600)
    local m = math.floor((value % 3600) / 60)
    local s = math.floor(value % 60)
    if h > 0 then
        return string.format("%s%02d:%02d:%02d", sign, h, m, s)
    end
    return string.format("%s%02d:%02d", sign, m, s)
end

local function readFileChunk(file, chunkSize)
    local ok, data = pcall(io.read, file, chunkSize)
    if not ok then return nil end
    return data
end

local function writeFileChunk(file, data)
    local ok = pcall(io.write, file, data)
    return ok
end

local READ_ALL_MAX_BYTES = 4096  -- safety cap: prevent OOM on corrupted files

local function readAllText(path)
    local file = io.open(path, "r")
    if not file then return nil end
    local parts = {}
    local total = 0
    -- pcall protects file handle from leaking if an OOM error occurs
    local ok, _ = pcall(function()
        while true do
            local chunk = readFileChunk(file, 96)
            if not chunk or #chunk == 0 then break end
            total = total + #chunk
            if total > READ_ALL_MAX_BYTES then break end
            parts[#parts + 1] = chunk
            if #chunk < 96 then break end
        end
    end)
    pcall(io.close, file)
    if not ok then return nil end
    return table.concat(parts)
end

local function writeAllText(path, text)
    local data = text or ""
    -- Write to temp file first so a failed write doesn't destroy existing data
    local tmpPath = path .. ".tmp"
    local file = io.open(tmpPath, "w")
    if file then
        local ok = writeFileChunk(file, data)
        pcall(io.close, file)
        if ok then
            local rok = pcall(os.rename, tmpPath, path)
            if rok then return true end
        end
    end
    -- Fallback: direct write if temp/rename unavailable
    file = io.open(path, "w")
    if not file then return false end
    local ok = writeFileChunk(file, data)
    pcall(io.close, file)
    return ok
end

local flightCountCache = nil

local function modelKey(name)
    if type(name) ~= "string" or name == "" then
        return "__default__"
    end
    name = trimText(name)
    if name == "" then return "__default__" end
    return (string.gsub(name, ",", " "))
end

local FLIGHT_CACHE_MAX_ENTRIES = 200  -- safety cap: bound memory from corrupted CSV

local function getFlightCountCache()
    if flightCountCache ~= nil then return flightCountCache end
    flightCountCache = {}
    local txt = readAllText(FLIGHTS_COUNT_PATH)
    if not txt or txt == "" then return flightCountCache end

    local entries = 0
    for line in string.gmatch(txt, "[^\r\n]+") do
        local n = trimText(line)
        if n ~= "" and string.sub(n, 1, 1) ~= "#" then
            local modelName, countText = string.match(n, "^%s*([^,]+)%s*,%s*([^,]+)")
            if modelName and countText and modelName ~= "model_name" then
                flightCountCache[trimText(modelName)] = tonumber(countText) or 0
                entries = entries + 1
                if entries >= FLIGHT_CACHE_MAX_ENTRIES then break end
            end
        end
    end
    return flightCountCache
end

local function saveFlightCountCache()
    local cache = flightCountCache
    if not cache then return end
    local keys = {}
    for k, _ in pairs(cache) do keys[#keys + 1] = k end
    table.sort(keys)

    local out = { "model_name,flight_count\n# api_ver=1\n" }
    for _, key in ipairs(keys) do
        out[#out + 1] = string.format("%s,%d\n", key, tonumber(cache[key]) or 0)
    end
    writeAllText(FLIGHTS_COUNT_PATH, table.concat(out))
end

local function txPercentFromVolts(volts, isLiIon)
    if isLiIon then
        -- Li-Ion 2S: 6.0V (cutoff) to 8.4V (full)
        return clamp(((volts - 6.0) / 2.4) * 100, 0, 100)
    end
    -- LiPo 2S: 6.6V (cutoff) to 8.4V (full)
    return clamp(((volts - 6.6) / 1.8) * 100, 0, 100)
end

local function signalPercent(signalRaw)
    local v = tonumber(signalRaw)
    if not v then return nil end
    local pct
    if v < 0 then
        pct = ((v + 120) / 80) * 100
    elseif v <= 1 then
        pct = v * 100
    elseif v <= 100 then
        pct = v
    elseif v <= 255 then
        pct = (v / 255) * 100
    else
        pct = 100
    end
    return clamp(pct, 0, 100)
end

local function ensureTopbar(wgt)
    if wgt.topbar then return wgt.topbar end
    wgt.topbar = {
        modelName = "Model",
        valueLabel = "Value",
        valueText = "--",
        valueColor = COLOR_WHITE,
        timerLabel = "Timer1",
        timerText = "--:--",
        flights = 0,
        signalBars = 0,
        txPct = nil,
        txVolts = nil,
        cpuUsage = nil,
        linkAvailable = false,
        statusArmed = false,
        ch5Percent = nil,
        linkLossHapticLatched = false,
        nextLinkLossHapticTick = 0,
        switchOn = false,
        telemetryAvailable = false,
        motorOn = false,
        groundOnSwitch = false,
        minFlightDur = TOPBAR_MIN_DUR_DEFAULT,
        flightModel = "__default__",
        timerThresholdArmed = nil,
        lastTimer1Seconds = nil,
    }
    return wgt.topbar
end

local function refreshTopbarData(wgt)
    local top = ensureTopbar(wgt)
    local opts = wgt.options

    local okInfo, info = pcall(model.getInfo)
    if not okInfo then info = nil end
    local modelName = safeObjField(info, "name")
    if type(modelName) ~= "string" or #modelName == 0 then modelName = "Model" end
    top.modelName = modelName

    local thisModel = modelKey(modelName)
    if top.flightModel ~= thisModel then
        top.flightModel = thisModel
        top.flights = getFlightCountCache()[thisModel] or 0
        top.timerThresholdArmed = nil
        top.lastTimer1Seconds = nil
        top.linkLossHapticLatched = false
        top.nextLinkLossHapticTick = 0
    end

    top.valueLabel = TOPBAR_VALUE_LABEL
    top.valueText = "DISARMED"
    top.valueColor = COLOR_RED

    top.timerLabel = "Timer1"
    top.timerText = formatTimerText(1)

    local rssiNow = nil
    if getRSSI then
        local ok, rssi = pcall(getRSSI)
        if ok then rssiNow = tonumber(rssi) end
    end
    local sig = rssiNow
    if sig == nil then
        sig = safeGetNamedValue("RSSI")
    end
    local sigPct = signalPercent(sig)
    if sigPct == nil then
        top.signalBars = 0
    else
        top.signalBars = clamp(math.floor((sigPct + 19) / 20), 0, 5)
    end
    top.linkAvailable = (sigPct ~= nil and sigPct > 0) or ((rssiNow or 0) > 0)

    local txVolts = safeGetNamedValue("tx-voltage")
    if txVolts and txVolts > 100 then txVolts = txVolts / 1000 end
    if txVolts and txVolts > 0 then
        top.txVolts = txVolts
        local txIsLiIon = (choiceIndex(opts.TxBatType, 1) == 1)
        top.txPct = txPercentFromVolts(txVolts, txIsLiIon)
    else
        top.txVolts = nil
        top.txPct = nil
    end

    local showCpu = (opts.TopCPU == nil) or (opts.TopCPU == 1) or (opts.TopCPU == true)
    if showCpu and getUsage then
        local ok, usage = pcall(getUsage)
        local cpuNow = ok and tonumber(usage) or nil
        if cpuNow ~= nil then
            top.cpuUsage = clamp(roundNearestInt(cpuNow), 0, 100)
        else
            top.cpuUsage = nil
        end
    else
        top.cpuUsage = nil
    end

    local minFlightDur = tonumber(opts["Min. Flight Time (sec)"] or opts.TopMinDur) or TOPBAR_MIN_DUR_DEFAULT
    local groundOnSwitch = false
    if minFlightDur < 0 then
        minFlightDur = math.abs(minFlightDur)
        groundOnSwitch = true
    end
    if minFlightDur < 1 then minFlightDur = 1 end
    top.minFlightDur = minFlightDur
    top.groundOnSwitch = groundOnSwitch

    local armRaw = safeGetValue(opts.TopArmSw)
    local nonInvertArm = (opts.TopArmInv == 1 or opts.TopArmInv == true)
    if type(armRaw) == "boolean" then
        top.switchOn = armRaw
    else
        local armVal = tonumber(armRaw) or 0
        if nonInvertArm then
            top.switchOn = armVal > 0
        else
            top.switchOn = armVal < 0
        end
    end

    local useTelemetry = (opts.TopUseTel == 1 or opts.TopUseTel == true)
    if useTelemetry then
        top.telemetryAvailable = top.linkAvailable
    else
        top.telemetryAvailable = true
    end

    local ch5Percent = readChannel5Percent()
    top.ch5Percent = ch5Percent
    local statusArmed = statusFromCh5(ch5Percent)
    top.statusArmed = (statusArmed == true)
    if top.statusArmed then
        top.valueText = "ARMED"
        top.valueColor = COLOR_GREEN
    else
        top.valueText = "DISARMED"
        top.valueColor = COLOR_RED
    end

    local ch5IsDisarmed = isCh5Disarmed(ch5Percent)
    if top.linkLossHapticLatched and ch5IsDisarmed then
        top.linkLossHapticLatched = false
        top.nextLinkLossHapticTick = 0
    end
    if (not top.linkAvailable) and top.statusArmed and (not ch5IsDisarmed) then
        top.linkLossHapticLatched = true
    end
    if top.linkLossHapticLatched and (not ch5IsDisarmed) then
        local nowTicks = getTime and getTime() or 0
        local nextTick = tonumber(top.nextLinkLossHapticTick) or 0
        if nowTicks >= nextTick then
            playBatteryHaptic()
            top.nextLinkLossHapticTick = nowTicks + LINKLOSS_HAPTIC_COOLDOWN_TICKS
        end
    end

    -- FlightsRCVR heli logic: motor activity follows arm switch state.
    top.motorOn = top.switchOn

    -- Flight counting is driven exclusively by Timer1 threshold crossing:
    -- each transition from below threshold to >= threshold increments once.
    local timer1Seconds = timerValueSeconds(1)
    if timer1Seconds ~= nil then
        if top.timerThresholdArmed == nil then
            top.timerThresholdArmed = (timer1Seconds < minFlightDur)
        end
        if timer1Seconds < minFlightDur then
            top.timerThresholdArmed = true
        elseif top.timerThresholdArmed then
            top.timerThresholdArmed = false
            local cache = getFlightCountCache()
            local newCount = (cache[thisModel] or top.flights or 0) + 1
            cache[thisModel] = newCount
            top.flights = newCount
            saveFlightCountCache()
        end
        top.lastTimer1Seconds = timer1Seconds
    end
end

local function topbarHeight(zone)
    local scaleY = zone.h / 480
    local h = math.floor((TOP_BAR_H_800 * scaleY) + 0.5)
    return clamp(h, 44, 64)
end

local function safeTextWidth(text, flags)
    local s = tostring(text or "")
    if lcd and lcd.getTextSize then
        local ok, w = pcall(lcd.getTextSize, s, flags or 0)
        if ok and type(w) == "number" then
            return w
        end
    end
    return #s * 8
end

local function drawTopBarBg(x, y, w, h)
    lcd.drawFilledRectangle(x, y, w, h, COLOR_TOPBAR_BG)
end

local function drawTopSlot(cx, y, h, label, value, labelColor, valueColor, valueFontOverride)
    local x = math.floor(cx + 0.5)
    local lblColor = normalizeTextColor(labelColor or COLOR_WHITE)
    local valColor = normalizeTextColor(valueColor or COLOR_WHITE)
    local labelY = y + math.floor(h * 0.26)
    local valueY = y + math.floor(h * 0.68)
    local valueFont = valueFontOverride
    if valueFont == nil then
        valueFont = (h < 48) and SMLSIZE or MIDSIZE
    end
    lcd.drawText(x, labelY, label or "", CENTER + VCENTER + SMLSIZE + lblColor)
    lcd.drawText(x, valueY, value or "--", CENTER + VCENTER + valueFont + valColor)
end

local function drawTopBatteryVertical(x, y, w, h, pct)
    local border = COLOR_BATT_TOP_BORDER
    local inner = COLOR_BATT_TOP_INNER
    local termW = math.max(4, math.floor(w * 0.44))
    local termH = math.max(2, math.floor(h * 0.12))
    local bodyY = y + termH
    local bodyH = h - termH

    lcd.drawFilledRectangle(x + math.floor((w - termW) / 2), y, termW, termH, border)
    lcd.drawFilledRectangle(x, bodyY, w, bodyH, border)
    lcd.drawFilledRectangle(x + 1, bodyY + 1, w - 2, bodyH - 2, inner)

    if pct then
        local clamped = clamp(pct, 0, 100)
        local fillH = math.floor((bodyH - 4) * clamped / 100)
        if fillH > 0 then
            local fillY = bodyY + bodyH - 2 - fillH
            lcd.drawFilledRectangle(x + 2, fillY, w - 4, fillH, getBarColor(clamped))
        end
    end

    if pct ~= nil then
        local pctVal = clamp(roundNearestInt(tonumber(pct) or 0), 0, 100)
        local txtX = x + math.floor(w / 2)
        local txtY = bodyY + math.floor(bodyH / 2)
        lcd.drawText(txtX, txtY, tostring(pctVal), CENTER + VCENTER + SMLSIZE + COLOR_WHITE)
    end
end

local function drawTopSignalBars(x, y, w, h, bars)
    local total = 5
    local gap = 2
    local barW = math.max(3, math.floor((w - (gap * (total - 1))) / total))
    local active = clamp(tonumber(bars) or 0, 0, total)
    for i = 1, total do
        local bh = math.max(3, math.floor((h * i) / total))
        local bx = x + (i - 1) * (barW + gap)
        local by = y + h - bh
        local color = (i <= active) and COLOR_GREEN or COLOR_GRAY
        lcd.drawFilledRectangle(bx, by, barW, bh, color)
    end
end

local function drawTopBar(wgt, zone)
    local top = ensureTopbar(wgt)
    local z = zone
    local scaleX = z.w / 800
    local scaleY = z.h / 480
    local h = topbarHeight(z)
    local topY = z.y
    local keepTopbarPos = true
    if wgt and wgt.options then
        local posOpt = wgt.options.TopBarPos
        keepTopbarPos = (posOpt == nil) or (posOpt == 1) or (posOpt == true)
    end
    if keepTopbarPos then
        drawTopBarBg(z.x, topY, z.w, h)
    end
    local topContentOffset = keepTopbarPos and 0 or clamp(math.floor((8 * scaleY) + 0.5), 4, 12)
    local contentTopY = topY + topContentOffset

    local rightPad = math.floor((TOP_BAR_RIGHT_PAD_800 * scaleX) + 0.5)
    local modelX = z.x + LEFT_STACK_PAD
    local modelLabel = "Model Name"
    local modelLabelFont = SMLSIZE
    local modelValueFont = SMLSIZE + BOLD
    local modelLabelY = contentTopY + math.floor(h * 0.18)
    local modelValueY = contentTopY + math.floor(h * 0.66)
    lcd.drawText(modelX, modelLabelY, modelLabel, modelLabelFont + VCENTER + COLOR_WHITE)
    lcd.drawText(modelX, modelValueY, top.modelName or "Model", modelValueFont + VCENTER + COLOR_GREEN)
    local modelW = safeTextWidth(modelLabel, modelLabelFont)
    local modelValueW = safeTextWidth(top.modelName or "Model", modelValueFont)
    if modelValueW > modelW then modelW = modelValueW end
    local modelGap = math.floor((TOP_BAR_MODEL_GAP_800 * scaleX) + 0.5)

    local radioH = math.floor((TOP_BAR_RADIO_H_800 * scaleX) + 0.5)
    local barsW = math.floor(42 * scaleX + 0.5)
    local barsH = math.floor(30 * scaleX + 0.5)
    local barsX = z.x + z.w - rightPad - barsW
    local barsY = contentTopY + math.floor((h - barsH) / 2)
    local battW = math.max(22, math.floor(36 * scaleX + 0.5))
    local battH = math.max(radioH, math.floor(43 * scaleX + 0.5))
    local battX = barsX - math.floor(10 * scaleX + 0.5) - battW
    local battY = contentTopY + math.floor((h - battH) / 2)

    drawTopBatteryVertical(battX, battY, battW, battH, top.txPct)
    drawTopSignalBars(barsX, barsY, barsW, barsH, top.signalBars)
    local radioLeft = battX
    local showCpu = true
    if wgt and wgt.options then
        local cpuOpt = wgt.options.TopCPU
        showCpu = (cpuOpt == nil) or (cpuOpt == 1) or (cpuOpt == true)
    end
    local cpuValue = showCpu and tonumber(top.cpuUsage) or nil
    if cpuValue ~= nil then
        local cpuLbl = "CPU"
        local cpuVal = tostring(clamp(roundNearestInt(cpuValue), 0, 100)) .. "%"
        local cpuLblFont = SMLSIZE
        local cpuValFont = SMLSIZE
        local cpuGap = math.max(19, math.floor(22 * scaleX + 0.5))
        local cpuRight = battX - cpuGap
        local cpuLblY = contentTopY + math.floor(h * 0.30)
        local cpuValY = contentTopY + math.floor(h * 0.66)
        local cpuReserveW = math.max(
            safeTextWidth(cpuLbl, cpuLblFont),
            safeTextWidth("100%", cpuValFont),
            math.floor(28 * scaleX + 0.5)
        )
        lcd.drawText(cpuRight, cpuLblY, cpuLbl, RIGHT + VCENTER + cpuLblFont + COLOR_WHITE)
        lcd.drawText(cpuRight, cpuValY, cpuVal, RIGHT + VCENTER + cpuValFont + COLOR_WHITE)
        radioLeft = cpuRight - cpuReserveW
    end
    local minGroupStart = modelX + modelW + modelGap
    local groupStart = z.x + math.floor((TOP_BAR_GROUP_START_800 * scaleX) + 0.5)
    if groupStart < minGroupStart then
        groupStart = minGroupStart
    end
    local groupGap = math.floor((TOP_BAR_GAP_TO_RADIO_800 * scaleX) + 0.5)
    if cpuValue ~= nil then
        groupGap = math.max(6, groupGap - math.floor(3 * scaleX + 0.5))
    end
    local groupEnd = radioLeft - groupGap
    if groupEnd < groupStart + 120 then
        groupStart = minGroupStart
    end
    local slotW = (groupEnd - groupStart) / 3
    if slotW < 52 then slotW = 52 end

    local valCx = groupStart + slotW * 0.5
    local timerCx = groupStart + slotW * 1.5
    local flightsBaseCx = groupStart + slotW * 2.5
    local flightsNudge = math.max(2, math.floor(5 * scaleX + 0.5))
    local flightsCx = flightsBaseCx + flightsNudge

    local statusValueFont = SMLSIZE
    drawTopSlot(valCx, contentTopY, h, top.valueLabel, top.valueText, COLOR_WHITE, top.valueColor or COLOR_WHITE, statusValueFont)
    local timerFont = (h < 52) and (SMLSIZE + BOLD) or MIDSIZE
    lcd.drawText(timerCx, contentTopY + math.floor(h * 0.52), top.timerText or "--:--", CENTER + VCENTER + timerFont + COLOR_WHITE)
    local flightsLabelY = contentTopY + math.floor(h * 0.22)
    local flightsValueY = contentTopY + math.floor(h * 0.68) + 1
    local flightsLabelFont = 0
    local flightsValueFont = (h < 48) and SMLSIZE or MIDSIZE
    lcd.drawText(flightsCx, flightsLabelY, "Flights:", CENTER + VCENTER + flightsLabelFont + COLOR_BLUE)
    lcd.drawText(flightsCx, flightsValueY, tostring(top.flights or 0), CENTER + VCENTER + flightsValueFont + COLOR_BLUE)

    local dotX = math.floor(flightsBaseCx - (slotW * 0.37))
    local dotRadius = math.max(3, math.floor(4 * scaleX + 0.5))
    local dotSpacing = math.max(8, math.floor(13 * scaleX + 0.5))
    local dotsH = (dotSpacing * 2) + (dotRadius * 2)
    local dotY = contentTopY + math.floor((h - dotsH) / 2) + dotRadius
    lcd.drawFilledCircle(dotX, dotY, dotRadius, top.telemetryAvailable and COLOR_GREEN or COLOR_GRAY)
    lcd.drawFilledCircle(dotX, dotY + dotSpacing, dotRadius, top.switchOn and COLOR_GREEN or COLOR_GRAY)
    lcd.drawFilledCircle(dotX, dotY + dotSpacing * 2, dotRadius, top.motorOn and COLOR_GREEN or COLOR_GRAY)
end

-- Model image handling --------------------------------------------------------
local function loadModelBitmap(wgt, targetW, targetH)
    if not wgt then return end
    if not targetW or not targetH or targetW <= 0 or targetH <= 0 then return end

    -- Use topbar's cached model name to avoid duplicate model.getInfo() per frame
    local top = wgt.topbar
    local name = top and top.modelName or nil
    if name == nil or name == "Model" or #name == 0 then
        name = "__default__"
    end

    -- Skip reload if nothing changed
    if wgt.modelName == name and wgt.modelImg and wgt.modelImgW == targetW and wgt.modelImgH == targetH then
        return
    end

    local previousImg = wgt.modelImg
    local candidates = {}
    if name ~= "__default__" then
        table.insert(candidates, "/IMAGES/" .. name .. ".png")
        local clean = sanitizeModelNameForFile(name)
        if clean ~= "" and clean ~= name then
            table.insert(candidates, "/IMAGES/" .. clean .. ".png")
        end
    end
    for _, path in ipairs(MODEL_FALLBACKS) do
        table.insert(candidates, path)
    end
    for _, path in ipairs(candidates) do
        local img = tryLoadBitmap(path, targetW, targetH)
        if img then
            wgt.modelImg = img
            wgt.modelName = name
            wgt.modelImgW = targetW
            wgt.modelImgH = targetH
            return
        end
    end

    -- Nothing found; keep previous image if we have one to avoid transient blank frames.
    wgt.modelImg = previousImg
    wgt.modelName = name
    wgt.modelImgW = targetW
    wgt.modelImgH = targetH
end

-- Widget life-cycle ----------------------------------------------------------
local function e_create(zone, opts)
    local wgt = {
        zone = zone,
        options = opts,
        isNitro = false,
        modelImg = nil,
        modelName = nil,
        modelImgW = 0,
        modelImgH = 0,
        textColor = normalizeTextColor(opts.TextColor),
        -- Telemetry state
        cells = opts.Cells or 0,
        current = 0,
        maxCurrent = 0,
        voltage = 0,
        cellVoltage = 0,
        minCellVoltage = nil,
        escTemp = 0,
        maxEscTemp = 0,
        becVolt = 0,
        minBecVolt = nil,
        rpm = 0,
        maxRpm = 0,
        tailRpm = 0,
        maxTailRpm = 0,
        capacity = 0,
        percent = 0,
        adjustedPercent = 0,
        barColor = COLOR_WHITE,
        battAlertPrevPct = nil,
        battAlert50Played = false,
        battAlert10Played = false,
        battAlert0Played = false,
        battAlert5HapticPlayed = false,
        battAlertNextTick = 0,
        isLiHV = false,
    }
    return wgt
end

local function e_update(wgt, opts)
    wgt.options = opts
    wgt.modelImg = nil
    wgt.textColor = normalizeTextColor(opts.TextColor or wgt.textColor)
    wgt.cells = opts.Cells or wgt.cells or 0
    resetBatteryAlertState(wgt)
    wgt.battAlertPrevPct = nil
end

-- Telemetry read -------------------------------------------------------------
local function e_readTelemetry(wgt)
    local configuredCells = wgt.options.Cells or 0
    local telemCells = safeGetValue(wgt.options.CellSrc)
    if configuredCells and configuredCells > 0 then
        wgt.cells = configuredCells
    elseif telemCells and telemCells >= 1 then
        wgt.cells = math.floor(telemCells + 0.5)
    else
        wgt.cells = 0
    end

    local curr = safeGetValue(wgt.options.Curr)
    if curr then
        wgt.current = curr
        if curr > (wgt.maxCurrent or 0) then wgt.maxCurrent = curr end
    end

    local volt = safeGetValue(wgt.options.Volt)
    if volt then
        wgt.voltage = volt
        if wgt.cells and wgt.cells > 0 then
            wgt.cellVoltage = volt / wgt.cells
            -- Auto-detect LiHV: latch true if per-cell voltage exceeds LiPo max
            if wgt.cellVoltage > 4.22 then
                wgt.isLiHV = true
            end
            if wgt.cellVoltage > 1.0 then
                if wgt.minCellVoltage == nil or wgt.cellVoltage < wgt.minCellVoltage then
                    wgt.minCellVoltage = wgt.cellVoltage
                end
            end
        else
            wgt.cellVoltage = nil
        end
    end

    local esc = safeGetValue(wgt.options.ESCtemp)
    if esc then
        wgt.escTemp = esc
        if esc > (wgt.maxEscTemp or 0) then wgt.maxEscTemp = esc end
    end

    local bec = safeGetValue(wgt.options.BECvolt)
    if bec then
        wgt.becVolt = bec
        if bec > 1.0 then  -- track min above noise floor (was >= 5, missed critical lows)
            if wgt.minBecVolt == nil or bec < wgt.minBecVolt then
                wgt.minBecVolt = bec
            end
        end
    end

    local rpm = safeGetValue(wgt.options.RPM)
    if rpm then
        wgt.rpm = rpm
        if rpm > (wgt.maxRpm or 0) then wgt.maxRpm = rpm end
    end

    local tail = safeGetValue(wgt.options.TailRPM)
    if tail then
        wgt.tailRpm = tail
        if tail > (wgt.maxTailRpm or 0) then wgt.maxTailRpm = tail end
    end

    wgt.hasBattData = false
    local hasPercentData = false

    local pct = safeGetValue(wgt.options.Percent)
    if pct ~= nil then
        wgt.percent = pct
        hasPercentData = true
        if pct > 0 then wgt.hasBattData = true end
    elseif volt and volt > 0 and wgt.cells and wgt.cells > 0 then
        wgt.percent = percentFromVoltage(volt, wgt.cells, wgt.isLiHV)
        hasPercentData = true
        wgt.hasBattData = true
    else
        wgt.percent = 0
    end

    local cap = safeGetValue(wgt.options.mAh)
    if cap then
        wgt.capacity = cap
        if cap > 0 then wgt.hasBattData = true end
    end

    wgt.adjustedPercent = calculateAdjustedPercent(wgt.percent, wgt.options.Reserve or 0)
    wgt.barColor = getBarColor(wgt.adjustedPercent)
    local voiceEnabled = (wgt.options.BattVoice == 1 or wgt.options.BattVoice == true)
    updateBatteryAlertState(wgt, wgt.adjustedPercent, hasPercentData, voiceEnabled)
end

-- Drawing helpers ------------------------------------------------------------

local function drawMetricRow(x, y, width, label, primary, secondary, labelColor, shadowLabels, valueColor, valStyle, secColor)
    labelColor = normalizeTextColor(labelColor or COLOR_WHITE)
    local valC = normalizeTextColor(valueColor or labelColor)
    local subC = secColor and normalizeTextColor(secColor) or labelColor
    local style = valStyle or 0
    -- 0 = Both Mid:   label MIDSIZE+BOLD, value MIDSIZE
    -- 1 = Big Val:    label SMLSIZE+BOLD, value MIDSIZE+BOLD
    -- 2 = Big Lbl:    label MIDSIZE+BOLD, value default (original)
    -- 3 = Small Lbl:  label SMLSIZE,      value MIDSIZE
    local labelSize, valSize, subValOff
    if style == 1 then
        labelSize = SMLSIZE + BOLD
        valSize   = MIDSIZE + BOLD
        subValOff = 34
    elseif style == 2 then
        labelSize = MIDSIZE + BOLD
        valSize   = 0
        subValOff = 21
    elseif style == 3 then
        labelSize = SMLSIZE
        valSize   = MIDSIZE
        subValOff = 34
    else
        labelSize = MIDSIZE + BOLD
        valSize   = MIDSIZE
        subValOff = 34
    end
    local labelFont = labelSize + labelColor
    if shadowLabels then
        labelFont = labelFont + SHADOWED
    end
    local valueFont = valSize + valC
    local subFont = 0 + subC

    local valX = x + math.floor(width * METRIC_VALUE_X_RATIO)
    lcd.drawText(x, y + 2, label, labelFont)
    if primary and secondary then
        lcd.drawText(valX, y - 1, primary, valueFont + RIGHT)
        lcd.drawText(valX, y + subValOff, secondary, subFont + RIGHT)
    elseif primary then
        lcd.drawText(valX, y + 12, primary, valueFont + RIGHT)
    end
end

local function drawTelemetryStack(wgt, area)
    local rows = 6
    local topNudge = 4
    local lineH = math.floor((area.h - topNudge) / rows)
    local y = area.y + topNudge
    local x = area.x
    local w = area.w
    local color = normalizeTextColor(wgt.textColor)
    local shadowLabels = (wgt.options and (wgt.options.LblShadow == 1 or wgt.options.LblShadow == true)) or false
    local vs = choiceIndex(wgt.options and wgt.options.ValStyle or 0, 3)

    drawMetricRow(x, y, w, "Current", fmtVal(wgt.current, "%.1fA"), "Max " .. fmtVal(wgt.maxCurrent, "%.1fA"), color, shadowLabels, nil, vs)
    y = y + lineH

    local cellPrimary = (wgt.cellVoltage and wgt.cellVoltage > 0)
        and voltageTextExact(wgt.cellVoltage, "V")
        or "--"
    local cellSecondary = wgt.minCellVoltage
        and ("Low " .. voltageTextExact(wgt.minCellVoltage, "V"))
        or "Low --"
    local cellSecColor = (wgt.minCellVoltage and wgt.minCellVoltage < 3.70) and COLOR_CRIT or nil
    drawMetricRow(x, y, w, "Cells", cellPrimary, cellSecondary, color, shadowLabels, nil, vs, cellSecColor)
    y = y + lineH

    drawMetricRow(x, y, w, "ESC Temp", fmtVal(wgt.escTemp, "%.0f°C"), "Max " .. fmtVal(wgt.maxEscTemp, "%.0f°C"), color, shadowLabels, escTempColor(wgt.escTemp), vs)
    y = y + lineH

    local becPrimary = (wgt.becVolt ~= nil) and voltageTextExact(wgt.becVolt, "V") or "--"
    local becSecondary = (wgt.minBecVolt ~= nil) and ("Low " .. voltageTextExact(wgt.minBecVolt, "V")) or "Low --"
    drawMetricRow(x, y, w, "BEC", becPrimary, becSecondary, color, shadowLabels, becColor(wgt.becVolt), vs)
    y = y + lineH

    drawMetricRow(x, y, w, "RPM", fmtVal(wgt.rpm, "%.0f"), "Max " .. fmtVal(wgt.maxRpm, "%.0f"), color, shadowLabels, nil, vs)
    y = y + lineH

    drawMetricRow(x, y, w, "Tail RPM", fmtVal(wgt.tailRpm, "%.0f"), "Max " .. fmtVal(wgt.maxTailRpm, "%.0f"), color, shadowLabels, nil, vs)
end

local function drawRoundedRect(x, y, w, h, r, color)
    local maxR = math.floor(math.min(w, h) / 2)
    if r > maxR then r = maxR end
    if r < 1 then r = 1 end
    lcd.drawFilledRectangle(x + r, y, w - r * 2, h, color)
    lcd.drawFilledRectangle(x, y + r, r, h - r * 2, color)
    lcd.drawFilledRectangle(x + w - r, y + r, r, h - r * 2, color)
    lcd.drawFilledCircle(x + r, y + r, r, color)
    lcd.drawFilledCircle(x + w - r - 1, y + r, r, color)
    lcd.drawFilledCircle(x + r, y + h - r - 1, r, color)
    lcd.drawFilledCircle(x + w - r - 1, y + h - r - 1, r, color)
end

local function drawBatteryBar(wgt, area)
    local x, y, w, h = area.x, area.y, area.w, area.h
    local pad = 10
    local capW = math.max(12, math.floor(h * 0.14))
    local capH = math.floor(h * 0.45)
    local battW = w - capW - pad * 2 - 2
    local battH = h - pad * 2
    local battX = x + pad
    local battY = y + pad
    local corner = math.min(10, math.floor(battH * 0.22))

    drawRoundedRect(battX, battY, battW, battH, corner, COLOR_BATT_BORDER)
    drawRoundedRect(battX + 3, battY + 3, battW - 6, battH - 6, corner - 1, COLOR_BATT_DARK)

    if wgt.hasBattData and wgt.adjustedPercent > 0 then
        local innerPad = 7
        local fillMax = battW - innerPad * 2
        local fillW = math.floor(fillMax * wgt.adjustedPercent / 100)
        if fillW > 0 then
            drawRoundedRect(battX + innerPad, battY + innerPad, fillW, battH - innerPad * 2, corner - 2, wgt.barColor)
        end
    end

    lcd.drawFilledRectangle(battX + battW + 2, battY + math.floor((battH - capH) / 2), capW, capH, COLOR_BATT_BORDER)

    local textColor = normalizeTextColor(wgt.textColor)
    local textFlags = CENTER + VCENTER + BOLD + SHADOWED
    local textFlagsSmall = CENTER + VCENTER
    local centerY = battY + battH / 2
    local pctText = wgt.hasBattData and string.format("%d%%", math.floor(wgt.adjustedPercent + 0.5)) or "--%"
    lcd.drawText(battX + battW / 2, centerY - 4, pctText, textFlags + MIDSIZE + textColor)

    local line2 = nil
    if wgt.hasBattData and wgt.voltage and wgt.voltage > 0 then
        line2 = voltageTextExact(wgt.voltage, "V")
    end
    if wgt.hasBattData and wgt.capacity and wgt.capacity > 0 then
        local mahText = string.format("%dmAh", math.floor(wgt.capacity + 0.5))
        if line2 then
            line2 = line2 .. "  " .. mahText
        else
            line2 = mahText
        end
    end
    if wgt.hasBattData and line2 then
        lcd.drawText(battX + battW / 2, centerY + 22, line2, textFlagsSmall + SMLSIZE + textColor)
    elseif not wgt.hasBattData then
        lcd.drawText(battX + battW / 2, centerY + 22, "NO DATA", textFlagsSmall + SMLSIZE + textColor)
    end
end

local function drawNitroRxPackBar(wgt, area)
    local x, y, w, h = area.x, area.y, area.w, area.h
    local pad = 10
    local capW = math.max(12, math.floor(h * 0.14))
    local capH = math.floor(h * 0.45)
    local battW = w - capW - pad * 2 - 2
    local battH = h - pad * 2
    local battX = x + pad
    local battY = y + pad
    local corner = math.min(10, math.floor(battH * 0.22))

    drawRoundedRect(battX, battY, battW, battH, corner, COLOR_BATT_BORDER)
    drawRoundedRect(battX + 3, battY + 3, battW - 6, battH - 6, corner - 1, COLOR_BATT_DARK)

    local hasRxData = (wgt.rxVoltage ~= nil and wgt.rxVoltage > 0)
    local rxPct = clamp(tonumber(wgt.percent) or 0, 0, 100)
    if hasRxData and rxPct > 0 then
        local innerPad = 7
        local fillMax = battW - innerPad * 2
        local fillW = math.floor(fillMax * rxPct / 100)
        if fillW > 0 then
            drawRoundedRect(
                battX + innerPad,
                battY + innerPad,
                fillW,
                battH - innerPad * 2,
                corner - 2,
                getBarColor(rxPct)
            )
        end
    end

    lcd.drawFilledRectangle(battX + battW + 2, battY + math.floor((battH - capH) / 2), capW, capH, COLOR_BATT_BORDER)

    local textColor = normalizeTextColor(wgt.textColor)
    local textFlags = CENTER + VCENTER
    local centerY = battY + battH / 2
    local summaryTextWide
    local summaryTextTight
    if hasRxData then
        local pctText = string.format("%d%%", math.floor(rxPct))
        local rxText = voltageTextExact(wgt.rxVoltage, "v")
        local cellText = (wgt.rxCellVoltage and wgt.rxCellVoltage > 0)
            and voltageTextExact(wgt.rxCellVoltage, "v")
            or "--v"
        summaryTextWide = pctText .. " / " .. rxText .. " / " .. cellText
        summaryTextTight = pctText .. "/" .. rxText .. "/" .. cellText
    else
        summaryTextWide = "--% / --v / --v"
        summaryTextTight = "--%/--v/--v"
    end

    local availableW = battW - 16
    local drawText = summaryTextWide
    local drawFont = 0
    if safeTextWidth(drawText, drawFont) > availableW then
        drawText = summaryTextTight
    end
    if safeTextWidth(drawText, drawFont) > availableW then
        drawFont = SMLSIZE
    end
    lcd.drawText(battX + battW / 2, centerY, drawText, textFlags + drawFont + textColor)
end

local function drawModelArea(wgt, area)
    loadModelBitmap(wgt, area.w, area.h)
    if wgt.modelImg then
        lcd.drawBitmap(wgt.modelImg, area.x, area.y)
    else
        lcd.drawRectangle(area.x, area.y, area.w, area.h, SOLID)
        local color = normalizeTextColor(wgt.textColor)
        lcd.drawText(area.x + area.w / 2, area.y + area.h / 2, "No model image", CENTER + VCENTER + SMLSIZE + color)
    end
end

-- EdgeTX lifecycle -----------------------------------------------------------
local function e_background(wgt)
    if not wgt then return end
    e_readTelemetry(wgt)
    refreshTopbarData(wgt)
end

local function e_refresh(wgt, event, touchState)
    if not wgt or not wgt.zone then return end
    e_readTelemetry(wgt)
    refreshTopbarData(wgt)
    local z = wgt.zone
    local topH = topbarHeight(z)
    drawTopBar(wgt, z)

    local contentY = z.y + topH + 6
    local contentH = z.h - topH - 10
    if contentH < 80 then return end

    local rightW = math.floor(z.w / 2)
    local rightX = z.x + z.w - rightW
    local pad = 10
    local gap = 8
    local usableH = contentH - (pad * 2) - gap
    local batteryH = math.floor(usableH * 0.25)
    local modelH = usableH - batteryH

    -- Reuse area tables stored on wgt to avoid per-frame allocation
    local la = wgt._leftArea
    if not la then la = {}; wgt._leftArea = la end
    la.x = z.x + LEFT_STACK_PAD; la.y = contentY + 2
    la.w = rightX - z.x - 18;    la.h = contentH - 4

    local ma = wgt._modelArea
    if not ma then ma = {}; wgt._modelArea = ma end
    ma.x = rightX + pad; ma.y = contentY + pad
    ma.w = rightW - pad * 2; ma.h = modelH

    local ba = wgt._battArea
    if not ba then ba = {}; wgt._battArea = ba end
    ba.x = rightX + pad; ba.y = contentY + pad + modelH + gap
    ba.w = rightW - pad * 2; ba.h = batteryH

    drawTelemetryStack(wgt, la)
    drawModelArea(wgt, ma)
    drawBatteryBar(wgt, ba)
end

-- Nitro helpers -------------------------------------------------------------
local function n_create(zone, opts)
    local wgt = {
        zone = zone,
        options = opts,
        isNitro = true,
        modelImg = nil,
        modelName = nil,
        modelImgW = 0,
        modelImgH = 0,
        textColor = normalizeTextColor(opts.TextColor),
        rxVoltage = nil,
        rxCellVoltage = nil,
        minRxVoltage = nil,
        accX = nil,
        maxAccX = nil,
        accZ = nil,
        maxAccZ = nil,
        ch6Percent = nil,
        rpm = 0, maxRpm = 0,
        tailRpm = 0, maxTailRpm = 0,
        percent = 0,
        govState = nil,
    }
    return wgt
end

local function n_update(wgt, opts)
    wgt.options = opts
    wgt.modelImg = nil
    wgt.textColor = normalizeTextColor(opts.TextColor or wgt.textColor)
end

local function n_readTelemetry(wgt)
    local rx = safeGetValue(wgt.options.RxBatt)
    if rx then
        wgt.rxVoltage = rx
        wgt.rxCellVoltage = rx / 2
        if rx > 1.0 then  -- track min above noise floor (was >= 5, missed critical lows)
            if wgt.minRxVoltage == nil or rx < wgt.minRxVoltage then
                wgt.minRxVoltage = rx
            end
        end
    else
        wgt.rxVoltage = nil
        wgt.rxCellVoltage = nil
    end

    local rpm = safeGetValue(wgt.options.RPM)
    if rpm then
        wgt.rpm = rpm
        if rpm > (wgt.maxRpm or 0) then wgt.maxRpm = rpm end
    end

    local tail = safeGetValue(wgt.options.TailRPM)
    if tail then
        wgt.tailRpm = tail
        if tail > (wgt.maxTailRpm or 0) then wgt.maxTailRpm = tail end
    end

    local gov = safeGetValue(wgt.options.GovState)
    if gov ~= nil then wgt.govState = gov end
    wgt.ch6Percent = readChannel6Percent()

    local accZ = safeGetValue(wgt.options.AccZ)
    local accZn = tonumber(accZ)
    if accZn ~= nil then
        wgt.accZ = accZn
        if wgt.maxAccZ == nil or accZn > wgt.maxAccZ then
            wgt.maxAccZ = accZn
        end
    end

    local accX = safeGetValue(wgt.options.AccX)
    local accXn = tonumber(accX)
    if accXn ~= nil then
        wgt.accX = accXn
        if wgt.maxAccX == nil or accXn > wgt.maxAccX then
            wgt.maxAccX = accXn
        end
    end

    if wgt.rxVoltage and wgt.rxVoltage > 0 then
        wgt.percent = percentFromVoltage(wgt.rxVoltage, 2)
    else
        wgt.percent = 0
    end
end

local function near(a, b, tol)
    return math.abs(a - b) <= tol
end

local function nitroThrottleText(govState, ch6Percent)
    local g = tonumber(govState)
    if g == nil then
        if govState == nil then return "--" end
        return tostring(govState)
    end
    if g == 0 then return "Disarmed" end
    if g == 1 then return "Idle Up" end
    if g == 9 then
        local ch6 = tonumber(ch6Percent)
        if ch6 ~= nil then
            if near(ch6, -100, 6) then return "Thr. Cut" end
            if near(ch6, -75, 8) then return "Throttle Hold" end
            if near(ch6, 0, 6) then return "Bailout" end
            if near(ch6, 100, 6) then return "Normal Mode" end
        end
        return "Mode 9"
    end
    return tostring(g)
end

local drawMetricRowN = drawMetricRow

local function n_drawTelemetryStack(wgt, area)
    local rows = 6
    local topNudge = 4
    local lineH = math.floor((area.h - topNudge) / rows)
    local y = area.y + topNudge
    local x = area.x
    local w = area.w
    local color = normalizeTextColor(wgt.textColor)
    local shadowLabels = (wgt.options and (wgt.options.LblShadow == 1 or wgt.options.LblShadow == true)) or false
    local vs = choiceIndex(wgt.options and wgt.options.ValStyle or 0, 3)

    local rxMinTxt = (wgt.minRxVoltage and ("Min " .. voltageTextExact(wgt.minRxVoltage, "V"))) or "Min --"
    drawMetricRowN(x, y, w, "Receiver", rxMinTxt, nil, color, shadowLabels, nil, vs)
    y = y + lineH

    drawMetricRowN(x, y, w, "Accel Z", "Max " .. fmtAcc(wgt.maxAccZ), nil, color, shadowLabels, nil, vs)
    y = y + lineH

    drawMetricRowN(x, y, w, "Accel X", "Max " .. fmtAcc(wgt.maxAccX), nil, color, shadowLabels, nil, vs)
    y = y + lineH

    drawMetricRowN(x, y, w, "RPM", fmtVal(wgt.rpm, "%.0f"), "Max " .. fmtVal(wgt.maxRpm, "%.0f"), color, shadowLabels, nil, vs)
    y = y + lineH

    drawMetricRowN(x, y, w, "Tail RPM", fmtVal(wgt.tailRpm, "%.0f"), "Max " .. fmtVal(wgt.maxTailRpm, "%.0f"), color, shadowLabels, nil, vs)
    y = y + lineH

    local govPrimary = nitroThrottleText(wgt.govState, wgt.ch6Percent)
    drawMetricRowN(x, y, w, "Throttle", govPrimary, nil, color, shadowLabels, nil, vs)
end

local function n_background(wgt)
    if not wgt then return end
    n_readTelemetry(wgt)
    refreshTopbarData(wgt)
end

local function n_refresh(wgt, event, touchState)
    if not wgt or not wgt.zone then return end
    n_readTelemetry(wgt)
    refreshTopbarData(wgt)
    local z = wgt.zone
    local topH = topbarHeight(z)
    drawTopBar(wgt, z)

    local contentY = z.y + topH + 6
    local contentH = z.h - topH - 10
    if contentH < 80 then return end

    local rightW = math.floor(z.w / 2)
    local rightX = z.x + z.w - rightW
    local pad = 10
    local gap = 8
    local usableH = contentH - (pad * 2) - gap
    local rxBarH = math.floor(usableH * 0.25)
    local modelH = usableH - rxBarH

    local la = wgt._leftArea
    if not la then la = {}; wgt._leftArea = la end
    la.x = z.x + LEFT_STACK_PAD; la.y = contentY + 2
    la.w = rightX - z.x - 18;    la.h = contentH - 4

    local ma = wgt._modelArea
    if not ma then ma = {}; wgt._modelArea = ma end
    ma.x = rightX + pad; ma.y = contentY + pad
    ma.w = rightW - pad * 2; ma.h = modelH

    local ra = wgt._rxBarArea
    if not ra then ra = {}; wgt._rxBarArea = ra end
    ra.x = rightX + pad; ra.y = contentY + pad + modelH + gap
    ra.w = rightW - pad * 2; ra.h = rxBarH

    n_drawTelemetryStack(wgt, la)
    drawModelArea(wgt, ma)
    drawNitroRxPackBar(wgt, ra)
end

-- Keys exclusive to each mode (nilled on mode switch to free stale memory)
local ELECTRIC_ONLY_KEYS = {
    "cells", "current", "maxCurrent", "voltage", "cellVoltage", "minCellVoltage",
    "escTemp", "maxEscTemp", "becVolt", "minBecVolt", "capacity",
    "adjustedPercent", "barColor", "hasBattData",
    "battAlertPrevPct", "battAlert50Played", "battAlert10Played",
    "battAlert0Played", "battAlert5HapticPlayed", "battAlertNextTick",
    "isLiHV", "_battArea",
}
local NITRO_ONLY_KEYS = {
    "rxVoltage", "rxCellVoltage", "minRxVoltage",
    "accX", "maxAccX", "accZ", "maxAccZ",
    "ch6Percent", "govState", "_rxBarArea",
}

-- Aggregator: Electric vs Nitro (self-contained)
local function create(zone, opts)
    local mode = choiceIndex(opts.Mode, 1)
    if mode == 1 then
        return n_create(zone, opts)
    else
        return e_create(zone, opts)
    end
end

local function update(wgt, opts)
    if not wgt then return end
    local newMode = choiceIndex(opts.Mode, 1)
    local isCurrentNitro = (wgt.isNitro == true)
    local isNewNitro = (newMode == 1)
    if isNewNitro ~= isCurrentNitro then
        -- Nil out stale keys from the old mode before copying new state
        local staleKeys = isNewNitro and ELECTRIC_ONLY_KEYS or NITRO_ONLY_KEYS
        for _, k in ipairs(staleKeys) do wgt[k] = nil end
        local new = create(wgt.zone, opts)
        for k, v in pairs(new) do wgt[k] = v end
        return
    end
    if isNewNitro then
        n_update(wgt, opts)
    else
        e_update(wgt, opts)
    end
end

local function background(wgt)
    if not wgt then return end
    if wgt.isNitro then
        n_background(wgt)
    else
        e_background(wgt)
    end
end

local function refresh(wgt, event, touchState)
    if not wgt then return end
    if wgt.isNitro then
        n_refresh(wgt, event, touchState)
    else
        e_refresh(wgt, event, touchState)
    end
end

return {
    name = appName,
    options = options,
    create = create,
    update = update,
    background = background,
    refresh = refresh
}

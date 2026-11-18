-- 四指实体压下时按住用户配置的快捷键，直到所有手指离开触控板。
local state = { fingers = 0, ready = false, pressed = false, swipeSleeping = false }
state.name = "FourFingerGestures"
local event = hs.eventtap.event
local directory = hs.spoons.scriptPath()

local modifierNames = {
    cmd = "leftCommand", ctrl = "leftControl", alt = "leftOption", shift = "leftShift",
    leftCommand = "leftCommand", rightCommand = "rightCommand",
    leftControl = "leftControl", rightControl = "rightControl",
    leftOption = "leftOption", rightOption = "rightOption",
    leftShift = "leftShift", rightShift = "rightShift",
}
local defaults = {
    hold = {key = 50, modifiers = {"leftOption", "leftShift"}},
    swipeDown = {key = 36},
}
local holdArgs, swipeArgs

local function shortcutArgs(action, shortcut, label)
    assert(type(shortcut) == "table", label .. " 必须是快捷键配置表")
    local key = shortcut.key
    if type(key) == "string" then
        key = hs.keycodes.map[key]
        assert(key, label .. " 包含未知按键：" .. shortcut.key)
    end
    if key ~= nil then
        assert(type(key) == "number" and key % 1 == 0 and key >= 0 and key <= 255,
            label .. " 的 key 必须是按键名或 0–255 的键码")
    end

    local mods = shortcut.modifiers
    if mods == nil then mods = {} end
    assert(type(mods) == "table", label .. " 的 modifiers 必须是列表")
    local args, seen = {action, key and tostring(math.floor(key)) or "-"}, {}
    for i, name in ipairs(mods) do
        local modifier = modifierNames[name]
        assert(modifier and not seen[modifier], label .. " 包含未知或重复的修饰键：" .. tostring(name))
        seen[modifier] = true
        args[i + 2] = modifier
    end
    for index in pairs(mods) do
        assert(type(index) == "number" and index % 1 == 0 and index >= 1 and index <= #args - 2,
            label .. " 的 modifiers 必须是连续列表")
    end
    assert(key or #args > 2, label .. " 至少需要一个按键")
    return args
end

function state:configure(options)
    assert(type(options) == "table", "FourFingerGestures 配置必须返回表")
    local hold = options.hold
    local swipe = options.swipeDown
    if hold == nil then hold = defaults.hold end
    if swipe == nil then swipe = defaults.swipeDown end
    local nextHold = shortcutArgs("--hold", hold, "hold")
    local nextSwipe = shortcutArgs("--tap", swipe, "swipeDown")
    holdArgs, swipeArgs = nextHold, nextSwipe
    return self
end

function state.startHold()
    state.pressed = true
    state.suppressSwipe = true
    if state.shortcutTask and state.shortcutTask:isRunning() then return end
    local task
    task = hs.task.new(directory .. "keyboard", function(code, _, err)
        if state.shortcutTask ~= task then return end
        state.shortcutTask = nil
        state.lastError = code ~= 0 and err or nil
        if code ~= 0 then
            state.pressed = false
            hs.alert.show("语音按键发送失败，请检查 Hammerspoon 辅助功能权限")
        elseif state.pressed then
            -- 上一轮释放完成前已再次压下时，顺序开始下一轮。
            state.startHold()
        end
    end, function() return true end, holdArgs)
    state.shortcutTask = task
    if not task or not task:start() then
        state.pressed = false
        state.shortcutTask = nil
        hs.alert.show("无法按住语音快捷键")
    end
end

function state.releaseHold()
    state.pressed = false
    if state.shortcutTask and state.shortcutTask:isRunning() then
        state.shortcutTask:closeInput()
    end
end

function state.onFingerFrame(values)
    local fingers = tonumber(values.multitouch_extension_finger_count_total)
    if not fingers then return end
    state.fingers, state.ready = fingers, true
    state.palms = tonumber(values.multitouch_extension_palm_count_total) or 0
    state.lastFingerError = nil
    if fingers == 0 then
        if state.pressed then state.releaseHold() end
        state.suppressSwipe = false
    end
end

function state.tapSwipeShortcut()
    local now = hs.timer.secondsSinceEpoch()
    if state.pressed or state.suppressSwipe or (state.lastSwipeAction and now - state.lastSwipeAction < 0.4) then return end
    state.lastSwipeAction = now
    state.swipeTask = hs.task.new(directory .. "keyboard", function(code, _, err)
        if code ~= 0 then
            state.lastError = err
            hs.alert.show("下滑快捷键发送失败，请检查 Hammerspoon 控制台")
        end
    end, swipeArgs)
    if not state.swipeTask or not state.swipeTask:start() then hs.alert.show("无法发送下滑快捷键") end
end

function state.onSwipe(line)
    if line == "swipe_down_4" then state.tapSwipeShortcut() end
end

local function startSwipeReader()
    state.swipeReady, state.lastSwipeError = false, nil
    local outputBuffer = ""
    local reader
    reader = hs.task.new(directory .. "trackpad-swipe", function(_, _, err)
        if state.swipeReader ~= reader then return end
        state.swipeReady = false
        state.lastSwipeError = err
    end, function(task, output)
        if not task or state.swipeReader ~= reader or state.swipeSleeping then return false end
        outputBuffer = outputBuffer .. (output or "")
        while true do
            local newline = outputBuffer:find("\n", 1, true)
            if not newline then break end
            local line = outputBuffer:sub(1, newline - 1)
            outputBuffer = outputBuffer:sub(newline + 1)
            if line:match("^ready %d+$") then state.swipeReady = true
            else state.onSwipe(line) end
        end
        return true
    end)
    state.swipeReader = reader
    if not reader or not reader:start() then state.lastSwipeError = "无法启动四指下滑读取器" end
end

local function stopSwipeReader()
    state.swipeReady = false
    if state.swipeReader and state.swipeReader:isRunning() then state.swipeReader:terminate() end
end

local function onPowerEvent(kind)
    local watcher = hs.caffeinate.watcher
    if kind == watcher.systemWillSleep then
        state.swipeSleeping = true
        stopSwipeReader()
    elseif kind == watcher.systemDidWake then
        -- 重新打开设备；旧进程即使还活着，也不再使用睡前的订阅。
        stopSwipeReader()
        state.swipeSleeping = false
    end
end

-- 使用现有 Karabiner 扩展读取手指数，不接管 Apple 触控板的 HID 设备。
local cli = "/Library/Application Support/org.pqrs/Karabiner-Elements/bin/karabiner_cli"
local buffer = ""
function state.consumeOutput(output)
    buffer = buffer .. (output or "")
    while true do
        local newline = buffer:find("\n", 1, true)
        if not newline then break end
        local line = buffer:sub(1, newline - 1)
        buffer = buffer:sub(newline + 1)
        local ok, values = pcall(hs.json.decode, line)
        if ok and type(values) == "table" then
            state.onFingerFrame(values)
        end
    end
end

local function startReader()
    state.fingers, state.ready = 0, false
    buffer = ""
    local reader
    reader = hs.task.new(cli, function(_, _, err)
        if state.reader ~= reader then return end
        state.fingers, state.ready, state.suppressSwipe = 0, false, false
        state.lastFingerError = err
        state.releaseHold()
    end, function(_, output)
        if state.reader ~= reader then return false end
        state.consumeOutput(output)
        return true
    end, { "--watch-multitouch-extension-variables=20" })
    state.reader = reader
    if not reader or not reader:start() then
        state.lastFingerError = "无法启动 Karabiner CLI，请安装支持触控扩展的 Karabiner-Elements"
    end
end

local types = event.types
local pendingButton
function state.handleClick(click)
    local kind = click:getType()
    local button = click:getProperty(event.properties.mouseEventButtonNumber)
    if kind == types.leftMouseDown or kind == types.rightMouseDown then
        if pendingButton ~= nil then return button == pendingButton end
        if state.ready and state.fingers == 4 and (state.palms or 0) == 0
            and state.reader and state.reader:isRunning() then
            pendingButton = button
            if not state.pressed then state.startHold() end
            return true
        end
        return false
    end
    if pendingButton == nil or button ~= pendingButton then return false end
    if kind == types.leftMouseUp or kind == types.rightMouseUp then
        -- 实体按键弹起只结束点击拦截，语音由接触数控制。
        pendingButton = nil
    end
    return true
end

function state:start(options)
    if self.healthTimer then return self end
    if options == nil then
        local path = hs.configdir .. "/four-finger-gestures.lua"
        if hs.fs.attributes(path) then
            options = dofile(path)
        else
            options = {}
        end
    end
    self:configure(options)
    state.swipeSleeping = false
    startReader()
    startSwipeReader()
    state.powerWatcher = hs.caffeinate.watcher.new(onPowerEvent):start()
    state.clickTap = hs.eventtap.new({
        types.leftMouseDown, types.leftMouseUp, types.leftMouseDragged,
        types.rightMouseDown, types.rightMouseUp, types.rightMouseDragged,
    }, state.handleClick):start()
    state.healthTimer = hs.timer.doEvery(1, function()
        if not state.reader or not state.reader:isRunning() then startReader() end
        if not state.swipeSleeping and (not state.swipeReader or not state.swipeReader:isRunning()) then
            startSwipeReader()
        end
        if not state.clickTap:isEnabled() then
            pendingButton = nil
            state.clickTap:start()
        end
    end)
    return self
end

function state:stop()
    if self.healthTimer then self.healthTimer:stop() end
    self.healthTimer = nil
    if self.powerWatcher then self.powerWatcher:stop() end
    if self.clickTap then self.clickTap:stop() end
    self.releaseHold()
    pendingButton = nil
    self.fingers, self.ready, self.suppressSwipe = 0, false, false
    local reader = self.reader
    self.reader = nil
    if reader and reader:isRunning() then reader:terminate() end
    stopSwipeReader()
    self.swipeReader = nil
    return self
end

function state:status()
    return {
        accessibility = hs.accessibilityState(),
        clickTap = self.clickTap and self.clickTap:isEnabled(),
        fingerReader = self.ready,
        swipeReader = self.swipeReady == true,
        fingers = self.fingers,
        voiceHeld = self.pressed,
        fingerError = self.lastFingerError,
        swipeError = self.lastSwipeError,
        keyboardError = self.lastError,
    }
end

return state:configure({})

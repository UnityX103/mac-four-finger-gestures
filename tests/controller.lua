local types = {
    leftMouseDown = 1, leftMouseUp = 2, leftMouseDragged = 3,
    rightMouseDown = 4, rightMouseUp = 5, rightMouseDragged = 6,
}
local started, released = 0, 0
local enters = 0
local now = 1
local holdArgs, swipeArgs
hs = {
    spoons = {scriptPath = function() return "/test/" end},
    eventtap = {event = {types = types, properties = {mouseEventButtonNumber = 0}}},
    keycodes = {map = {f8 = 100, space = 49}},
    json = {decode = function(line)
        return {multitouch_extension_finger_count_total = assert(tonumber(line))}
    end},
    timer = {secondsSinceEpoch = function() return now end},
    task = {new = function(path, done, stream, args)
        args = args or stream
        assert(path == "/test/keyboard")
        if args[1] == "--tap" then
            swipeArgs = table.concat(args, " ")
            return {start = function(self)
                enters = enters + 1
                done(0)
                return self
            end}
        end
        assert(args[1] == "--hold")
        holdArgs = table.concat(args, " ")
        return {
            start = function(self)
                started = started + 1
                self.running = true
                return self
            end,
            isRunning = function(self) return self.running end,
            closeInput = function(self)
                released = released + 1
                self.running = false
                done(0)
            end,
        }
    end},
}
local controller = dofile(assert(arg[1]))
controller.reader = {isRunning = function() return true end}
local function click(kind, button)
    return controller.handleClick({
        getType = function() return kind end,
        getProperty = function() return button end,
    })
end
local function contacts(count)
    controller.consumeOutput(tostring(count))
    controller.consumeOutput("\n")
end

contacts(4)
contacts(0)
assert(started == 0, "四指轻触不能启动录音")
contacts(3)
assert(not click(types.leftMouseDown, 0), "普通点击应当放行")
contacts(4)
assert(click(types.leftMouseDown, 0) and controller.pressed and started == 1)
assert(click(types.leftMouseDragged, 0))
contacts(3)
assert(click(types.leftMouseUp, 0), "拦截已接管的 click-up")
assert(controller.pressed and released == 0, "还有三指接触，实体按键弹起不应停止录音")
for _, count in ipairs({2, 1, 1, 4}) do
    contacts(count)
    assert(controller.pressed and controller.suppressSwipe and released == 0,
        string.format("仍有 %d 指，语音应继续", count))
end
assert(click(types.rightMouseDown, 1) and click(types.rightMouseUp, 1))
assert(started == 1 and released == 0 and controller.pressed)
assert(holdArgs == "--hold 50 leftOption leftShift")
contacts(1)
controller.onSwipe("swipe_down_4")
assert(enters == 0, "录音中不能触发发送")
contacts(0)
assert(released == 1 and not controller.pressed and not controller.suppressSwipe)
contacts(0)
assert(released == 1, "重复的零接触帧只能停止一次")

contacts(4)
assert(click(types.rightMouseDown, 1) and started == 2)
contacts(0)
assert(released == 2 and not controller.pressed, "零接触早于 click-up 时也要立即停止")
assert(click(types.rightMouseUp, 1))
assert(released == 2 and not click(types.leftMouseDown, 0))
controller.onSwipe("swipe_down_3")
assert(enters == 0)
controller.onSwipe("swipe_down_4")
controller.onSwipe("swipe_down_4")
assert(enters == 1 and swipeArgs == "--tap 36", "四指下滑只发送一次 Return")
now = 2
controller.onSwipe("swipe_down_4")
assert(enters == 2, "下一次下滑仍可发送")
controller:configure({
    hold = {modifiers = {"rightOption"}},
    swipeDown = {key = "space", modifiers = {"cmd", "rightShift"}},
})
assert(not pcall(controller.configure, controller, {hold = {key = "unknown"}}))
assert(not pcall(controller.configure, controller, {hold = {modifiers = {"cmd", "leftCommand"}}}))
contacts(4)
assert(click(types.leftMouseDown, 0) and holdArgs == "--hold - rightOption")
contacts(1)
assert(click(types.leftMouseUp, 0) and released == 2)
contacts(0)
assert(released == 3)
now = 3
controller.onSwipe("swipe_down_4")
assert(enters == 3 and swipeArgs == "--tap 49 leftCommand rightShift")
print("PASS: 4→3→2→1 保持语音，0 停止；录音中不发送，四指下滑只发送一次；默认与自定义快捷键已验证。")

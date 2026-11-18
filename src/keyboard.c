#include <ApplicationServices/ApplicationServices.h>
#include <Carbon/Carbon.h>
#include <errno.h>
#include <signal.h>
#include <stdbool.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>

typedef struct {
    const char *name;
    CGKeyCode key;
    CGEventFlags flags;
} Modifier;

static const Modifier modifiers[] = {
    {"leftControl", kVK_Control, kCGEventFlagMaskControl | 0x0001},
    {"rightControl", kVK_RightControl, kCGEventFlagMaskControl | 0x2000},
    {"leftShift", kVK_Shift, kCGEventFlagMaskShift | 0x0002},
    {"rightShift", kVK_RightShift, kCGEventFlagMaskShift | 0x0004},
    {"leftCommand", kVK_Command, kCGEventFlagMaskCommand | 0x0008},
    {"rightCommand", kVK_RightCommand, kCGEventFlagMaskCommand | 0x0010},
    {"leftOption", kVK_Option, kCGEventFlagMaskAlternate | 0x0020},
    {"rightOption", kVK_RightOption, kCGEventFlagMaskAlternate | 0x0040},
};
enum { modifierCount = sizeof(modifiers) / sizeof(modifiers[0]) };

typedef struct {
    bool has_key;
    CGKeyCode key;
    const Modifier *mods[modifierCount];
    size_t count;
} Shortcut;

static volatile sig_atomic_t stopping;

static void stop_signal(int number) {
    (void)number;
    stopping = 1;
}

static bool parse_shortcut(Shortcut *shortcut, int argc, char **argv) {
    if (argc < 1 || argc > modifierCount + 1) return false;
    shortcut->has_key = strcmp(argv[0], "-") != 0;
    if (shortcut->has_key) {
        char *end;
        long code = strtol(argv[0], &end, 10);
        if (end == argv[0] || *end || code < 0 || code > 255) return false;
        shortcut->key = (CGKeyCode)code;
    }

    for (int i = 1; i < argc; i++) {
        const Modifier *selected = NULL;
        for (size_t j = 0; j < modifierCount; j++) {
            if (strcmp(argv[i], modifiers[j].name) == 0) selected = &modifiers[j];
        }
        if (!selected || (shortcut->has_key && selected->key == shortcut->key)) return false;
        for (size_t j = 0; j < shortcut->count; j++) {
            if (shortcut->mods[j] == selected) return false;
        }
        shortcut->mods[shortcut->count++] = selected;
    }
    return shortcut->has_key || shortcut->count > 0;
}

static void send_key(CGEventSourceRef source, CGKeyCode key, bool down, CGEventType type, CGEventFlags flags) {
    CGEventRef event = CGEventCreateKeyboardEvent(source, key, down);
    if (!event) return;
    CGEventSetType(event, type);
    CGEventSetFlags(event, flags);
    CGEventPost(kCGHIDEventTap, event);
    CFRelease(event);
}

static CGEventFlags modifier_flags(const Shortcut *shortcut, size_t count) {
    CGEventFlags flags = 0;
    for (size_t i = 0; i < count; i++) flags |= shortcut->mods[i]->flags;
    return flags;
}

static void wait_until_release(void) {
    // The Spoon closes stdin on all fingers leaving. Parent exit also produces EOF.
    while (!stopping) {
        fd_set read_fds;
        FD_ZERO(&read_fds);
        FD_SET(STDIN_FILENO, &read_fds);
        struct timeval timeout = {.tv_sec = 0, .tv_usec = 100000};
        int ready = select(STDIN_FILENO + 1, &read_fds, NULL, NULL, &timeout);
        if (ready < 0 && errno != EINTR) break;
        if (ready > 0) {
            char command;
            ssize_t size = read(STDIN_FILENO, &command, 1);
            if (size == 0 || (size < 0 && errno != EINTR) || (size > 0 && command == '\n')) break;
        }
    }
}

int main(int argc, char **argv) {
    const char *action = argc > 1 ? argv[1] : "";
    bool hold = strcmp(action, "--hold") == 0;
    bool check = strcmp(action, "--check") == 0;
    Shortcut shortcut = {0};
    if ((!hold && !check && strcmp(action, "--tap") != 0) || !parse_shortcut(&shortcut, argc - 2, argv + 2)) {
        fputs("Usage: keyboard --hold | --tap | --check KEYCODE [MODIFIER ...]\n", stderr);
        return 2;
    }
    if (check) return 0;
    if (!AXIsProcessTrusted()) {
        fputs("Accessibility unavailable\n", stderr);
        return 1;
    }
    CGEventSourceRef source = CGEventSourceCreate(kCGEventSourceStateHIDSystemState);
    if (!source) return 2;
    signal(SIGTERM, stop_signal);
    signal(SIGINT, stop_signal);

    for (size_t i = 0; i < shortcut.count; i++) {
        send_key(source, shortcut.mods[i]->key, true, kCGEventFlagsChanged, modifier_flags(&shortcut, i + 1));
    }
    CGEventFlags flags = modifier_flags(&shortcut, shortcut.count);
    if (shortcut.has_key) {
        if (shortcut.count > 0) usleep(20000);
        send_key(source, shortcut.key, true, kCGEventKeyDown, flags);
    }
    if (hold) wait_until_release();
    else usleep(20000);
    if (shortcut.has_key) send_key(source, shortcut.key, false, kCGEventKeyUp, flags);

    for (size_t i = shortcut.count; i > 0; i--) {
        send_key(source, shortcut.mods[i - 1]->key, false, kCGEventFlagsChanged, modifier_flags(&shortcut, i - 1));
    }
    CFRelease(source);
    return 0;
}

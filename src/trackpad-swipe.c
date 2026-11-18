// MultitouchSupport ABI reference: artginzburg/MiddleClick,
// MoreTouch/Sources/MultitouchSupport/MultitouchSupport.h.
// Read-only callbacks. Each connected trackpad has its own gesture state.
#include <CoreFoundation/CoreFoundation.h>
#include <assert.h>
#include <dlfcn.h>
#include <math.h>
#include <signal.h>
#include <stdbool.h>
#include <stdio.h>
#include <string.h>

typedef struct { float x, y; } TouchPoint;
typedef struct { TouchPoint position, velocity; } TouchVector;
typedef struct {
    int frame;
    double timestamp;
    int identifier, stage, fingerID, handID;
    TouchVector normalizedVector;
    float total, pressure, angle, majorAxis, minorAxis;
    TouchVector absoluteVector;
    int unknown14, unknown15;
    float density;
} Contact;
typedef void *Device;

enum { fingers = 4, maxDevices = 16 };
typedef struct {
    bool tracking, finished;
    int ids[fingers];
    double began;
    TouchPoint origin;
} Gesture;
static struct { Device device; Gesture gesture; } devices[maxDevices];
static volatile sig_atomic_t stopping;

static void stop_signal(int number) {
    (void)number;
    stopping = 1;
}

static bool update(Gesture *gesture, const Contact *contacts, int count, double now) {
    if (count == 0) {
        *gesture = (Gesture){0};
        return false;
    }
    if (count > fingers || (gesture->tracking && count < fingers)) gesture->finished = true;
    if (count != fingers || gesture->finished) return false;

    TouchPoint center = {0};
    for (int i = 0; i < fingers; i++) {
        center.x += contacts[i].normalizedVector.position.x / fingers;
        center.y += contacts[i].normalizedVector.position.y / fingers;
    }
    if (!gesture->tracking) {
        gesture->tracking = true;
        gesture->began = now;
        gesture->origin = center;
        for (int i = 0; i < fingers; i++) gesture->ids[i] = contacts[i].identifier;
        return false;
    }

    for (int i = 0; i < fingers; i++) {
        bool found = false;
        for (int j = 0; j < fingers; j++) {
            if (gesture->ids[i] == contacts[j].identifier) found = true;
        }
        if (!found) {
            gesture->finished = true;
            return false;
        }
    }
    double dx = center.x - gesture->origin.x;
    double dy = center.y - gesture->origin.y;
    double elapsed = now - gesture->began;
    if (dy > 0.04 || fabs(dx) > 0.08 || elapsed > 0.9) {
        gesture->finished = true;
        return false;
    }
    if (dy > -0.12 || elapsed < 0.04) return false;

    gesture->finished = true;
    return true;
}

static void frame(Device device, Contact *raw, int count, double now, int frame_number) {
    (void)frame_number;
    Contact active[fingers];
    int active_count = 0;
    for (int i = 0; i < count; i++) {
        if (raw[i].stage != 3 && raw[i].stage != 4) continue;
        if (active_count < fingers) active[active_count] = raw[i];
        active_count++;
    }
    for (int i = 0; i < maxDevices; i++) {
        if (devices[i].device != device) continue;
        if (update(&devices[i].gesture, active, active_count, now)) {
            puts("swipe_down_4");
            fflush(stdout);
        }
        break;
    }
}

static void selftest(void) {
    Gesture gesture = {0};
    Contact contacts[fingers] = {0};
    for (int i = 0; i < fingers; i++) contacts[i].identifier = i;

    assert(!update(&gesture, contacts, 3, 0));
    assert(!update(&gesture, contacts, 4, 0.01));
    for (int i = 0; i < fingers; i++) contacts[i].normalizedVector.position.y = -0.15f;
    assert(update(&gesture, contacts, 4, 0.15));
    assert(!update(&gesture, contacts, 4, 0.20));
    assert(!update(&gesture, contacts, 3, 0.25));
    assert(!update(&gesture, contacts, 0, 0.30));

    assert(!update(&gesture, contacts, 5, 1));
    assert(!update(&gesture, contacts, 4, 1.1));
    assert(!update(&gesture, contacts, 0, 1.2));

    const TouchPoint rejected[] = {{0, 0.20f}, {0.15f, -0.15f}, {0, 0}};
    for (size_t i = 0; i < sizeof(rejected) / sizeof(rejected[0]); i++) {
        for (int j = 0; j < fingers; j++) contacts[j].normalizedVector.position = (TouchPoint){0};
        assert(!update(&gesture, contacts, 4, 2));
        for (int j = 0; j < fingers; j++) contacts[j].normalizedVector.position = rejected[i];
        assert(!update(&gesture, contacts, 4, 2.2));
        assert(!update(&gesture, contacts, 0, 2.3));
    }
    puts("PASS: one action per four-finger down swipe; other directions, counts and taps ignored.");
}

int main(int argc, char **argv) {
    if (argc == 2 && strcmp(argv[1], "--self-test") == 0) {
        selftest();
        return 0;
    }
    void *library = dlopen("/System/Library/PrivateFrameworks/MultitouchSupport.framework/MultitouchSupport", RTLD_NOW);
    if (!library) {
        fputs("MultitouchSupport unavailable\n", stderr);
        return 1;
    }
    typedef void (*FrameCallback)(Device, Contact *, int, double, int);
    CFArrayRef (*create)(void) = dlsym(library, "MTDeviceCreateList");
    void (*register_callback)(Device, FrameCallback) = dlsym(library, "MTRegisterContactFrameCallback");
    void (*unregister_callback)(Device, FrameCallback) = dlsym(library, "MTUnregisterContactFrameCallback");
    void (*start)(Device, int) = dlsym(library, "MTDeviceStart");
    void (*stop)(Device) = dlsym(library, "MTDeviceStop");
    if (!create || !register_callback || !unregister_callback || !start || !stop) {
        fputs("MultitouchSupport API unavailable\n", stderr);
        return 2;
    }

    CFArrayRef list = create();
    if (list == NULL || CFArrayGetCount(list) == 0) {
        fputs("No multitouch device\n", stderr);
        return 3;
    }
    CFIndex count = CFArrayGetCount(list);
    if (count > maxDevices) count = maxDevices;
    for (CFIndex i = 0; i < count; i++) devices[i].device = (Device)CFArrayGetValueAtIndex(list, i);

    signal(SIGTERM, stop_signal);
    signal(SIGINT, stop_signal);
    for (CFIndex i = 0; i < count; i++) {
        register_callback(devices[i].device, frame);
        start(devices[i].device, 0);
    }
    printf("ready %ld\n", count);
    fflush(stdout);
    while (!stopping) CFRunLoopRunInMode(kCFRunLoopDefaultMode, 0.1, false);

    for (CFIndex i = 0; i < count; i++) {
        unregister_callback(devices[i].device, frame);
        stop(devices[i].device);
    }
    CFRelease(list);
    dlclose(library);
    return 0;
}

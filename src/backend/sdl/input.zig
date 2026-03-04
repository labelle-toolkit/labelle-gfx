//! SDL2 Backend Input Handling
//!
//! Keyboard input with key enum mapping to SDL scancodes.

const state = @import("state.zig");

/// Key codes for input handling (maps to SDL scancodes)
pub const Key = enum(u16) {
    // Letters
    a = 4,
    b = 5,
    c = 6,
    d = 7,
    e = 8,
    f = 9,
    g = 10,
    h = 11,
    i = 12,
    j = 13,
    k = 14,
    l = 15,
    m = 16,
    n = 17,
    o = 18,
    p = 19,
    q = 20,
    r = 21,
    s = 22,
    t = 23,
    u = 24,
    v = 25,
    w = 26,
    x = 27,
    y = 28,
    z = 29,

    // Numbers
    @"1" = 30,
    @"2" = 31,
    @"3" = 32,
    @"4" = 33,
    @"5" = 34,
    @"6" = 35,
    @"7" = 36,
    @"8" = 37,
    @"9" = 38,
    @"0" = 39,

    // Special keys
    @"return" = 40,
    escape = 41,
    backspace = 42,
    tab = 43,
    space = 44,

    // Function keys
    f1 = 58,
    f2 = 59,
    f3 = 60,
    f4 = 61,
    f5 = 62,
    f6 = 63,
    f7 = 64,
    f8 = 65,
    f9 = 66,
    f10 = 67,
    f11 = 68,
    f12 = 69,

    // Arrow keys
    right = 79,
    left = 80,
    down = 81,
    up = 82,
};

/// Check if a key is currently held down
pub fn isKeyDown(key: Key) bool {
    const scancode = @intFromEnum(key);
    if (scancode < state.keys_pressed.len) {
        return state.keys_pressed[scancode];
    }
    return false;
}

/// Check if a key was just pressed this frame
pub fn isKeyPressed(key: Key) bool {
    const scancode = @intFromEnum(key);
    if (scancode < state.keys_just_pressed.len) {
        return state.keys_just_pressed[scancode];
    }
    return false;
}

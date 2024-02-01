const std = @import("std");
const zm = @import("zmath");
const math = @import("../math/math.zig");
const game = @import("../ab.zig");
const nfd = @import("nfd");
const core = @import("mach-core");

const Key = core.Key;
const Mods = core.KeyMods;

const builtin = @import("builtin");

const Self = @This();

pub const KeyState = enum(u32) {
    press,
    repeat,
    release,
};

pub const Action = enum(u32) {
    up,
    down,
    jump,
};

hotkeys: []Hotkey,

pub const Hotkey = struct {
    shortcut: [:0]const u8 = undefined,
    key: core.Key,
    mods: ?Mods = null,
    action: Action,
    state: bool = false,
    previous_state: bool = false,

    /// Returns true the frame the key was pressed.
    pub fn pressed(self: Hotkey) bool {
        return (self.state == true and self.state != self.previous_state);
    }

    /// Returns true while the key is pressed down.
    pub fn down(self: Hotkey) bool {
        return self.state == true;
    }

    /// Returns true the frame the key was released.
    pub fn released(self: Hotkey) bool {
        return (self.state == false and self.state != self.previous_state);
    }

    /// Returns true while the key is released.
    pub fn up(self: Hotkey) bool {
        return self.state == false;
    }
};

pub fn hotkey(self: *Self, action: Action) ?*Hotkey {
    for (self.hotkeys) |*hk| {
        if (hk.action == action)
            return hk;
    }
    return null;
}

pub fn setHotkeyState(self: *Self, k: Key, mods: Mods, state: KeyState) void {
    for (self.hotkeys) |*hk| {
        if (hk.key == k) {
            if (state == .release or (hk.mods == null and @as(u8, @bitCast(mods)) == 0)) {
                hk.previous_state = hk.state;
                hk.state = switch (state) {
                    .release => false,
                    else => true,
                };
            } else if (hk.mods) |md| {
                if (@as(u8, @bitCast(md)) == @as(u8, @bitCast(mods))) {
                    hk.previous_state = hk.state;
                    hk.state = switch (state) {
                        .release => false,
                        else => true,
                    };
                }
            }
        }
    }
}

pub fn initDefault(allocator: std.mem.Allocator) !Self {
    var hotkeys = std.ArrayList(Hotkey).init(allocator);

    // const os = builtin.target.os.tag;
    // const windows = os == .windows;
    // const macos = os == .macos;

    {
        try hotkeys.append(.{
            .shortcut = "down arrow",
            .key = Key.down,
            .action = .down,
        });

        try hotkeys.append(.{
            .shortcut = "up arrow",
            .key = Key.up,
            .action = .up,
        });

        try hotkeys.append(.{
            .shortcut = "space",
            .key = Key.space,
            .action = .jump,
        });
    }

    return .{ .hotkeys = try hotkeys.toOwnedSlice() };
}

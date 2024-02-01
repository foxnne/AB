const std = @import("std");
const zm = @import("zmath");
const ecs = @import("zflecs");
const game = @import("../../ab.zig");
const components = game.components;

pub fn system() ecs.system_desc_t {
    var desc: ecs.system_desc_t = .{};
    desc.query.filter.terms[0] = .{ .id = ecs.id(components.Player) };
    desc.query.filter.terms[1] = .{ .id = ecs.id(components.Jump), .oper = ecs.oper_kind_t.Not };
    desc.run = run;
    return desc;
}

pub fn run(it: *ecs.iter_t) callconv(.C) void {
    while (ecs.iter_next(it)) {
        var i: usize = 0;
        while (i < it.count()) : (i += 1) {
            const entity = it.entities()[i];
            if (game.state.hotkeys.hotkey(.jump)) |hk| {
                if (hk.pressed()) {
                    _ = ecs.set(it.world, entity, components.Jump, .{});
                }
            }
        }
    }
}

const std = @import("std");
const zm = @import("zmath");
const game = @import("../../ab.zig");
const components = game.components;
const ecs = @import("zflecs");

pub fn system() ecs.system_desc_t {
    var desc: ecs.system_desc_t = .{};
    desc.query.filter.terms[0] = .{ .id = ecs.id(components.Jump) };
    desc.query.filter.terms[1] = .{ .id = ecs.id(components.Position) };
    desc.query.filter.terms[2] = .{ .id = ecs.id(components.Player), .oper = ecs.oper_kind_t.Optional };
    desc.run = run;
    return desc;
}

pub fn run(it: *ecs.iter_t) callconv(.C) void {
    const world = it.world;

    while (ecs.iter_next(it)) {
        var i: usize = 0;
        while (i < it.count()) : (i += 1) {
            const entity = it.entities()[i];

            if (ecs.field(it, components.Jump, 1)) |jumps| {
                if (ecs.field(it, components.Position, 2)) |positions| {
                    jumps[i].elapsed = std.math.clamp(jumps[i].elapsed + game.state.delta_time, 0.0, 1.0);

                    if (jumps[i].elapsed >= 1.0) {
                        ecs.remove(world, entity, components.Jump);

                        if (ecs.field(it, components.Player, 3)) |players| {
                            players[i].state = .run;
                        }
                    } else {
                        if (ecs.field(it, components.Player, 3)) |players| {
                            players[i].state = .jump;
                        } 
                    }

                    if (jumps[i].elapsed <= 0.5) {
                        const offset = game.math.ease(game.settings.ground_height, game.settings.ground_height + 64.0, jumps[i].elapsed * 2.0, .ease_out);
                        positions[i].y = offset;
                        jumps[i].tail_offset = -2.5;
                    } else {
                        const offset = game.math.ease(game.settings.ground_height + 64.0, game.settings.ground_height, (jumps[i].elapsed - 0.5) * 2.0, .ease_in);
                        positions[i].y = offset;
                        jumps[i].tail_offset = 2.5;
                    }
                }
            }
        }
    }
}

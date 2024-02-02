const std = @import("std");
const zm = @import("zmath");
const ecs = @import("zflecs");
const game = @import("../../ab.zig");
const components = game.components;

pub fn system() ecs.system_desc_t {
    var desc: ecs.system_desc_t = .{};
    desc.query.filter.terms[0] = .{ .id = ecs.id(components.PlayerAnimator) };
    desc.query.filter.terms[1] = .{ .id = ecs.id(components.PlayerRenderer) };
    desc.query.filter.terms[2] = .{ .id = ecs.id(components.Player) };
    desc.run = run;
    return desc;
}

pub fn run(it: *ecs.iter_t) callconv(.C) void {
    while (ecs.iter_next(it)) {
        var i: usize = 0;
        while (i < it.count()) : (i += 1) {
            if (ecs.field(it, components.PlayerAnimator, 1)) |animators| {
                if (ecs.field(it, components.PlayerRenderer, 2)) |renderers| {
                    if (ecs.field(it, components.Player, 3)) |players| {
                        animators[i].animation_body = switch (players[i].state) {
                            .idle, .jump => &game.animations.character_idle_main,
                            .run => &game.animations.character_run_main,
                        };

                        animators[i].fps = switch (players[i].state) {
                            .idle, .jump => 8,
                            .run => 14,
                        };
                    }

                    if (animators[i].state == components.PlayerAnimator.State.play) {
                        animators[i].elapsed += it.delta_time;

                        if (animators[i].elapsed > (1.0 / @as(f32, @floatFromInt(animators[i].fps)))) {
                            animators[i].elapsed = 0.0;

                            if (animators[i].frame < animators[i].animation_body.len - 1) {
                                animators[i].frame += 1;
                            } else animators[i].frame = 0;
                        }

                        animators[i].frame = std.math.clamp(animators[i].frame, 0, animators[i].animation_body.len - 1);

                        renderers[i].index_body = animators[i].animation_body[animators[i].frame];
                        //renderers[i].index_tail = animators[i].animation_tail[animators[i].frame];
                    }
                }
            }
        }
    }
}

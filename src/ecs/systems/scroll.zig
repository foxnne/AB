const std = @import("std");
const zm = @import("zmath");
const game = @import("../../ab.zig");
const components = game.components;
const ecs = @import("zflecs");

pub fn system() ecs.system_desc_t {
    var desc: ecs.system_desc_t = .{};
    desc.query.filter.terms[0] = .{ .id = ecs.id(components.Scroll) };
    desc.query.filter.terms[1] = .{ .id = ecs.id(components.Position) };
    desc.run = run;
    return desc;
}

pub fn run(it: *ecs.iter_t) callconv(.C) void {
    const world = it.world;

    if (ecs.get(world, game.state.entities.player, components.Player)) |player| {
        while (ecs.iter_next(it)) {
            var i: usize = 0;
            while (i < it.count()) : (i += 1) {
                const entity = it.entities()[i];
                _ = entity;

                if (ecs.field(it, components.Scroll, 1)) |scrolls| {
                    if (player.state == .idle and scrolls[i].wait_on_player == true) continue;

                    if (ecs.field(it, components.Position, 2)) |positions| {
                        if (positions[i].x <= -scrolls[i].width / 2.0) {
                            positions[i].x += scrolls[i].width;
                        }

                        var boost: f32 = 1.0;

                        if (ecs.has_pair(world, game.state.entities.player, ecs.id(components.Boost), ecs.id(components.Cooldown))) {
                            boost = 2.0;
                        }

                        positions[i].x = positions[i].x - (it.delta_time * scrolls[i].speed * boost);

                        if (scrolls[i].speed == game.settings.scroll_speed) {
                            positions[i].x = @floor(positions[i].x);
                        }
                    }
                }
            }
        }
    }
}

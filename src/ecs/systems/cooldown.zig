const std = @import("std");
const zm = @import("zmath");
const game = @import("../../ab.zig");
const components = game.components;
const ecs = @import("zflecs");

pub fn system() ecs.system_desc_t {
    var desc: ecs.system_desc_t = .{};
    desc.query.filter.terms[0] = .{ .id = ecs.pair(ecs.Wildcard, ecs.id(components.Cooldown)) };
    desc.run = run;
    return desc;
}

pub fn run(it: *ecs.iter_t) callconv(.C) void {
    const world = it.world;

    while (ecs.iter_next(it)) {
        var i: usize = 0;
        while (i < it.count()) : (i += 1) {
            const entity = it.entities()[i];

            if (ecs.field(it, components.Cooldown, 1)) |cooldowns| {
                if (cooldowns[i].current >= cooldowns[i].end) {
                    const pair_id = ecs.field_id(it, 1);
                    ecs.remove_id(world, entity, pair_id);
                    if (ecs.get_mut(world, game.state.entities.player, components.ParticleAnimator)) |particles| {
                        particles.state = .pause;
                    }
                } else if (cooldowns[i].current >= cooldowns[i].end - it.delta_time) {
                    cooldowns[i].current = cooldowns[i].end;
                    const pair_id = ecs.field_id(it, 1);
                    ecs.remove_id(world, entity, pair_id);

                    if (ecs.get_mut(world, game.state.entities.player, components.ParticleAnimator)) |particles| {
                        particles.state = .pause;
                    }
                } else {
                    cooldowns[i].current += it.delta_time;
                    if (ecs.get_mut(world, game.state.entities.player, components.ParticleAnimator)) |particles| {
                        particles.state = .play;
                    }
                }
            }
        }
    }
}

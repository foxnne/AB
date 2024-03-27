const std = @import("std");
const zm = @import("zmath");
const game = @import("../../ab.zig");
const components = game.components;
const ecs = @import("zflecs");

pub fn system() ecs.system_desc_t {
    var desc: ecs.system_desc_t = .{};
    desc.query.filter.terms[0] = .{ .id = ecs.id(components.Apple) };
    desc.query.filter.terms[1] = .{ .id = ecs.id(components.Position) };
    desc.query.filter.terms[2] = .{ .id = ecs.id(components.SpriteRenderer) };
    desc.query.filter.terms[3] = .{ .id = ecs.id(components.Scroll) };
    desc.run = run;
    return desc;
}

pub fn run(it: *ecs.iter_t) callconv(.C) void {
    const world = it.world;

    if (ecs.get(world, game.state.entities.player, components.PlayerRenderer)) |player_renderer| {
        if (ecs.get(world, game.state.entities.player, components.Position)) |player_position| {
            const player_sprite = game.state.atlas.sprites[player_renderer.index_body];
            var player_origin: [2]f32 = .{ @floatFromInt(player_sprite.origin[0]), @floatFromInt(player_sprite.origin[1]) };
            const player_size: [2]f32 = .{ @floatFromInt(player_sprite.source[2]), @floatFromInt(player_sprite.source[3]) };
            player_origin[0] = -player_origin[0];
            player_origin[1] = -(player_origin[1]);
            const player_tl: [2]f32 = .{
                player_position.x + player_origin[0],
                player_position.y + player_size[1] + player_origin[1],
            };

            const player_br: [2]f32 = .{
                player_position.x + player_size[0] + player_origin[0],
                player_position.y + player_origin[1],
            };

            while (ecs.iter_next(it)) {
                var i: usize = 0;
                while (i < it.count()) : (i += 1) {
                    //const entity = it.entities()[i];

                    if (ecs.field(it, components.Position, 2)) |positions| {
                        if (positions[i].x < -game.settings.tile_size or positions[i].x > game.settings.tile_size) continue;

                        if (ecs.field(it, components.SpriteRenderer, 3)) |renderers| {
                            const sprite = game.state.atlas.sprites[renderers[i].index];
                            var origin: [2]f32 = .{ @floatFromInt(sprite.origin[0]), @floatFromInt(sprite.origin[1]) };
                            const size: [2]f32 = .{ @floatFromInt(sprite.source[2]), @floatFromInt(sprite.source[3]) };
                            origin[0] = -origin[0];
                            origin[1] = -(origin[1]);
                            const renderer_tl: [2]f32 = .{
                                positions[i].x + origin[0],
                                positions[i].y + size[1] + origin[1],
                            };

                            const renderer_br: [2]f32 = .{
                                positions[i].x + size[0] + origin[0],
                                positions[i].y + origin[1],
                            };

                            if (player_tl[0] > renderer_br[0] or player_br[0] < renderer_tl[0]) continue;

                            if (player_tl[1] < renderer_br[1] or player_br[1] > renderer_tl[1]) continue;

                            if (ecs.field(it, components.Scroll, 4)) |scrolls| {
                                positions[i].x += scrolls[i].width / 2.0;
                                _ = ecs.set_pair(world, game.state.entities.player, ecs.id(components.Cooldown), ecs.id(components.Boost), components.Cooldown, .{
                                    .end = 5.0,
                                });
                            }
                        }
                    }
                }
            }
        }
    }
}

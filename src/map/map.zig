const std = @import("std");
const game = @import("../ab.zig");
const zm = @import("zmath");
const ecs = @import("zflecs");
const core = @import("mach-core");

pub fn load() void {
    const camera = game.state.camera;
    const camera_matrix = camera.frameBufferMatrix();
    const camera_tl = camera.screenToWorld(zm.f32x4s(0.0), camera_matrix);
    const camera_br = camera.screenToWorld(zm.f32x4(game.window_size[0], -game.window_size[1], 0, 0), camera_matrix);

    const world_width = (camera_br[0] - camera_tl[0]) * 4.0;

    { // Create sun

        const sunflare = ecs.new_id(game.state.world);

        _ = ecs.set(game.state.world, sunflare, game.components.Position, .{ .x = camera_br[0], .y = camera_tl[1], .z = 201.0 });
        _ = ecs.set(game.state.world, sunflare, game.components.SpriteRenderer, .{
            .index = game.assets.ab_atlas.light_big_0_main,
            .color = game.math.Color.initFloats(1.0, 1.0, 0.9, 1.0).toSlice(),
        });

        const sun = ecs.new_id(game.state.world);

        _ = ecs.set(game.state.world, sun, game.components.Position, .{ .x = camera_br[0], .y = camera_tl[1], .z = 20.0 });
        _ = ecs.set(game.state.world, sun, game.components.SpriteRenderer, .{
            .index = game.assets.ab_atlas.sun_0_main,
        });
    }

    { // Create clouds
        var count: usize = @intFromFloat(@ceil(world_width / game.settings.cloud_spacing));
        const width = @as(f32, @floatFromInt(count)) * game.settings.cloud_spacing;

        for (0..count) |index| {
            const i: f32 = @floatFromInt(index);
            const offset: f32 = (i - (@as(f32, @floatFromInt(count))) / 2.0) * game.settings.cloud_spacing + (game.settings.cloud_spacing / 2.0);
            const sprite_index: usize = if (@mod(index, 2) == 0) game.assets.ab_atlas.cloud_1_0_main else game.assets.ab_atlas.cloud_2_0_main;

            const cloud = ecs.new_id(game.state.world);

            _ = ecs.set(game.state.world, cloud, game.components.Position, .{ .x = offset, .y = game.settings.ground_height + 128.0 });
            _ = ecs.set(game.state.world, cloud, game.components.SpriteRenderer, .{
                .index = sprite_index,
                .flip_x = if (@mod(index, 4) == 0) true else false,
            });
            _ = ecs.set(game.state.world, cloud, game.components.Scroll, .{ .width = width, .speed = 10.0, .wait_on_player = false });
        }
    }

    { // Create ground tiles
        var count: usize = @intFromFloat(@ceil(world_width / game.settings.tile_size));
        const width = @as(f32, @floatFromInt(count)) * game.settings.tile_size;

        for (0..count) |index| {
            const i: f32 = @floatFromInt(index);
            const offset: f32 = (i - (@as(f32, @floatFromInt(count))) / 2.0) * game.settings.tile_size + (game.settings.tile_size / 2.0);
            const sprite_index: usize = if (@mod(index, 2) == 0) game.assets.ab_atlas.ground_grass_0_main else game.assets.ab_atlas.ground_grass_1_main;

            const ground = ecs.new_id(game.state.world);

            _ = ecs.set(game.state.world, ground, game.components.Position, .{ .x = offset, .y = game.settings.ground_height });
            _ = ecs.set(game.state.world, ground, game.components.SpriteRenderer, .{
                .index = sprite_index,
                .flip_x = if (@mod(index, 4) == 0) true else false,
            });
            _ = ecs.set(game.state.world, ground, game.components.Scroll, .{ .width = width });
        }
    }

    { // Create grass
        var count: usize = @intFromFloat(@ceil(world_width / 10.0));
        const width = @as(f32, @floatFromInt(count)) * 10.0;

        for (0..count) |index| {
            const i: f32 = @floatFromInt(index);
            const offset: f32 = (i - (@as(f32, @floatFromInt(count))) / 2.0) * 10.0 + (10.0 / 2.0);
            const sprite_index: usize = game.animations.grass_assorted_main[@intFromFloat(@mod(i, @as(f32, @floatFromInt(game.animations.grass_assorted_main.len))))];

            const grass = ecs.new_id(game.state.world);

            _ = ecs.set(game.state.world, grass, game.components.Position, .{ .x = offset, .y = game.settings.ground_height });
            _ = ecs.set(game.state.world, grass, game.components.SpriteRenderer, .{
                .index = sprite_index,
                .vert_mode = .top_sway,
            });
            _ = ecs.set(game.state.world, grass, game.components.Scroll, .{ .width = width });
        }
    }
}

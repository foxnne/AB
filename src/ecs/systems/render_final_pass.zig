const std = @import("std");
const zm = @import("zmath");
const ecs = @import("zflecs");
const game = @import("../../ab.zig");
const gfx = game.gfx;
const components = game.components;

pub fn system() ecs.system_desc_t {
    var desc: ecs.system_desc_t = .{};
    desc.callback = callback;
    return desc;
}

pub const FinalUniforms = extern struct {
    mvp: zm.Mat,
    output_channel: i32 = 0,
};

pub fn callback(it: *ecs.iter_t) callconv(.C) void {
    if (it.count() > 0) return;

    const uniforms = FinalUniforms{ .mvp = zm.transpose(game.state.camera.frameBufferMatrix()), .output_channel = @intFromEnum(game.state.output_channel) };

    game.state.batcher.begin(.{
        .pipeline_handle = game.state.pipeline_final,
        .bind_group_handle = game.state.bind_group_final,
        .clear_color = .{ .r = 1.0, .g = 1.0, .b = 1.0, .a = 0.0 },
    }) catch unreachable;

    game.state.batcher.texture(zm.f32x4(0.0, -128, 0, 0), &game.state.blur_textures[1], .{ .flip_y = true, .flip_x = true, .color = zm.f32x4(0.2, 0.9, 1.0, 0.5), .data = 1.0 }) catch unreachable;
    game.state.batcher.texture(zm.f32x4s(0), &game.state.output_diffuse, .{ .data = 0.0 }) catch unreachable;

    game.state.batcher.end(uniforms, game.state.uniform_buffer_final) catch unreachable;
}

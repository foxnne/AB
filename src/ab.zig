const std = @import("std");

const core = @import("mach-core");
const gpu = core.gpu;

const zstbi = @import("zstbi");
const zmath = @import("zmath");
const ecs = @import("zflecs");

const sysaudio = @import("mach-sysaudio");
const Opus = @import("mach-opus");

pub const App = @This();

timer: core.Timer,

pub const name: [:0]const u8 = "AB";
pub const version: std.SemanticVersion = .{ .major = 0, .minor = 1, .patch = 0 };

pub const assets = @import("assets.zig");
pub const animations = @import("animations.zig");
pub const shaders = @import("shaders.zig");
pub const settings = @import("settings.zig");

pub const fs = @import("tools/fs.zig");
pub const fa = @import("tools/font_awesome.zig");
pub const math = @import("math/math.zig");
pub const gfx = @import("gfx/gfx.zig");
pub const input = @import("input/input.zig");

pub const map = @import("map/map.zig");

pub const components = @import("ecs/components/components.zig");

// Constants from the blur.wgsl shader
const tile_dimension: u32 = 128;
const batch: [2]u32 = .{ 4, 4 };

// Currently hardcoded
const filter_size: u32 = 1;
const iterations: u32 = 3;
var block_dimension: u32 = tile_dimension - (filter_size - 1);

test {
    _ = zstbi;
    _ = math;
    _ = gfx;
    _ = input;
}

pub var state: *GameState = undefined;
pub var content_scale: [2]f32 = undefined;
pub var window_size: [2]f32 = undefined;
pub var framebuffer_size: [2]f32 = undefined;

var gpa = std.heap.GeneralPurposeAllocator(.{}){};

/// Holds the global game state.
pub const GameState = struct {
    allocator: std.mem.Allocator = undefined,
    hotkeys: input.Hotkeys = undefined,
    mouse: input.Mouse = undefined,
    root_path: [:0]const u8 = undefined,
    camera: gfx.Camera = undefined,
    atlas: gfx.Atlas = undefined,
    diffusemap: gfx.Texture = undefined,
    palette: gfx.Texture = undefined,
    bind_group_diffuse: *gpu.BindGroup = undefined,
    pipeline_diffuse: *gpu.RenderPipeline = undefined,
    bind_group_final: *gpu.BindGroup = undefined,
    pipeline_final: *gpu.RenderPipeline = undefined,
    pipeline_blur: *gpu.ComputePipeline = undefined,
    uniform_buffer_diffuse: *gpu.Buffer = undefined,
    uniform_buffer_final: *gpu.Buffer = undefined,
    output_diffuse: gfx.Texture = undefined,
    output_channel: Channel = .final,
    delta_time: f32 = 0.0,
    time: f32 = 0.0,
    batcher: gfx.Batcher = undefined,
    world: *ecs.world_t = undefined,
    entities: Entities = .{},
    sounds: Sounds = .{},
    blur_params_buffer: *gpu.Buffer = undefined,
    compute_constants: *gpu.BindGroup = undefined,
    compute_bind_group_0: *gpu.BindGroup = undefined,
    compute_bind_group_1: *gpu.BindGroup = undefined,
    compute_bind_group_2: *gpu.BindGroup = undefined,
    blur_textures: [2]gfx.Texture = undefined,
};

pub const Entities = struct {
    player: usize = 0,
};

pub const Sounds = struct {
    player: sysaudio.Player = undefined,
    ctx: sysaudio.Context = undefined,
    device: sysaudio.Device = undefined,
};

pub const Channel = enum(i32) {
    final = 0,
};

/// Registers all public declarations within the passed type
/// as components.
fn register(world: *ecs.world_t, comptime T: type) void {
    const decls = comptime std.meta.declarations(T);
    inline for (decls) |decl| {
        const Type = @field(T, decl.name);
        if (@TypeOf(Type) == type) {
            if (@sizeOf(Type) > 0) {
                ecs.COMPONENT(world, Type);
            } else ecs.TAG(world, Type);
        }
    }
}

pub fn init(app: *App) !void {
    const allocator = gpa.allocator();

    var path_buffer: [1024]u8 = undefined;
    const root_path = std.fs.selfExeDirPath(path_buffer[0..]) catch ".";

    state = try allocator.create(GameState);
    state.* = .{ .root_path = try allocator.dupeZ(u8, root_path) };

    try core.init(.{
        .title = name,
        .size = .{ .width = 1280, .height = 720 },
        //.display_mode = .borderless

    });

    const descriptor = core.descriptor;
    window_size = .{ @floatFromInt(core.size().width), @floatFromInt(core.size().height) };
    framebuffer_size = .{ @floatFromInt(descriptor.width), @floatFromInt(descriptor.height) };
    content_scale = .{
        framebuffer_size[0] / window_size[0],
        framebuffer_size[1] / window_size[1],
    };

    zstbi.init(allocator);

    state.allocator = allocator;

    // Images
    {
        state.palette = try gfx.Texture.loadFromFile(assets.ab_palette_png.path, .{});
        state.diffusemap = try gfx.Texture.loadFromFile(assets.ab_png.path, .{});
        state.atlas = try gfx.Atlas.loadFromFile(allocator, assets.ab_atlas.path);
        state.output_diffuse = try gfx.Texture.createEmpty(settings.design_width, settings.design_height, .{ .format = core.descriptor.format });

        for (state.blur_textures, 0..) |_, i| {
            state.blur_textures[i] = try gfx.Texture.createEmpty(settings.design_width, settings.design_height, .{ .storage_binding = true });
        }
    }

    // Sounds
    {
        state.sounds.ctx = try sysaudio.Context.init(null, allocator, .{});
        try state.sounds.ctx.refresh();

        state.sounds.device = state.sounds.ctx.defaultDevice(.playback) orelse return error.NoDevice;

        state.sounds.player = try state.sounds.ctx.createPlayer(state.sounds.device, writeCallback, .{});

        try state.sounds.player.start();
        try state.sounds.player.setVolume(0.5);
    }

    // Input and Rendering
    {
        state.hotkeys = try input.Hotkeys.initDefault(allocator);
        state.mouse = try input.Mouse.initDefault(allocator);
        state.camera = gfx.Camera.init(zmath.f32x4s(0.0));
        state.batcher = try gfx.Batcher.init(allocator, 1000);
    }

    app.* = .{
        .timer = try core.Timer.start(),
    };

    const diffuse_shader_module = core.device.createShaderModuleWGSL("diffuse.wgsl", @embedFile("shaders/diffuse.wgsl"));
    const final_shader_module = core.device.createShaderModuleWGSL("final.wgsl", @embedFile("shaders/final.wgsl"));
    const blur_shader_module = core.device.createShaderModuleWGSL("blur.wgsl", @embedFile("shaders/blur.wgsl"));

    const vertex_attributes = [_]gpu.VertexAttribute{
        .{ .format = .float32x3, .offset = @offsetOf(gfx.Vertex, "position"), .shader_location = 0 },
        .{ .format = .float32x2, .offset = @offsetOf(gfx.Vertex, "uv"), .shader_location = 1 },
        .{ .format = .float32x4, .offset = @offsetOf(gfx.Vertex, "color"), .shader_location = 2 },
        .{ .format = .float32x3, .offset = @offsetOf(gfx.Vertex, "data"), .shader_location = 3 },
    };
    const vertex_buffer_layout = gpu.VertexBufferLayout.init(.{
        .array_stride = @sizeOf(gfx.Vertex),
        .step_mode = .vertex,
        .attributes = &vertex_attributes,
    });

    const sampler = core.device.createSampler(&.{
        .mag_filter = .linear,
        .min_filter = .linear,
    });

    const blend = gpu.BlendState{
        .color = .{
            .operation = .add,
            .src_factor = .src_alpha,
            .dst_factor = .one_minus_src_alpha,
        },
        .alpha = .{
            .operation = .add,
            .src_factor = .src_alpha,
            .dst_factor = .one_minus_src_alpha,
        },
    };

    const blur_pipeline_descriptor = gpu.ComputePipeline.Descriptor{
        .compute = gpu.ProgrammableStageDescriptor{
            .module = blur_shader_module,
            .entry_point = "main",
        },
    };

    state.pipeline_blur = core.device.createComputePipeline(&blur_pipeline_descriptor);
    blur_shader_module.release();

    // the shader blurs the input texture in one direction,
    // depending on whether flip value is 0 or 1
    var flip: [2]*gpu.Buffer = undefined;
    for (flip, 0..) |_, i| {
        const buffer = core.device.createBuffer(&.{
            .usage = .{ .uniform = true },
            .size = @sizeOf(u32),
            .mapped_at_creation = .true,
        });

        const buffer_mapped = buffer.getMappedRange(u32, 0, 1);
        buffer_mapped.?[0] = @as(u32, @intCast(i));
        buffer.unmap();

        flip[i] = buffer;
    }

    const blur_params_buffer = core.device.createBuffer(&.{
        .size = 8,
        .usage = .{ .copy_dst = true, .uniform = true },
    });

    const blur_bind_group_layout0 = state.pipeline_blur.getBindGroupLayout(0);
    const blur_bind_group_layout1 = state.pipeline_blur.getBindGroupLayout(1);

    const compute_constants = core.device.createBindGroup(&gpu.BindGroup.Descriptor.init(.{
        .layout = blur_bind_group_layout0,
        .entries = &.{
            gpu.BindGroup.Entry.sampler(0, sampler),
            gpu.BindGroup.Entry.buffer(1, blur_params_buffer, 0, 8),
        },
    }));

    const compute_bind_group_0 = core.device.createBindGroup(&gpu.BindGroup.Descriptor.init(.{
        .layout = blur_bind_group_layout1,
        .entries = &.{
            gpu.BindGroup.Entry.textureView(1, state.output_diffuse.view_handle),
            gpu.BindGroup.Entry.textureView(2, state.blur_textures[0].view_handle),
            gpu.BindGroup.Entry.buffer(3, flip[0], 0, 4),
        },
    }));

    const compute_bind_group_1 = core.device.createBindGroup(&gpu.BindGroup.Descriptor.init(.{
        .layout = blur_bind_group_layout1,
        .entries = &.{
            gpu.BindGroup.Entry.textureView(1, state.blur_textures[0].view_handle),
            gpu.BindGroup.Entry.textureView(2, state.blur_textures[1].view_handle),
            gpu.BindGroup.Entry.buffer(3, flip[1], 0, 4),
        },
    }));

    const compute_bind_group_2 = core.device.createBindGroup(&gpu.BindGroup.Descriptor.init(.{
        .layout = blur_bind_group_layout1,
        .entries = &.{
            gpu.BindGroup.Entry.textureView(1, state.blur_textures[1].view_handle),
            gpu.BindGroup.Entry.textureView(2, state.blur_textures[0].view_handle),
            gpu.BindGroup.Entry.buffer(3, flip[0], 0, 4),
        },
    }));

    state.compute_constants = compute_constants;
    state.compute_bind_group_0 = compute_bind_group_0;
    state.compute_bind_group_1 = compute_bind_group_1;
    state.compute_bind_group_2 = compute_bind_group_2;

    blur_bind_group_layout0.release();
    blur_bind_group_layout1.release();
    sampler.release();
    flip[0].release();
    flip[1].release();

    const blur_params_buffer_data = [_]u32{ filter_size, block_dimension };
    core.queue.writeBuffer(blur_params_buffer, 0, &blur_params_buffer_data);

    const diffuse_color_target = gpu.ColorTargetState{
        .format = core.descriptor.format,
        .blend = &blend,
        .write_mask = gpu.ColorWriteMaskFlags.all,
    };
    const diffuse_fragment = gpu.FragmentState.init(.{
        .module = diffuse_shader_module,
        .entry_point = "frag_main",
        .targets = &.{diffuse_color_target},
    });

    const diffuse_pipeline_descriptor = gpu.RenderPipeline.Descriptor{
        .fragment = &diffuse_fragment,
        .vertex = gpu.VertexState.init(.{ .module = diffuse_shader_module, .entry_point = "vert_main", .buffers = &.{vertex_buffer_layout} }),
    };

    state.pipeline_diffuse = core.device.createRenderPipeline(&diffuse_pipeline_descriptor);

    state.uniform_buffer_diffuse = core.device.createBuffer(&.{
        .usage = .{ .copy_dst = true, .uniform = true },
        .size = @sizeOf(gfx.UniformBufferObject),
        .mapped_at_creation = .false,
    });

    state.bind_group_diffuse = core.device.createBindGroup(
        &gpu.BindGroup.Descriptor.init(.{
            .layout = state.pipeline_diffuse.getBindGroupLayout(0),
            .entries = &.{
                gpu.BindGroup.Entry.buffer(0, state.uniform_buffer_diffuse, 0, @sizeOf(gfx.UniformBufferObject)),
                gpu.BindGroup.Entry.textureView(1, state.diffusemap.view_handle),
                gpu.BindGroup.Entry.textureView(2, state.palette.view_handle),
                gpu.BindGroup.Entry.sampler(3, state.diffusemap.sampler_handle),
            },
        }),
    );

    const final_color_target = gpu.ColorTargetState{
        .format = core.descriptor.format,
        .blend = &blend,
        .write_mask = gpu.ColorWriteMaskFlags.all,
    };

    const final_fragment = gpu.FragmentState.init(.{
        .module = final_shader_module,
        .entry_point = "frag_main",
        .targets = &.{final_color_target},
    });

    const final_pipeline_descriptor = gpu.RenderPipeline.Descriptor{
        .fragment = &final_fragment,
        .vertex = gpu.VertexState.init(.{ .module = final_shader_module, .entry_point = "vert_main", .buffers = &.{vertex_buffer_layout} }),
    };

    state.pipeline_final = core.device.createRenderPipeline(&final_pipeline_descriptor);

    const FinalUniformObject = @import("ecs/systems/render_final_pass.zig").FinalUniforms;

    state.uniform_buffer_final = core.device.createBuffer(&.{
        .usage = .{ .copy_dst = true, .uniform = true },
        .size = @sizeOf(FinalUniformObject),
        .mapped_at_creation = .false,
    });

    state.bind_group_final = core.device.createBindGroup(
        &gpu.BindGroup.Descriptor.init(.{
            .layout = state.pipeline_final.getBindGroupLayout(0),
            .entries = &.{
                gpu.BindGroup.Entry.buffer(0, state.uniform_buffer_final, 0, @sizeOf(FinalUniformObject)),
                gpu.BindGroup.Entry.textureView(1, state.output_diffuse.view_handle),
                gpu.BindGroup.Entry.sampler(2, state.output_diffuse.sampler_handle),
                gpu.BindGroup.Entry.textureView(3, state.blur_textures[1].view_handle),
            },
        }),
    );

    state.world = ecs.init();
    register(state.world, components);

    // - Input
    var input_jump_system = @import("ecs/systems/input_jump.zig").system();
    ecs.SYSTEM(state.world, "InputJumpSystem", ecs.OnUpdate, &input_jump_system);

    // - Gameplay
    var cooldown_system = @import("ecs/systems/cooldown.zig").system();
    ecs.SYSTEM(state.world, "CooldownSystem", ecs.OnUpdate, &cooldown_system);
    var jump_system = @import("ecs/systems/jump.zig").system();
    ecs.SYSTEM(state.world, "JumpSystem", ecs.OnUpdate, &jump_system);
    var scroll_system = @import("ecs/systems/scroll.zig").system();
    ecs.SYSTEM(state.world, "ScrollSystem", ecs.OnUpdate, &scroll_system);
    var apple_system = @import("ecs/systems/apple.zig").system();
    ecs.SYSTEM(state.world, "AppleSystem", ecs.OnUpdate, &apple_system);

    // - Animation
    var animation_sprite_system = @import("ecs/systems/animation_sprite.zig").system();
    ecs.SYSTEM(state.world, "AnimationSpriteSystem", ecs.OnUpdate, &animation_sprite_system);
    var animation_player_system = @import("ecs/systems/animation_player.zig").system();
    ecs.SYSTEM(state.world, "AnimationPlayerSystem", ecs.OnUpdate, &animation_player_system);
    var animation_particle_system = @import("ecs/systems/animation_particle.zig").system();
    ecs.SYSTEM(state.world, "AnimationParticleSystem", ecs.OnUpdate, &animation_particle_system);

    // - Rendering
    var render_diffuse_system = @import("ecs/systems/render_diffuse_pass.zig").system();
    ecs.SYSTEM(state.world, "RenderDiffuseSystem", ecs.PostUpdate, &render_diffuse_system);
    var render_final_system = @import("ecs/systems/render_final_pass.zig").system();
    ecs.SYSTEM(state.world, "RenderFinalSystem", ecs.PostUpdate, &render_final_system);

    map.load();

    state.entities.player = ecs.new_id(state.world);
    _ = ecs.add(state.world, state.entities.player, components.Player);
    _ = ecs.set(state.world, state.entities.player, components.Position, .{ .x = 0.0, .y = settings.ground_height, .z = -20.0 });
    _ = ecs.set(state.world, state.entities.player, components.PlayerRenderer, .{
        .index_body = assets.ab_atlas.character_idle_0_main,
        .index_tail = assets.ab_atlas.character_idle_1_tail,
    });
    _ = ecs.set(state.world, state.entities.player, components.PlayerAnimator, .{
        .animation_body = &animations.character_idle_main,
        .animation_tail = &animations.character_idle_tail,
        .fps = 8,
        .state = .play,
    });
    _ = ecs.set(state.world, state.entities.player, components.Direction, .e);

    _ = ecs.set(state.world, state.entities.player, components.ParticleRenderer, .{
        .particles = state.allocator.alloc(components.ParticleRenderer.Particle, 500) catch unreachable,
        .offset = .{ -5.0, 2.0, 0.0, 0.0 },
    });

    _ = ecs.set(state.world, state.entities.player, components.ParticleAnimator, .{
        .animation = &animations.squares_main,
        .rate = 80.0,
        .velocity_min = .{ -100.0, 0.0 },
        .velocity_max = .{ -200.0, 40.0 },
        .start_color = math.Color.initFloats(1.0, 0.3, 0.3, 1.0).toSlice(),
        .end_color = math.Color.initFloats(0.3, 0.3, 1.0, 0.5).toSlice(),
        .start_life = 1.5,
        .state = .pause,
    });
}

pub fn updateMainThread(_: *App) !bool {
    return false;
}

pub fn update(app: *App) !bool {
    state.delta_time = app.timer.lap();
    state.time += state.delta_time;

    var iter = core.pollEvents();
    while (iter.next()) |event| {
        switch (event) {
            .key_press => |key_press| {
                state.hotkeys.setHotkeyState(key_press.key, key_press.mods, .press);
            },
            .key_repeat => |key_repeat| {
                state.hotkeys.setHotkeyState(key_repeat.key, key_repeat.mods, .repeat);
            },
            .key_release => |key_release| {
                state.hotkeys.setHotkeyState(key_release.key, key_release.mods, .release);
            },
            .mouse_scroll => |mouse_scroll| {
                state.mouse.scroll_x = mouse_scroll.xoffset;
                state.mouse.scroll_y = mouse_scroll.yoffset;
            },
            .mouse_motion => |mouse_motion| {
                state.mouse.position = .{ @floatCast(mouse_motion.pos.x * content_scale[0]), @floatCast(mouse_motion.pos.y * content_scale[1]) };
            },
            .mouse_press => |mouse_press| {
                state.mouse.setButtonState(mouse_press.button, mouse_press.mods, .press);
            },
            .mouse_release => |mouse_release| {
                state.mouse.setButtonState(mouse_release.button, mouse_release.mods, .release);
            },
            .close => {
                return true;
            },
            .framebuffer_resize => |size| {
                const descriptor = core.descriptor;
                window_size = .{ @floatFromInt(size.width), @floatFromInt(size.height) };
                framebuffer_size = .{ @floatFromInt(descriptor.width), @floatFromInt(descriptor.height) };
                content_scale = .{
                    framebuffer_size[0] / window_size[0],
                    framebuffer_size[1] / window_size[1],
                };

                state.camera.zoom = gfx.Camera.minZoom();
            },
            else => {},
        }
    }

    const descriptor = core.descriptor;
    window_size = .{ @floatFromInt(core.size().width), @floatFromInt(core.size().height) };
    framebuffer_size = .{ @floatFromInt(descriptor.width), @floatFromInt(descriptor.height) };
    content_scale = .{
        framebuffer_size[0] / window_size[0],
        framebuffer_size[1] / window_size[1],
    };

    try input.process();

    _ = ecs.progress(state.world, 0);

    const batcher_commands = try state.batcher.finish();
    defer batcher_commands.release();

    const encoder = core.device.createCommandEncoder(null);

    const compute_pass = encoder.beginComputePass(null);
    compute_pass.setPipeline(state.pipeline_blur);
    compute_pass.setBindGroup(0, state.compute_constants, &.{});

    const width: u32 = settings.design_width;
    const height: u32 = settings.design_height;
    compute_pass.setBindGroup(1, state.compute_bind_group_0, &.{});
    compute_pass.dispatchWorkgroups(try std.math.divCeil(u32, width, block_dimension), try std.math.divCeil(u32, height, batch[1]), 1);

    compute_pass.setBindGroup(1, state.compute_bind_group_1, &.{});
    compute_pass.dispatchWorkgroups(try std.math.divCeil(u32, height, block_dimension), try std.math.divCeil(u32, width, batch[1]), 1);

    var i: u32 = 0;
    while (i < iterations - 1) : (i += 1) {
        compute_pass.setBindGroup(1, state.compute_bind_group_2, &.{});
        compute_pass.dispatchWorkgroups(try std.math.divCeil(u32, width, block_dimension), try std.math.divCeil(u32, height, batch[1]), 1);

        compute_pass.setBindGroup(1, state.compute_bind_group_1, &.{});
        compute_pass.dispatchWorkgroups(try std.math.divCeil(u32, height, block_dimension), try std.math.divCeil(u32, width, batch[1]), 1);
    }
    compute_pass.end();
    compute_pass.release();

    var command = encoder.finish(null);
    encoder.release();

    core.queue.submit(&.{ batcher_commands, command });
    command.release();
    core.swap_chain.present();

    for (state.hotkeys.hotkeys) |*hotkey| {
        hotkey.previous_state = hotkey.state;
    }

    for (state.mouse.buttons) |*button| {
        button.previous_state = button.state;
    }

    state.mouse.previous_position = state.mouse.position;

    return false;
}

pub fn deinit(_: *App) void {
    state.sounds.ctx.deinit();
    state.sounds.player.deinit();
    state.allocator.free(state.hotkeys.hotkeys);
    state.diffusemap.deinit();
    state.blur_textures[0].deinit();
    state.blur_textures[1].deinit();
    state.palette.deinit();
    state.output_diffuse.deinit();
    state.atlas.deinit(state.allocator);
    zstbi.deinit();
    state.allocator.free(state.root_path);
    state.allocator.destroy(state);
    core.deinit();
}

// var idle_i: usize = 0;
// var rev_i: usize = 0;
// var release_i: usize = 0;
// var birds_i: usize = 0;
// var sparkles_i: usize = 0;
// var rev_swap: usize = 0;
// var music_i: usize = 0;
fn writeCallback(_: ?*anyopaque, frames: usize) void {
    for (0..frames) |_| {
        // const channels = state.sounds.engine_idle.channels;
        // for (0..channels) |_| {
        //     birds_i += 1;
        //     if (state.sounds.play_sparkles)
        //         sparkles_i += 1;
        //     if (birds_i >= state.sounds.birds_idle.samples.len) birds_i = 0;
        //     if (sparkles_i >= state.sounds.sparkles.samples.len) sparkles_i = 0;
        //     idle_i += 1;
        //     if (idle_i >= state.sounds.engine_idle.samples.len) idle_i = 0;
        //     music_i += 1;
        //     if (music_i >= state.sounds.music.samples.len) music_i = 0;
        // }

        // if (state.sounds.play_engine_rev) {
        //     idle_i += 1;
        //     if (idle_i >= state.sounds.engine_idle.samples.len) idle_i = 0;
        //     const rev_sound = if (@mod(rev_swap, 2) == 0) state.sounds.engine_rev_1 else state.sounds.engine_rev_2;

        //     if (rev_i >= rev_sound.samples.len) {
        //         rev_i = 0;
        //         state.sounds.play_engine_rev = false;
        //     }

        //     const fade_in: f32 = @min(1.0, @as(f32, @floatFromInt(rev_i / 10)));
        //     const fade_out: f32 = 1.0 - @min(1.0, @as(f32, @floatFromInt(rev_i / rev_sound.samples.len)));

        //     for (0..channels) |ch| {
        //         var sample = rev_sound.samples[rev_i] * fade_in * fade_out + state.sounds.birds_idle.samples[birds_i] * 3.0 + state.sounds.engine_idle.samples[idle_i] * 2.0 + state.sounds.music.samples[music_i] * 0.5;
        //         if (state.sounds.play_sparkles) {
        //             sample = rev_sound.samples[rev_i] * fade_in * fade_out + state.sounds.sparkles.samples[sparkles_i] + state.sounds.engine_idle.samples[idle_i] * 2.0 + state.sounds.music.samples[music_i] * 0.5;
        //         }
        //         state.sounds.player.write(state.sounds.player.channels()[ch], fi, sample);
        //         rev_i += 1;
        //     }
        //     idle_i = 0;
        //     continue;
        // }
        // if (state.sounds.play_engine_release) {
        //     idle_i += 1;
        //     if (idle_i >= state.sounds.engine_idle.samples.len) idle_i = 0;
        //     const release_sound = state.sounds.engine_release;

        //     if (release_i >= release_sound.samples.len) {
        //         release_i = 0;
        //         state.sounds.play_engine_release = false;
        //     }

        //     const fade_in: f32 = @min(1.0, @as(f32, @floatFromInt(release_i / 10)));
        //     const fade_out: f32 = 1.0 - @min(1.0, @as(f32, @floatFromInt(release_i / release_sound.samples.len)));

        //     for (0..channels) |ch| {
        //         var sample = release_sound.samples[release_i] * fade_in * fade_out + state.sounds.birds_idle.samples[birds_i] * 3.0 + state.sounds.engine_idle.samples[idle_i] * 2.0 + state.sounds.music.samples[music_i] * 0.5;
        //         if (state.sounds.play_sparkles) {
        //             sample = release_sound.samples[release_i] * fade_in * fade_out + state.sounds.sparkles.samples[sparkles_i] + state.sounds.engine_idle.samples[idle_i] * 2.0 + state.sounds.music.samples[music_i] * 0.5;
        //         }
        //         state.sounds.player.write(state.sounds.player.channels()[ch], fi, sample);
        //         release_i += 1;
        //     }
        //     idle_i = 0;
        //     continue;
        // }
        // {
        //     rev_swap += 1;
        //     rev_i = 0;
        //     release_i = 0;
        //     for (0..channels) |ch| {
        //         var sample = state.sounds.engine_idle.samples[idle_i] * 0.35 + state.sounds.birds_idle.samples[birds_i] * 3.0 + state.sounds.music.samples[music_i] * 0.5;
        //         if (state.sounds.play_sparkles) {
        //             sample = state.sounds.engine_idle.samples[idle_i] * 0.35 + state.sounds.sparkles.samples[sparkles_i] * 0.5 + state.sounds.music.samples[music_i] * 0.5;
        //         } else {
        //             sparkles_i = 0;
        //         }

        //         state.sounds.player.write(state.sounds.player.channels()[ch], fi, sample);
        //     }
        // }
    }
}

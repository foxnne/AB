const game = @import("../../ab.zig");
const gfx = game.gfx;
const math = game.math;

pub const SpriteRenderer = struct {
    index: usize = 0,
    flip_x: bool = false,
    flip_y: bool = false,
    scale: [2]f32 = .{ 1.0, 1.0 },
    color: [4]f32 = math.Colors.white.toSlice(),
    frag_mode: gfx.Batcher.SpriteOptions.FragRenderMode = .standard,
    vert_mode: gfx.Batcher.SpriteOptions.VertRenderMode = .standard,
    order: usize = 0,
};

pub const SpriteAnimator = struct {
    animation: []usize,
    frame: usize = 0,
    elapsed: f32 = 0,
    fps: usize = 8,
    state: State = State.pause,

    pub const State = enum {
        pause,
        play,
    };
};

pub const PlayerRenderer = struct {
    index_body: usize = 0,
    index_tail: usize = 0,
    flip_x: bool = false,
    flip_y: bool = false,
    scale: [2]f32 = .{ 1.0, 1.0 },
    color: [4]f32 = math.Colors.white.toSlice(),
    frag_mode: gfx.Batcher.SpriteOptions.FragRenderMode = .standard,
    vert_mode: gfx.Batcher.SpriteOptions.VertRenderMode = .standard,
    order: usize = 0,
};

pub const PlayerAnimator = struct {
    animation_body: []usize,
    animation_tail: []usize,
    frame: usize = 0,
    elapsed: f32 = 0,
    fps: usize = 8,
    state: State = State.pause,

    pub const State = enum {
        pause,
        play,
    };
};

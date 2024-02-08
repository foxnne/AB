const zmath = @import("zmath");
const game = @import("../../ab.zig");

pub const Player = struct {
    state: State = .idle,
    speed: f32 = 0.0,

    pub const State = enum {
        idle,
        run,
        jump,
    };
};

pub const Jump = struct {
    elapsed: f32 = 0.0,
    tail_offset: f32 = 0.0,
};

pub const Apple = struct {};
pub const Boost = struct {};

pub const Speed = struct {
    value: f32 = 0.0,
};

pub const Scroll = struct {
    speed: f32 = game.settings.scroll_speed,
    width: f32,
    wait_on_player: bool = true,
};
pub const Request = struct {};
pub const Target = struct {};
pub const Event = struct {};

pub const Trigger = struct { direction: game.math.Direction };
pub const Direction = game.math.Direction;
pub const Rotation = struct { value: f32 = 0 };

pub const Cooldown = struct { current: f32 = 0.0, end: f32 = 5.0 };

pub const Hitpoints = struct { value: usize = 0 };

pub const Position = struct {
    x: f32 = 0.0,
    y: f32 = 0.0,
    z: f32 = 0.0,

    /// Returns the position as a vector.
    pub fn toF32x4(self: Position) zmath.F32x4 {
        return zmath.f32x4(self.x, self.y, self.z, 0.0);
    }
};

const sprites = @import("sprites.zig");
pub const SpriteRenderer = sprites.SpriteRenderer;
pub const SpriteAnimator = sprites.SpriteAnimator;

pub const PlayerRenderer = sprites.PlayerRenderer;
pub const PlayerAnimator = sprites.PlayerAnimator;

const particles = @import("particles.zig");
pub const ParticleRenderer = particles.ParticleRenderer;
pub const ParticleAnimator = particles.ParticleAnimator;

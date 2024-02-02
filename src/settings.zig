const std = @import("std");
const zm = @import("zmath");

/// The design texture width for render-textures.
pub const design_width: u32 = 1280;

/// The design texture height for render-textures.
pub const design_height: u32 = 720;

/// The design texture size for render-textures as an f32x4.
pub const design_size = zm.f32x4(@floatFromInt(design_width), @floatFromInt(design_height), 0, 0);

/// Tile size
pub const tile_size: f32 = 32.0;

pub const cloud_spacing: f32 = 240.0;

/// Height where ground sits
pub const ground_height: f32 = -48.0;

pub const scroll_speed: f32 = 100.0;

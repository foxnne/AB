const std = @import("std");
const zm = @import("zmath");
const zgpu = @import("zgpu");
const zglfw = @import("zglfw");
const game = @import("../ab.zig");

pub const Camera = struct {
    zoom: f32 = 1.0,
    position: zm.F32x4 = zm.f32x4s(0),
    previous_position: zm.F32x4 = zm.f32x4s(0),
    velocity: f32 = 0.0,
    culling_margin: f32 = 256.0,

    pub fn init(position: zm.F32x4) Camera {
        const zooms = zm.ceil(zm.f32x4(game.window_size[0], game.window_size[1], 0, 0) / game.settings.design_size);
        const zoom = @max(zooms[0], zooms[1]) + 1.0 * game.content_scale[0]; // Initially set the zoom to be 1 step greater than minimum.

        return .{
            .zoom = zoom,
            .position = position,
        };
    }

    /// Use this matrix when drawing to the framebuffer.
    pub fn frameBufferMatrix(camera: Camera) zm.Mat {
        const fb_ortho = zm.orthographicLh(game.window_size[0], game.window_size[1], -100, 100);
        const fb_scaling = zm.scaling(camera.zoom, camera.zoom, 1);
        const fb_translation = zm.translation(-game.settings.design_size[0] / 2 * camera.zoom, -game.settings.design_size[1] / 2 * camera.zoom, 1);

        return zm.mul(fb_scaling, zm.mul(fb_translation, fb_ortho));
    }

    /// Use this matrix when drawing to an off-screen render texture.
    pub fn renderTextureMatrix(camera: Camera) zm.Mat {
        const rt_ortho = zm.orthographicLh(game.settings.design_size[0], game.settings.design_size[1], -100, 100);
        const rt_translation = zm.translation(-camera.position[0], -camera.position[1], 0);

        return zm.mul(rt_translation, rt_ortho);
    }

    /// Transforms a position from screen-space to world-space.
    /// Remember that in screen-space positive Y is down, and positive Y is up in world-space.
    pub fn screenToWorld(camera: Camera, position: zm.F32x4, fb_mat: zm.Mat) zm.F32x4 {
        const ndc = zm.mul(fb_mat, zm.f32x4(position[0], -position[1], 1, 1)) / zm.f32x4(camera.zoom * 2, camera.zoom * 2, 1, 1) + zm.f32x4(-0.5, 0.5, 1, 1);
        const world = ndc * zm.f32x4(game.window_size[0] / camera.zoom, game.window_size[1] / camera.zoom, 1, 1) - zm.f32x4(-camera.position[0], -camera.position[1], 1, 1);

        return zm.f32x4(world[0], world[1], 0, 0);
    }

    /// Transforms a position from world-space to screen-space.
    /// Remember that in screen-space positive Y is down, and positive Y is up in world-space.
    pub fn worldToScreen(camera: Camera, position: zm.F32x4) zm.F32x4 {
        const cs = game.state.gctx.window.getContentScale();
        const screen = (camera.position - position) * zm.f32x4(camera.zoom * cs[0], camera.zoom * cs[1], 0, 0) - zm.f32x4((game.window_size[0] / 2) * cs[0], (-game.window_size[1] / 2) * cs[1], 0, 0);

        return zm.f32x4(-screen[0], screen[1], 0, 0);
    }

    /// Returns the minimum zoom needed to render to the window without black bars.
    pub fn minZoom() f32 {
        const zoom = zm.ceil(zm.f32x4(game.window_size[0], game.window_size[1], 0.0, 0.0) / game.settings.design_size);
        return @max(zoom[0], zoom[1]) * game.content_scale[0];
    }

    /// Returns the maximum zoom allowed for the current window size.
    pub fn maxZoom() f32 {
        const min = minZoom();
        return min + game.settings.max_zoom_offset;
    }
};

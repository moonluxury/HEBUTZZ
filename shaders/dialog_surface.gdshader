shader_type canvas_item;
render_mode unshaded, blend_disabled;

// Preserve straight RGB and coverage for the embedded Window compositor.
// Child controls keep their own normal blending over the opaque panel interior.

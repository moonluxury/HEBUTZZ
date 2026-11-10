shader_type canvas_item;
render_mode unshaded;
uniform sampler2D front_image : source_color, filter_linear_mipmap, repeat_disable;
uniform sampler2D back_image : source_color, filter_linear_mipmap, repeat_disable;
uniform float front_aspect = 0.6666667;
uniform float back_aspect = 0.6666667;
uniform float turn = 0.0;
uniform float perspective = 5.0;
uniform float expansion = 1.16;
uniform vec2 card_size = vec2(240.0, 360.0);
uniform bool crossfade = false;
uniform float blend_amount = 0.0;
uniform bool grayscale = false;
varying vec4 tint;

vec4 fitted(sampler2D source, vec2 uv, float aspect) {
    float container_aspect = card_size.x / max(card_size.y, 1.0);
    vec2 fit = vec2(min(1.0, aspect / container_aspect), min(1.0, container_aspect / aspect));
    vec2 sample_uv = (uv - 0.5) / fit + 0.5;
    if (any(lessThan(sample_uv, vec2(0.0))) || any(greaterThan(sample_uv, vec2(1.0)))) return vec4(0.0);
    return texture(source, sample_uv);
}
void vertex() {
    tint = COLOR;
    VERTEX = (VERTEX - card_size * 0.5) * expansion + card_size * 0.5;
}
void fragment() {
    float ratio = card_size.y / max(card_size.x, 1.0);
    vec2 screen = (UV - 0.5) * vec2(expansion, expansion * ratio);
    vec4 ink = vec4(0.0);
    if (crossfade) {
        vec2 uv = (UV - 0.5) * expansion + 0.5;
        vec4 a = fitted(back_image, uv, back_aspect);
        vec4 b = fitted(front_image, uv, front_aspect);
        if (grayscale) b.rgb = vec3(dot(b.rgb, vec3(0.2126, 0.7152, 0.0722)));
        // Premultiplied interpolation preserves both PNGs' transparent edges.
        float alpha = mix(a.a, b.a, blend_amount);
        ink = vec4(mix(a.rgb * a.a, b.rgb * b.a, blend_amount) / max(alpha, 0.0001), alpha);
    } else {
        float c = cos(turn);
        float s = sin(turn);
        float denominator = perspective * c - screen.x * s;
        if (abs(c) > 0.0001 && abs(denominator) > 0.0001) {
            float x = screen.x * perspective / denominator;
            float y = screen.y * (perspective + x * s) / perspective;
            bool front = c < 0.0;
            vec2 uv = vec2((front ? -x : x) + 0.5, y / ratio + 0.5);
            ink = front ? fitted(front_image, uv, front_aspect) : fitted(back_image, uv, back_aspect);
            if (front && grayscale) ink.rgb = vec3(dot(ink.rgb, vec3(0.2126, 0.7152, 0.0722)));
        }
    }
    // One projected face: parent fades never flatten or overlap 3D faces.
    COLOR = ink * tint;
}

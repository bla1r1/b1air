#version 440
// Ui/LiquidGlass: liquid glass, after Apple's Human Interface Guidelines
// (Materials, Color).
//
// - regular: what is behind is blurred and its luminosity held in a range, so
//   text on it stays legible over anything; for bars, sidebars, popovers.
// - clear: highly translucent, for controls over photos and video; over
//   something bright, a 35% dimming layer.
// - a thin line of light on the edge, brighter where it faces the light, and
//   what is behind bent toward the middle only near the rim;
// - pressed, it lights from within, from under the pointer outward;
// - Increase Contrast: a firmer edge. (Reduce Transparency is the flat pane
//   LiquidGlass draws instead; `solid` blends towards `base` for a pane
//   that wants a little of it anyway.)
//
// `source` is what is behind, blurred, with `pad` pixels more on every side
// than the glass: a blur reaching past what it was given fades dark there.
//
// Compiled to liquid.frag.qsb by tools/build-shaders.sh; both are in the tree.

layout(location = 0) in vec2 qt_TexCoord0;
layout(location = 0) out vec4 fragColor;

layout(std140, binding = 0) uniform buf {
    mat4 qt_Matrix;
    float qt_Opacity;
    vec2 size;        // the glass, in pixels
    float radius;     // its corners
    float refraction; // how far the rim pulls what is behind, in pixels
    float bevel;      // how deep the curved rim is, in pixels
    float rim;        // the line of light on the edge, 0..1
    float dispersion; // the colour split at the rim, 0..1
    float pad;        // the source's extra pixels on each side
    float regular;    // 1 regular, 0 clear
    float solid;      // 0..1 towards an opaque `base`
    float contrast;   // Increase Contrast, 0..1
    float caustic;    // light gathered inside the edge facing away, 0..1
    float glow;      // pressed: light from within, 0..1
    vec2 glowPos;     // where it was pressed, in pixels
    vec4 tint;        // a colour over it, alpha the amount
    vec4 base;        // the opaque colour `solid` blends to
};
layout(binding = 1) uniform sampler2D source;

float roundBox(vec2 p, vec2 b, float r) {
    vec2 q = abs(p) - b + r;
    return length(max(q, 0.0)) + min(max(q.x, q.y), 0.0) - r;
}

vec2 at(vec2 px) {
    return (px + pad) / (size + 2.0 * pad);
}

float luma(vec3 c) { return dot(c, vec3(0.2126, 0.7152, 0.0722)); }

void main() {
    vec2 half_ = size * 0.5;
    vec2 px = qt_TexCoord0 * size;
    vec2 p = px - half_;
    float d = roundBox(p, half_, radius);          // < 0 inside
    float cover = clamp(0.5 - d, 0.0, 1.0);        // a one-pixel smooth edge
    if (cover <= 0.0) { fragColor = vec4(0.0); return; }

    vec2 e = vec2(1.0, 0.0);
    vec2 n = vec2(roundBox(p + e.xy, half_, radius) - roundBox(p - e.xy, half_, radius),
                  roundBox(p + e.yx, half_, radius) - roundBox(p - e.yx, half_, radius));
    n = normalize(n + 1e-6);

    float depth = clamp(-d / bevel, 0.0, 1.0);
    float curve = pow(1.0 - depth, 2.0);
    vec2 pull = -n * refraction * curve * (1.0 - solid);
    float split = dispersion * curve;

    vec4 r = texture(source, at(px + pull * (1.0 + split)));
    vec4 g = texture(source, at(px + pull));
    vec4 b = texture(source, at(px + pull * (1.0 - split)));
    vec4 c = vec4(r.r, g.g, b.b, g.a);

    // One judgement for the whole element, on a 5 x 3 grid, so it dims as a
    // whole and agrees with its labels (labels.frag).
    vec3 around = vec3(0.0);
    for (int i = 0; i < 5; ++i)
        for (int j = 0; j < 3; ++j)
            around += texture(source, at(size * vec2((float(i) + 0.5) / 5.0, (float(j) + 0.5) / 3.0))).rgb;
    around /= 15.0;
    float light = smoothstep(0.55, 0.85, luma(around));

    // Regular: luminosity held in a range — the brightest pulled down, the
    // darkest lifted a little — so labels read over anything.
    vec3 held = 0.07 * c.a + c.rgb * 0.62;
    c.rgb = mix(c.rgb, held, regular);
    // Clear over something bright: the 35% dimming layer.
    c.rgb *= 1.0 - 0.35 * light * (1.0 - regular);

    c = c * (1.0 - tint.a) + vec4(tint.rgb * tint.a, tint.a);

    c = mix(c, vec4(base.rgb, 1.0), solid * 0.92);

    // The edge: a line of light a pixel and a half wide, and a soft glow just
    // inside it; firmer with Increase Contrast.
    vec2 lightDir = normalize(vec2(-0.5, -0.86));
    float facing = dot(n, lightDir);
    // Brightest where it faces the light, and again, less, on the far
    // edge, where the light that came through leaves it.
    float along = 0.25 + 0.75 * pow(max(facing, 0.0), 1.5) + 0.45 * pow(max(-facing, 0.0), 1.5);
    float line = 1.0 - smoothstep(0.0, 1.5, -d);
    float glowRim = (1.0 - smoothstep(0.0, 6.0, -d)) * 0.25;
    float h = rim * along * (line + glowRim) + contrast * 0.35 * line;
    c += vec4(vec3(h), h);

    // What makes it glass rather than a sheet of Air: the light that came in
    // through the lit edge, gathered along the edge facing away from it, as
    // a drop of water is brightest at its foot. A soft band inside the rim,
    // never on the line itself.
    float band = smoothstep(1.0, 3.0, -d) * (1.0 - smoothstep(3.0, bevel * 1.6, -d));
    float gathered = caustic * 0.4 * max(-facing, 0.0) * band;
    c += vec4(vec3(gathered), gathered);

    // Its body: lit through the top, a sheen fading out by the middle, and
    // a touch deeper below it, above the bright foot. Over a flat backdrop
    // (the dark theme's Air) nothing bends, and without this the glass was
    // a grey pill.
    float y = px.y / size.y;
    float inside = smoothstep(0.0, 2.0, -d);
    float sheen = caustic * 0.13 * pow(clamp(1.0 - y * 1.8, 0.0, 1.0), 2.0) * inside;
    c += vec4(vec3(sheen), sheen);
    c.rgb *= 1.0 - caustic * 0.08 * smoothstep(0.45, 1.0, y) * inside;

    // Pressed: lit from within, from under the pointer outward.
    float spread = length(px - glowPos) / max(size.x, size.y);
    float lit = glow * (0.22 * exp(-spread * 3.0) + 0.06);
    c += vec4(vec3(lit), lit);

    fragColor = clamp(c, 0.0, 1.0) * cover * qt_Opacity;
}

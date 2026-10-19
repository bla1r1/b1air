#version 440
// Ui/LiquidGlass: labels on small glass, monochrome and adaptive (Apple, Color
// → Liquid Glass color): darker when what is behind is light, lighter when
// it is dark. Judged once for the whole element, as Apple flips a small
// element as a whole. Only the grey of the labels changes; anything
// coloured keeps its colour (an accent pill and its text stay as they are).
//
// Compiled to labels.frag.qsb by tools/build-shaders.sh; both are in the tree.

layout(location = 0) in vec2 qt_TexCoord0;
layout(location = 0) out vec4 fragColor;

layout(std140, binding = 0) uniform buf {
    mat4 qt_Matrix;
    float qt_Opacity;
    vec2 size;
    float pad;
    float amount;   // 0 off .. 1
};
layout(binding = 1) uniform sampler2D source;    // the labels, as drawn
layout(binding = 2) uniform sampler2D behind;    // what is behind the glass

vec2 at(vec2 px) { return (px + pad) / (size + 2.0 * pad); }

void main() {
    vec4 l = texture(source, qt_TexCoord0);
    vec3 around = vec3(0.0);
    for (int i = 0; i < 5; ++i)
        for (int j = 0; j < 3; ++j)
            around += texture(behind, at(size * vec2((float(i) + 0.5) / 5.0, (float(j) + 0.5) / 3.0))).rgb;
    around /= 15.0;
    float light = smoothstep(0.5, 0.7, dot(around, vec3(0.2126, 0.7152, 0.0722))) * amount;
    vec3 rgb = l.a > 0.0 ? l.rgb / l.a : vec3(0.0);
    float grey = 1.0 - smoothstep(0.05, 0.2, max(max(rgb.r, rgb.g), rgb.b) - min(min(rgb.r, rgb.g), rgb.b));
    vec3 dark = vec3(0.11, 0.12, 0.13);
    vec3 outRgb = mix(rgb, dark, light * grey);
    fragColor = vec4(outRgb * l.a, l.a) * qt_Opacity;
}

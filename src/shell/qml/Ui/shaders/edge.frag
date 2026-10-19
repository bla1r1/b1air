#version 440
// Ui/ScrollEdge: what scrolls under a toolbar, blurred (by the caller), full
// under the bar and fading smoothly to nothing below it — Apple's scroll
// edge effect, with no line where it stops.
//
// Compiled to edge.frag.qsb by tools/build-shaders.sh; both are in the tree.

layout(location = 0) in vec2 qt_TexCoord0;
layout(location = 0) out vec4 fragColor;

layout(std140, binding = 0) uniform buf {
    mat4 qt_Matrix;
    float qt_Opacity;
    vec2 size;       // the effect, in pixels
    float pad;       // the blurred source's extra pixels on each side
    float full;      // how far down it stays full, in pixels
    vec4 base;       // the surface colour the blurred copy is laid on
};
layout(binding = 1) uniform sampler2D source;

void main() {
    vec2 px = qt_TexCoord0 * size;
    vec4 c = texture(source, (px + pad) / (size + 2.0 * pad));
    vec4 wash = vec4(base.rgb, 1.0) * base.a;
    c = c + wash * (1.0 - c.a);
    float k = 1.0 - smoothstep(full, size.y, px.y);
    fragColor = c * k * qt_Opacity;
}

#version 330 core
out vec4 fragColor;

// Additional information for lighting
in vec4 color;
in vec4 position_worldSpace;

uniform int cube = 0;
uniform float red = 1.0;
uniform float green = 1.0;
uniform float blue = 1.0;
uniform float alpha = 1.0;
uniform float maxVelocity = 0.0;
uniform int renderMode = 0;

vec3 boysSurfaceColor(vec2 v, float maxMag)
{
    float mag = length(v);
    float sat = clamp(mag / maxMag, 0.0, 1.0);

    float angle = atan(v.y, v.x);

    float x = cos(angle);
    float y = sin(angle);

    float r =  0.5 + 0.5 * ( 0.14861*x - 0.29227*y + 1.97294*x*y);
    float g =  0.5 + 0.5 * (-0.29227*x + 0.14861*y + 1.97294*x*y);
    float b =  0.5 + 0.5 * ( 1.97294*x*y - 0.14861*x - 0.29227*y);

    vec3 base = vec3(r, g, b);

    // blend toward gray for small magnitude
    vec3 gray = vec3(0.75);
    return mix(gray, base, sat);
}

vec3 scalarColor(float t)
{
    float clamped = clamp(t, 0.0, 1.0);
    vec3 cool = vec3(0.12, 0.25, 0.85);
    vec3 warm = vec3(0.95, 0.25, 0.15);
    vec3 mid = vec3(0.95, 0.9, 0.2);
    vec3 lowHigh = mix(cool, mid, smoothstep(0.0, 0.6, clamped));
    return mix(lowHigh, warm, smoothstep(0.6, 1.0, clamped));
}

void main() {

    if (cube == 1) {
        fragColor = vec4(1.0);
        return;
    }

    if (renderMode == 1) {
        vec3 c = scalarColor(color.x);
        fragColor = vec4(c, 1.0);
        return;
    }
    if (renderMode == 2) {
        fragColor = vec4(red, green, blue, alpha);
        return;
    }

    vec2 vel = vec2(color[0], color[1]);
    vec3 c = boysSurfaceColor(vel, maxVelocity);
    fragColor = vec4(c, 1.0);
}

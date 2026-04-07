#version 330 core

layout(location = 0) in vec3 position; // Position of the vertex
layout(location = 1) in vec3 veloc;   // Normal of the vertex
layout(location = 2) in vec3 instanceOffset;
layout(location = 3) in float instanceValue;

uniform mat4 proj;
uniform mat4 view;
uniform mat4 model;

uniform mat3 inverseTransposeModel;
uniform int renderMode;
uniform float sphereScale;

out vec4 color;
out vec4 position_worldSpace;

void main() {
    vec3 pos = position;
    vec3 attrib = veloc;

    if (renderMode == 1) {
        pos = instanceOffset + position * sphereScale;
        attrib = vec3(instanceValue, 0.0, 0.0);
    }

    color   = vec4(attrib,0);
    position_worldSpace = vec4(pos, 1.0);

    gl_Position = proj * view * model * vec4(pos, 1.0);
}

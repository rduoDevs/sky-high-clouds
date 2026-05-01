#pragma once
#include <glm/glm.hpp>


// Tris/cloud
struct GPUTriangle {
    glm::vec3 v0;
    float pad0;
    glm::vec3 v1;
    float pad1;
    glm::vec3 v2;
    float pad2;
    glm::vec3 normal;
    float pad3;
};

struct CloudMesh {
    glm::vec3 boundsMin;
    float pad0;
    glm::vec3 boundsMax;
    float pad1;
    uint32_t triangleOffset;
    uint32_t triangleCount;
    float shellThickness;
    float pad2;
};

struct CameraData {
    glm::vec3 position;
    float _pad0;
    glm::vec3 rotation;
    float fov;
};

struct MaterialData {
    glm::vec4 colorSmoothness;
    glm::vec4 specularEmissionPad;
    glm::vec4 emissionColorRefractive;
};

struct SphereData {
    glm::vec4 centerRadius;
    MaterialData material;
};

struct WorldData {
    SphereData spheres[2];
};

struct RaySettingsData {
    uint32_t maxBounces;
    uint32_t antiAliasingSamples;
    uint32_t _pad[2];
};

struct FrameCountData {
    uint32_t frameCount;
    uint32_t _pad[3];
};

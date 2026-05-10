#include "sdfhandler.h"
#include <algorithm>
#include <iostream>

SDFHandler::SDFHandler() {}

static glm::vec3 closestPointOnTriangle(glm::vec3 p,
                                        glm::vec3 a,
                                        glm::vec3 b,
                                        glm::vec3 c) {
    glm::vec3 ab = b - a;
    glm::vec3 ac = c - a;
    glm::vec3 ap = p - a;

    float d1 = glm::dot(ab, ap);
    float d2 = glm::dot(ac, ap);
    if (d1 <= 0.0f && d2 <= 0.0f)
        return a;

    glm::vec3 bp = p - b;
    float d3 = glm::dot(ab, bp);
    float d4 = glm::dot(ac, bp);
    if (d3 >= 0.0f && d4 <= d3)
        return b;

    float vc = d1 * d4 - d3 * d2;
    if (vc <= 0.0f && d1 >= 0.0f && d3 <= 0.0f) {
        float v = d1 / (d1 - d3);
        return a + v * ab;
    }

    glm::vec3 cp = p - c;
    float d5 = glm::dot(ab, cp);
    float d6 = glm::dot(ac, cp);
    if (d6 >= 0.0f && d5 <= d6)
        return c;

    float vb = d5 * d2 - d1 * d6;
    if (vb <= 0.0f && d2 >= 0.0f && d6 <= 0.0f) {
        float w = d2 / (d2 - d6);
        return a + w * ac;
    }

    float va = d3 * d6 - d5 * d4;
    if (va <= 0.0f && (d4 - d3) >= 0.0f && (d5 - d6) >= 0.0f) {
        float w = (d4 - d3) / ((d4 - d3) + (d5 - d6));
        return b + w * (c - b);
    }

    float denom = 1.0f / (va + vb + vc);
    float v = vb * denom;
    float w = vc * denom;
    return a + ab * v + ac * w;
}

std::vector<float> SDFHandler::generateSDF(
    const std::vector<GPUTriangle>& triangles,
    glm::vec3 boundsMin,
    glm::vec3 boundsMax,
    glm::uvec3 gridRes) {
    std::vector<float> sdf(gridRes.x * gridRes.y * gridRes.z, 0.0f);
    glm::vec3 extent = boundsMax - boundsMin;
    glm::vec3 cellSize =
        extent / glm::max(glm::vec3(gridRes - 1u), glm::vec3(1.0f));

    std::cout << "Generating SDF (" << gridRes.x << "x" << gridRes.y << "x"
              << gridRes.z << ")...\n";

    for (uint32_t z = 0; z < gridRes.z; ++z) {
        for (uint32_t y = 0; y < gridRes.y; ++y) {
            for (uint32_t x = 0; x < gridRes.x; ++x) {
                glm::vec3 p = boundsMin + glm::vec3(x, y, z) * cellSize;
                float minDist = 1e6f;
                bool isInside = false;
                // Brute force distance
                for (const auto& tri : triangles) {
                    glm::vec3 closest =
                        closestPointOnTriangle(p, tri.v0, tri.v1, tri.v2);
                    // if closest point is inside the triangle/mesh, we mark it
                    // as inside

                    float dist = glm::distance(p, closest);
                    if (dist < minDist) {
                        minDist = dist;
                        glm::vec3 edge1 = tri.v1 - tri.v0;
                        glm::vec3 edge2 = tri.v2 - tri.v0;
                        glm::vec3 normal =
                            glm::normalize(glm::cross(edge1, edge2));
                        // if the point is behind the triangle plane, we
                        // consider it inside
                        if (glm::dot(p - closest, normal) < 0.0f) {
                            isInside = true;
                        } else {
                            isInside = false;
                        }
                    }
                }
                sdf[z * gridRes.y * gridRes.x + y * gridRes.x + x] =
                    minDist * (isInside ? 1.0f : -1.0f);
            }
        }
    }
    std::cout << "SDF generated.\n";
    return sdf;
}

#ifndef SDFHANDLER_H
#define SDFHANDLER_H

#include <vector>
#include <glm/glm.hpp>
#include "gpuData.h"

class SDFHandler
{
public:
    SDFHandler();

    static std::vector<float> generateSDF(const std::vector<GPUTriangle>& triangles,
                                          glm::vec3 boundsMin, glm::vec3 boundsMax,
                                          glm::uvec3 gridRes);
};

#endif // SDFHANDLER_H


#include "ResourceManager.h"

#include <fstream>
#include <iostream>

using namespace wgpu;

ShaderModule ResourceManager::loadShaderModule(const path& path,
                                               Device device) {
    std::ifstream file(path, std::ios::binary);
    if (!file.is_open()) {
        std::cerr << "Failed to open shader file: " << path << std::endl;
        return nullptr;
    }

    std::string shaderSource((std::istreambuf_iterator<char>(file)),
                             std::istreambuf_iterator<char>());

    ShaderSourceWGSL shaderCodeDesc;
    shaderCodeDesc.code = StringView(shaderSource.data(), shaderSource.size());

    ShaderModuleDescriptor shaderDesc;
    shaderDesc.nextInChain = &shaderCodeDesc;

    return device.CreateShaderModule(&shaderDesc);
}
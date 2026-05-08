#include <iostream>
#include "Application.h"
#include "gpuData.h"
#define TINYOBJLOADER_IMPLEMENTATION
#include <fstream>
#include <string>
#include <vector>
#include "Bouthors_Texture_Definitions.h"
#include "sdfhandler.h"
#include "tiny_obj_loader.h"

void Application::initBuffers() {
    wgpu::BufferDescriptor desc{};
    desc.mappedAtCreation = false;

    desc.label = wgpu::StringView("Camera Uniform");
    desc.size = sizeof(CameraData);
    desc.usage = wgpu::BufferUsage::CopyDst | wgpu::BufferUsage::Uniform;
    m_uniformBuffer = m_device.CreateBuffer(&desc);

    desc.label = wgpu::StringView("World Storage");
    desc.size = sizeof(WorldData);
    desc.usage = wgpu::BufferUsage::CopyDst | wgpu::BufferUsage::Storage;
    m_worldBuffer = m_device.CreateBuffer(&desc);

    desc.label = wgpu::StringView("Ray Settings Uniform");
    desc.size = sizeof(RaySettingsData);
    desc.usage = wgpu::BufferUsage::CopyDst | wgpu::BufferUsage::Uniform;
    m_settingsBuffer = m_device.CreateBuffer(&desc);

    desc.label = wgpu::StringView("Frame Count Uniform");
    desc.size = sizeof(FrameCountData);
    desc.usage = wgpu::BufferUsage::CopyDst | wgpu::BufferUsage::Uniform;
    m_frameCountBuffer = m_device.CreateBuffer(&desc);

    m_cameraData = {
        .position = glm::vec3(0.0f, 0.0f, 3.5f),
        ._pad0 = 0.0f,
        .rotation = glm::vec3(0.0f, 0.0f, 0.0f),
        .fov = 60.0f,
    };

    WorldData world{};

    // world.spheres[0].centerRadius = glm::vec4(-0.8f, 0.0f, -1.2f, 0.65f);
    // world.spheres[0].material.colorSmoothness =
    //     glm::vec4(0.95f, 0.2f, 0.2f, 0.0f);
    // world.spheres[0].material.specularEmissionPad =
    //     glm::vec4(0.0f, 1.0f, 0.0f, 0.0f);
    // world.spheres[0].material.emissionColorRefractive =
    //     glm::vec4(1.0f, 0.0f, 0.0f, 0.0f);

    // world.spheres[1].centerRadius = glm::vec4(1.9f, 0.1f, -2.0f, 0.75f);
    // world.spheres[1].material.colorSmoothness =
    //     glm::vec4(0.2f, 0.45f, 0.95f, 0.0f);
    // world.spheres[1].material.specularEmissionPad =
    //     glm::vec4(0.0f, 0.0f, 0.0f, 0.0f);
    // world.spheres[1].material.emissionColorRefractive =
    //     glm::vec4(0.0f, 0.0f, 0.0f, 0.0f);

    // world.spheres[2].centerRadius = glm::vec4(0.5f, 0.2f, -1.0f, 0.5f);

    m_raySettingsData = {
        .maxBounces = 2,
        .antiAliasingSamples = 1,
        .scatteringOrderMask = 0xFFF,
        ._pad = 0,
    };

    const FrameCountData frameData = {.frameCount = 0, ._pad = {0, 0, 0}};

    // textures and samplers

    wgpu::SamplerDescriptor samplerDesc{};
    samplerDesc.addressModeU = wgpu::AddressMode::ClampToEdge;
    samplerDesc.addressModeV = wgpu::AddressMode::ClampToEdge;
    samplerDesc.magFilter = wgpu::FilterMode::Linear;
    samplerDesc.minFilter = wgpu::FilterMode::Linear;

    this->m_texSampler = m_device.CreateSampler(&samplerDesc);

    // Load higher-order tables from raw text files and pack into a single float
    // array
    // const uint32_t TAB_W = 64u;
    // const uint32_t TAB_H = 64u;
    // const uint32_t TAB_LAYERS = 49u;  // 7 orders * 7 sections

    // std::vector<std::string> tableFiles = {
    //     "multiple_scattering_textures/tables/LogGaussAniso_A_1.txt",
    //     "multiple_scattering_textures/tables/LogGaussAniso_A_2.txt",
    //     "multiple_scattering_textures/tables/LogGaussAniso_A_3.txt",
    //     "multiple_scattering_textures/tables/LogGaussAniso_A_4-5.txt",
    //     "multiple_scattering_textures/tables/LogGaussAniso_A_6-8.txt",
    //     "multiple_scattering_textures/tables/LogGaussAniso_A_9-14.txt",
    //     "multiple_scattering_textures/tables/LogGaussAniso_A_15p.txt",

    //     "multiple_scattering_textures/tables/LogGaussAniso_B1_1.txt",
    //     "multiple_scattering_textures/tables/LogGaussAniso_B1_2.txt",
    //     "multiple_scattering_textures/tables/LogGaussAniso_B1_3.txt",
    //     "multiple_scattering_textures/tables/LogGaussAniso_B1_4-5.txt",
    //     "multiple_scattering_textures/tables/LogGaussAniso_B1_6-8.txt",
    //     "multiple_scattering_textures/tables/LogGaussAniso_B1_9-14.txt",
    //     "multiple_scattering_textures/tables/LogGaussAniso_B1_15p.txt",

    //     "multiple_scattering_textures/tables/LogGaussAniso_B2_1.txt",
    //     "multiple_scattering_textures/tables/LogGaussAniso_B2_2.txt",
    //     "multiple_scattering_textures/tables/LogGaussAniso_B2_3.txt",
    //     "multiple_scattering_textures/tables/LogGaussAniso_B2_4-5.txt",
    //     "multiple_scattering_textures/tables/LogGaussAniso_B2_6-8.txt",
    //     "multiple_scattering_textures/tables/LogGaussAniso_B2_9-14.txt",
    //     "multiple_scattering_textures/tables/LogGaussAniso_B2_15p.txt",

    //     "multiple_scattering_textures/tables/LogGaussAniso_C_1.txt",
    //     "multiple_scattering_textures/tables/LogGaussAniso_C_2.txt",
    //     "multiple_scattering_textures/tables/LogGaussAniso_C_3.txt",
    //     "multiple_scattering_textures/tables/LogGaussAniso_C_4-5.txt",
    //     "multiple_scattering_textures/tables/LogGaussAniso_C_6-8.txt",
    //     "multiple_scattering_textures/tables/LogGaussAniso_C_9-14.txt",
    //     "multiple_scattering_textures/tables/LogGaussAniso_C_15p.txt",

    //     "multiple_scattering_textures/tables/LogGaussAniso_D_1.txt",
    //     "multiple_scattering_textures/tables/LogGaussAniso_D_2.txt",
    //     "multiple_scattering_textures/tables/LogGaussAniso_D_3.txt",
    //     "multiple_scattering_textures/tables/LogGaussAniso_D_4-5.txt",
    //     "multiple_scattering_textures/tables/LogGaussAniso_D_6-8.txt",
    //     "multiple_scattering_textures/tables/LogGaussAniso_D_9-14.txt",
    //     "multiple_scattering_textures/tables/LogGaussAniso_D_15p.txt",

    //     "multiple_scattering_textures/tables/LogGaussAniso_P_1.txt",
    //     "multiple_scattering_textures/tables/LogGaussAniso_P_2.txt",
    //     "multiple_scattering_textures/tables/LogGaussAniso_P_3.txt",
    //     "multiple_scattering_textures/tables/LogGaussAniso_P_4-5.txt",
    //     "multiple_scattering_textures/tables/LogGaussAniso_P_6-8.txt",
    //     "multiple_scattering_textures/tables/LogGaussAniso_P_9-14.txt",
    //     "multiple_scattering_textures/tables/LogGaussAniso_P_15p.txt",

    //     "multiple_scattering_textures/tables/LogGaussAniso_X_1.txt",
    //     "multiple_scattering_textures/tables/LogGaussAniso_X_2.txt",
    //     "multiple_scattering_textures/tables/LogGaussAniso_X_3.txt",
    //     "multiple_scattering_textures/tables/LogGaussAniso_X_4-5.txt",
    //     "multiple_scattering_textures/tables/LogGaussAniso_X_6-8.txt",
    //     "multiple_scattering_textures/tables/LogGaussAniso_X_9-14.txt",
    //     "multiple_scattering_textures/tables/LogGaussAniso_X_15p.txt",
    // };

    // std::vector<float> allData;
    // allData.reserve(TAB_W * TAB_H * TAB_LAYERS);

    // for (size_t fi = 0; fi < tableFiles.size(); ++fi) {
    //     const std::string path = std::string("./resources/") +
    //     tableFiles[fi]; std::ifstream ifs(path); if (!ifs) {
    //         std::cerr << "ERROR: Failed to open table file: " << path
    //                   << std::endl;
    //         // pad with zeros for this layer
    //         for (uint32_t i = 0; i < TAB_W * TAB_H; ++i)
    //             allData.push_back(0.0f);
    //         continue;
    //     }
    //     // std::cout << "Loaded table: " << path << std::endl;
    //     // parse whitespace separated floats
    //     std::vector<float> layer;
    //     layer.reserve(TAB_W * TAB_H);
    //     float v;
    //     while (ifs >> v) {
    //         layer.push_back(v);
    //     }
    //     if (layer.size() != TAB_W * TAB_H) {
    //         std::cerr << "Warning: table file " << path << " contains "
    //                   << layer.size() << " floats (expected " << (TAB_W *
    //                   TAB_H)
    //                   << ")." << std::endl;
    //         // pad or trim
    //         layer.resize(TAB_W * TAB_H, 0.0f);
    //     }
    //     allData.insert(allData.end(), layer.begin(), layer.end());
    // }

    // std::cout << "Total table data loaded: " << allData.size()
    //           << " floats (expected " << (TAB_W * TAB_H * TAB_LAYERS) << ")"
    //           << std::endl;

    std::vector<float> allData;
    allData.reserve(64 * 64 * 49);  // 7 orders * 7 sections * 64*64 floats each
    auto appendTable = [&allData](const float table[64][64]) {
        for (size_t i = 0; i < 64; ++i) {
            for (size_t j = 0; j < 64; ++j) {
                allData.push_back(table[i][j]);
            }
        }
    };
    appendTable(LogGaussAniso_A_1);
    appendTable(LogGaussAniso_A_2);
    appendTable(LogGaussAniso_A_3);
    appendTable(LogGaussAniso_A_4_5);
    appendTable(LogGaussAniso_A_6_8);
    appendTable(LogGaussAniso_A_9_14);
    appendTable(LogGaussAniso_A_15p);
    appendTable(LogGaussAniso_B1_1);
    appendTable(LogGaussAniso_B1_2);
    appendTable(LogGaussAniso_B1_3);
    appendTable(LogGaussAniso_B1_4_5);
    appendTable(LogGaussAniso_B1_6_8);
    appendTable(LogGaussAniso_B1_9_14);
    appendTable(LogGaussAniso_B1_15p);
    appendTable(LogGaussAniso_B2_1);
    appendTable(LogGaussAniso_B2_2);
    appendTable(LogGaussAniso_B2_3);
    appendTable(LogGaussAniso_B2_4_5);
    appendTable(LogGaussAniso_B2_6_8);
    appendTable(LogGaussAniso_B2_9_14);
    appendTable(LogGaussAniso_B2_15p);
    appendTable(LogGaussAniso_C_1);
    appendTable(LogGaussAniso_C_2);
    appendTable(LogGaussAniso_C_3);
    appendTable(LogGaussAniso_C_4_5);
    appendTable(LogGaussAniso_C_6_8);
    appendTable(LogGaussAniso_C_9_14);
    appendTable(LogGaussAniso_C_15p);
    appendTable(LogGaussAniso_D_1);
    appendTable(LogGaussAniso_D_2);
    appendTable(LogGaussAniso_D_3);
    appendTable(LogGaussAniso_D_4_5);
    appendTable(LogGaussAniso_D_6_8);
    appendTable(LogGaussAniso_D_9_14);
    appendTable(LogGaussAniso_D_15p);
    appendTable(LogGaussAniso_P_1);
    appendTable(LogGaussAniso_P_2);
    appendTable(LogGaussAniso_P_3);
    appendTable(LogGaussAniso_P_4_5);
    appendTable(LogGaussAniso_P_6_8);
    appendTable(LogGaussAniso_P_9_14);
    appendTable(LogGaussAniso_P_15p);
    appendTable(LogGaussAniso_X_1);
    appendTable(LogGaussAniso_X_2);
    appendTable(LogGaussAniso_X_3);
    appendTable(LogGaussAniso_X_4_5);
    appendTable(LogGaussAniso_X_6_8);
    appendTable(LogGaussAniso_X_9_14);
    appendTable(LogGaussAniso_X_15p);

    // Create storage buffer for packed tables
    uint64_t allBytes = (uint64_t)allData.size() * sizeof(float);
    wgpu::BufferDescriptor tableDesc{};
    tableDesc.label = wgpu::StringView("Higher Order Table Buffer");
    tableDesc.size = allBytes;
    tableDesc.usage = wgpu::BufferUsage::CopyDst | wgpu::BufferUsage::Storage;
    m_higherOrderTableBuffer = m_device.CreateBuffer(&tableDesc);
    if (allData.size() > 0) {
        m_queue.WriteBuffer(m_higherOrderTableBuffer, 0, allData.data(),
                            (uint32_t)allBytes);
    }

    m_queue.WriteBuffer(m_uniformBuffer, 0, &m_cameraData,
                        sizeof(m_cameraData));
    m_queue.WriteBuffer(m_worldBuffer, 0, &world, sizeof(world));
    m_queue.WriteBuffer(m_settingsBuffer, 0, &m_raySettingsData,
                        sizeof(m_raySettingsData));
    m_queue.WriteBuffer(m_frameCountBuffer, 0, &frameData, sizeof(frameData));
}

void Application::initBindGroup() {
    std::vector<wgpu::BindGroupEntry> entries(10);

    entries[0].binding = 0;
    entries[0].buffer = m_uniformBuffer;
    entries[0].offset = 0;
    entries[0].size = sizeof(CameraData);

    entries[1].binding = 1;
    entries[1].buffer = m_worldBuffer;
    entries[1].offset = 0;
    entries[1].size = sizeof(WorldData);

    entries[2].binding = 2;
    entries[2].textureView = m_outputTextureView;

    entries[3].binding = 3;
    entries[3].buffer = m_settingsBuffer;
    entries[3].offset = 0;
    entries[3].size = sizeof(RaySettingsData);

    entries[4].binding = 4;
    entries[4].buffer = m_frameCountBuffer;
    entries[4].offset = 0;
    entries[4].size = sizeof(FrameCountData);

    entries[5].binding = 5;
    entries[5].buffer = m_triangleBuffer;
    entries[5].offset = 0;
    entries[5].size = m_triangleCount * sizeof(GPUTriangle);

    entries[6].binding = 6;
    entries[6].buffer = m_cloudMeshBuffer;
    entries[6].offset = 0;
    entries[6].size = sizeof(CloudMesh);

    entries[7].binding = 7;
    entries[7].buffer = m_higherOrderTableBuffer;
    entries[7].offset = 0;
    entries[7].size = wgpu::kWholeSize;

    entries[8].binding = 8;
    entries[8].buffer = m_sdfBuffer;
    entries[8].offset = 0;
    entries[8].size = wgpu::kWholeSize;

    entries[9].binding = 9;
    entries[9].sampler = m_texSampler;

    wgpu::BindGroupDescriptor bindGroupDesc;
    bindGroupDesc.layout = m_bindGroupLayout;
    bindGroupDesc.entryCount = (uint32_t)entries.size();
    bindGroupDesc.entries = entries.data();
    m_bindGroup = m_device.CreateBindGroup(&bindGroupDesc);
}

void Application::initBindGroupLayout() {
    std::vector<wgpu::BindGroupLayoutEntry> bindings(10);

    bindings[0].binding = 0;
    bindings[0].buffer.type = wgpu::BufferBindingType::Uniform;
    bindings[0].buffer.minBindingSize = sizeof(CameraData);
    bindings[0].visibility = wgpu::ShaderStage::Compute;

    bindings[1].binding = 1;
    bindings[1].buffer.type = wgpu::BufferBindingType::ReadOnlyStorage;
    bindings[1].buffer.minBindingSize = sizeof(WorldData);
    bindings[1].visibility = wgpu::ShaderStage::Compute;

    bindings[2].binding = 2;
    bindings[2].storageTexture.access = wgpu::StorageTextureAccess::WriteOnly;
    bindings[2].storageTexture.format = wgpu::TextureFormat::RGBA8Unorm;
    bindings[2].storageTexture.viewDimension = wgpu::TextureViewDimension::e2D;
    bindings[2].visibility = wgpu::ShaderStage::Compute;

    bindings[3].binding = 3;
    bindings[3].buffer.type = wgpu::BufferBindingType::Uniform;
    bindings[3].buffer.minBindingSize = sizeof(RaySettingsData);
    bindings[3].visibility = wgpu::ShaderStage::Compute;

    bindings[4].binding = 4;
    bindings[4].buffer.type = wgpu::BufferBindingType::Uniform;
    bindings[4].buffer.minBindingSize = sizeof(FrameCountData);
    bindings[4].visibility = wgpu::ShaderStage::Compute;

    bindings[5].binding = 5;
    bindings[5].buffer.type = wgpu::BufferBindingType::ReadOnlyStorage;
    bindings[5].buffer.minBindingSize = sizeof(GPUTriangle);
    bindings[5].visibility = wgpu::ShaderStage::Compute;

    bindings[6].binding = 6;
    bindings[6].buffer.type = wgpu::BufferBindingType::Uniform;
    bindings[6].buffer.minBindingSize = sizeof(CloudMesh);
    bindings[6].visibility = wgpu::ShaderStage::Compute;

    bindings[7].binding = 7;
    bindings[7].buffer.type = wgpu::BufferBindingType::ReadOnlyStorage;
    bindings[7].buffer.minBindingSize = 0;
    bindings[7].visibility = wgpu::ShaderStage::Compute;

    bindings[8].binding = 8;
    bindings[8].buffer.type = wgpu::BufferBindingType::ReadOnlyStorage;
    bindings[8].buffer.minBindingSize = 0;
    bindings[8].visibility = wgpu::ShaderStage::Compute;

    bindings[9].binding = 9;
    bindings[9].sampler.type = wgpu::SamplerBindingType::Filtering;
    bindings[9].visibility = wgpu::ShaderStage::Compute;

    wgpu::BindGroupLayoutDescriptor bindGroupLayoutDesc;
    bindGroupLayoutDesc.entryCount = (uint32_t)bindings.size();
    bindGroupLayoutDesc.entries = bindings.data();
    m_bindGroupLayout = m_device.CreateBindGroupLayout(&bindGroupLayoutDesc);
}

void Application::handleKeyInput(float deltaTime) {
    glm::vec3 movement(0.0f);

    // WASD movement in camera space
    if (m_keys[GLFW_KEY_W])
        movement.z -= 1.0f;
    if (m_keys[GLFW_KEY_S])
        movement.z += 1.0f;
    if (m_keys[GLFW_KEY_A])
        movement.x -= 1.0f;
    if (m_keys[GLFW_KEY_D])
        movement.x += 1.0f;
    if (m_keys[GLFW_KEY_SPACE] || m_keys[GLFW_KEY_E])
        movement.y += 1.0f;
    if (m_keys[GLFW_KEY_LEFT_SHIFT] || m_keys[GLFW_KEY_Q])
        movement.y -= 1.0f;

    if (glm::length(movement) > 0.0f) {
        movement = glm::normalize(movement);

        // Create rotation matrix from camera rotation
        float cosY = glm::cos(m_cameraData.rotation.y);
        float sinY = glm::sin(m_cameraData.rotation.y);

        // Transform movement based on camera rotation (yaw only for now)
        float movedX = movement.x * cosY - movement.z * sinY;
        float movedZ = movement.x * sinY + movement.z * cosY;

        m_cameraData.position.x += movedX * m_moveSpeed * deltaTime;
        m_cameraData.position.z += movedZ * m_moveSpeed * deltaTime;
        m_cameraData.position.y += movement.y * m_moveSpeed * deltaTime;

        m_cameraDataUpdated = true;
    }
}

void Application::toggleMouseCapture() {
    m_mouseCaptured = !m_mouseCaptured;
    std::cout << "Mouse capture " << (m_mouseCaptured ? "enabled" : "disabled")
              << std::endl;

    if (m_mouseCaptured) {
        glfwSetInputMode(m_window, GLFW_CURSOR, GLFW_CURSOR_DISABLED);
    } else {
        glfwSetInputMode(m_window, GLFW_CURSOR, GLFW_CURSOR_NORMAL);
    }
}

void Application::HandleKeyCallback(int key, int action) {
    if (key >= 0 && key <= GLFW_KEY_LAST) {
        m_keys[key] = (action != GLFW_RELEASE);

        // Handle Escape key for mouse capture toggle
        if (key == GLFW_KEY_ESCAPE && action == GLFW_PRESS) {
            toggleMouseCapture();
        }
    }
}

void Application::HandleMouseCallback(double xpos, double ypos) {
    if (m_mouseCaptured) {
        double deltaX = xpos - m_lastMouseX;
        double deltaY = ypos - m_lastMouseY;

        // Update camera rotation based on mouse movement
        // y is yaw (looking left/right), x is pitch (looking up/down)
        m_cameraData.rotation.y += static_cast<float>(deltaX) * m_rotateSpeed;
        m_cameraData.rotation.x -= static_cast<float>(deltaY) * m_rotateSpeed;
        m_cameraDataUpdated = true;
    }
    m_lastMouseX = xpos;
    m_lastMouseY = ypos;
}

void Application::loadCloudMesh() {
    tinyobj::attrib_t attrib;
    std::vector<tinyobj::shape_t> shapes;
    std::vector<tinyobj::material_t> materials;
    std::string err;

    bool ok =
        tinyobj::LoadObj(&attrib, &shapes, &materials, &err,
                         "resources/better_test_cloud.obj", nullptr, true);

    if (!ok) {
        std::cerr << "OBJ load failed: " << err << std::endl;
        return;
    }
    if (!err.empty()) {
        std::cout << "OBJ warning: " << err << std::endl;
    }

    const glm::vec3 translate(0.0f, 0.0f, 0.0f);
    const float scale = 0.6f;

    std::vector<GPUTriangle> tris;
    glm::vec3 boundsMin(std::numeric_limits<float>::max());
    glm::vec3 boundsMax(-std::numeric_limits<float>::max());

    auto getVertex = [&](int idx) {
        return glm::vec3(attrib.vertices[3 * idx + 0],
                         attrib.vertices[3 * idx + 1],
                         attrib.vertices[3 * idx + 2]) *
                   scale +
               translate;
    };
    auto getNormal = [&](int idx) {
        return glm::vec3(
            attrib.normals[3 * idx + 0],
            attrib.normals[3 * idx + 1],
            attrib.normals[3 * idx + 2]);
    };

    for (const auto& shape : shapes) {
        const auto& mesh = shape.mesh;
        size_t off = 0;
        for (size_t f = 0; f < mesh.num_face_vertices.size(); f++) {
            int fv = mesh.num_face_vertices[f];
            if (fv != 3) {
                off += fv;
                continue;
            }

            GPUTriangle t{};
            t.v0 = getVertex(mesh.indices[off + 0].vertex_index);
            t.v1 = getVertex(mesh.indices[off + 1].vertex_index);
            t.v2 = getVertex(mesh.indices[off + 2].vertex_index);
            t.n0 = getNormal(mesh.indices[off + 0].normal_index);
            t.n1 = getNormal(mesh.indices[off + 1].normal_index);
            t.n2 = getNormal(mesh.indices[off + 2].normal_index);

            boundsMin =
                glm::min(boundsMin, glm::min(t.v0, glm::min(t.v1, t.v2)));
            boundsMax =
                glm::max(boundsMax, glm::max(t.v0, glm::max(t.v1, t.v2)));

            tris.push_back(t);
            off += 3;
        }
    }

    m_triangleCount = static_cast<uint32_t>(tris.size());
    std::cout << "Loaded mesh: " << m_triangleCount << " triangles"
              << std::endl;

    wgpu::BufferDescriptor triDesc{};
    triDesc.label = "Triangle Buffer";
    triDesc.size = tris.size() * sizeof(GPUTriangle);
    triDesc.usage = wgpu::BufferUsage::Storage | wgpu::BufferUsage::CopyDst;
    m_triangleBuffer = m_device.CreateBuffer(&triDesc);
    m_queue.WriteBuffer(m_triangleBuffer, 0, tris.data(), triDesc.size);

    CloudMesh meta{};
    meta.boundsMin = boundsMin;
    meta.boundsMax = boundsMax;
    meta.triangleOffset = 0;
    meta.triangleCount = m_triangleCount;
    // meta.shellThickness = 0.3f;
    meta.shellThickness = 0.42f;

    wgpu::BufferDescriptor metaDesc{};
    metaDesc.label = "Cloud Mesh Buffer";
    metaDesc.size = sizeof(CloudMesh);
    metaDesc.usage = wgpu::BufferUsage::Uniform | wgpu::BufferUsage::CopyDst;
    m_cloudMeshBuffer = m_device.CreateBuffer(&metaDesc);
    m_queue.WriteBuffer(m_cloudMeshBuffer, 0, &meta, sizeof(meta));

    // Generate SDF Texture
    glm::uvec3 sdfRes(128, 128, 128);
    // Expand bounds slightly to give room outside the mesh
    glm::vec3 sdfBoundsMin = boundsMin - glm::vec3(meta.shellThickness * 1.5f);
    glm::vec3 sdfBoundsMax = boundsMax + glm::vec3(meta.shellThickness * 1.5f);
    std::vector<float> sdfData =
        SDFHandler::generateSDF(tris, sdfBoundsMin, sdfBoundsMax, sdfRes);

    wgpu::BufferDescriptor sdfDesc{};
    sdfDesc.label = "SDF Buffer";
    sdfDesc.size = sdfData.size() * sizeof(float);
    sdfDesc.usage = wgpu::BufferUsage::Storage | wgpu::BufferUsage::CopyDst;
    m_sdfBuffer = m_device.CreateBuffer(&sdfDesc);
    m_queue.WriteBuffer(m_sdfBuffer, 0, sdfData.data(), sdfDesc.size);
    std::cout << "Generated SDF: " << sdfData.size()
              << " floats for resolution " << sdfRes.x << "x" << sdfRes.y << "x"
              << sdfRes.z << std::endl;
}

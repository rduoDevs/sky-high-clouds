#include "gpuData.h"
#include "Application.h"

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

    const CameraData camera = {
        .position = glm::vec3(0.0f, 0.0f, 3.5f),
        ._pad0 = 0.0f,
        .rotation = glm::vec3(0.0f, 0.0f, 0.0f),
        .fov = 60.0f,
    };

    WorldData world{};

    world.spheres[0].centerRadius = glm::vec4(-0.8f, 0.0f, -1.2f, 0.65f);
    world.spheres[0].material.colorSmoothness =
        glm::vec4(0.95f, 0.2f, 0.2f, 0.0f);
    world.spheres[0].material.specularEmissionPad =
        glm::vec4(0.0f, 1.0f, 0.0f, 0.0f);
    world.spheres[0].material.emissionColorRefractive =
        glm::vec4(1.0f, 0.0f, 0.0f, 0.0f);

    world.spheres[1].centerRadius = glm::vec4(0.9f, 0.1f, -2.0f, 0.75f);
    world.spheres[1].material.colorSmoothness =
        glm::vec4(0.2f, 0.45f, 0.95f, 0.0f);
    world.spheres[1].material.specularEmissionPad =
        glm::vec4(0.0f, 0.0f, 0.0f, 0.0f);
    world.spheres[1].material.emissionColorRefractive =
        glm::vec4(0.0f, 0.0f, 0.0f, 0.0f);

    const RaySettingsData raySettings = {
        .maxBounces = 4,
        .antiAliasingSamples = 1,
        ._pad = {0, 0},
    };

    const FrameCountData frameData = {.frameCount = 0, ._pad = {0, 0, 0}};

    m_queue.WriteBuffer(m_uniformBuffer, 0, &camera, sizeof(camera));
    m_queue.WriteBuffer(m_worldBuffer, 0, &world, sizeof(world));
    m_queue.WriteBuffer(m_settingsBuffer, 0, &raySettings, sizeof(raySettings));
    m_queue.WriteBuffer(m_frameCountBuffer, 0, &frameData, sizeof(frameData));
}

void Application::initBindGroup() {
    std::vector<wgpu::BindGroupEntry> entries(5);

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

    wgpu::BindGroupDescriptor bindGroupDesc;
    bindGroupDesc.layout = m_bindGroupLayout;
    bindGroupDesc.entryCount = (uint32_t)entries.size();
    bindGroupDesc.entries = entries.data();
    m_bindGroup = m_device.CreateBindGroup(&bindGroupDesc);
}

void Application::initBindGroupLayout() {
    std::vector<wgpu::BindGroupLayoutEntry> bindings(5);

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

    wgpu::BindGroupLayoutDescriptor bindGroupLayoutDesc;
    bindGroupLayoutDesc.entryCount = (uint32_t)bindings.size();
    bindGroupLayoutDesc.entries = bindings.data();
    m_bindGroupLayout = m_device.CreateBindGroupLayout(&bindGroupLayoutDesc);
}
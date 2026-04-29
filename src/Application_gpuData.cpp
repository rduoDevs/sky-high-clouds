#include <iostream>
#include "Application.h"
#include "gpuData.h"

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

    m_queue.WriteBuffer(m_uniformBuffer, 0, &m_cameraData,
                        sizeof(m_cameraData));
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
        std::cout << "Camera rotation: (" << m_cameraData.rotation.x << ", "
                  << m_cameraData.rotation.y << ", " << m_cameraData.rotation.z
                  << ")" << std::endl;
    }
    m_lastMouseX = xpos;
    m_lastMouseY = ypos;
}
#include "Application.h"
#include "ResourceManager.h"

#include <glfw3webgpu/glfw3webgpu.h>

#define GLM_FORCE_LEFT_HANDED
#define GLM_FORCE_DEPTH_ZERO_TO_ONE
#include <glm/ext.hpp>
#include <glm/glm.hpp>

#include <backends/imgui_impl_glfw.h>
#include <backends/imgui_impl_wgpu.h>
#include <imgui.h>

#include <webgpu/webgpu_cpp.h>

// Define resource directory
#define RESOURCE_DIR "./resources"

#include <array>
#include <cassert>
#include <filesystem>
#include <fstream>
#include <iostream>
#include <sstream>
#include <string>
#include <vector>

constexpr float PI = 3.14159265358979323846f;

using namespace wgpu;
using glm::mat4x4;
using glm::vec2;
using glm::vec3;
using glm::vec4;
// == GLFW Callbacks == //

void onWindowResize(GLFWwindow* window, int width, int height) {
    (void)width;
    (void)height;
    auto pApp =
        reinterpret_cast<Application*>(glfwGetWindowUserPointer(window));
    if (pApp != nullptr)
        pApp->onResize();
}

void onKeyCallback(GLFWwindow* window,
                   int key,
                   int scancode,
                   int action,
                   int mods) {
    (void)scancode;
    (void)mods;
    auto pApp =
        reinterpret_cast<Application*>(glfwGetWindowUserPointer(window));
    if (pApp != nullptr) {
        pApp->HandleKeyCallback(key, action);
    }
}

void onMouseCallback(GLFWwindow* window, double xpos, double ypos) {
    auto pApp =
        reinterpret_cast<Application*>(glfwGetWindowUserPointer(window));
    if (pApp != nullptr) {
        pApp->HandleMouseCallback(xpos, ypos);
    }
}

void OnDeviceError(const wgpu::Device& device,
                   wgpu::ErrorType type,
                   wgpu::StringView message) {
    std::cerr << "Uncaptured error: " << message.data << std::endl;
    exit(1);
}
// == Application == //

bool Application::onInit() {
    if (!initWindow())
        return false;
    if (!initDevice())
        return false;
    initSwapChain();
    initGui();
    initBuffers();
    loadCloudMesh();
    initTextures();
    initTextureViews();
    initBindGroupLayout();
    initBindGroup();
    initComputePipeline();
    initPresentPipeline();
    return true;
}

void Application::onFinish() {
    terminatePresentPipeline();
    terminateBindGroup();
    terminateTextureViews();
    terminateTextures();
    terminateBuffers();
    terminateComputePipeline();
    terminateBindGroupLayout();
    terminateGui();
    terminateSwapChain();
    terminateDevice();
    terminateWindow();
}

bool Application::isRunning() {
    return !glfwWindowShouldClose(m_window);
}

bool Application::initDevice() {
    // Create instance
    m_instance = wgpu::CreateInstance();
    if (!m_instance) {
        std::cerr << "Could not initialize WebGPU!" << std::endl;
        return false;
    }

    // Create surface and adapter
    std::cout << "Requesting adapter..." << std::endl;
    m_surface =
        wgpu::Surface::Acquire(glfwGetWGPUSurface(m_instance.Get(), m_window));
    wgpu::RequestAdapterOptions adapterOpts{};
    adapterOpts.compatibleSurface = m_surface;
    adapterOpts.powerPreference = wgpu::PowerPreference::HighPerformance;

    // Request adapter synchronously
    wgpu::Adapter tempAdapter = nullptr;
    auto future = m_instance.RequestAdapter(
        &adapterOpts, wgpu::CallbackMode::WaitAnyOnly,
        [](wgpu::RequestAdapterStatus status, wgpu::Adapter adapter,
           wgpu::StringView message, wgpu::Adapter* adapterOut) {
            if (status == wgpu::RequestAdapterStatus::Success) {
                *adapterOut = adapter;
            } else {
                std::cerr << "Failed to request adapter: " << message.data
                          << std::endl;
            }
        },
        &tempAdapter);

    wgpu::FutureWaitInfo waitInfo{future};
    m_instance.WaitAny(1, &waitInfo, 0);
    m_adapter = tempAdapter;
    std::cout << "Got adapter" << std::endl;

    std::cout << "Requesting device..." << std::endl;
    // Create device
    wgpu::DeviceDescriptor deviceDesc{};
    deviceDesc.label = wgpu::StringView("My Device");
    deviceDesc.requiredLimits = nullptr;
    deviceDesc.defaultQueue.label = wgpu::StringView("The default queue");

    // add error callback
    deviceDesc.SetUncapturedErrorCallback(OnDeviceError);

    // Request device synchronously
    wgpu::Device tempDevice = nullptr;
    auto deviceFuture = m_adapter.RequestDevice(
        &deviceDesc, wgpu::CallbackMode::WaitAnyOnly,
        [](wgpu::RequestDeviceStatus status, wgpu::Device device,
           wgpu::StringView message, wgpu::Device* deviceOut) {
            if (status == wgpu::RequestDeviceStatus::Success) {
                *deviceOut = device;
            } else {
                std::cerr << "Failed to request device: " << message.data
                          << std::endl;
            }
        },
        &tempDevice);

    wgpu::FutureWaitInfo deviceWaitInfo{deviceFuture};
    m_instance.WaitAny(1, &deviceWaitInfo, 0);
    m_device = tempDevice;

    if (!m_device) {
        std::cerr << "Failed to create device!" << std::endl;
        return false;
    }
    std::cout << "Got device" << std::endl;
    // print device type and name
    wgpu::AdapterInfo adapterProps;
    m_adapter.GetInfo(&adapterProps);
    std::cout << "Got adapter: {";
    std::cout << "vendor: " << adapterProps.vendor.data << ", ";
    std::cout << "architecture: " << adapterProps.architecture.data << ", ";
    std::cout << "device: " << adapterProps.device.data << ", ";
    std::cout << "description: " << adapterProps.description.data << ", ";
    std::cout << "vendorID: " << adapterProps.vendorID << ", ";
    std::cout << "deviceID: " << adapterProps.deviceID << ", ";
    std::cout << "subgroupMinSize: " << adapterProps.subgroupMinSize << ", ";
    std::cout << "subgroupMaxSize: " << adapterProps.subgroupMaxSize;
    std::cout << "}" << std::endl;

    m_queue = m_device.GetQueue();

    // Allow the GPU backend to process device creation
#ifdef WEBGPU_BACKEND_WGPU
    m_queue.Submit(0, nullptr);
#else
    m_instance.ProcessEvents();
#endif

    return true;
}

void Application::terminateDevice() {
    // RAII handles cleanup
}

bool Application::initWindow() {
    if (!glfwInit()) {
        std::cerr << "Could not initialize GLFW!" << std::endl;
        return false;
    }

    // Create window
    glfwWindowHint(GLFW_CLIENT_API, GLFW_NO_API);
    glfwWindowHint(GLFW_RESIZABLE, GLFW_TRUE);
    m_window = glfwCreateWindow(640, 480, "Sky High Clouds | Physically-Accurate Clouds", NULL, NULL);
    if (!m_window) {
        std::cerr << "Could not open window!" << std::endl;
        return false;
    }
#ifdef UNCAPPED_FPS
    glfwSwapInterval(0);
#else
    glfwSwapInterval(1);
#endif

    // Add window callbacks
    glfwSetWindowUserPointer(m_window, this);
    glfwSetFramebufferSizeCallback(m_window, onWindowResize);
    glfwSetKeyCallback(m_window, onKeyCallback);
    glfwSetCursorPosCallback(m_window, onMouseCallback);
    return true;
}

void Application::terminateWindow() {
    glfwDestroyWindow(m_window);
    glfwTerminate();
}

void Application::initSwapChain() {
    m_swapChainFormat = wgpu::TextureFormat::BGRA8Unorm;

    int width, height;
    glfwGetFramebufferSize(m_window, &width, &height);

    // Ensure device is ready before configuring surface
    m_instance.ProcessEvents();

    std::cout << "Configuring surface..." << std::endl;
    m_swapChainDesc = {};
    m_swapChainDesc.device = m_device;
    m_swapChainDesc.width = (uint32_t)width;
    m_swapChainDesc.height = (uint32_t)height;
    m_swapChainDesc.usage = wgpu::TextureUsage::RenderAttachment;
    m_swapChainDesc.format = m_swapChainFormat;
#ifdef UNCAPPED_FPS
    m_swapChainDesc.presentMode = wgpu::PresentMode::Immediate;
#else
    m_swapChainDesc.presentMode = wgpu::PresentMode::Fifo;
#endif
    m_surface.Configure(&m_swapChainDesc);
    std::cout << "Surface configured" << std::endl;
}

void Application::terminateSwapChain() {
    m_surface.Unconfigure();
}

void Application::initGui() {
    // Setup Dear ImGui context
    IMGUI_CHECKVERSION();
    ImGui::CreateContext();
    ImGuiIO& io = ImGui::GetIO();
    (void)io;

    // Setup Platform/Renderer backends
    ImGui_ImplGlfw_InitForOther(m_window, true);
    ImGui_ImplWGPU_InitInfo initInfo;
    initInfo.Device = m_device.Get();
    initInfo.RenderTargetFormat =
        static_cast<WGPUTextureFormat>(m_swapChainFormat);

    ImGui_ImplWGPU_Init(&initInfo);
}

void Application::terminateGui() {
    ImGui_ImplWGPU_Shutdown();
    ImGui_ImplGlfw_Shutdown();
}

void Application::terminateBuffers() {
    // RAII handles cleanup
}

void Application::initTextures() {
    int width = 640;
    int height = 480;
    glfwGetFramebufferSize(m_window, &width, &height);

    if (width <= 0)
        width = 1;
    if (height <= 0)
        height = 1;

    m_textureWidth = width;
    m_textureHeight = height;
    wgpu::Extent3D textureSize = {(uint32_t)width, (uint32_t)height, 1};

    wgpu::TextureDescriptor textureDesc{};
    textureDesc.dimension = wgpu::TextureDimension::e2D;
    textureDesc.format = wgpu::TextureFormat::RGBA8Unorm;
    textureDesc.size = textureSize;
    textureDesc.sampleCount = 1;
    textureDesc.viewFormatCount = 0;
    textureDesc.viewFormats = nullptr;
    textureDesc.mipLevelCount = 1;

    textureDesc.label = wgpu::StringView("Output");
    textureDesc.usage =
        (wgpu::TextureUsage::TextureBinding |
         wgpu::TextureUsage::StorageBinding | wgpu::TextureUsage::CopySrc);
    m_outputTexture = m_device.CreateTexture(&textureDesc);
}

void Application::terminateTextures() {
    // RAII handles cleanup
}

void Application::initTextureViews() {
    wgpu::TextureViewDescriptor textureViewDesc;
    textureViewDesc.aspect = wgpu::TextureAspect::All;
    textureViewDesc.baseArrayLayer = 0;
    textureViewDesc.arrayLayerCount = 1;
    textureViewDesc.dimension = wgpu::TextureViewDimension::e2D;
    textureViewDesc.format = wgpu::TextureFormat::RGBA8Unorm;
    textureViewDesc.mipLevelCount = 1;
    textureViewDesc.baseMipLevel = 0;

    textureViewDesc.label = wgpu::StringView("Output");
    m_outputTextureView = m_outputTexture.CreateView(&textureViewDesc);
}

void Application::terminateTextureViews() {
    // RAII handles cleanup
}

void Application::terminateBindGroup() {
    // RAII handles cleanup
}

void Application::terminateBindGroupLayout() {
    // RAII handles cleanup
}

void Application::initComputePipeline() {
    // Load compute shader
    wgpu::ShaderModule computeShaderModule =
        ResourceManager::loadShaderModule(RESOURCE_DIR "/ray.wgsl", m_device);
    if (!computeShaderModule) {
        std::cerr << "Failed to load shader resources/ray.wgsl" << std::endl;
        return;
    }

    // Create compute pipeline layout
    wgpu::PipelineLayoutDescriptor pipelineLayoutDesc;
    pipelineLayoutDesc.bindGroupLayoutCount = 1;
    pipelineLayoutDesc.bindGroupLayouts = &m_bindGroupLayout;
    m_pipelineLayout = m_device.CreatePipelineLayout(&pipelineLayoutDesc);

    // Create compute pipeline
    wgpu::ComputePipelineDescriptor computePipelineDesc;
    computePipelineDesc.compute.constantCount = 0;
    computePipelineDesc.compute.constants = nullptr;
    computePipelineDesc.compute.entryPoint = wgpu::StringView("main");
    computePipelineDesc.compute.module = computeShaderModule;
    computePipelineDesc.layout = m_pipelineLayout;

    m_pipeline = m_device.CreateComputePipeline(&computePipelineDesc);
}

void Application::terminateComputePipeline() {
    // RAII handles cleanup
}

void Application::initPresentBindGroup() {
    wgpu::BindGroupEntry entries[2]{};
    entries[0].binding = 0;
    entries[0].sampler = m_presentSampler;
    entries[1].binding = 1;
    entries[1].textureView = m_outputTextureView;

    wgpu::BindGroupDescriptor bindGroupDesc{};
    bindGroupDesc.layout = m_presentBindGroupLayout;
    bindGroupDesc.entryCount = 2;
    bindGroupDesc.entries = entries;
    m_presentBindGroup = m_device.CreateBindGroup(&bindGroupDesc);
}

void Application::initPresentPipeline() {
    wgpu::ShaderModule presentShaderModule = ResourceManager::loadShaderModule(
        RESOURCE_DIR "/present.wgsl", m_device);
    if (!presentShaderModule) {
        std::cerr << "Failed to load shader resources/present.wgsl"
                  << std::endl;
        return;
    }

    wgpu::BindGroupLayoutEntry bindings[2]{};
    bindings[0].binding = 0;
    bindings[0].visibility = wgpu::ShaderStage::Fragment;
    bindings[0].sampler.type = wgpu::SamplerBindingType::Filtering;

    bindings[1].binding = 1;
    bindings[1].visibility = wgpu::ShaderStage::Fragment;
    bindings[1].texture.sampleType = wgpu::TextureSampleType::Float;
    bindings[1].texture.viewDimension = wgpu::TextureViewDimension::e2D;
    bindings[1].texture.multisampled = false;

    wgpu::BindGroupLayoutDescriptor bindGroupLayoutDesc{};
    bindGroupLayoutDesc.entryCount = 2;
    bindGroupLayoutDesc.entries = bindings;
    m_presentBindGroupLayout =
        m_device.CreateBindGroupLayout(&bindGroupLayoutDesc);

    wgpu::PipelineLayoutDescriptor pipelineLayoutDesc{};
    pipelineLayoutDesc.bindGroupLayoutCount = 1;
    pipelineLayoutDesc.bindGroupLayouts = &m_presentBindGroupLayout;
    wgpu::PipelineLayout presentPipelineLayout =
        m_device.CreatePipelineLayout(&pipelineLayoutDesc);

    wgpu::SamplerDescriptor samplerDesc{};
    samplerDesc.minFilter = wgpu::FilterMode::Linear;
    samplerDesc.magFilter = wgpu::FilterMode::Linear;
    samplerDesc.mipmapFilter = wgpu::MipmapFilterMode::Nearest;
    samplerDesc.addressModeU = wgpu::AddressMode::ClampToEdge;
    samplerDesc.addressModeV = wgpu::AddressMode::ClampToEdge;
    samplerDesc.addressModeW = wgpu::AddressMode::ClampToEdge;
    m_presentSampler = m_device.CreateSampler(&samplerDesc);

    wgpu::ColorTargetState colorTarget{};
    colorTarget.format = m_swapChainFormat;

    wgpu::FragmentState fragmentState{};
    fragmentState.module = presentShaderModule;
    fragmentState.entryPoint = wgpu::StringView("fs_main");
    fragmentState.targetCount = 1;
    fragmentState.targets = &colorTarget;

    wgpu::RenderPipelineDescriptor pipelineDesc{};
    pipelineDesc.layout = presentPipelineLayout;
    pipelineDesc.vertex.module = presentShaderModule;
    pipelineDesc.vertex.entryPoint = wgpu::StringView("vs_main");
    pipelineDesc.vertex.bufferCount = 0;
    pipelineDesc.primitive.topology = wgpu::PrimitiveTopology::TriangleList;
    pipelineDesc.primitive.frontFace = wgpu::FrontFace::CCW;
    pipelineDesc.primitive.cullMode = wgpu::CullMode::None;
    pipelineDesc.multisample.count = 1;
    pipelineDesc.fragment = &fragmentState;

    m_presentPipeline = m_device.CreateRenderPipeline(&pipelineDesc);
    initPresentBindGroup();
}

void Application::terminatePresentPipeline() {
    // RAII handles cleanup
}

void Application::onFrame() {
    glfwPollEvents();

    // Calculate delta time
    double currentTime = glfwGetTime();
    if (m_lastFrameTime == 0.0) {
        m_lastFrameTime = currentTime;
    }
    float deltaTime = static_cast<float>(currentTime - m_lastFrameTime);
    m_lastFrameTime = currentTime;

    // Handle input
    handleKeyInput(deltaTime);

    // Get current surface texture
    wgpu::SurfaceTexture surfaceTexture;
    m_surface.GetCurrentTexture(&surfaceTexture);
    if (surfaceTexture.status !=
            wgpu::SurfaceGetCurrentTextureStatus::SuccessOptimal &&
        surfaceTexture.status !=
            wgpu::SurfaceGetCurrentTextureStatus::SuccessSuboptimal) {
        std::cerr << "Cannot acquire next surface texture" << std::endl;
        return;
    }

    // wgpu::TextureView nextTexture =
    //     wgpu::Texture(surfaceTexture.texture).CreateView();

    // WGPURenderPassColorAttachment renderPassColorAttachment{};
    // renderPassColorAttachment.view = nextTexture.Get();
    // renderPassColorAttachment.resolveTarget = nullptr;
    // renderPassColorAttachment.loadOp = WGPULoadOp_Clear;
    // renderPassColorAttachment.storeOp = WGPUStoreOp_Store;
    // renderPassColorAttachment.clearValue = WGPUColor{0.0, 0.0, 0.0, 1.0};

    // WGPURenderPassDescriptor renderPassDesc{};
    // renderPassDesc.colorAttachmentCount = 1;
    // renderPassDesc.colorAttachments = &renderPassColorAttachment;

    // wgpu::CommandEncoder encoder = m_device.CreateCommandEncoder();
    // wgpu::RenderPassEncoder renderPass = wgpu::RenderPassEncoder(
    //     wgpuCommandEncoderBeginRenderPass(encoder.Get(), &renderPassDesc));

    wgpu::TextureView nextTexture =
        wgpu::Texture(surfaceTexture.texture).CreateView();

    wgpu::CommandEncoder encoder = m_device.CreateCommandEncoder();

    wgpu::RenderPassColorAttachment backgroundAttachment{};
    backgroundAttachment.view = nextTexture;
    backgroundAttachment.loadOp = wgpu::LoadOp::Clear;
    backgroundAttachment.storeOp = wgpu::StoreOp::Store;
    backgroundAttachment.clearValue = {0.0, 0.0, 0.0, 1.0};

    wgpu::RenderPassDescriptor backgroundPassDesc{};
    backgroundPassDesc.colorAttachmentCount = 1;
    backgroundPassDesc.colorAttachments = &backgroundAttachment;

    if (m_presentPipeline && m_presentBindGroup) {
        wgpu::RenderPassEncoder backgroundPass =
            encoder.BeginRenderPass(&backgroundPassDesc);
        backgroundPass.SetPipeline(m_presentPipeline);
        backgroundPass.SetBindGroup(0, m_presentBindGroup, 0, nullptr);
        backgroundPass.Draw(3, 1, 0, 0);
        backgroundPass.End();
    }

    wgpu::RenderPassColorAttachment guiAttachment{};
    guiAttachment.view = nextTexture;
    guiAttachment.loadOp = wgpu::LoadOp::Load;
    guiAttachment.storeOp = wgpu::StoreOp::Store;

    wgpu::RenderPassDescriptor guiPassDesc{};
    guiPassDesc.colorAttachmentCount = 1;
    guiPassDesc.colorAttachments = &guiAttachment;

    wgpu::RenderPassEncoder guiPass = encoder.BeginRenderPass(&guiPassDesc);
    onGui(guiPass);
    guiPass.End();

    wgpu::CommandBuffer command = encoder.Finish();
    m_queue.Submit(1, &command);

    m_surface.Present();
#ifdef WEBGPU_BACKEND_WGPU
    m_queue.Submit(0, nullptr);
#else
    m_device.Tick();
#endif
}

void Application::onGui(RenderPassEncoder renderPass) {
    ImGui_ImplWGPU_NewFrame();
    ImGui_ImplGlfw_NewFrame();
    ImGui::NewFrame();

    ImGui::Begin("Settings");
    ImGuiIO& io = ImGui::GetIO();
    const float fps = io.Framerate;
    const float frameMs = (fps > 0.0f) ? (1000.0f / fps) : 0.0f;
    ImGui::Text("FPS: %.1f", fps);
    ImGui::Text("Frame time: %.3f ms", frameMs);
    if (ImGui::Button("Save Output")) {
        // TODO: Implement texture saving
        std::cout << "Save output not yet implemented" << std::endl;
    }
    ImGui::End();

    ImGui::Render();
    ImGui_ImplWGPU_RenderDrawData(ImGui::GetDrawData(), renderPass.Get());
}

void Application::onCompute() {
    if (!m_pipeline) {
        std::cerr << "Skipping compute: pipeline is invalid" << std::endl;
        return;
    }

    FrameCountData frameData = {m_frameCount, {0, 0, 0}};
    m_queue.WriteBuffer(m_frameCountBuffer, 0, &frameData, sizeof(frameData));

    if (m_cameraDataUpdated) {
        m_queue.WriteBuffer(m_uniformBuffer, 0, &m_cameraData,
                            sizeof(m_cameraData));
        m_cameraDataUpdated = false;
    }

    // Initialize a command encoder
    wgpu::CommandEncoderDescriptor encoderDesc{};
    wgpu::CommandEncoder encoder = m_device.CreateCommandEncoder(&encoderDesc);

    // Create compute pass
    wgpu::ComputePassDescriptor computePassDesc{};
    wgpu::ComputePassEncoder computePass =
        encoder.BeginComputePass(&computePassDesc);

    computePass.SetPipeline(m_pipeline);

    computePass.SetBindGroup(0, m_bindGroup, 0, nullptr);

    uint32_t invocationCountX = m_outputTexture.GetWidth();
    uint32_t invocationCountY = m_outputTexture.GetHeight();
    uint32_t workgroupSizePerDim = 8;
    // This ceils invocationCountX / workgroupSizePerDim
    uint32_t workgroupCountX =
        (invocationCountX + workgroupSizePerDim - 1) / workgroupSizePerDim;
    uint32_t workgroupCountY =
        (invocationCountY + workgroupSizePerDim - 1) / workgroupSizePerDim;
    computePass.DispatchWorkgroups(workgroupCountX, workgroupCountY, 1);

    // Finalize compute pass
    computePass.End();

    // Encode and submit the GPU commands
    wgpu::CommandBuffer commands = encoder.Finish();
    m_queue.Submit(1, &commands);

    ++m_frameCount;
}

void Application::onResize() {
    terminateSwapChain();
    initSwapChain();

    terminateTextureViews();
    terminateTextures();
    initTextures();
    initTextureViews();
    initBindGroup();
    initPresentBindGroup();

    m_frameCount = 0;
}

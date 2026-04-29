#pragma once

#include <webgpu/webgpu_cpp.h>

#include <GLFW/glfw3.h>

#include <gpuData.h>
#include <glm/glm.hpp>

class Application {
   public:
    // A function called only once at the beginning. Returns false is init
    // failed.
    bool onInit();

    // A function called only once at the very end.
    void onFinish();

    // A function that tells if the application is still running.
    bool isRunning();

    // A function called at each frame, guarantied never to be called before
    // `onInit`.
    void onFrame();

    // Where the GPU computation is actually issued
    void onCompute();

   public:
    // A function called when we should draw the GUI.
    void onGui(wgpu::RenderPassEncoder renderPass);

    // A function called when the window is resized.
    void onResize();

    // Input callbacks (public wrappers for GLFW callbacks)
    void HandleKeyCallback(int key, int action);
    void HandleMouseCallback(double xpos, double ypos);

   private:
    // Detailed steps
    bool initDevice();
    void terminateDevice();

    bool initWindow();
    void terminateWindow();

    void initSwapChain();
    void terminateSwapChain();

    void initGui();
    void terminateGui();

    void initBuffers();
    void terminateBuffers();

    void initTextures();
    void terminateTextures();

    void initTextureViews();
    void terminateTextureViews();

    void initBindGroup();
    void terminateBindGroup();

    void initBindGroupLayout();
    void terminateBindGroupLayout();

    void initComputePipeline();
    void terminateComputePipeline();

    void initPresentPipeline();
    void terminatePresentPipeline();
    void initPresentBindGroup();

   private:
    GLFWwindow* m_window = nullptr;
    wgpu::Surface m_surface = nullptr;
    wgpu::Instance m_instance = nullptr;
    wgpu::Adapter m_adapter = nullptr;
    wgpu::Device m_device = nullptr;
    wgpu::Queue m_queue = nullptr;
    wgpu::TextureFormat m_swapChainFormat = wgpu::TextureFormat::Undefined;
    wgpu::SurfaceConfiguration m_swapChainDesc;
    wgpu::Surface m_swapChain = nullptr;
    wgpu::BindGroup m_bindGroup = nullptr;
    wgpu::BindGroupLayout m_bindGroupLayout = nullptr;
    wgpu::PipelineLayout m_pipelineLayout = nullptr;
    wgpu::ComputePipeline m_pipeline = nullptr;
    wgpu::BindGroupLayout m_presentBindGroupLayout = nullptr;
    wgpu::BindGroup m_presentBindGroup = nullptr;
    wgpu::RenderPipeline m_presentPipeline = nullptr;
    wgpu::Sampler m_presentSampler = nullptr;
    // std::unique_ptr<wgpu::ErrorCallback> m_uncapturedErrorCallback;
    // std::unique_ptr<wgpu::DeviceLostCallback> m_deviceLostCallback;

    wgpu::Buffer m_uniformBuffer = nullptr;
    wgpu::Buffer m_worldBuffer = nullptr;
    wgpu::Buffer m_settingsBuffer = nullptr;
    wgpu::Buffer m_frameCountBuffer = nullptr;
    wgpu::Texture m_inputTexture = nullptr;
    wgpu::Texture m_outputTexture = nullptr;
    wgpu::TextureView m_inputTextureView = nullptr;
    wgpu::TextureView m_outputTextureView = nullptr;
    uint32_t m_textureWidth = 0;
    uint32_t m_textureHeight = 0;

    uint32_t m_frameCount = 0;

    // Input tracking
    bool m_mouseCaptured = false;
    double m_lastMouseX = 0.0;
    double m_lastMouseY = 0.0;
    bool m_keys[GLFW_KEY_LAST + 1] = {};  // GLFW key state tracking
    CameraData m_cameraData;
    float m_moveSpeed = 1.0f;
    float m_rotateSpeed = 0.002f;
    double m_lastFrameTime = 0.0;
    bool m_cameraDataUpdated = false;

    // Input handling
    void handleKeyInput(float deltaTime);
    void toggleMouseCapture();
};
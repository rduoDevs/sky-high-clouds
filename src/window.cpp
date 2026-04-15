#include "window.h"

#include <GL/glew.h>

#include "imgui.h"
#include "imgui_impl_glfw.h"
#include "imgui_impl_opengl3.h"

#include <algorithm>
#include <chrono>
#include <filesystem>
#include <iostream>
#include <vector>

namespace
{
constexpr float kSpeed = 1.0f;
constexpr float kRotateSpeed = 0.0015f;

std::string resolveResourcePath(const char *relativePath)
{
    namespace fs = std::filesystem;
    const fs::path rel(relativePath);
    const std::vector<fs::path> candidates = {
        fs::current_path() / rel,
        fs::current_path().parent_path() / rel,
        fs::current_path().parent_path().parent_path() / rel
    };

    for (const auto &candidate : candidates) {
        if (fs::exists(candidate)) {
            return candidate.string();
        }
    }

    return rel.string();
}
}

Window::Window(int width, int height, const char *title)
    : m_window(nullptr),
      m_width(width),
      m_height(height),
      m_title(title),
      m_initialized(false),
      //m_grid(16, 16, 16, 0.1f),
      ////m_sim(m_grid),
     // m_gridRenderer(),
     // m_gridRenderMode(GridRenderMode::VELOC),
      //m_camera(),
      //(nullptr),
      m_forward(0.0f),
      m_sideways(0.0f),
      m_vertical(0.0f),
      m_lastX(0.0),
      m_lastY(0.0),
      m_capture(false),
      m_paused(false),
      m_showParticles(true),
      m_velocityOverlay(false)
{
}

Window::~Window()
{
    shutdown();
}

int Window::run()
{
    if (!init()) {
        return -1;
    }

    using clock = std::chrono::steady_clock;
    auto lastTime = clock::now();

    while (!glfwWindowShouldClose(m_window)) {
        glfwPollEvents();

        auto now = clock::now();
        float deltaSeconds = std::chrono::duration<float>(now - lastTime).count();
        lastTime = now;

        renderFrame(deltaSeconds);
        glfwSwapBuffers(m_window);
    }

    shutdown();
    return 0;
}

bool Window::init()
{
    if (m_initialized) {
        return true;
    }

    if (!glfwInit()) {
        std::cerr << "Failed to initialize GLFW.\n";
        return false;
    }

    glfwWindowHint(GLFW_CONTEXT_VERSION_MAJOR, 3);
    glfwWindowHint(GLFW_CONTEXT_VERSION_MINOR, 3);
    glfwWindowHint(GLFW_OPENGL_PROFILE, GLFW_OPENGL_CORE_PROFILE);
#ifdef __APPLE__
    glfwWindowHint(GLFW_OPENGL_FORWARD_COMPAT, GL_TRUE);
#endif

    m_window = glfwCreateWindow(m_width, m_height, m_title, nullptr, nullptr);
    if (!m_window) {
        std::cerr << "Failed to create GLFW window.\n";
        glfwTerminate();
        return false;
    }

    glfwMakeContextCurrent(m_window);
    glfwSwapInterval(1);

    glfwSetWindowUserPointer(m_window, this);
    glfwSetFramebufferSizeCallback(m_window, framebufferSizeCallback);
    glfwSetKeyCallback(m_window, keyCallback);
    glfwSetMouseButtonCallback(m_window, mouseButtonCallback);
    glfwSetCursorPosCallback(m_window, cursorPosCallback);
    glfwSetScrollCallback(m_window, scrollCallback);
    glfwSetCharCallback(m_window, charCallback);

    glewExperimental = GL_TRUE;
    GLenum err = glewInit();
    if (err != GLEW_OK) {
        std::cerr << "Error while initializing GLEW: " << glewGetErrorString(err) << "\n";
        return false;
    }
    std::cout << "Successfully initialized GLEW " << glewGetString(GLEW_VERSION) << "\n";

    glClearColor(0.f, 0.f, 0.f, 1.f);
    glEnable(GL_DEPTH_TEST);
    glEnable(GL_CULL_FACE);
    glCullFace(GL_BACK);

    const std::string vertexPath = resolveResourcePath("resources/shaders/shader.vert");
    const std::string fragmentPath = resolveResourcePath("resources/shaders/shader.frag");
    // m_shader = new Shader(vertexPath, fragmentPath);

    // m_sim.init();
    // m_gridRenderer.init();

    // Eigen::Vector3f eye(0.f, 2.f, -5.f);
    // Eigen::Vector3f target(0.f, 1.f, 0.f);
    // m_camera.lookAt(eye, target);
    // m_camera.setOrbitPoint(target);
    // m_camera.setPerspective(120, m_width / static_cast<float>(m_height), 0.1f, 50.f);

    IMGUI_CHECKVERSION();
    ImGui::CreateContext();
    ImGuiIO &io = ImGui::GetIO();
    io.ConfigFlags |= ImGuiConfigFlags_NavEnableKeyboard;
    ImGui::StyleColorsDark();

    // Scale font globally
    io.FontGlobalScale = 1.5f;

    // Scale padding, spacing, etc.
    ImGuiStyle& style = ImGui::GetStyle();
    style.ScaleAllSizes(1.5f);

    ImGui_ImplGlfw_InitForOpenGL(m_window, false);
    ImGui_ImplOpenGL3_Init("#version 330");

    m_initialized = true;
    return true;
}

void Window::shutdown()
{
    if (!m_initialized) {
        return;
    }

    ImGui_ImplOpenGL3_Shutdown();
    ImGui_ImplGlfw_Shutdown();
    ImGui::DestroyContext();

    // if (m_shader) {
    //     delete m_shader;
    //     m_shader = nullptr;
    // }

    if (m_window) {
        glfwDestroyWindow(m_window);
        m_window = nullptr;
    }

    glfwTerminate();
    m_initialized = false;
}

void Window::renderFrame(float deltaSeconds)
{
    ImGui_ImplOpenGL3_NewFrame();
    ImGui_ImplGlfw_NewFrame();
    ImGui::NewFrame();

    renderUi();

    // if (!m_paused) {
    //     m_sim.update(deltaSeconds);
    // }

    updateCamera(deltaSeconds);
    renderScene();

    ImGui::Render();
    ImGui_ImplOpenGL3_RenderDrawData(ImGui::GetDrawData());
}

void Window::renderScene()
{
    glClear(GL_COLOR_BUFFER_BIT | GL_DEPTH_BUFFER_BIT);

    // m_shader->bind();
    // m_shader->setUniform("proj", m_camera.getProjection());
    // m_shader->setUniform("view", m_camera.getView());
    // m_gridRenderer.draw(m_shader, m_grid, m_gridRenderMode);
    // if (m_velocityOverlay && m_gridRenderMode != GridRenderMode::VELOC) {
    //     m_gridRenderer.draw(m_shader, m_grid, GridRenderMode::VELOC);
    // }
    // if (m_showParticles) {
    //     m_gridRenderer.drawParticles(m_shader, m_grid, m_sim.particles());
    // }
    // m_shader->unbind();
}

void Window::updateCamera(float deltaSeconds)
{
    // auto look = m_camera.getLook();
    // look.y() = 0.f;
    // look.normalize();
    // Eigen::Vector3f perp(-look.z(), 0.f, look.x());
    // Eigen::Vector3f moveVec = m_forward * look.normalized()
    //                           + m_sideways * perp.normalized()
    //                           + m_vertical * Eigen::Vector3f::UnitY();
    // moveVec *= deltaSeconds;
    // m_camera.move(moveVec);
}

void Window::renderUi()
{
    ImGuiIO &io = ImGui::GetIO();

    ImGui::Begin("Simulation");
    ImGui::Text("FPS: %.1f", io.Framerate);
    ImGui::Checkbox("Pause Simulation", &m_paused);
    ImGui::Button("Take a Screenshot!");
    // if (ImGui::Button("Reset Grid")) {
    //     //m_sim.resetGridToInitial();
    // }
    // if (ImGui::Button("Toggle Orbit")) {
    //    // m_camera.toggleIsOrbiting();
    // }

    ImGui::Separator();
    int mode = 0;
    // switch (m_gridRenderMode) {
    // case GridRenderMode::GRID_CENTER: mode = 0; break;
    // case GridRenderMode::VELOC: mode = 1; break;
    // case GridRenderMode::DENSITY: mode = 2; break;
    // case GridRenderMode::PRESSURE: mode = 3; break;
    // }
    ImGui::Text("Noise Selection");
    ImGui::RadioButton("Perlin", &mode, 0);
    ImGui::RadioButton("Worley", &mode, 1);
    ImGui::RadioButton("Hybrid", &mode, 2);
    // switch (mode) {
    // case 0: m_gridRenderMode = GridRenderMode::GRID_CENTER; break;
    // case 1: m_gridRenderMode = GridRenderMode::VELOC; break;
    // case 2: m_gridRenderMode = GridRenderMode::DENSITY; break;
    // case 3: m_gridRenderMode = GridRenderMode::PRESSURE; break;
    // default: break;
    // }


    ImGui::Separator();
    ImGui::Text("Mesh");
    ImGui::Button("Upload Cloud Mesh");

    // int particleCount = 200; //m_sim.particleCount();
    // if (ImGui::SliderInt("Particle Count", &particleCount, 200, 10000)) {
    //   //  m_sim.setParticleCount(particleCount);
    // }

    // int spawnMode = 1; //static_cast<int>(m_sim.particleSpawnMode());
    // ImGui::Text("Spawn Mode");
    // ImGui::RadioButton("Sphere Volume", &spawnMode, 3);
    // if (spawnMode != 1 ){//static_cast<int>(m_sim.particleSpawnMode())) {
    //  //   m_sim.setParticleSpawnMode(static_cast<ParticleSpawnMode>(spawnMode));
    // }
    // // if (m_sim.particleSpawnMode() == ParticleSpawnMode::SPHERE_VOLUME) {
    // //     float radius = m_sim.particleSpawnSphereRadius();
    // //     const float maxRadius = 0.5f * std::min(m_grid.nx * m_grid.cellSize,
    // //                                             std::min(m_grid.ny * m_grid.cellSize,
    // //                                                      m_grid.nz * m_grid.cellSize));
    // //     if (ImGui::SliderFloat("Sphere Radius", &radius, 0.0f, maxRadius)) {
    // //         m_sim.setParticleSpawnSphereRadius(radius);
    // //     }
    // // }
    // ImGui::RadioButton("Vortex Ring", &spawnMode, 0);
    // ImGui::RadioButton("Cell Centers", &spawnMode, 1);
    // ImGui::RadioButton("Random In Cell", &spawnMode, 2);

    ImGui::Separator();
    ImGui::Text("Renderer: WebGPU");
    // ImGui::Text("WASD + R/F: move");
    // ImGui::Text("Mouse drag: orbit");
    // ImGui::Text("Scroll: zoom");
    // ImGui::Text("1/2/3/4: render mode");
    // ImGui::Text("Space: respawn particles");
    // ImGui::Text("O: reset grid");
    // ImGui::Text("P: pause");
    ImGui::Separator();
    ImGui::End();
}

void Window::handleResize(int width, int height)
{
    if (height == 0) {
        return;
    }

    m_width = width;
    m_height = height;
    glViewport(0, 0, width, height);
   // m_camera.setAspect(static_cast<float>(width) / static_cast<float>(height));
}

void Window::onKey(int key, int action)
{
    ImGuiIO &io = ImGui::GetIO();
    if (io.WantCaptureKeyboard) {
        return;
    }

    // Eigen::Vector3f impulsePoint(0.5f * m_grid.nx * m_grid.cellSize,0.3f * m_grid.ny * m_grid.cellSize,0.5f * m_grid.nz * m_grid.cellSize);
    // if (action == GLFW_PRESS) {
    //     switch (key) {
    //     case GLFW_KEY_J: {
    //         Eigen::Vector3f force = Eigen::Vector3f(0.f,1.f,0.f);
    //         m_sim.impulse(impulsePoint, force);
    //         break;
    //     }
    //     case GLFW_KEY_Y: {
    //         m_sim.m_isCounting = true;
    //         m_sim.m_count = 0;
    //         break;
    //     }
    //     case GLFW_KEY_K: {
    //         Eigen::Vector3f force = Eigen::Vector3f(1.f,1.f,1.f);
    //         m_sim.impulse(impulsePoint, force);
    //         break;
    //     }
    //     case GLFW_KEY_L: {
    //         Eigen::Vector3f force = Eigen::Vector3f(-1.f,-1.f,-1.f);
    //         m_sim.impulse(impulsePoint, force);
    //         break;
    //     }
    //     case GLFW_KEY_I: {
    //         Eigen::Vector3f force = Eigen::Vector3f(0.f,-1.f,0.f);
    //         m_sim.impulse(impulsePoint, force);
    //         break;
    //     }

        // case GLFW_KEY_P: m_paused = !m_paused; break;
        // case GLFW_KEY_W: m_forward += kSpeed; break;
        // case GLFW_KEY_S: m_forward -= kSpeed; break;
        // case GLFW_KEY_A: m_sideways -= kSpeed; break;
        // case GLFW_KEY_D: m_sideways += kSpeed; break;
        // case GLFW_KEY_F: m_vertical -= kSpeed; break;
        // case GLFW_KEY_R: m_vertical += kSpeed; break;
        // case GLFW_KEY_1: m_gridRenderMode = GridRenderMode::GRID_CENTER; break;
        // case GLFW_KEY_2: m_gridRenderMode = GridRenderMode::VELOC; break;
        // case GLFW_KEY_3: m_gridRenderMode = GridRenderMode::DENSITY; break;
        // case GLFW_KEY_4: m_gridRenderMode = GridRenderMode::PRESSURE; break;
        // case GLFW_KEY_SPACE: m_sim.resetParticles(); break;
        // case GLFW_KEY_O: m_sim.resetGridToInitial(); break;
        // case GLFW_KEY_C: m_camera.toggleIsOrbiting(); break;
        // case GLFW_KEY_ESCAPE: glfwSetWindowShouldClose(m_window, GLFW_TRUE); break;
        //default: break;
        //}
    // } else if (action == GLFW_RELEASE) {
    //     switch (key) {
    //     case GLFW_KEY_W: m_forward -= kSpeed; break;
    //     case GLFW_KEY_S: m_forward += kSpeed; break;
    //     case GLFW_KEY_A: m_sideways += kSpeed; break;
    //     case GLFW_KEY_D: m_sideways -= kSpeed; break;
    //     case GLFW_KEY_F: m_vertical += kSpeed; break;
    //     case GLFW_KEY_R: m_vertical -= kSpeed; break;
    //     default: break;
    //     }
    // }
}

void Window::onMouseButton(int button, int action)
{
    ImGuiIO &io = ImGui::GetIO();
    if (io.WantCaptureMouse) {
        return;
    }

    if (button == GLFW_MOUSE_BUTTON_LEFT) {
        if (action == GLFW_PRESS) {
            m_capture = true;
            glfwGetCursorPos(m_window, &m_lastX, &m_lastY);
        } else if (action == GLFW_RELEASE) {
            m_capture = false;
        }
    }
}

void Window::onCursorPos(double xpos, double ypos)
{
    ImGuiIO &io = ImGui::GetIO();
    if (io.WantCaptureMouse || !m_capture) {
        return;
    }

    double deltaX = xpos - m_lastX;
    double deltaY = ypos - m_lastY;

    if (deltaX == 0.0 && deltaY == 0.0) {
        return;
    }

    // m_camera.rotate(static_cast<float>(deltaY) * kRotateSpeed,
    //                 static_cast<float>(-deltaX) * kRotateSpeed);

    m_lastX = xpos;
    m_lastY = ypos;
}

void Window::onScroll(double yoffset)
{
    ImGuiIO &io = ImGui::GetIO();
    if (io.WantCaptureMouse) {
        return;
    }

    float zoom = 1.f - static_cast<float>(yoffset) * 0.1f;
    //m_camera.zoom(zoom);
}

void Window::onChar(unsigned int codepoint)
{
    (void)codepoint;
}

void Window::framebufferSizeCallback(GLFWwindow *window, int width, int height)
{
    Window *self = static_cast<Window *>(glfwGetWindowUserPointer(window));
    if (self) {
        self->handleResize(width, height);
    }
}

void Window::keyCallback(GLFWwindow *window, int key, int scancode, int action, int mods)
{
    (void)scancode;
    (void)mods;
    ImGui_ImplGlfw_KeyCallback(window, key, scancode, action, mods);

    Window *self = static_cast<Window *>(glfwGetWindowUserPointer(window));
    if (self) {
        self->onKey(key, action);
    }
}

void Window::mouseButtonCallback(GLFWwindow *window, int button, int action, int mods)
{
    ImGui_ImplGlfw_MouseButtonCallback(window, button, action, mods);

    Window *self = static_cast<Window *>(glfwGetWindowUserPointer(window));
    if (self) {
        self->onMouseButton(button, action);
    }
}

void Window::cursorPosCallback(GLFWwindow *window, double xpos, double ypos)
{
    ImGui_ImplGlfw_CursorPosCallback(window, xpos, ypos);

    Window *self = static_cast<Window *>(glfwGetWindowUserPointer(window));
    if (self) {
        self->onCursorPos(xpos, ypos);
    }
}

void Window::scrollCallback(GLFWwindow *window, double xoffset, double yoffset)
{
    (void)xoffset;
    ImGui_ImplGlfw_ScrollCallback(window, xoffset, yoffset);

    Window *self = static_cast<Window *>(glfwGetWindowUserPointer(window));
    if (self) {
        self->onScroll(yoffset);
    }
}

void Window::charCallback(GLFWwindow *window, unsigned int codepoint)
{
    ImGui_ImplGlfw_CharCallback(window, codepoint);

    Window *self = static_cast<Window *>(glfwGetWindowUserPointer(window));
    if (self) {
        self->onChar(codepoint);
    }
}

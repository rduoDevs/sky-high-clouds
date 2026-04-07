#pragma once

#include "simulation.h"
#include "gridrenderer.h"
#include "grid.h"
#include "graphics/camera.h"
#include "graphics/shader.h"

#include <GLFW/glfw3.h>

class Window {
public:
    Window(int width = 800, int height = 600, const char *title = "Fluid Simulation");
    ~Window();

    int run();

private:
    bool init();
    void shutdown();

    void renderFrame(float deltaSeconds);
    void updateCamera(float deltaSeconds);
    void renderUi();
    void renderScene();
    void handleResize(int width, int height);

    void onKey(int key, int action);
    void onMouseButton(int button, int action);
    void onCursorPos(double xpos, double ypos);
    void onScroll(double yoffset);
    void onChar(unsigned int codepoint);

    static void framebufferSizeCallback(GLFWwindow *window, int width, int height);
    static void keyCallback(GLFWwindow *window, int key, int scancode, int action, int mods);
    static void mouseButtonCallback(GLFWwindow *window, int button, int action, int mods);
    static void cursorPosCallback(GLFWwindow *window, double xpos, double ypos);
    static void scrollCallback(GLFWwindow *window, double xoffset, double yoffset);
    static void charCallback(GLFWwindow *window, unsigned int codepoint);

private:
    GLFWwindow *m_window;
    int m_width;
    int m_height;
    const char *m_title;
    bool m_initialized;

    Grid m_grid;
    Simulation m_sim;
    GridRenderer m_gridRenderer;
    GridRenderMode m_gridRenderMode;
    Camera m_camera;
    Shader *m_shader;

    float m_forward;
    float m_sideways;
    float m_vertical;

    double m_lastX;
    double m_lastY;

    bool m_capture;
    bool m_paused;
    bool m_showParticles;
    bool m_velocityOverlay;
};

#pragma once

#include <GL/glew.h>

#include "graphics/shape.h"
#include "grid.h"
#include "simulation.h"

class Shader;

enum class GridRenderMode
{
    GRID_CENTER = 0,
    VELOC = 1,
    DENSITY = 2,
    PRESSURE = 3
};

class GridRenderer
{
    public:
        GridRenderer();

        void init();

        void update(double seconds);

        void draw(Shader *shader, const Grid &grid, GridRenderMode mode);
        void drawParticles(Shader *shader, const Grid &grid, const std::vector<Particle> &particles);
    
    private:
        Shape m_domainCube;
        GLuint m_pointsVao;
        GLuint m_pointsVbo;
        GLuint m_arrowsVao;
        GLuint m_arrowsVbo;
        GLuint m_sphereVao;
        GLuint m_sphereVbo;
        GLuint m_sphereIbo;
        GLuint m_instanceVbo;
        GLuint m_particlesVao;
        GLuint m_particlesVbo;
        GLsizei m_numPointVertices;
        GLsizei m_numArrowVertices;
        GLsizei m_numSphereIndices;
        GLsizei m_numSphereInstances;
        GLsizei m_numParticles;
        float max_veloc = 0.f;
        float m_sphereScale = 0.04f;

        void initDomainCube();
        void initDebugGeometryBuffers();
        void initSphereGeometry();
        void initParticleBuffers();
        void updateDomainCubeTransform(const Grid &grid);
        void uploadCellCenterPoints(const Grid &grid);
        void uploadVelocityArrows(const Grid &grid);
        void uploadScalarSpheres(const Grid &grid, bool useDensity);
        void uploadParticles(const Grid &grid, const std::vector<Particle> &particles);
        void drawCellCenters(Shader *shader);
        void drawVelocityArrows(Shader *shader);
        void drawScalarSpheres(Shader *shader);
        void drawParticlePoints(Shader *shader);
};

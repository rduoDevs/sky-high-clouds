#include "gridrenderer.h"
#include "graphics/shader.h"

#include <Eigen/Geometry>

#include <algorithm>
#include <cmath>
#include <iostream>
#include <limits>
#include <vector>

using namespace Eigen;

namespace
{
struct DebugVertex
{
    GLfloat px;
    GLfloat py;
    GLfloat pz;
    GLfloat nx;
    GLfloat ny;
    GLfloat nz;
};

struct InstanceData
{
    GLfloat ox;
    GLfloat oy;
    GLfloat oz;
    GLfloat value;
};

Vector3f toRenderSpaceCenter(const Grid &grid, int i, int j, int k)
{
    const float fx = (static_cast<float>(i) + 0.5f) / static_cast<float>(grid.nx);
    const float fy = (static_cast<float>(j) + 0.5f) / static_cast<float>(grid.ny);
    const float fz = (static_cast<float>(k) + 0.5f) / static_cast<float>(grid.nz);
    return Vector3f(2.f * fx - 1.f, 2.f * fy - 1.f, 2.f * fz - 1.f);
}

Vector3f toRenderSpacePosition(const Grid &grid, const Vector3f &pos)
{
    const float sx = static_cast<float>(grid.nx) * grid.cellSize;
    const float sy = static_cast<float>(grid.ny) * grid.cellSize;
    const float sz = static_cast<float>(grid.nz) * grid.cellSize;

    const float fx = sx > 0.0f ? (pos.x() / sx) : 0.0f;
    const float fy = sy > 0.0f ? (pos.y() / sy) : 0.0f;
    const float fz = sz > 0.0f ? (pos.z() / sz) : 0.0f;

    return Vector3f(2.f * fx - 1.f, 2.f * fy - 1.f, 2.f * fz - 1.f);
}
}

GridRenderer::GridRenderer()
    : m_pointsVao(0),
      m_pointsVbo(0),
      m_arrowsVao(0),
      m_arrowsVbo(0),
      m_sphereVao(0),
      m_sphereVbo(0),
      m_sphereIbo(0),
      m_instanceVbo(0),
      m_particlesVao(0),
      m_particlesVbo(0),
      m_numPointVertices(0),
      m_numArrowVertices(0),
      m_numSphereIndices(0),
      m_numSphereInstances(0),
      m_numParticles(0)
{
}

void GridRenderer::init()
{
    initDomainCube();
    initDebugGeometryBuffers();
    initSphereGeometry();
    initParticleBuffers();
}

void GridRenderer::draw(Shader *shader, const Grid &grid, GridRenderMode mode)
{
    updateDomainCubeTransform(grid);
    shader->setUniform("renderMode", 0);

    if (mode == GridRenderMode::VELOC) {
        uploadVelocityArrows(grid);
    } else if (mode == GridRenderMode::DENSITY || mode == GridRenderMode::PRESSURE) {
        uploadScalarSpheres(grid, mode == GridRenderMode::DENSITY);
    } else {
        m_numArrowVertices = 0;
        uploadCellCenterPoints(grid);
    }

    m_domainCube.draw(shader);
    if (mode == GridRenderMode::VELOC) {
        drawVelocityArrows(shader);
    } else if (mode == GridRenderMode::DENSITY || mode == GridRenderMode::PRESSURE) {
        drawScalarSpheres(shader);
    } else {
        drawCellCenters(shader);
    }
}

void GridRenderer::update(double seconds)
{
    
}

void GridRenderer::drawParticles(Shader *shader, const Grid &grid, const std::vector<Particle> &particles)
{
    uploadParticles(grid, particles);
    drawParticlePoints(shader);
}

void GridRenderer::initDomainCube()
{
    std::vector<Eigen::Vector3d> verts = {
        {-1,-1,-1},{1,-1,-1},{1,1,-1},{-1,1,-1},
        {-1,-1,1},{1,-1,1},{1,1,1},{-1,1,1}
    };

    std::vector<Eigen::Vector2i> edges = {
        {0,1},{1,2},{2,3},{3,0}, 
        {4,5},{5,6},{6,7},{7,4}, 
        {0,4},{1,5},{2,6},{3,7}  
    };

    m_domainCube.initEdges(verts, edges);

}

void GridRenderer::initDebugGeometryBuffers()
{
    glGenVertexArrays(1, &m_pointsVao);
    glGenBuffers(1, &m_pointsVbo);

    glBindVertexArray(m_pointsVao);
    glBindBuffer(GL_ARRAY_BUFFER, m_pointsVbo);
    glBufferData(GL_ARRAY_BUFFER, 0, nullptr, GL_DYNAMIC_DRAW);
    glEnableVertexAttribArray(0);
    glVertexAttribPointer(0, 3, GL_FLOAT, GL_FALSE, sizeof(DebugVertex), reinterpret_cast<void *>(0));
    glEnableVertexAttribArray(1);
    glVertexAttribPointer(1, 3, GL_FLOAT, GL_FALSE, sizeof(DebugVertex), reinterpret_cast<void *>(3 * sizeof(GLfloat)));
    glBindVertexArray(0);
    glBindBuffer(GL_ARRAY_BUFFER, 0);

    glGenVertexArrays(1, &m_arrowsVao);
    glGenBuffers(1, &m_arrowsVbo);

    glBindVertexArray(m_arrowsVao);
    glBindBuffer(GL_ARRAY_BUFFER, m_arrowsVbo);
    glBufferData(GL_ARRAY_BUFFER, 0, nullptr, GL_DYNAMIC_DRAW);
    glEnableVertexAttribArray(0);
    glVertexAttribPointer(0, 3, GL_FLOAT, GL_FALSE, sizeof(DebugVertex), reinterpret_cast<void *>(0));
    glEnableVertexAttribArray(1);
    glVertexAttribPointer(1, 3, GL_FLOAT, GL_FALSE, sizeof(DebugVertex), reinterpret_cast<void *>(3 * sizeof(GLfloat)));
    glBindVertexArray(0);
    glBindBuffer(GL_ARRAY_BUFFER, 0);
}

void GridRenderer::initSphereGeometry()
{
    static constexpr int kStacks = 12;
    static constexpr int kSlices = 24;
    static constexpr float kPi = 3.14159265359f;
    static constexpr float kTwoPi = 6.28318530718f;

    std::vector<float> vertices;
    std::vector<unsigned int> indices;

    vertices.reserve(static_cast<size_t>((kStacks + 1) * (kSlices + 1) * 3));

    for (int i = 0; i <= kStacks; ++i) {
        float v = static_cast<float>(i) / static_cast<float>(kStacks);
        float phi = v * kPi;
        float sinPhi = std::sin(phi);
        float cosPhi = std::cos(phi);

        for (int j = 0; j <= kSlices; ++j) {
            float u = static_cast<float>(j) / static_cast<float>(kSlices);
            float theta = u * kTwoPi;
            float sinTheta = std::sin(theta);
            float cosTheta = std::cos(theta);

            vertices.push_back(sinPhi * cosTheta);
            vertices.push_back(cosPhi);
            vertices.push_back(sinPhi * sinTheta);
        }
    }

    for (int i = 0; i < kStacks; ++i) {
        for (int j = 0; j < kSlices; ++j) {
            int first = i * (kSlices + 1) + j;
            int second = first + kSlices + 1;

            indices.push_back(static_cast<unsigned int>(first));
            indices.push_back(static_cast<unsigned int>(second));
            indices.push_back(static_cast<unsigned int>(first + 1));

            indices.push_back(static_cast<unsigned int>(second));
            indices.push_back(static_cast<unsigned int>(second + 1));
            indices.push_back(static_cast<unsigned int>(first + 1));
        }
    }

    m_numSphereIndices = static_cast<GLsizei>(indices.size());

    glGenVertexArrays(1, &m_sphereVao);
    glGenBuffers(1, &m_sphereVbo);
    glGenBuffers(1, &m_sphereIbo);
    glGenBuffers(1, &m_instanceVbo);

    glBindVertexArray(m_sphereVao);

    glBindBuffer(GL_ARRAY_BUFFER, m_sphereVbo);
    glBufferData(
        GL_ARRAY_BUFFER,
        static_cast<GLsizeiptr>(vertices.size() * sizeof(float)),
        vertices.data(),
        GL_STATIC_DRAW
    );
    glEnableVertexAttribArray(0);
    glVertexAttribPointer(0, 3, GL_FLOAT, GL_FALSE, 3 * sizeof(float), reinterpret_cast<void *>(0));

    glBindBuffer(GL_ELEMENT_ARRAY_BUFFER, m_sphereIbo);
    glBufferData(
        GL_ELEMENT_ARRAY_BUFFER,
        static_cast<GLsizeiptr>(indices.size() * sizeof(unsigned int)),
        indices.data(),
        GL_STATIC_DRAW
    );

    glBindBuffer(GL_ARRAY_BUFFER, m_instanceVbo);
    glBufferData(GL_ARRAY_BUFFER, 0, nullptr, GL_DYNAMIC_DRAW);
    glEnableVertexAttribArray(2);
    glVertexAttribPointer(2, 3, GL_FLOAT, GL_FALSE, sizeof(InstanceData), reinterpret_cast<void *>(0));
    glVertexAttribDivisor(2, 1);
    glEnableVertexAttribArray(3);
    glVertexAttribPointer(3, 1, GL_FLOAT, GL_FALSE, sizeof(InstanceData), reinterpret_cast<void *>(3 * sizeof(GLfloat)));
    glVertexAttribDivisor(3, 1);

    glBindVertexArray(0);
    glBindBuffer(GL_ARRAY_BUFFER, 0);
}

void GridRenderer::initParticleBuffers()
{
    glGenVertexArrays(1, &m_particlesVao);
    glGenBuffers(1, &m_particlesVbo);

    glBindVertexArray(m_particlesVao);
    glBindBuffer(GL_ARRAY_BUFFER, m_particlesVbo);
    glBufferData(GL_ARRAY_BUFFER, 0, nullptr, GL_DYNAMIC_DRAW);
    glEnableVertexAttribArray(0);
    glVertexAttribPointer(0, 3, GL_FLOAT, GL_FALSE, sizeof(DebugVertex), reinterpret_cast<void *>(0));
    glEnableVertexAttribArray(1);
    glVertexAttribPointer(1, 3, GL_FLOAT, GL_FALSE, sizeof(DebugVertex), reinterpret_cast<void *>(3 * sizeof(GLfloat)));
    glBindVertexArray(0);
    glBindBuffer(GL_ARRAY_BUFFER, 0);
}

void GridRenderer::updateDomainCubeTransform(const Grid &grid)
{
    (void)grid;
    m_domainCube.setModelMatrix(Affine3f::Identity());
}

void GridRenderer::uploadCellCenterPoints(const Grid &grid)
{
    std::vector<DebugVertex> vertices;
    vertices.reserve(static_cast<size_t>(grid.nx) * grid.ny * grid.nz);

    for (int k = 0; k < grid.nz; ++k) {
        for (int j = 0; j < grid.ny; ++j) {
            for (int i = 0; i < grid.nx; ++i) {
                const Vector3f c = toRenderSpaceCenter(grid, i, j, k);
                vertices.push_back({c.x(), c.y(), c.z(), 0.f, 1.f, 0.f});
            }
        }
    }

    m_numPointVertices = static_cast<GLsizei>(vertices.size());

    glBindBuffer(GL_ARRAY_BUFFER, m_pointsVbo);
    glBufferData(
        GL_ARRAY_BUFFER,
        static_cast<GLsizeiptr>(vertices.size() * sizeof(DebugVertex)),
        vertices.data(),
        GL_DYNAMIC_DRAW
    );
    glBindBuffer(GL_ARRAY_BUFFER, 0);
}

void GridRenderer::uploadVelocityArrows(const Grid &grid)
{
    static constexpr float kVelocityArrowScale = 0.15f;
    static constexpr float kMinVelocity = 1e-6f;

    std::vector<DebugVertex> vertices;
    vertices.reserve(static_cast<size_t>(grid.nx) * grid.ny * grid.nz * 6);

    const Vector3f domainExtents(
        static_cast<float>(grid.nx) * grid.cellSize,
        static_cast<float>(grid.ny) * grid.cellSize,
        static_cast<float>(grid.nz) * grid.cellSize
        );

    for (int k = 0; k < grid.nz; ++k) {
        for (int j = 0; j < grid.ny; ++j) {
            for (int i = 0; i < grid.nx; ++i) {

                const Vector3f start = toRenderSpaceCenter(grid, i, j, k);
                const Vector3f vel = grid.at(i, j, k).velocity;

                const Vector3f velRender(
                    domainExtents.x() > 0.f ? (2.f * vel.x() / domainExtents.x()) : 0.f,
                    domainExtents.y() > 0.f ? (2.f * vel.y() / domainExtents.y()) : 0.f,
                    domainExtents.z() > 0.f ? (2.f * vel.z() / domainExtents.z()) : 0.f
                    );

                float mag = velRender.norm();
                max_veloc = std::max(max_veloc, mag);
                if (mag < kMinVelocity)
                    continue;

                Vector3f dir = velRender / mag;

                // Shaft length
                float arrowLength = mag * kVelocityArrowScale;
                Vector3f end = start + dir * arrowLength;

                // Main arrow line
                vertices.push_back({start.x(), start.y(), start.z(), vel.x(), vel.y(), vel.z()});
                vertices.push_back({end.x(), end.y(), end.z(), vel.x(), vel.y(), vel.z()});

                // ---- Arrowhead ----

                Vector3f perp(-dir.y(), dir.x(), 0.0f);
                if (perp.squaredNorm() < 1e-6f)
                    perp = Vector3f(0.0f, -dir.z(), dir.y());

                perp.normalize();

                float headLength = arrowLength * 0.25f;
                float headWidth  = arrowLength * 0.15f;

                Vector3f back = end - dir * headLength;

                Vector3f left  = back + perp * headWidth;
                Vector3f right = back - perp * headWidth;

                // Left wing
                vertices.push_back({end.x(), end.y(), end.z(), vel.x(), vel.y(), vel.z()});
                vertices.push_back({left.x(), left.y(), left.z(), vel.x(), vel.y(), vel.z()});

                // Right wing
                vertices.push_back({end.x(), end.y(), end.z(), vel.x(), vel.y(), vel.z()});
                vertices.push_back({right.x(), right.y(), right.z(), vel.x(), vel.y(), vel.z()});
            }
        }
    }

    m_numArrowVertices = static_cast<GLsizei>(vertices.size());

    glBindBuffer(GL_ARRAY_BUFFER, m_arrowsVbo);
    glBufferData(
        GL_ARRAY_BUFFER,
        static_cast<GLsizeiptr>(vertices.size() * sizeof(DebugVertex)),
        vertices.data(),
        GL_DYNAMIC_DRAW
        );
    glBindBuffer(GL_ARRAY_BUFFER, 0);
}

void GridRenderer::uploadScalarSpheres(const Grid &grid, bool useDensity)
{
    std::vector<InstanceData> instances;
    instances.reserve(static_cast<size_t>(grid.nx) * grid.ny * grid.nz);

    float minValue = std::numeric_limits<float>::max();
    float maxValue = std::numeric_limits<float>::lowest();

    for (int k = 0; k < grid.nz; ++k) {
        for (int j = 0; j < grid.ny; ++j) {
            for (int i = 0; i < grid.nx; ++i) {
                const GridCell &cell = grid.at(i, j, k);
                float value = useDensity ? cell.density : cell.pressure;
                minValue = std::min(minValue, value);
                maxValue = std::max(maxValue, value);
            }
        }
    }

    const float range = std::max(1e-6f, maxValue - minValue);

    for (int k = 0; k < grid.nz; ++k) {
        for (int j = 0; j < grid.ny; ++j) {
            for (int i = 0; i < grid.nx; ++i) {
                const Vector3f c = toRenderSpaceCenter(grid, i, j, k);
                const GridCell &cell = grid.at(i, j, k);
                float value = useDensity ? cell.density : cell.pressure;
                float normalized = (value - minValue) / range;
                instances.push_back({c.x(), c.y(), c.z(), normalized});
            }
        }
    }

    m_numSphereInstances = static_cast<GLsizei>(instances.size());

    glBindBuffer(GL_ARRAY_BUFFER, m_instanceVbo);
    glBufferData(
        GL_ARRAY_BUFFER,
        static_cast<GLsizeiptr>(instances.size() * sizeof(InstanceData)),
        instances.data(),
        GL_DYNAMIC_DRAW
    );
    glBindBuffer(GL_ARRAY_BUFFER, 0);

    const float cellX = grid.nx > 0 ? (2.0f / static_cast<float>(grid.nx)) : 0.1f;
    const float cellY = grid.ny > 0 ? (2.0f / static_cast<float>(grid.ny)) : 0.1f;
    const float cellZ = grid.nz > 0 ? (2.0f / static_cast<float>(grid.nz)) : 0.1f;
    const float cellMin = std::min(cellX, std::min(cellY, cellZ));
    m_sphereScale = 0.3f * cellMin;
}

void GridRenderer::uploadParticles(const Grid &grid, const std::vector<Particle> &particles)
{
    std::vector<DebugVertex> vertices;
    vertices.reserve(particles.size());

    for (const auto &p : particles) {
        const Vector3f c = toRenderSpacePosition(grid, p.position);
        vertices.push_back({c.x(), c.y(), c.z(), 0.0f, 0.0f, 0.0f});
    }

    m_numParticles = static_cast<GLsizei>(vertices.size());

    glBindBuffer(GL_ARRAY_BUFFER, m_particlesVbo);
    glBufferData(
        GL_ARRAY_BUFFER,
        static_cast<GLsizeiptr>(vertices.size() * sizeof(DebugVertex)),
        vertices.data(),
        GL_DYNAMIC_DRAW
    );
    glBindBuffer(GL_ARRAY_BUFFER, 0);
}

void GridRenderer::drawCellCenters(Shader *shader)
{
    if (m_numPointVertices == 0) {
        return;
    }

    Eigen::Matrix4f I4 = Eigen::Matrix4f::Identity();
    Eigen::Matrix3f I3 = Eigen::Matrix3f::Identity();
    shader->setUniform("cube", 0);
    shader->setUniform("model", I4);
    shader->setUniform("inverseTransposeModel", I3);
    shader->setUniform("red", 0.2f);
    shader->setUniform("green", 0.8f);
    shader->setUniform("blue", 1.0f);
    shader->setUniform("alpha", 1.0f);
    shader->setUniform("maxVelocity", max_veloc);
    shader->setUniform("renderMode", 0);

    glPointSize(2.0f);
    glBindVertexArray(m_pointsVao);
    glDrawArrays(GL_POINTS, 0, m_numPointVertices);
    glBindVertexArray(0);
}

void GridRenderer::drawVelocityArrows(Shader *shader)
{
    if (m_numArrowVertices == 0) {
        return;
    }

    Eigen::Matrix4f I4 = Eigen::Matrix4f::Identity();
    Eigen::Matrix3f I3 = Eigen::Matrix3f::Identity();
    shader->setUniform("cube", 0);
    shader->setUniform("model", I4);
    shader->setUniform("inverseTransposeModel", I3);
    shader->setUniform("red", 1.0f);
    shader->setUniform("green", 0.0f);
    shader->setUniform("blue", 0.0f);
    shader->setUniform("alpha", 1.0f);
    shader->setUniform("renderMode", 0);

    glBindVertexArray(m_arrowsVao);
    glDrawArrays(GL_LINES, 0, m_numArrowVertices);
    glBindVertexArray(0);
}

void GridRenderer::drawParticlePoints(Shader *shader)
{
    if (m_numParticles == 0) {
        return;
    }

    Eigen::Matrix4f I4 = Eigen::Matrix4f::Identity();
    Eigen::Matrix3f I3 = Eigen::Matrix3f::Identity();
    shader->setUniform("cube", 0);
    shader->setUniform("model", I4);
    shader->setUniform("inverseTransposeModel", I3);
    shader->setUniform("red", 0.95f);
    shader->setUniform("green", 0.95f);
    shader->setUniform("blue", 0.95f);
    shader->setUniform("alpha", 1.0f);
    shader->setUniform("renderMode", 2);

    glPointSize(3.0f);
    glBindVertexArray(m_particlesVao);
    glDrawArrays(GL_POINTS, 0, m_numParticles);
    glBindVertexArray(0);
}

void GridRenderer::drawScalarSpheres(Shader *shader)
{
    if (m_numSphereInstances == 0 || m_numSphereIndices == 0) {
        return;
    }

    Eigen::Matrix4f I4 = Eigen::Matrix4f::Identity();
    Eigen::Matrix3f I3 = Eigen::Matrix3f::Identity();
    shader->setUniform("cube", 0);
    shader->setUniform("model", I4);
    shader->setUniform("inverseTransposeModel", I3);
    shader->setUniform("red", 1.0f);
    shader->setUniform("green", 1.0f);
    shader->setUniform("blue", 1.0f);
    shader->setUniform("alpha", 1.0f);
    shader->setUniform("renderMode", 1);
    shader->setUniform("sphereScale", m_sphereScale);

    glBindVertexArray(m_sphereVao);
    glDrawElementsInstanced(GL_TRIANGLES, m_numSphereIndices, GL_UNSIGNED_INT, reinterpret_cast<void *>(0), m_numSphereInstances);
    glBindVertexArray(0);
}

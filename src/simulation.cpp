#include "simulation.h"
#include <Eigen/Sparse>
#include <Eigen/SparseCholesky>
#include <fstream>
#include <algorithm>
#include <cmath>
#include <iostream>
#include <random>

using namespace Eigen;

namespace
{
std::mt19937 &particleRng()
{
    static std::mt19937 rng(1337);
    return rng;
}

float random01()
{
    static std::uniform_real_distribution<float> dist(0.0f, 1.0f);
    return dist(particleRng());
}
}

Simulation::Simulation(Grid &grid) 
    : m_grid(grid)
{

}

void Simulation::init()
{

    const Vector3f domainCenter(
        0.5f * static_cast<float>(m_grid.nx) * m_grid.cellSize,
        0.5f * static_cast<float>(m_grid.ny) * m_grid.cellSize,
        0.5f * static_cast<float>(m_grid.nz) * m_grid.cellSize
    );

    const float maxDist = 0.5f * std::sqrt(
        static_cast<float>(m_grid.nx * m_grid.nx + m_grid.ny * m_grid.ny + m_grid.nz * m_grid.nz)
    ) * m_grid.cellSize;
    const float spanX = static_cast<float>(m_grid.nx) * m_grid.cellSize;
    const float spanY = static_cast<float>(m_grid.ny) * m_grid.cellSize;
    const float spanZ = static_cast<float>(m_grid.nz) * m_grid.cellSize;
    const float maxSphereRadius = 0.5f * std::min(spanX, std::min(spanY, spanZ));
    if (m_particleSpawnSphereRadius <= 0.0f) {
        m_particleSpawnSphereRadius = 0.25f * maxSphereRadius;
    }
    const float sigma = 0.35f * maxDist;
    const float invTwoSigma2 = sigma > 0.0f ? (1.0f / (2.0f * sigma * sigma)) : 0.0f;

    for (int k = 0; k < m_grid.nz; ++k) {
        for (int j = 0; j < m_grid.ny; ++j) {
            for (int i = 0; i < m_grid.nx; ++i) {
                const Vector3f p = m_grid.cellCenter(i, j, k);
                const Vector3f d = p - domainCenter;
                m_grid.at(i, j, k).velocity = 0.2f * Vector3f(0.f, 1.f, 0.f);

                //Init velocity in a xz spiral
                //m_grid.at(i, j, k).velocity = 0.2f * Vector3f(-d.z(), 0.f, d.x());

                const float radial = d.squaredNorm();
                const float density = std::exp(-radial * invTwoSigma2);
                // m_grid.at(i, j, k).density = density;

                const float height = maxDist > 0.0f ? (d.y() / maxDist) : 0.0f;
                // m_grid.at(i, j, k).pressure = 0.5f + 0.5f * height;
            }
        }
    }

    m_initialCells = m_grid.cells;
    m_totalTime = 0.0f;

    initParticles();
    buildLMat();
}

void Simulation::boundParticles() {
    for (int k = 0; k < m_grid.nz; ++k) {
        for (int j = 0; j < m_grid.ny; ++j) {
            for (int i = 0; i < m_grid.nx; ++i) {
                Vector3f &v = m_grid.at(i, j, k).velocity;
                if (i == 0 || i == m_grid.nx - 1) v.x() = 0.f;
                if (j == 0 || j == m_grid.ny - 1) v.y() = 0.f;
                if (k == 0 || k == m_grid.nz - 1) v.z() = 0.f;
            }
        }
    }
}

void Simulation::impulse(Vector3f pos, Vector3f force) {
    m_impulsePosition = pos;
    impulseActive = true;
    m_impulseDirection = force.normalized();
    m_impulseRadius = m_grid.cellSize * 5;
}


void Simulation::update(double seconds) {
    m_totalTime += static_cast<float>(seconds);

    if (!m_diffusionBuilt) {
        buildDiffuse(seconds);
        m_diffusionBuilt = true;
    }

    Vector3f gravity(0.f, -9.80665f*5, 0.f); // *3 to make it go faster lmao
    float dt = static_cast<float>(seconds);

    for (int k = 0; k < m_grid.nz; ++k)
        for (int j = 0; j < m_grid.ny; ++j)
            for (int i = 0; i < m_grid.nx; ++i) {
                m_grid.at(i, j, k).velocity += dt * gravity;

                if (impulseActive) {
                    Vector3f cellPos = m_grid.cellCenter(i, j, k);
                    Vector3f diff = cellPos - m_impulsePosition;
                    float norm = diff.squaredNorm();
                    float r2 = m_impulseRadius*m_impulseRadius;
                    m_grid.at(i, j, k).velocity += dt * 600 * std::exp(-norm / r2) * static_cast<Vector3f>(m_impulseDirection);
                }
            }
    advectField(seconds);
    applyDiffuse(seconds);
    applyProject();
    boundParticles();

    if (m_isCounting) {
        m_count+=1;
        exportFrame(m_count);
    }

    impulseActive = false;

    // vortexSim(seconds);
    advectParticles(dt);
}

//A simulation PURELY for understanding the Visual Interface.
//It's useful to understand how to write values into the grid data structure.
//Not Physically Plausible, do not be inspired :)
void Simulation::vortexSim(double seconds){
    const Vector3f domainCenter(
        0.5f * m_grid.nx * m_grid.cellSize,
        0.5f * m_grid.ny * m_grid.cellSize,
        0.5f * m_grid.nz * m_grid.cellSize
        );

    const float maxDist = 0.5f * std::sqrt(
        static_cast<float>(m_grid.nx * m_grid.nx + m_grid.ny * m_grid.ny + m_grid.nz * m_grid.nz)
    ) * m_grid.cellSize;

    const float rotationSpeed = 2.0f; // radians per second
    const float vortexStrength = 1.0f;

    for (int k = 0; k < m_grid.nz; ++k) {
        for (int j = 0; j < m_grid.ny; ++j) {
            for (int i = 0; i < m_grid.nx; ++i) {
                Vector3f d = m_grid.cellCenter(i, j, k) - domainCenter;

                float theta = rotationSpeed * m_totalTime;

                float cosTheta = cos(theta);
                float sinTheta = sin(theta);

                Vector3f tangent(-sinTheta * d.x() - cosTheta * d.z(),
                                 0.0f,
                                 cosTheta * d.x() - sinTheta * d.z());

                if (tangent.norm() > 1e-6f)
                    tangent.normalize();

                m_grid.at(i, j, k).velocity = vortexStrength * tangent;

                const float radial = maxDist > 0.0f ? (d.norm() / maxDist) : 0.0f;
                const float wave = std::sin(m_totalTime * 1.7f + radial * 6.0f);
                const float density = 0.35f + 0.65f * (0.5f + 0.5f * wave);
                m_grid.at(i, j, k).density = std::clamp(density, 0.0f, 1.0f);

                const float height = maxDist > 0.0f ? (d.y() / maxDist) : 0.0f;
                const float pressureWave = std::cos(m_totalTime * 1.1f + d.x() * 2.5f);
                const float pressure = 0.5f + 0.35f * height + 0.25f * pressureWave;
                m_grid.at(i, j, k).pressure = std::clamp(pressure, 0.0f, 1.0f);
            }
        }
    }

}


void Simulation::initParticles()
{
    m_particles.resize(std::max(1, m_particleCount));
    m_spawnCursor = 0;
    for (auto &particle : m_particles) {
        respawnParticle(particle);
    }
}

void Simulation::applyDiffuse(double dt) {
    int nx = m_grid.nx;
    int ny = m_grid.ny;
    int nz = m_grid.nz;
    int nIters = nx * ny * nz;

    Eigen::VectorXd xVals(nIters), yVals(nIters), zVals(nIters);
    for (int k = 0; k < nz; ++k) {
        for (int j = 0; j < ny; ++j) {
            for (int i = 0; i < nx; ++i) {
                int id = (k*ny+j)*nx+i;
                Vector3f v = m_grid.at(i, j, k).velocity;
                xVals[id] = static_cast<double>(v.x());
                yVals[id] = static_cast<double>(v.y());
                zVals[id] = static_cast<double>(v.z());
            }
        }
    }
    Eigen::VectorXd newX = m_diffuse.solve(xVals);
    Eigen::VectorXd newY = m_diffuse.solve(yVals);
    Eigen::VectorXd newZ = m_diffuse.solve(zVals);
    for (int k = 0; k < nz; ++k) {
        for (int j = 0; j < ny; ++j) {
            for (int i = 0; i < nx; ++i) {
                int id = (k*ny+j)*nx+i;
                m_grid.at(i, j, k).velocity = Vector3f(static_cast<float>(newX[id]),static_cast<float>(newY[id]), static_cast<float>(newZ[id]));
            }
        }
    }
}

void Simulation::buildDiffuse(double dt) {
    int nx = m_grid.nx, ny = m_grid.ny, nz = m_grid.nz;
    int nIters = nx * ny * nz;
    double dx = static_cast<double>(m_grid.cellSize);
    double alpha = dt * m_viscosity / (dx * dx);

    std::vector<Triplet<double>> triplets;
    triplets.reserve(nIters*7);
    for (int k = 0; k < nz; ++k)
        for (int j = 0; j < ny; ++j)
            for (int i = 0; i < nx; ++i) {
                int id = i+nx*(j+ny*k);
                int neighbors = 0;
                auto addNeighbor = [&](int x, int y, int z) {
                    triplets.emplace_back(id, x + nx * (y + ny * z), -alpha);
                    neighbors++;
                };

                if (i > 0) addNeighbor(i-1, j, k);
                if (i < nx - 1) addNeighbor(i+1, j, k);
                if (j > 0) addNeighbor(i, j-1, k);
                if (j < ny - 1) addNeighbor(i, j+1, k);
                if (k > 0) addNeighbor(i, j, k-1);
                if (k < nz - 1) addNeighbor(i, j, k+1);
                triplets.emplace_back(id, id, 1.0 + neighbors * alpha);
            }

    m_diffusionMat.resize(nIters, nIters);
    m_diffusionMat.setFromTriplets(triplets.begin(), triplets.end());
    m_diffuse.compute(m_diffusionMat);
}

void Simulation::buildLMat() {
    int nx = m_grid.nx;
    int ny = m_grid.ny;
    int nz = m_grid.nz;
    int n = nx * ny * nz;
    double dx = static_cast<double>(m_grid.cellSize);
    double invDx2 = 1.0 / (dx * dx);

    std::vector<Eigen::Triplet<double>> triplets;
    triplets.reserve(n*7);
    for (int k = 0; k < nz; ++k)
        for (int j = 0; j < ny; ++j)
            for (int i = 0; i < nx; ++i) {
                int id = i + nx * (j + ny * k);
                int neighbors = 0;
                auto addNeighbor = [&](int ni, int nj, int nk) {
                    triplets.emplace_back(id, ni+nx *(nj+ ny* nk), -invDx2);
                    neighbors++;
                };

                if (i > 0) addNeighbor(i-1, j, k);
                if (i < nx - 1) addNeighbor(i+1, j, k);
                if (j > 0) addNeighbor(i, j-1, k);
                if (j < ny - 1) addNeighbor(i, j+1, k);
                if (k > 0) addNeighbor(i, j, k-1);
                if (k < nz - 1) addNeighbor(i, j, k+1);
                triplets.emplace_back(id, id, static_cast<double>(neighbors) * invDx2 + 1e-6);
            }

    m_laplacian.resize(n,n);
    m_laplacian.setFromTriplets(triplets.begin(), triplets.end());
    m_poissonSolver.compute(m_laplacian);
}

void Simulation::applyProject() {
    int nx = m_grid.nx;
    int ny = m_grid.ny;
    int nz = m_grid.nz;
    int nIters = nx*ny*nz;
    double dx = static_cast<double>(m_grid.cellSize);

    Eigen::VectorXd div(nIters);
    for (int k = 0; k < nz; ++k) {
        for (int j = 0; j < ny; ++j) {
            for (int i = 0; i < nx; ++i) {
                int index = i + nx * (j + ny * k);
                double ux_right = (i < nx-1) ? m_grid.at(i+1, j, k).velocity.x() : 0.0;
                double ux_left  = (i > 0)? m_grid.at(i-1, j, k).velocity.x() : 0.0;
                double uy_up = (j < ny-1) ? m_grid.at(i, j+1, k).velocity.y() : 0.0;
                double uy_down = (j > 0) ? m_grid.at(i, j-1, k).velocity.y() : 0.0;
                double uz_front = (k < nz-1) ? m_grid.at(i, j, k+1).velocity.z() : 0.0;
                double uz_back = (k > 0)? m_grid.at(i, j, k-1).velocity.z() : 0.0;

                double dudx = (ux_right - ux_left) / (2.0 * dx);
                double dvdy = (uy_up    - uy_down) / (2.0 * dx);
                double dwdz = (uz_front - uz_back) / (2.0 * dx);

                div[index] = dudx + dvdy + dwdz;
            }
        }
    }

    Eigen::VectorXd q = m_poissonSolver.solve(-div);
    for (int k = 0; k < nz; ++k) {
        for (int j = 0; j < ny; ++j) {
            for (int i = 0; i < nx; ++i) {
                int index = i + nx * (j + ny * k);

                double q_right = (i < nx-1) ? q[i+1 + nx*(j + ny*k)] : q[index];
                double q_left = (i > 0)? q[i-1 + nx*(j + ny*k)] : q[index];
                double q_up = (j < ny-1) ? q[i + nx*(j+1 + ny*k)] : q[index];
                double q_down = (j > 0) ? q[i + nx*(j-1 + ny*k)] : q[index];
                double q_front = (k < nz-1) ? q[i + nx*(j + ny*(k+1))] : q[index];
                double q_back = (k > 0)? q[i + nx*(j + ny*(k-1))] : q[index];

                double dqdx = (q_right - q_left) / (2.0 * dx);
                double dqdy = (q_up    - q_down) / (2.0 * dx);
                double dqdz = (q_front - q_back) / (2.0 * dx);

                m_grid.at(i,j,k).velocity.x() -= static_cast<float>(dqdx);
                m_grid.at(i,j,k).velocity.y() -= static_cast<float>(dqdy);
                m_grid.at(i,j,k).velocity.z() -= static_cast<float>(dqdz);

                m_grid.at(i,j,k).pressure = static_cast<float>(q[index]);
                m_grid.at(i,j,k).density = static_cast<float>(std::abs(div[index]));
            }
        }
    }
}

void Simulation::advectField(double seconds) {
    auto newCells = m_grid.cells;
    double maxX = m_grid.nx * m_grid.cellSize - 1e-4;
    double maxY = m_grid.ny * m_grid.cellSize - 1e-4;
    double maxZ = m_grid.nz * m_grid.cellSize - 1e-4;

    for (int k = 0; k < m_grid.nz; ++k) {
        for (int j = 0; j < m_grid.ny; ++j) {
            for (int i = 0; i < m_grid.nx; ++i) {
                Vector3d pos = m_grid.cellCenter(i, j, k).cast<double>();
                Vector3d v1 = m_grid.sampleVelocity(pos.cast<float>()).cast<double>();
                Vector3d mid = pos - 0.5 * seconds * v1;
                mid = Vector3d(std::clamp(mid.x(), 0.0, maxX), std::clamp(mid.y(), 0.0, maxY), std::clamp(mid.z(), 0.0, maxZ));
                Vector3d v2 = m_grid.sampleVelocity(mid.cast<float>()).cast<double>();
                Vector3d backPos = pos - seconds * v2;
                backPos = Vector3d(std::clamp(backPos.x(), 0.0, maxX), std::clamp(backPos.y(), 0.0, maxY), std::clamp(backPos.z(), 0.0, maxZ));
                Vector3f newPos = backPos.cast<float>();
                newCells[(j + m_grid.ny * k)*m_grid.nx +i].velocity = m_grid.sampleVelocity(newPos);
            }
        }
    }

    m_grid.cells = newCells;
}


void Simulation::advectParticles(float seconds)
{
    if (m_particles.empty()) {
        return;
    }

    const Vector3f domainMin(0.0f, 0.0f, 0.0f);
    const Vector3f domainMax(
        static_cast<float>(m_grid.nx) * m_grid.cellSize,
        static_cast<float>(m_grid.ny) * m_grid.cellSize,
        static_cast<float>(m_grid.nz) * m_grid.cellSize
    );

    static constexpr float kMaxAge = 6.0f;
    static constexpr float kSpeedScale = 0.6f;

    for (auto &particle : m_particles) {
        const Vector3f vel = m_grid.sampleVelocity(particle.position);
        particle.position += vel * (seconds * kSpeedScale);
        particle.age += seconds;

        if (particle.age > kMaxAge
            || particle.position.x() < domainMin.x() || particle.position.y() < domainMin.y() || particle.position.z() < domainMin.z()
            || particle.position.x() > domainMax.x() || particle.position.y() > domainMax.y() || particle.position.z() > domainMax.z()) {
            respawnParticle(particle);
        }
    }
}

void Simulation::respawnParticle(Particle &particle)
{
    const Vector3f domainCenter(
        0.5f * static_cast<float>(m_grid.nx) * m_grid.cellSize,
        0.5f * static_cast<float>(m_grid.ny) * m_grid.cellSize,
        0.5f * static_cast<float>(m_grid.nz) * m_grid.cellSize
    );

    const float spanX = static_cast<float>(m_grid.nx) * m_grid.cellSize;
    const float spanY = static_cast<float>(m_grid.ny) * m_grid.cellSize;
    const float spanZ = static_cast<float>(m_grid.nz) * m_grid.cellSize;
    const float maxSphereRadius = 0.5f * std::min(spanX, std::min(spanY, spanZ));
    const float sphereRadius = std::clamp(m_particleSpawnSphereRadius, 0.0f, maxSphereRadius);

    Vector3f position = domainCenter;
    switch (m_particleSpawnMode) {
    case ParticleSpawnMode::CELL_CENTERS: {
        const int cellCount = std::max(1, m_grid.nx * m_grid.ny * m_grid.nz);
        const int idx = m_spawnCursor++ % cellCount;
        const int i = idx % m_grid.nx;
        const int j = (idx / m_grid.nx) % m_grid.ny;
        const int k = idx / (m_grid.nx * m_grid.ny);
        position = m_grid.cellCenter(i, j, k);
        break;
    }
    case ParticleSpawnMode::RANDOM_IN_CELL: {
        const int i = static_cast<int>(random01() * m_grid.nx);
        const int j = static_cast<int>(random01() * m_grid.ny);
        const int k = static_cast<int>(random01() * m_grid.nz);
        const Vector3f center = m_grid.cellCenter(i, j, k);
        const float half = 0.5f * m_grid.cellSize;
        const Vector3f jitter(
            (random01() * 2.0f - 1.0f) * half,
            (random01() * 2.0f - 1.0f) * half,
            (random01() * 2.0f - 1.0f) * half
        );
        position = center + jitter;
        break;
    }
    case ParticleSpawnMode::VORTEX_RING:
    default: {
        const float radius = 0.25f * std::min(spanX, spanZ);
        const float u = random01();
        const float v = random01();
        const float w = random01();
        const float angle = v * 6.28318530718f;
        const float r = radius * std::sqrt(u);
        const float x = domainCenter.x() + r * std::cos(angle);
        const float z = domainCenter.z() + r * std::sin(angle);
        const float y = 0.25f * spanY + w * 0.5f * spanY;
        position = Vector3f(x, y, z);
        break;
    }
    case ParticleSpawnMode::SPHERE_VOLUME: {
        const float u = random01();
        const float v = random01();
        const float w = random01();
        const float theta = 2.0f * 3.14159265359f * u;
        const float phi = std::acos(2.0f * v - 1.0f);
        const float r = sphereRadius * std::cbrt(w);
        const float sinPhi = std::sin(phi);
        const float x = r * sinPhi * std::cos(theta);
        const float y = r * std::cos(phi);
        const float z = r * sinPhi * std::sin(theta);
        position = domainCenter + Vector3f(x, y, z);
        break;
    }
    }

    particle.position = position;
    particle.age = 0.0f;
}

void Simulation::setParticleCount(int count)
{
    m_particleCount = std::max(1, count);
    resetParticles();
}

void Simulation::setParticleSpawnMode(ParticleSpawnMode mode)
{
    m_particleSpawnMode = mode;
    resetParticles();
}

void Simulation::setParticleSpawnSphereRadius(float radius)
{
    const float spanX = static_cast<float>(m_grid.nx) * m_grid.cellSize;
    const float spanY = static_cast<float>(m_grid.ny) * m_grid.cellSize;
    const float spanZ = static_cast<float>(m_grid.nz) * m_grid.cellSize;
    const float maxSphereRadius = 0.5f * std::min(spanX, std::min(spanY, spanZ));
    m_particleSpawnSphereRadius = std::clamp(radius, 0.0f, maxSphereRadius);
    if (m_particleSpawnMode == ParticleSpawnMode::SPHERE_VOLUME) {
        resetParticles();
    }
}

void Simulation::resetParticles()
{
    m_isCounting =false;
    m_particles.clear();
    initParticles();
}

void Simulation::resetGridToInitial()
{
    if (m_initialCells.empty()) {
        return;
    }

    if (m_initialCells.size() != m_grid.cells.size()) {
        m_grid.cells = m_initialCells;
    } else {
        std::copy(m_initialCells.begin(), m_initialCells.end(), m_grid.cells.begin());
    }

    m_totalTime = 0.0f;
}


void Simulation::exportFrame(int frameNum) {
    std::string filename = "frame_" + std::to_string(frameNum) + ".ply";
    std::ofstream file(filename);

    int count = m_particles.size();
    file << "ply\n";
    file << "format ascii 1.0\n";
    file << "element vertex " << count << "\n";
    file << "property float x\n";
    file << "property float y\n";
    file << "property float z\n";
    file << "end_header\n";

    for (auto &p : m_particles) {
        file << p.position.x() << " "
             << p.position.y() << " "
             << p.position.z() << "\n";
    }
}

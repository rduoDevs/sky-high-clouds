#pragma once

#include "graphics/shape.h"
#include "grid.h"
#include "src/IterativeLinearSolvers/ConjugateGradient.h"
#include <vector>

class Shader;

struct Particle
{
    Eigen::Vector3f position = Eigen::Vector3f::Zero();
    float age = 0.0f;
};

enum class ParticleSpawnMode
{
    VORTEX_RING = 0,
    CELL_CENTERS = 1,
    RANDOM_IN_CELL = 2,
    SPHERE_VOLUME = 3
};

class Simulation
{
public:
    Simulation(Grid &grid);

    void init();

    void update(double seconds);

    const std::vector<Particle> &particles() const { return m_particles; }
    int particleCount() const { return m_particleCount; }
    ParticleSpawnMode particleSpawnMode() const { return m_particleSpawnMode; }
    float particleSpawnSphereRadius() const { return m_particleSpawnSphereRadius; }
    void setParticleCount(int count);
    void setParticleSpawnMode(ParticleSpawnMode mode);
    void setParticleSpawnSphereRadius(float radius);
    void advectField(double seconds);
    void impulse(Eigen::Vector3f pos, Eigen::Vector3f force);
    void resetParticles();
    void boundParticles();
    void resetGridToInitial();
    void exportFrame(int frameNum);
    bool impulseActive = false;
    int m_count = 0;
    bool m_isCounting = false;
private:
    Shape m_shape;
    Grid &m_grid;

    Shape m_ground;
    void vortexSim(double seconds);

    void initParticles();
    void advectParticles(float seconds);
    void respawnParticle(Particle &particle);

    std::vector<Particle> m_particles;
    int m_particleCount = 2000;
    ParticleSpawnMode m_particleSpawnMode = ParticleSpawnMode::VORTEX_RING;
    int m_spawnCursor = 0;
    float m_particleSpawnSphereRadius = 0.0f;
    std::vector<GridCell> m_initialCells;
    float m_totalTime = 0.0f;

    //impulse factors
    // = true;
    Eigen::Vector3f m_impulsePosition;
    Eigen::Vector3f m_impulseDirection;
    double m_impulseRadius = 1.f;

    // diffuse properties
    double m_viscosity = 0.001;
    Eigen::SparseMatrix<double> m_diffusionMat;
    Eigen::SimplicialLDLT<Eigen::SparseMatrix<double>> m_diffuse;
    bool m_diffusionBuilt = false;
    void buildDiffuse(double dt);
    void applyDiffuse(double dt);

    // Projection
    Eigen::SparseMatrix<double> m_laplacian;
    Eigen::ConjugateGradient<Eigen::SparseMatrix<double>, Eigen::Lower | Eigen::Upper> m_poissonSolver;
    void buildLMat();
    void applyProject();
};

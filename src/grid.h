#pragma once

#include <Eigen/Core>

#include <vector>

struct GridCell
{
    Eigen::Vector3f velocity = Eigen::Vector3f::Zero();
    float density = 0.0f;
    float pressure = 0.0f;
};

class Grid
{
public:
    int nx;
    int ny;
    int nz;
    float cellSize;

    std::vector<GridCell> cells;

    Grid(int nx, int ny, int nz, float cellSize);

    GridCell &at(int i, int j, int k);
    const GridCell &at(int i, int j, int k) const;

    Eigen::Vector3f cellCenter(int i, int j, int k) const;
    Eigen::Vector3f sampleVelocity(const Eigen::Vector3f &position) const;

private:
    int index(int i, int j, int k) const;
};

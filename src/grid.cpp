#include "grid.h"

#include <algorithm>
#include <cassert>
#include <cmath>

Grid::Grid(int nx, int ny, int nz, float cellSize)
    : nx(nx), ny(ny), nz(nz), cellSize(cellSize), cells(static_cast<size_t>(nx) * ny * nz)
{
    
}

GridCell &Grid::at(int i, int j, int k)
{
    return cells[static_cast<size_t>(index(i, j, k))];
}

const GridCell &Grid::at(int i, int j, int k) const
{
    return cells[static_cast<size_t>(index(i, j, k))];
}

Eigen::Vector3f Grid::cellCenter(int i, int j, int k) const
{
    return Eigen::Vector3f(
        (static_cast<float>(i) + 0.5f) * cellSize,
        (static_cast<float>(j) + 0.5f) * cellSize,
        (static_cast<float>(k) + 0.5f) * cellSize
    );
}

Eigen::Vector3f Grid::sampleVelocity(const Eigen::Vector3f &position) const
{
    if (nx <= 0 || ny <= 0 || nz <= 0 || cellSize <= 0.0f) {
        return Eigen::Vector3f::Zero();
    }

    float gx = position.x() / cellSize - 0.5f;
    float gy = position.y() / cellSize - 0.5f;
    float gz = position.z() / cellSize - 0.5f;

    int i0 = static_cast<int>(std::floor(gx));
    int j0 = static_cast<int>(std::floor(gy));
    int k0 = static_cast<int>(std::floor(gz));

    float tx = gx - static_cast<float>(i0);
    float ty = gy - static_cast<float>(j0);
    float tz = gz - static_cast<float>(k0);

    if (i0 < 0) { i0 = 0; tx = 0.0f; }
    if (j0 < 0) { j0 = 0; ty = 0.0f; }
    if (k0 < 0) { k0 = 0; tz = 0.0f; }

    int i1 = std::min(i0 + 1, nx - 1);
    int j1 = std::min(j0 + 1, ny - 1);
    int k1 = std::min(k0 + 1, nz - 1);

    if (i0 >= nx - 1) { i0 = nx - 1; i1 = i0; tx = 0.0f; }
    if (j0 >= ny - 1) { j0 = ny - 1; j1 = j0; ty = 0.0f; }
    if (k0 >= nz - 1) { k0 = nz - 1; k1 = k0; tz = 0.0f; }

    const Eigen::Vector3f v000 = at(i0, j0, k0).velocity;
    const Eigen::Vector3f v100 = at(i1, j0, k0).velocity;
    const Eigen::Vector3f v010 = at(i0, j1, k0).velocity;
    const Eigen::Vector3f v110 = at(i1, j1, k0).velocity;
    const Eigen::Vector3f v001 = at(i0, j0, k1).velocity;
    const Eigen::Vector3f v101 = at(i1, j0, k1).velocity;
    const Eigen::Vector3f v011 = at(i0, j1, k1).velocity;
    const Eigen::Vector3f v111 = at(i1, j1, k1).velocity;

    const Eigen::Vector3f v00 = v000 * (1.0f - tx) + v100 * tx;
    const Eigen::Vector3f v10 = v010 * (1.0f - tx) + v110 * tx;
    const Eigen::Vector3f v01 = v001 * (1.0f - tx) + v101 * tx;
    const Eigen::Vector3f v11 = v011 * (1.0f - tx) + v111 * tx;

    const Eigen::Vector3f v0 = v00 * (1.0f - ty) + v10 * ty;
    const Eigen::Vector3f v1 = v01 * (1.0f - ty) + v11 * ty;

    return v0 * (1.0f - tz) + v1 * tz;
}

int Grid::index(int i, int j, int k) const
{

    return i + nx * (j + ny * k);
}

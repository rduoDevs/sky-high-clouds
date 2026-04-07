#ifndef SHAPE_H
#define SHAPE_H

#include <GL/glew.h>
#include <vector>

#include <Eigen>

class Shader;

class Shape
{
public:
    Shape();

    void init(const std::vector<Eigen::Vector3d> &vertices, const std::vector<Eigen::Vector3d> &normals, const std::vector<Eigen::Vector3i> &triangles);
    void init(const std::vector<Eigen::Vector3d> &vertices, const std::vector<Eigen::Vector3i> &triangles);
    void init(const std::vector<Eigen::Vector3d> &vertices, const std::vector<Eigen::Vector3i> &triangles, const std::vector<Eigen::Vector4i> &tetIndices);
    void initEdges(const std::vector<Eigen::Vector3d>& vertices, const std::vector<Eigen::Vector2i>& edges);

    void setVertices(const std::vector<Eigen::Vector3d> &vertices, const std::vector<Eigen::Vector3d> &normals);
    void setVertices(const std::vector<Eigen::Vector3d> &vertices);

    void setModelMatrix(const Eigen::Affine3f &model);

    void toggleWireframe();

    void draw(Shader *shader);

private:
    GLuint m_surfaceVao;
    GLuint m_tetVao;
    GLuint m_surfaceVbo;
    GLuint m_tetVbo;
    GLuint m_surfaceIbo;
    GLuint m_tetIbo;

    unsigned int m_numSurfaceVertices;
    unsigned int m_numTetVertices;
    unsigned int m_verticesSize;
    float m_red = 1.f;
    float m_blue = 0.f;
    float m_green = 0.f;
    float m_alpha = 1.f;

    std::vector<Eigen::Vector3i> m_faces;

    Eigen::Matrix4f m_modelMatrix;

    bool m_wireframe;

    // bool m_
};

#endif // SHAPE_H

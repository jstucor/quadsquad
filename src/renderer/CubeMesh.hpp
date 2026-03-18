#pragma once

#include <glad/glad.h>

// Indexed unit cube centred at origin, ±0.5 on each axis.
// Vertex layout: location 0 = vec3 position.
class CubeMesh {
public:
    CubeMesh();
    ~CubeMesh();

    void draw() const;  // issues glDrawElements(GL_TRIANGLES, 36, ...)

    CubeMesh(const CubeMesh&) = delete;
    CubeMesh& operator=(const CubeMesh&) = delete;

private:
    GLuint m_vao = 0;
    GLuint m_vbo = 0;
    GLuint m_ebo = 0;
};

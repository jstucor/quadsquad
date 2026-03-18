#include "renderer/CubeMesh.hpp"

//  Vertex indices into k_verts (each row = one vertex = x,y,z):
//
//    3 ──── 2        7 ──── 6
//    │ back │        │ front│
//    0 ──── 1        4 ──── 5
//
//  Vertices labelled as: 0=(-x,-y,-z)  1=(+x,-y,-z)  2=(+x,+y,-z)  3=(-x,+y,-z)
//                        4=(-x,-y,+z)  5=(+x,-y,+z)  6=(+x,+y,+z)  7=(-x,+y,+z)

static const float k_verts[] = {
    -0.5f, -0.5f, -0.5f,   // 0
     0.5f, -0.5f, -0.5f,   // 1
     0.5f,  0.5f, -0.5f,   // 2
    -0.5f,  0.5f, -0.5f,   // 3
    -0.5f, -0.5f,  0.5f,   // 4
     0.5f, -0.5f,  0.5f,   // 5
     0.5f,  0.5f,  0.5f,   // 6
    -0.5f,  0.5f,  0.5f,   // 7
};

static const unsigned int k_indices[] = {
    0, 2, 1,  0, 3, 2,  // back   (z-)
    4, 5, 6,  4, 6, 7,  // front  (z+)
    0, 4, 7,  0, 7, 3,  // left   (x-)
    1, 2, 6,  1, 6, 5,  // right  (x+)
    0, 1, 5,  0, 5, 4,  // bottom (y-)
    3, 7, 6,  3, 6, 2,  // top    (y+)
};

CubeMesh::CubeMesh() {
    glGenVertexArrays(1, &m_vao);
    glGenBuffers(1, &m_vbo);
    glGenBuffers(1, &m_ebo);

    glBindVertexArray(m_vao);

    glBindBuffer(GL_ARRAY_BUFFER, m_vbo);
    glBufferData(GL_ARRAY_BUFFER, sizeof(k_verts), k_verts, GL_STATIC_DRAW);

    glBindBuffer(GL_ELEMENT_ARRAY_BUFFER, m_ebo);
    glBufferData(GL_ELEMENT_ARRAY_BUFFER, sizeof(k_indices), k_indices, GL_STATIC_DRAW);

    // layout(location = 0) in vec3 aPos
    glVertexAttribPointer(0, 3, GL_FLOAT, GL_FALSE, 3 * sizeof(float), nullptr);
    glEnableVertexAttribArray(0);

    glBindVertexArray(0);
}

CubeMesh::~CubeMesh() {
    glDeleteBuffers(1, &m_ebo);
    glDeleteBuffers(1, &m_vbo);
    glDeleteVertexArrays(1, &m_vao);
}

void CubeMesh::draw() const {
    glBindVertexArray(m_vao);
    glDrawElements(GL_TRIANGLES, 36, GL_UNSIGNED_INT, nullptr);
    glBindVertexArray(0);
}

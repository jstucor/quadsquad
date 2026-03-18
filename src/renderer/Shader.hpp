#pragma once

#include <glad/glad.h>
#include <glm/glm.hpp>

class Shader {
public:
    Shader(const char* vertSrc, const char* fragSrc);
    ~Shader();

    void use() const;
    void setMat4 (const char* name, const glm::mat4& m) const;
    void setVec3 (const char* name, const glm::vec3& v) const;
    void setFloat(const char* name, float v)            const;

    Shader(const Shader&) = delete;
    Shader& operator=(const Shader&) = delete;

private:
    GLuint m_program = 0;
};

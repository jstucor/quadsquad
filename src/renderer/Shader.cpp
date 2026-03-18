#include "renderer/Shader.hpp"

#include <glm/gtc/type_ptr.hpp>
#include <cstdio>
#include <cstdlib>

static GLuint compileStage(GLenum type, const char* src) {
    GLuint s = glCreateShader(type);
    glShaderSource(s, 1, &src, nullptr);
    glCompileShader(s);

    GLint ok = 0;
    glGetShaderiv(s, GL_COMPILE_STATUS, &ok);
    if (!ok) {
        char log[512];
        glGetShaderInfoLog(s, sizeof(log), nullptr, log);
        std::fprintf(stderr, "Shader compile error (%s):\n%s\n",
            type == GL_VERTEX_SHADER ? "vert" : "frag", log);
        std::abort();
    }
    return s;
}

Shader::Shader(const char* vertSrc, const char* fragSrc) {
    const GLuint vert = compileStage(GL_VERTEX_SHADER,   vertSrc);
    const GLuint frag = compileStage(GL_FRAGMENT_SHADER, fragSrc);

    m_program = glCreateProgram();
    glAttachShader(m_program, vert);
    glAttachShader(m_program, frag);
    glLinkProgram(m_program);

    GLint ok = 0;
    glGetProgramiv(m_program, GL_LINK_STATUS, &ok);
    if (!ok) {
        char log[512];
        glGetProgramInfoLog(m_program, sizeof(log), nullptr, log);
        std::fprintf(stderr, "Shader link error:\n%s\n", log);
        std::abort();
    }

    glDeleteShader(vert);
    glDeleteShader(frag);
}

Shader::~Shader() {
    if (m_program) glDeleteProgram(m_program);
}

void Shader::use() const { glUseProgram(m_program); }

void Shader::setMat4(const char* name, const glm::mat4& m) const {
    glUniformMatrix4fv(glGetUniformLocation(m_program, name),
                       1, GL_FALSE, glm::value_ptr(m));
}

void Shader::setVec3(const char* name, const glm::vec3& v) const {
    glUniform3f(glGetUniformLocation(m_program, name), v.x, v.y, v.z);
}

void Shader::setFloat(const char* name, float v) const {
    glUniform1f(glGetUniformLocation(m_program, name), v);
}

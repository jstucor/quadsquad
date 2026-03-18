#include "particle/ParticleSystem.hpp"

#include <glm/gtc/type_ptr.hpp>

#include <cmath>
#include <cstdio>
#include <random>

// ── Module RNG ────────────────────────────────────────────────────────────────

static std::mt19937 s_rng{1337u};

static float randF(float lo, float hi) {
    return std::uniform_real_distribution<float>{lo, hi}(s_rng);
}

// ── GLSL sources ──────────────────────────────────────────────────────────────

static const char* k_vertSrc = R"glsl(
#version 330 core
layout(location = 0) in vec2  aQuadPos;  // [-0.5, +0.5] unit quad vertex
layout(location = 1) in vec3  aInstPos;  // world-space particle centre
layout(location = 2) in float aInstSize; // size in world units
layout(location = 3) in vec4  aInstColor;// RGBA (alpha carries fade)

uniform mat4 uVP;
uniform vec3 uCamRight;
uniform vec3 uCamUp;

out vec4 vColor;

void main() {
    // Billboard: expand the quad in screen-aligned world space
    vec3 worldPos = aInstPos
                  + uCamRight * aQuadPos.x * aInstSize
                  + uCamUp    * aQuadPos.y * aInstSize;
    gl_Position = uVP * vec4(worldPos, 1.0);
    vColor = aInstColor;
}
)glsl";

static const char* k_fragSrc = R"glsl(
#version 330 core
in  vec4 vColor;
out vec4 FragColor;
void main() {
    FragColor = vColor;
}
)glsl";

// ── Shader helpers ────────────────────────────────────────────────────────────

static GLuint compileShader(GLenum type, const char* src) {
    GLuint s = glCreateShader(type);
    glShaderSource(s, 1, &src, nullptr);
    glCompileShader(s);
    GLint ok;
    glGetShaderiv(s, GL_COMPILE_STATUS, &ok);
    if (!ok) {
        char buf[512];
        glGetShaderInfoLog(s, sizeof(buf), nullptr, buf);
        std::fprintf(stderr, "ParticleSystem shader error: %s\n", buf);
    }
    return s;
}

static GLuint linkProgram(GLuint vert, GLuint frag) {
    GLuint p = glCreateProgram();
    glAttachShader(p, vert);
    glAttachShader(p, frag);
    glLinkProgram(p);
    glDeleteShader(vert);
    glDeleteShader(frag);
    return p;
}

// ── Constructor / Destructor ──────────────────────────────────────────────────

ParticleSystem::ParticleSystem() {
    m_prog = linkProgram(
        compileShader(GL_VERTEX_SHADER,   k_vertSrc),
        compileShader(GL_FRAGMENT_SHADER, k_fragSrc)
    );
    m_locVP       = glGetUniformLocation(m_prog, "uVP");
    m_locCamRight = glGetUniformLocation(m_prog, "uCamRight");
    m_locCamUp    = glGetUniformLocation(m_prog, "uCamUp");

    // Unit quad: two CCW triangles spanning [-0.5, +0.5]
    const float quad[] = {
        -0.5f, -0.5f,    0.5f, -0.5f,    0.5f,  0.5f,
        -0.5f, -0.5f,    0.5f,  0.5f,   -0.5f,  0.5f,
    };

    glGenVertexArrays(1, &m_vao);
    glBindVertexArray(m_vao);

    // Attrib 0 — per-vertex quad position (static)
    glGenBuffers(1, &m_quadVBO);
    glBindBuffer(GL_ARRAY_BUFFER, m_quadVBO);
    glBufferData(GL_ARRAY_BUFFER, sizeof(quad), quad, GL_STATIC_DRAW);
    glEnableVertexAttribArray(0);
    glVertexAttribPointer(0, 2, GL_FLOAT, GL_FALSE, 2 * sizeof(float), nullptr);
    glVertexAttribDivisor(0, 0);  // same quad repeated for every instance

    // Attribs 1-3 — per-instance stream  (pos + size + color  =  8 floats = 32 bytes)
    glGenBuffers(1, &m_instanceVBO);
    glBindBuffer(GL_ARRAY_BUFFER, m_instanceVBO);
    glBufferData(GL_ARRAY_BUFFER, MAX_PARTICLES * 8 * sizeof(float),
                 nullptr, GL_DYNAMIC_DRAW);

    // loc 1 : position (vec3), byte offset 0
    glEnableVertexAttribArray(1);
    glVertexAttribPointer(1, 3, GL_FLOAT, GL_FALSE,
                          8 * sizeof(float), reinterpret_cast<void*>(0));
    glVertexAttribDivisor(1, 1);

    // loc 2 : size (float), byte offset 12
    glEnableVertexAttribArray(2);
    glVertexAttribPointer(2, 1, GL_FLOAT, GL_FALSE,
                          8 * sizeof(float), reinterpret_cast<void*>(3 * sizeof(float)));
    glVertexAttribDivisor(2, 1);

    // loc 3 : color rgba (vec4), byte offset 16
    glEnableVertexAttribArray(3);
    glVertexAttribPointer(3, 4, GL_FLOAT, GL_FALSE,
                          8 * sizeof(float), reinterpret_cast<void*>(4 * sizeof(float)));
    glVertexAttribDivisor(3, 1);

    glBindVertexArray(0);
}

ParticleSystem::~ParticleSystem() {
    glDeleteProgram(m_prog);
    glDeleteBuffers(1, &m_instanceVBO);
    glDeleteBuffers(1, &m_quadVBO);
    glDeleteVertexArrays(1, &m_vao);
}

// ── Emit helper ───────────────────────────────────────────────────────────────

void ParticleSystem::emit(const glm::vec3& pos, const glm::vec3& vel,
                           const glm::vec3& color, float size, float lifetime)
{
    auto& p      = m_pool[static_cast<size_t>(m_nextSlot)];
    m_nextSlot   = (m_nextSlot + 1) % MAX_PARTICLES;
    p.position   = pos;
    p.velocity   = vel;
    p.color      = color;
    p.initSize   = size;
    p.age        = 0.f;
    p.lifetime   = lifetime;
    p.alive      = true;
}

// ── Spawn patterns ────────────────────────────────────────────────────────────

void ParticleSystem::spawnImpact(const glm::vec3& pos,
                                  const glm::vec3& inDir,
                                  const glm::vec3& color)
{
    // Particles scatter back from the surface: approximate normal = -inDir
    const glm::vec3 normal = -inDir;

    // Build two tangent vectors perpendicular to the normal
    const glm::vec3 tangA = glm::abs(normal.y) < 0.9f
        ? glm::normalize(glm::cross(normal, glm::vec3(0.f, 1.f, 0.f)))
        : glm::normalize(glm::cross(normal, glm::vec3(1.f, 0.f, 0.f)));
    const glm::vec3 tangB = glm::cross(normal, tangA);

    const int count = static_cast<int>(randF(10.f, 20.f));
    for (int i = 0; i < count; ++i) {
        const float theta = randF(0.f, 6.2832f);   // full revolution around normal
        const float phi   = randF(0.f, 1.1f);       // up to ~63° off-normal spread
        const float speed = randF(3.f, 9.f);

        const glm::vec3 dir = glm::normalize(
            normal * std::cos(phi)
          + tangA  * (std::sin(phi) * std::cos(theta))
          + tangB  * (std::sin(phi) * std::sin(theta))
        );

        // Mix each spark toward white for a "hot core" look
        const glm::vec3 c = glm::mix(color, glm::vec3(1.f), randF(0.f, 0.5f));

        emit(pos, dir * speed, c,
             randF(0.025f, 0.07f),   // small tight sparks
             randF(0.25f,  0.50f));  // short lifetime
    }
}

void ParticleSystem::spawnExplosion(const glm::vec3& pos)
{
    const int count = static_cast<int>(randF(20.f, 30.f));
    for (int i = 0; i < count; ++i) {
        // Uniform sphere distribution
        const float cosP  = randF(-1.f, 1.f);
        const float sinP  = std::sqrt(std::max(0.f, 1.f - cosP * cosP));
        const float theta = randF(0.f, 6.2832f);
        const glm::vec3 d{sinP * std::cos(theta), cosP, sinP * std::sin(theta)};

        const float speed = randF(2.f, 8.f);

        // Explosion palette: bright orange → dark red
        const glm::vec3 orange{1.0f, 0.55f, 0.05f};
        const glm::vec3 red   {0.9f, 0.15f, 0.02f};
        const glm::vec3 c = glm::mix(orange, red, randF(0.f, 1.f));

        emit(pos + d * randF(0.f, 0.3f),  // slight positional scatter
             d * speed, c,
             randF(0.06f, 0.14f),   // bigger than wall sparks
             randF(0.35f, 0.70f));  // slightly longer life
    }
}

// ── Update ────────────────────────────────────────────────────────────────────

void ParticleSystem::update(float dt)
{
    static constexpr float GRAVITY = -9.8f;

    for (auto& p : m_pool) {
        if (!p.alive) continue;

        p.age += dt;
        if (p.age >= p.lifetime) {
            p.alive = false;
            continue;
        }

        p.velocity.y += GRAVITY * dt;
        p.position   += p.velocity * dt;
    }
}

// ── Render ────────────────────────────────────────────────────────────────────

void ParticleSystem::render(const glm::mat4& vp,
                             const glm::vec3& camRight,
                             const glm::vec3& camUp)
{
    // Build packed instance data on the stack — no heap allocation
    float instanceData[MAX_PARTICLES * 8];
    int   liveCount = 0;

    for (const auto& p : m_pool) {
        if (!p.alive) continue;

        const float t     = p.age / p.lifetime;
        const float alpha = 1.f - t;
        const float size  = p.initSize * (1.f - t * 0.5f);  // shrinks to half at death

        float* d = &instanceData[liveCount * 8];
        d[0] = p.position.x;
        d[1] = p.position.y;
        d[2] = p.position.z;
        d[3] = size;
        d[4] = p.color.r;
        d[5] = p.color.g;
        d[6] = p.color.b;
        d[7] = alpha;
        ++liveCount;
    }

    if (liveCount == 0) return;

    // Upload live instances
    glBindBuffer(GL_ARRAY_BUFFER, m_instanceVBO);
    glBufferSubData(GL_ARRAY_BUFFER, 0,
                    liveCount * 8 * static_cast<int>(sizeof(float)),
                    instanceData);

    // Additive blending: particles glow like the bolts
    glEnable(GL_BLEND);
    glBlendFunc(GL_SRC_ALPHA, GL_ONE);
    glDepthMask(GL_FALSE);  // particles don't occlude each other or the scene

    glUseProgram(m_prog);
    glUniformMatrix4fv(m_locVP,       1, GL_FALSE, glm::value_ptr(vp));
    glUniform3fv(m_locCamRight, 1, glm::value_ptr(camRight));
    glUniform3fv(m_locCamUp,    1, glm::value_ptr(camUp));

    glBindVertexArray(m_vao);
    glDrawArraysInstanced(GL_TRIANGLES, 0, 6, liveCount);
    glBindVertexArray(0);

    // Restore state
    glDepthMask(GL_TRUE);
    glBlendFunc(GL_SRC_ALPHA, GL_ONE_MINUS_SRC_ALPHA);
    glDisable(GL_BLEND);
}

#include "renderer/PostProcess.hpp"

#include <cstdio>

// ── Shader sources ────────────────────────────────────────────────────────────

// Shared vertex shader — emits a full-screen triangle strip.
static const char* k_quadVert = R"glsl(
#version 330 core
layout(location = 0) in vec2 aPos;
out vec2 vUV;
void main() {
    vUV = aPos * 0.5 + 0.5;
    gl_Position = vec4(aPos, 0.0, 1.0);
}
)glsl";

// Pass 1 — extract pixels whose max channel exceeds the threshold.
// Using max-channel (rather than luminance) catches saturated reds like
// the bolt core (1.0, 0.12, 0.04) that score low on perceptual luminance.
static const char* k_brightFrag = R"glsl(
#version 330 core
in vec2 vUV;
uniform sampler2D uScene;
uniform float uThreshold;
out vec4 FragColor;
void main() {
    vec3  col    = texture(uScene, vUV).rgb;
    float bright = max(col.r, max(col.g, col.b));
    // Soft knee of 0.1 avoids a hard cutoff edge.
    float contrib = smoothstep(uThreshold - 0.1, uThreshold + 0.1, bright);
    FragColor = vec4(col * contrib, 1.0);
}
)glsl";

// Pass 2/3 — separable 9-tap Gaussian blur.
// uDir = (1/width, 0) for the horizontal pass, (0, 1/height) for vertical.
static const char* k_blurFrag = R"glsl(
#version 330 core
in vec2 vUV;
uniform sampler2D uTex;
uniform vec2 uDir;
out vec4 FragColor;
void main() {
    // Weights for a Gaussian with sigma ≈ 2 (normalised, symmetric 9-tap).
    const float w[5] = float[](0.227027, 0.194595, 0.121622, 0.054054, 0.016216);
    vec3 result = texture(uTex, vUV).rgb * w[0];
    for (int i = 1; i < 5; ++i) {
        result += texture(uTex, vUV + float(i) * uDir).rgb * w[i];
        result += texture(uTex, vUV - float(i) * uDir).rgb * w[i];
    }
    FragColor = vec4(result, 1.0);
}
)glsl";

// Pass 4 — additively composite the blurred bloom over the scene.
// The scene FBO is RGBA16F, so bolt pixels can exceed 1.0 from additive
// glow blending; the final min() clamps back to display range while letting
// the bloom bleed realistically into surrounding pixels.
static const char* k_compositeFrag = R"glsl(
#version 330 core
in vec2 vUV;
uniform sampler2D uScene;
uniform sampler2D uBloom;
uniform float uIntensity;
out vec4 FragColor;
void main() {
    vec3 scene = texture(uScene, vUV).rgb;
    vec3 bloom = texture(uBloom, vUV).rgb * uIntensity;
    FragColor  = vec4(min(scene + bloom, vec3(1.0)), 1.0);
}
)glsl";

// ── Helpers ───────────────────────────────────────────────────────────────────

GLuint PostProcess::buildProg(const char* vs, const char* fs) {
    auto compile = [](GLenum type, const char* src) -> GLuint {
        GLuint s = glCreateShader(type);
        glShaderSource(s, 1, &src, nullptr);
        glCompileShader(s);
        GLint ok;
        glGetShaderiv(s, GL_COMPILE_STATUS, &ok);
        if (!ok) {
            char log[512];
            glGetShaderInfoLog(s, sizeof(log), nullptr, log);
            std::fprintf(stderr, "PostProcess shader compile error:\n%s\n", log);
        }
        return s;
    };

    GLuint v = compile(GL_VERTEX_SHADER,   vs);
    GLuint f = compile(GL_FRAGMENT_SHADER, fs);
    GLuint p = glCreateProgram();
    glAttachShader(p, v);
    glAttachShader(p, f);
    glLinkProgram(p);
    GLint ok;
    glGetProgramiv(p, GL_LINK_STATUS, &ok);
    if (!ok) {
        char log[512];
        glGetProgramInfoLog(p, sizeof(log), nullptr, log);
        std::fprintf(stderr, "PostProcess program link error:\n%s\n", log);
    }
    glDeleteShader(v);
    glDeleteShader(f);
    return p;
}

// Create a colour-only FBO with one GL_RGB16F texture attachment.
static void makeFBO(int w, int h, GLuint& fbo, GLuint& tex) {
    glGenFramebuffers(1, &fbo);
    glBindFramebuffer(GL_FRAMEBUFFER, fbo);

    glGenTextures(1, &tex);
    glBindTexture(GL_TEXTURE_2D, tex);
    glTexImage2D(GL_TEXTURE_2D, 0, GL_RGB16F, w, h, 0, GL_RGB, GL_HALF_FLOAT, nullptr);
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, GL_LINEAR);
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, GL_LINEAR);
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_S, GL_CLAMP_TO_EDGE);
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_T, GL_CLAMP_TO_EDGE);
    glFramebufferTexture2D(GL_FRAMEBUFFER, GL_COLOR_ATTACHMENT0,
                           GL_TEXTURE_2D, tex, 0);

    if (glCheckFramebufferStatus(GL_FRAMEBUFFER) != GL_FRAMEBUFFER_COMPLETE)
        std::fprintf(stderr, "PostProcess: bloom FBO incomplete (%dx%d)!\n", w, h);

    glBindFramebuffer(GL_FRAMEBUFFER, 0);
}

// ── Constructor / destructor ──────────────────────────────────────────────────

PostProcess::PostProcess(int w, int h)
    : m_w(w), m_h(h), m_bw(w / 2), m_bh(h / 2)
{
    // ── Shader programs ───────────────────────────────────────────────────
    m_brightProg    = buildProg(k_quadVert, k_brightFrag);
    m_blurProg      = buildProg(k_quadVert, k_blurFrag);
    m_compositeProg = buildProg(k_quadVert, k_compositeFrag);

    m_uBrightScene     = glGetUniformLocation(m_brightProg,    "uScene");
    m_uBrightThreshold = glGetUniformLocation(m_brightProg,    "uThreshold");
    m_uBlurTex         = glGetUniformLocation(m_blurProg,      "uTex");
    m_uBlurDir         = glGetUniformLocation(m_blurProg,      "uDir");
    m_uCompScene       = glGetUniformLocation(m_compositeProg, "uScene");
    m_uCompBloom       = glGetUniformLocation(m_compositeProg, "uBloom");
    m_uCompIntensity   = glGetUniformLocation(m_compositeProg, "uIntensity");

    // ── Scene FBO — RGBA16F + depth renderbuffer ──────────────────────────
    // RGBA16F lets additive bolt-glow blending exceed 1.0 ("HDR headroom"),
    // which the composite pass then maps back to display range.
    glGenFramebuffers(1, &m_sceneFBO);
    glBindFramebuffer(GL_FRAMEBUFFER, m_sceneFBO);

    glGenTextures(1, &m_sceneTex);
    glBindTexture(GL_TEXTURE_2D, m_sceneTex);
    glTexImage2D(GL_TEXTURE_2D, 0, GL_RGBA16F, m_w, m_h, 0,
                 GL_RGBA, GL_HALF_FLOAT, nullptr);
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, GL_LINEAR);
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, GL_LINEAR);
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_S, GL_CLAMP_TO_EDGE);
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_T, GL_CLAMP_TO_EDGE);
    glFramebufferTexture2D(GL_FRAMEBUFFER, GL_COLOR_ATTACHMENT0,
                           GL_TEXTURE_2D, m_sceneTex, 0);

    glGenRenderbuffers(1, &m_sceneDepth);
    glBindRenderbuffer(GL_RENDERBUFFER, m_sceneDepth);
    glRenderbufferStorage(GL_RENDERBUFFER, GL_DEPTH_COMPONENT24, m_w, m_h);
    glFramebufferRenderbuffer(GL_FRAMEBUFFER, GL_DEPTH_ATTACHMENT,
                              GL_RENDERBUFFER, m_sceneDepth);

    if (glCheckFramebufferStatus(GL_FRAMEBUFFER) != GL_FRAMEBUFFER_COMPLETE)
        std::fprintf(stderr, "PostProcess: scene FBO incomplete!\n");

    glBindFramebuffer(GL_FRAMEBUFFER, 0);

    // ── Bloom FBOs (half-res, colour only) ───────────────────────────────
    makeFBO(m_bw, m_bh, m_brightFBO, m_brightTex);
    makeFBO(m_bw, m_bh, m_blurFBO[0], m_blurTex[0]);
    makeFBO(m_bw, m_bh, m_blurFBO[1], m_blurTex[1]);

    // ── Full-screen quad (NDC triangle strip) ─────────────────────────────
    constexpr float quad[] = { -1.f,-1.f,  1.f,-1.f,  -1.f,1.f,  1.f,1.f };
    glGenVertexArrays(1, &m_quadVAO);
    glGenBuffers(1, &m_quadVBO);
    glBindVertexArray(m_quadVAO);
    glBindBuffer(GL_ARRAY_BUFFER, m_quadVBO);
    glBufferData(GL_ARRAY_BUFFER, sizeof(quad), quad, GL_STATIC_DRAW);
    glEnableVertexAttribArray(0);
    glVertexAttribPointer(0, 2, GL_FLOAT, GL_FALSE, 2 * sizeof(float), nullptr);
    glBindVertexArray(0);
}

PostProcess::~PostProcess() {
    glDeleteFramebuffers(1,  &m_sceneFBO);
    glDeleteTextures(1,      &m_sceneTex);
    glDeleteRenderbuffers(1, &m_sceneDepth);

    glDeleteFramebuffers(1, &m_brightFBO);
    glDeleteTextures(1,     &m_brightTex);

    glDeleteFramebuffers(2,  m_blurFBO);
    glDeleteTextures(2,      m_blurTex);

    glDeleteVertexArrays(1, &m_quadVAO);
    glDeleteBuffers(1,      &m_quadVBO);

    glDeleteProgram(m_brightProg);
    glDeleteProgram(m_blurProg);
    glDeleteProgram(m_compositeProg);
}

// ── Public API ────────────────────────────────────────────────────────────────

void PostProcess::bindScene() {
    glBindFramebuffer(GL_FRAMEBUFFER, m_sceneFBO);
}

void PostProcess::drawQuad() const {
    glBindVertexArray(m_quadVAO);
    glDrawArrays(GL_TRIANGLE_STRIP, 0, 4);
}

void PostProcess::apply() {
    glDisable(GL_DEPTH_TEST);
    glDisable(GL_BLEND);

    // ── Pass 1: brightness extract → half-res brightFBO ──────────────────
    glViewport(0, 0, m_bw, m_bh);
    glBindFramebuffer(GL_FRAMEBUFFER, m_brightFBO);
    glUseProgram(m_brightProg);
    glActiveTexture(GL_TEXTURE0);
    glBindTexture(GL_TEXTURE_2D, m_sceneTex);
    glUniform1i(m_uBrightScene, 0);
    glUniform1f(m_uBrightThreshold, 0.9f);
    drawQuad();

    // ── Passes 2–5: ping-pong Gaussian blur (3 H+V iterations = 6 passes)
    // Three iterations widen the kernel enough for a cinematic soft glow
    // while staying well within budget on integrated GPU.
    glUseProgram(m_blurProg);
    glUniform1i(m_uBlurTex, 0);

    bool   horizontal = true;
    GLuint src        = m_brightTex;
    for (int i = 0; i < 6; ++i) {
        const int dst = horizontal ? 0 : 1;
        glBindFramebuffer(GL_FRAMEBUFFER, m_blurFBO[dst]);
        glBindTexture(GL_TEXTURE_2D, src);
        if (horizontal)
            glUniform2f(m_uBlurDir, 1.f / static_cast<float>(m_bw), 0.f);
        else
            glUniform2f(m_uBlurDir, 0.f, 1.f / static_cast<float>(m_bh));
        drawQuad();
        src        = m_blurTex[dst];
        horizontal = !horizontal;
    }
    // Pass sequence (H→0, V→1, H→0, V→1, H→0, V→1): final result in blurTex[1].

    // ── Pass 6: composite → default framebuffer ───────────────────────────
    glViewport(0, 0, m_w, m_h);
    glBindFramebuffer(GL_FRAMEBUFFER, 0);
    glUseProgram(m_compositeProg);
    glActiveTexture(GL_TEXTURE0);
    glBindTexture(GL_TEXTURE_2D, m_sceneTex);
    glUniform1i(m_uCompScene, 0);
    glActiveTexture(GL_TEXTURE1);
    glBindTexture(GL_TEXTURE_2D, m_blurTex[1]);
    glUniform1i(m_uCompBloom, 1);
    glUniform1f(m_uCompIntensity, 1.2f);
    drawQuad();

    // Restore state expected by the scene/ImGui passes next frame.
    glActiveTexture(GL_TEXTURE0);
    glEnable(GL_DEPTH_TEST);
}

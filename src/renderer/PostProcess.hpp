#pragma once

#include <glad/glad.h>

// Two-pass bloom post-processor.
//
// Usage (each frame, inside the GL-object scope):
//   postProcess.bindScene();          // redirect scene rendering to internal FBO
//   glClear(...);
//   // ... all viewport draws ...
//   postProcess.apply();              // bloom composite → default framebuffer
//   // ... ImGui HUD renders on top ...
class PostProcess {
public:
    PostProcess(int w, int h);
    ~PostProcess();

    PostProcess(const PostProcess&)            = delete;
    PostProcess& operator=(const PostProcess&) = delete;

    // Redirect subsequent GL rendering into the scene FBO.
    void bindScene();

    // Run brightness extract → Gaussian blur → composite onto the default
    // framebuffer.  Restores full viewport and default FB on return.
    void apply();

private:
    static GLuint buildProg(const char* vertSrc, const char* fragSrc);
    void drawQuad() const;

    int m_w, m_h;       // full resolution  (scene FBO)
    int m_bw, m_bh;     // half resolution  (bloom FBOs)

    // Scene FBO — RGBA16F colour + depth renderbuffer.
    GLuint m_sceneFBO   = 0;
    GLuint m_sceneTex   = 0;
    GLuint m_sceneDepth = 0;

    // Brightness-extract FBO (half-res, RGB16F).
    GLuint m_brightFBO = 0;
    GLuint m_brightTex = 0;

    // Ping-pong blur FBOs (half-res, RGB16F).
    GLuint m_blurFBO[2] = {};
    GLuint m_blurTex[2] = {};

    // Full-screen quad (NDC triangle strip).
    GLuint m_quadVAO = 0;
    GLuint m_quadVBO = 0;

    // Shader programs.
    GLuint m_brightProg    = 0;
    GLuint m_blurProg      = 0;
    GLuint m_compositeProg = 0;

    // Cached uniform locations.
    GLint m_uBrightScene     = -1;
    GLint m_uBrightThreshold = -1;
    GLint m_uBlurTex         = -1;
    GLint m_uBlurDir         = -1;
    GLint m_uCompScene       = -1;
    GLint m_uCompBloom       = -1;
    GLint m_uCompIntensity   = -1;
};

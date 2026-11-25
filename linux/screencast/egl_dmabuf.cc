// SPDX-FileCopyrightText: 2026 Mein1337
// SPDX-License-Identifier: AGPL-3.0-or-later

#include "egl_dmabuf.h"

#include <EGL/eglext.h>
#include <GLES2/gl2.h>
#include <GLES2/gl2ext.h>

#include <cstdio>
#include <cstring>

#ifndef EGL_PLATFORM_SURFACELESS_MESA
#define EGL_PLATFORM_SURFACELESS_MESA 0x31DD
#endif

namespace hardline_screencast {

namespace {

constexpr uint64_t kModInvalid = 0x00ffffffffffffffULL;

PFNEGLQUERYDEVICESEXTPROC query_devices;
PFNEGLQUERYDEVICESTRINGEXTPROC query_device_string;
PFNEGLGETPLATFORMDISPLAYEXTPROC get_platform_display;
PFNEGLQUERYDMABUFMODIFIERSEXTPROC query_dmabuf_modifiers;
PFNEGLCREATEIMAGEKHRPROC create_image;
PFNEGLDESTROYIMAGEKHRPROC destroy_image;
PFNGLEGLIMAGETARGETTEXTURE2DOESPROC image_target_texture;

bool HasExtension(const char* list, const char* name) {
  if (list == nullptr) return false;
  const size_t length = strlen(name);
  for (const char* p = list; (p = strstr(p, name)) != nullptr; p += length) {
    const bool starts = p == list || p[-1] == ' ';
    const bool ends = p[length] == '\0' || p[length] == ' ';
    if (starts && ends) return true;
  }
  return false;
}

template <typename T>
void Load(T* fn, const char* name) {
  *fn = reinterpret_cast<T>(eglGetProcAddress(name));
}

// A display on a real GPU. Prefers EGL_EXT_platform_device, which needs no
// window system and is what NVIDIA's driver offers; Mesa offers it too. The
// software rasteriser is skipped: it cannot import a GPU buffer.
EGLDisplay OpenDisplay() {
  const char* client = eglQueryString(EGL_NO_DISPLAY, EGL_EXTENSIONS);
  Load(&get_platform_display, "eglGetPlatformDisplayEXT");
  if (get_platform_display == nullptr) return EGL_NO_DISPLAY;

  if (HasExtension(client, "EGL_EXT_device_enumeration") &&
      HasExtension(client, "EGL_EXT_platform_device")) {
    Load(&query_devices, "eglQueryDevicesEXT");
    Load(&query_device_string, "eglQueryDeviceStringEXT");
    EGLDeviceEXT devices[16];
    EGLint count = 0;
    if (query_devices && query_device_string &&
        query_devices(16, devices, &count)) {
      for (EGLint i = 0; i < count; i++) {
        const char* exts = query_device_string(devices[i], EGL_EXTENSIONS);
        if (HasExtension(exts, "EGL_MESA_device_software")) continue;
        if (!HasExtension(exts, "EGL_EXT_device_drm") &&
            !HasExtension(exts, "EGL_EXT_device_drm_render_node")) {
          continue;
        }
        EGLDisplay display =
            get_platform_display(EGL_PLATFORM_DEVICE_EXT, devices[i], nullptr);
        if (display != EGL_NO_DISPLAY &&
            eglInitialize(display, nullptr, nullptr)) {
          return display;
        }
      }
    }
  }

  if (HasExtension(client, "EGL_MESA_platform_surfaceless")) {
    EGLDisplay display = get_platform_display(EGL_PLATFORM_SURFACELESS_MESA,
                                              EGL_DEFAULT_DISPLAY, nullptr);
    if (display != EGL_NO_DISPLAY && eglInitialize(display, nullptr, nullptr)) {
      return display;
    }
  }
  return EGL_NO_DISPLAY;
}

}  // namespace

EglDmaBuf::EglDmaBuf() {
  display_ = OpenDisplay();
  if (display_ == EGL_NO_DISPLAY) {
    fprintf(stderr, "[screencast] no EGL display for DMA-BUF import\n");
    return;
  }

  const char* exts = eglQueryString(display_, EGL_EXTENSIONS);
  if (!HasExtension(exts, "EGL_EXT_image_dma_buf_import") ||
      !HasExtension(exts, "EGL_KHR_surfaceless_context")) {
    fprintf(stderr, "[screencast] EGL display cannot import DMA-BUFs\n");
    return;
  }
  has_modifiers_ = HasExtension(exts, "EGL_EXT_image_dma_buf_import_modifiers");

  Load(&create_image, "eglCreateImageKHR");
  Load(&destroy_image, "eglDestroyImageKHR");
  Load(&image_target_texture, "glEGLImageTargetTexture2DOES");
  if (has_modifiers_) Load(&query_dmabuf_modifiers, "eglQueryDmaBufModifiersEXT");
  if (!create_image || !destroy_image || !image_target_texture) return;

  if (!eglBindAPI(EGL_OPENGL_ES_API)) return;
  EGLConfig config = nullptr;
  if (!HasExtension(exts, "EGL_KHR_no_config_context")) {
    const EGLint attribs[] = {EGL_RENDERABLE_TYPE, EGL_OPENGL_ES2_BIT,
                              EGL_NONE};
    EGLint count = 0;
    if (!eglChooseConfig(display_, attribs, &config, 1, &count) || count < 1) {
      return;
    }
  }
  const EGLint context_attribs[] = {EGL_CONTEXT_CLIENT_VERSION, 2, EGL_NONE};
  context_ =
      eglCreateContext(display_, config, EGL_NO_CONTEXT, context_attribs);
  if (context_ == EGL_NO_CONTEXT) {
    fprintf(stderr, "[screencast] eglCreateContext failed: 0x%x\n",
            eglGetError());
    return;
  }
  ok_ = true;
}

EglDmaBuf::~EglDmaBuf() {
  if (context_ != EGL_NO_CONTEXT) {
    if (gl_ready_ && MakeCurrent()) {
      glDeleteFramebuffers(1, &framebuffer_);
      glDeleteTextures(1, &texture_);
    }
    eglMakeCurrent(display_, EGL_NO_SURFACE, EGL_NO_SURFACE, EGL_NO_CONTEXT);
    eglDestroyContext(display_, context_);
  }
  // The display is left initialised: EGL displays are per process and shared
  // by every capture, and terminating one would pull it out from under the
  // others.
}

bool EglDmaBuf::MakeCurrent() {
  return eglMakeCurrent(display_, EGL_NO_SURFACE, EGL_NO_SURFACE, context_);
}

std::vector<uint64_t> EglDmaBuf::QueryModifiers(uint32_t drm_format) {
  std::vector<uint64_t> result;
  if (!ok_) return result;
  if (has_modifiers_ && query_dmabuf_modifiers) {
    EGLint count = 0;
    if (query_dmabuf_modifiers(display_, drm_format, 0, nullptr, nullptr,
                               &count) &&
        count > 0) {
      std::vector<EGLuint64KHR> modifiers(count);
      std::vector<EGLBoolean> external_only(count);
      if (query_dmabuf_modifiers(display_, drm_format, count, modifiers.data(),
                                 external_only.data(), &count)) {
        for (EGLint i = 0; i < count; i++) {
          // External-only images can only be sampled through
          // samplerExternalOES, never attached to a framebuffer.
          if (!external_only[i]) result.push_back(modifiers[i]);
        }
      }
    }
  }
  // "Implicit": whatever layout the driver picks on its own, which is what a
  // compositor without modifier support allocates.
  result.push_back(kModInvalid);
  return result;
}

bool EglDmaBuf::ReadPixels(uint32_t drm_format, uint64_t modifier, int width,
                           int height, const std::vector<DmaBufPlane>& planes,
                           std::vector<uint8_t>* rgba) {
  if (!ok_ || planes.empty() || planes.size() > 4 || !MakeCurrent()) {
    return false;
  }
  if (!gl_ready_) {
    glGenTextures(1, &texture_);
    glBindTexture(GL_TEXTURE_2D, texture_);
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, GL_NEAREST);
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, GL_NEAREST);
    glGenFramebuffers(1, &framebuffer_);
    gl_ready_ = true;
  }

  static const EGLint kFd[] = {
      EGL_DMA_BUF_PLANE0_FD_EXT, EGL_DMA_BUF_PLANE1_FD_EXT,
      EGL_DMA_BUF_PLANE2_FD_EXT, EGL_DMA_BUF_PLANE3_FD_EXT};
  static const EGLint kOffset[] = {
      EGL_DMA_BUF_PLANE0_OFFSET_EXT, EGL_DMA_BUF_PLANE1_OFFSET_EXT,
      EGL_DMA_BUF_PLANE2_OFFSET_EXT, EGL_DMA_BUF_PLANE3_OFFSET_EXT};
  static const EGLint kPitch[] = {
      EGL_DMA_BUF_PLANE0_PITCH_EXT, EGL_DMA_BUF_PLANE1_PITCH_EXT,
      EGL_DMA_BUF_PLANE2_PITCH_EXT, EGL_DMA_BUF_PLANE3_PITCH_EXT};
  static const EGLint kModLo[] = {
      EGL_DMA_BUF_PLANE0_MODIFIER_LO_EXT, EGL_DMA_BUF_PLANE1_MODIFIER_LO_EXT,
      EGL_DMA_BUF_PLANE2_MODIFIER_LO_EXT, EGL_DMA_BUF_PLANE3_MODIFIER_LO_EXT};
  static const EGLint kModHi[] = {
      EGL_DMA_BUF_PLANE0_MODIFIER_HI_EXT, EGL_DMA_BUF_PLANE1_MODIFIER_HI_EXT,
      EGL_DMA_BUF_PLANE2_MODIFIER_HI_EXT, EGL_DMA_BUF_PLANE3_MODIFIER_HI_EXT};

  std::vector<EGLint> attribs = {EGL_WIDTH, width, EGL_HEIGHT, height,
                                 EGL_LINUX_DRM_FOURCC_EXT,
                                 static_cast<EGLint>(drm_format)};
  const bool explicit_modifier = has_modifiers_ && modifier != kModInvalid;
  for (size_t i = 0; i < planes.size(); i++) {
    attribs.insert(attribs.end(),
                   {kFd[i], planes[i].fd, kOffset[i],
                    static_cast<EGLint>(planes[i].offset), kPitch[i],
                    static_cast<EGLint>(planes[i].stride)});
    if (explicit_modifier) {
      attribs.insert(attribs.end(),
                     {kModLo[i], static_cast<EGLint>(modifier & 0xffffffff),
                      kModHi[i], static_cast<EGLint>(modifier >> 32)});
    }
  }
  attribs.push_back(EGL_NONE);

  EGLImageKHR image = create_image(display_, EGL_NO_CONTEXT,
                                   EGL_LINUX_DMA_BUF_EXT, nullptr,
                                   attribs.data());
  if (image == EGL_NO_IMAGE_KHR) {
    fprintf(stderr, "[screencast] DMA-BUF import failed: 0x%x\n",
            eglGetError());
    return false;
  }

  glBindTexture(GL_TEXTURE_2D, texture_);
  image_target_texture(GL_TEXTURE_2D, image);
  glBindFramebuffer(GL_FRAMEBUFFER, framebuffer_);
  glFramebufferTexture2D(GL_FRAMEBUFFER, GL_COLOR_ATTACHMENT0, GL_TEXTURE_2D,
                         texture_, 0);
  bool ok = glCheckFramebufferStatus(GL_FRAMEBUFFER) == GL_FRAMEBUFFER_COMPLETE;
  if (ok) {
    rgba->resize(static_cast<size_t>(width) * height * 4);
    glPixelStorei(GL_PACK_ALIGNMENT, 4);
    // Row 0 of the image is row 0 of the texture, and glReadPixels starts at
    // row 0 too, so the picture comes out the right way up.
    glReadPixels(0, 0, width, height, GL_RGBA, GL_UNSIGNED_BYTE, rgba->data());
    ok = glGetError() == GL_NO_ERROR;
  } else {
    fprintf(stderr, "[screencast] DMA-BUF framebuffer incomplete\n");
  }
  glFramebufferTexture2D(GL_FRAMEBUFFER, GL_COLOR_ATTACHMENT0, GL_TEXTURE_2D,
                         0, 0);
  glBindFramebuffer(GL_FRAMEBUFFER, 0);
  destroy_image(display_, image);
  // Released after every frame, so the context is never left current on the
  // capture thread: the destructor runs on another thread and needs it.
  eglMakeCurrent(display_, EGL_NO_SURFACE, EGL_NO_SURFACE, EGL_NO_CONTEXT);
  return ok;
}

}  // namespace hardline_screencast

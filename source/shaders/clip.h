#if !defined(CLIP_H)
#define CLIP_H

#if defined(GL_ES)
    out vec2 depth_ratio;

    void place_clip(vec4 clip) {
        depth_ratio = clip.zw;
        gl_Position = vec4(clip.x, -clip.y, 2.0 * clip.z - clip.w, clip.w);
    }
#else
    void place_clip(vec4 clip) {
        gl_Position = clip;
    }
#endif

#endif

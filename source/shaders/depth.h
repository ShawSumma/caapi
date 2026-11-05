#if !defined(DEPTH_H)
#define DEPTH_H

#if defined(GL_ES)
    in vec2 depth_ratio;

    void write_depth() {
        gl_FragDepth = depth_ratio.x / depth_ratio.y;
    }
#else
    void write_depth() {
    }
#endif

#endif

module client.renderer;

import std.string : toStringz, fromStringz;
import std.stdio : writeln;
import std.math : tan, PI;
import client.gl;
import common.math : Matrix4;
import common.world : DIM;
import client.mesher : Vertex, meshCube;

private enum string VERT_SRC = import("cube.vert");
private enum string FRAG_SRC = import("cube.frag");

struct CubeMesh {
    GLuint vao;
    GLuint vbo;
    int count;
}

struct Renderer {
    GLuint program;
    GLint uModel;
    GLint uProj;
    Matrix4 proj;

    void init(int fbw, int fbh) {
        program = buildProgram(VERT_SRC, FRAG_SRC);
        uModel = glGetUniformLocation(program, "model".ptr);
        uProj = glGetUniformLocation(program, "proj".ptr);
        glEnable(GL_DEPTH_TEST);
        glDepthFunc(GL_LESS);
        glEnable(GL_CULL_FACE);
        glCullFace(GL_BACK);
        resize(fbw, fbh);
    }

    void resize(int w, int h) {
        glViewport(0, 0, w, h);
        float aspect = h > 0 ? cast(float) w / h : 1.0f;
        proj = perspective(100.0f, aspect, 0.001f, 2.0f);
    }

    CubeMesh upload(const ushort[] voxels) {
        Vertex[] verts = meshCube(voxels);
        CubeMesh mesh;
        mesh.count = cast(int) verts.length;
        if (verts.length == 0) {
            return mesh;
        }
        glGenVertexArrays(1, &mesh.vao);
        glBindVertexArray(mesh.vao);
        glGenBuffers(1, &mesh.vbo);
        glBindBuffer(GL_ARRAY_BUFFER, mesh.vbo);
        glBufferData(
            GL_ARRAY_BUFFER,
            cast(GLsizeiptr)(verts.length * Vertex.sizeof),
            verts.ptr,
            GL_STATIC_DRAW,
        );
        glVertexAttribPointer(
            0,
            3,
            GL_FLOAT,
            GL_FALSE,
            Vertex.sizeof,
            cast(void*) 0,
        );
        glEnableVertexAttribArray(0);
        glVertexAttribPointer(
            1,
            3,
            GL_FLOAT,
            GL_FALSE,
            Vertex.sizeof,
            cast(void*)(3 * float.sizeof),
        );
        glEnableVertexAttribArray(1);
        glBindVertexArray(0);
        return mesh;
    }

    void beginFrame() {
        glClearColor(0.06, 0.07, 0.10, 1.0);
        glClear(GL_COLOR_BUFFER_BIT | GL_DEPTH_BUFFER_BIT);
        glUseProgram(program);
        float[16] pf = proj.flat();
        glUniformMatrix4fv(uProj, 1, GL_FALSE, pf.ptr);
    }

    void draw(ref CubeMesh mesh, Matrix4 model) {
        if (mesh.count == 0) {
            return;
        }
        float[16] mf = model.flat();
        glUniformMatrix4fv(uModel, 1, GL_FALSE, mf.ptr);
        glBindVertexArray(mesh.vao);
        glDrawArrays(GL_TRIANGLES, 0, mesh.count);
    }
}

private Matrix4 perspective(float fovDeg, float aspect, float near, float far) {
    float f = 1.0f / tan(fovDeg * (PI / 180.0f) * 0.5f);
    Matrix4 m;
    m.data = [
        [0, 0, 0, 0],
        [0, 0, 0, 0],
        [0, 0, 0, 0],
        [0, 0, 0, 0],
    ];
    m.data[0][0] = f / aspect;
    m.data[1][1] = f;
    m.data[2][2] = (far + near) / (near - far);
    m.data[2][3] = -1.0f;
    m.data[3][2] = (2.0f * far * near) / (near - far);
    return m;
}

private GLuint compile(GLenum type, string src) {
    GLuint s = glCreateShader(type);
    const(char)* p = src.ptr;
    GLint len = cast(GLint) src.length;
    glShaderSource(s, 1, &p, &len);
    glCompileShader(s);
    GLint ok;
    glGetShaderiv(s, GL_COMPILE_STATUS, &ok);
    if (!ok) {
        char[1024] log;
        glGetShaderInfoLog(s, 1024, null, log.ptr);
        writeln("shader compile error: ", fromStringz(log.ptr));
    }
    return s;
}

private GLuint buildProgram(string vsrc, string fsrc) {
    GLuint vs = compile(GL_VERTEX_SHADER, vsrc);
    GLuint fs = compile(GL_FRAGMENT_SHADER, fsrc);
    GLuint p = glCreateProgram();
    glAttachShader(p, vs);
    glAttachShader(p, fs);
    glLinkProgram(p);
    GLint ok;
    glGetProgramiv(p, GL_LINK_STATUS, &ok);
    if (!ok) {
        char[1024] log;
        glGetProgramInfoLog(p, 1024, null, log.ptr);
        writeln("program link error: ", fromStringz(log.ptr));
    }
    glDeleteShader(vs);
    glDeleteShader(fs);
    return p;
}

module client.gl;

import client.glfw : glfwGetProcAddress;

extern (C) @nogc nothrow:

alias GLenum = uint;
alias GLbitfield = uint;
alias GLuint = uint;
alias GLint = int;
alias GLsizei = int;
alias GLfloat = float;
alias GLboolean = ubyte;
alias GLchar = char;
alias GLsizeiptr = ptrdiff_t;
alias GLintptr = ptrdiff_t;

enum GLenum GL_FALSE = 0;
enum GLenum GL_TRUE = 1;
enum GLenum GL_TRIANGLES = 0x0004;
enum GLenum GL_DEPTH_TEST = 0x0B71;
enum GLenum GL_CULL_FACE = 0x0B44;
enum GLenum GL_BACK = 0x0405;
enum GLenum GL_LESS = 0x0201;
enum GLenum GL_COLOR_BUFFER_BIT = 0x4000;
enum GLenum GL_DEPTH_BUFFER_BIT = 0x0100;
enum GLenum GL_ARRAY_BUFFER = 0x8892;
enum GLenum GL_STATIC_DRAW = 0x88E4;
enum GLenum GL_DYNAMIC_DRAW = 0x88E8;
enum GLenum GL_FLOAT = 0x1406;
enum GLenum GL_VERTEX_SHADER = 0x8B31;
enum GLenum GL_FRAGMENT_SHADER = 0x8B30;
enum GLenum GL_COMPILE_STATUS = 0x8B81;
enum GLenum GL_LINK_STATUS = 0x8B82;

// Fixed-pipeline-ish calls that link directly against libGL.
void glClear(GLbitfield mask);
void glClearColor(GLfloat r, GLfloat g, GLfloat b, GLfloat a);
void glEnable(GLenum cap);
void glDisable(GLenum cap);
void glCullFace(GLenum mode);
void glDepthFunc(GLenum func);
void glViewport(GLint x, GLint y, GLsizei w, GLsizei h);
void glDrawArrays(GLenum mode, GLint first, GLsizei count);

// Modern GL loaded via glfwGetProcAddress.
__gshared:
GLuint function() glCreateProgram;
GLuint function(GLenum) glCreateShader;
void function(GLuint, GLsizei, const(GLchar*)*, const(GLint)*) glShaderSource;
void function(GLuint) glCompileShader;
void function(GLuint, GLenum, GLint*) glGetShaderiv;
void function(GLuint, GLsizei, GLsizei*, GLchar*) glGetShaderInfoLog;
void function(GLuint, GLuint) glAttachShader;
void function(GLuint) glLinkProgram;
void function(GLuint, GLenum, GLint*) glGetProgramiv;
void function(GLuint, GLsizei, GLsizei*, GLchar*) glGetProgramInfoLog;
void function(GLuint) glUseProgram;
void function(GLuint) glDeleteShader;
void function(GLsizei, GLuint*) glGenVertexArrays;
void function(GLuint) glBindVertexArray;
void function(GLsizei, GLuint*) glGenBuffers;
void function(GLenum, GLuint) glBindBuffer;
void function(GLenum, GLsizeiptr, const(void)*, GLenum) glBufferData;
void function(GLuint, GLint, GLenum, GLboolean, GLsizei, const(void)*) glVertexAttribPointer;
void function(GLuint) glEnableVertexAttribArray;
GLint function(GLuint, const(GLchar)*) glGetUniformLocation;
void function(GLint, GLsizei, GLboolean, const(GLfloat)*) glUniformMatrix4fv;
void function(GLint, GLfloat, GLfloat, GLfloat, GLfloat) glUniform4f;

extern (D):

// name must be a null-terminated string literal (all call sites below pass one).
private void* load(string name) {
    return glfwGetProcAddress(name.ptr);
}

/// Resolve modern GL entry points. Call once after a context is current.
void loadGL() {
    glCreateProgram = cast(typeof(glCreateProgram)) load("glCreateProgram");
    glCreateShader = cast(typeof(glCreateShader)) load("glCreateShader");
    glShaderSource = cast(typeof(glShaderSource)) load("glShaderSource");
    glCompileShader = cast(typeof(glCompileShader)) load("glCompileShader");
    glGetShaderiv = cast(typeof(glGetShaderiv)) load("glGetShaderiv");
    glGetShaderInfoLog = cast(typeof(glGetShaderInfoLog)) load("glGetShaderInfoLog");
    glAttachShader = cast(typeof(glAttachShader)) load("glAttachShader");
    glLinkProgram = cast(typeof(glLinkProgram)) load("glLinkProgram");
    glGetProgramiv = cast(typeof(glGetProgramiv)) load("glGetProgramiv");
    glGetProgramInfoLog = cast(typeof(glGetProgramInfoLog)) load("glGetProgramInfoLog");
    glUseProgram = cast(typeof(glUseProgram)) load("glUseProgram");
    glDeleteShader = cast(typeof(glDeleteShader)) load("glDeleteShader");
    glGenVertexArrays = cast(typeof(glGenVertexArrays)) load("glGenVertexArrays");
    glBindVertexArray = cast(typeof(glBindVertexArray)) load("glBindVertexArray");
    glGenBuffers = cast(typeof(glGenBuffers)) load("glGenBuffers");
    glBindBuffer = cast(typeof(glBindBuffer)) load("glBindBuffer");
    glBufferData = cast(typeof(glBufferData)) load("glBufferData");
    glVertexAttribPointer = cast(typeof(glVertexAttribPointer)) load("glVertexAttribPointer");
    glEnableVertexAttribArray = cast(typeof(glEnableVertexAttribArray)) load("glEnableVertexAttribArray");
    glGetUniformLocation = cast(typeof(glGetUniformLocation)) load("glGetUniformLocation");
    glUniformMatrix4fv = cast(typeof(glUniformMatrix4fv)) load("glUniformMatrix4fv");
    glUniform4f = cast(typeof(glUniform4f)) load("glUniform4f");
}

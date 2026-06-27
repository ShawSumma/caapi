module client.glfw;

// Minimal GLFW + OpenGL bindings — just what the renderer uses.
extern (C) @nogc nothrow:

alias GLFWwindow = void;

enum int GLFW_CONTEXT_VERSION_MAJOR = 0x00022002;
enum int GLFW_CONTEXT_VERSION_MINOR = 0x00022003;
enum int GLFW_OPENGL_PROFILE = 0x00022008;
enum int GLFW_OPENGL_CORE_PROFILE = 0x00032001;
enum int GLFW_OPENGL_FORWARD_COMPAT = 0x00022006;
enum int GLFW_DEPTH_BITS = 0x00021005;
enum int GLFW_TRUE = 1;

enum int GLFW_PRESS = 1;
enum int GLFW_KEY_W = 87;
enum int GLFW_KEY_A = 65;
enum int GLFW_KEY_S = 83;
enum int GLFW_KEY_D = 68;
enum int GLFW_KEY_SPACE = 32;
enum int GLFW_KEY_LEFT_SHIFT = 340;
enum int GLFW_KEY_LEFT = 263;
enum int GLFW_KEY_RIGHT = 262;
enum int GLFW_KEY_UP = 265;
enum int GLFW_KEY_DOWN = 264;
enum int GLFW_KEY_ESCAPE = 256;

int glfwInit();
void glfwTerminate();
void glfwWindowHint(int hint, int value);
GLFWwindow* glfwCreateWindow(int w, int h, const(char)* title, void* monitor, void* share);
void glfwMakeContextCurrent(GLFWwindow* window);
int glfwWindowShouldClose(GLFWwindow* window);
void glfwSwapBuffers(GLFWwindow* window);
void glfwSwapInterval(int interval);
void glfwPollEvents();
int glfwGetKey(GLFWwindow* window, int key);
void glfwSetWindowShouldClose(GLFWwindow* window, int value);
void glfwGetFramebufferSize(GLFWwindow* window, int* w, int* h);
double glfwGetTime();
void* glfwGetProcAddress(const(char)* name);

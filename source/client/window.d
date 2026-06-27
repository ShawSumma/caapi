module client.window;

import std.string : toStringz;
import client.glfw;
import client.gl : loadGL;

struct Window {
    GLFWwindow* handle;
    int width;
    int height;

    static Window* open(int w, int h, string title) {
        if (!glfwInit()) {
            return null;
        }
        glfwWindowHint(GLFW_CONTEXT_VERSION_MAJOR, 3);
        glfwWindowHint(GLFW_CONTEXT_VERSION_MINOR, 3);
        glfwWindowHint(GLFW_OPENGL_PROFILE, GLFW_OPENGL_CORE_PROFILE);
        glfwWindowHint(GLFW_OPENGL_FORWARD_COMPAT, GLFW_TRUE);
        glfwWindowHint(GLFW_DEPTH_BITS, 24);

        GLFWwindow* handle = glfwCreateWindow(w, h, title.toStringz, null, null);
        if (handle is null) {
            glfwTerminate();
            return null;
        }
        glfwMakeContextCurrent(handle);
        glfwSwapInterval(1);
        loadGL();

        Window* win = new Window;
        win.handle = handle;
        glfwGetFramebufferSize(handle, &win.width, &win.height);
        return win;
    }

    bool shouldClose() {
        return glfwWindowShouldClose(handle) != 0;
    }

    void requestClose() {
        glfwSetWindowShouldClose(handle, 1);
    }

    void swap() {
        glfwSwapBuffers(handle);
    }

    void poll() {
        glfwPollEvents();
    }

    bool key(int code) {
        return glfwGetKey(handle, code) == GLFW_PRESS;
    }

    void close() {
        glfwTerminate();
    }
}

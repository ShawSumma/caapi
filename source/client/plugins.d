module client.plugins;

import core.stdc.stdio : fprintf, snprintf, stderr;
import core.stdc.string : strlen;
import core.sys.posix.dirent : DIR, closedir, dirent, opendir, readdir;
import core.sys.posix.dlfcn : RTLD_NOW, dlerror, dlopen, dlsym;
import plugins.api.api : ENTRY, Entry, Registry, Structure;

enum size_t MAX_STRUCTURES = 64;
enum size_t PATH_CAPACITY = 4096;
enum string PLUGIN_DIRECTORY = "lib";
version (OSX) {
    enum string LIBRARY_SUFFIX = ".dylib";
} else {
    enum string LIBRARY_SUFFIX = ".so";
}

struct Worlds {
    string[MAX_STRUCTURES] names;
    Structure[MAX_STRUCTURES] structures;
    size_t count;

    void gather() {
        DIR* directory = opendir(PLUGIN_DIRECTORY.ptr);
        if (directory is null) {
            fprintf(stderr, "cannot open the plugin directory '%s'\n", PLUGIN_DIRECTORY.ptr);
        } else {
            dirent* entry = readdir(directory);
            while (entry !is null) {
                const(char)[] name = entry.d_name.ptr[0 .. strlen(entry.d_name.ptr)];
                if (name.length > LIBRARY_SUFFIX.length && name[$ - LIBRARY_SUFFIX.length .. $] == LIBRARY_SUFFIX) {
                    load(name);
                }
                entry = readdir(directory);
            }
            closedir(directory);
        }
    }

    void load(const(char)[] file) {
        char[PATH_CAPACITY] path = 0;
        snprintf(path.ptr, path.length, "%s/%.*s", PLUGIN_DIRECTORY.ptr, cast(int) file.length, file.ptr);
        void* library = dlopen(path.ptr, RTLD_NOW);
        if (library is null) {
            fprintf(stderr, "cannot load the plugin '%s': %s\n", path.ptr, dlerror());
        } else {
            Entry plugin = cast(Entry) dlsym(library, ENTRY.ptr);
            if (plugin is null) {
                fprintf(stderr, "the plugin '%s' has no '%s'\n", path.ptr, ENTRY.ptr);
            } else {
                Registry registry = Registry(&this, &add);
                plugin(&registry);
            }
        }
    }

    const(string)[] allNames() const return {
        return names[0 .. count];
    }

    Structure find(const(char)[] name) const {
        size_t index = 0;
        while (index < count && names[index] != name) {
            index += 1;
        }
        return index < count ? structures[index] : null;
    }
}

void add(const(Registry)* registry, const(char)* name, Structure world) {
    Worlds* worlds = cast(Worlds*) registry.host;
    assert(worlds.count < MAX_STRUCTURES);
    worlds.names[worlds.count] = cast(string) name[0 .. strlen(name)];
    worlds.structures[worlds.count] = world;
    worlds.count += 1;
}

__gshared Worlds gathered;
__gshared bool isGathered;

ref const(Worlds) registry() {
    if (!isGathered) {
        gathered.gather();
        isGathered = true;
    }
    return gathered;
}

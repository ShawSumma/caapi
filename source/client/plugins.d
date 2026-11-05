module client.plugins;

import core.stdc.stdio : fprintf, snprintf, stderr;
import core.stdc.string : strlen;
import base.flags : Readiness;
import plugins.api.api : ENTRY, Entry, Registry, RisingKind, Structure;

enum size_t MAX_STRUCTURES = 64;
enum size_t MAX_KINDS = 32;
enum size_t MAX_LANDMARKS = 32;
enum size_t PATH_CAPACITY = 4096;
enum string PLUGIN_DIRECTORY = "lib";
version (WebAssembly) {
    import arbor = plugins.arbor.plugin;
    import babel = plugins.babel.plugin;
    import backrooms = plugins.backrooms.plugin;
    import city = plugins.city.plugin;
    import crown = plugins.crown.plugin;
    import fixtures = plugins.fixtures.plugin;
    import lattice = plugins.lattice.plugin;
    import library = plugins.library.plugin;
    import palace = plugins.palace.plugin;
    import planet = plugins.planet.plugin;
    import road = plugins.road.plugin;
    import tower = plugins.tower.plugin;
    import trail = plugins.trail.plugin;
} else version (OSX) {
    import core.sys.posix.dirent : DIR, closedir, dirent, opendir, readdir;
    import core.sys.posix.dlfcn : RTLD_NOW, dlerror, dlopen, dlsym;
    import core.sys.posix.stdlib : realpath;

    enum string LIBRARY_SUFFIX = ".dylib";

    extern (C) int _NSGetExecutablePath(char* buffer, uint* size) nothrow @nogc;

    size_t executablePath(ref char[PATH_CAPACITY] resolved) {
        char[PATH_CAPACITY] path = 0;
        uint size = cast(uint) path.length;
        if (_NSGetExecutablePath(path.ptr, &size) != 0 || realpath(path.ptr, resolved.ptr) is null) {
            return 0;
        } else {
            return strlen(resolved.ptr);
        }
    }
} else {
    import core.sys.posix.dirent : DIR, closedir, dirent, opendir, readdir;
    import core.sys.posix.dlfcn : RTLD_NOW, dlerror, dlopen, dlsym;
    import core.sys.posix.unistd : readlink;

    enum string LIBRARY_SUFFIX = ".so";

    size_t executablePath(ref char[PATH_CAPACITY] path) {
        ptrdiff_t length = readlink("/proc/self/exe", path.ptr, path.length);
        if (length <= 0 || length == path.length) {
            return 0;
        } else {
            return cast(size_t) length;
        }
    }
}

void sortByName(T)(string[] names, T[] items) {
    foreach (index; 1 .. names.length) {
        string name = names[index];
        T item = items[index];
        size_t at = index;
        while (at > 0 && isOrderedAfter(names[at - 1], name)) {
            names[at] = names[at - 1];
            items[at] = items[at - 1];
            at -= 1;
        }
        names[at] = name;
        items[at] = item;
    }
}

bool isOrderedAfter(const(char)[] a, const(char)[] b) {
    size_t index = 0;
    while (index < a.length && index < b.length && a[index] == b[index]) {
        index += 1;
    }
    if (index == a.length || index == b.length) {
        return a.length > b.length;
    } else {
        return a[index] > b[index];
    }
}

struct Worlds {
    string[MAX_STRUCTURES] names;
    Structure[MAX_STRUCTURES] structures;
    size_t count;
    string[MAX_KINDS] kindNames;
    RisingKind[MAX_KINDS] risingKinds;
    size_t kindCount;
    string[MAX_LANDMARKS] landmarkNames;
    Structure[MAX_LANDMARKS] landmarks;
    size_t landmarkCount;

    void sort() {
        sortByName(names[0 .. count], structures[0 .. count]);
        sortByName(kindNames[0 .. kindCount], risingKinds[0 .. kindCount]);
        sortByName(landmarkNames[0 .. landmarkCount], landmarks[0 .. landmarkCount]);
    }

    version (WebAssembly) {
        void gather() {
            Registry registry = Registry(&this, &add, &addKind, &addLandmark);
            Entry[13] entries = [&arbor.plugin, &babel.plugin, &backrooms.plugin, &city.plugin, &crown.plugin, &fixtures.plugin, &lattice.plugin, &library.plugin, &palace.plugin, &planet.plugin, &road.plugin, &tower.plugin, &trail.plugin];
            foreach (entry; entries) {
                entry(&registry);
            }
            sort();
        }
    } else {
        void gather() {
            char[PATH_CAPACITY] directory = 0;
            size_t length = executablePath(directory);
            while (length > 0 && directory[length - 1] != '/') {
                length -= 1;
            }
            if (length == 0) {
                fprintf(stderr, "cannot find the executable's own path, so no plugins are loaded\n");
            } else {
                snprintf(directory.ptr + length, directory.length - length, "%s", PLUGIN_DIRECTORY.ptr);
                gatherFrom(directory.ptr);
                sort();
            }
        }

        void gatherFrom(const(char)* path) {
            DIR* directory = opendir(path);
            if (directory is null) {
                fprintf(stderr, "cannot open the plugin directory '%s'\n", path);
            } else {
                dirent* entry = readdir(directory);
                while (entry !is null) {
                    const(char)[] name = entry.d_name.ptr[0 .. strlen(entry.d_name.ptr)];
                    if (name.length > LIBRARY_SUFFIX.length && name[$ - LIBRARY_SUFFIX.length .. $] == LIBRARY_SUFFIX) {
                        load(path, name);
                    }
                    entry = readdir(directory);
                }
                closedir(directory);
            }
        }

        void load(const(char)* directory, const(char)[] file) {
            char[PATH_CAPACITY] path = 0;
            snprintf(path.ptr, path.length, "%s/%.*s", directory, cast(int) file.length, file.ptr);
            void* library = dlopen(path.ptr, RTLD_NOW);
            if (library is null) {
                fprintf(stderr, "cannot load the plugin '%s': %s\n", path.ptr, dlerror());
            } else {
                Entry plugin = cast(Entry) dlsym(library, ENTRY.ptr);
                if (plugin is null) {
                    fprintf(stderr, "the plugin '%s' has no '%s'; it may have been built against another version of the API\n", path.ptr, ENTRY.ptr);
                } else {
                    Registry registry = Registry(&this, &add, &addKind, &addLandmark);
                    plugin(&registry);
                }
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
        if (index < count) {
            return structures[index];
        } else {
            return null;
        }
    }
}

void add(const(Registry)* registry, const(char)* name, Structure world) {
    Worlds* worlds = cast(Worlds*) registry.host;
    if (worlds.count == MAX_STRUCTURES) {
        fprintf(stderr, "too many worlds, '%s' is left out (at most %zu)\n", name, MAX_STRUCTURES);
    } else {
        worlds.names[worlds.count] = cast(string) name[0 .. strlen(name)];
        worlds.structures[worlds.count] = world;
        worlds.count += 1;
    }
}

void addKind(const(Registry)* registry, const(char)* name, const(RisingKind)* kind) {
    Worlds* worlds = cast(Worlds*) registry.host;
    if (worlds.kindCount == MAX_KINDS) {
        fprintf(stderr, "too many rising kinds, '%s' is left out (at most %zu)\n", name, MAX_KINDS);
    } else {
        worlds.kindNames[worlds.kindCount] = cast(string) name[0 .. strlen(name)];
        worlds.risingKinds[worlds.kindCount] = *kind;
        worlds.kindCount += 1;
    }
}

void addLandmark(const(Registry)* registry, const(char)* name, Structure landmark) {
    Worlds* worlds = cast(Worlds*) registry.host;
    if (worlds.landmarkCount == MAX_LANDMARKS) {
        fprintf(stderr, "too many landmarks, '%s' is left out (at most %zu)\n", name, MAX_LANDMARKS);
    } else {
        worlds.landmarkNames[worlds.landmarkCount] = cast(string) name[0 .. strlen(name)];
        worlds.landmarks[worlds.landmarkCount] = landmark;
        worlds.landmarkCount += 1;
    }
}

__gshared Worlds gathered;
__gshared Readiness gatheredState;

ref const(Worlds) registry() {
    if (gatheredState == Readiness.pending) {
        gathered.gather();
        gatheredState = Readiness.ready;
    }
    return gathered;
}

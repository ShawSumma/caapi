module client.plugins;

import core.stdc.string : strlen;
import base.flags : Readiness;
import base.stdio : fprintf, snprintf, stderr;
import core.stdc.stdlib : malloc;
import core.stdc.string : memcpy;
import base.array : Array;
import common.content.content : USER_SETTINGS;
import common.content.load : loadContent;
import common.content.mods : ModOrder, describe, orderMods;
import plugins.api.api : ENTRY, Entry, Registry, RisingKind, Structure;
import plugins.api.content : Manifest;

enum size_t MAX_PLUGINS = 64;
enum size_t MESSAGE_CAPACITY = 256;
enum size_t MAX_STRUCTURES = 64;
enum size_t MAX_KINDS = 32;
enum size_t MAX_LANDMARKS = 32;
enum size_t PATH_CAPACITY = 4096;
enum string PLUGIN_DIRECTORY = "lib";
enum size_t READ_CHUNK = 4096;

uint worldCount() {
    return cast(uint) registry().allNames().length + 1;
}

const(char)[] worldNameAt(uint index) {
    if (index == 0) {
        return "terrain";
    } else {
        return registry().allNames()[index - 1];
    }
}

version (WebAssembly) {
    import arbor = plugins.arbor.plugin;
    import babel = plugins.babel.plugin;
    import backrooms = plugins.backrooms.plugin;
    import caves = plugins.caves.plugin;
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
    import vaults = plugins.vaults.plugin;
    import base = plugins.base.plugin;
    import blocksMod = plugins.blocks.plugin;
    import boxMod = plugins.box.plugin;
    import buildingsMod = plugins.buildings.plugin;
    import connectorMod = plugins.connector.plugin;
    import horospheresMod = plugins.horospheres.plugin;
    import roomsMod = plugins.rooms.plugin;

    immutable Entry[22] WEB_ENTRIES = [&base.plugin, &blocksMod.plugin, &boxMod.plugin, &buildingsMod.plugin, &connectorMod.plugin, &horospheresMod.plugin, &roomsMod.plugin, &arbor.plugin, &babel.plugin, &backrooms.plugin, &caves.plugin, &city.plugin, &crown.plugin, &fixtures.plugin, &lattice.plugin, &library.plugin, &palace.plugin, &planet.plugin, &road.plugin, &tower.plugin, &trail.plugin, &vaults.plugin];
    immutable string[22] WEB_PLUGINS = ["base", "blocks", "box", "buildings", "connector", "horospheres", "rooms", "arbor", "babel", "backrooms", "caves", "city", "crown", "fixtures", "lattice", "library", "palace", "planet", "road", "tower", "trail", "vaults"];
} else version (OSX) {
    import core.sys.posix.dirent : DIR, closedir, dirent, opendir, readdir;
    import core.sys.posix.dlfcn : RTLD_NOW, dlerror, dlopen, dlsym;
    import core.sys.posix.stdlib : realpath;

    enum string LIBRARY_SUFFIX = ".dylib";

    extern (C) int _NSGetExecutablePath(char* buffer, uint* size) nothrow @nogc;

    size_t executablePath(ref char[PATH_CAPACITY] resolved) {
        char[PATH_CAPACITY] path = 0;
        uint size = cast(uint) path.length;
        int status = _NSGetExecutablePath(path.ptr, &size);
        if (status != 0) {
            return 0;
        } else {
            const(char)* found = realpath(path.ptr, resolved.ptr);
            if (found is null) {
                return 0;
            } else {
                return strlen(resolved.ptr);
            }
        }
    }
} else {
    import core.stdc.stdio : FILE, fclose, fopen, fread;
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
    uint[MAX_STRUCTURES] structureOwners;
    size_t count;
    string[MAX_KINDS] kindNames;
    RisingKind[MAX_KINDS] risingKinds;
    uint[MAX_KINDS] kindOwners;
    size_t kindCount;
    string[MAX_LANDMARKS] landmarkNames;
    Structure[MAX_LANDMARKS] landmarks;
    uint[MAX_LANDMARKS] landmarkOwners;
    size_t landmarkCount;
    Manifest[MAX_PLUGINS] manifests;
    const(char)[][MAX_PLUGINS] files;
    size_t pluginCount;
    ModOrder order;

    void enter(const(char)[] file) {
        assert(pluginCount < MAX_PLUGINS);
        manifests[pluginCount] = Manifest.init;
        files[pluginCount] = file;
        pluginCount += 1;
    }

    uint current() const {
        return cast(uint) pluginCount - 1;
    }

    void dropRefused() {
        size_t kept = 0;
        foreach (index; 0 .. count) {
            if (!order.isRefused(structureOwners[index])) {
                names[kept] = names[index];
                structures[kept] = structures[index];
                structureOwners[kept] = structureOwners[index];
                kept += 1;
            }
        }
        count = kept;
        kept = 0;
        foreach (index; 0 .. kindCount) {
            if (!order.isRefused(kindOwners[index])) {
                kindNames[kept] = kindNames[index];
                risingKinds[kept] = risingKinds[index];
                kindOwners[kept] = kindOwners[index];
                kept += 1;
            }
        }
        kindCount = kept;
        kept = 0;
        foreach (index; 0 .. landmarkCount) {
            if (!order.isRefused(landmarkOwners[index])) {
                landmarkNames[kept] = landmarkNames[index];
                landmarks[kept] = landmarks[index];
                landmarkOwners[kept] = landmarkOwners[index];
                kept += 1;
            }
        }
        landmarkCount = kept;
    }

    void settle(const(char)[] overrides) {
        order = orderMods(manifests[0 .. pluginCount]);
        loadContent(manifests[0 .. pluginCount], order, overrides);
        foreach (refusal; order.refused.slice()) {
            char[MESSAGE_CAPACITY] buffer;
            const(char)[] message = describe(manifests[0 .. pluginCount], refusal, buffer[]);
            const(char)[] file = files[refusal.mod];
            fprintf(stderr, "%.*s: %.*s\n", cast(int) file.length, file.ptr, cast(int) message.length, message.ptr);
        }
        dropRefused();
    }

    void sort() {
        sortByName(names[0 .. count], structures[0 .. count]);
        sortByName(kindNames[0 .. kindCount], risingKinds[0 .. kindCount]);
        sortByName(landmarkNames[0 .. landmarkCount], landmarks[0 .. landmarkCount]);
    }

    version (WebAssembly) {
        void gather() {
            Registry registry = Registry(&this, &add, &addKind, &addLandmark, &declare);
            foreach (index, entry; WEB_ENTRIES) {
                enter(WEB_PLUGINS[index]);
                entry(&registry);
            }
            settle(null);
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
                snprintf(directory.ptr + length, directory.length - length, "%s", USER_SETTINGS.ptr);
                Array!char overrides;
                readWhole(directory.ptr, overrides);
                snprintf(directory.ptr + length, directory.length - length, "%s", PLUGIN_DIRECTORY.ptr);
                gatherFrom(directory.ptr);
                settle(overrides.slice());
                sort();
            }
        }

        void readWhole(const(char)* path, ref Array!char into) {
            FILE* file = fopen(path, "rb");
            if (file !is null) {
                char[READ_CHUNK] chunk;
                size_t got = fread(chunk.ptr, 1, chunk.length, file);
                while (got > 0) {
                    into.appendAll(chunk[0 .. got]);
                    got = fread(chunk.ptr, 1, chunk.length, file);
                }
                fclose(file);
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
                    Registry registry = Registry(&this, &add, &addKind, &addLandmark, &declare);
                    enter(keptName(file));
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
        worlds.structureOwners[worlds.count] = worlds.current();
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
        worlds.kindOwners[worlds.kindCount] = worlds.current();
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
        worlds.landmarkOwners[worlds.landmarkCount] = worlds.current();
        worlds.landmarkCount += 1;
    }
}

void declare(const(Registry)* registry, const(Manifest)* manifest) {
    Worlds* worlds = cast(Worlds*) registry.host;
    worlds.manifests[worlds.current()] = *manifest;
}

const(char)[] keptName(const(char)[] file) {
    char* copy = cast(char*) malloc(file.length + 1);
    memcpy(copy, file.ptr, file.length);
    copy[file.length] = 0;
    return copy[0 .. file.length];
}

__gshared Worlds gathered;
__gshared Readiness gatheredState;

void gatherWorlds() {
    gathered.gather();
    gatheredState = Readiness.ready;
}

ref const(Worlds) registry() {
    assert(gatheredState == Readiness.ready);
    return gathered;
}

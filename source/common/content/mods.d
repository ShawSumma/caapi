module common.content.mods;

import base.array : Array;
import base.maybe : Maybe, MaybeIndex;
import base.stdio : printed;
import plugins.api.content : Dependency, Manifest, Need, Version;

enum Reason : ubyte {
    undeclared,
    duplicate,
    missing,
    tooOld,
    otherMajor,
    refusedDependency,
    cycle,
    unbound,
}

struct Refusal {
    uint mod;
    uint dependency;
    Reason reason;
}

struct ModOrder {
    Array!uint order;
    Array!Refusal refused;

    bool isRefused(uint mod) const {
        size_t index = 0;
        while (index < refused.length && refused.ptr[index].mod != mod) {
            index += 1;
        }
        return index < refused.length;
    }

    void release() {
        order.release();
        refused.release();
    }
}

bool isAtLeast(Version have, Version least) {
    if (have.minor != least.minor) {
        return have.minor > least.minor;
    } else {
        return have.patch >= least.patch;
    }
}

bool isNamedBefore(const(char)[] a, const(char)[] b) {
    size_t index = 0;
    while (index < a.length && index < b.length && a[index] == b[index]) {
        index += 1;
    }
    if (index == a.length || index == b.length) {
        return a.length < b.length;
    } else {
        return a[index] < b[index];
    }
}

MaybeIndex!uint providerOf(const(Manifest)[] manifests, ref const ModOrder order, const(char)[] name) {
    uint index = 0;
    while (index < manifests.length && !(manifests[index].name == name && !order.isRefused(index))) {
        index += 1;
    }
    if (index < manifests.length) {
        return MaybeIndex!uint.of(index);
    } else {
        return MaybeIndex!uint.init;
    }
}

MaybeIndex!uint installed(const(Manifest)[] manifests, const(char)[] name) {
    uint index = 0;
    while (index < manifests.length && manifests[index].name != name) {
        index += 1;
    }
    if (index < manifests.length) {
        return MaybeIndex!uint.of(index);
    } else {
        return MaybeIndex!uint.init;
    }
}

Maybe!Reason versionProblem(Version have, Version least) {
    if (have.major != least.major) {
        return Maybe!Reason.of(Reason.otherMajor);
    } else if (!isAtLeast(have, least)) {
        return Maybe!Reason.of(Reason.tooOld);
    } else {
        return Maybe!Reason.init;
    }
}

void refuseUndeclared(const(Manifest)[] manifests, ref ModOrder order) {
    foreach (index, ref manifest; manifests) {
        if (manifest.name.length == 0) {
            order.refused.append(Refusal(cast(uint) index, 0, Reason.undeclared));
        }
    }
}

void refuseDuplicates(const(Manifest)[] manifests, ref ModOrder order) {
    foreach (index, ref manifest; manifests) {
        uint earlier = 0;
        while (earlier < index && manifests[earlier].name != manifest.name) {
            earlier += 1;
        }
        if (earlier < index && !order.isRefused(cast(uint) index)) {
            order.refused.append(Refusal(cast(uint) index, earlier, Reason.duplicate));
        }
    }
}

void refuseUnmet(const(Manifest)[] manifests, ref ModOrder order) {
    foreach (index, ref manifest; manifests) {
        if (!order.isRefused(cast(uint) index)) {
            foreach (dependency, ref needed; manifest.dependencies) {
                MaybeIndex!uint provider = installed(manifests, needed.name);
                if (!provider.exists && needed.need == Need.required) {
                    order.refused.append(Refusal(cast(uint) index, cast(uint) dependency, Reason.missing));
                } else if (provider.exists && versionProblem(manifests[provider.value].current, needed.least).exists) {
                    order.refused.append(Refusal(cast(uint) index, cast(uint) dependency, versionProblem(manifests[provider.value].current, needed.least).value));
                }
            }
        }
    }
}

void refuseDependents(const(Manifest)[] manifests, ref ModOrder order) {
    size_t before = 0;
    while (before != order.refused.length) {
        before = order.refused.length;
        foreach (index; 0 .. cast(uint) manifests.length) {
            if (!order.isRefused(index)) {
                MaybeIndex!uint dependency = refusedDependencyOf(manifests, order, index);
                if (dependency.exists) {
                    order.refused.append(Refusal(index, dependency.value, Reason.refusedDependency));
                }
            }
        }
    }
}

MaybeIndex!uint refusedDependencyOf(const(Manifest)[] manifests, ref const ModOrder order, uint mod) {
    uint index = 0;
    while (index < manifests[mod].dependencies.length && !(manifests[mod].dependencies[index].need == Need.required && !providerOf(manifests, order, manifests[mod].dependencies[index].name).exists)) {
        index += 1;
    }
    if (index < manifests[mod].dependencies.length) {
        return MaybeIndex!uint.of(index);
    } else {
        return MaybeIndex!uint.init;
    }
}

bool isReady(const(Manifest)[] manifests, ref const ModOrder order, uint mod, const(uint)[] placed) {
    foreach (ref needed; manifests[mod].dependencies) {
        MaybeIndex!uint provider = providerOf(manifests, order, needed.name);
        if (provider.exists) {
            uint index = 0;
            while (index < placed.length && placed[index] != provider.value) {
                index += 1;
            }
            if (index == placed.length) {
                return false;
            }
        }
    }
    return true;
}

ModOrder orderMods(const(Manifest)[] manifests) {
    ModOrder order;
    refuseUndeclared(manifests, order);
    refuseDuplicates(manifests, order);
    refuseUnmet(manifests, order);
    refuseDependents(manifests, order);
    Array!uint waiting;
    foreach (index; 0 .. manifests.length) {
        if (!order.isRefused(cast(uint) index)) {
            waiting.append(cast(uint) index);
        }
    }
    MaybeIndex!uint next = nextReady(manifests, order, waiting.slice());
    while (next.exists) {
        uint mod = waiting.ptr[next.value];
        order.order.append(mod);
        foreach (later; next.value + 1 .. waiting.length) {
            waiting.ptr[later - 1] = waiting.ptr[later];
        }
        waiting.length -= 1;
        next = nextReady(manifests, order, waiting.slice());
    }
    foreach (mod; waiting.slice()) {
        order.refused.append(Refusal(mod, 0, Reason.cycle));
    }
    waiting.release();
    return order;
}

MaybeIndex!uint nextReady(const(Manifest)[] manifests, ref const ModOrder order, const(uint)[] waiting) {
    MaybeIndex!uint best;
    foreach (index, mod; waiting) {
        if (isReady(manifests, order, mod, order.order.slice()) && (!best.exists || isNamedBefore(manifests[mod].name, manifests[waiting[best.value]].name))) {
            best = MaybeIndex!uint.of(cast(uint) index);
        }
    }
    return best;
}

const(char)[] describe(const(Manifest)[] manifests, Refusal refusal, char[] buffer) {
    const(Manifest)* mod = &manifests[refusal.mod];
    int modLength = cast(int) mod.name.length;
    final switch (refusal.reason) {
        case Reason.undeclared:
            return printed(buffer, "the plugin declares no manifest, so it is left out");
        case Reason.duplicate:
            return printed(buffer, "the mod '%.*s' is loaded twice; the second copy is left out", modLength, mod.name.ptr);
        case Reason.cycle:
            return printed(buffer, "the mod '%.*s' depends on itself through other mods, so it is left out", modLength, mod.name.ptr);
        case Reason.unbound:
            return printed(buffer, "the mod '%.*s' could not read the content it needs, so it is left out", modLength, mod.name.ptr);
        case Reason.missing:
        case Reason.tooOld:
        case Reason.otherMajor:
        case Reason.refusedDependency:
            return describeDependency(mod, refusal, buffer);
    }
}

const(char)[] describeDependency(const(Manifest)* mod, Refusal refusal, char[] buffer) {
    const(Dependency)* needed = &mod.dependencies[refusal.dependency];
    int modLength = cast(int) mod.name.length;
    int nameLength = cast(int) needed.name.length;
    if (refusal.reason == Reason.missing) {
        return printed(buffer, "the mod '%.*s' needs '%.*s', which is not installed", modLength, mod.name.ptr, nameLength, needed.name.ptr);
    } else if (refusal.reason == Reason.tooOld) {
        return printed(buffer, "the mod '%.*s' needs '%.*s' %u.%u.%u or newer", modLength, mod.name.ptr, nameLength, needed.name.ptr, needed.least.major, needed.least.minor, needed.least.patch);
    } else if (refusal.reason == Reason.otherMajor) {
        return printed(buffer, "the mod '%.*s' needs '%.*s' %u.x, and another major version is installed", modLength, mod.name.ptr, nameLength, needed.name.ptr, needed.least.major);
    } else {
        return printed(buffer, "the mod '%.*s' is left out because '%.*s' was", modLength, mod.name.ptr, nameLength, needed.name.ptr);
    }
}

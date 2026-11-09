module unit.mods;

import common.content.mods : ModOrder, Reason, orderMods;
import plugins.api.content : Dependency, Manifest, Need, Version;

immutable Dependency[1] ON_BASE = [Dependency("base", Version(1, 0, 0), Need.required)];
immutable Dependency[1] ON_NEWER_BASE = [Dependency("base", Version(1, 3, 0), Need.required)];
immutable Dependency[1] ON_SPACE = [Dependency("space", Version(1, 0, 0), Need.required)];
immutable Dependency[1] ON_GONE = [Dependency("gone", Version(1, 0, 0), Need.required)];
immutable Dependency[1] ON_GONE_MAYBE = [Dependency("gone", Version(1, 0, 0), Need.optional)];
immutable Dependency[1] ON_LOOP_B = [Dependency("loop-b", Version(1, 0, 0), Need.required)];
immutable Dependency[1] ON_LOOP_A = [Dependency("loop-a", Version(1, 0, 0), Need.required)];
immutable Dependency[1] ON_BROKEN = [Dependency("broken", Version(1, 0, 0), Need.required)];

Reason reasonOf(ref const ModOrder order, uint mod) {
    uint index = 0;
    while (order.refused.ptr[index].mod != mod) {
        index += 1;
    }
    return order.refused.ptr[index].reason;
}

unittest {
    Manifest[11] manifests = [
        Manifest("space", Version(1, 0, 0), ON_BASE[]),
        Manifest("base", Version(1, 2, 0), null),
        Manifest("extra", Version(1, 0, 0), ON_SPACE[]),
        Manifest("broken", Version(1, 0, 0), ON_GONE[]),
        Manifest("relying", Version(1, 0, 0), ON_BROKEN[]),
        Manifest("newer", Version(1, 0, 0), ON_NEWER_BASE[]),
        Manifest("loop-a", Version(1, 0, 0), ON_LOOP_B[]),
        Manifest("loop-b", Version(1, 0, 0), ON_LOOP_A[]),
        Manifest("base", Version(1, 2, 0), null),
        Manifest("lenient", Version(1, 0, 0), ON_GONE_MAYBE[]),
        Manifest.init,
    ];
    ModOrder order = orderMods(manifests[]);
    assert(order.order.length == 4);
    assert(order.order.ptr[0] == 1 && order.order.ptr[1] == 9 && order.order.ptr[2] == 0 && order.order.ptr[3] == 2);
    assert(reasonOf(order, 3) == Reason.missing);
    assert(reasonOf(order, 4) == Reason.refusedDependency);
    assert(reasonOf(order, 5) == Reason.tooOld);
    assert(reasonOf(order, 6) == Reason.cycle && reasonOf(order, 7) == Reason.cycle);
    assert(reasonOf(order, 8) == Reason.duplicate);
    assert(reasonOf(order, 10) == Reason.undeclared);
    order.release();
}

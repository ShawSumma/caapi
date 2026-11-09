module plugins.horospheres.plugin;

import plugins.api.api : Registry, entryOf;
import plugins.api.content : FIRST_VERSION, Manifest, ON_BASE;

immutable Manifest MANIFEST = Manifest("horospheres", FIRST_VERSION, ON_BASE[], null, null, null, null, import("plugins/horospheres/horospheres.decl"), import("plugins/horospheres/horospheres.content"));

pragma(mangle, entryOf!__MODULE__) void plugin(const(Registry)* registry) {
    registry.declare(registry, &MANIFEST);
}

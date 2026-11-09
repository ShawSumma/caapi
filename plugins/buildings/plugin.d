module plugins.buildings.plugin;

import plugins.api.api : Registry, entryOf;
import plugins.api.content : FIRST_VERSION, Manifest, ON_BASE;

immutable Manifest MANIFEST = Manifest("buildings", FIRST_VERSION, ON_BASE[], null, null, null, null, import("plugins/buildings/buildings.decl"), import("plugins/buildings/buildings.content"));

pragma(mangle, entryOf!__MODULE__) void plugin(const(Registry)* registry) {
    registry.declare(registry, &MANIFEST);
}

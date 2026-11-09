module plugins.box.plugin;

import plugins.api.api : Registry, entryOf;
import plugins.api.content : FIRST_VERSION, Manifest, ON_BASE;

immutable Manifest MANIFEST = Manifest("box", FIRST_VERSION, ON_BASE[], null, null, null, null, import("plugins/box/box.decl"), import("plugins/box/box.content"));

pragma(mangle, entryOf!__MODULE__) void plugin(const(Registry)* registry) {
    registry.declare(registry, &MANIFEST);
}

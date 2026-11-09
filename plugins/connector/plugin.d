module plugins.connector.plugin;

import plugins.api.api : Registry, entryOf;
import plugins.api.content : FIRST_VERSION, Manifest, ON_BASE;

immutable Manifest MANIFEST = Manifest("connector", FIRST_VERSION, ON_BASE[], null, null, null, null, import("plugins/connector/connector.decl"), import("plugins/connector/connector.content"));

pragma(mangle, entryOf!__MODULE__) void plugin(const(Registry)* registry) {
    registry.declare(registry, &MANIFEST);
}

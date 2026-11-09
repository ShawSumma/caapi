module plugins.rooms.plugin;

import plugins.api.api : Registry, entryOf;
import plugins.api.content : BASE, Dependency, FIRST_VERSION, Manifest, dependencyOn;

immutable Dependency[2] NEEDS = [dependencyOn(BASE), dependencyOn("connector")];
immutable Manifest MANIFEST = Manifest("rooms", FIRST_VERSION, NEEDS[], null, null, null, import("plugins/rooms/settings.conf"), import("plugins/rooms/rooms.decl"), import("plugins/rooms/rooms.content"));

pragma(mangle, entryOf!__MODULE__) void plugin(const(Registry)* registry) {
    registry.declare(registry, &MANIFEST);
}

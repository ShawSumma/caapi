module plugins.blocks.plugin;

import plugins.api.api : Registry, entryOf;
import plugins.api.content : BASE, Dependency, FIRST_VERSION, Manifest, dependencyOn;

immutable Dependency[3] NEEDS = [dependencyOn(BASE), dependencyOn("buildings"), dependencyOn("connector")];
immutable Manifest MANIFEST = Manifest("blocks", FIRST_VERSION, NEEDS[], null, null, null, import("plugins/blocks/settings.conf"), import("plugins/blocks/blocks.decl"), import("plugins/blocks/blocks.content"));

pragma(mangle, entryOf!__MODULE__) void plugin(const(Registry)* registry) {
    registry.declare(registry, &MANIFEST);
}

module plugins.base.plugin;

import plugins.api.api : Registry, entryOf;
import plugins.api.content : Manifest, Version;

enum Version BASE_VERSION = Version(1, 0, 0);

immutable Manifest MANIFEST = Manifest("base", BASE_VERSION, null, null, null, null, null, null, import("plugins/base/base.content"));

pragma(mangle, entryOf!__MODULE__) void plugin(const(Registry)* registry) {
    registry.declare(registry, &MANIFEST);
}

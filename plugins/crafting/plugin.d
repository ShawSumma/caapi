module plugins.crafting.plugin;

import common.content.content : graphOf;
import plugins.api.api : Registry;
import plugins.api.content : Content, FIRST_VERSION, Manifest;
import plugins.crafting.crafting : HAND_NAME, STATION_KIND, buildCrafting;

enum string NAME = "crafting";

void define(const(Content)* content) {
    content.node(content, STATION_KIND, HAND_NAME);
}

void resolve(const(Content)* content) {
    buildCrafting(graphOf(content));
}

immutable Manifest MANIFEST = Manifest(NAME, FIRST_VERSION, null, &define, &resolve, null, null, import("plugins/crafting/crafting.decl"), null);

void plugin(const(Registry)* registry) {
    registry.declare(registry, &MANIFEST);
}

module plugins.game.plugin;

import common.content.content : graphOf;
import common.content.graph : ContentGraph;
import plugins.api.api : Registry;
import plugins.api.content : BASE, Content, Dependency, FIRST_VERSION, Manifest, dependencyOn;
import crafting = plugins.crafting.plugin;
import plugins.game.mining : buildMining;
import plugins.game.roles : buildRoles, defineRoles;

enum string NAME = "game";

void resolve(const(Content)* content) {
    ContentGraph* graph = &graphOf(content);
    buildMining(*graph);
    buildRoles(*graph);
}

immutable Dependency[2] NEEDS = [dependencyOn(crafting.NAME), dependencyOn(BASE)];
immutable Manifest MANIFEST = Manifest(NAME, FIRST_VERSION, NEEDS[], &defineRoles, &resolve, null, import("plugins/game/settings.conf"), import("plugins/game/game.decl"), import("plugins/game/game.content"));

void plugin(const(Registry)* registry) {
    registry.declare(registry, &MANIFEST);
}

module plugins.game.roles;

import common.content.graph : ContentGraph;
import plugins.api.api : Material;
import plugins.api.content : Content;
import plugins.crafting.items : placedBlock;
import plugins.crafting.roles : ROLE_KIND, fillerOf;

enum string BEACON_ROLE = "game:beacon-role";

__gshared Material beaconBlock;

void defineRoles(const(Content)* content) {
    content.node(content, ROLE_KIND, BEACON_ROLE);
}

void buildRoles(ref ContentGraph graph) {
    beaconBlock = placedBlock(fillerOf(graph, BEACON_ROLE));
}

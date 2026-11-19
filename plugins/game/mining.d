module plugins.game.mining;

import base.array : Array;
import common.content.graph : ContentGraph;
import common.material : MATERIAL_KIND;
import plugins.api.content : ContentRef, Holder;
import plugins.crafting.crafting : UPGRADE_KIND;

__gshared Array!float breakSeconds;
__gshared Array!uint miningTiers;
__gshared Array!uint toolTiers;

void buildMining(ref ContentGraph graph) {
    foreach (node; 0 .. cast(uint) graph.nodes.length) {
        ContentRef at = ContentRef(node, Holder.node);
        if (graph.isKind(node, MATERIAL_KIND)) {
            breakSeconds.append(cast(float) graph.number(at, "break-seconds"));
            miningTiers.append(cast(uint) graph.number(at, "mining-tier"));
        } else if (graph.isKind(node, UPGRADE_KIND)) {
            toolTiers.append(cast(uint) graph.number(at, "mining-tier"));
        }
    }
}

module plugins.pharmacology.machines;

import common.content.graph : ContentGraph;
import plugins.api.api : Material;
import plugins.api.content : Content, ContentRef, Holder;
import plugins.crafting.crafting : IdSet, UPGRADE_KIND, upgrades;
import plugins.crafting.items : Item, placedBlock;
import plugins.crafting.roles : ROLE_KIND, fillerOf;

enum string COLLECTOR_ROLE = "pharmacology:collector-role";
enum string BENCH_ROLE = "pharmacology:bench-role";
enum string MUTAGEN_ROLE = "pharmacology:mutagen";
enum string CATALOG_ROLE = "pharmacology:catalog-role";

__gshared Material collectorBlock;
__gshared Material benchBlock;
__gshared Material catalogBlock;
__gshared Item mutagenItem;
__gshared IdSet assayUpgrades;

void defineMachines(const(Content)* content) {
    content.node(content, ROLE_KIND, COLLECTOR_ROLE);
    content.node(content, ROLE_KIND, BENCH_ROLE);
    content.node(content, ROLE_KIND, MUTAGEN_ROLE);
    content.node(content, ROLE_KIND, CATALOG_ROLE);
}

void buildMachines(ref ContentGraph graph) {
    collectorBlock = placedBlock(fillerOf(graph, COLLECTOR_ROLE));
    benchBlock = placedBlock(fillerOf(graph, BENCH_ROLE));
    catalogBlock = placedBlock(fillerOf(graph, CATALOG_ROLE));
    mutagenItem = fillerOf(graph, MUTAGEN_ROLE);
    assayUpgrades = IdSet.init;
    foreach (node; 0 .. cast(uint) graph.nodes.length) {
        if (graph.isKind(node, UPGRADE_KIND) && graph.number(ContentRef(node, Holder.node), "assays") != 0) {
            assayUpgrades.set(graph.ordinalOf(node));
        }
    }
}

bool grantsAssay(IdSet owned) {
    uint index = 0;
    while (index < upgrades().length && !(owned.has(index) && assayUpgrades.has(index))) {
        index += 1;
    }
    return index < upgrades().length;
}

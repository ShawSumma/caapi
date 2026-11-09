module common.content.load;

import common.biology.breeding : buildHabits, declareBreeding;
import common.biology.organism : buildOrganism, declareOrganism;
import common.content.content : contentGraph, defineEngine, defineMods, reportProblems, resolveMods;
import common.content.graph : ENGINE_OWNER;
import common.content.mods : ModOrder;
import common.content.roles : buildRoles, declareRoles, defineRoles;
import common.crafting : buildCrafting, declareCrafting;
import common.material : buildMaterials, declareMaterials;
import common.perception : buildPerception, declarePerception;
import common.worldgen.palette : buildPalette, declarePalette;
import plugins.api.content : Manifest;

void loadContent(const(Manifest)[] manifests, ref ModOrder order, const(char)[] overrides) {
    defineEngine();
    defineRoles(contentGraph);
    declareMaterials(contentGraph);
    declareCrafting(contentGraph);
    declarePalette(contentGraph);
    declareRoles(contentGraph);
    declareBreeding(contentGraph);
    declarePerception(contentGraph);
    declareOrganism(contentGraph);
    defineMods(manifests, order.order.slice(), overrides);
    contentGraph.freeze();
    buildMaterials(contentGraph);
    buildPerception(contentGraph);
    buildOrganism(contentGraph);
    buildCrafting(contentGraph);
    buildRoles(contentGraph);
    buildPalette(contentGraph, contentGraph.intern(ENGINE_OWNER));
    buildHabits(contentGraph);
    resolveMods(manifests, order);
    reportProblems();
}

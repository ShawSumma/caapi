module common.content.load;

import common.content.content : contentGraph, defineEngine, defineMods, reportProblems, resolveMods;
import common.content.graph : ENGINE_OWNER;
import common.content.mods : ModOrder;
import common.material : buildMaterials, declareMaterials;
import common.perception : buildPerception, declarePerception;
import common.worldgen.palette : NamedForm, buildPalette, declarePalette;
import plugins.api.content : Manifest;

void loadContent(const(Manifest)[] manifests, ref ModOrder order, const(char)[] overrides, const(NamedForm)[] forms) {
    defineEngine();
    declareMaterials(contentGraph);
    declarePalette(contentGraph);
    declarePerception(contentGraph);
    defineMods(manifests, order.order.slice(), overrides);
    contentGraph.freeze();
    buildMaterials(contentGraph);
    buildPerception(contentGraph);
    buildPalette(contentGraph, contentGraph.intern(ENGINE_OWNER), forms);
    resolveMods(manifests, order);
    reportProblems();
}

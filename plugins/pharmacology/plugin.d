module plugins.pharmacology.plugin;

import common.content.content : graphOf;
import common.content.graph : ContentGraph;
import plugins.api.api : Registry;
import plugins.api.content : Content, Dependency, FIRST_VERSION, Manifest, dependencyOn;
import plugins.game.bindings : addAction;
import plugins.game.game : extend;
import plugins.game.hud : displays;
import game = plugins.game.plugin;
import plugins.game.save : sections;
import plugins.game.screens : Sheet, addMachineScreen, extraSheets;
import plugins.pharmacology.breeding : buildHabits;
import plugins.pharmacology.drives : buildDrives;
import plugins.pharmacology.machines : buildMachines, defineMachines;
import plugins.pharmacology.organism : buildOrganism;
import plugins.pharmacology.panels : BODY_SHEET, CHEMISTRY_SHEET, DISPLAY, buildBench, buildBody, buildCatalog, buildChemistry, buildCollector;
import plugins.pharmacology.player : DOSE, EAT, EXTENSION, benchScreen, catalogScreen, collectorScreen, guest;
import plugins.pharmacology.saved : SECTION;
import plugins.pharmacology.synthesis : buildRoutes, buildSyntheses;

enum string NAME = "pharmacology";

void resolve(const(Content)* content) {
    ContentGraph* graph = &graphOf(content);
    buildOrganism(*graph);
    buildHabits(*graph);
    buildDrives(*graph);
    buildSyntheses(*graph);
    buildRoutes(*graph);
    buildMachines(*graph);
}

immutable Dependency[1] NEEDS = [dependencyOn(game.NAME)];
immutable Manifest MANIFEST = Manifest(NAME, FIRST_VERSION, NEEDS[], &defineMachines, &resolve, null, null, import("plugins/pharmacology/pharmacology.decl"), import("plugins/pharmacology/pharmacology.content"));

void plugin(const(Registry)* registry) {
    registry.declare(registry, &MANIFEST);
    guest = extend(EXTENSION);
    displays.append(DISPLAY);
    extraSheets.append(Sheet(BODY_SHEET, &buildBody));
    extraSheets.append(Sheet(CHEMISTRY_SHEET, &buildChemistry));
    benchScreen = addMachineScreen(&buildBench);
    collectorScreen = addMachineScreen(&buildCollector);
    catalogScreen = addMachineScreen(&buildCatalog);
    sections.append(SECTION);
    addAction(EAT);
    addAction(DOSE);
}

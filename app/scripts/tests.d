module app.scripts.tests;

import core.math : sqrt;
import core.stdc.math : acos, atan2, ceil, exp, fabs, fmod, roundf, sin;
import app.caves : CaveCount, UPPER_CAVES, countCaves;
import app.script : NamedScript, ONE_SECOND, Script, StepHook, degrees, extractOf, insightNamed, materialNamed, named, recipeNamed, stationNamed, synthesisNamed, upgradeNamed;
import app.scripts.claims : Measure, Topic, claim, link;
import climb = app.scripts.climb;
import walk = app.scripts.walk : Across, ClimbGoal, Motion;
import base.array : Array;
import base.flags : Readiness;
import base.maybe : Maybe, MaybeIndex;
import base.names : textFor;
import base.numbers : RADIANS_PER_DEGREE, higherOf, lowerOf;
import base.units : AngularSpeed, Length, Ratio, Time;
import base.vector3 : Vec3, ZERO_VECTOR, dot, magnitude, minus, rejectAlong;
import client.camera : CAMERA_FORWARD;
import client.plugins : sceneCount, sceneNameAt, worldCount;
import client.structures : StructureProblem;
import client.tiles : Census, FootprintCount, footprintCensus, footprintTotal;
import client.world : Placement;
import common.character.controller : MovementMode;
import common.character.features : CellRange, LocalFrame, visitCells;
import common.content.content : hooks;
import common.graph : Graph, NodeId;
import common.material : has, nameHashOf;
import common.node : ChunkId, ChunkSlot, ChunkState, cellIndex;
import common.perception : Perception, REVEAL_ON_LEVEL, effectiveFor, levelOf, senseNamed;
import common.position : Position;
import common.settings : CharacterConfig;
import common.worldgen.generation : Worldgen;
import common.worldgen.horospheres : CornerKey, Horosphere, HorosphereId, HorosphereStage, Horospheres, ROOT, edgeOf, ensureGravityAt, ensurePlaneHeight, ensureUndersideAt, isBelowAbyss;
import common.worldgen.lineage : LINEAGE_SEEDS, Lineage;
import common.worldgen.structure : ColumnSpot, SiteFrame, columnPoint, edgeCells, edgeSitesOf, ensureSiteHash, forwarded, moveToLevel, nodeToNode, rootSite, sitePlacement, turnSite;
import geometry.cube : Cell;
import geometry.honeycomb : CORNER_COUNT, Corner, Face;
import geometry.lorentz : Point, Shift = Motion, Vec4;
import plugins.api.api : Material, SitePart, Turn, tagNamed;
import plugins.api.content : Happening;
import plugins.crafting.crafting : Insight, Recipe, Station, Upgrade, insights, recipes, stations;
import plugins.crafting.inventory : HOTBAR_SLOTS, Inventory, SLOT_COUNT, STACK_LIMIT, Sorting, Stack, isSameKind;
import plugins.crafting.items : Item, itemOf;
import plugins.game.bindings : ACTIONS, Action, Rules;
import plugins.game.config : ClientConfig;
import plugins.game.game : AimKind, BeaconSighting, ChunkSupply, Click, CraftKind, FEW_CRAFTS, FrameInput, Game, Key, KeyStroke, Mineable, Note, NoteKind, RouteWaypoint, Screen, SolidProbe, UiAction, UiKind, UnloadedCount;
import plugins.game.hud : FrameMeter, Growth, Hud;
import plugins.game.input : Controls, ESCAPE_KEY, Request;
import plugins.game.play : BROKE, Play;
import plugins.game.restart : placeStructure, restartGame, worldgenOf;
import plugins.game.save : SaveData, Writer, applyEdits, applyState, readGame, writeGame;
import plugins.game.screens : CATALOG_SHEET, INVENTORY_SHEET, sheetNamed;
import plugins.pharmacology.air : AirMix, GAS_COUNT, airOf;
import plugins.pharmacology.breeding : expressionIn, productOf;
import plugins.pharmacology.catalog : CALL_DIGITS, callNumber;
import plugins.pharmacology.drives : felt;
import plugins.pharmacology.kinetics : Body, Route;
import plugins.pharmacology.molecule : Fragment, GRID_CELLS, Molecule, ROTATION_COUNT, conjugated, rotated, withFragment;
import plugins.pharmacology.organism : Dose, starterDoses;
import plugins.pharmacology.panels : BODY_SHEET, CHEMISTRY_SHEET, actBreathe, actCross, actPress, actSplice, actSynthesize, actTakeDose, acting;
import plugins.pharmacology.player : COLLECTION_RATE, EAT, GROWN_SECONDS, MOST_EXTRA_YIELD, PLANT_DOSE, Ripeness, SEALED_GAIN, Sight, Told, benchScreen, breatheMachine, catalogScreen, choose, chooseCompound, chosen, chosenCompound, collectorScreen, compoundIndexOf, compounds, crossChosen, hasAssay, isKnownProduct, keepCompound, mutationOddsAt, organism, pharma, pressLiving, sealedGainAt, spliceChosen, synthesize, takeDose;
import plugins.pharmacology.pocket : TRANSDUCER_COUNT;
import plugins.pharmacology.signaling : REST_TICK, SIGNAL_COUNT, Signaling;
import plugins.pharmacology.synthesis : Reaction, Synthesis, doseRoutes, syntheses, synthesized;
import plugins.pharmacology.wild : cellGenes, speciesGenes;

immutable NamedScript[] TESTS = [
    NamedScript("api", &api),
    NamedScript("demo/growth", &demoGrowth),
    NamedScript("demo/holonomy", &demoHolonomy),
    NamedScript("demo/throw", &demoThrow),
    NamedScript("flat/corner", &flatCorner),
    NamedScript("flat/curve", &flatCurve),
    NamedScript("flat/hole", &flatHole),
    NamedScript("flat/items", &flatItems),
    NamedScript("flat/mining", &flatMining),
    NamedScript("flat/crafting", &flatCrafting),
    NamedScript("flat/queue", &flatQueue),
    NamedScript("flat/refund", &flatRefund),
    NamedScript("flat/several", &flatSeveral),
    NamedScript("flat/tiers", &flatTiers),
    NamedScript("flat/jump", &flatJump),
    NamedScript("flat/place", &flatPlace),
    NamedScript("flat/stair", &flatStair),
    NamedScript("flat/stepover", &flatStepover),
    NamedScript("flat/timestep", &flatTimestep),
    NamedScript("flat/walk", &flatWalk),
    NamedScript("flat/wall", &flatWall),
    NamedScript("beacon/home", &beaconHome),
    NamedScript("biology/dosed-climb", &biologyDosedClimb),
    NamedScript("biology/sober", &biologySober),
    NamedScript("biology/tide", &biologyTide),
    NamedScript("biology/rebound", &biologyRebound),
    NamedScript("biology/ember", &biologyEmber),
    NamedScript("biology/wild-tide", &biologyWildTide),
    NamedScript("biology/wild-mist", &biologyWildMist),
    NamedScript("biology/wild-ember", &biologyWildEmber),
    NamedScript("gene/breed-splice", &geneBreedSplice),
    NamedScript("gene/grow", &geneGrow),
    NamedScript("gene/harvest", &geneHarvest),
    NamedScript("gene/kept", &geneKept),
    NamedScript("gene/ripening", &geneRipening),
    NamedScript("gene/wild", &geneWild),
    NamedScript("gene/unsorted", &geneUnsorted),
    NamedScript("flat/learning", &flatLearning),
    NamedScript("gene/synthesis", &geneSynthesis),
    NamedScript("gene/compounds", &geneCompounds),
    NamedScript("hidden/climb", &hiddenClimb),
    NamedScript("hidden/reveal-inside", &hiddenRevealInside),
    NamedScript("hidden/unrevealed", &hiddenUnrevealed),
    NamedScript("live/drift", &liveDrift),
    NamedScript("live/edit-kept", &liveEditKept),
    NamedScript("live/far", &liveFar),
    NamedScript("live/fly", &liveFly),
    NamedScript("save/round-trip", &saveRoundTrip),
    NamedScript("save/queue", &saveQueue),
    NamedScript("save/lost-recipe", &saveLostRecipe),
    NamedScript("perception/body", &perceptionBody),
    NamedScript("plant/collector", &plantCollector),
    NamedScript("plant/eat", &plantEat),
    NamedScript("slope/across", &slopeAcross),
    NamedScript("slope/downhill", &slopeDownhill),
    NamedScript("slope/hopping", &slopeHopping),
    NamedScript("slope/steep", &slopeSteep),
    NamedScript("slope/turning", &slopeTurning),
    NamedScript("slope/uphill", &slopeUphill),
    NamedScript("slope/wall", &slopeWall),
    NamedScript("ui/keys", &uiKeys),
    NamedScript("ui/screen-holds", &uiScreenHolds),
    NamedScript("ui/catalog", &uiCatalog),
    NamedScript("ui/scenes", &uiScenes),
    NamedScript("structure/arbor", &climbing!("arbor", 2.5f, SpawnCheck.checked)),
    NamedScript("structure/arborendless", &structureArborEndless),
    NamedScript("structure/arborbench", &structureArborBench),
    NamedScript("structure/arch", &climbing!("crown", 1.8f, SpawnCheck.skipped)),
    NamedScript("structure/axis", &structureAxis),
    NamedScript("structure/babel", &climbing!("babel", 1.2f, SpawnCheck.checked)),
    NamedScript("structure/backrooms", &structureBackrooms),
    NamedScript("structure/backroomsbasement", &climbing!("basement", 0.2f, SpawnCheck.skipped)),
    NamedScript("structure/backroomsstairs", &climbing!("backroomsstairs", 0.25f, SpawnCheck.skipped)),
    NamedScript("structure/backroomsworld", &structureBackroomsWorld),
    NamedScript("structure/chain", &structureChain),
    NamedScript("structure/city", &structureCity),
    NamedScript("structure/crown", &structureCrown),
    NamedScript("structure/endless", &structureEndless),
    NamedScript("structure/hamlet", &structureHamlet),
    NamedScript("structure/inlay", &structureInlay),
    NamedScript("structure/portrule", &structurePortRule),
    NamedScript("structure/portroll", &structurePortRoll),
    NamedScript("structure/portfaces", &structurePortFaces),
    NamedScript("structure/cityport", &structureCityPort),
    NamedScript("structure/overreach", &structureOverreach),
    NamedScript("structure/twoedges", &structureTwoEdges),
    NamedScript("structure/cavenetwork", &structureCaveNetwork),
    NamedScript("structure/lattice", &structureLattice),
    NamedScript("structure/library", &structureLibrary),
    NamedScript("structure/libraryendless", &structureLibraryEndless),
    NamedScript("structure/librarylive", &structureLibraryLive),
    NamedScript("structure/libraryflight", &structureLibraryFlight),
    NamedScript("structure/librarynohole", &structureLibraryNoHole),
    NamedScript("structure/librarypress", &structureLibraryPress),
    NamedScript("structure/librarybench", &structureLibraryBench),
    NamedScript("structure/librarystaff", &structureLibraryStaff),
    NamedScript("structure/palace", &climbing!("palace", 0.35f, SpawnCheck.checked)),
    NamedScript("structure/risen", &risen!("risencity", 1.5f, "base:concrete", "the risen city's paved lot")),
    NamedScript("structure/road", &structureRoad),
    NamedScript("structure/spiral", &risen!("spiralcity", 1.5f, "base:concrete", "the spiral's landing")),
    NamedScript("structure/drift", &risen!("driftcity", 1.5f, "base:concrete", "the drift's landing")),
    NamedScript("structure/lantern", &risen!("lanterncity", 1.5f, "base:concrete", "the lantern's landing")),
    NamedScript("structure/paired", &risen!("pairedcity", 1.5f, "base:concrete", "the paired connector's landing")),
    NamedScript("structure/stacked", &risen!("stacked", 1.5f, "base:concrete", "the connector's landing")),
    NamedScript("structure/stackedrooms", &risen!("stackedrooms", 1.5f, "base:concrete", "the connector's landing")),
    NamedScript("structure/stairs", &climbing!("tower", 2.5f, SpawnCheck.skipped)),
    NamedScript("structure/grove", &climbing!("grove", 0.6f, SpawnCheck.skipped)),
    NamedScript("structure/planetgrove", &structurePlanetGrove),
    NamedScript("structure/tower", &structureTower),
    NamedScript("structure/trail", &structureTrail),
    NamedScript("structure/tripcity", &roundTrip!("tripcity")),
    NamedScript("structure/tripwild", &roundTrip!("tripwild")),
    NamedScript("structure/triprooms", &roundTrip!("triprooms")),
    NamedScript("structure/tripstacked", &roundTrip!("tripstacked")),
    NamedScript("structure/tripcities", &roundTrip!("tripcities")),
    NamedScript("structure/tripwildwild", &roundTrip!("tripwildwild")),
    NamedScript("structure/tripspiral", &roundTrip!("tripspiral")),
    NamedScript("structure/tripdrift", &roundTrip!("tripdrift")),
    NamedScript("structure/triplantern", &roundTrip!("triplantern")),
    NamedScript("structure/trippaired", &roundTrip!("trippaired")),
    NamedScript("structure/trippairedwild", &roundTrip!("trippairedwild")),
    NamedScript("structure/treetrunk", &structureTreetrunk),
    NamedScript("structure/wild", &risen!("risenwild", 2.0f, "base:concrete", "the connector's landing")),
    NamedScript("structure/caves", &structureCaves),
    NamedScript("structure/sinkhole", &structureSinkhole),
    NamedScript("structure/well", &structureWell),
    NamedScript("structure/vaultwell", &structureVaultWell),
    NamedScript("structure/citycaves", &caveStack!("city", 2.85f, "base:water", "base:silty-loam", "Under a city the caves three edges down are a cistern: water lies on the floor of the chamber a well passes there, and none of the loam an open cave has at that depth.")),
    NamedScript("structure/backroomscaves", &caveStack!("backrooms", 3.85f, "base:lava", "base:glass", "Under the backrooms the caves four edges down are a boiler room: lava lies in the chamber a well passes there, and none of the glass beams an open cave has at that depth.")),
    NamedScript("structure/vaultscaves", &caveStack!("vaults", 2.85f, "base:red-sandstone", "base:silty-loam", "Under the vaults the caves three edges down are a reliquary: red sandstone is laid in the floor of the chamber a well passes there, and none of the loam an open cave has at that depth.")),
    NamedScript("structure/wellstair", &structureWellStair),
    NamedScript("structure/wellflight", &wellFlight!("backrooms", "base:concrete")),
    NamedScript("structure/vaultwellflight", &wellFlight!("vaults", "base:marble")),
    NamedScript("structure/citywellflight", &wellFlight!("city", "base:steel")),
    NamedScript("structure/wildwellflight", &wildWellFlight!("base:spruce-wood")),    NamedScript("structure/latticeflight", &structureLatticeFlight),
    NamedScript("structure/voidflight", &structureVoidFlight),
    NamedScript("structure/void", &structureVoid),
    NamedScript("structure/maze", &structureMaze),
    NamedScript("structure/window", &structureWindow),
    NamedScript("structure/shield", &structureShield),
    NamedScript("structure/waydown", &structureWayDown),
    NamedScript("structure/gallery", &structureGallery),
    NamedScript("structure/forcedroute", &structureForcedRoute),
    NamedScript("structure/vertexmarks", &structureVertexMarks),
    NamedScript("structure/footprint", &structureFootprint!("")),
    NamedScript("structure/footprintcity", &structureFootprint!("city")),
    NamedScript("structure/footprintbackrooms", &structureFootprint!("backrooms")),
    NamedScript("structure/footprintlibrary", &structureFootprint!("library")),
    NamedScript("structure/footprintvaults", &structureFootprint!("vaults")),
    NamedScript("structure/footprintcaves", &structureFootprint!("caves")),
    NamedScript("structure/footprintlattice", &structureFootprint!("lattice")),
    NamedScript("structure/footprintterraces", &structureFootprint!("terraces")),
    NamedScript("structure/footprintgarden", &structureFootprint!("garden")),
    NamedScript("structure/footprinttrellis", &structureFootprint!("trellis")),    NamedScript("structure/vaults", &climbing!("vaults", 0.35f, SpawnCheck.checked)),
    NamedScript("structure/hiddenvaults", &structureHiddenVaults),
    NamedScript("structure/citytunnel", &structureCityTunnel),
    NamedScript("structure/subwaystation", &structureSubwayStation),
    NamedScript("structure/subwaymezzanine", &structureSubwayMezzanine),
    NamedScript("structure/subwaywalk", &structureSubwayWalk),
    NamedScript("structure/subwaytransfer", &structureSubwayTransfer),
    NamedScript("structure/shallowplatform", &structureShallowPlatform),
    NamedScript("structure/subwaywell", &structureSubwayWell),
    NamedScript("structure/subwaythrough", &structureSubwayThrough),
    NamedScript("structure/subwayunder", &structureSubwayUnder),
    NamedScript("structure/subwayabandoned", &structureSubwayAbandoned),
    NamedScript("structure/streets", &structureStreets),
    NamedScript("structure/watchtower", &structureWatchtower),
    NamedScript("structure/sealedair", &structureSealedAir),
    NamedScript("structure/librarycatalog", &structureLibraryCatalog),
    NamedScript("structure/libraryrumor", &rumorIn!("library", "A pamphlet in the library holds a rumor: reading it puts one new entry in the journal, reading it again adds none, and it opens no screen.")),
    NamedScript("structure/babelrumor", &rumorIn!("babel", "A pamphlet lies in Babel and holds a rumor: reading it puts one new entry in the journal, reading it again adds none, and it opens no screen.")),
    NamedScript("gene/catalog", &catalogShelf),
    NamedScript("structure/hiddenvaultsclimb", &structureHiddenVaultsClimb),
    NamedScript("content/hooks", &contentHooks),
    NamedScript("lost/thread-off", &lostThreadOff),
    NamedScript("lost/thread", &lostThread),
    NamedScript("lost/thread-full", &lostThreadFull),
    NamedScript("falls/wake", &fallsWake),
    NamedScript("falls/loss", &fallsLoss),
    NamedScript("falls/creative", &fallsCreative),
    NamedScript("falls/unmarked", &fallsUnmarked),
    NamedScript("falls/gone", &fallsGone),
    NamedScript("falls/nowhere", &fallsNowhere),
    NamedScript("falls/fly", &fallsFly),
    NamedScript("falls/planet", &fallsPlanet),
];

enum string WAY_DOWN_WOOD = "base:spruce-wood";
enum int WAY_DOWN_DECK_LOW = -6;
enum int WAY_DOWN_DECK_HIGH = 5;
enum uint WAY_DOWN_LEAST_DECK = 72;
enum uint WAY_DOWN_MOST_SITES = 600;
enum float WAY_DOWN_DEEPEST_EDGES = 5;

uint deckCellsAt(ref Script world, SiteFrame up, int z) {
    world.game.generateWithin(walk.cellPosition(world, up, 0, 0, z), Length(walk.TREAD_REACH_CELLS * 2 * world.game.blockLength().value));
    uint found = 0;
    foreach (x; WAY_DOWN_DECK_LOW .. WAY_DOWN_DECK_HIGH + 1) {
        foreach (y; WAY_DOWN_DECK_LOW .. WAY_DOWN_DECK_HIGH + 1) {
            if (walk.isMaterial(walk.generatedAt(world, walk.cellPosition(world, up, x, y, z)), WAY_DOWN_WOOD)) {
                found += 1;
            }
        }
    }
    return found;
}

void structureWayDown(ref Script world) {
    world.terrain();
    Graph* graph = &world.game.world.graph;
    int cells = edgeCells(graph.layout.dimension);
    SiteFrame[walk.MOST_PORT_SITES] sites;
    sites[0] = rootSite(graph.anchorSlot);
    size_t count = 1;
    size_t next = 0;
    uint deck = 0;
    float crust = 0;
    while (deck < WAY_DOWN_LEAST_DECK && next < count && next < WAY_DOWN_MOST_SITES) {
        SiteFrame site = graph.view.moveToLevel(sites[next], 0);
        next += 1;
        crust = graph.view.ensureUndersideAt(ROOT, walk.ensureVertex(*graph, site)) / graph.view.edgeOf();
        if (crust < WAY_DOWN_DEEPEST_EDGES) {
            deck = deckCellsAt(world, graph.view.turnSite(site, Turn.pitchUp), -cast(int) ceil(crust) * cells);
        }
        if (count + 3 <= walk.MOST_PORT_SITES) {
            SiteFrame ahead = forwarded(site, 1);
            sites[count] = ahead;
            sites[count + 1] = graph.view.turnSite(ahead, Turn.left);
            sites[count + 2] = graph.view.turnSite(ahead, Turn.right);
            count += 3;
        }
    }
    world.claim(Topic.structures, "Under the default world a way down from the caves, a drain or a well, comes out where the rock ends: under one of the ground vertices nearest spawn, the first vertex past the rock's underside carries a deck of their wood.", deck >= WAY_DOWN_LEAST_DECK, Measure.of("ground vertices searched", next), Measure.of("deck cells of the wood found", deck), Measure.of("rock ends this many edges down there", crust));
}

enum ulong GALLERY_SALT = 0x47_414C_4C59;
enum double GALLERY_ODDS = 0.15;
enum ulong GALLERY_MIX = 0x2545F4914F6CDD1D;
enum uint GALLERY_FOLD = 31;
enum uint GALLERY_UNIT_SHIFT = 40;
enum double GALLERY_UNIT_STEPS = 1 << 24;
enum double GALLERY_LEAST_DEPTH = 1.95;
enum double GALLERY_ROCK_MARGIN = 0.5;
enum double GALLERY_GRADE = 0.5;
enum float GALLERY_SEARCH = 1.2f;

double galleryRoll(ulong hash) {
    ulong value = (hash ^ GALLERY_SALT) * GALLERY_MIX;
    value ^= value >> GALLERY_FOLD;
    value *= GALLERY_MIX;
    value ^= value >> GALLERY_FOLD;
    return (value >> GALLERY_UNIT_SHIFT) / GALLERY_UNIT_STEPS;
}

bool isGalleryEnd(ref Graph graph, Position at) {
    float edge = graph.view.edgeOf();
    double depth = -graph.view.ensurePlaneHeight(ROOT, at) / edge;
    double crust = graph.view.ensureUndersideAt(ROOT, at) / edge;
    return depth >= GALLERY_LEAST_DEPTH && depth <= crust - GALLERY_ROCK_MARGIN;
}

void structureGallery(ref Script world) {
    world.terrain();
    Maybe!Position deep = walk.ensureUnderGround(world, walk.Beneath.rock);
    world.check(deep.exists, "found no place under the default world's ground still in rock");
    if (!world.isFailed) {
        world.game.generateWithin(deep.value, Length(GALLERY_SEARCH));
        Graph* graph = &world.game.world.graph;
        float edge = graph.view.edgeOf();
        int cells = edgeCells(graph.layout.dimension);
        uint galleries = 0;
        uint hollow = 0;
        foreach (slot; 0 .. graph.slotCount) {
            if (graph.nodeAt(slot).hasState) {
                foreach (site; graph.view.edgeSitesOf(slot)) {
                    if (galleryRoll(graph.view.ensureSiteHash(site, SitePart.line)) < GALLERY_ODDS) {
                        Position near = walk.columnPosition(world, site, 0, 0, 0);
                        Position far = walk.columnPosition(world, site, 0, 0, cells);
                        float rise = graph.view.ensurePlaneHeight(ROOT, far) - graph.view.ensurePlaneHeight(ROOT, near);
                        if (fabs(rise) < GALLERY_GRADE * edge && isGalleryEnd(*graph, near) && isGalleryEnd(*graph, far)) {
                            Position middle = walk.cellPosition(world, site, 0, 0, cells / 2);
                            Maybe!Material held = walk.generatedAt(world, middle);
                            if (held.exists) {
                                galleries += 1;
                                if (held.value == Material.none) {
                                    hollow += 1;
                                }
                            }
                        }
                    }
                }
            }
        }
        world.claim(Topic.structures, "Under the default world a line of edges that rolls a gallery is a tunnel through the rock: on every such edge deep inside the rock near spawn, the cell at the middle of the edge is air.", galleries > 0 && hollow == galleries, Measure.of("gallery edges found", galleries), Measure.of("hollow at the middle", hollow));
    }
}

enum uint VERTEX_MARK_CELLS = 4;

size_t loadedCellsOf(ref Script world, Material wanted) {
    const(Graph)* graph = &world.game.world.graph;
    ubyte dimension = graph.layout.dimension;
    size_t count = 0;
    foreach (slot; 0 .. graph.slotCount) {
        foreach (corner; 0 .. CORNER_COUNT) {
            ChunkSlot chunk = ChunkSlot(slot, cast(Corner) corner);
            if (graph.chunks.at(chunk).state == ChunkState.populated) {
                foreach (cell; 0 .. dimension * dimension * dimension) {
                    if (graph.chunks.at(chunk).voxels.at(cell) == wanted) {
                        count += 1;
                    }
                }
            }
        }
    }
    return count;
}

void structureVertexMarks(ref Script world) {
    Material mark = materialNamed("base:limestone");
    world.plane(degrees(0));
    walk.spawn(world);
    size_t bare = loadedCellsOf(world, mark);
    world.structure("vertexmarks");
    walk.spawn(world);
    size_t marked = loadedCellsOf(world, mark);
    world.claim(Topic.structures, "A world's vertex tile runs at the ground's vertices: a rig whose vertex tile stands a four cell column of limestone on each leaves limestone near spawn in whole columns, where the bare ground has none.", bare == 0 && marked > 0 && marked % VERTEX_MARK_CELLS == 0, Measure.of("limestone cells on bare ground", bare), Measure.of("limestone cells under the rig", marked), Measure.of("columns", marked / VERTEX_MARK_CELLS));
}

void structureFootprint(string name)(ref Script world) {
    footprintCensus = Census.counting;
    footprintTotal = FootprintCount.init;
    if (name.length == 0) {
        world.terrain();
    } else {
        world.structure(name);
    }
    walk.spawn(world);
    FootprintCount count = footprintTotal;
    footprintCensus = Census.off;
    world.claim(Topic.structures, "Every brush a tile paints near where a world starts lies on a line through one of that tile's own vertices: an edge tile's two ends within the span of edges the brush covers, a face tile's five corners within eight edges beyond that span, a ground's foot tile its foot within the edges that ground rose.", count.brushes > 0 && count.strays == 0, Measure.of("world", name), Measure.of("brushes counted", count.brushes), Measure.of("brushes on no line through the tile's vertices", count.strays));
}

enum float FORCED_ROUTE_BELOW_EDGES = 0.5f;
enum float FORCED_ROUTE_SLACK_EDGES = 0.5f;
enum size_t LEAST_FORCED_STOPS = 3;

void structureForcedRoute(ref Script world) {
    world.terrain();
    Graph* graph = &world.game.world.graph;
    float edge = graph.view.edgeOf();
    Array!Position path;
    foreach (stop; graph.structures.blueprint.route.slice()) {
        Position at = walk.columnPosition(world, stop.site, stop.spot.x, stop.spot.y, stop.spot.z);
        if (graph.view.ensurePlaneHeight(ROOT, at) < -FORCED_ROUTE_BELOW_EDGES * edge) {
            path.append(at);
        }
    }
    world.check(path.length >= LEAST_FORCED_STOPS, "the default world's route has %zu stops under the ground, too few for a route down through its caves", path.length);
    if (!world.isFailed) {
        world.mode(MovementMode.noclip);
        world.game.placeAt(path.ptr[path.length - 2], Length(0));
        world.mode(MovementMode.walk);
        world.wait(walk.LANDING_SECONDS + walk.SETTLE_SECONDS);
        Position at = world.game.characterState.position;
        float depth = -graph.view.ensurePlaneHeight(ROOT, at);
        float underside = graph.view.ensureUndersideAt(ROOT, at);
        world.claim(Topic.structures, "Near spawn the default world lays a route from a sinkhole's chamber down through its cave tree to a drain: a body let go at the top of that drain's chute falls through it and stands where the rock ends, within half an edge of the underside.", world.isOnGround() && fabs(depth - underside) < FORCED_ROUTE_SLACK_EDGES * edge, Measure.of("stops under the ground", path.length), Measure.of("standing on", walk.nameOf(walk.lookBelow(world))), Measure.of("depth in edges", depth / edge), Measure.of("underside there in edges", underside / edge));
    }
    path.release();
}

uint placesOf(ref Script world, Position from, string material) {
    if (walk.nearestAround(world, from, materialNamed(material)).exists) {
        return 1;
    } else {
        return 0;
    }
}

void caveStack(string name, float edges, string own, string open, string law)(ref Script world) {
    world.structure(name);
    Maybe!Position port = walk.ensurePort(world);
    world.check(port.exists, "found no port among the vertices nearest the root of %s", name.ptr);
    if (!world.isFailed) {
        world.mode(MovementMode.noclip);
        world.game.placeAt(port.value, Length(-edges * world.game.world.graph.view.edgeOf()));
        Position chamber = world.game.characterState.position;
        uint found = placesOf(world, chamber, own);
        uint other = placesOf(world, chamber, open);
        world.claim(Topic.structures, law, found == 1 && other == 0, Measure.of("edges down the well", edges), Measure.of("its own material", own), Measure.of("found within reach", found), Measure.of("the open caves' material", open), Measure.of("found within reach of it", other));
    }
}

enum string WATCH_FIRE = "base:lava";
enum uint WATCH_RINGS = 8;

void structureWatchtower(ref Script world) {
    world.terrain();
    walk.spawn(world);
    Maybe!Position found = walk.ensureNearest(world, world.game.characterState.position, materialNamed(WATCH_FIRE), WATCH_RINGS);
    float above = 0;
    if (found.exists) {
        world.mode(MovementMode.noclip);
        world.game.placeAt(found.value, Length(0));
        above = world.altitude().value;
    }
    world.claim(Topic.structures, "Watchtowers stand on raised ground in the default world: a watch fire burns at the foot of one within a few hops of spawn, on the surface and not in a cave.", found.exists && above > 0, Measure.of("hops searched", WATCH_RINGS), Measure.of("fire this far above the ground plane", above));
}

enum float SEALED_DIVE = 2.6f;
enum float SEALED_REACH = 0.1f;

float sealedGainHere(ref Script world) {
    world.game.generateWithin(world.game.characterState.position, Length(SEALED_REACH));
    Graph* graph = &world.game.world.graph;
    return sealedGainAt(*graph, graph.slotOf(world.game.characterState.position.node).value).value;
}

void structureSealedAir(ref Script world) {
    world.structure("city");
    walk.spawn(world);
    float surface = sealedGainHere(world);
    world.mode(MovementMode.noclip);
    world.press(SEALED_DIVE / walk.NOCLIP_SPEED, Key.down);
    float sealed = sealedGainHere(world);
    world.claim(Topic.air, "Sealed means kept: under a built ground, below where its sealed caves begin, a collector gathers the air at the sealed gain, and on the street above it at none.", surface == 1 && sealed == SEALED_GAIN.value, Measure.of("gain on the street", surface), Measure.of("gain this far down", SEALED_DIVE), Measure.of("gain there", sealed), Measure.of("the sealed gain", SEALED_GAIN.value));
}

immutable ubyte[4] SHELF_FRAGMENTS = [1, 3, 5, 6];
immutable uint[4] SHELF_CELLS = [0, 5, 13, 21];

void catalogShelf(ref Script world) {
    Molecule shape = conjugated(Molecule.init);
    foreach (index, cell; SHELF_CELLS) {
        shape = shape.withFragment(cell, Fragment.of(SHELF_FRAGMENTS[index]));
    }
    char[CALL_DIGITS] call = callNumber(shape);
    uint same = 0;
    foreach (rotation; 0 .. ROTATION_COUNT) {
        if (callNumber(rotated(shape, rotation)) == call) {
            same += 1;
        }
    }
    world.claim(Topic.chemistry, "A compound's shelf in the catalog does not depend on how it is turned: all 24 turnings of a shape read the same call number.", same == ROTATION_COUNT, Measure.of("turnings with the same call number", same), Measure.of("turnings", ROTATION_COUNT));
}

enum uint CATALOG_RINGS = 12;
enum float CATALOG_FLOOR = 0.45f;
enum float CATALOG_LIFT = 0.06f;

void structureLibraryCatalog(ref Script world) {
    world.structure("library");
    walk.spawn(world);
    world.mode(MovementMode.noclip);
    world.press(CATALOG_FLOOR / walk.NOCLIP_SPEED, Key.down);
    Maybe!Position found = walk.ensureNearest(world, world.game.characterState.position, materialNamed("pharmacology:catalog"), CATALOG_RINGS);
    world.check(found.exists, "no catalog stands within %u hops of the library's start", CATALOG_RINGS);
    if (!world.isFailed) {
        world.mode(MovementMode.noclip);
        world.game.placeAt(found.value, Length(CATALOG_LIFT));
        world.look(degrees(0), degrees(walk.STRAIGHT_DOWN_DEGREES));
        world.interact();
        world.step();
        world.claim(Topic.structures, "The library's atriums hold a catalog: the nearest one opens its desk where it stands.", world.game.screen == Screen.machine && world.game.machineScreen == catalogScreen, Measure.of("hops searched", CATALOG_RINGS));
    }
}

enum string PAMPHLET = "game:pamphlet";
enum uint PAMPHLET_RINGS = 12;

uint noticedCount(ref Script world) {
    uint count = 0;
    foreach (index; 0 .. insights().length) {
        if (world.game.noticed.has(cast(uint) index)) {
            count += 1;
        }
    }
    return count;
}

void rumorIn(string name, string law)(ref Script world) {
    world.structure(name);
    walk.spawn(world);
    Maybe!Position found = walk.ensureNearest(world, world.game.characterState.position, materialNamed(PAMPHLET), PAMPHLET_RINGS);
    world.check(found.exists, "no pamphlet lies within %u hops of the start of %s", PAMPHLET_RINGS, name.ptr);
    if (!world.isFailed) {
        world.mode(MovementMode.noclip);
        world.game.placeAt(found.value, Length(CATALOG_LIFT));
        world.look(degrees(0), degrees(walk.STRAIGHT_DOWN_DEGREES));
        world.step();
        uint before = noticedCount(world);
        world.interact();
        world.step();
        uint once = noticedCount(world);
        world.interact();
        world.step();
        uint twice = noticedCount(world);
        world.claim(Topic.learning, law, once == before + 1 && twice == once && world.game.screen == Screen.none && world.game.aim.kind == AimKind.readable, Measure.of("hops searched", PAMPHLET_RINGS), Measure.of("noticed before", before), Measure.of("after one reading", once), Measure.of("after two", twice));
    }
}

enum string MIST_FAMILY = "base:mist";
enum string TIDE_FAMILY = "base:tide";
enum string EMBER_FAMILY = "base:ember";
enum string SEEN_TIDE = "pharmacology:seen-tide";
enum uint OPENS_MIST = 0;
enum uint OPENS_SWAY = 1;
enum double DOSE_ONSET = 4;

float familyLevel(ref Script world, string family) {
    Ratio[SIGNAL_COUNT] signals = organism(world.game).signaling.signals();
    Perception made = felt(Perception.init, signals[]);
    return made.levelOf(senseNamed(family).value).value;
}

void biologyTide(ref Script world) {
    world.plane(degrees(0));
    float sober = familyLevel(world, TIDE_FAMILY);
    organism(world.game).dose(starterDoses.ptr[OPENS_SWAY]);
    world.wait(DOSE_ONSET);
    float mist = familyLevel(world, MIST_FAMILY);
    float tide = familyLevel(world, TIDE_FAMILY);
    bool journaled = world.game.noticed.has(insightNamed(SEEN_TIDE).id);
    world.claim(Topic.learning, "Seeing a hidden family for the first time puts it in the journal: the dose that shows tide adds the entry about the tide.", journaled, Measure.of("insight", SEEN_TIDE));
    world.link(Topic.body, Topic.perception, "Tide shows to a body whose mist signal is held below rest: a dose that opens sway pushes mist down, and the tide family's level passes the line where a family is revealed while the mist family's stays under it.", sober < REVEAL_ON_LEVEL && tide > REVEAL_ON_LEVEL && mist < REVEAL_ON_LEVEL, Measure.of("tide level sober", sober), Measure.of("seconds after the dose", DOSE_ONSET), Measure.of("tide level", tide), Measure.of("mist level", mist), Measure.of("revealed above", REVEAL_ON_LEVEL));
}

enum uint REBOUND_DOSES = 9;
enum double REBOUND_GAP = 20;
enum double REBOUND_WATCH = 300;
enum double REBOUND_TICK = 2;

void biologyRebound(ref Script world) {
    world.plane(degrees(0));
    float most = -float.infinity;
    foreach (_; 0 .. REBOUND_DOSES) {
        organism(world.game).dose(starterDoses.ptr[OPENS_MIST]);
        world.wait(REBOUND_GAP);
        most = higherOf(most, familyLevel(world, TIDE_FAMILY));
    }
    float after = -float.infinity;
    double at = 0;
    double waited = 0;
    while (waited < REBOUND_WATCH) {
        world.wait(REBOUND_TICK);
        waited += REBOUND_TICK;
        float level = familyLevel(world, TIDE_FAMILY);
        if (level > after) {
            after = level;
            at = waited;
        }
    }
    world.link(Topic.body, Topic.perception, "Withdrawal shows tide: while doses that open mist are kept up the tide family stays under the line where a family is revealed, and after they stop the mist signal falls below rest and tide passes it.", most < REVEAL_ON_LEVEL && after > REVEAL_ON_LEVEL, Measure.of("doses", REBOUND_DOSES), Measure.of("seconds apart", REBOUND_GAP), Measure.of("highest tide level while dosing", most), Measure.of("highest after", after), Measure.of("seconds after the last gap", at), Measure.of("revealed above", REVEAL_ON_LEVEL));
}

void biologyEmber(ref Script world) {
    world.plane(degrees(0));
    organism(world.game).dose(starterDoses.ptr[OPENS_MIST]);
    world.wait(DOSE_ONSET);
    float alone = familyLevel(world, EMBER_FAMILY);
    float mist = familyLevel(world, MIST_FAMILY);
    organism(world.game).dose(starterDoses.ptr[OPENS_SWAY]);
    world.wait(DOSE_ONSET);
    float both = familyLevel(world, EMBER_FAMILY);
    world.link(Topic.body, Topic.perception, "Ember does not show to a body that only has mist: the dose that reveals the mist family leaves the ember family under the line where a family is revealed.", mist > REVEAL_ON_LEVEL && alone < REVEAL_ON_LEVEL, Measure.of("mist level", mist), Measure.of("ember level", alone), Measure.of("ember level with sway opened too", both), Measure.of("revealed above", REVEAL_ON_LEVEL));
    float weakMist = levelUnder(MIST_FAMILY, WEAK_DRIVE);
    float weakEmber = levelUnder(EMBER_FAMILY, WEAK_DRIVE);
    float fullEmber = levelUnder(EMBER_FAMILY, 1);
    world.link(Topic.body, Topic.perception, "Ember asks more of a compound than mist does: with the first trigger driven part way the mist family passes the line where a family is revealed and ember does not, and with it driven fully ember passes too.", weakMist > REVEAL_ON_LEVEL && weakEmber < REVEAL_ON_LEVEL && fullEmber > REVEAL_ON_LEVEL, Measure.of("first trigger driven at", WEAK_DRIVE), Measure.of("mist level", weakMist), Measure.of("ember level", weakEmber), Measure.of("ember level driven fully", fullEmber), Measure.of("revealed above", REVEAL_ON_LEVEL));
}

enum uint WILD_FLOWERS = 9;
enum double FLOWER_WATCH = 30;
enum double FLOWER_TICK = 0.5;

float mostAfterEating(ref Script world, Lineage genes, Material species, string family, Route route, uint count) {
    organism(world.game).dose(Dose(productOf(species, genes), PLANT_DOSE * count, route));
    float most = -float.infinity;
    double waited = 0;
    while (waited < FLOWER_WATCH) {
        world.wait(FLOWER_TICK);
        waited += FLOWER_TICK;
        most = higherOf(most, familyLevel(world, family));
    }
    return most;
}

struct Eaten {
    uint shown;
    float best;
}

Eaten eatWild(ref Script world, string plant, string family, Route route, uint count) {
    Graph* graph = &world.game.world.graph;
    Position here = world.game.characterState.position;
    Material species = materialNamed(plant);
    Lineage genes = speciesGenes(graph.stateAt(graph.slotOf(here.node).value).lineage, nameHashOf(species));
    ulong spice = here.node.spice();
    Eaten eaten = Eaten(0, -float.infinity);
    foreach (cell; 0 .. WILD_FLOWERS) {
        world.game.startOver();
        float most = mostAfterEating(world, cellGenes(genes, spice ^ cell), species, family, route, count);
        eaten.best = higherOf(eaten.best, most);
        if (most > REVEAL_ON_LEVEL) {
            eaten.shown += 1;
        }
    }
    return eaten;
}

void biologyWildTide(ref Script world) {
    world.plane(degrees(0));
    world.step();
    Eaten mushroom = eatWild(world, "base:mushroom-cap", TIDE_FAMILY, Route.ingested, 1);
    Eaten thornbush = eatWild(world, "base:thornbush", TIDE_FAMILY, Route.ingested, 1);
    Eaten moss = eatWild(world, "base:moss", TIDE_FAMILY, Route.ingested, 1);
    Eaten fern = eatWild(world, "base:fern", TIDE_FAMILY, Route.ingested, 1);
    world.link(Topic.body, Topic.perception, "Some wild strains of mushroom cap show tide when one is eaten, and no wild strain of thornbush, moss or fern does.", mushroom.shown > 0 && thornbush.shown == 0 && moss.shown == 0 && fern.shown == 0, Measure.of("wild strains tried of each", WILD_FLOWERS), Measure.of("mushroom caps that showed tide", mushroom.shown), Measure.of("thornbush", thornbush.shown), Measure.of("its highest tide level", thornbush.best), Measure.of("moss", moss.shown), Measure.of("fern", fern.shown));
}

void biologyWildMist(ref Script world) {
    world.plane(degrees(0));
    world.step();
    Eaten fern = eatWild(world, "base:fern", MIST_FAMILY, Route.ingested, 1);
    Eaten flower = eatWild(world, "base:flower", MIST_FAMILY, Route.ingested, 1);
    world.link(Topic.body, Topic.perception, "Some wild strains of fern and of flower show mist when one is eaten.", fern.shown > 0 && flower.shown > 0, Measure.of("wild strains tried of each", WILD_FLOWERS), Measure.of("ferns that showed mist", fern.shown), Measure.of("flowers", flower.shown), Measure.of("highest mist level", higherOf(fern.best, flower.best)));
}

void biologyWildEmber(ref Script world) {
    world.plane(degrees(0));
    world.step();
    Eaten fern = eatWild(world, "base:fern", EMBER_FAMILY, Route.ingested, 1);
    Eaten flower = eatWild(world, "base:flower", EMBER_FAMILY, Route.ingested, 1);
    world.link(Topic.body, Topic.perception, "Some wild strains of flower show ember when one is eaten, and no wild fern eaten alone does.", flower.shown > 0 && fern.shown == 0, Measure.of("wild strains tried of each", WILD_FLOWERS), Measure.of("flowers that showed ember", flower.shown), Measure.of("highest ember level from a fern", fern.best), Measure.of("revealed above", REVEAL_ON_LEVEL));
}

enum uint DRIVEN_TICKS = 200;
enum float WEAK_DRIVE = 0.4f;

float levelUnder(string family, float first) {
    Signaling body = Signaling.atRest();
    Ratio[TRANSDUCER_COUNT] driven = [Ratio(first), Ratio(0)];
    foreach (_; 0 .. DRIVEN_TICKS) {
        body.advance(driven, REST_TICK);
    }
    Ratio[SIGNAL_COUNT] signals = body.signals();
    Perception made = felt(Perception.init, signals[]);
    return made.levelOf(senseNamed(family).value).value;
}

enum float NETWORK_RADIUS = 2.5f;
enum double MOST_OF_THE_CAVES = 0.8;

void structureCaveNetwork(ref Script world) {
    world.structure("caves");
    world.game.generateWithin(Position.origin(), Length(NETWORK_RADIUS));
    CaveCount root = countCaves(world.game.world.graph, UPPER_CAVES);
    world.claim(Topic.structures, "Within 2.5 units of the caves world's root, most of the cave air in a band of rock under the ground is one connected space.", root.largestShare() > MOST_OF_THE_CAVES, Measure.of("separate spaces", root.spaces), Measure.of("cells of cave air", root.cells), Measure.of("in the largest space", root.largest), Measure.of("its share", root.largestShare()));
}

immutable string[2] EDGE_MARKS = ["base:limestone", "base:grey-brick"];

void structureTwoEdges(ref Script world) {
    world.structure("twoedges");
    world.step();
    Position here = world.game.characterState.position;
    uint found = 0;
    foreach (mark; EDGE_MARKS) {
        found += placesOf(world, here, mark);
    }
    world.claim(Topic.structures, "A world may give the engine more than one edge tile, and each of them runs: on a rig with two, each marks the start of the edges near spawn with its own stone.", found == EDGE_MARKS.length, Measure.of("edge tiles", EDGE_MARKS.length), Measure.of("marks found near spawn", found));
}

enum float ARBOR_DECK_UP = 3.2f;
enum uint ARBOR_RINGS = 3;

float oddsHere(ref Script world) {
    Graph* graph = &world.game.world.graph;
    return world.game.mutationOddsAt(graph.slotOf(world.game.characterState.position.node).value).value;
}

void structureArborBench(ref Script world) {
    world.structure("arbor");
    world.step();
    float below = oddsHere(world);
    world.mode(MovementMode.noclip);
    world.enterStructure(Length(ARBOR_DECK_UP));
    Maybe!Position found = walk.ensureNearest(world, world.game.characterState.position, materialNamed("pharmacology:bench"), ARBOR_RINGS);
    world.check(found.exists, "no bench lies within %u hops of the arbor's axis %.1f up", ARBOR_RINGS, ARBOR_DECK_UP);
    if (!world.isFailed) {
        world.game.placeAt(found.value, Length(CATALOG_LIFT));
        float up = world.altitude().value;
        float aloft = oddsHere(world);
        world.look(degrees(0), degrees(walk.STRAIGHT_DOWN_DEGREES));
        world.interact();
        world.step();
        world.claim(Topic.structures, "The arbor's decks hold a breeding bench: the nearest one to a deck stands high over the ground and opens where it stands.", world.game.screen == Screen.machine && world.game.machineScreen == benchScreen && up > ARBOR_DECK_UP / 2, Measure.of("searched from this far up the axis", ARBOR_DECK_UP), Measure.of("bench this far over the ground", up), Measure.of("mutation odds at the bench", aloft), Measure.of("at the foot of the tree", below));
    }
}

enum string TUNNEL_MATERIAL = "base:gravel";
immutable string[2] TRACK_MATERIALS = ["base:gravel", "base:steel"];
enum uint TUNNEL_RINGS = 3;
enum float TUNNEL_LIFT = 0.12f;

void structureCityTunnel(ref Script world) {
    world.structure("city");
    walk.spawn(world);
    Maybe!Position found = walk.ensureNearest(world, world.game.characterState.position, materialNamed(TUNNEL_MATERIAL), TUNNEL_RINGS);
    world.check(found.exists, "no track bed lies within %u hops of the city's start", TUNNEL_RINGS);
    if (!world.isFailed) {
        world.mode(MovementMode.noclip);
        world.game.placeAt(found.value, Length(TUNNEL_LIFT));
        world.mode(MovementMode.walk);
        world.wait(walk.LANDING_SECONDS);
        Maybe!Material below = walk.lookBelow(world);
        const(char)[] floor = walk.nameOf(below);
        float under = -world.altitude().value;
        world.claim(Topic.structures, "Subway lines run under the city's streets: a body let go over a track lands on its ballast or a rail, below the street.", world.isOnGround() && walk.isOneOf(below, TRACK_MATERIALS[]) && under > 0, Measure.of("standing on", floor), Measure.of("this far under the ground", under));
    }
}

enum string PLATFORM_EDGE = "base:pollen";
enum string MEZZANINE_MATERIAL = "base:ceiling-tile";
enum uint SUBWAY_RINGS = 4;
enum float PLATFORM_LIFT = 0.05f;

float standOn(ref Script world, Position at) {
    world.mode(MovementMode.noclip);
    world.game.placeAt(at, Length(PLATFORM_LIFT));
    world.mode(MovementMode.walk);
    world.wait(walk.LANDING_SECONDS);
    return -world.altitude().value;
}

bool isStandingOn(ref Script world, string material) {
    return world.isOnGround() && walk.isMaterial(walk.lookBelow(world), material);
}

void structureSubwayStation(ref Script world) {
    world.structure("city");
    walk.spawn(world);
    Maybe!Position rim = walk.ensureNearest(world, world.game.characterState.position, materialNamed(PLATFORM_EDGE), SUBWAY_RINGS);
    world.check(rim.exists, "no platform's edge lies within %u hops of the city's start", SUBWAY_RINGS);
    if (!world.isFailed) {
        Maybe!Position track = walk.ensureNearest(world, rim.value, materialNamed(TUNNEL_MATERIAL), 0);
        float bed = -float.infinity;
        if (track.exists) {
            bed = depthAt(world, track.value);
        }
        float edge = depthAt(world, rim.value);
        float platform = standOn(world, rim.value);
        bool onPlatform = isStandingOn(world, PLATFORM_EDGE);
        world.claim(Topic.structures, "A subway station has platforms above its track: a body set down on a platform's edge stands on it below the street, and the edge lies higher than the ballast of the track beside it.", onPlatform && platform > 0 && edge < bed, Measure.of("standing this far under the street", platform), Measure.of("platform's edge this far under it", edge), Measure.of("ballast this far under it", bed));
    }
}

float depthAt(ref Script world, Position at) {
    world.mode(MovementMode.noclip);
    world.game.placeAt(at, Length(0));
    return -world.altitude().value;
}

void structureSubwayMezzanine(ref Script world) {
    world.structure("city");
    walk.spawn(world);
    Maybe!Position mezzanine = walk.ensureNearest(world, world.game.characterState.position, materialNamed(MEZZANINE_MATERIAL), SUBWAY_RINGS);
    world.check(mezzanine.exists, "no mezzanine lies within %u hops of the city's start", SUBWAY_RINGS);
    if (!world.isFailed) {
        Maybe!Position rim = walk.ensureNearest(world, mezzanine.value, materialNamed(PLATFORM_EDGE), 0);
        float concourse = standOn(world, mezzanine.value);
        bool onConcourse = isStandingOn(world, MEZZANINE_MATERIAL);
        float platform = -float.infinity;
        if (rim.exists) {
            platform = standOn(world, rim.value);
        }
        world.claim(Topic.structures, "A deep subway station has a mezzanine between its platforms and the street: a body set down on a mezzanine floor stands on it below the street and above the nearest platform.", onConcourse && concourse > 0 && concourse < platform, Measure.of("mezzanine this far under the street", concourse), Measure.of("platform this far under the street", platform));
    }
}

enum size_t MOST_SUBWAY_STOPS = 24;
enum int ENTRANCE_STEPS = 6;
enum int MEZZANINE_STEPS = 4;
enum int TRANSFER_STEPS = 4;
enum int TRANSFER_START_X = 8;
enum int MOST_HEADROOM = 12;
enum int LEAST_HEADROOM = 4;
enum int PLATFORM_RISE = 2;
enum float LEAST_ENTRANCE_DESCENT = 10;
enum float LEAST_TRANSFER_DESCENT = 3;
enum float SUBWAY_SKIN = 0.001f;
immutable string[2] PLATFORM_MATERIALS = ["base:concrete", "base:pollen"];
immutable string[2] DEEP_FLOORS = ["base:gravel", "base:steel"];

struct Stops {
    Position[MOST_SUBWAY_STOPS] items;
    size_t count;

    void add(Position stop) {
        assert(count < MOST_SUBWAY_STOPS);
        items[count] = stop;
        count += 1;
    }
}

float cellsDown(ref Script world, float from) {
    Graph* graph = &world.game.world.graph;
    return (from - world.altitude().value) / (graph.view.edgeOf() / edgeCells(graph.layout.dimension));
}

void standAt(ref Script world, Position floor) {
    world.mode(MovementMode.noclip);
    world.game.placeAt(floor, Length(world.game.bodyExtent().value + SUBWAY_SKIN));
    world.mode(MovementMode.walk);
    world.wait(walk.SETTLE_SECONDS);
}

void structureSubwayWalk(ref Script world) {
    world.structure("city");
    Maybe!(walk.Sided) found = walk.ensureSided!(walk.isDeepEntrance)(world);
    world.check(found.exists, "no deep station near the city's start has a street entrance");
    if (!world.isFailed) {
        walk.Sided end = found.value;
        Stops stops;
        foreach (step; 1 .. ENTRANCE_STEPS + 1) {
            stops.add(end.spot(world, 3, 1 - step, 3.5f + step));
        }
        stops.add(end.spot(world, 3, -ENTRANCE_STEPS + 1, 4.5f + ENTRANCE_STEPS));
        stops.add(end.spot(world, 4, -ENTRANCE_STEPS + 1, 5.5f + ENTRANCE_STEPS));
        foreach (step; 1 .. MEZZANINE_STEPS + 1) {
            stops.add(end.spot(world, 4, -ENTRANCE_STEPS + 1 - step, 11.5f + step));
        }
        stops.add(end.spot(world, 4, -ENTRANCE_STEPS - MEZZANINE_STEPS, 12.5f + MEZZANINE_STEPS));
        standAt(world, end.spot(world, 3, 1, 2.5f));
        float street = world.altitude().value;
        bool started = world.isOnGround();
        size_t reached = climb.followStops(world, stops.items[0 .. stops.count]);
        world.wait(walk.SETTLE_SECONDS);
        Maybe!Material below = walk.lookBelow(world);
        float down = cellsDown(world, street);
        world.claim(Topic.structures, "A deep subway station is reached on foot from the street: from the sidewalk a body walks down the street entrance's stair to the mezzanine, across it and down the mezzanine's stair onto a platform.", started && reached == stops.count && world.isOnGround() && walk.isOneOf(below, PLATFORM_MATERIALS[]) && down >= LEAST_ENTRANCE_DESCENT, Measure.of("stops reached", reached), Measure.of("stops", stops.count), Measure.of("cells walked down", down), Measure.of("standing on", walk.nameOf(below)));
    }
}

bool isWalkableTransfer(ref Script world, walk.Sided end) {
    return walk.isTransfer(world, end) && end.holds(world, TRANSFER_START_X, walk.SUBWAY_TRANSFER_Y, 0, "base:gravel");
}

void structureSubwayTransfer(ref Script world) {
    world.structure("city");
    Maybe!(walk.Sided) found = walk.ensureSided!(isWalkableTransfer)(world);
    world.check(found.exists, "no transfer from a shallow line to a deep one lies near the city's start");
    if (!world.isFailed) {
        walk.Sided end = found.value;
        int shallow = walk.SUBWAY_TRANSFER_Y + 1;
        Stops stops;
        stops.add(end.spot(world, 4, shallow, 0.5f));
        stops.add(end.spot(world, 4, shallow, 3.5f));
        foreach (step; 1 .. TRANSFER_STEPS + 1) {
            stops.add(end.spot(world, 4, shallow - step, 3.5f + step));
        }
        stops.add(end.spot(world, 4, shallow - TRANSFER_STEPS, 5.5f + TRANSFER_STEPS));
        stops.add(end.spot(world, 0, shallow - TRANSFER_STEPS, 5.5f + TRANSFER_STEPS));
        standAt(world, end.spot(world, TRANSFER_START_X, shallow, 0.5f));
        float bore = world.altitude().value;
        bool started = world.isOnGround();
        size_t reached = climb.followStops(world, stops.items[0 .. stops.count]);
        world.wait(walk.SETTLE_SECONDS);
        Maybe!Material below = walk.lookBelow(world);
        float down = cellsDown(world, bore);
        world.claim(Topic.structures, "A transfer joins a shallow subway line to the deep line it crosses: a body walks from the shallow line's track down the passage's stair and onto the deep line's track.", started && reached == stops.count && world.isOnGround() && walk.isOneOf(below, DEEP_FLOORS[]) && down >= LEAST_TRANSFER_DESCENT, Measure.of("stops reached", reached), Measure.of("stops", stops.count), Measure.of("cells walked down", down), Measure.of("standing on", walk.nameOf(below)));
    }
}

enum double INTO_SHAFT_SECONDS = 0.15;
enum float MOST_DOOR_DROP = 1.5f;
enum string CITY_WELL_STAIR = "base:steel";

void structureSubwayWell(ref Script world) {
    world.structure("city");
    Maybe!(walk.Sided) found = walk.ensureSided!(walk.isWellDoor)(world);
    world.check(found.exists, "no subway line near the city's start ends at a port with a doorway");
    if (!world.isFailed) {
        walk.Sided end = found.value;
        int door = walk.floorUp(world, end, walk.DOOR_Z);
        bool level = end.holds(world, 0, door - 1, walk.DOOR_Z - 1, CITY_WELL_STAIR) || end.holds(world, -1, door - 1, walk.DOOR_Z - 1, CITY_WELL_STAIR);
        Stops stops;
        foreach_reverse (z; walk.DOOR_Z .. walk.DOOR_Z + walk.DOOR_RUN) {
            stops.add(end.spot(world, 0, walk.floorUp(world, end, z), z + 0.5f));
        }
        standAt(world, end.spot(world, 0, walk.floorUp(world, end, walk.DOOR_Z + walk.DOOR_RUN), walk.DOOR_Z + walk.DOOR_RUN + 0.5f));
        bool started = world.isOnGround();
        size_t reached = climb.followStops(world, stops.items[0 .. stops.count]);
        float atDoor = world.altitude().value;
        world.hold(Key.forward);
        world.wait(INTO_SHAFT_SECONDS);
        world.release(Key.forward);
        world.wait(walk.SETTLE_SECONDS);
        Maybe!Material below = walk.lookBelow(world);
        float dropped = cellsDown(world, atDoor);
        world.claim(Topic.structures, "Where a subway line ends short of a port, a doorway leads from its track into the well's shaft, level with a tread of the well's stair: a body walks from the track through the doorway onto the stair without falling.", started && level && reached == stops.count && world.isOnGround() && walk.isMaterial(below, CITY_WELL_STAIR) && dropped < MOST_DOOR_DROP, Measure.of("doorway's floor (cells under the road)", -door), Measure.of("stops reached", reached), Measure.of("stops", stops.count), Measure.of("cells dropped past the doorway", dropped), Measure.of("standing on", walk.nameOf(below)));
    }
}

int firstSolidDown(ref Script world, walk.Sided end, int x, int from, int z) {
    int y = from;
    while (y > from - MOST_HEADROOM && !end.isFilled(world, x, y, z)) {
        y -= 1;
    }
    return y;
}

void structureShallowPlatform(ref Script world) {
    world.structure("city");
    Maybe!(walk.Sided) found = walk.ensureSided!(walk.isShallowStation)(world);
    world.check(found.exists, "no shallow station lies near the city's start");
    if (!world.isFailed) {
        walk.Sided end = found.value;
        int floor = walk.SHALLOW_RIM + 1;
        int headroom = 0;
        while (headroom < MOST_HEADROOM && !end.isFilled(world, 4, floor + headroom, walk.SUBWAY_MIDDLE)) {
            headroom += 1;
        }
        int rise = firstSolidDown(world, end, 4, floor, walk.SUBWAY_MIDDLE) - firstSolidDown(world, end, 0, floor, walk.SUBWAY_MIDDLE);
        Stops stops;
        stops.add(end.spot(world, 4.5f, floor, 16.5f));
        standAt(world, end.spot(world, 4.5f, floor, 7.5f));
        bool stood = world.isOnGround();
        float start = world.traveled().value;
        size_t reached = climb.followStops(world, stops.items[0 .. stops.count]);
        world.wait(walk.SETTLE_SECONDS);
        Maybe!Material below = walk.lookBelow(world);
        world.claim(Topic.structures, "A shallow subway platform stands two cells over the ballast with at least four cells clear over it under the street, and a body set on it stands and walks its length.", headroom >= LEAST_HEADROOM && rise == PLATFORM_RISE && stood && reached == stops.count && world.isOnGround() && walk.isOneOf(below, PLATFORM_MATERIALS[]), Measure.of("cells clear over the platform", headroom), Measure.of("platform over the ballast (cells)", rise), Measure.of("walked", world.traveled().value - start), Measure.of("standing on", walk.nameOf(below)));
    }
}

enum string GROVE_STEP = "base:spruce-wood";
enum uint GROVE_TREADS = 15;
enum float TREAD_BELOW = 0.5f;
enum float TREAD_REACH = 0.1f;

void structurePlanetGrove(ref Script world) {
    world.terrain();
    Graph* graph = &world.game.world.graph;
    Material step = materialNamed(GROVE_STEP);
    size_t stops = graph.structures.blueprint.route.length;
    uint treads = 0;
    foreach (index; 0 .. stops) {
        SiteFrame site = graph.structures.blueprint.route.ptr[index].site;
        ColumnSpot spot = graph.structures.blueprint.route.ptr[index].spot;
        Position under = walk.columnPosition(world, site, spot.x, spot.y, spot.z - TREAD_BELOW);
        world.game.generateWithin(under, Length(TREAD_REACH));
        Maybe!Material held = walk.generatedAt(world, under);
        if (held.exists && held.value == step) {
            treads += 1;
        }
    }
    world.claim(Topic.structures, "The default world raises a grove of treehouses among its landmarks, and its route climbs the grove's spiral stair: at least as many of its stops stand on spruce treads as the stair has treads below the deck.", treads >= GROVE_TREADS, Measure.of("route stops", stops), Measure.of("stops on a spruce tread", treads), Measure.of("treads below the deck", GROVE_TREADS));
}

enum string HALL_LAMP = "base:light-panel";
enum int HALL_LOW_X = -6;
enum int HALL_HIGH_X = 5;
enum int HALL_TOP = -2;
enum int HALL_FIRST_Z = 6;
enum int HALL_LAST_Z = 17;

struct HallCount {
    uint cells;
    uint seen;
    uint lamps;
}

HallCount hallLamps(ref Script world, walk.Sided end, int bed) {
    Material lamp = materialNamed(HALL_LAMP);
    HallCount hall;
    foreach (z; HALL_FIRST_Z .. HALL_LAST_Z + 1) {
        foreach (x; HALL_LOW_X .. HALL_HIGH_X + 1) {
            foreach (y; bed .. HALL_TOP + 1) {
                Maybe!Material held = walk.generatedAt(world, walk.cellPosition(world, end.site, walk.mirroredCell(end.mirror, x), y, z));
                hall.cells += 1;
                if (held.exists) {
                    hall.seen += 1;
                    if (held.value == lamp) {
                        hall.lamps += 1;
                    }
                }
            }
        }
    }
    return hall;
}

void structureSubwayAbandoned(ref Script world) {
    world.structure("city");
    Maybe!(walk.Sided) found = walk.ensureSided!(walk.isAbandonedStation)(world);
    world.check(found.exists, "no station of an abandoned line lies near the city's start");
    if (!world.isFailed) {
        walk.Sided end = found.value;
        int bed = walk.SHALLOW_BALLAST;
        if (walk.isStation(world, end, walk.DEEP_RIM)) {
            bed = walk.LOWEST_BORE;
        }
        world.game.generateWithin(end.spot(world, 0, bed, walk.SUBWAY_MIDDLE), Length(walk.SIDED_REACH));
        HallCount hall = hallLamps(world, end, bed);
        uint entrances = 0;
        if (walk.isEntrance(world, end)) {
            entrances = 1;
        }
        world.claim(Topic.structures, "A station on an abandoned subway line is dark and shut: no lamp hangs in its hall and no stair comes down to it from the street.", hall.seen == hall.cells && hall.lamps == 0 && entrances == 0, Measure.of("cells of the hall seen", hall.seen), Measure.of("cells of the hall", hall.cells), Measure.of("lamps", hall.lamps), Measure.of("entrances at its end", entrances));
    }
}

enum uint SURVEYED_CITIES = 3;
enum size_t STREET_VERTICES = 48;
enum double STREETS_LOAD_SECONDS = 12;
enum int STREET_REACH = 10;
enum float PAVED_DEPTH = 1;
enum float LEAST_UNDER_DEPTH = 2;
enum float MOST_UNDER_DEPTH = 4;
immutable float[2] STREET_OFFSETS = [6.5f, -6.5f];
enum uint CITY_GROUND = tagNamed("horospheres:city");

struct StreetSurvey {
    uint columns;
    uint paved;
    uint holed;
}

void surveyColumn(ref Script world, HorosphereId city, SiteFrame up, float x, float y, ref StreetSurvey survey) {
    Graph* graph = &world.game.world.graph;
    float cell = graph.view.edgeOf() / edgeCells(graph.layout.dimension);
    uint paved = 0;
    uint holes = 0;
    foreach (z; -STREET_REACH .. STREET_REACH + 1) {
        Position at = walk.columnPosition(world, up, x, y, z + 0.5f);
        Maybe!Material held = walk.generatedAt(world, at);
        float depth = -graph.view.ensurePlaneHeight(city, at) / cell;
        if (held.exists && depth > 0 && depth <= PAVED_DEPTH && held.value != Material.none) {
            paved += 1;
        } else if (held.exists && depth >= LEAST_UNDER_DEPTH && depth <= MOST_UNDER_DEPTH && held.value == Material.none) {
            holes += 1;
        }
    }
    survey.columns += 1;
    if (paved > 0) {
        survey.paved += 1;
        if (holes > 0) {
            survey.holed += 1;
        }
    }
}

StreetSurvey surveyStreets(ref Script world, HorosphereId city, SiteFrame foot) {
    Graph* graph = &world.game.world.graph;
    SiteFrame[STREET_VERTICES] sites;
    sites[0] = foot;
    size_t count = 1;
    size_t next = 0;
    StreetSurvey survey;
    while (next < count) {
        SiteFrame site = graph.view.moveToLevel(sites[next], 0);
        next += 1;
        SiteFrame up = graph.view.turnSite(site, Turn.pitchUp);
        foreach (x; STREET_OFFSETS) {
            foreach (y; STREET_OFFSETS) {
                surveyColumn(world, city, up, x, y, survey);
            }
        }
        if (count + 3 <= STREET_VERTICES) {
            SiteFrame ahead = forwarded(site, 1);
            sites[count] = ahead;
            sites[count + 1] = graph.view.turnSite(ahead, Turn.left);
            sites[count + 2] = graph.view.turnSite(ahead, Turn.right);
            count += 3;
        }
    }
    return survey;
}

bool isSurveyed(const(CornerKey)[] surveyed, CornerKey key) {
    size_t index = 0;
    while (index < surveyed.length && surveyed[index] != key) {
        index += 1;
    }
    return index < surveyed.length;
}

bool isUnsurveyedCity(ref const Horospheres horospheres, uint index, const(CornerKey)[] surveyed) {
    const(Horosphere)* ground = &horospheres.horospheres.ptr[index];
    return ground.stage != HorosphereStage.free && horospheres.kinds.ptr[ground.kind].tag == CITY_GROUND && !isSurveyed(surveyed, ground.key);
}

MaybeIndex!uint unsurveyedCity(ref const Horospheres horospheres, const(CornerKey)[] surveyed) {
    uint index = 0;
    while (index < horospheres.horospheres.length && !isUnsurveyedCity(horospheres, index, surveyed)) {
        index += 1;
    }
    if (index < horospheres.horospheres.length) {
        return MaybeIndex!uint.of(index);
    } else {
        return MaybeIndex!uint.init;
    }
}

void structureStreets(ref Script world) {
    world.terrain();
    world.live();
    world.mode(MovementMode.noclip);
    world.wait(STREETS_LOAD_SECONDS);
    const(Horospheres)* horospheres = &world.game.world.graph.horospheres;
    CornerKey[SURVEYED_CITIES] surveyed;
    uint cities = 0;
    MaybeIndex!uint next = unsurveyedCity(*horospheres, surveyed[0 .. cities]);
    world.check(next.exists, "no city rose within %.0f seconds of loading around the default world's spawn", STREETS_LOAD_SECONDS);
    while (!world.isFailed && cities < SURVEYED_CITIES && next.exists) {
        CornerKey key = horospheres.horospheres.ptr[next.value].key;
        world.game.placeAt(walk.ensureVertex(world.game.world.graph, horospheres.horospheres.ptr[next.value].foot), Length(0));
        world.wait(STREETS_LOAD_SECONDS);
        Horosphere city = horospheres.horospheres.ptr[next.value];
        world.check(city.stage != HorosphereStage.free && city.key == key, "a city was let go while the camera stood on it");
        if (!world.isFailed) {
            StreetSurvey survey = surveyStreets(world, HorosphereId.ofIndex(next.value), city.foot);
            world.claim(Topic.structures, "Wherever a city risen over the default world's ground is paved, there is ground under the paving.", survey.paved > 0 && survey.holed == 0, Measure.of("city", cities), Measure.of("columns surveyed", survey.columns), Measure.of("paved", survey.paved), Measure.of("paved over open air", survey.holed));
        }
        surveyed[cities] = key;
        cities += 1;
        next = unsurveyedCity(*horospheres, surveyed[0 .. cities]);
    }
}

enum int THROUGH_CELLS = 10;
enum int JOINT_CELLS = 4;
enum int BORE_CLEAR = 4;
enum string RAIL_MATERIAL = "base:steel";
immutable int[4] TRACK_CELLS = [-2, -1, 0, 1];
immutable int[2] RAIL_CELLS = [-2, 1];
immutable int[2] RIM_CELLS = [-3, 2];

struct Line {
    int bed;
    int rim;
}

Line lineOf(ref Script world, walk.Sided end) {
    if (end.holds(world, walk.SUBWAY_RIM_X, walk.DEEP_RIM, 1, walk.SUBWAY_RIM)) {
        return Line(walk.LOWEST_BORE, walk.DEEP_RIM);
    } else {
        return Line(walk.SHALLOW_BALLAST, walk.SHALLOW_RIM);
    }
}

bool isRailCell(ref Script world, walk.Sided end, int x, int y, int z, int bed) {
    return y == bed + 1 && (x == RAIL_CELLS[0] || x == RAIL_CELLS[1]) && end.holds(world, x, y, z, RAIL_MATERIAL);
}

uint blockedOverTrack(ref Script world, walk.Sided end, int bed, int from, int to) {
    uint blocked = 0;
    foreach (z; from .. to) {
        foreach (x; TRACK_CELLS) {
            foreach (y; bed + 1 .. bed + 1 + BORE_CLEAR) {
                if (end.isFilled(world, x, y, z) && !isRailCell(world, end, x, y, z, bed)) {
                    blocked += 1;
                }
            }
        }
    }
    return blocked;
}

uint rimsMissing(ref Script world, walk.Sided end, int rim, int from, int to) {
    uint missing = 0;
    foreach (z; from .. to) {
        foreach (x; RIM_CELLS) {
            if (!end.holds(world, x, rim, z, walk.SUBWAY_RIM)) {
                missing += 1;
            }
        }
    }
    return missing;
}

void structureSubwayThrough(ref Script world) {
    world.structure("city");
    Maybe!(walk.Sided) found = walk.ensureSided!(walk.isContinuedStation)(world);
    world.check(found.exists, "no station near the city's start continues across a vertex");
    if (!world.isFailed) {
        walk.Sided end = found.value;
        Line line = lineOf(world, end);
        int bed = line.bed;
        uint blocked = blockedOverTrack(world, end, bed, -THROUGH_CELLS, THROUGH_CELLS);
        uint missing = rimsMissing(world, end, line.rim, -JOINT_CELLS, JOINT_CELLS);
        Stops stops;
        stops.add(end.spot(world, 0, bed + 1, 0.5f));
        stops.add(end.spot(world, 0, bed + 1, 0.5f - THROUGH_CELLS));
        standAt(world, end.spot(world, 0, bed + 1, THROUGH_CELLS - 0.5f));
        bool started = world.isOnGround();
        float start = world.traveled().value;
        size_t reached = climb.followStops(world, stops.items[0 .. stops.count]);
        world.wait(walk.SETTLE_SECONDS);
        Maybe!Material below = walk.lookBelow(world);
        world.claim(Topic.structures, "A station that continues across a vertex is whole through the joint: for ten cells either side of it nothing but the line's own two rails stands in the four cells over the ballast, both platform edges run unbroken for the four cells either side of it, short of the entrances' stairs, and a body walks the track bed from one edge into the next.", blocked == 0 && missing == 0 && started && reached == stops.count && world.isOnGround() && walk.isOneOf(below, DEEP_FLOORS[]), Measure.of("cells blocked over the track", blocked), Measure.of("platform edge cells missing", missing), Measure.of("ballast (cells under the road)", -bed), Measure.of("stops reached", reached), Measure.of("stops", stops.count), Measure.of("walked", world.traveled().value - start), Measure.of("standing on", walk.nameOf(below)));
    }
}

enum int UNDER_CELLS = 10;
enum int UNDER_AT = 2;

bool isDeepCrossing(ref Script world, walk.Sided end) {
    return isWalkableTransfer(world, end) && end.holds(world, 0, walk.LOWEST_BORE, -UNDER_CELLS, "base:gravel");
}

void structureSubwayUnder(ref Script world) {
    world.structure("city");
    Maybe!(walk.Sided) found = walk.ensureSided!(isDeepCrossing)(world);
    world.check(found.exists, "no deep line near the city's start runs on under a shallow one");
    if (!world.isFailed) {
        walk.Sided end = found.value;
        int floor = walk.LOWEST_BORE + 1;
        int headroom = 0;
        while (headroom < MOST_HEADROOM && !end.isFilled(world, 0, floor + headroom, UNDER_AT)) {
            headroom += 1;
        }
        bool roofed = end.holds(world, 0, walk.SHALLOW_BALLAST, UNDER_AT, "base:gravel");
        Stops stops;
        stops.add(end.spot(world, 0, floor, 0.5f));
        stops.add(end.spot(world, 0, floor, 0.5f - UNDER_CELLS));
        standAt(world, end.spot(world, 0, floor, UNDER_CELLS - 0.5f));
        bool started = world.isOnGround();
        float start = world.traveled().value;
        size_t reached = climb.followStops(world, stops.items[0 .. stops.count]);
        world.wait(walk.SETTLE_SECONDS);
        Maybe!Material below = walk.lookBelow(world);
        world.claim(Topic.structures, "Where a deep subway line passes under a shallow one its bore stays walkable: under the shallow line's ballast a body walks the deep track bed through the crossing from one edge into the next.", roofed && started && reached == stops.count && world.isOnGround() && walk.isOneOf(below, DEEP_FLOORS[]), Measure.of("cells clear over the deep ballast at the crossing", headroom), Measure.of("stops reached", reached), Measure.of("stops", stops.count), Measure.of("walked", world.traveled().value - start), Measure.of("standing on", walk.nameOf(below)));
    }
}

enum string HIDDEN_VAULTS_RIG = "risenvaults";
enum float VAULTS_RISE = 1.8f;
enum float HIDDEN_STAYED = 0.3f;

void structureHiddenVaults(ref Script world) {
    world.structure(HIDDEN_VAULTS_RIG);
    world.enterRoute();
    world.wait(walk.SETTLE_SECONDS);
    float start = world.altitude().value;
    Maybe!Material door = walk.lookBelow(world);
    const(char)[] doorName = walk.nameOf(door);
    world.claim(Topic.structures, "Nothing plain is laid at the foot of a hidden stair: the body stands on its own ground or on mist stone.", door.exists && doorName != "base:concrete", Measure.of("under the lower door", doorName));
    climb.follow(world, Maybe!size_t.init);
    world.takeFailure();
    world.wait(walk.SETTLE_SECONDS);
    float undosed = world.altitude().value - start;
    world.claim(Topic.structures, "Without mist sight a body following the hidden stair to the vaults does not leave the ground it started on.", undosed < HIDDEN_STAYED, Measure.of("height gained", undosed));
}

void structureHiddenVaultsClimb(ref Script world) {
    float start = 0;
    world.structure(HIDDEN_VAULTS_RIG);
    world.perceive("base:mist-sight");
    world.enterRoute();
    world.wait(walk.SETTLE_SECONDS);
    start = world.altitude().value;
    climb.follow(world, Maybe!size_t.init);
    world.wait(walk.SETTLE_SECONDS);
    float dosed = world.altitude().value - start;
    const(char)[] floor = walk.nameOf(walk.lookBelow(world));
    world.claim(Topic.structures, "With mist sight a body follows the hidden stair up and stands on the vaults.", world.isOnGround() && dosed > VAULTS_RISE,Measure.of("height gained", dosed), Measure.of("standing on", floor));
}

enum string ABYSS_RIG = "abyss";
enum float FOOTHOLD_HOP = 0.5f;
enum float DIVE_EDGES = 1.5f;
enum float BELOW_ABYSS_EDGES = 3.5f;
enum float PLANET_PAST_BOTTOM_EDGES = 0.5f;
enum double MOST_FALL_SECONDS = 10;
enum double HOVER_SECONDS = 3;
enum float WAKE_TOLERANCE = 1e-3f;
enum float HOLE_RADIUS = 0.06f;
enum float HOLE_DEPTH = 0.2f;
enum uint LOST_THIRD = 3;
enum string STRAINED = "base:flower";
immutable string[5] FALL_KINDS = ["base:granite", "base:dirt", "base:sand", "base:glass", "base:wood-planks"];
immutable uint[5] FALL_COUNTS = [1, 2, 3, 8, 81];
immutable Lineage[2] FALL_STRAINS = [Lineage([81, 82, 83, 84]), Lineage([91, 92, 93, 94])];
immutable uint[2] STRAIN_COUNTS = [4, 2];
immutable string[2] STRAIN_NAMES = ["base:flower, first strain", "base:flower, second strain"];

struct Hollow {
    Vec3!float up;
    Array!ChunkSlot slots;
    Array!Cell cells;

    void visitMissingNode(uint, Face) {
    }

    void visitChunk(ref const Graph graph, LocalFrame frame, ChunkSlot slot, CellRange range) {
        foreach (x; range.low.x .. range.high.x + 1) {
            foreach (y; range.low.y .. range.high.y + 1) {
                foreach (z; range.low.z .. range.high.z + 1) {
                    Vec3!float center = frame.cell(graph.layout, slot.corner, Vec3!int(x, y, z)).center();
                    float below = -center.dot(up);
                    if (below > 0 && below < HOLE_DEPTH && center.rejectAlong(up).magnitude < HOLE_RADIUS) {
                        slots.append(slot);
                        cells.append(Cell(cast(ubyte) x, cast(ubyte) y, cast(ubyte) z));
                    }
                }
            }
        }
    }

    void release() {
        slots.release();
        cells.release();
    }
}

uint hollowUnder(ref Script world, Position at) {
    Graph* graph = &world.game.world.graph;
    world.game.generateWithin(at, Length(HOLE_DEPTH));
    Hollow hollow = Hollow((*graph).ensureGravityAt(at).up);
    visitCells(*graph, at, Length(HOLE_DEPTH), hollow);
    uint removed = 0;
    foreach (index, slot; hollow.slots.slice()) {
        Cell cell = hollow.cells.ptr[index];
        ChunkId chunk = ChunkId(graph.idAt(slot.slot), slot.corner);
        Maybe!Material held = world.game.materialAt(chunk, cast(uint) cellIndex(graph.layout.dimension, cell.x, cell.y, cell.z));
        if (held.exists && held.value != Material.none && world.game.world.setVoxel(chunk, cell, Material.none)) {
            removed += 1;
        }
    }
    hollow.release();
    return removed;
}

float apartOn(ref Script world, Position from, Position to) {
    const(Graph)* graph = &world.game.world.graph;
    Point!float there = graph.ownView.nodeToNode(graph.slotOf(from.node).value, graph.slotOf(to.node).value) * from.local * Point!float.origin();
    return there.distance(to.local * Point!float.origin());
}

void standAfter(ref Script world, float ahead) {
    world.mode(MovementMode.noclip);
    world.press(ahead / walk.NOCLIP_SPEED, Key.forward);
    world.mode(MovementMode.walk);
    world.wait(walk.LANDING_SECONDS);
}

void dive(ref Script world, float edges) {
    world.mode(MovementMode.noclip);
    world.press(edges * world.game.world.graph.view.edgeOf() / walk.NOCLIP_SPEED, Key.down);
}

bool fallUntilWoken(ref Script world) {
    Time since = world.time();
    world.mode(MovementMode.walk);
    double fallen = 0;
    while (!world.isFailed && !notedSince(world, NoteKind.woke, since) && fallen < MOST_FALL_SECONDS) {
        world.step();
        fallen += world.timestep.value;
    }
    return notedSince(world, NoteKind.woke, since);
}

Inventory fallStock() {
    Inventory stock;
    foreach (index, name; FALL_KINDS) {
        stock.gain(Stack(named(name), FALL_COUNTS[index]));
    }
    foreach (index, genes; FALL_STRAINS) {
        stock.gain(Stack.ofLiving(named(STRAINED), STRAIN_COUNTS[index], genes, Sorting.unsorted));
    }
    return stock;
}

void fallsWake(ref Script world) {
    world.structure(ABYSS_RIG);
    walk.spawn(world);
    standAfter(world, FOOTHOLD_HOP);
    standAfter(world, FOOTHOLD_HOP);
    Position stood = world.game.characterState.position;
    Position marked = world.game.footholds.places[0];
    float behind = apartOn(world, marked, stood);
    float block = world.game.blockLength().value;
    dive(world, DIVE_EDGES);
    bool woke = fallUntilWoken(world);
    float apart = apartOn(world, world.game.characterState.position, marked);
    world.claim(Topic.falls, "A body that falls past the bottom of the world wakes standing within a block of the last place it stood before it went under the ground.", woke && world.isOnGround() && apart < WAKE_TOLERANCE && behind < block, Measure.of("let go this many edges below the ground", DIVE_EDGES), Measure.of("woke this far from the place marked", apart), Measure.of("that place was this far from where it last stood", behind), Measure.of("a block", block));
}

void fallsLoss(ref Script world) {
    world.structure(ABYSS_RIG);
    walk.spawn(world);
    world.game.inventory = fallStock();
    dive(world, DIVE_EDGES);
    bool woke = fallUntilWoken(world);
    world.check(woke, "the body let go under the ground did not wake");
    uint predictedLost = 0;
    foreach (index, name; FALL_KINDS) {
        uint held = FALL_COUNTS[index];
        uint predicted = held - held / LOST_THIRD;
        uint kept = world.game.inventory.countOf(named(name));
        predictedLost += held / LOST_THIRD;
        world.claim(Topic.falls, "A fall keeps every kind of thing the body held one or two of and loses a third, rounded down, of every kind it held three or more of.", woke && kept == predicted, Measure.of("kind", name), Measure.of("held", held), Measure.of("kept", kept), Measure.of("predicted", predicted));
    }
    foreach (index, genes; FALL_STRAINS) {
        uint held = STRAIN_COUNTS[index];
        uint predicted = held - held / LOST_THIRD;
        uint kept = world.game.inventory.countOfKind(Stack.ofLiving(named(STRAINED), 1, genes, Sorting.unsorted));
        predictedLost += held / LOST_THIRD;
        world.claim(Topic.falls, "A fall keeps every kind of thing the body held one or two of and loses a third, rounded down, of every kind it held three or more of.", woke && kept == predicted, Measure.of("kind", STRAIN_NAMES[index]), Measure.of("held", held), Measure.of("kept", kept), Measure.of("predicted", predicted));
    }
    if (world.game.notes.length == 0) {
        world.fail("no note was written after the fall");
    } else {
        const(Note)* said = &world.game.notes.ptr[world.game.notes.length - 1];
        world.check(said.kind == NoteKind.woke && said.amount == predictedLost, "the note after the fall says %.0f things were lost, not %u", cast(double) said.amount, predictedLost);
    }
}

void fallsCreative(ref Script world) {
    world.structure(ABYSS_RIG);
    walk.spawn(world);
    world.game.rules = Rules.creative;
    world.game.inventory = fallStock();
    Inventory before = world.game.inventory;
    dive(world, DIVE_EDGES);
    bool woke = fallUntilWoken(world);
    uint held = 0;
    foreach (ref stack; before.slots) {
        held += stack.count;
    }
    uint kept = 0;
    foreach (ref stack; world.game.inventory.slots) {
        kept += stack.count;
    }
    world.claim(Topic.falls, "Under creative rules a fall loses nothing.", woke && world.game.inventory == before, Measure.of("things held", held), Measure.of("things kept", kept));
}

void fallsUnmarked(ref Script world) {
    world.structure(ABYSS_RIG);
    walk.spawn(world);
    Position spawned = world.game.characterState.position;
    dive(world, DIVE_EDGES);
    uint marked = world.game.footholds.count;
    bool woke = fallUntilWoken(world);
    float apart = apartOn(world, world.game.characterState.position, spawned);
    world.claim(Topic.falls, "A body that has not stood anywhere since the world began wakes at the world's spawn.", woke && marked == 0 && world.isOnGround() && apart < WAKE_TOLERANCE, Measure.of("places it had stood", marked), Measure.of("woke this far from spawn", apart));
}

uint hollowUnderNewest(ref Script world, uint count) {
    uint removed = 0;
    foreach (index; 0 .. count) {
        removed += hollowUnder(world, world.game.footholds.places[index]);
    }
    return removed;
}

void fallsGone(ref Script world) {
    world.structure(ABYSS_RIG);
    walk.spawn(world);
    standAfter(world, FOOTHOLD_HOP);
    uint first = world.game.footholds.count;
    Position earlier = world.game.footholds.places[0];
    standAfter(world, FOOTHOLD_HOP);
    uint marked = world.game.footholds.count;
    uint removed = hollowUnderNewest(world, marked - first);
    world.check(first > 0 && marked > first && removed > 0, "standing in two places marked %u and then %u, and %u cells were removed", first, marked, removed);
    dive(world, DIVE_EDGES);
    bool woke = fallUntilWoken(world);
    float apart = apartOn(world, world.game.characterState.position, earlier);
    world.claim(Topic.falls, "When the ground is gone under the last places the body stood, it wakes on the latest place it stood that still has ground under it.", woke && world.isOnGround() && apart < WAKE_TOLERANCE && world.game.footholds.count == first, Measure.of("places whose ground was removed", marked - first), Measure.of("cells removed under them", removed), Measure.of("woke this far from the latest place left", apart));
}

void fallsNowhere(ref Script world) {
    world.structure(ABYSS_RIG);
    walk.spawn(world);
    Position spawned = world.game.characterState.position;
    standAfter(world, FOOTHOLD_HOP);
    standAfter(world, FOOTHOLD_HOP);
    uint marked = world.game.footholds.count;
    uint removed = hollowUnderNewest(world, marked);
    world.check(marked > 0 && removed > 0, "standing in two places marked %u, and %u cells were removed", marked, removed);
    dive(world, DIVE_EDGES);
    bool woke = fallUntilWoken(world);
    float apart = apartOn(world, world.game.characterState.position, spawned);
    world.claim(Topic.falls, "When the ground is gone under every place the body stood, it wakes at the world's spawn.", woke && world.isOnGround() && apart < WAKE_TOLERANCE && world.game.footholds.count == 0, Measure.of("places whose ground was removed", marked), Measure.of("cells removed under them", removed), Measure.of("woke this far from spawn", apart));
}

void fallsPlanet(ref Script world) {
    world.terrain();
    walk.spawn(world);
    Position spawned = world.game.characterState.position;
    Maybe!float abyss = world.game.world.graph.horospheres.abyssOf(ROOT);
    world.check(abyss.exists, "the default world names no bottom under its root");
    if (!world.isFailed) {
        float bottom = abyss.value / world.game.world.graph.view.edgeOf();
        float depth = bottom + PLANET_PAST_BOTTOM_EDGES;
        dive(world, depth);
        bool woke = fallUntilWoken(world);
        float apart = apartOn(world, world.game.characterState.position, spawned);
        world.claim(Topic.falls, "The default world has a bottom: a body let go below it wakes, and with nowhere stood yet it wakes at the world's spawn.", woke && world.isOnGround() && apart < WAKE_TOLERANCE, Measure.of("bottom (edges down)", bottom), Measure.of("let go this many edges below the ground", depth), Measure.of("woke this far from spawn", apart));
    }
}

void fallsFly(ref Script world) {
    world.structure(ABYSS_RIG);
    walk.spawn(world);
    dive(world, BELOW_ABYSS_EDGES);
    world.mode(MovementMode.fly);
    Time since = world.time();
    world.wait(HOVER_SECONDS);
    bool below = world.game.world.graph.isBelowAbyss(world.game.characterState.position);
    world.claim(Topic.falls, "In fly mode a body below the bottom of the world never wakes.", below && !notedSince(world, NoteKind.woke, since), Measure.of("let go this many edges below the ground", BELOW_ABYSS_EDGES), Measure.of("seconds flying there", HOVER_SECONDS));
}

enum double THREAD_WALK_SECONDS = 4;
enum uint FEW_BEADS = 8;
enum uint MANY_BEADS = 1024;
enum size_t REWOUND_SLACK = 2;

void lostThreadOff(ref Script world) {
    world.plane(degrees(0));
    walk.spawn(world);
    world.press(THREAD_WALK_SECONDS, Key.forward);
    world.claim(Topic.navigation, "The thread lays nothing unless it is turned on.", world.game.thread.beads.length == 0, Measure.of("beads laid", world.game.thread.beads.length));
}

void lostThread(ref Script world) {
    world.plane(degrees(0));
    world.game.thread.most = MANY_BEADS;
    walk.spawn(world);
    float spacing = world.game.thread.spacing.value;
    world.press(THREAD_WALK_SECONDS, Key.forward);
    float walked = world.traveled().value;
    size_t laid = world.game.thread.beads.length;
    size_t expected = cast(size_t)(walked / spacing) + 1;
    world.claim(Topic.navigation, "With the thread on, a bead is laid for every spacing walked.", laid + 1 >= expected && laid <= expected + 1, Measure.of("walked", walked), Measure.of("spacing", spacing), Measure.of("beads laid", laid), Measure.of("predicted", expected));
    world.check(world.game.isExplored(world.game.characterState.position.node), "the node underfoot is not marked explored");
    world.turn(degrees(180), degrees(0), walk.TURN_SECONDS);
    world.press(THREAD_WALK_SECONDS, Key.forward);
    float back = world.traveled().value - walked;
    size_t left = world.game.thread.beads.length;
    size_t rewound = cast(size_t)(fabs(walked - back) / spacing) + REWOUND_SLACK;
    world.claim(Topic.navigation, "Walking back along the thread winds it up again.", left <= rewound, Measure.of("walked out", walked), Measure.of("walked back", back), Measure.of("beads left", left));
}

void lostThreadFull(ref Script world) {
    world.plane(degrees(0));
    walk.spawn(world);
    world.game.thread.most = FEW_BEADS;
    world.step();
    world.check(world.game.thread.beads.length == 1, "standing still laid %zu thread beads, not one", world.game.thread.beads.length);
    Position first = world.game.thread.beads.ptr[0];
    world.press(THREAD_WALK_SECONDS, Key.forward);
    size_t held = world.game.thread.beads.length;
    Position kept = world.game.thread.beads.ptr[0];
    world.check(held <= FEW_BEADS && held > FEW_BEADS / 2, "a thread of at most %u beads holds %zu after walking %.3f", FEW_BEADS, held, world.traveled().value);
    float apart = (kept.local * Point!float.origin()).distance(first.local * Point!float.origin());
    world.check(kept.node == first.node && apart < SAVE_PLACE_TOLERANCE, "the full thread's first bead moved %.5f, so it no longer leads back to where it began", apart);
}

enum string HOOK_GIFT = "game:charcoal";
enum string HOOK_NOTE = "a mod heard the block break";
enum double GROUND_PITCH = 60;

void hearBreaks(const(void)* host, Happening happening) {
    const(Play)* play = cast(const(Play)*) host;
    if (happening.event == BROKE) {
        play.give(play, HOOK_GIFT, 1);
        play.learn(play, CHARRING);
        play.note(play, HOOK_NOTE);
    }
}

void contentHooks(ref Script world) {
    world.plane(degrees(0));
    walk.spawn(world);
    hooks.append(&hearBreaks);
    world.look(degrees(0), degrees(GROUND_PITCH));
    bool broke = world.breakBlock();
    hooks.length -= 1;
    world.check(broke, "broke the ground underfoot");
    uint gifts = world.game.inventory.countOf(named(HOOK_GIFT));
    world.claim(Topic.mods, "A mod can hear a block break and give the player an item in answer.", gifts == 1, Measure.of("given", gifts), Measure.of("item", HOOK_GIFT));
    world.check(world.game.noticed.has(insightNamed(CHARRING).id), "the hook taught charring, which breaking ground does not");
    size_t index = 0;
    while (index < world.game.notes.length && !(world.game.notes.ptr[index].kind == NoteKind.told && world.game.notes.ptr[index].label == HOOK_NOTE)) {
        index += 1;
    }
    world.check(index < world.game.notes.length, "the hook's note was not posted");
}

enum Time DEFAULT_TIMESTEP = Time(0.016f);
enum Time CHOSEN_TIMESTEP = Time(0.02f);
enum float TIMESTEP_TOLERANCE = 1e-6f;
enum float CLOCK_TOLERANCE = 1e-4f;
enum float REST_TOLERANCE = 5e-5f;

enum SpawnCheck : ubyte {
    skipped,
    checked,
}

enum Launch : ubyte {
    still,
    moving,
}

struct HookCount {
    uint steps;
    uint allowed;
}

void countHook(ref Script world, void* context) {
    HookCount* count = cast(HookCount*) context;
    count.steps += 1;
    world.wait(1);
    bool refused = world.takeFailure();
    if (!refused) {
        count.allowed += 1;
    }
}

void api(ref Script world) {
    world.material(HOTBAR_SLOTS + 1);
    bool refused = world.takeFailure();
    world.check(refused, "material slots past the hotbar are an error");
    world.check(fabs(world.timestep.value - DEFAULT_TIMESTEP.value) < TIMESTEP_TOLERANCE, "default timestep is 0.016 s");
    world.setTimestep(CHOSEN_TIMESTEP);
    world.plane(degrees(0));
    world.check(world.mode() == MovementMode.walk && world.isOnGround(), "the player starts walking, standing on the ground");
    world.wait(1);
    world.check(fabs(world.time().value - 1) < CLOCK_TOLERANCE, "waited 1 s, clock reads %.4f s", world.time().value);
    world.step(Time(CHOSEN_TIMESTEP.value / 2));
    world.check(fabs(world.time().value - 1 - CHOSEN_TIMESTEP.value / 2) < CLOCK_TOLERANCE, "one half step, clock reads %.4f s", world.time().value);
    if (!world.isFailed) {
        world.terrain();
        refused = world.takeFailure();
        world.check(refused, "worldgen cannot change after the first step");
    }
    if (!world.isFailed) {
        world.wait(1, Time(0));
        refused = world.takeFailure();
        world.check(refused, "a zero timestep is an error");
    }

    HookCount count;
    world.onStep(StepHook(&countHook, &count));
    world.wait(0.1);
    world.check(count.steps == 5, "the step hook ran %u times in 5 steps", count.steps);
    world.check(count.allowed == 0, "a step hook cannot advance time");
    world.onStep(StepHook.init);
    world.wait(0.1);
    world.check(count.steps == 5, "a removed step hook does not run");

    world.check(world.yawRate.value == 0 && world.pitchRate.value == 0, "turn rate starts at rest");
    world.turn(degrees(90), degrees(0), 0.5);
    world.check(world.yawRate.value == 0 && world.pitchRate.value == 0, "turn restores the previous turn rate");

    world.wait(3);
    world.check(world.isOnGround(), "standing after turning");
    world.check(fabs(world.speed().value) < REST_TOLERANCE && fabs(world.verticalSpeed().value) < REST_TOLERANCE, "at rest when no key is held");

    world.hold(Key.forward);
    world.look(degrees(0.25), degrees(-0.5));
    world.wait(0.48, DEFAULT_TIMESTEP);
    world.release(Key.forward);
    world.wait(0.48, DEFAULT_TIMESTEP);
    world.check(world.traveled().value > 0, "holding fwd moves the player");
    world.material(3);
    world.check(world.material() == 3, "material slot is set and read back");
}

enum float PENTAGON_SIDE = 1.0613f;
enum uint PENTAGON_SIDES = 5;
enum double QUARTER_TURN = 90;
enum double QUARTER_TOLERANCE = 3;
enum double STRAIGHT_TOLERANCE = 0.5;
enum float CLOSED_SHARE = 0.25f;

Vec4!float facingAt(ref Script world, Position at) {
    Vec3!float forward = world.game.camera.heading.rotate(CAMERA_FORWARD);
    return at.local * Vec4!float([forward.x, forward.y, forward.z, 0]);
}

float pentagonLap(ref Script world) {
    world.look(degrees(0), degrees(0));
    world.resetCompass();
    float before = world.compassOff().value;
    foreach (_; 0 .. PENTAGON_SIDES) {
        world.press(PENTAGON_SIDE / walk.NOCLIP_SPEED, Key.forward);
        world.look(degrees(QUARTER_TURN), degrees(0));
    }
    world.step();
    return world.compassOff().value - before;
}

void demoHolonomy(ref Script world) {
    world.plane(degrees(0));
    world.mode(MovementMode.noclip);
    world.resetCompass();
    world.press(0.2f / walk.NOCLIP_SPEED, Key.forward);
    double straight = world.compassOff().value / RADIANS_PER_DEGREE;
    world.claim(Topic.navigation, "Going straight ahead does not turn the compass.", fabs(straight) < STRAIGHT_TOLERANCE, Measure.of("compass turned by (degrees)",straight));
    Position start = world.game.characterState.position;
    Vec4!float first = facingAt(world, start);
    double off = pentagonLap(world) / RADIANS_PER_DEGREE;
    Position end = world.game.characterState.position;
    float apart = (end.local * Point!float.origin()).distance(start.local * Point!float.origin());
    double facing = acos(higherOf(lowerOf(first.minkowski(facingAt(world, end)), 1.0f), -1.0f)) / RADIANS_PER_DEGREE;
    world.claim(Topic.space, "A walk of five equal legs with a right turn after each ends where it began. In flat space it would take four.", end.node == start.node && apart < CLOSED_SHARE * PENTAGON_SIDE, Measure.of("leg length", PENTAGON_SIDE), Measure.of("ended this far from its start", apart));
    world.claim(Topic.space, "After those five legs and five right turns, a turn and a quarter in all, the walker faces the way it first faced.", end.node == start.node && facing < QUARTER_TOLERANCE, Measure.of("facing off its first direction (degrees)", facing));
    world.claim(Topic.navigation, "The compass holds the direction it was set to while the player turns: after five right turns it reads a quarter turn off.", fabs(fabs(off) - QUARTER_TURN) < QUARTER_TOLERANCE, Measure.of("compass turned by (degrees)",off));
}

void demoThrow(ref Script world) {
    world.plane(degrees(0));
    walk.spawn(world);
    world.throwBlock();
    world.check(world.thrownCount() == 1, "a thrown block is flying");
    world.check(!world.isThrownResting(0), "a thrown block starts in the air");
    world.wait(4);
    world.check(world.thrownCount() == 1, "the block is still there after it lands");
    world.claim(Topic.gravity, "A thrown block falls and comes to rest where it hits something solid.", world.isThrownResting(0));
}

enum double GROWTH_SECONDS = 3;
enum uint GROWTH_FIRST_STEP = 2;
enum uint GROWTH_LAST_STEP = 5;
enum double LEAST_GROWTH = 2;

void demoGrowth(ref Script world) {
    world.structure("city");
    world.live();
    world.wait(GROWTH_SECONDS);
    Growth growth;
    growth.update(world.game.world);
    foreach (step; GROWTH_FIRST_STEP .. GROWTH_LAST_STEP + 1) {
        double rate = cast(double) growth.within[step] / growth.within[step - 1];
        world.claim(Topic.space, "Each further step through the honeycomb more than doubles the number of cells within reach.", rate > LEAST_GROWTH, Measure.of("steps", step), Measure.of("cells within them", growth.within[step]), Measure.of("cells within one step fewer", growth.within[step - 1]), Measure.of("growth", rate));
    }
    growth.release();
}

enum uint CORNER_BLOCKS = 2;
enum double ARRIVAL_MARGIN_SECONDS = 0.5;
enum double PUSH_SECONDS = 2;
enum float MOST_PUSH_TRAVEL = 0.0025f;
enum float MOST_CAMERA_ACCELERATION = 0.05f;

void shakeHook(ref Script world, void* context) {
    float* shake = cast(float*) context;
    *shake = higherOf(*shake, world.cameraVerticalAcceleration());
}

void flatCorner(ref Script world) {
    world.plane(degrees(0));
    walk.spawn(world);
    walk.buildCorner(world, CORNER_BLOCKS);
    walk.checkStanding(world, "back on the floor");
    double cornerYaw = atan2(walk.WALL_HALF_WIDTH, walk.WALL_DISTANCE) / RADIANS_PER_DEGREE;
    world.look(degrees(cornerYaw), degrees(0));
    world.hold(Key.forward);
    world.wait(sqrt(walk.WALL_DISTANCE * walk.WALL_DISTANCE + walk.WALL_HALF_WIDTH * walk.WALL_HALF_WIDTH) / walk.SPEED + ARRIVAL_MARGIN_SECONDS);
    float start = world.traveled().value;
    float shake = 0;
    world.onStep(StepHook(&shakeHook, &shake));
    world.wait(PUSH_SECONDS);
    world.release(Key.forward);
    world.onStep(StepHook.init);
    float pushed = world.traveled().value - start;
    world.claim(Topic.movement, "Pushing into a corner does not move the body.", pushed <= MOST_PUSH_TRAVEL, Measure.of("moved", pushed), Measure.of("seconds pushing", PUSH_SECONDS));
    world.check(shake <= MOST_CAMERA_ACCELERATION, "camera shook at %.4f/s^2 in the corner", shake);
    walk.checkStanding(world, "in the corner");
}

enum float CURVE_ALTITUDE = 1;
enum double FALL_SECONDS = 0.25;
enum double LEAST_CURVE_FRACTION = 0.75;
enum double MOST_CURVE_FRACTION = 1.25;

struct Fall {
    float vertical = 0;
    float speed = 0;
    float altitude = 0;
}

void riseTo(ref Script world, float altitude) {
    world.mode(MovementMode.fly);
    world.press((altitude - world.altitude().value) / walk.FLY_SPEED, Key.up);
    world.step();
}

Fall fall(ref Script world, Launch launch) {
    if (launch == Launch.moving) {
        world.hold(Key.forward);
        world.step();
    }
    world.mode(MovementMode.walk);
    if (launch == Launch.moving) {
        world.release(Key.forward);
    }
    float altitude = world.altitude().value;
    float speed = world.horizontalSpeed().value;
    world.wait(FALL_SECONDS);
    return Fall(world.verticalSpeed().value, speed, altitude);
}

void flatCurve(ref Script world) {
    world.plane(degrees(0));
    walk.spawn(world);
    riseTo(world, CURVE_ALTITUDE);
    Fall still = fall(world, Launch.still);
    riseTo(world, CURVE_ALTITUDE);
    Fall moving = fall(world, Launch.moving);
    double doubled = exp(2.0 * moving.altitude);
    double predicted = moving.speed * moving.speed * (doubled - 1) / (doubled + 1) * FALL_SECONDS;
    double gained = moving.vertical - still.vertical;
    world.link(Topic.space, Topic.movement, "A body launched level at speed v at height h over flat ground falls slower than one dropped from rest: after a time t its downward speed is less by v^2 tanh(h) t.", gained >= LEAST_CURVE_FRACTION * predicted && gained <= MOST_CURVE_FRACTION * predicted, Measure.of("speed", moving.speed), Measure.of("height", moving.altitude), Measure.of("seconds", FALL_SECONDS), Measure.of("fell slower by", gained), Measure.of("predicted", predicted));
}

enum uint HOLE_BLOCKS = 2;
enum double LOWER_BLOCK_DEGREES = 18;
enum uint MOST_BREAKS = 4;
enum double APPROACH_SECONDS = 1;
enum double SEARCH_SECONDS = 0.5;
enum double THROUGH_SECONDS = 2;
enum double FREE_SECONDS = 1;
enum float LEAST_FREE_FRACTION = 0.8f;

bool isWall(Maybe!Material target) {
    return walk.isMaterial(target, walk.BUILD_LAYERS[0].material) || walk.isMaterial(target, walk.BUILD_LAYERS[1].material);
}

void clearAhead(ref Script world, double pitch, const(char)* what) {
    world.look(degrees(0), degrees(pitch));
    uint breaks = 0;
    while (!world.isFailed && isWall(world.targetMaterial()) && breaks < MOST_BREAKS) {
        bool broke = world.breakBlock();
        world.check(broke, "broke the %s block of the hole", what);
        breaks += 1;
    }
    const(char)[] facing = walk.nameOf(world.targetMaterial());
    world.check(breaks > 0 && !isWall(world.targetMaterial()), "cleared the %s of the hole in %u breaks, facing %.*s", what, breaks, cast(int) facing.length, facing.ptr);
    world.look(degrees(0), degrees(-pitch));
}

void flatHole(ref Script world) {
    world.plane(degrees(0));
    walk.spawn(world);
    walk.buildWall(world, HOLE_BLOCKS);
    walk.checkStanding(world, "back on the floor");
    clearAhead(world, 0, "upper half");
    clearAhead(world, LOWER_BLOCK_DEGREES, "lower half");
    world.hold(Key.forward);
    world.wait(APPROACH_SECONDS);
    world.press(SEARCH_SECONDS, Key.left);
    world.press(2 * SEARCH_SECONDS, Key.right);
    world.wait(THROUGH_SECONDS);
    world.release(Key.forward);
    walk.checkStanding(world, "after squeezing through the hole");
    walk.forward(world, FREE_SECONDS, LEAST_FREE_FRACTION);
}

enum float IDEAL_RISE = 0.085f;
enum float LEAST_RISE_FRACTION = 0.97f;
enum float MOST_RISE_FRACTION = 1.001f;

struct Jump {
    float apex = 0;
    float drift = 0;
}

void jumpHook(ref Script world, void* context) {
    Jump* jump = cast(Jump*) context;
    jump.apex = higherOf(jump.apex, world.altitude().value);
    jump.drift = higherOf(jump.drift, world.horizontalSpeed().value);
}

void flatJump(ref Script world) {
    world.plane(degrees(0));
    walk.spawn(world);
    walk.checkStanding(world, "before jumping");
    float standing = world.altitude().value;
    Jump jump = Jump(standing, 0);
    world.onStep(StepHook(&jumpHook, &jump));
    world.press(0.1, Key.up);
    world.wait(1.5);
    world.onStep(StepHook.init);
    float rise = jump.apex - standing;
    world.claim(Topic.movement, "A standing jump rises to the body's jump height.", rise >= LEAST_RISE_FRACTION * IDEAL_RISE && rise <= MOST_RISE_FRACTION * IDEAL_RISE, Measure.of("rose", rise), Measure.of("expected", IDEAL_RISE), Measure.of("jump height setting", world.game.character.jumpHeight.value));
    world.claim(Topic.movement, "A standing jump does not drift sideways.", jump.drift < walk.SPEED_TOLERANCE, Measure.of("fastest sideways speed", jump.drift));
    walk.checkStanding(world, "after landing");
}

enum double AHEAD_DEGREES = 30;

void flatItems(ref Script world) {
    world.plane(degrees(0));
    walk.spawn(world);
    world.look(degrees(0), degrees(AHEAD_DEGREES));
    Item ground = itemOf(world.targetMaterial().value);
    uint before = world.game.inventory.countOf(ground);
    bool broke = world.breakBlock();
    world.claim(Topic.blocks, "Breaking a block puts one of it in the inventory.", broke && world.game.inventory.countOf(ground) == before + 1, Measure.of("held before", before), Measure.of("held after", world.game.inventory.countOf(ground)));
    Item held = world.game.inventory.held();
    uint stock = world.game.inventory.countOf(held);
    bool placed = world.placeBlock();
    world.claim(Topic.blocks, "Placing a block takes one of it out of the inventory.", placed && world.game.inventory.countOf(held) == stock - 1, Measure.of("held before", stock), Measure.of("held after", world.game.inventory.countOf(held)));
    world.breakBlock();
    world.game.inventory.slots[world.game.inventory.selected] = Stack.init;
    world.check(!world.placeBlock(), "placed a block with none held");
}

enum double MINING_SLACK_SECONDS = 0.2;

void flatMining(ref Script world) {
    world.plane(degrees(0));
    walk.spawn(world);
    world.game.inventory = Inventory.init;
    world.look(degrees(0), degrees(AHEAD_DEGREES));
    world.step();
    Item ground = itemOf(world.targetMaterial().value);
    double needed = world.game.breakTimeOf(ground.block).value;
    world.hold(Key.mine);
    world.wait(needed / 2);
    world.claim(Topic.blocks, "Half way through its break time a block is still whole and shows mining progress.", world.game.inventory.countOf(ground) == 0 && world.game.miningShare().value > 0.3f, Measure.of("break time (seconds)",needed), Measure.of("progress shown", world.game.miningShare().value));
    world.wait(needed / 2 + MINING_SLACK_SECONDS);
    world.release(Key.mine);
    world.claim(Topic.blocks, "Holding mine on a block for its break time breaks it and puts it in the inventory.", world.game.inventory.countOf(ground) == 1, Measure.of("break time (seconds)",needed), Measure.of("held after", world.game.inventory.countOf(ground)));
}

enum uint SANDSTONE_SLOT = 6;
enum string SANDSTONE = "base:sandstone";

void flatTiers(ref Script world) {
    world.plane(degrees(0));
    walk.spawn(world);
    world.material(SANDSTONE_SLOT);
    world.look(degrees(0), degrees(AHEAD_DEGREES));
    world.check(world.placeBlock() && walk.isMaterial(world.targetMaterial(), SANDSTONE), "could not place the sandstone");
    world.game.inventory = Inventory.init;
    double needed = world.game.breakTimeOf(materialNamed(SANDSTONE)).value;
    world.hold(Key.mine);
    world.wait(needed + MINING_SLACK_SECONDS);
    world.claim(Topic.blocks, "A block that needs a pickaxe cannot be mined by hand, however long the key is held.", world.game.inventory.countOf(named(SANDSTONE)) == 0 && world.game.mineableOf(materialNamed(SANDSTONE)) == Mineable.tooHard, Measure.of("block", SANDSTONE), Measure.of("seconds held", needed + MINING_SLACK_SECONDS));
    world.check(world.game.notes.length > 0 && world.game.notes.ptr[world.game.notes.length - 1].kind == NoteKind.needsTier, "mining sandstone by hand left no note saying what it needs");
    world.release(Key.mine);
    world.game.owned.set(upgradeNamed(WOODEN_PICKAXE).id);
    double picked = world.game.breakTimeOf(materialNamed(SANDSTONE)).value;
    world.claim(Topic.blocks, "A pickaxe shortens a block's break time.", picked < needed, Measure.of("block", SANDSTONE), Measure.of("by hand (seconds)", needed), Measure.of("with a wooden pickaxe (seconds)", picked));
    world.hold(Key.mine);
    world.wait(picked + MINING_SLACK_SECONDS);
    world.release(Key.mine);
    world.claim(Topic.blocks, "With the pickaxe it needs, a block is mined in its shortened break time.", world.game.inventory.countOf(named(SANDSTONE)) == 1, Measure.of("block", SANDSTONE), Measure.of("seconds held", picked + MINING_SLACK_SECONDS));
}

enum uint STATION_SLOT = HOTBAR_SLOTS - 1;
enum string PLANKS_RECIPE = "game:planks";
enum string WORKBENCH_RECIPE = "game:make-workbench";
enum string WOOD_PICK_RECIPE = "game:make-wooden-pickaxe";
enum string GLASS_RECIPE = "game:smelt-glass";
enum string SIFT_SAND_RECIPE = "game:sift-sand";
enum string WOODEN_PICKAXE = "game:wooden-pickaxe";
enum string WORKBENCH_STATION = "game:workbench-station";
enum string SIFTING = "game:sifting";
enum string CHARRING = "game:charring";
enum string PRESS_DOSE = "pharmacology:press-dose";
enum string PRESS_EXTRACT = "pharmacology:press-extract";

double secondsOf(const(char)[] recipe) {
    return recipes()[recipeNamed(recipe)].time.value;
}

void flatCrafting(ref Script world) {
    world.plane(degrees(0));
    walk.spawn(world);
    world.game.inventory = Inventory.init;
    world.check(!world.game.craft(recipeNamed(WORKBENCH_RECIPE)), "made a workbench from nothing");
    const(Recipe)* sawing = &recipes()[recipeNamed(PLANKS_RECIPE)];
    uint boards = recipes()[recipeNamed(WORKBENCH_RECIPE)].needs[0].count;
    uint wood = (boards + sawing.yield - 1) / sawing.yield;
    uint spare = wood * sawing.yield - boards;
    world.game.inventory.gain(Stack(named("base:birch-wood"), wood));
    world.claim(Topic.crafting, "Queuing a recipe also queues, ahead of it, the recipes that make its missing ingredients.", world.game.craft(recipeNamed(WORKBENCH_RECIPE)) && world.game.crafts.length == wood + 1, Measure.of("wood held", wood), Measure.of("planks a workbench takes", boards), Measure.of("steps queued for a workbench", world.game.crafts.length));
    double total = wood * secondsOf(PLANKS_RECIPE) + secondsOf(WORKBENCH_RECIPE);
    world.wait(total + MINING_SLACK_SECONDS);
    Item planks = named("base:wood-planks");
    world.check(world.game.inventory.countOf(named("game:workbench")) == 1 && world.game.inventory.countOf(planks) == spare && world.game.crafts.length == 0, "%u wood made %u workbenches and left %u planks", wood, world.game.inventory.countOf(named("game:workbench")), world.game.inventory.countOf(planks));
    world.game.inventory.gain(Stack(named("base:spruce-wood"), 1));
    world.check(world.game.craft(recipeNamed(PLANKS_RECIPE)), "could not queue planks");
    world.step();
    world.check(world.game.crafts.length == 1 && world.game.crafts.ptr[0].started == Readiness.ready && world.game.inventory.countOf(named("base:spruce-wood")) == 0, "the planks did not start on the first step");
    world.game.cancelCraft(0);
    world.claim(Topic.crafting, "Cancelling a craft that has started gives back exactly the ingredients it took.", world.game.inventory.countOf(named("base:spruce-wood")) == 1 && world.game.inventory.countOf(named("base:oak-wood")) == 0 && world.game.crafts.length == 0, Measure.of("spruce wood back", world.game.inventory.countOf(named("base:spruce-wood"))), Measure.of("oak wood back", world.game.inventory.countOf(named("base:oak-wood"))));
    world.check(world.game.craft(recipeNamed(WOOD_PICK_RECIPE)) && world.game.crafts.length == 2, "%u spare planks and a wood queued %zu steps for a wooden pickaxe, not planks and the pickaxe", spare, world.game.crafts.length);
    world.check(!world.game.craft(recipeNamed(WOOD_PICK_RECIPE)) && world.game.crafts.length == 2 && world.game.notes.ptr[world.game.notes.length - 1].kind == NoteKind.upgradeQueued, "a second wooden pickaxe was queued while the first waits");
    world.wait(secondsOf(PLANKS_RECIPE) + secondsOf(WOOD_PICK_RECIPE) + MINING_SLACK_SECONDS);
    world.claim(Topic.crafting, "Work for a station waits while the player has used no station of that kind nearby.", !world.game.owned.has(upgradeNamed(WOODEN_PICKAXE).id) && world.game.crafts.length == 1, Measure.of("crafts still waiting", world.game.crafts.length));
    world.check(world.game.inventory.spend(named("game:workbench"), 1), "the workbench left the inventory");
    world.game.inventory.slots[STATION_SLOT] = Stack(named("game:workbench"), 1);
    world.material(STATION_SLOT + 1);
    world.look(degrees(0), degrees(AHEAD_DEGREES));
    world.check(world.placeBlock() && walk.isMaterial(world.targetMaterial(), "game:workbench"), "could not place the workbench");
    world.interact();
    world.check(world.game.screen == Screen.station && world.game.workstation == stationNamed(WORKBENCH_STATION), "using the workbench did not open it");
    world.wait(secondsOf(WOOD_PICK_RECIPE) + MINING_SLACK_SECONDS);
    world.claim(Topic.crafting, "Once the player has placed and used the station, the work that waited for it is done.", world.game.owned.has(upgradeNamed(WOODEN_PICKAXE).id) && world.game.crafts.length == 0, Measure.of("crafts still waiting", world.game.crafts.length));
}

void geneRipening(ref Script world) {
    world.plane(degrees(0));
    walk.spawn(world);
    world.look(degrees(0), degrees(AHEAD_DEGREES));
    world.game.inventory.slots[0] = Stack(named("base:flower"), 1);
    world.material(1);
    world.check(world.placeBlock() && world.game.inventory.slots[0].isEmpty, "could not plant the flower");
    world.check(world.breakBlock() && world.game.compounds.length == 0 && isLastTold(world, Told.unripeHarvest), "breaking an unripe flower gave %zu compounds or no note that it was unripe", world.game.compounds.length);
    Stack back = world.game.inventory.slots[0];
    world.claim(Topic.plants, "Breaking a plant before it is ripe gives back the one plant with its genes, and nothing more.", back.count == 1 && back.item == named("base:flower") && back.genes.exists, Measure.of("given back", back.count));
    world.check(world.placeBlock() && isLastTold(world, Told.planted), "the flower that came back did not replant with its own genes");
    world.wait(GROWN_SECONDS.value + 1);
    uint slot = world.game.world.graph.slotOf(world.game.characterState.position.node).value;
    float fit = expressionIn(materialNamed("base:flower"), world.game.world.graph.stateAt(slot).climate.climate());
    uint predicted = 1 + cast(uint) roundf(MOST_EXTRA_YIELD * fit);
    world.check(world.breakBlock(), "could not break the ripe flower");
    uint gathered = world.game.inventory.countOfKind(back);
    world.link(Topic.climate, Topic.plants, "A ripe plant yields one of itself and up to two more, in proportion to how well the climate suits it.", gathered == predicted && world.game.compounds.length == 0, Measure.of("how well the climate suits it (0 to 1)", fit), Measure.of("yielded", gathered), Measure.of("predicted", predicted));
}

void flatLearning(ref Script world) {
    world.plane(degrees(0));
    walk.spawn(world);
    world.look(degrees(0), degrees(AHEAD_DEGREES));
    uint sifting = insightNamed(SIFTING).id;
    world.game.inventory.gain(Stack(named("base:dirt"), recipes()[recipeNamed(SIFT_SAND_RECIPE)].needs[0].count));
    world.claim(Topic.learning, "No recipe waits on an insight: what an insight describes can be made before it is noticed.", !world.game.noticed.has(sifting) && world.game.planOf(recipeNamed(SIFT_SAND_RECIPE)).shortfall.count == 0, Measure.of("insight not yet noticed", SIFTING), Measure.of("recipe", SIFT_SAND_RECIPE));
    world.check(walk.isMaterial(world.targetMaterial(), "base:dirt") && world.breakBlock(), "could not break the dirt ground");
    world.claim(Topic.learning, "Breaking the right block is noticed, and the journal keeps what was noticed.", world.game.noticed.has(sifting) && world.game.notes.ptr[world.game.notes.length - 1].kind == NoteKind.learned, Measure.of("block broken", walk.GROUND), Measure.of("insight", SIFTING));
    world.game.rules = Rules.creative;
    world.game.inventory = Inventory.init;
    world.game.inventory.gain(Stack(named("base:sand"), recipes()[recipeNamed(GLASS_RECIPE)].needs[0].count));
    world.check(world.game.craft(recipeNamed(GLASS_RECIPE)), "could not queue glass");
    world.wait(secondsOf(GLASS_RECIPE) + MINING_SLACK_SECONDS);
    world.claim(Topic.learning, "Finishing work at a station can teach an insight.", world.game.noticed.has(insightNamed(CHARRING).id), Measure.of("recipe worked", GLASS_RECIPE), Measure.of("insight", CHARRING));
}

void flatRefund(ref Script world) {
    world.plane(degrees(0));
    walk.spawn(world);
    world.game.inventory = Inventory.init;
    Item wood = named("base:oak-wood");
    Item filler = named("base:dirt");
    world.game.inventory.slots[0] = Stack(wood, 1);
    foreach (slot; 1 .. SLOT_COUNT) {
        world.game.inventory.slots[slot] = Stack(filler, STACK_LIMIT);
    }
    world.check(world.game.craft(recipeNamed(PLANKS_RECIPE)), "could not queue planks from one wood");
    world.step();
    world.check(world.game.crafts.length == 1 && world.game.crafts.ptr[0].started == Readiness.ready && world.game.inventory.countOf(wood) == 0, "the planks did not start with the wood taken out of the inventory");
    world.game.inventory.slots[0] = Stack(filler, STACK_LIMIT);
    Time cancelled = world.time();
    world.game.cancelCraft(0);
    bool told = notedSince(world, NoteKind.inventoryFull, cancelled);
    world.claim(Topic.crafting, "Cancelling work whose ingredients no longer fit in the inventory says what was lost.", told && world.game.crafts.length == 0 && world.game.inventory.countOf(wood) == 0, Measure.of("steps left queued", world.game.crafts.length), Measure.of("wood held after", world.game.inventory.countOf(wood)));
}

enum uint SAVED_WOOD = 2;
enum uint CARRIED_DIRT = 3;

void queuePlanksTwice(ref Script world, Item wood) {
    world.game.inventory = Inventory.init;
    world.game.inventory.gain(Stack(wood, SAVED_WOOD));
    world.check(world.game.craft(recipeNamed(PLANKS_RECIPE)) && world.game.craft(recipeNamed(PLANKS_RECIPE)), "could not queue planks twice from %u wood", SAVED_WOOD);
}

void saveQueue(ref Script world) {
    world.plane(degrees(0));
    walk.spawn(world);
    world.game.rules = Rules.creative;
    Item wood = named("base:spruce-wood");
    Item planks = named("base:wood-planks");
    Item dirt = named("base:dirt");
    queuePlanksTwice(world, wood);
    world.game.keepCompound(starterDoses.ptr[0].molecule, extractOf(PRESS_DOSE), 0);
    world.game.apply(acting(&chooseCompound, 0), Click.primary);
    world.check(world.game.synthesize(synthesisNamed(PRESS_DOSE)), "could not queue a pressing after the planks");
    world.step();
    size_t queued = world.game.crafts.length;
    world.check(queued == 3 && world.game.crafts.ptr[0].started == Readiness.ready && world.game.crafts.ptr[1].started == Readiness.pending && world.game.inventory.countOf(wood) == 0 && world.game.compounds.ptr[0].raw == 0, "the first planks did not start alone on the first step with all %zu steps paid for", queued);
    world.game.carried = Stack(dirt, CARRIED_DIRT);
    Writer writer;
    writeGame(world.game, writer);
    ClientConfig config;
    Game copy = Game.make(world.game.world.graph.worldgen, config.reach);
    copy.supply = ChunkSupply.onDemand;
    copy.rules = Rules.creative;
    SaveData data;
    const(char)* problem = readGame(writer.bytes.slice(), copy, data);
    world.check(problem is null, "the save written with work queued did not read back: it %s", problem);
    if (problem is null) {
        applyEdits(copy, data);
        StructureProblem placed = copy.placeStructure();
        world.check(!placed.isPresent, "the copy's world did not start");
        applyState(copy, data);
        size_t alike = 0;
        foreach (index, ref crafting; copy.crafts.slice()) {
            if (index < queued && crafting == world.game.crafts.ptr[index]) {
                alike += 1;
            }
        }
        uint waiting = 0;
        foreach (ref job; copy.jobs.slice()) {
            waiting += job.held.countOf(wood);
        }
        world.link(Topic.saves, Topic.crafting, "A save keeps the crafting queue: every step in its order, with what it has taken, what its job still holds and the time it has left.", copy.crafts.length == queued && alike == queued && copy.jobs.length == world.game.jobs.length && waiting == SAVED_WOOD - 1, Measure.of("steps queued", queued), Measure.of("steps loaded back the same", alike), Measure.of("wood still held by a job", waiting));
        world.claim(Topic.saves, "A stack that was being carried between slots when the game was saved is in the inventory when the save is loaded.", copy.carried.isEmpty && copy.inventory.countOf(dirt) == CARRIED_DIRT, Measure.of("carried", CARRIED_DIRT), Measure.of("in the inventory after loading", copy.inventory.countOf(dirt)));
        world.check(data.time.value == world.game.time.value && data.time.value > 0, "the save holds the clock at %.3f s, the game is at %.3f s", data.time.value, world.game.time.value);
        copy.cancelCraft(0);
        world.link(Topic.saves, Topic.crafting, "Cancelling a step that was loaded from a save gives back what it had taken.", copy.crafts.length == queued - 1 && copy.inventory.countOf(wood) == 1, Measure.of("steps left queued", copy.crafts.length), Measure.of("wood back in the inventory", copy.inventory.countOf(wood)));
        double left = secondsOf(PLANKS_RECIPE) + syntheses()[synthesisNamed(PRESS_DOSE).id].time.value + MINING_SLACK_SECONDS;
        while (left > 0) {
            copy.step(FrameInput.init, world.timestep);
            left -= world.timestep.value;
        }
        uint yield = recipes()[recipeNamed(PLANKS_RECIPE)].yield;
        world.link(Topic.saves, Topic.crafting, "Work that was loaded from a save is done as it would have been.", copy.crafts.length == 0 && copy.inventory.countOf(planks) == yield && copy.compounds.length == 1 && copy.compounds.ptr[0].doses == 1, Measure.of("steps left queued", copy.crafts.length), Measure.of("planks made", copy.inventory.countOf(planks)), Measure.of("predicted", yield));
    }
    data.release();
    copy.release();
    writer.bytes.release();
}

void saveLostRecipe(ref Script world) {
    world.plane(degrees(0));
    walk.spawn(world);
    Item wood = named("base:spruce-wood");
    queuePlanksTwice(world, wood);
    world.step();
    world.check(world.game.crafts.length == 2 && world.game.crafts.ptr[0].started == Readiness.ready && world.game.inventory.countOf(wood) == 0, "the first planks did not start with both woods out of the inventory");
    Writer writer;
    writeGame(world.game, writer);
    ClientConfig config;
    Game copy = Game.make(world.game.world.graph.worldgen, config.reach);
    copy.supply = ChunkSupply.onDemand;
    SaveData data;
    const(char)* problem = readGame(writer.bytes.slice(), copy, data);
    world.check(problem is null, "the save written with planks queued did not read back: it %s", problem);
    if (problem is null) {
        applyEdits(copy, data);
        StructureProblem placed = copy.placeStructure();
        world.check(!placed.isPresent, "the copy's world did not start");
        data.remap.recipes.ptr[recipeNamed(PLANKS_RECIPE)] = MaybeIndex!uint.init;
        applyState(copy, data);
        world.link(Topic.saves, Topic.crafting, "A queued step whose recipe the loaded content does not define is dropped when the save is loaded, and what its job held and had taken goes back to the inventory.", copy.crafts.length == 0 && copy.jobs.length == 0 && copy.inventory.countOf(wood) == SAVED_WOOD, Measure.of("steps saved", world.game.crafts.length), Measure.of("steps loaded", copy.crafts.length), Measure.of("wood saved in the queue", SAVED_WOOD), Measure.of("wood in the inventory after loading", copy.inventory.countOf(wood)));
    }
    data.release();
    copy.release();
    writer.bytes.release();
}

enum uint LEAVES_SLOT = 2;

enum uint PRESS_SLOT = HOTBAR_SLOTS - 1;

bool isLastTold(ref Script world, Told told) {
    if (world.game.notes.length == 0) {
        return false;
    } else {
        const(Note)* last = &world.game.notes.ptr[world.game.notes.length - 1];
        return last.kind == NoteKind.written && last.code == told;
    }
}

bool toldSince(ref Script world, Told told, Time since) {
    size_t index = 0;
    while (index < world.game.notes.length && !(world.game.notes.ptr[index].kind == NoteKind.written && world.game.notes.ptr[index].code == told && world.game.notes.ptr[index].at >= since)) {
        index += 1;
    }
    return index < world.game.notes.length;
}

Maybe!uint slotHolding(ref Script world, Stack kind) {
    uint slot = 0;
    while (slot < SLOT_COUNT && !(!world.game.inventory.slots[slot].isEmpty && world.game.inventory.slots[slot].isSameKind(kind))) {
        slot += 1;
    }
    if (slot < SLOT_COUNT) {
        return Maybe!uint.of(slot);
    } else {
        return Maybe!uint.init;
    }
}

void geneHarvest(ref Script world) {
    world.plane(degrees(0));
    walk.spawn(world);
    world.game.rules = Rules.creative;
    world.material(LEAVES_SLOT + 1);
    world.look(degrees(0), degrees(AHEAD_DEGREES));
    world.check(world.placeBlock() && walk.isMaterial(world.targetMaterial(), "base:oak-leaves"), "could not place the leaves");
    world.step();
    world.check(world.game.pharma.sight == Sight.living, "aiming at leaves does not read them as living");
    Molecule product = world.game.pharma.living.product;
    uint leaves = world.game.inventory.countOf(named("base:oak-leaves"));
    world.check(world.breakBlock() && world.game.compounds.length == 0 && world.game.inventory.countOf(named("base:oak-leaves")) == leaves + 1, "breaking the leaves gave %zu compounds and %u leaves back", world.game.compounds.length, world.game.inventory.countOf(named("base:oak-leaves")) - leaves);
    Maybe!uint held = Maybe!uint.init;
    foreach (slot; 0 .. SLOT_COUNT) {
        if (world.game.inventory.slots[slot].genes.exists) {
            held = Maybe!uint.of(slot);
        }
    }
    world.check(held.exists && productOf(materialNamed("base:oak-leaves"), world.game.inventory.slots[held.value].genes.value) == product, "the broken leaves did not keep the genes that make the compound they read as");
    if (!world.isFailed) {
        Stack kind = world.game.inventory.slots[held.value].front();
        world.game.inventory.slots[PRESS_SLOT] = Stack(named("pharmacology:press"), 1);
        world.material(PRESS_SLOT + 1);
        world.check(world.placeBlock() && world.interact() && world.game.screen == Screen.station, "could not place and open the press");
        world.check(world.game.pressLiving(held.value), "could not queue pressing the leaves");
        world.step();
        world.check(world.game.inventory.countOfKind(kind) == 0, "pressing did not take the leaves");
        world.game.cancelCraft(0);
        world.check(world.game.inventory.countOfKind(kind) == 1, "cancelling the pressing did not give the same leaves back");
        Maybe!uint again = slotHolding(world, kind);
        world.check(again.exists && world.game.pressLiving(again.value), "could not queue pressing the leaves again");
        world.wait(syntheses()[synthesisNamed(PRESS_EXTRACT).id].time.value + MINING_SLACK_SECONDS);
        world.link(Topic.plants, Topic.chemistry, "Pressing a living block yields extract of the compound that its genes make.", world.game.compounds.length == 1 && world.game.compounds.ptr[0].molecule == product && world.game.compounds.ptr[0].raw == extractOf(PRESS_EXTRACT), Measure.of("compounds held", world.game.compounds.length), Measure.of("extract expected", extractOf(PRESS_EXTRACT)));
        world.check(world.game.inventory.countOfKind(kind) == 0, "the pressed leaves are still held");
    }
}

void geneKept(ref Script world) {
    world.plane(degrees(0));
    walk.spawn(world);
    Lineage genes = Lineage([41, 42, 43, 44]);
    Stack kind = Stack.ofLiving(named("base:oak-leaves"), 1, genes, Sorting.unsorted);
    world.game.inventory.slots[0] = kind;
    world.material(1);
    world.look(degrees(0), degrees(AHEAD_DEGREES));
    world.check(world.placeBlock() && world.game.inventory.countOfKind(kind) == 0, "could not place the leaves");
    world.step();
    world.check(world.game.pharma.sight == Sight.living && world.game.pharma.living.product == productOf(materialNamed("base:oak-leaves"), genes), "placed leaves read as another compound than their genes make");
    world.claim(Topic.plants, "A living block that is placed and broken again comes back with the genes it had.", world.breakBlock() && world.game.inventory.countOfKind(kind) == 1);
}

void geneSynthesis(ref Script world) {
    world.plane(degrees(0));
    walk.spawn(world);
    world.game.rules = Rules.creative;
    Molecule starter = starterDoses.ptr[0].molecule;
    world.game.keepCompound(starter, 2 * extractOf(PRESS_DOSE), 0);
    world.game.apply(acting(&chooseCompound, 0), Click.primary);
    Synthesis press = synthesisNamed(PRESS_DOSE);
    world.check(world.game.synthesize(press) && world.game.synthesize(press), "could not queue two pressings");
    world.wait(2 * syntheses()[press.id].time.value + MINING_SLACK_SECONDS);
    world.claim(Topic.chemistry, "A press turns extract into doses.", world.game.compounds.ptr[0].doses == 2 && world.game.compounds.ptr[0].raw == 0, Measure.of("extract before", 2 * extractOf(PRESS_DOSE)), Measure.of("doses after", world.game.compounds.ptr[0].doses), Measure.of("extract after", world.game.compounds.ptr[0].raw));
    uint changing = 0;
    while (changing < syntheses().length && (syntheses()[changing].reaction == Reaction.press || synthesized(starter, Synthesis(cast(ubyte) changing)).value == starter)) {
        changing += 1;
    }
    world.check(changing < syntheses().length, "no lab operation changes the starter compound");
    if (!world.isFailed) {
        Synthesis chosen = Synthesis(cast(ubyte) changing);
        Item reagent = syntheses()[chosen.id].reagent;
        world.claim(Topic.chemistry, "A lab reaction whose reagent is missing is not queued, and takes nothing.", !world.game.synthesize(chosen) && world.game.crafts.length == 0 && world.game.compounds.ptr[0].doses == 2, Measure.of("crafts queued", world.game.crafts.length), Measure.of("doses still held", world.game.compounds.ptr[0].doses));
        world.game.inventory.gain(Stack(reagent, 1));
        world.claim(Topic.chemistry, "Queuing a lab reaction takes its reagent and its dose at once.", world.game.synthesize(chosen) && world.game.inventory.countOf(reagent) == 0 && world.game.compounds.ptr[0].doses == 1, Measure.of("reagent left", world.game.inventory.countOf(reagent)), Measure.of("doses left", world.game.compounds.ptr[0].doses));
        world.wait(syntheses()[chosen.id].time.value + MINING_SLACK_SECONDS);
        world.check(world.game.compounds.length == 2 && world.game.compounds.ptr[1].doses == 1 && world.game.compounds.ptr[1].molecule == synthesized(starter, chosen).value, "the lab made %zu compounds", world.game.compounds.length);
        world.claim(Topic.chemistry, "A dose cannot be taken by a route whose device the player lacks.", !world.game.takeDose(routeIndexOf(Route.injected)), Measure.of("route", "injected"));
        world.link(Topic.chemistry, Topic.body, "Taking a dose puts its compound into the body.", world.game.takeDose(routeIndexOf(Route.ingested)) && world.game.organism.body.count == 1, Measure.of("compounds in the body", world.game.organism.body.count));
    }
}

void geneCompounds(ref Script world) {
    world.plane(degrees(0));
    walk.spawn(world);
    foreach (cell; 0 .. GRID_CELLS) {
        world.game.keepCompound(Molecule.init.withFragment(cell, Fragment.of(0)), 1, 0);
    }
    uint held = 0;
    foreach (cell; 0 .. GRID_CELLS) {
        MaybeIndex!uint found = world.game.compoundIndexOf(Molecule.init.withFragment(cell, Fragment.of(0)));
        if (found.exists && world.game.compounds.ptr[found.value].raw == 1) {
            held += 1;
        }
    }
    world.claim(Topic.chemistry, "Every compound the player comes to hold is kept, however many there are.", held == GRID_CELLS, Measure.of("distinct compounds kept", GRID_CELLS), Measure.of("still held with their extract", held));
}

enum uint QUEUED_BATCHES = 27;

void flatQueue(ref Script world) {
    world.plane(degrees(0));
    walk.spawn(world);
    world.game.inventory = Inventory.init;
    Item wood = named("base:birch-wood");
    Item planks = named("base:wood-planks");
    uint yield = recipes()[recipeNamed(PLANKS_RECIPE)].yield;
    world.game.inventory.gain(Stack(wood, QUEUED_BATCHES));
    uint queued = 0;
    while (queued < QUEUED_BATCHES && world.game.craft(recipeNamed(PLANKS_RECIPE))) {
        queued += 1;
    }
    world.claim(Topic.crafting, "Queuing a craft takes its ingredients out of the inventory at once.", queued == QUEUED_BATCHES && world.game.inventory.countOf(wood) == 0, Measure.of("batches queued", queued), Measure.of("wood left in the inventory", world.game.inventory.countOf(wood)));
    world.claim(Topic.crafting, "A craft whose ingredients are missing is not queued.", !world.game.craft(recipeNamed(PLANKS_RECIPE)) && world.game.crafts.length == QUEUED_BATCHES, Measure.of("crafts queued", world.game.crafts.length));
    world.wait(QUEUED_BATCHES * secondsOf(PLANKS_RECIPE) + MINING_SLACK_SECONDS);
    world.claim(Topic.crafting, "The crafting queue has no size: every batch queued is made.", world.game.crafts.length == 0 && world.game.inventory.countOf(planks) == QUEUED_BATCHES * yield, Measure.of("batches queued", QUEUED_BATCHES), Measure.of("planks made", world.game.inventory.countOf(planks)), Measure.of("predicted", QUEUED_BATCHES * yield));
}

void flatSeveral(ref Script world) {
    world.plane(degrees(0));
    walk.spawn(world);
    world.game.inventory = Inventory.init;
    Item wood = named("base:birch-wood");
    world.game.inventory.gain(Stack(wood, QUEUED_BATCHES));
    UiAction make = {kind: UiKind.craft, index: recipeNamed(PLANKS_RECIPE)};
    world.game.apply(make, Click.secondary);
    world.claim(Topic.crafting, "A secondary click on a recipe queues three of it.", world.game.crafts.length == FEW_CRAFTS && world.game.inventory.countOf(wood) == QUEUED_BATCHES - FEW_CRAFTS, Measure.of("crafts queued", world.game.crafts.length), Measure.of("wood left in the inventory", world.game.inventory.countOf(wood)));
    world.game.apply(make, Click.quick);
    world.claim(Topic.crafting, "A quick click on a recipe queues as many of it as the inventory can pay for.", world.game.crafts.length == QUEUED_BATCHES && world.game.inventory.countOf(wood) == 0, Measure.of("wood held at first", QUEUED_BATCHES), Measure.of("crafts queued", world.game.crafts.length), Measure.of("wood left in the inventory", world.game.inventory.countOf(wood)));
    Time asked = world.time();
    world.game.apply(make, Click.quick);
    world.claim(Topic.crafting, "Asking for more of a recipe when none can be paid for queues nothing and says what is missing.", world.game.crafts.length == QUEUED_BATCHES && notedSince(world, NoteKind.missingIngredients, asked), Measure.of("crafts queued", world.game.crafts.length));
}

uint routeIndexOf(Route route) {
    uint index = 0;
    while (doseRoutes()[index].route != route) {
        index += 1;
    }
    return index;
}

void flatPlace(ref Script world) {
    world.plane(degrees(0));
    walk.spawn(world);
    world.look(degrees(0), degrees(walk.STRAIGHT_DOWN_DEGREES));
    bool placed = world.placeBlock();
    world.claim(Topic.blocks, "A block cannot be placed where the body stands.", !placed);
    world.wait(0.5);
    walk.checkStanding(world, "after the refused placement");
    world.look(degrees(0), degrees(AHEAD_DEGREES - walk.STRAIGHT_DOWN_DEGREES));
    placed = world.placeBlock();
    world.check(placed, "placing a block ahead succeeds");
    world.wait(0.5);
    walk.checkStanding(world, "after placing ahead");
}

enum double STEP_WALK_SECONDS = 3;
enum float CLIMB_SPEED_TOLERANCE = 1.5f;

void flatStair(ref Script world) {
    world.plane(degrees(0));
    walk.spawn(world);
    walk.checkStanding(world, "before building");
    walk.buildStep(world);
    float standing = world.altitude().value;
    Motion motion;
    walk.trackMotion(world, &motion);
    double deadline = world.time().value + STEP_WALK_SECONDS;
    world.hold(Key.forward);
    bool onStep = walk.probeOnStep(world, standing);
    while (!world.isFailed && world.time().value < deadline && !onStep) {
        world.step();
        onStep = walk.probeOnStep(world, standing);
    }
    world.release(Key.forward);
    world.wait(walk.SETTLE_SECONDS);
    world.onStep(StepHook.init);
    world.claim(Topic.movement, "The body walks up a step one block high without leaving the ground.", motion.offGround == 0, Measure.of("steps spent off the ground", motion.offGround));
    walk.checkOnStep(world, standing, "after walking onto the step");
}

struct Stepover {
    Motion motion;
    float fastest = 0;
    float traveled = 0;
}

void stepoverHook(ref Script world, void* context) {
    Stepover* over = cast(Stepover*) context;
    over.fastest = higherOf(over.fastest, (world.traveled().value - over.traveled) / world.timestep.value);
    over.traveled = world.traveled().value;
    walk.observe(world, over.motion);
}

void flatStepover(ref Script world) {
    world.plane(degrees(0));
    walk.spawn(world);
    walk.buildStep(world);
    float standing = world.altitude().value;
    Stepover over = Stepover(walk.motionFrom(world), 0, world.traveled().value);
    world.onStep(StepHook(&stepoverHook, &over));
    double deadline = world.time().value + STEP_WALK_SECONDS;
    world.hold(Key.forward);
    bool onStep = walk.probeOnStep(world, standing);
    while (!world.isFailed && world.time().value < deadline && !onStep) {
        world.step();
        onStep = walk.probeOnStep(world, standing);
    }
    world.release(Key.forward);
    world.onStep(StepHook.init);
    onStep = walk.probeOnStep(world, standing);
    world.check(onStep, "walked onto the step");
    world.check(over.motion.offGround == 0, "left the ground on %u steps walking up a one-block step", over.motion.offGround);
    world.check(over.fastest <= walk.SPEED * CLIMB_SPEED_TOLERANCE, "moved at %.4f stepping up, walking is %.4f", over.fastest, walk.SPEED);
}

enum float DROP_HEIGHT = 0.3f;
enum Time DROP_STEP = Time(2.0f);
enum double TIMESTEP_WALK_SECONDS = 2;
enum Time LONG_STEP = Time(0.5f);
enum double TIMESTEP_CLIMB_SECONDS = 4;
enum Time CLIMB_STEP = Time(0.25f);
enum double STOP_SECONDS = 0.5;
enum float WALK_TOLERANCE = 0.001f;

float walkFromRest(ref Script world, Time dt) {
    float start = world.traveled().value;
    world.hold(Key.forward);
    world.wait(TIMESTEP_WALK_SECONDS, dt);
    world.release(Key.forward);
    float walked = world.traveled().value - start;
    world.wait(STOP_SECONDS);
    return walked;
}

void flatTimestep(ref Script world) {
    world.plane(degrees(0));
    walk.spawn(world);
    walk.checkStanding(world, "before the drop");
    world.mode(MovementMode.fly);
    world.press(DROP_HEIGHT / walk.FLY_SPEED, Key.up);
    world.step();
    world.mode(MovementMode.walk);
    world.step(DROP_STEP);
    walk.checkStanding(world, "after one 2.0 s step falling 0.30");
    float inShortSteps = walkFromRest(world, world.timestep);
    float inLongSteps = walkFromRest(world, LONG_STEP);
    world.claim(Topic.movement, "Walking covers the same distance whether time advances in long steps or in short ones.", fabs(inLongSteps - inShortSteps) <= WALK_TOLERANCE, Measure.of("walked in long steps", inLongSteps), Measure.of("long step (seconds)", LONG_STEP.value), Measure.of("walked in short steps", inShortSteps), Measure.of("short step (seconds)", world.timestep.value));
    walk.checkStanding(world, "after walking in long steps");
    walk.buildStep(world);
    float standing = world.altitude().value;
    walk.climbForward(world, TIMESTEP_CLIMB_SECONDS, CLIMB_STEP, ClimbGoal.ontoStep, standing);
    world.wait(walk.SETTLE_SECONDS);
    walk.checkOnStep(world, standing, "after jumping onto the step in 0.25 s steps");
}

immutable int[4] HEADINGS = [0, 90, 180, 270];
immutable float[4] AXIS_HEIGHTS = [0.25f, 1.0f, 2.0f, 3.0f];
enum double LEG_SECONDS = 3;
enum float LEAST_WALKED_FRACTION = 0.95f;

void flatWalk(ref Script world) {
    world.plane(degrees(0));
    walk.spawn(world);
    walk.checkStanding(world, "after landing");
    Motion motion;
    walk.trackMotion(world, &motion);
    foreach (heading; HEADINGS) {
        float start = world.traveled().value;
        world.press(LEG_SECONDS, Key.forward);
        world.wait(0.5);
        float walked = world.traveled().value - start;
        float free = walk.SPEED * LEG_SECONDS;
        world.claim(Topic.movement, "On level ground the body walks at its walk speed whichever way it faces.", walked >= LEAST_WALKED_FRACTION * free, Measure.of("heading (degrees)", heading), Measure.of("walked", walked), Measure.of("expected", free), Measure.of("walk speed setting", world.game.character.walkSpeed.value));
        walk.checkStanding(world, "after a heading");
        world.turn(degrees(90), degrees(0), 0.5);
    }
    world.press(LEG_SECONDS, Key.forward, Key.up);
    world.wait(1);
    world.onStep(StepHook.init);
    walk.checkSpeedLimit(world, motion);
    walk.checkStanding(world, "after hopping");
}

enum uint WALL_BLOCKS = 2;
enum double WALL_APPROACH_SECONDS = 0.3;
enum double WALL_PUSH_SECONDS = 2.5;
enum float CONTACT_SPEED_FRACTION = 0.8f;
enum float MOST_CLIMB = 0.0025f;
enum float VERTICAL_SPEED_TOLERANCE = 0.005f;

void flatWall(ref Script world) {
    world.plane(degrees(0));
    walk.spawn(world);
    walk.checkStanding(world, "before building");
    walk.buildWall(world, WALL_BLOCKS);
    world.wait(2);
    walk.checkStanding(world, "back on the floor");
    float standing = world.altitude().value;
    Motion motion;
    walk.trackMotion(world, &motion);
    float start = world.traveled().value;
    world.hold(Key.forward);
    world.wait(WALL_APPROACH_SECONDS + WALL_PUSH_SECONDS);
    world.release(Key.forward);
    world.onStep(StepHook.init);
    float walked = world.traveled().value - start;
    float free = walk.SPEED * (WALL_APPROACH_SECONDS + WALL_PUSH_SECONDS);
    world.check(walked <= CONTACT_SPEED_FRACTION * free, "walked %.4f of a free %.4f, so the wall was not reached", walked, free);
    world.claim(Topic.movement, "The body cannot walk up a wall two blocks high.", motion.highest - standing <= MOST_CLIMB, Measure.of("climbed", motion.highest - standing));
    world.check(motion.rise <= VERTICAL_SPEED_TOLERANCE, "vertical speed reached %.4f against the wall", motion.rise);
    world.check(motion.offGround == 0, "left the ground on %u steps walking into the wall", motion.offGround);
    walk.checkSpeedLimit(world, motion);
    walk.checkStanding(world, "against the wall");
}

enum double DRIFT_CLIMB_SECONDS = 2;
enum uint DRIFT_LEGS = 6;
enum float DRIFT_LEG_DISTANCE = 1.0f;
enum Length DRIFT_RADIUS = Length(2.0f);
enum float MOST_DRIFT = 1e-3f;

void liveDrift(ref Script world) {
    world.live();
    world.mode(MovementMode.fly);
    world.press(DRIFT_CLIMB_SECONDS, Key.up);
    foreach (leg; 0 .. DRIFT_LEGS) {
        world.press(DRIFT_LEG_DISTANCE / walk.FLY_SPEED, Key.forward);
        float drift = world.probeFrameDrift(DRIFT_RADIUS).value;
        world.claim(Topic.world, "However far the player flies, cells are drawn where they are.", drift < MOST_DRIFT, Measure.of("flown", (leg + 1) * DRIFT_LEG_DISTANCE), Measure.of("largest offset", drift));
    }
}

enum uint BENCH_SLOT = 7;

void geneBreedSplice(ref Script world) {
    world.plane(degrees(0));
    walk.spawn(world);
    Lineage first = Lineage([11, 12, 13, 14]);
    Lineage second = Lineage([21, 22, 23, 24]);
    Stack mother = Stack.ofLiving(named("base:flower"), 2, first, Sorting.sorted);
    Stack father = Stack.ofLiving(named("base:flower"), 1, second, Sorting.sorted);
    world.game.inventory.slots[HOTBAR_SLOTS] = mother;
    world.game.inventory.slots[HOTBAR_SLOTS + 1] = father;
    world.material(BENCH_SLOT);
    world.look(degrees(0), degrees(AHEAD_DEGREES));
    world.check(world.placeBlock() && walk.isMaterial(world.targetMaterial(), "pharmacology:bench"), "could not place the bench");
    world.interact();
    world.check(world.game.screen == Screen.machine && world.game.machineScreen == benchScreen, "right clicking the bench did not open it");
    world.check(world.game.chosen[0] == MaybeIndex!uint.of(HOTBAR_SLOTS) && world.game.chosen[1] == MaybeIndex!uint.of(HOTBAR_SLOTS + 1), "opening the bench did not mark the two flowers");
    uint flowers = world.game.inventory.countOf(named("base:flower"));
    world.check(world.cross(), "could not cross the flowers");
    world.check(world.game.inventory.countOfKind(mother) == 1 && world.game.inventory.countOfKind(father) == 1 && world.game.inventory.countOf(named("base:flower")) == flowers, "crossing did not turn one of the first flower into the cross: %u first, %u second, %u flowers from %u", world.game.inventory.countOfKind(mother), world.game.inventory.countOfKind(father), world.game.inventory.countOf(named("base:flower")), flowers);
    Maybe!uint childSlot = Maybe!uint.init;
    foreach (slot; 0 .. SLOT_COUNT) {
        Stack stack = world.game.inventory.slots[slot];
        if (!stack.isEmpty && stack.genes.exists && !stack.isSameKind(mother) && !stack.isSameKind(father)) {
            childSlot = Maybe!uint.of(slot);
        }
    }
    world.check(childSlot.exists, "the cross is not in the inventory");
    if (!world.isFailed) {
        Lineage child = world.game.inventory.slots[childSlot.value].genes.value;
        uint inherited = 0;
        foreach (index; 0 .. LINEAGE_SEEDS) {
            if (child.seeds[index] == first.seeds[index] || child.seeds[index] == second.seeds[index]) {
                inherited += 1;
            }
        }
        world.claim(Topic.breeding, "A cross takes each of its genes from one of its two parents, apart from the occasional mutation.", inherited >= LINEAGE_SEEDS - 1, Measure.of("genes taken from a parent", inherited), Measure.of("genes in all", LINEAGE_SEEDS));
        uint genes = world.game.organism.genome.count;
        world.link(Topic.breeding, Topic.body, "Splicing uses up the plant and adds one gene to the player's genome.", world.splice() && world.game.organism.genome.count == genes + 1 && world.game.inventory.countOfKind(mother) == 0, Measure.of("genes before", genes), Measure.of("genes after", world.game.organism.genome.count));
    }
}

void geneGrow(ref Script world) {
    world.plane(degrees(0));
    walk.spawn(world);
    Lineage genes = Lineage([31, 32, 33, 34]);
    world.game.inventory.slots[0] = Stack.ofLiving(named("base:flower"), 1, genes, Sorting.unsorted);
    world.material(1);
    world.look(degrees(0), degrees(AHEAD_DEGREES));
    world.check(world.placeBlock() && world.game.inventory.slots[0].isEmpty, "planting did not use the flower");
    world.step();
    world.check(world.game.pharma.sight == Sight.living && world.game.pharma.living.growth == Ripeness.growing && world.game.pharma.living.product == productOf(materialNamed("base:flower"), genes), "aiming at the planted flower does not read it as a growing plant with its genes");
    world.wait(GROWN_SECONDS.value + 1);
    world.claim(Topic.plants, "A planted plant reads as growing at first, and as ripe once its growing time has passed.", world.game.pharma.living.growth == Ripeness.ripe, Measure.of("growing time (seconds)", GROWN_SECONDS.value));
}

void geneWild(ref Script world) {
    world.plane(degrees(0));
    walk.spawn(world);
    world.game.inventory = Inventory.init;
    world.look(degrees(0), degrees(AHEAD_DEGREES));
    Maybe!Placement spot = world.game.world.placementTarget();
    world.check(spot.exists && world.game.world.setVoxel(spot.value.chunk, spot.value.coords, materialNamed("base:flower")), "could not set a flower into the world");
    world.step();
    world.check(world.game.pharma.sight == Sight.living && world.game.pharma.living.growth == Ripeness.wild, "a flower that nobody planted does not read as wild");
    uint slot = world.game.world.graph.slotOf(world.game.characterState.position.node).value;
    float fit = expressionIn(materialNamed("base:flower"), world.game.world.graph.stateAt(slot).climate.climate());
    world.check(world.breakBlock(), "could not break the wild flower");
    uint gathered = world.game.inventory.countOf(named("base:flower"));
    world.claim(Topic.plants, "Breaking a plant that nobody planted gives one of itself.", gathered == 1, Measure.of("yielded", gathered), Measure.of("a ripe planted one would yield here", 1 + cast(uint) roundf(MOST_EXTRA_YIELD * fit)));
}

enum double HALF_EAT_SECONDS = 0.5;
enum float EATEN_TOLERANCE = 0.01f;

bool notedSince(ref Script world, NoteKind kind, Time since) {
    size_t index = 0;
    while (index < world.game.notes.length && !(world.game.notes.ptr[index].kind == kind && !(world.game.notes.ptr[index].at < since))) {
        index += 1;
    }
    return index < world.game.notes.length;
}

void plantEat(ref Script world) {
    world.plane(degrees(0));
    walk.spawn(world);
    world.game.inventory.slots[0] = Stack(named("base:flower"), 2);
    world.material(1);
    Time tried = world.time();
    world.check(!world.eat() && toldSince(world, Told.noGenes, tried), "ate a flower with no genes of its own");
    Lineage genes = Lineage([51, 52, 53, 54]);
    world.game.inventory.slots[0] = Stack.ofLiving(named("base:flower"), 2, genes, Sorting.unsorted);
    world.pressed(EAT.name);
    world.wait(HALF_EAT_SECONDS);
    world.released(EAT.name);
    world.step();
    world.check(world.game.inventory.slots[0].count == 2 && world.game.organism.body.count == 0, "letting go of eat after %.1f s still ate", HALF_EAT_SECONDS);
    world.check(world.eat() && world.game.inventory.slots[0].count == 1 && world.game.organism.body.count == 1, "holding eat did not eat one flower: %u left, %u molecules in the body", world.game.inventory.slots[0].count, world.game.organism.body.count);
    if (!world.isFailed) {
        const(Body)* body = &world.game.organism.body;
        float eaten = body.species[0].gut.value + body.species[0].blood.value;
        world.link(Topic.plants, Topic.body, "Eating a living block puts one dose of the compound its genes make into the body.", body.species[0].molecule == productOf(materialNamed("base:flower"), genes) && fabs(eaten - PLANT_DOSE.value) < EATEN_TOLERANCE, Measure.of("amount in the body", eaten), Measure.of("one dose", PLANT_DOSE.value));
    }
    world.material(2);
    tried = world.time();
    uint held = world.game.inventory.slots[1].count;
    world.pressed(EAT.name);
    world.step();
    bool told = toldSince(world, Told.nothingToEat, tried);
    world.released(EAT.name);
    world.check(told && world.game.inventory.slots[1].count == held, "ate something that is not living");
}

uint stacksOf(ref Script world, Item item) {
    uint held = 0;
    foreach (ref stack; world.game.inventory.slots) {
        if (!stack.isEmpty && stack.item == item) {
            held += 1;
        }
    }
    return held;
}

void geneUnsorted(ref Script world) {
    world.plane(degrees(0));
    walk.spawn(world);
    world.game.inventory = Inventory.init;
    Item flower = named("base:flower");
    Stack first = Stack.ofLiving(flower, 2, Lineage([61, 62, 63, 64]), Sorting.unsorted);
    Stack second = Stack.ofLiving(flower, 3, Lineage([71, 72, 73, 74]), Sorting.unsorted);
    world.game.store(first);
    world.game.store(second);
    uint together = stacksOf(world, flower);
    world.claim(Topic.plants, "Plants whose compounds the player has not identified share one stack, and each keeps its own genes inside it.", together == 1 && world.game.inventory.countOfKind(first) == 2 && world.game.inventory.countOfKind(second) == 3, Measure.of("stacks held", together), Measure.of("of the first strain", world.game.inventory.countOfKind(first)), Measure.of("of the second strain", world.game.inventory.countOfKind(second)));
    world.game.keepCompound(productOf(materialNamed("base:flower"), first.strains[0].genes), extractOf(PRESS_EXTRACT), 0);
    Maybe!uint apart = slotHolding(world, first);
    world.check(apart.exists, "the first strain is no longer at the front of any stack");
    if (!world.isFailed) {
        Stack known = world.game.inventory.slots[apart.value];
        world.link(Topic.chemistry, Topic.plants, "Once the player holds a compound, the plants that make it leave the unidentified stack for a stack of their own.", known.sorting == Sorting.sorted && known.count == 2 && stacksOf(world, flower) == 2 && world.game.inventory.countOfKind(second) == 3, Measure.of("stacks held", stacksOf(world, flower)), Measure.of("in the identified stack", known.count));
    }
}

void uiKeys(ref Script world) {
    world.plane(degrees(0));
    walk.spawn(world);
    Controls controls = Controls.make();
    string inventory = ACTIONS[Action.inventory].key;
    controls.keyDown(world.game, inventory, KeyStroke.first);
    UiAction shown = {kind: UiKind.sheet, index: sheetNamed(BODY_SHEET)};
    world.game.apply(shown, Click.primary);
    controls.keyDown(world.game, inventory, KeyStroke.first);
    world.check(world.game.screen == Screen.none, "the inventory key did not close the inventory");
    controls.keyDown(world.game, inventory, KeyStroke.first);
    world.check(world.game.screen == Screen.character && world.game.sheet == sheetNamed(INVENTORY_SHEET), "after the body sheet was shown, the inventory key opened sheet %u and not the inventory", world.game.sheet);
    controls.keyDown(world.game, ESCAPE_KEY, KeyStroke.first);
    controls.keyDown(world.game, ACTIONS[Action.journal].key, KeyStroke.first);
    world.check(world.game.screen == Screen.journal, "the journal key did not open the journal");
    Request closed = controls.keyDown(world.game, ESCAPE_KEY, KeyStroke.first);
    Request asked = controls.keyDown(world.game, ESCAPE_KEY, KeyStroke.first);
    world.check(closed == Request.nothing && world.game.screen == Screen.none && asked == Request.menu, "Escape did not close the journal and then ask for the menu");
}

enum double SCREEN_WALK_SECONDS = 1;
enum float SCREEN_DRIFT = 1e-3f;
enum uint PACK_SLOT = HOTBAR_SLOTS + 3;

void uiScreenHolds(ref Script world) {
    world.plane(degrees(0));
    walk.spawn(world);
    world.open(Screen.character);
    float start = world.traveled().value;
    world.press(SCREEN_WALK_SECONDS, Key.forward);
    float walked = world.traveled().value - start;
    world.check(walked < SCREEN_DRIFT, "walked %.5f while the inventory was open", walked);
    Stack first = world.game.inventory.slots[0];
    UiAction pick = {kind: UiKind.slot, index: 0};
    world.game.apply(pick, Click.primary);
    world.check(world.game.inventory.slots[0].isEmpty && world.game.carried == first, "clicking slot 1 did not pick up its stack");
    UiAction drop = {kind: UiKind.slot, index: PACK_SLOT};
    world.game.apply(drop, Click.secondary);
    world.check(world.game.inventory.slots[PACK_SLOT].count == 1 && world.game.carried.count == first.count - 1, "a right click put %u in the pack slot, leaving %u carried", world.game.inventory.slots[PACK_SLOT].count, world.game.carried.count);
    UiAction closing = {kind: UiKind.close};
    world.game.apply(closing, Click.primary);
    world.check(world.game.carried.isEmpty && world.game.inventory.countOf(first.item) == first.count, "closing the inventory lost carried blocks: %u of %u left", world.game.inventory.countOf(first.item), first.count);
    walk.forward(world, SCREEN_WALK_SECONDS, LEAST_FREE_FRACTION);
}

void uiCatalog(ref Script world) {
    world.plane(degrees(0));
    walk.spawn(world);
    world.game.rules = Rules.creative;
    world.game.inventory = Inventory.init;
    world.open(Screen.character);
    UiAction catalog = {kind: UiKind.sheet, index: sheetNamed(CATALOG_SHEET)};
    world.game.apply(catalog, Click.primary);
    Item lab = named("pharmacology:lab");
    UiAction take = {kind: UiKind.takeItem, index: lab.id};
    world.game.apply(take, Click.primary);
    world.check(world.game.sheet == sheetNamed(CATALOG_SHEET) && world.game.carried == Stack(lab, STACK_LIMIT), "the catalog gave %u of item %u, not a stack of labs", world.game.carried.count, world.game.carried.item.id);
    UiAction drop = {kind: UiKind.slot, index: PACK_SLOT};
    world.game.apply(drop, Click.primary);
    Item syringe = named("pharmacology:syringe");
    UiAction one = {kind: UiKind.takeItem, index: syringe.id};
    world.game.apply(one, Click.secondary);
    world.check(world.game.inventory.slots[PACK_SLOT] == Stack(lab, STACK_LIMIT) && world.game.carried == Stack(syringe, 1), "dropping the labs and taking one syringe left %u in the slot and %u carried", world.game.inventory.slots[PACK_SLOT].count, world.game.carried.count);
}

enum uint MENU_WIDTH = 1280;
enum uint MENU_HEIGHT = 720;
enum string SCENE_PICKED = "tower";

uint hotspotsOf(ref const Hud hud, UiKind kind) {
    uint count = 0;
    foreach (ref spot; hud.hotspots.slice()) {
        if (spot.action.kind == kind) {
            count += 1;
        }
    }
    return count;
}

uint sceneNamed(const(char)[] name) {
    uint index = 0;
    while (index < sceneCount() && sceneNameAt(index) != name) {
        index += 1;
    }
    return index;
}

void uiScenes(ref Script world) {
    world.plane(degrees(0));
    walk.spawn(world);
    Hud hud;
    Controls controls = Controls.make();
    FrameMeter meter;
    world.open(Screen.menu);
    hud.build(world.game, controls, meter, MENU_WIDTH, MENU_HEIGHT);
    uint worldsListed = hotspotsOf(hud, UiKind.pickWorld);
    uint scenesListed = hotspotsOf(hud, UiKind.pickScene);
    world.claim(Topic.screens, "Under survival rules the world menu lists every world and no scene.", worldsListed == worldCount() && scenesListed == 0, Measure.of("worlds listed", worldsListed), Measure.of("worlds registered", worldCount()), Measure.of("scenes listed", scenesListed));
    world.game.rules = Rules.creative;
    hud.build(world.game, controls, meter, MENU_WIDTH, MENU_HEIGHT);
    worldsListed = hotspotsOf(hud, UiKind.pickWorld);
    scenesListed = hotspotsOf(hud, UiKind.pickScene);
    world.claim(Topic.screens, "Under creative rules the world menu also lists every debug structure as a scene.", worldsListed == worldCount() && scenesListed == sceneCount(), Measure.of("worlds listed", worldsListed), Measure.of("scenes listed", scenesListed), Measure.of("debug structures registered", sceneCount()));
    uint scene = sceneNamed(SCENE_PICKED);
    world.check(scene < sceneCount(), "no debug structure is named %s", SCENE_PICKED.ptr);
    if (!world.isFailed) {
        UiAction pick = {kind: UiKind.pickScene, index: scene};
        world.game.apply(pick, Click.primary);
        hud.build(world.game, controls, meter, MENU_WIDTH, MENU_HEIGHT);
        uint offered = hotspotsOf(hud, UiKind.playScene);
        StructureProblem problem = restartGame(world.game, worldgenOf(world.game.worlds.picked.value));
        const(char)[] entered = world.game.world.graph.worldgen.structureName();
        world.claim(Topic.screens, "Picking a scene offers to start it, and starting it puts the player in that structure alone.", offered == 1 && !problem.isPresent && entered == SCENE_PICKED, Measure.of("buttons that start the scene", offered));
    }
    hud.release();
}

enum uint COLLECTOR_SLOT = 8;
enum double COLLECTING_SECONDS = 30;
enum float COLLECTED_TOLERANCE = 1e-3f;

void plantCollector(ref Script world) {
    world.plane(degrees(0));
    walk.spawn(world);
    world.material(COLLECTOR_SLOT);
    world.look(degrees(0), degrees(AHEAD_DEGREES));
    world.check(world.placeBlock(), "could not place the collector");
    world.wait(COLLECTING_SECONDS);
    world.interact();
    world.check(world.game.screen == Screen.machine && world.game.machineScreen == collectorScreen, "right clicking the collector did not open it");
    world.game.breatheMachine();
    const(Body)* body = &world.game.organism.body;
    world.check(body.count == GAS_COUNT, "breathing the collected air dosed %u gases", body.count);
    if (!world.isFailed) {
        uint slot = world.game.world.graph.slotOf(world.game.characterState.position.node).value;
        AirMix air = airOf(world.game.world.graph.stateAt(slot).climate.climate());
        float expected = air.fractions[0].value * COLLECTION_RATE.value * cast(float) COLLECTING_SECONDS;
        float held = body.species[0].lung.value + body.species[0].blood.value;
        world.link(Topic.air, Topic.body, "A collector gathers a gas at its level in the local air times the collection rate, and breathing it in puts that much into the body.", fabs(held - expected) < COLLECTED_TOLERANCE + expected * 0.05f, Measure.of("seconds collecting", COLLECTING_SECONDS), Measure.of("first gas breathed in", held), Measure.of("predicted", expected));
        world.game.breatheMachine();
        float again = body.species[0].lung.value + body.species[0].blood.value;
        world.check(fabs(again - held) < COLLECTED_TOLERANCE, "collecting again at once added %.4f", again - held);
    }
}

enum uint BEACON_SLOT = 9;
enum float BEACON_AWAY = 6.0f;
enum float BEACON_DISTANCE_TOLERANCE = 0.3f;
enum double BEHIND_DEGREES = 150;

void beaconHome(ref Script world) {
    world.plane(degrees(0));
    walk.spawn(world);
    world.material(BEACON_SLOT);
    world.look(degrees(0), degrees(AHEAD_DEGREES));
    world.check(world.placeBlock() && world.game.beacons.length == 1, "placed no beacon");
    if (!world.isFailed) {
        world.look(degrees(0), degrees(-AHEAD_DEGREES));
        float near = world.game.sightingOf(world.game.beacons.ptr[0]).distance.value;
        world.mode(MovementMode.noclip);
        world.press(BEACON_AWAY / walk.NOCLIP_SPEED, Key.back);
        world.step();
        BeaconSighting far = world.game.sightingOf(world.game.beacons.ptr[0]);
        double toward = world.game.yawToward(far.direction).value / RADIANS_PER_DEGREE;
        world.claim(Topic.navigation, "Backing straight away from a beacon, its distance grows by the distance travelled.", fabs(far.distance.value - near - BEACON_AWAY) < BEACON_DISTANCE_TOLERANCE, Measure.of("distance at first", near), Measure.of("backed away by", BEACON_AWAY), Measure.of("distance then", far.distance.value));
        world.claim(Topic.navigation, "A beacon the player backed away from still lies ahead.", fabs(toward) < 180 - BEHIND_DEGREES, Measure.of("direction off straight ahead (degrees)", toward));
        world.press(BEACON_AWAY / walk.NOCLIP_SPEED, Key.forward);
        world.mode(MovementMode.walk);
        world.wait(walk.LANDING_SECONDS);
        world.look(degrees(0), degrees(AHEAD_DEGREES));
        world.check(world.breakBlock() && world.game.beacons.length == 0, "breaking the beacon left %zu beacons", world.game.beacons.length);
    }
}

enum float SAVE_WALK = 0.5f;
enum double SAVE_STROLL_SECONDS = 1;
enum float SAVE_PLACE_TOLERANCE = 1e-3f;

void saveRoundTrip(ref Script world) {
    world.plane(degrees(0));
    walk.spawn(world);
    world.mode(MovementMode.noclip);
    world.press(SAVE_WALK / walk.NOCLIP_SPEED, Key.forward);
    world.mode(MovementMode.walk);
    world.wait(walk.LANDING_SECONDS);
    world.press(SAVE_STROLL_SECONDS, Key.forward);
    world.look(degrees(0), degrees(AHEAD_DEGREES));
    world.check(world.placeBlock(), "placed a block to save");
    world.dose();
    world.wait(1);
    Molecule desk = conjugated(Molecule.init).withFragment(SHELF_CELLS[1], Fragment.of(SHELF_FRAGMENTS[1]));
    world.game.pharma.catalog.molecule = desk;
    Writer writer;
    writeGame(world.game, writer);
    ClientConfig config;
    Game copy = Game.make(world.game.world.graph.worldgen, config.reach);
    copy.supply = ChunkSupply.onDemand;
    SaveData data;
    const(char)* problem = readGame(writer.bytes.slice(), copy, data);
    world.check(problem is null, "the save did not read back: it %s", problem);
    if (problem is null) {
        applyEdits(copy, data);
        StructureProblem placed = copy.placeStructure();
        world.check(!placed.isPresent, "the copy's world did not start");
        applyState(copy, data);
        world.claim(Topic.saves, "A save keeps every block the player changed.", copy.world.graph.edits.cellCount == world.game.world.graph.edits.cellCount, Measure.of("blocks changed", world.game.world.graph.edits.cellCount), Measure.of("loaded back", copy.world.graph.edits.cellCount));
        world.claim(Topic.saves, "A save keeps the inventory.", copy.inventory == world.game.inventory);
        world.claim(Topic.saves, "A save keeps the shape set on the catalog desk.", copy.pharma.catalog.molecule == desk);
        world.claim(Topic.saves, "A save keeps what is in the body.", copy.organism.body.count == world.game.organism.body.count && copy.organism.body.species[0].blood == world.game.organism.body.species[0].blood, Measure.of("compounds in the body", world.game.organism.body.count));
        Position here = world.game.characterState.position;
        Position there = copy.characterState.position;
        float apart = (here.local * Point!float.origin()).distance(there.local * Point!float.origin());
        world.claim(Topic.saves, "A save keeps where the player stands.", here.node == there.node && apart < SAVE_PLACE_TOLERANCE, Measure.of("came back this far away", apart));
        uint kept = world.game.footholds.count;
        uint matched = 0;
        float farthestApart = 0;
        while (matched < kept && copy.footholds.places[matched].node == world.game.footholds.places[matched].node) {
            farthestApart = higherOf(farthestApart, (copy.footholds.places[matched].local * Point!float.origin()).distance(world.game.footholds.places[matched].local * Point!float.origin()));
            matched += 1;
        }
        world.link(Topic.saves, Topic.falls, "A save keeps every place the player would wake on after a fall.", kept > 1 && copy.footholds.count == kept && matched == kept && farthestApart < SAVE_PLACE_TOLERANCE, Measure.of("places saved", kept), Measure.of("places loaded back", copy.footholds.count), Measure.of("farthest any came back from where it was", farthestApart));
    }
    Game other = Game.make(Worldgen.makeTerrain(), config.reach);
    SaveData refused;
    world.claim(Topic.saves, "A save made in one world does not load into another.", readGame(writer.bytes.slice(), other, refused) !is null);
    refused.release();
    other.release();
    data.release();
    copy.release();
    writer.bytes.release();
}

enum float EDIT_AWAY = 12.0f;
enum float EDIT_RISE = 0.5f;
enum double EDIT_LOAD_SECONDS = 3;
enum double EDIT_AHEAD_DEGREES = 30;
enum double MOST_EVICTION_SECONDS = 30;

void travel(ref Script world, Key along) {
    world.press(EDIT_RISE / walk.NOCLIP_SPEED, Key.up);
    world.press(EDIT_AWAY / walk.NOCLIP_SPEED, along);
    world.press(EDIT_RISE / walk.NOCLIP_SPEED, Key.down);
    world.wait(EDIT_LOAD_SECONDS);
}

Maybe!Material storedAt(ref Script world, Placement placement) {
    const(Graph)* graph = &world.game.world.graph;
    MaybeIndex!uint slot = graph.slotOf(placement.chunk.node);
    if (slot.exists && graph.chunks.at(ChunkSlot(slot.value, placement.chunk.corner)).state == ChunkState.populated) {
        return Maybe!Material.of(graph.chunks.at(ChunkSlot(slot.value, placement.chunk.corner)).voxels.at(cellIndex(graph.layout.dimension, placement.coords.x, placement.coords.y, placement.coords.z)));
    } else {
        return Maybe!Material.init;
    }
}

void liveEditKept(ref Script world) {
    world.plane(degrees(0));
    walk.spawn(world);
    world.live();
    world.mode(MovementMode.noclip);
    travel(world, Key.forward);
    world.look(degrees(0), degrees(EDIT_AHEAD_DEGREES));
    Maybe!Placement target = world.game.world.placementTarget();
    world.check(target.exists && world.placeBlock(), "could not place the block to keep");
    if (!world.isFailed) {
        NodeId edited = target.value.chunk.node;
        Maybe!Material placed = world.targetMaterial();
        world.look(degrees(0), degrees(-EDIT_AHEAD_DEGREES));
        travel(world, Key.back);
        double waited = 0;
        while (!world.isFailed && world.game.world.graph.slotOf(edited).exists && waited < MOST_EVICTION_SECONDS) {
            world.wait(ONSET_STEP_SECONDS);
            waited += ONSET_STEP_SECONDS;
        }
        world.check(!world.game.world.graph.slotOf(edited).exists, "the edited node is still loaded %.0f s after going %.0f back toward the root, so nothing was evicted", MOST_EVICTION_SECONDS, EDIT_AWAY);
        travel(world, Key.forward);
        Maybe!Material back = storedAt(world, target.value);
        const(char)[] before = walk.nameOf(placed);
        const(char)[] after = walk.nameOf(back);
        world.claim(Topic.world, "A block the player placed is still there after its cell was dropped and made again.", placed.exists && back.exists && back.value == placed.value, Measure.of("placed", before), Measure.of("found afterwards", after));
    }
}

enum double FAR_CLIMB_SECONDS = 2;
enum uint FAR_LEGS = 8;
enum float FAR_LEG_DISTANCE = 4.0f;
enum float ALTITUDE_DRIFT = 0.01f;
enum float MOST_PROBE_DEPTH = 2.0f;
enum double AWAY_FROM_TREE_DEGREES = 180;
enum Length CLOSE = Length(0.5f);

struct Probe {
    Maybe!Material below;
    float depth = 0;
}

Probe groundBelow(ref Script world) {
    uint mostSteps = cast(uint)(MOST_PROBE_DEPTH / (walk.NOCLIP_SPEED * world.timestep.value) + 0.999f);
    Maybe!Material below = walk.lookBelow(world);
    uint steps = 0;
    world.hold(Key.down);
    while (!world.isFailed && !below.exists && steps < mostSteps) {
        world.step();
        steps += 1;
        below = walk.lookBelow(world);
    }
    world.release(Key.down);
    world.hold(Key.up);
    foreach (_; 0 .. steps) {
        world.step();
    }
    world.release(Key.up);
    return Probe(below, steps * walk.NOCLIP_SPEED * world.timestep.value);
}

void liveFar(ref Script world) {
    world.live();
    world.look(degrees(AWAY_FROM_TREE_DEGREES), degrees(0));
    world.mode(MovementMode.fly);
    world.press(FAR_CLIMB_SECONDS, Key.up);
    world.mode(MovementMode.noclip);
    float start = world.altitude().value;
    foreach (leg; 0 .. FAR_LEGS) {
        world.press(FAR_LEG_DISTANCE / walk.NOCLIP_SPEED, Key.forward);
        float altitude = world.altitude().value;
        UnloadedCount unloaded = world.unloadedWithin(CLOSE);
        Probe probe = groundBelow(world);
        world.check(fabs(altitude - start) < ALTITUDE_DRIFT && probe.below.exists, "after %.0f units: altitude %.3f from %.3f, %u fresh %u generating %u nodes missing, %s below within %.2f", (leg + 1) * FAR_LEG_DISTANCE, altitude, start, unloaded.fresh, unloaded.generating, unloaded.missingNodes, textFor(probe.below.exists, "something", "nothing"), probe.depth);
    }
}

enum uint FLY_SECONDS = 40;
enum uint NOCLIP_SECONDS = 30;
enum float LEAST_FLY_FRACTION = 0.9f;
enum double FLY_CLIMB_SECONDS = 5;

void checkClose(ref Script world, const(char)* what, uint second) {
    UnloadedCount unloaded = world.unloadedWithin(CLOSE);
    world.check(unloaded.fresh + unloaded.dropped == 0, "%s, second %u: %u fresh and %u dropped chunks right around the body (%u generating, %u waiting for a building, %u nodes missing)", what, second, unloaded.fresh, unloaded.dropped, unloaded.generating, unloaded.awaitingBuilding, unloaded.missingNodes);
}

void liveFly(ref Script world) {
    world.live();
    world.look(degrees(AWAY_FROM_TREE_DEGREES), degrees(0));
    world.mode(MovementMode.fly);
    world.press(FLY_CLIMB_SECONDS, Key.up);
    foreach (second; 1 .. FLY_SECONDS + 1) {
        float before = world.traveled().value;
        world.press(1, Key.forward);
        float flown = world.traveled().value - before;
        world.check(flown >= LEAST_FLY_FRACTION * walk.FLY_SPEED, "flew %.3f in second %u, %s at altitude %.3f", flown, second, textFor(world.isLoaded(), "loaded", "not loaded"), world.altitude().value);
        checkClose(world, "flying", second);
    }
    world.mode(MovementMode.walk);
    world.wait(walk.LANDING_SECONDS);
    world.check(world.isLoaded(), "landed where the world is loaded");
    world.mode(MovementMode.noclip);
    foreach (second; 1 .. NOCLIP_SECONDS + 1) {
        float before = world.traveled().value;
        world.press(1, Key.forward);
        world.check(world.traveled().value - before >= LEAST_FLY_FRACTION * walk.NOCLIP_SPEED, "noclip moved %.3f in second %u", world.traveled().value - before, second);
        checkClose(world, "noclip", second);
    }
}

enum double MOST_ONSET_SECONDS = 30;
enum double ONSET_STEP_SECONDS = 0.5;
enum double SOBER_SECONDS = 20;
enum float SOBER_SIGNAL = 1e-4f;

void biologyDosedClimb(ref Script world) {
    world.structure("hiddenstair");
    world.enterRoute();
    world.wait(walk.SETTLE_SECONDS);
    world.dose();
    double waited = 0;
    while (!world.isFailed && !world.game.reveal.revealed.has(materialNamed("base:mist-stone")) && waited < MOST_ONSET_SECONDS) {
        world.wait(ONSET_STEP_SECONDS);
        waited += ONSET_STEP_SECONDS;
    }
    world.link(Topic.body, Topic.perception, "A swallowed dose of the first starter compound raises the mist signal until the hidden mist blocks are revealed.", world.game.reveal.revealed.has(materialNamed("base:mist-stone")), Measure.of("seconds until revealed", waited), Measure.of("mist signal then", world.game.organism.signaling.signalOf(0).value));
    size_t reached = climb.follow(world, Maybe!size_t.init);
    world.wait(walk.SETTLE_SECONDS);
    world.link(Topic.perception, Topic.movement, "Blocks that a dose reveals are solid: the body can climb a stair made of them.", !world.routeWaypoint(reached + 1).exists && world.altitude().value > HIDDEN_RISE, Measure.of("climbed to", world.altitude().value), Measure.of("stops reached", reached));
}

void biologySober(ref Script world) {
    world.plane(degrees(0));
    walk.spawn(world);
    world.wait(SOBER_SECONDS);
    foreach (signal; 0 .. 3) {
        float level = world.game.organism.signaling.signalOf(signal).value;
        world.claim(Topic.body, "With nothing in the body, its signals stay at rest.", level <= SOBER_SIGNAL && level >= -SOBER_SIGNAL, Measure.of("signal", signal), Measure.of("level", level));
    }
}

enum float HIDDEN_RISE = 1.5f;
enum size_t INSIDE_STOP = 6;
enum float SINK_INTO_TREAD = 0.03f;

void hiddenClimb(ref Script world) {
    world.structure("hiddenstair");
    world.perceive("base:mist-sight");
    world.enterRoute();
    world.wait(walk.SETTLE_SECONDS);
    world.check(world.isOnGround(), "standing at the foot of the revealed stair");
    size_t reached = climb.follow(world, Maybe!size_t.init);
    world.wait(walk.SETTLE_SECONDS);
    world.check(!world.routeWaypoint(reached + 1).exists, "stopped after %zu waypoints on the revealed stair", reached);
    world.link(Topic.perception, Topic.movement, "A stair of hidden blocks can be climbed while perception reveals them.", world.isOnGround() && world.altitude().value > HIDDEN_RISE, Measure.of("climbed to", world.altitude().value));
}

void hiddenUnrevealed(ref Script world) {
    world.structure("hiddenstair");
    world.enterRoute();
    world.wait(walk.SETTLE_SECONDS);
    climb.follow(world, Maybe!size_t.init);
    bool stuck = world.takeFailure();
    world.check(stuck, "walked the whole route of a stair that is not revealed");
    world.link(Topic.perception, Topic.movement, "Hidden blocks that are not revealed do not hold the body up.", world.altitude().value < HIDDEN_RISE, Measure.of("rose to", world.altitude().value));
}

void hiddenRevealInside(ref Script world) {
    world.structure("hiddenstair");
    world.perceive("base:mist-sight");
    world.enterRoute(INSIDE_STOP);
    world.wait(walk.SETTLE_SECONDS);
    world.check(world.isOnGround(), "standing on a revealed tread");
    world.perceive("plain");
    world.mode(MovementMode.noclip);
    world.press(SINK_INTO_TREAD / walk.NOCLIP_SPEED, Key.down);
    world.perceive("base:mist-sight");
    world.link(Topic.perception, Topic.movement, "Hidden blocks that are revealed while the body is inside them stay passable.", !world.game.reveal.touchable.has(materialNamed("base:mist-stone")));
    world.mode(MovementMode.walk);
    world.wait(walk.LANDING_SECONDS);
    world.check(world.isOnGround(), "did not land after falling out of the stair");
    world.link(Topic.perception, Topic.movement, "Revealed hidden blocks turn solid once the body is no longer inside them.", world.game.reveal.touchable.has(materialNamed("base:mist-stone")));
}

enum string FELT_PRESET = "base:heavy";
enum double FELT_WALK_SECONDS = 3;
enum float MOST_WALKED_FRACTION = 1.001f;

void perceptionBody(ref Script world) {
    world.plane(degrees(0));
    walk.spawn(world);
    world.perceive(FELT_PRESET);
    CharacterConfig felt = world.game.character.effectiveFor(world.game.perception);
    world.check(felt.walkSpeed.value < walk.SPEED && felt.jumpHeight.value < IDEAL_RISE, "the preset should slow walking and lower the jump, but walks at %.4f and jumps %.4f", felt.walkSpeed.value, felt.jumpHeight.value);
    float standing = world.altitude().value;
    Jump jump = Jump(standing, 0);
    world.onStep(StepHook(&jumpHook, &jump));
    world.press(0.1, Key.up);
    world.wait(1.5);
    world.onStep(StepHook.init);
    float rise = jump.apex - standing;
    world.link(Topic.perception, Topic.movement, "Perception that lowers the jump height lowers the jump by as much.", rise >= LEAST_RISE_FRACTION * felt.jumpHeight.value && rise <= MOST_RISE_FRACTION * felt.jumpHeight.value, Measure.of("rose", rise), Measure.of("felt jump height", felt.jumpHeight.value), Measure.of("jump height without it", world.game.character.jumpHeight.value));
    walk.checkStanding(world, "after the heavy jump");
    float start = world.traveled().value;
    world.press(FELT_WALK_SECONDS, Key.forward);
    float walked = world.traveled().value - start;
    float free = felt.walkSpeed.value * FELT_WALK_SECONDS;
    world.link(Topic.perception, Topic.movement, "Perception that lowers the walk speed slows the walk by as much.", walked >= LEAST_WALKED_FRACTION * free && walked <= MOST_WALKED_FRACTION * free, Measure.of("walked", walked), Measure.of("felt walk speed times the time", free), Measure.of("walk speed without it", world.game.character.walkSpeed.value));
}

enum double TILT_DEGREES = 25;
enum double SLOPE_WALK_SECONDS = 8;
enum float LEAST_SLOPE_FRACTION = 0.8f;
enum float LEAST_CLIMB_FRACTION = 0.4f;

void slopeAcross(ref Script world) {
    walk.acrossSlope(world, TILT_DEGREES, 90, SLOPE_WALK_SECONDS, LEAST_SLOPE_FRACTION);
}

void slopeDownhill(ref Script world) {
    walk.acrossSlope(world, TILT_DEGREES, 180, SLOPE_WALK_SECONDS, LEAST_SLOPE_FRACTION);
}

void slopeUphill(ref Script world) {
    Across across = walk.acrossSlope(world, TILT_DEGREES, 0, SLOPE_WALK_SECONDS, LEAST_SLOPE_FRACTION);
    double ideal = across.walked * sin(TILT_DEGREES * RADIANS_PER_DEGREE);
    world.check(across.climbed >= LEAST_CLIMB_FRACTION * ideal, "climbed %.4f walking %.4f up a 25 degree slope", across.climbed, across.walked);
}

enum uint HOPS = 6;
enum double SECONDS_BETWEEN_HOPS = 0.544;
enum double JUMP_PRESS_SECONDS = 0.096;
enum double HOP_LANDING_SECONDS = 0.96;

void slopeHopping(ref Script world) {
    walk.onSlope(world, TILT_DEGREES, 0);
    Motion motion;
    walk.trackMotion(world, &motion);
    foreach (heading; 0 .. 3) {
        world.hold(Key.forward);
        foreach (_; 0 .. HOPS) {
            world.wait(SECONDS_BETWEEN_HOPS);
            world.press(JUMP_PRESS_SECONDS, Key.up);
        }
        world.release(Key.forward);
        world.wait(HOP_LANDING_SECONDS);
        world.turn(degrees(90), degrees(0), walk.TURN_SECONDS);
    }
    world.onStep(StepHook.init);
    walk.checkSpeedLimit(world, motion);
    world.check(world.isOnGround(), "on ground at the end");
}

enum double STEEP_DEGREES = 40;

void slopeSteep(ref Script world) {
    walk.onSlope(world, STEEP_DEGREES, 0);
    Motion motion;
    walk.trackMotion(world, &motion);
    float start = world.altitude().value;
    walk.climbForward(world, SLOPE_WALK_SECONDS, world.timestep, ClimbGoal.timed, 0);
    world.wait(walk.LANDING_SECONDS);
    world.onStep(StepHook.init);
    walk.checkSpeedLimit(world, motion);
    world.check(world.altitude().value > start, "climbed some of the slope");
    world.check(world.isOnGround(), "on ground at the end");
}

enum double TURN_DEGREES_PER_SECOND = 25;
enum double TURNING_SECONDS = 14.4;

void slopeTurning(ref Script world) {
    walk.onSlope(world, TILT_DEGREES, 0);
    Motion motion;
    walk.trackMotion(world, &motion);
    world.turnRate(degrees(TURN_DEGREES_PER_SECOND) / ONE_SECOND, AngularSpeed(0));
    world.press(TURNING_SECONDS, Key.forward);
    world.turnRate(AngularSpeed(0), AngularSpeed(0));
    world.wait(walk.SETTLE_SECONDS);
    world.onStep(StepHook.init);
    walk.checkSpeedLimit(world, motion);
    world.check(world.isOnGround(), "on ground at the end");
}

enum uint SLOPE_WALL_BLOCKS = 3;
enum double SLOPE_APPROACH_SECONDS = 0.5;
enum float MOST_RISE_SPEED = 0.1f;

struct Pushing {
    Motion motion;
    float slowest;
}

void pushingHook(ref Script world, void* context) {
    Pushing* pushing = cast(Pushing*) context;
    pushing.slowest = lowerOf(pushing.slowest, world.horizontalSpeed().value);
    walk.observe(world, pushing.motion);
}

void slopeWall(ref Script world) {
    walk.onSlope(world, TILT_DEGREES, 0);
    foreach (heading; HEADINGS) {
        if (heading != 0) {
            world.turn(degrees(90), degrees(0), walk.TURN_SECONDS);
        }
        walk.buildWall(world, SLOPE_WALL_BLOCKS);
        world.wait(2);
        world.check(world.isOnGround(), "heading %d: back on the ground after building", heading);
        Pushing pushing = Pushing(walk.motionFrom(world), world.horizontalSpeed().value);
        world.onStep(StepHook(&walk.observeHook, &pushing.motion));
        world.hold(Key.forward);
        world.wait(SLOPE_APPROACH_SECONDS);
        world.onStep(StepHook(&pushingHook, &pushing));
        world.wait(WALL_PUSH_SECONDS);
        world.release(Key.forward);
        world.wait(walk.SETTLE_SECONDS);
        world.onStep(StepHook.init);
        world.check(pushing.slowest <= CONTACT_SPEED_FRACTION * walk.SPEED, "heading %d: never slowed below %.4f, so the wall was not reached", heading, pushing.slowest);
        world.check(pushing.motion.rise <= MOST_RISE_SPEED, "heading %d: rose at %.4f against the wall", heading, pushing.motion.rise);
        walk.checkSpeedLimit(world, pushing.motion);
        world.check(world.isOnGround(), "heading %d: on ground against the wall", heading);
        world.press(walk.WALL_DISTANCE / walk.SPEED, Key.back);
    }
}

void climbing(string name, float minClimb, SpawnCheck spawnCheck)(ref Script world) {
    world.structure(name);
    if (spawnCheck == SpawnCheck.checked) {
        walk.spawn(world);
    }
    climb.route(world, minClimb);
}

void structureAxis(ref Script world) {
    world.structure("tower");
    world.mode(MovementMode.noclip);
    foreach (height; AXIS_HEIGHTS) {
        world.enterStructure(Length(height));
        world.look(degrees(0), degrees(walk.STRAIGHT_DOWN_DEGREES));
        world.step();
        world.check(world.targetMaterial().exists, "%.2f up the axis: no floor within reach below", height);
        world.look(degrees(0), degrees(-walk.STRAIGHT_DOWN_DEGREES));
    }
}

enum float RISEN_BACKROOMS_ALTITUDE = 1.5f;

void checkBackroomsAround(ref Script world) {
    world.look(degrees(0), degrees(walk.STRAIGHT_DOWN_DEGREES));
    Maybe!Material below = world.targetMaterial();
    world.look(degrees(0), degrees(-2 * walk.STRAIGHT_DOWN_DEGREES));
    Maybe!Material above = world.targetMaterial();
    const(char)[] floor = walk.nameOf(below);
    const(char)[] ceiling = walk.nameOf(above);
    world.check(walk.isOneOf(below, walk.BACKROOMS_FLOORS[]), "standing on %.*s instead of the backrooms' floor", cast(int) floor.length, floor.ptr);
    world.check(walk.isOneOf(above, walk.BACKROOMS_CEILINGS[]), "under %.*s instead of the backrooms' ceiling", cast(int) ceiling.length, ceiling.ptr);
}

void structureBackrooms(ref Script world) {
    world.structure("risenbackrooms");
    world.enterRoute();
    world.wait(walk.SETTLE_SECONDS);
    world.check(world.altitude().value < RISEN_BACKROOMS_ALTITUDE, "starting on the ground, %.3f up", world.altitude().value);
    size_t reached = climb.follow(world, Maybe!size_t.init);
    world.wait(walk.SETTLE_SECONDS);
    world.check(!world.routeWaypoint(reached + 1).exists, "stopped after %zu waypoints", reached);
    world.check(world.isOnGround(), "standing in the backrooms");
    world.check(world.altitude().value > RISEN_BACKROOMS_ALTITUDE, "ended only %.3f above the ground", world.altitude().value);
    checkBackroomsAround(world);
}

void structureBackroomsWorld(ref Script world) {
    world.structure("backrooms");
    walk.spawn(world);
    checkBackroomsAround(world);
}

enum float CHAIN_LOWER_ALTITUDE = 1.5f;
enum float LEAST_MOVED = 0.5f;

void structureChain(ref Script world) {
    world.structure("chain");
    world.enterRoute();
    world.wait(walk.SETTLE_SECONDS);
    world.check(world.isOnGround(), "standing on the first city outside the connector's lower door");
    float start = world.altitude().value;
    world.check(start > CHAIN_LOWER_ALTITUDE, "starting only %.3f above the ground, not on the first city", start);
    size_t reached = climb.follow(world, Maybe!size_t.init);
    world.wait(walk.SETTLE_SECONDS);
    world.check(!world.routeWaypoint(reached + 1).exists, "stopped after %zu waypoints", reached);
    world.check(world.isOnGround(), "standing in the city risen from the first");
    world.check(fabs(world.altitude().value - start) > LEAST_MOVED, "ended %.3f above the ground from %.3f, still by the first city", world.altitude().value, start);
    world.look(degrees(0), degrees(walk.STRAIGHT_DOWN_DEGREES));
    const(char)[] below = walk.nameOf(world.targetMaterial());
    world.check(walk.isMaterial(world.targetMaterial(), "base:concrete"), "standing on %.*s instead of the connector's landing", cast(int) below.length, below.ptr);
}

enum size_t ENTRY_STOPS = 2;
enum size_t STOPS_PER_STORY = 7;
enum size_t ROUTE_STORIES = 2;
enum float CITY_LEAST_CLIMB = 0.25f;

void structureCity(ref Script world) {
    world.structure("city");
    walk.spawn(world);
    world.look(degrees(0), degrees(walk.STRAIGHT_DOWN_DEGREES));
    const(char)[] spawned = walk.nameOf(world.targetMaterial());
    world.check(walk.isOneOf(world.targetMaterial(), walk.STREET_MATERIALS[]), "spawned on %.*s instead of the street", cast(int) spawned.length, spawned.ptr);
    world.look(degrees(0), degrees(-walk.STRAIGHT_DOWN_DEGREES));
    world.enterRoute();
    world.wait(walk.SETTLE_SECONDS);
    float ground = world.altitude().value;
    size_t reached = climb.follow(world, Maybe!size_t.init);
    world.wait(walk.SETTLE_SECONDS);
    world.check(reached == ENTRY_STOPS + ROUTE_STORIES * STOPS_PER_STORY, "reached %zu stops from the street up the stairs", reached);
    world.check(world.isOnGround(), "standing upstairs");
    world.check(world.altitude().value - ground >= CITY_LEAST_CLIMB, "climbed only %.3f", world.altitude().value - ground);
}

enum double CROWN_WALK_SECONDS = 6;
enum float CROWN_LEAST_WALKED = 0.9f;

void structureCrown(ref Script world) {
    world.structure("crown");
    walk.spawn(world);
    float ground = world.altitude().value;
    float start = world.traveled().value;
    world.press(CROWN_WALK_SECONDS, Key.forward);
    world.wait(walk.SETTLE_SECONDS);
    float walked = world.traveled().value - start;
    world.look(degrees(0), degrees(walk.STRAIGHT_DOWN_DEGREES));
    Maybe!Material below = world.targetMaterial();
    const(char)[] name = walk.nameOf(below);
    world.check(world.isOnGround(), "standing in the hall");
    world.check(walked >= CROWN_LEAST_WALKED * walk.SPEED * CROWN_WALK_SECONDS, "walked only %.3f toward the hall door", walked);
    world.check(world.altitude().value - ground > walk.LEAST_BLOCK_EDGE / 2, "rose %.3f, not over the door's threshold", world.altitude().value - ground);
    world.check(walk.isOneOf(below, walk.TOWER_MATERIALS[]), "standing on %.*s instead of the hall floor", cast(int) name.length, name.ptr);
}

enum float ENDLESS_FLIGHT = 5;
enum uint ENDLESS_SAMPLES = 10;

void structureEndless(ref Script world) {
    world.structure("city");
    world.mode(MovementMode.noclip);
    foreach (sample; 1 .. ENDLESS_SAMPLES + 1) {
        world.press(ENDLESS_FLIGHT / ENDLESS_SAMPLES / walk.NOCLIP_SPEED, Key.forward);
        world.look(degrees(0), degrees(walk.STRAIGHT_DOWN_DEGREES));
        world.step();
        Maybe!Material below = world.targetMaterial();
        const(char)[] name = walk.nameOf(below);
        world.claim(Topic.structures, "Flying over the city there is always city below, and never bare ground.", below.exists && !walk.isMaterial(below, walk.GROUND), Measure.of("flown", sample * ENDLESS_FLIGHT / ENDLESS_SAMPLES), Measure.of("below", name));
        world.look(degrees(0), degrees(-walk.STRAIGHT_DOWN_DEGREES));
    }
}

enum size_t HUTS = 5;
enum size_t STOPS_PER_HUT = 14;
enum double HAMLET_WALK_SECONDS = 6;

void structureHamlet(ref Script world) {
    world.structure("hamlet");
    world.check(world.routeWaypoint(HUTS * STOPS_PER_HUT).exists, "every hut added its stair route");
    world.check(!world.routeWaypoint(HUTS * STOPS_PER_HUT + 1).exists, "and nothing else did");
    walk.spawn(world);
    float ground = world.altitude().value;
    world.press(HAMLET_WALK_SECONDS, Key.forward);
    world.wait(walk.SETTLE_SECONDS);
    world.look(degrees(0), degrees(walk.STRAIGHT_DOWN_DEGREES));
    const(char)[] name = walk.nameOf(world.targetMaterial());
    world.check(walk.isMaterial(world.targetMaterial(), "base:wood-planks"), "standing on %.*s instead of the first hut's floor", cast(int) name.length, name.ptr);
    world.check(world.altitude().value - ground > walk.LEAST_BLOCK_EDGE / 2, "stepped over the hut's threshold");
}

immutable string[3] PLATFORMS = ["base:wood-planks", "base:marble", "base:grey-brick"];

void structureLattice(ref Script world) {
    world.structure("lattice");
    walk.spawn(world);
    float standing = world.altitude().value;
    world.check(standing > 0, "standing at altitude %.4f, not below the plane gravity points away from", standing);
    world.look(degrees(0), degrees(walk.STRAIGHT_DOWN_DEGREES));
    const(char)[] name = walk.nameOf(world.targetMaterial());
    world.check(walk.isOneOf(world.targetMaterial(), PLATFORMS[]), "standing on %.*s instead of the root platform", cast(int) name.length, name.ptr);
    world.press(world.timestep.value, Key.up);
    world.step();
    world.check(!world.isOnGround(), "jumped off the platform");
    world.check(world.altitude().value > standing, "jumped to %.4f from %.4f, not away from the platform", world.altitude().value, standing);
    world.wait(walk.LANDING_SECONDS);
    world.check(world.isOnGround(), "landed back on the platform");
    world.check(fabs(world.altitude().value - standing) < walk.ALTITUDE_TOLERANCE, "landed at %.4f instead of %.4f", world.altitude().value, standing);
}

void risen(string name, float risenAltitude, string landing, string what)(ref Script world) {
    world.structure(name);
    world.enterRoute();
    world.wait(walk.SETTLE_SECONDS);
    world.check(world.isOnGround(), "standing at the start of the route");
    world.check(world.altitude().value < risenAltitude, "starting on the ground, %.3f up", world.altitude().value);
    size_t reached = climb.follow(world, Maybe!size_t.init);
    world.wait(walk.SETTLE_SECONDS);
    world.check(!world.routeWaypoint(reached + 1).exists, "stopped after %zu waypoints", reached);
    world.check(world.isOnGround(), "standing at the end of the route");
    world.claim(Topic.structures, "A connector's route leads on foot from the lower ground up onto the risen one.", world.altitude().value > risenAltitude, Measure.of("ended this high", world.altitude().value));
    world.look(degrees(0), degrees(walk.STRAIGHT_DOWN_DEGREES));
    const(char)[] below = walk.nameOf(world.targetMaterial());
    world.check(walk.isMaterial(world.targetMaterial(), landing), "standing on %.*s instead of %.*s", cast(int) below.length, below.ptr, cast(int) what.length, what.ptr);
}

enum float TRIP_LEAST_RISE = 1.5f;
enum float TRIP_HOME_TOLERANCE = 0.1f;
enum float MOST_PULL_PER_STEP = 0.15f;

struct PullWatch {
    Vec3!float last = ZERO_VECTOR;
    float largest = 0;
    float highest = 0;
    uint steps;
}

void pullWatchHook(ref Script world, void* context) {
    PullWatch* watch = cast(PullWatch*) context;
    Vec3!float pull = world.game.characterState.pull;
    if (watch.steps > 0) {
        watch.largest = higherOf(watch.largest, pull.minus(watch.last).magnitude);
    }
    watch.last = pull;
    watch.highest = higherOf(watch.highest, world.altitude().value);
    watch.steps += 1;
}

void roundTrip(string name)(ref Script world) {
    world.structure(name);
    world.enterRoute();
    world.wait(walk.SETTLE_SECONDS);
    world.check(world.isOnGround(), "standing at the start of the round trip");
    float start = world.altitude().value;
    PullWatch watch;
    world.onStep(StepHook(&pullWatchHook, &watch));
    size_t reached = climb.follow(world, Maybe!size_t.init);
    world.wait(walk.SETTLE_SECONDS);
    world.onStep(StepHook.init);
    world.check(!world.routeWaypoint(reached + 1).exists, "stopped after %zu waypoints", reached);
    world.check(world.isOnGround(), "standing at the end of the round trip");
    world.check(watch.highest - start > TRIP_LEAST_RISE, "rose only %.3f on the way", watch.highest - start);
    world.check(fabs(world.altitude().value - start) < TRIP_HOME_TOLERANCE, "came back to altitude %.3f from %.3f", world.altitude().value, start);
    world.claim(Topic.gravity, "On the way up to a risen ground and back down, the pull of gravity changes gradually and never jumps.", watch.largest <= MOST_PULL_PER_STEP, Measure.of("largest change in one step", watch.largest), Measure.of("rose", watch.highest - start));
    world.look(degrees(0), degrees(walk.STRAIGHT_DOWN_DEGREES));
    const(char)[] below = walk.nameOf(world.targetMaterial());
    world.check(walk.isMaterial(world.targetMaterial(), "base:concrete"), "ended on %.*s instead of the lower landing", cast(int) below.length, below.ptr);
}

void structureRoad(ref Script world) {
    world.structure("road");
    world.enterRoute();
    world.wait(walk.SETTLE_SECONDS);
    size_t reached = climb.follow(world, Maybe!size_t.init);
    world.wait(walk.SETTLE_SECONDS);
    world.check(world.isOnGround(), "standing on the road after %zu waypoints", reached);
    world.check(!world.routeWaypoint(reached + 1).exists, "stopped after %zu waypoints", reached);
    world.look(degrees(0), degrees(walk.STRAIGHT_DOWN_DEGREES));
    const(char)[] below = walk.nameOf(world.targetMaterial());
    world.check(walk.isOneOf(world.targetMaterial(), walk.STREET_MATERIALS[]), "standing on %.*s instead of the road", cast(int) below.length, below.ptr);
}

enum double TOWER_WALK_SECONDS = 20;
enum float TOWER_MOST_WALKED_FRACTION = 0.8f;

void highestHook(ref Script world, void* context) {
    float* highest = cast(float*) context;
    *highest = higherOf(*highest, world.altitude().value);
}

void structureTower(ref Script world) {
    world.structure("tower");
    walk.spawn(world);
    float start = world.traveled().value;
    float ground = world.altitude().value;
    float highest = ground;
    world.onStep(StepHook(&highestHook, &highest));
    world.press(TOWER_WALK_SECONDS, Key.forward);
    world.wait(walk.SETTLE_SECONDS);
    world.onStep(StepHook.init);
    float walked = world.traveled().value - start;
    float free = walk.SPEED * TOWER_WALK_SECONDS;
    world.look(degrees(0), degrees(walk.STRAIGHT_DOWN_DEGREES));
    Maybe!Material below = world.targetMaterial();
    const(char)[] name = walk.nameOf(below);
    world.check(world.isOnGround(), "standing inside the tower");
    world.check(world.altitude().value - ground > walk.LEAST_BLOCK_EDGE / 2, "rose %.3f, not onto the ground floor through the door", world.altitude().value - ground);
    world.check(highest - ground < walk.MOST_BLOCK_EDGE, "climbed %.3f, more than the door's threshold", highest - ground);
    world.check(walked < TOWER_MOST_WALKED_FRACTION * free, "walked %.3f of %.3f without reaching the far wall", walked, free);
    world.check(walk.isOneOf(below, walk.TOWER_MATERIALS[]), "standing on %.*s instead of the ground floor", cast(int) name.length, name.ptr);
}

enum size_t TRAIL_STOPS = 12;
enum float MOST_STRAIGHTNESS = 0.8f;

size_t stopCount(ref Script world) {
    size_t count = 0;
    while (world.routeWaypoint(count + 1).exists) {
        count += 1;
    }
    return count;
}

void structureTrail(ref Script world) {
    world.structure("trail");
    size_t built = stopCount(world);
    world.enterRoute();
    world.wait(walk.SETTLE_SECONDS);
    float start = world.traveled().value;
    size_t reached = climb.follow(world, Maybe!size_t.of(TRAIL_STOPS));
    world.wait(walk.SETTLE_SECONDS);
    world.check(reached == TRAIL_STOPS, "walked %zu of %zu trail stops", reached, TRAIL_STOPS);
    world.check(stopCount(world) > built, "the trail did not grow past its first %zu stops as the world grew", built);
    float back = world.needWaypoint(1).horizontal.value;
    float walked = world.traveled().value - start;
    world.check(back < MOST_STRAIGHTNESS * walked, "the trail ran straight: %.3f back to its start after walking %.3f", back, walked);
    world.look(degrees(0), degrees(walk.STRAIGHT_DOWN_DEGREES));
    const(char)[] below = walk.nameOf(world.targetMaterial());
    world.check(walk.isMaterial(world.targetMaterial(), "base:gravel"), "standing on %.*s instead of the trail", cast(int) below.length, below.ptr);
}

enum float TOP_ALTITUDE = 3.2f;
enum float TRUNK_CLIMB = 0.1f;
enum float NUDGE = 0.01f;
enum uint MOST_NUDGES = 200;

immutable string[2] TREE_MATERIALS = ["base:oak-wood", "base:oak-leaves"];

void approachBark(ref Script world) {
    uint nudges = 0;
    while (!world.isFailed && !walk.isOneOf(world.targetMaterial(), TREE_MATERIALS[]) && nudges < MOST_NUDGES) {
        world.press(NUDGE / walk.NOCLIP_SPEED, Key.forward);
        nudges += 1;
    }
    const(char)[] facing = walk.nameOf(world.targetMaterial());
    world.check(walk.isOneOf(world.targetMaterial(), TREE_MATERIALS[]), "no tree ahead at altitude %.3f, facing %.*s", world.altitude().value, cast(int) facing.length, facing.ptr);
}

immutable float[6] ENDLESS_SPOTS = [2.1f, 5.3f, 9.7f, 14.2f, 20.4f, 40.0f];
enum float LIBRARY_LEAST_DESCENT = 20.0f;
enum double MOST_FLOOR_TILT = 3;
enum double LIBRARY_LOAD_SECONDS = 3;
enum float LIBRARY_FLIGHT_DEPTH = 30.0f;
enum float LIBRARY_FLIGHT_LEG = 0.5f;
enum float LIBRARY_MOST_FALL = 0.5f;
enum double LIBRARY_FREE_SECONDS = 0.1;
enum float LIBRARY_NUDGE = 0.03f;
enum uint LIBRARY_MOST_NUDGES = 10;

void structureArborEndless(ref Script world) {
    world.structure("arbor");
    world.mode(MovementMode.noclip);
    foreach (height; ENDLESS_SPOTS) {
        world.enterStructure(Length(height));
        world.step();
        world.look(degrees(0), degrees(walk.STRAIGHT_DOWN_DEGREES));
        const(char)[] below = walk.nameOf(world.targetMaterial());
        world.check(walk.isOneOf(world.targetMaterial(), TREE_MATERIALS[]), "standing in the trunk %.1f up, facing %.*s", height, cast(int) below.length, below.ptr);
        world.look(degrees(0), degrees(-walk.STRAIGHT_DOWN_DEGREES));
    }
}

void walkDownShaft(ref Script world) {
    world.check(world.isOnGround(), "standing at the top of the shaft's stair");
    float start = world.altitude().value;
    size_t reached = climb.follow(world, Maybe!size_t.init);
    world.wait(walk.SETTLE_SECONDS);
    double tilt = world.floorTilt().value / RADIANS_PER_DEGREE;
    world.check(!world.routeWaypoint(reached + 1).exists, "stopped after %zu waypoints", reached);
    world.check(world.isOnGround(), "standing in the shaft after %zu waypoints", reached);
    world.check(start - world.altitude().value >= LIBRARY_LEAST_DESCENT, "went down only %.3f", start - world.altitude().value);
    world.check(tilt <= MOST_FLOOR_TILT, "standing still, the floor tilts %.1f degrees against gravity at altitude %.2f", tilt, world.altitude().value);
}

void structureLibraryFlight(ref Script world) {
    world.structure("library");
    world.live();
    world.enterRoute();
    world.wait(LIBRARY_LOAD_SECONDS);
    world.mode(MovementMode.noclip);
    float start = world.altitude().value;
    while (!world.isFailed && start - world.altitude().value < LIBRARY_FLIGHT_DEPTH) {
        world.press(LIBRARY_FLIGHT_LEG / walk.NOCLIP_SPEED, Key.down);
        Maybe!Material below = walk.lookBelow(world);
        world.check(below.exists, "flying down the stair's ring, no floor below after %.1f down", start - world.altitude().value);
    }
}

void structureLibrary(ref Script world) {
    world.structure("library");
    walk.spawn(world);
    world.enterRoute();
    world.wait(walk.SETTLE_SECONDS);
    walkDownShaft(world);
}

void structureLibraryLive(ref Script world) {
    world.structure("library");
    world.live();
    world.enterRoute();
    world.wait(LIBRARY_LOAD_SECONDS);
    walkDownShaft(world);
}

void structureLibraryEndless(ref Script world) {
    world.structure("library");
    world.mode(MovementMode.noclip);
    foreach (depth; ENDLESS_SPOTS) {
        world.enterStructure(Length(-depth));
        world.step();
        Maybe!Material below = walk.lookBelow(world);
        const(char)[] name = walk.nameOf(below);
        world.check(walk.isMaterial(below, "base:glass"), "no glass floor over the well %.1f down, facing %.*s", depth, cast(int) name.length, name.ptr);
    }
}

void structureLibraryNoHole(ref Script world) {
    world.structure("library");
    foreach (depth; ENDLESS_SPOTS) {
        world.mode(MovementMode.noclip);
        world.enterStructure(Length(-depth));
        float dropped = world.altitude().value;
        uint nudges = 0;
        world.mode(MovementMode.walk);
        world.wait(LIBRARY_FREE_SECONDS);
        while (!world.isFailed && world.altitude().value == dropped && nudges < LIBRARY_MOST_NUDGES) {
            world.mode(MovementMode.noclip);
            world.press(LIBRARY_NUDGE / walk.NOCLIP_SPEED, Key.up);
            dropped = world.altitude().value;
            world.mode(MovementMode.walk);
            world.wait(LIBRARY_FREE_SECONDS);
            nudges += 1;
        }
        world.check(world.altitude().value != dropped, "stuck in solid %.1f down after %u nudges", depth, nudges);
        world.wait(walk.LANDING_SECONDS);
        world.check(world.isOnGround(), "still falling down the well after %.1f from %.1f down", cast(double)(dropped - world.altitude().value), depth);
        world.check(dropped - world.altitude().value < LIBRARY_MOST_FALL, "fell %.2f down the well from %.1f down", cast(double)(dropped - world.altitude().value), depth);
    }
}

enum float PRESS_LIFT = 0.06f;
enum uint STATION_RINGS = 3;
enum string STUDY_PRESS = "pharmacology:press";
enum string PRESSED_LEAVES = "base:oak-leaves";

void structureLibraryPress(ref Script world) {
    world.structure("library");
    walk.spawn(world);
    Material press = materialNamed(STUDY_PRESS);
    Position entrance = world.game.characterState.position;
    Maybe!Position found = walk.ensureNearest(world, entrance, press, STATION_RINGS);
    world.check(found.exists, "no press stands within %u hops of the library's entrance", STATION_RINGS);
    if (!world.isFailed) {
        float away = apartOn(world, entrance, found.value);
        world.game.inventory = Inventory.init;
        Stack leaves = Stack.ofLiving(named(PRESSED_LEAVES), 1, Lineage([41, 42, 43, 44]), Sorting.unsorted);
        world.game.inventory.slots[0] = leaves;
        world.mode(MovementMode.noclip);
        world.game.placeAt(found.value, Length(PRESS_LIFT));
        world.look(degrees(0), degrees(walk.STRAIGHT_DOWN_DEGREES));
        world.step();
        const(char)[] facing = walk.nameOf(world.targetMaterial());
        world.check(walk.isMaterial(world.targetMaterial(), STUDY_PRESS), "above the press found %.2f from the entrance, looking down at %.*s", away, cast(int) facing.length, facing.ptr);
        world.check(world.interact() && world.game.screen == Screen.station && stations()[world.game.workstation.id].block == press, "using the press in the study did not open it");
        bool queued = world.game.pressLiving(0);
        world.wait(syntheses()[synthesisNamed(PRESS_EXTRACT).id].time.value + MINING_SLACK_SECONDS);
        world.link(Topic.structures, Topic.chemistry, "A press that stands in one of the library's study rooms works where it stands: opened there, it presses a living block into extract.", queued && world.game.crafts.length == 0 && world.game.compounds.length == 1 && world.game.compounds.ptr[0].raw == extractOf(PRESS_EXTRACT), Measure.of("press found this far from the entrance", away), Measure.of("compounds held after pressing", world.game.compounds.length), Measure.of("extract expected", extractOf(PRESS_EXTRACT)));
    }
}

enum string HALL_BENCH = "pharmacology:bench";

void structureLibraryBench(ref Script world) {
    world.structure("library");
    walk.spawn(world);
    Position entrance = world.game.characterState.position;
    Maybe!Position found = walk.ensureNearest(world, entrance, materialNamed(HALL_BENCH), STATION_RINGS);
    world.check(found.exists, "no bench stands within %u hops of the library's entrance", STATION_RINGS);
    if (!world.isFailed) {
        float away = apartOn(world, entrance, found.value);
        world.mode(MovementMode.noclip);
        world.game.placeAt(found.value, Length(PRESS_LIFT));
        world.look(degrees(0), degrees(walk.STRAIGHT_DOWN_DEGREES));
        world.step();
        const(char)[] facing = walk.nameOf(world.targetMaterial());
        bool opened = walk.isMaterial(world.targetMaterial(), HALL_BENCH) && world.interact();
        world.link(Topic.structures, Topic.plants, "A bench that stands at a table in one of the library's reading halls opens where it stands.", opened && world.game.screen == Screen.machine && world.game.machineScreen == benchScreen, Measure.of("bench found this far from the entrance", away), Measure.of("looking down at", facing));
    }
}

enum uint STAFF_RINGS = 6;
enum float STAFF_ROOM_WIDTH = 0.55f;
enum string STAFF_WORKBENCH = "game:workbench";
enum string STAFF_LOCKER = "base:steel";

void structureLibraryStaff(ref Script world) {
    world.structure("library");
    walk.spawn(world);
    Position entrance = world.game.characterState.position;
    Maybe!Position found = walk.ensureNearest(world, entrance, materialNamed(STAFF_WORKBENCH), STAFF_RINGS);
    world.check(found.exists, "no workbench stands within %u hops of the library's entrance", STAFF_RINGS);
    if (!world.isFailed) {
        Maybe!Position locker = walk.ensureNearest(world, found.value, materialNamed(STAFF_LOCKER), 0);
        float beside = float.infinity;
        if (locker.exists) {
            beside = apartOn(world, found.value, locker.value);
        }
        world.mode(MovementMode.noclip);
        world.game.placeAt(found.value, Length(PRESS_LIFT));
        world.look(degrees(0), degrees(walk.STRAIGHT_DOWN_DEGREES));
        world.step();
        const(char)[] facing = walk.nameOf(world.targetMaterial());
        bool opened = walk.isMaterial(world.targetMaterial(), STAFF_WORKBENCH) && world.interact();
        world.link(Topic.structures, Topic.crafting, "A workbench that stands in one of the library's staff rooms opens where it stands, and steel lockers stand within the room's width of it.", opened && world.game.screen == Screen.station && world.game.workstation == stationNamed(WORKBENCH_STATION) && beside < STAFF_ROOM_WIDTH, Measure.of("looking down at", facing), Measure.of("nearest steel to the workbench", beside), Measure.of("a room's width", STAFF_ROOM_WIDTH));
    }
}

enum string INLAY_RIG = "inlay";
enum uint INLAY_RINGS = 2;
enum float INLAY_REACH = 0.35f;
enum uint INLAY_CELLS = 4 * 4 * 3;

struct Inlaid {
    Material wanted;
    Vec3!float up;
    uint cells;
    float highest = -float.infinity;

    void visitMissingNode(uint, Face) {
    }

    void visitChunk(ref const Graph graph, LocalFrame frame, ChunkSlot slot, CellRange range) {
        if (graph.chunks.at(slot).state == ChunkState.populated) {
            foreach (x; range.low.x .. range.high.x + 1) {
                foreach (y; range.low.y .. range.high.y + 1) {
                    foreach (z; range.low.z .. range.high.z + 1) {
                        if (graph.chunks.at(slot).voxels.at(cellIndex(graph.layout.dimension, x, y, z)) == wanted) {
                            cells += 1;
                            highest = higherOf(highest, frame.cell(graph.layout, slot.corner, Vec3!int(x, y, z)).center().dot(up));
                        }
                    }
                }
            }
        }
    }
}

enum string INLAID_STONE = "base:limestone";

void structureInlay(ref Script world) {
    world.structure(INLAY_RIG);
    walk.spawn(world);
    Material stone = materialNamed(INLAID_STONE);
    Maybe!Position found = walk.ensureNearest(world, world.game.characterState.position, stone, INLAY_RINGS);
    world.check(found.exists, "no inlaid stone lies within %u hops of where the rig starts", INLAY_RINGS);
    if (!world.isFailed) {
        world.mode(MovementMode.noclip);
        world.game.placeAt(found.value, Length(0));
        world.game.generateWithin(world.game.characterState.position, Length(INLAY_REACH));
        Inlaid inlaid = Inlaid(stone, world.game.characterState.up);
        visitCells(world.game.world.graph, world.game.characterState.position, Length(INLAY_REACH), inlaid);
        float top = world.altitude().value + inlaid.highest;
        world.claim(Topic.structures, "A structure can paint only into what is solid: of a box that straddles flat ground, the cells under the ground take the material and the cells above it stay open.", inlaid.cells == INLAY_CELLS && top < 0, Measure.of("cells that took the material", inlaid.cells), Measure.of("cells of the box under the ground", INLAY_CELLS), Measure.of("highest of them above the ground", top));
    }
}

enum string EVERY_PORT_RIG = "everyport";
enum float EDGE_TOLERANCE = 0.01f;

void structurePortRule(ref Script world) {
    world.structure(EVERY_PORT_RIG);
    walk.spawn(world);
    Maybe!Position port = walk.ensurePort(world);
    bool started = walk.probeStartPort(world);
    world.check(port.exists, "found no port near where the rig starts");
    if (!world.isFailed) {
        float away = apartOn(world, walk.ensureStartVertex(world), port.value);
        float edge = world.game.world.graph.view.edgeOf();
        world.claim(Topic.structures, "A ground's own rule decides where its ports are: under a rule that takes every vertex, the vertex next to the world's start is a port, and the start itself never is.", !started && fabs(away - edge) < EDGE_TOLERANCE, Measure.of("nearest port from the start", away), Measure.of("one edge", edge));
    }
}

enum string PORT_FRAME = "base:steel";
enum float PIT_WIDTH = 0.36f;

void structureCityPort(ref Script world) {
    world.structure("city");
    Maybe!Position port = walk.ensurePort(world);
    world.check(port.exists, "found no port among the vertices nearest the city's start");
    if (!world.isFailed) {
        Maybe!Position steel = walk.ensureNearest(world, port.value, materialNamed(PORT_FRAME), 0);
        float away = float.infinity;
        if (steel.exists) {
            away = apartOn(world, port.value, steel.value);
        }
        world.claim(Topic.structures, "In the city a port is dressed as a pit under a steel frame: steel stands within the pit's width of the port's vertex.", away < PIT_WIDTH, Measure.of("nearest steel to the port's vertex", away), Measure.of("the pit's width", PIT_WIDTH));
    }
}

enum string FACED_PORT_RIG = "facedport";
enum uint FACED_VERTICES = 81;

void structurePortFaces(ref Script world) {
    world.structure(FACED_PORT_RIG);
    walk.spawn(world);
    walk.PortCensus census = walk.censusPorts(world, FACED_VERTICES);
    world.claim(Topic.structures, "A ground's rule is handed a site that lies in the ground, whichever way the asker stands: a rule that reads the four ground faces around a vertex answers an upright asker as it answers one lying in the ground.", census.asked == FACED_VERTICES && census.agreeing == census.asked && census.ports > 0 && census.ports < census.asked, Measure.of("vertices asked both ways", census.asked), Measure.of("answered the same", census.agreeing), Measure.of("ports among them", census.ports));
}

enum string ROLLED_PORT_RIG = "rolledport";

void structurePortRoll(ref Script world) {
    world.structure(ROLLED_PORT_RIG);
    world.check(!world.isFailed, "the rig with a port rule that rolls did not start");
    walk.ensurePort(world);
    world.step();
    bool refused = world.takeFailure();
    world.claim(Topic.structures, "A port rule that rolls is refused: once it is asked, the world stops with a message.", refused);
}

enum string OVERREACH_RIG = "overreach";
enum float REACH_AROUND = 0.35f;

void structureOverreach(ref Script world) {
    world.structure(OVERREACH_RIG);
    world.check(!world.isFailed, "the rig whose tile paints past its reach did not start");
    world.game.generateWithin(world.game.characterState.position, Length(REACH_AROUND));
    world.step();
    bool refused = world.takeFailure();
    world.claim(Topic.structures, "A tile that paints farther from its ground than the reach its world gave it is refused: once it runs, the world stops with a message.", refused);
}

void structureTreetrunk(ref Script world) {
    world.terrain();
    world.mode(MovementMode.noclip);
    approachBark(world);
    while (!world.isFailed && world.altitude().value < TOP_ALTITUDE) {
        world.press(TRUNK_CLIMB / walk.NOCLIP_SPEED, Key.up);
        approachBark(world);
    }
}

enum float CAVES_LEAST_DESCENT = 0.9f;
enum float CAVES_HOME_TOLERANCE = 0.05f;

void lowestHook(ref Script world, void* context) {
    float* lowest = cast(float*) context;
    *lowest = lowerOf(*lowest, world.altitude().value);
}

void structureCaves(ref Script world) {
    world.structure("caves");
    walk.spawn(world);
    world.enterRoute();
    world.wait(walk.SETTLE_SECONDS);
    world.check(world.isOnGround(), "standing on the rim of the sinkhole");
    float start = world.altitude().value;
    float lowest = start;
    world.onStep(StepHook(&lowestHook, &lowest));
    size_t reached = climb.follow(world, Maybe!size_t.init);
    world.wait(walk.SETTLE_SECONDS);
    world.onStep(StepHook.init);
    world.check(!world.routeWaypoint(reached + 1).exists, "stopped after %zu waypoints down the sinkhole and back", reached);
    world.check(world.isOnGround(), "standing on the rim again after %zu waypoints", reached);
    world.check(start - lowest >= CAVES_LEAST_DESCENT, "went down only %.3f into the cave", start - lowest);
    world.check(fabs(world.altitude().value - start) < CAVES_HOME_TOLERANCE, "came back up to %.3f from %.3f", world.altitude().value, start);
}

enum float SINKHOLE_RISE = 0.1f;
enum double SINKHOLE_FALL_SECONDS = 6;

void structureSinkhole(ref Script world) {
    world.terrain();
    Maybe!Position rim = walk.ensureLastFlat(world);
    world.check(rim.exists, "the default world flattened no ground, so it has no sinkhole");
    if (!world.isFailed) {
        world.mode(MovementMode.noclip);
        world.game.placeAt(rim.value, Length(0));
        world.press(SINKHOLE_RISE / walk.NOCLIP_SPEED, Key.up);
        float start = world.altitude().value;
        world.mode(MovementMode.walk);
        world.wait(SINKHOLE_FALL_SECONDS);
        float fell = start - world.altitude().value;
        world.claim(Topic.structures, "A body dropped into the default world's sinkhole falls most of an edge below the ground before it lands.", world.isOnGround() && fell >= CAVES_LEAST_DESCENT, Measure.of("fell", fell), Measure.of("least expected", CAVES_LEAST_DESCENT));
    }
}

enum float WELL_ASIDE = 0.11f;
enum float WELL_DOWN = 1.0f;
enum float WELL_TURN = 0.36f;
enum string WELL_STAIR = "base:steel";

struct WellDrop {
    float from = 0;
    float fell = 0;
}

WellDrop dropIntoWell(ref Script world, Position port) {
    world.mode(MovementMode.noclip);
    world.game.placeAt(port, Length(0));
    world.press(WELL_ASIDE / walk.NOCLIP_SPEED, Key.forward);
    world.press(WELL_DOWN / walk.NOCLIP_SPEED, Key.down);
    float start = world.altitude().value;
    world.mode(MovementMode.walk);
    world.wait(walk.LANDING_SECONDS);
    return WellDrop(start, start - world.altitude().value);
}

void structureWell(ref Script world) {
    world.structure("city");
    Maybe!Position port = walk.ensurePort(world);
    world.check(port.exists, "found no port among the vertices nearest the city's root");
    if (!world.isFailed) {
        WellDrop drop = dropIntoWell(world, port.value);
        Maybe!Material below = walk.lookBelow(world);
        const(char)[] name = walk.nameOf(below);
        world.claim(Topic.structures, "Under a port in the city's streets a stair well runs down through the rock: a body let go in it most of an edge below the street drops less than one turn of the stair and lands on a steel tread, the city's own.", world.isOnGround() && drop.fell > 0 && drop.fell < WELL_TURN && walk.isMaterial(below, WELL_STAIR), Measure.of("let go this far below the street", -drop.from), Measure.of("dropped", drop.fell), Measure.of("one turn of the stair", WELL_TURN), Measure.of("landed on", name));
    }
}

enum string VAULT_WELL_STAIR = "base:marble";

void structureVaultWell(ref Script world) {
    world.structure("vaults");
    Maybe!Position port = walk.ensurePort(world);
    world.check(port.exists, "found no port among the vertices nearest the vaults' start");
    if (!world.isFailed) {
        WellDrop drop = dropIntoWell(world, port.value);
        Maybe!Material below = walk.lookBelow(world);
        const(char)[] name = walk.nameOf(below);
        world.claim(Topic.structures, "A well's stair is made of its ground's own stone: under the vaults a body let go in a port's well lands on a marble tread.", world.isOnGround() && drop.fell > 0 && drop.fell < WELL_TURN && walk.isMaterial(below, VAULT_WELL_STAIR), Measure.of("let go this far below the floor", -drop.from), Measure.of("dropped", drop.fell), Measure.of("landed on", name));
    }
}

enum string WELL_RIG = "wellstair";
enum int WELL_RIG_EDGES = 3;
enum float WELL_RIG_SHORT = 0.25f;

void structureWellStair(ref Script world) {
    world.structure(WELL_RIG);
    world.enterRoute();
    world.wait(walk.SETTLE_SECONDS);
    world.check(world.isOnGround(), "standing on the top tread of the rig's well");
    float start = world.altitude().value;
    size_t reached = climb.follow(world, Maybe!size_t.init);
    world.wait(walk.SETTLE_SECONDS);
    float descended = (start - world.altitude().value) / world.game.world.graph.view.edgeOf();
    const(char)[] below = walk.nameOf(walk.lookBelow(world));
    world.claim(Topic.structures, "A well's stair can be walked down past the joints between its edges: a body follows it on foot from the mouth to its last tread three edges down.", !world.routeWaypoint(reached + 1).exists && world.isOnGround() && descended > WELL_RIG_EDGES - WELL_RIG_SHORT, Measure.of("stops reached", reached), Measure.of("edges descended", descended), Measure.of("standing on", below));
}

enum int FLIGHT_EDGES = 3;
enum double LEAST_TREAD_TURN = 15;
enum double MOST_TREAD_TURN = 60;

double turnBetween(double from, double to) {
    double turn = to - from;
    if (turn > 180) {
        return turn - 360;
    } else if (turn <= -180) {
        return turn + 360;
    } else {
        return turn;
    }
}

void checkFlight(ref Script world, string stair) {
    Maybe!SiteFrame port = walk.ensurePortSite(world);
    world.check(port.exists, "found no port among the vertices nearest the world's root");
    if (!world.isFailed) {
        Graph* graph = &world.game.world.graph;
        SiteFrame up = graph.view.turnSite(port.value, Turn.pitchUp);
        int cells = edgeCells(graph.layout.dimension);
        int deepest = FLIGHT_EDGES * cells;
        if (!graph.horospheres.crustOf(ROOT).isBottomless()) {
            float crust = graph.view.ensureUndersideAt(ROOT, walk.ensureVertex(*graph, port.value)) / graph.view.edgeOf();
            deepest = lowerOf(deepest, cast(int)(crust * cells));
        }
        Material material = materialNamed(stair);
        walk.TreadSeen above = walk.treadIn(world, up, material, -1);
        double way = 0;
        uint broken = 0;
        int firstBroken = 0;
        uint brokenCells = 0;
        Maybe!Material brokenBy;
        int z = -2;
        while (z >= -deepest) {
            walk.TreadSeen here = walk.treadIn(world, up, material, z);
            double turn = turnBetween(above.degrees, here.degrees);
            if (way == 0) {
                way = turn;
            }
            bool stepped = here.cells > 0 && above.cells > 0 && turn * way > 0 && fabs(turn) >= LEAST_TREAD_TURN && fabs(turn) <= MOST_TREAD_TURN;
            if (!stepped) {
                if (broken == 0) {
                    firstBroken = -z;
                    brokenCells = here.cells;
                    brokenBy = here.other;
                }
                broken += 1;
            }
            above = here;
            z -= 1;
        }
        world.claim(Topic.structures, "A well's stair is one flight: going down its shaft a cell at a time through the rock, the tread moves on round the shaft by one step, the same way round every time, across the joints between the edges it is painted in.", broken == 0, Measure.of("stair", stair), Measure.of("cells down the shaft read", deepest), Measure.of("steps that broke the flight", broken), Measure.of("first broken this many cells down", firstBroken), Measure.of("tread cells there", brokenCells), Measure.of("also there", walk.nameOf(brokenBy)));
    }
}

void wellFlight(string name, string stair)(ref Script world) {
    world.structure(name);
    checkFlight(world, stair);
}

void wildWellFlight(string stair)(ref Script world) {
    world.terrain();
    checkFlight(world, stair);
}


enum uint POLE_FLIGHTS = 3;
enum size_t MOST_POLE_VERTICES = 512;
enum double TREAD_STEP = 45;
enum int POLE_JOINT_ROWS = 3;

struct PoleRead {
    uint rows;
    uint broken;
    int firstBroken;
}

bool isNearJoint(int z, int cells) {
    int along = (z % cells + cells) % cells;
    return along <= POLE_JOINT_ROWS || along >= cells - 1 - POLE_JOINT_ROWS;
}

PoleRead readPole(ref Script world, SiteFrame up, Material step, int from, int to, int cells) {
    PoleRead read;
    double start = 0;
    double turn = 0;
    int anchor = from;
    int z = from;
    while (z <= to) {
        walk.TreadSeen here = walk.treadIn(world, up, step, z);
        if (isNearJoint(z, cells)) {
            z += 1;
        } else if (read.rows == 0) {
            start = here.degrees;
            anchor = z;
            read.rows = 1;
            z += 1;
        } else {
            if (read.rows == 1) {
                turn = TREAD_STEP;
                if (turnBetween(start, here.degrees) < 0) {
                    turn = -TREAD_STEP;
                }
            }
            double off = turnBetween(fmod(start + turn * (z - anchor), 360), here.degrees);
            if (here.cells == 0 || fabs(off) > LEAST_TREAD_TURN) {
                if (read.broken == 0) {
                    read.firstBroken = z;
                }
                read.broken += 1;
            }
            read.rows += 1;
            z += 1;
        }
    }
    return read;
}

bool isNearAny(ref Script world, Position at, const(Position)[] seen) {
    float edge = world.game.world.graph.view.edgeOf();
    size_t index = 0;
    while (index < seen.length && !(apartOn(world, seen[index], at) < edge / 2)) {
        index += 1;
    }
    return index < seen.length;
}

void checkPoleFlights(ref Script world, Turn along, int first, int last, uint wanted) {
    Graph* graph = &world.game.world.graph;
    Material step = materialNamed(walk.POLE_STEP);
    int cells = edgeCells(graph.layout.dimension);
    SiteFrame[MOST_POLE_VERTICES] sites;
    Position[POLE_FLIGHTS] lines;
    sites[0] = rootSite(graph.anchorSlot);
    size_t count = 1;
    size_t next = 0;
    uint flights = 0;
    while (flights < wanted && next < count && !world.isFailed) {
        SiteFrame site = graph.view.moveToLevel(sites[next], 0);
        next += 1;
        Position vertex = walk.ensureVertex(*graph, site);
        if (!isNearAny(world, vertex, lines[0 .. flights])) {
            SiteFrame line = graph.view.turnSite(site, along);
            Maybe!int pair = walk.stairPairOn(world, line, step, cells, first, last);
            if (pair.exists) {
                SiteFrame foot = graph.view.moveToLevel(forwarded(line, pair.value), 0);
                PoleRead read = readPole(world, foot, step, 1, 2 * cells - 2, cells);
                world.claim(Topic.structures, "A pole stair in the lattice is one flight over the joint between two edges: read a cell at a time along the pole on both sides of the landing at the joint, each tread lies as many steps further round the pole, the same way round, as it lies cells further on.", read.broken == 0, Measure.of("ground vertex searched", next), Measure.of("first edge of the stair, counted along the line from the ground", pair.value), Measure.of("cells read", read.rows), Measure.of("cells off the flight", read.broken), Measure.of("first off this many cells from the stair's foot", read.firstBroken), Measure.of("joint this many cells from the stair's foot", cells));
                lines[flights] = vertex;
                flights += 1;
            }
        }
        if (count + 3 <= MOST_POLE_VERTICES) {
            SiteFrame ahead = forwarded(site, 1);
            sites[count] = ahead;
            sites[count + 1] = graph.view.turnSite(ahead, Turn.left);
            sites[count + 2] = graph.view.turnSite(ahead, Turn.right);
            count += 3;
        }
    }
    world.check(flights == wanted, "found %u pole stairs of two edges along the lines through the ground's vertices, not %u", flights, wanted);
}

void structureLatticeFlight(ref Script world) {
    world.structure("lattice");
    checkPoleFlights(world, Turn.pitchUp, 0, walk.POLE_LINE_EDGES - 1, POLE_FLIGHTS);
}

enum int VOID_HIGHEST_EDGE = -3;
enum int VOID_LOWEST_EDGE = -9;
enum uint VOID_FLIGHTS = 1;

void structureVoidFlight(ref Script world) {
    world.terrain();
    checkPoleFlights(world, Turn.pitchUp, VOID_LOWEST_EDGE, VOID_HIGHEST_EDGE, VOID_FLIGHTS);
}

enum float DECK_ASIDE = 1.5f;
enum float OFF_DECK_ASIDE = 6;
immutable int[6] DECK_PROBES = [6, 12, 18, 30, 36, 42];
enum int MAZE_WALK_CELLS = 47;
enum float MAZE_STOP_EVERY = 6;
enum float MAZE_STANDING = 0.12f;
enum float MAZE_FELL = 0.1f;
enum double OFF_DECK_SECONDS = 1;

bool isDeckAt(ref Script world, SiteFrame way, int z) {
    Material deck = materialNamed(walk.MAZE_DECK);
    world.game.generateWithin(walk.columnPosition(world, way, DECK_ASIDE, 0, z + 0.5f), world.game.blockLength());
    Maybe!Material over = walk.generatedAt(world, walk.columnPosition(world, way, DECK_ASIDE, 0.5f, z + 0.5f));
    Maybe!Material under = walk.generatedAt(world, walk.columnPosition(world, way, DECK_ASIDE, -0.5f, z + 0.5f));
    return (over.exists && over.value == deck) || (under.exists && under.value == deck);
}

Maybe!SiteFrame ensureMazeWalk(ref Script world, HorosphereId maze) {
    Graph* graph = &world.game.world.graph;
    SiteFrame foot = graph.horospheres.horosphere(maze).foot;
    SiteFrame[4] ways = walk.waysAt(*graph, foot);
    Maybe!SiteFrame found;
    foreach (way; ways) {
        uint decked = 0;
        foreach (z; DECK_PROBES) {
            if (isDeckAt(world, way, z)) {
                decked += 1;
            }
        }
        if (!found.exists && decked == DECK_PROBES.length) {
            found = Maybe!SiteFrame.of(way);
        }
    }
    return found;
}

float heightOver(ref Script world, HorosphereId maze) {
    return world.game.world.graph.view.ensurePlaneHeight(maze, world.game.characterState.position);
}

void structureMaze(ref Script world) {
    world.terrain();
    Maybe!HorosphereId maze = walk.ensureMaze(world);
    if (!world.isFailed) {
        Maybe!SiteFrame way = ensureMazeWalk(world, maze.value);
        world.check(way.exists, "no walkway of the maze runs two edges on from its foot");
        if (!world.isFailed) {
            Graph* graph = &world.game.world.graph;
            standAt(world, walk.ensureOnMaze(*graph, way.value, ColumnSpot(DECK_ASIDE, 0, 0.5f)));
            float stood = heightOver(world, maze.value);
            bool standing = world.isOnGround() && stood > 0 && stood < MAZE_STANDING;
            world.claim(Topic.structures, "The hanging maze holds a body up: set down on a walkway, it stands on the deck just over the maze's plane.", standing, Measure.of("standing this far over the plane", stood));
            Stops stops;
            float z = MAZE_STOP_EVERY;
            while (z < MAZE_WALK_CELLS) {
                stops.add(walk.ensureOnMaze(*graph, way.value, ColumnSpot(DECK_ASIDE, 0, z + 0.5f)));
                z += MAZE_STOP_EVERY;
            }
            stops.add(walk.ensureOnMaze(*graph, way.value, ColumnSpot(DECK_ASIDE, 0, MAZE_WALK_CELLS + 0.5f)));
            Motion motion;
            walk.trackMotion(world, &motion);
            float start = world.traveled().value;
            size_t reached = climb.followStops(world, stops.items[0 .. stops.count]);
            world.wait(walk.SETTLE_SECONDS);
            world.onStep(StepHook.init);
            float walked = world.traveled().value - start;
            float edges = walked / graph.view.edgeOf();
            float after = heightOver(world, maze.value);
            Maybe!Material below = walk.lookBelow(world);
            world.claim(Topic.structures, "The hanging maze's walkways run on along the honeycomb's lines: a body walks along one from beside a vertex to beside the vertex two edges on and never leaves the deck.", reached == stops.count && motion.offGround == 0 && world.isOnGround() && walk.isMaterial(below, walk.MAZE_DECK) && after > 0 && after < MAZE_STANDING, Measure.of("stops reached", reached), Measure.of("stops", stops.count), Measure.of("edges walked", edges), Measure.of("steps off the ground", motion.offGround), Measure.of("over the plane at the end", after));
            world.look(climb.waypointTo(world, walk.ensureOnMaze(*graph, way.value, ColumnSpot(OFF_DECK_ASIDE, 0, MAZE_WALK_CELLS - MAZE_STOP_EVERY))).yaw, degrees(0));
            world.press(OFF_DECK_SECONDS, Key.forward);
            world.wait(OFF_DECK_SECONDS);
            float off = heightOver(world, maze.value);
            world.claim(Topic.structures, "The hanging maze has no walls or rails: a body that walks off the side of a walkway falls below the maze's plane.", !world.isOnGround() && off < -MAZE_FELL, Measure.of("over the plane a second after stepping off", off));
        }
    }
}

enum float VOID_DEPTH = 6.6f;
enum double VOID_FALL_SECONDS = 1;
enum float VOID_LEAST_FALL = 0.2f;
immutable string[11] LATTICE_MATERIALS = ["base:steel", "base:concrete", "base:basalt", "base:wood-planks", "base:red-sandstone", "base:marble", "base:grey-brick", "base:oak-leaves", "base:grass", "base:dirt", "base:andesite"];

void structureVoid(ref Script world) {
    world.terrain();
    world.mode(MovementMode.noclip);
    world.press(VOID_DEPTH / walk.NOCLIP_SPEED, Key.down);
    float start = world.altitude().value;
    world.mode(MovementMode.walk);
    world.wait(VOID_FALL_SECONDS);
    float fell = start - world.altitude().value;
    world.claim(Topic.structures, "The default world's ground has a bottom: a body let go far enough under it is in the open and falls.", fell >= VOID_LEAST_FALL, Measure.of("let go this far below the ground", -start), Measure.of("fell in a second", fell));
    world.wait(walk.LANDING_SECONDS);
    Maybe!Material below = walk.lookBelow(world);
    const(char)[] name = walk.nameOf(below);
    world.claim(Topic.structures, "The void under the default world's ground comes in layers, a lattice near the underside and floating islands below it: a body let go under spawn lands on one of them.", world.isOnGround() && walk.isOneOf(below, LATTICE_MATERIALS[]), Measure.of("landed this far below the ground", -world.altitude().value), Measure.of("landed on", name));
}

enum double WINDOW_FALL_SECONDS = 1;

float undersideEdges(ref Script world, Position at) {
    return world.game.world.graph.view.ensureUndersideAt(ROOT, at) / world.game.world.graph.view.edgeOf();
}

uint solidCellsAt(ref Script world, Position at) {
    world.game.generateWithin(at, Length(0));
    SolidProbe probe = SolidProbe(world.game.bodySolid());
    visitCells(world.game.world.graph, at, Length(0), probe);
    return probe.solidCells;
}

void structureWindow(ref Script world) {
    world.terrain();
    Maybe!Position window = walk.ensureUnderGround(world, walk.Beneath.open);
    world.check(window.exists, "no node %d and a half edges under a ground vertex near spawn is in the open void", walk.BENEATH_EDGES);
    if (!world.isFailed) {
        float rock = undersideEdges(world, window.value);
        world.mode(MovementMode.noclip);
        world.game.placeAt(window.value, Length(0));
        uint solid = solidCellsAt(world, world.game.characterState.position);
        float start = world.altitude().value;
        world.mode(MovementMode.walk);
        world.wait(WINDOW_FALL_SECONDS);
        float fell = start - world.altitude().value;
        world.claim(Topic.structures, "Near spawn the default world's crust is thin in places: a body let go three and a half edges under the ground there is in the open and falls.", solid == 0 && fell >= VOID_LEAST_FALL, Measure.of("let go this far below the ground", -start), Measure.of("rock ends there this many edges down", rock), Measure.of("solid cells where it was let go", solid), Measure.of("fell in a second", fell));
    }
}

void structureShield(ref Script world) {
    world.terrain();
    Maybe!Position shield = walk.ensureUnderGround(world, walk.Beneath.rock);
    world.check(shield.exists, "no node %d and a half edges under a ground vertex near spawn is in rock", walk.BENEATH_EDGES);
    if (!world.isFailed) {
        float rock = undersideEdges(world, shield.value);
        world.mode(MovementMode.noclip);
        world.game.placeAt(shield.value, Length(0));
        uint solid = solidCellsAt(world, world.game.characterState.position);
        world.claim(Topic.structures, "Near spawn the default world's crust is thick in places: three and a half edges under the ground there, a body is inside solid rock.", solid > 0, Measure.of("placed this far below the ground", -world.altitude().value), Measure.of("rock ends there this many edges down", rock), Measure.of("solid cells where the body is", solid));
    }
}

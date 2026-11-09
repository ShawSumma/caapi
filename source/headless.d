module headless;

import core.stdc.stdio : FILE, fflush, fprintf, printf, stderr;
import base.array : Array;
import base.clock : nowSeconds;
import base.crash : reportCrashes, reportHangAfter;
import base.maybe : Maybe;
import base.names : ENUM_NAMES;
import base.numbers : higherOf, lowerOf;
import base.splitmix : SplitMix;
import base.units : Ratio, Time;
import client.arguments : ArgumentCursor, ExitStatus, HELP_OPTION, NOT_A_NUMBER, OUTPUT_OPTION, OptionSpec, REPORT_UNOPENED, StartupError, UNKNOWN_OPTION, VERSION_OPTION, VERSION_TEXT, WORLDGEN_OPTION, WorldgenArgument, closeReport, exitStatus, numberIn, openReport, optionNamed, parseOptions, sliceOf, usageOf;
import client.config : ClientConfig;
import client.game : ChunkSupply, Game;
import client.plugins : gatherWorlds, registry;
import client.script : NamedScript, Script;
import client.structures : StructureProblem, placeStructure;
import common.biology.breeding : productOf;
import common.biology.kinetics : Route;
import common.biology.molecule : Molecule;
import common.biology.occupancy : occupanciesOf;
import common.biology.organism : Dose, Organism, starterDoses, starterGenome;
import common.biology.pocket : Binding;
import common.biology.wild : WildGenes, differingGenes;
import common.content.content : content;
import common.content.exporting : writeGraphData, writeGraphDot, writeGraphJson;
import common.graph : Graph, ROOT_NODE;
import common.items : materialNames;
import common.material : isLiving, materialCount;
import common.perception : Channel, Perception, felt;
import common.settings : CHUNK_DIMENSION;
import common.worldgen.generation : PlaneWorld, Worldgen, WorldgenKind;
import geometry.honeycomb : FACE_COUNT, Face;
import plugins.api.api : Material;
import scripts.claims : Outcome, isPrefixOf, ledger, namesTopic, writeClaimLines, writeDot, writeProblems, writeTally, writeWiki;
import scripts.films : FILMS;
import scripts.tests : TESTS;
import scripts.views : VIEWS;
import worldcheck : benchDrive, benchGen, benchHashMap, benchMesh, benchNearby, checkContent, checkForget, checkRepaint, dumpStructure, dumpWorld, printMaterialCensus, printSlices, printSurfaceCensus, printWorldDigest;

enum float DEFAULT_DUMP_RADIUS = 3.0f;
enum float DEFAULT_GEN_RADIUS = 2.5f;
enum float DEFAULT_NEARBY_RADIUS = 4.5f;
enum uint DEFAULT_NEARBY_ITERATIONS = 50;
enum int DEFAULT_SLICE_HEIGHT = 1;
enum uint TEST_HANG_SECONDS = 120;
enum float LEAST_TABLE_CONCENTRATION = 0.001f;
enum float MOST_TABLE_CONCENTRATION = 10;
enum float TABLE_CONCENTRATION_STEP = 10;
enum uint TABLE_ROWS = 31;
enum Time TABLE_ROW_SECONDS = Time(2);
enum uint CENSUS_DEPTH = 40;
enum size_t CENSUS_WIDTH = 2000;
enum Ratio CENSUS_DOSE = Ratio(1);
enum Ratio CENSUS_ACTING = Ratio(0.1f);
enum uint CENSUS_SELECTIVE = 2;
enum uint MOST_RECEPTORS_COUNTED = 16;
enum uint CENSUS_RANDOM_SAMPLES = 4000;
enum uint CENSUS_FELT_SAMPLES = 100;
enum Time CENSUS_FELT_AFTER = Time(4);
immutable Channel[5] CENSUS_CHANNELS = [Channel.revealMist, Channel.afterimage, Channel.fieldOfView, Channel.gravity, Channel.jumpHeight];
enum ulong CENSUS_RANDOM_SALT = 0x5A_4D1E;
enum string USAGE = "usage: caapi-headless [options] <command> [name prefix ...]\noptions:\n" ~ usageOf(OPTIONS[]) ~ "commands:\n" ~ usageOf(COMMANDS[]);

enum Option : ubyte {
    worldgen,
    output,
    radius,
    iterations,
    height,
    help,
    showVersion,
}

immutable OptionSpec[Option.max + 1] OPTIONS = [
    Option.worldgen: WORLDGEN_OPTION,
    Option.output: OUTPUT_OPTION,
    Option.radius: OptionSpec("--radius", "<units>", "how far a census, dump or benchmark reaches"),
    Option.iterations: OptionSpec("--iterations", "<count>", "how many times bench-nearby runs"),
    Option.height: OptionSpec("--height", "<cells>", "the height slice prints"),
    Option.help: HELP_OPTION,
    Option.showVersion: VERSION_OPTION,
];

enum Command : ubyte {
    tests,
    views,
    films,
    claims,
    wiki,
    wikiDot,
    worldDigest,
    dumpWorld,
    materialCensus,
    surfaceCensus,
    dumpStructure,
    slice,
    checkRepaint,
    checkForget,
    benchGen,
    benchMesh,
    benchDrive,
    benchNearby,
    benchHashMap,
    biologyTables,
    wildCensus,
    contentGraph,
    contentDot,
    contentData,
    contentCheck,
}

immutable OptionSpec[Command.max + 1] COMMANDS = [
    Command.tests: OptionSpec("tests", "", "run the behavior tests (all, or those whose names start with a prefix)"),
    Command.views: OptionSpec("views", "", "run the screenshot view scripts without rendering, to check they still run"),
    Command.films: OptionSpec("films", "", "run the film shots without rendering, to check they still run"),
    Command.claims: OptionSpec("claims", "", "run the behavior tests and print every claim they state with what was measured (all, or by test name prefix or topic)"),
    Command.wiki: OptionSpec("wiki", "", "run the behavior tests and write their claims as one Markdown page (all, or by test name prefix or topic)"),
    Command.wikiDot: OptionSpec("wiki-dot", "", "run the behavior tests and write the topics and the links between them for Graphviz"),
    Command.worldDigest: OptionSpec("world-digest", "", "hash the terrain world"),
    Command.dumpWorld: OptionSpec("dump-world", "", "print the terrain world"),
    Command.materialCensus: OptionSpec("material-census", "", "count the terrain world's materials"),
    Command.surfaceCensus: OptionSpec("surface-census", "", "count the terrain world's surfaces"),
    Command.dumpStructure: OptionSpec("dump-structure", "", "print a structure world"),
    Command.slice: OptionSpec("slice", "", "print slices of a structure world"),
    Command.checkRepaint: OptionSpec("check-repaint", "", "check a dropped tile repaints identically"),
    Command.checkForget: OptionSpec("check-forget", "", "check evicted structure state regenerates identically"),
    Command.benchGen: OptionSpec("bench-gen", "", "benchmark generation"),
    Command.benchMesh: OptionSpec("bench-mesh", "", "benchmark meshing"),
    Command.benchDrive: OptionSpec("bench-drive", "", "benchmark driving through the world"),
    Command.benchNearby: OptionSpec("bench-nearby", "", "benchmark the nearby traversal"),
    Command.benchHashMap: OptionSpec("bench-hashmap", "", "benchmark the hash map"),
    Command.biologyTables: OptionSpec("biology-tables", "", "print dose-response and time-course tables for the starter body and doses"),
    Command.wildCensus: OptionSpec("wild-census", "", "print how far wild genomes drift from the root's with depth, and how well their products bind the starter body"),
    Command.contentGraph: OptionSpec("content-graph", "", "print the content graph of every loaded mod as JSON"),
    Command.contentDot: OptionSpec("content-dot", "", "print the content graph of every loaded mod for Graphviz"),
    Command.contentData: OptionSpec("content-data", "", "print the content of the named mods, or of every mod, in the data format"),
    Command.contentCheck: OptionSpec("content-check", "", "place every world, then check every item can be reached and has uses"),
];

enum RunKind : ubyte {
    command,
    help,
    showVersion,
}

struct HeadlessArguments {
    Array!(const(char)*) prefixes;
    StartupError error;
    const(char)* outputPath;
    Worldgen worldgen;
    Maybe!float radius;
    Maybe!float iterations;
    Maybe!float height;
    Maybe!Command command;
    RunKind kind;

    static HeadlessArguments fromArgv(int argc, char** argv) {
        HeadlessArguments arguments;
        arguments.parseOptions!Option(OPTIONS[], argc, argv);
        return arguments;
    }

    void apply(Option option, ref ArgumentCursor cursor) {
        final switch (option) {
            case Option.worldgen:
                parseWorldgen(cursor);
                break;
            case Option.output:
                outputPath = cursor.next();
                break;
            case Option.radius:
                radius = number(option, cursor.next());
                break;
            case Option.iterations:
                iterations = number(option, cursor.next());
                break;
            case Option.height:
                height = number(option, cursor.next());
                break;
            case Option.help:
                kind = RunKind.help;
                cursor.stop();
                break;
            case Option.showVersion:
                kind = RunKind.showVersion;
                cursor.stop();
                break;
        }
    }

    void applyPositional(const(char)* argument) {
        if (argument[0] == '-') {
            error = StartupError(null, UNKNOWN_OPTION, argument);
        } else if (!command.exists) {
            command = optionNamed!Command(COMMANDS[], sliceOf(argument));
            if (!command.exists) {
                error = StartupError(null, "unknown command", argument);
            }
        } else if (takesPrefixes()) {
            prefixes.append(argument);
        } else {
            error = StartupError(null, "unexpected", argument);
        }
    }

    void parseWorldgen(ref ArgumentCursor cursor) {
        WorldgenArgument parsed = WorldgenArgument.from(cursor);
        worldgen = parsed.worldgen;
        error = parsed.error;
    }

    Maybe!float number(Option option, const(char)* text) {
        Maybe!float parsed = numberIn(text);
        if (!parsed.exists) {
            error = StartupError(null, NOT_A_NUMBER, text, OPTIONS[option].name);
        }
        return parsed;
    }

    bool takesPrefixes() const {
        return command.value == Command.tests || command.value == Command.views || command.value == Command.films || command.value == Command.claims || command.value == Command.wiki || command.value == Command.wikiDot || command.value == Command.contentData;
    }

    bool needsStructure() const {
        return command.value == Command.dumpStructure || command.value == Command.slice || command.value == Command.checkRepaint || command.value == Command.checkForget;
    }

    StartupError usageError() const {
        if (kind != RunKind.command) {
            return StartupError.init;
        } else if (!command.exists) {
            return StartupError(null, "nothing to do: give a command");
        } else if (needsStructure() && worldgen.kind != WorldgenKind.structure) {
            return StartupError(registry().allNames(), "needs a structure world", null, COMMANDS[command.value].name);
        } else {
            return StartupError.init;
        }
    }

    float commandRadius() const {
        if (radius.exists) {
            return radius.value;
        } else if (command.value == Command.dumpWorld || command.value == Command.worldDigest || command.value == Command.materialCensus || command.value == Command.surfaceCensus) {
            return DEFAULT_DUMP_RADIUS;
        } else if (command.value == Command.benchNearby) {
            return DEFAULT_NEARBY_RADIUS;
        } else {
            return DEFAULT_GEN_RADIUS;
        }
    }

    int sliceHeight() const {
        if (height.exists) {
            return cast(int) height.value;
        } else {
            return DEFAULT_SLICE_HEIGHT;
        }
    }

    uint iterationCount() const {
        if (iterations.exists) {
            return cast(uint) iterations.value;
        } else {
            return DEFAULT_NEARBY_ITERATIONS;
        }
    }
}

bool isChosen(ref const HeadlessArguments arguments, string name) {
    size_t index = 0;
    while (index < arguments.prefixes.length && !isPrefixOf(sliceOf(arguments.prefixes.ptr[index]), name)) {
        index += 1;
    }
    return arguments.prefixes.length == 0 || index < arguments.prefixes.length;
}

ExitStatus runTest(ref const NamedScript test, Worldgen worldgen, FILE* report) {
    double start = nowSeconds();
    fprintf(report, "== %.*s\n", cast(int) test.name.length, test.name.ptr);
    fflush(report);
    reportHangAfter(TEST_HANG_SECONDS);
    ClientConfig config;
    Game game = Game.make(worldgen, config.reach);
    game.supply = ChunkSupply.onDemand;
    StructureProblem problem = game.placeStructure();
    ExitStatus status = ExitStatus.failed;
    ledger.begin(test.name);
    if (problem.isPresent) {
        fprintf(report, "%s\n", problem.text.ptr);
        ledger.end(Outcome.failed, sliceOf(problem.text.ptr));
    } else {
        Script script = Script.make(&game, report);
        status = script.run(test.run);
        fprintf(report, "session: steps=%u time=%.2f traveled=%.2f wall=%.1fs%s\n", script.steps, cast(double) game.time.value, cast(double) game.traveled.value, nowSeconds() - start, sessionSuffix(status));
        ledger.end(outcomeOf(status), sliceOf(script.failure.ptr));
    }
    fflush(report);
    game.release();
    return status;
}

Outcome outcomeOf(ExitStatus status) {
    if (status == ExitStatus.ok) {
        return Outcome.passed;
    } else {
        return Outcome.failed;
    }
}

enum ClaimForm : ubyte {
    lines,
    wiki,
    dot,
}

ExitStatus runClaims(ref const HeadlessArguments arguments, FILE* output, ClaimForm form) {
    Array!(const(char)[]) selectors;
    foreach (name; arguments.prefixes.slice()) {
        selectors.append(sliceOf(name));
    }
    FILE* progress = stderr;
    if (form == ClaimForm.lines) {
        progress = output;
    }
    foreach (ref test; TESTS) {
        if (arguments.isChosen(test.name) || namesTopic(selectors.slice())) {
            runTest(test, arguments.worldgen, progress);
            if (form == ClaimForm.lines) {
                writeClaimLines(output, ledger, cast(uint) ledger.tests.length - 1, selectors.slice());
            }
        }
    }
    final switch (form) {
        case ClaimForm.lines:
            break;
        case ClaimForm.wiki:
            writeWiki(output, ledger, selectors.slice());
            break;
        case ClaimForm.dot:
            writeDot(output, ledger, selectors.slice());
            break;
    }
    writeTally(progress, ledger, selectors.slice());
    uint problems = writeProblems(progress, ledger);
    bool clean = problems == 0 && ledger.tallyOf(selectors.slice()).failedTests == 0;
    selectors.release();
    return exitStatus(clean);
}

immutable(char)* sessionSuffix(ExitStatus status) {
    if (status == ExitStatus.ok) {
        return "";
    } else {
        return " error";
    }
}

ExitStatus runFilms(ref const HeadlessArguments arguments, FILE* report) {
    ExitStatus status = ExitStatus.ok;
    foreach (ref film; FILMS) {
        ExitStatus ran = runScripts(arguments, film.shots, report);
        if (ran != ExitStatus.ok) {
            status = ExitStatus.failed;
        }
    }
    return status;
}

ExitStatus runScripts(ref const HeadlessArguments arguments, const(NamedScript)[] scripts, FILE* report) {
    uint passed = 0;
    uint failed = 0;
    foreach (ref test; scripts) {
        if (arguments.isChosen(test.name)) {
            ExitStatus ran = runTest(test, arguments.worldgen, report);
            if (ran == ExitStatus.ok) {
                passed += 1;
            } else {
                failed += 1;
            }
        }
    }
    fprintf(report, "%u passed, %u failed\n", passed, failed);
    return exitStatus(failed == 0);
}

ExitStatus runCommand(ref const HeadlessArguments arguments, FILE* output) {
    float radius = arguments.commandRadius();
    ExitStatus status = ExitStatus.ok;
    final switch (arguments.command.value) {
        case Command.tests:
            status = runScripts(arguments, TESTS, output);
            break;
        case Command.views:
            status = runScripts(arguments, VIEWS, output);
            break;
        case Command.films:
            status = runFilms(arguments, output);
            break;
        case Command.claims:
            status = runClaims(arguments, output, ClaimForm.lines);
            break;
        case Command.wiki:
            status = runClaims(arguments, output, ClaimForm.wiki);
            break;
        case Command.wikiDot:
            status = runClaims(arguments, output, ClaimForm.dot);
            break;
        case Command.worldDigest:
            status = printWorldDigest(output, radius, CHUNK_DIMENSION);
            break;
        case Command.dumpWorld:
            status = dumpWorld(output, radius, CHUNK_DIMENSION);
            break;
        case Command.materialCensus:
            status = printMaterialCensus(output, radius, CHUNK_DIMENSION);
            break;
        case Command.surfaceCensus:
            status = printSurfaceCensus(output, radius, CHUNK_DIMENSION);
            break;
        case Command.dumpStructure:
            status = dumpStructure(output, CHUNK_DIMENSION, arguments.worldgen);
            break;
        case Command.slice:
            status = printSlices(output, CHUNK_DIMENSION, arguments.worldgen, arguments.sliceHeight());
            break;
        case Command.checkRepaint:
            status = checkRepaint(output, CHUNK_DIMENSION, arguments.worldgen);
            break;
        case Command.checkForget:
            status = checkForget(output, CHUNK_DIMENSION, arguments.worldgen);
            break;
        case Command.benchGen:
            benchGen(output, radius, CHUNK_DIMENSION);
            break;
        case Command.benchMesh:
            benchMesh(output, radius, CHUNK_DIMENSION);
            break;
        case Command.benchDrive:
            benchDrive(output, radius, CHUNK_DIMENSION);
            break;
        case Command.benchNearby:
            benchNearby(output, radius, arguments.iterationCount(), CHUNK_DIMENSION);
            break;
        case Command.benchHashMap:
            benchHashMap(output);
            break;
        case Command.biologyTables:
            printBiologyTables(output);
            break;
        case Command.wildCensus:
            printWildCensus(output);
            break;
        case Command.contentGraph:
            writeGraphJson(output, content());
            break;
        case Command.contentDot:
            writeGraphDot(output, content());
            break;
        case Command.contentData:
            writeModData(arguments, output);
            break;
        case Command.contentCheck:
            status = checkContent(output, CHUNK_DIMENSION);
            break;
    }
    return status;
}

void writeModData(ref const HeadlessArguments arguments, FILE* output) {
    Array!(const(char)[]) mods;
    foreach (name; arguments.prefixes.slice()) {
        mods.append(sliceOf(name));
    }
    writeGraphData(output, content(), mods.slice());
    mods.release();
}

void printSpeciesCensus(FILE* output, ref Organism organism, Material species) {
    uint[MOST_RECEPTORS_COUNTED] targets;
    uint acting = 0;
    uint selective = 0;
    SplitMix draw = SplitMix(CENSUS_RANDOM_SALT);
    float[CENSUS_CHANNELS.length] feltSum = 0;
    foreach (sample; 0 .. CENSUS_RANDOM_SAMPLES) {
        WildGenes genes;
        foreach (ref seed; genes.seeds) {
            seed = draw.next();
        }
        Molecule product = productOf(species, genes);
        if (sample < CENSUS_FELT_SAMPLES) {
            Organism dosed = Organism.make(starterGenome());
            dosed.dose(Dose(product, CENSUS_DOSE, Route.injected));
            dosed.advance(CENSUS_FELT_AFTER);
            Perception made = felt(Perception.init, dosed.signaling.signals[]);
            foreach (index, channel; CENSUS_CHANNELS) {
                feltSum[index] += made.level[channel].value;
            }
            dosed.release();
        }
        uint reach = receptorsActedOn(organism, product);
        if (reach > 0) {
            acting += 1;
        }
        foreach (index, ref receptor; organism.receptors.slice()) {
            if (occupancyAlone(organism.cache.bindingOf(receptor.pocket, product).affinity) > CENSUS_ACTING) {
                targets[lowerOf(cast(uint) index, MOST_RECEPTORS_COUNTED - 1)] += 1;
            }
        }
        if (reach > 0 && reach <= CENSUS_SELECTIVE) {
            selective += 1;
        }
    }
    const(char)[] name = materialNames.ptr[species.id];
    fprintf(output, "%-20.*s %.3f %.3f", cast(int) name.length, name.ptr, cast(double) acting / CENSUS_RANDOM_SAMPLES, cast(double) selective / higherOf(acting, 1u));
    foreach (index, ref receptor; organism.receptors.slice()) {
        fprintf(output, " %c%c:%u", cast(char)('A' + receptor.firstHalf), cast(char)('A' + receptor.secondHalf), targets[lowerOf(cast(uint) index, MOST_RECEPTORS_COUNTED - 1)]);
    }
    foreach (index, channel; CENSUS_CHANNELS) {
        fprintf(output, " %s:%+.3f", ENUM_NAMES!Channel[channel].ptr, cast(double)(feltSum[index] / CENSUS_FELT_SAMPLES));
    }
    fprintf(output, "\n");
}

uint receptorsActedOn(ref Organism organism, Molecule molecule) {
    uint count = 0;
    foreach (ref receptor; organism.receptors.slice()) {
        if (occupancyAlone(organism.cache.bindingOf(receptor.pocket, molecule).affinity) > CENSUS_ACTING) {
            count += 1;
        }
    }
    return count;
}

Ratio occupancyAlone(Ratio affinity) {
    Ratio[1] concentrations = [CENSUS_DOSE];
    Ratio[1] affinities = [affinity];
    Ratio[1] occupied;
    occupanciesOf(concentrations[], affinities[], occupied[]);
    return occupied[0];
}

void printWildCensus(FILE* output) {
    Graph graph = Graph.make(CHUNK_DIMENSION, Worldgen.fromPlane(PlaneWorld(0)));
    graph.bindView();
    Organism organism = Organism.make(starterGenome());
    uint root = graph.slotOf(ROOT_NODE).value;
    WildGenes rootGenes = graph.ensureState(root).wild;
    Array!uint frontier;
    Array!uint next;
    frontier.append(root);
    fprintf(output, "depth nodes mean_genes_differing_from_root\n");
    foreach (depth; 1 .. CENSUS_DEPTH + 1) {
        next.clear();
        foreach (slot; frontier.slice()) {
            foreach (face; 0 .. FACE_COUNT) {
                if (next.length < CENSUS_WIDTH && !graph.isParentFace(slot, cast(Face) face)) {
                    uint child = graph.ensureNeighborSlot(slot, cast(Face) face);
                    if (graph.depthOf(child) == depth) {
                        next.append(child);
                    }
                }
            }
        }
        float differing = 0;
        foreach (slot; next.slice()) {
            differing += differingGenes(graph.ensureState(slot).wild, rootGenes);
        }
        fprintf(output, "%5u %5zu %.3f\n", cast(uint) depth, next.length, cast(double)(differing / next.length));
        Array!uint swapped = frontier;
        frontier = next;
        next = swapped;
    }
    fprintf(output, "species share_acting share_of_those_on_at_most_%u, products acting on each receptor, mean felt level\n", CENSUS_SELECTIVE);
    foreach (id; 1 .. materialCount()) {
        Material species = Material(cast(ubyte) id);
        if (isLiving(species)) {
            printSpeciesCensus(output, organism, species);
        }
    }
    frontier.release();
    next.release();
    organism.release();
    graph.release();
}

void printBiologyTables(FILE* output) {
    Organism organism = Organism.make(starterGenome());
    foreach (index, ref given; starterDoses.slice()) {
        fprintf(output, "dose %zu, %s\n  concentration:", index + 1, ENUM_NAMES!Route[given.route].ptr);
        foreach (receptor; organism.receptors.slice()) {
            fprintf(output, " %c%c", cast(char)('A' + receptor.firstHalf), cast(char)('A' + receptor.secondHalf));
        }
        fprintf(output, "\n");
        float concentration = LEAST_TABLE_CONCENTRATION;
        while (concentration <= MOST_TABLE_CONCENTRATION) {
            fprintf(output, "  %10.4f:", cast(double) concentration);
            foreach (ref receptor; organism.receptors.slice()) {
                Binding binding = organism.cache.bindingOf(receptor.pocket, given.molecule);
                Ratio[1] concentrations = [Ratio(concentration)];
                Ratio[1] affinities = [binding.affinity];
                Ratio[1] occupied;
                occupanciesOf(concentrations[], affinities[], occupied[]);
                fprintf(output, " %.2f", cast(double) occupied[0].value);
            }
            fprintf(output, "\n");
            concentration *= TABLE_CONCENTRATION_STEP;
        }
        Organism dosed = Organism.make(starterGenome());
        dosed.dose(given);
        fprintf(output, "  seconds: blood, then signals\n");
        foreach (row; 0 .. TABLE_ROWS) {
            fprintf(output, "  %7.1f: %.4f", cast(double)(row * TABLE_ROW_SECONDS.value), cast(double) dosed.body.bloodOf(given.molecule).value);
            foreach (signal; dosed.signaling.signals()) {
                fprintf(output, " %+.3f", cast(double) signal.value);
            }
            fprintf(output, "\n");
            dosed.advance(TABLE_ROW_SECONDS);
        }
        dosed.release();
    }
    organism.release();
}

ExitStatus runWithOutput(ref const HeadlessArguments arguments, const(char)* program) {
    FILE* output = openReport(arguments.outputPath);
    if (output is null) {
        StartupError(null, REPORT_UNOPENED, arguments.outputPath).report(program);
        return ExitStatus.failed;
    } else {
        ExitStatus status = runCommand(arguments, output);
        closeReport(output);
        return status;
    }
}

ExitStatus startCommand(ref const HeadlessArguments arguments, const(char)* program) {
    if (arguments.error.isPresent()) {
        arguments.error.report(program);
        return ExitStatus.usage;
    } else if (arguments.kind == RunKind.help) {
        printf("%.*s", cast(int) USAGE.length, USAGE.ptr);
        return ExitStatus.ok;
    } else if (arguments.kind == RunKind.showVersion) {
        printf("%s", VERSION_TEXT.ptr);
        return ExitStatus.ok;
    } else {
        return runWithOutput(arguments, program);
    }
}

extern (C) int main(int argc, char** argv) {
    reportCrashes();
    gatherWorlds();
    HeadlessArguments arguments = HeadlessArguments.fromArgv(argc, argv);
    ExitStatus status = startCommand(arguments, argv[0]);
    ledger.release();
    arguments.prefixes.release();
    return status;
}

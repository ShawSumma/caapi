module scripts.claims;

import base.array : Array;
import base.maybe : Maybe;
import base.names : ENUM_NAMES;
import base.stdio : FILE, fprintf, printed;
import client.arguments : VERSION;
import client.script : Script;

enum size_t LINE_CAPACITY = 1024;
enum char SENTENCE_END = '.';

enum Topic : ubyte {
    space,
    gravity,
    movement,
    world,
    structures,
    climate,
    air,
    blocks,
    crafting,
    learning,
    plants,
    breeding,
    chemistry,
    body,
    perception,
    navigation,
    saves,
    screens,
    mods,
    scripts,
}

enum uint TOPIC_COUNT = Topic.max + 1;

struct TopicInfo {
    string title;
    string intro;
}

TopicInfo infoOf(Topic topic) {
    final switch (topic) {
        case Topic.space:
            return TopicInfo("Space", "Space is hyperbolic. There is exponentially more room farther out, and a path that closes on itself turns whatever is carried along it.");
        case Topic.gravity:
            return TopicInfo("Ground and gravity", "The ground is a plane, and some worlds raise more planes above it. Gravity pulls toward the grounds that are near and blends between them.");
        case Topic.movement:
            return TopicInfo("Movement", "The body walks, jumps, steps up single blocks and slides along what it cannot pass. In creative mode it can also fly, or pass through everything.");
        case Topic.world:
            return TopicInfo("The loaded world", "The world is made as the player comes near and dropped again behind them. What the player changed is kept apart and put back.");
        case Topic.structures:
            return TopicInfo("Built worlds", "Built worlds are laid out along the honeycomb by plugins: cities, towers, stairs and the routes through them.");
        case Topic.climate:
            return TopicInfo("Climate and terrain", "Each cell has a climate: relief, heat, wetness and strata. It decides what the ground is made of and what grows there.");
        case Topic.air:
            return TopicInfo("Air", "The air is a mix of three gases whose shares follow the climate. A collector gathers it over time.");
        case Topic.blocks:
            return TopicInfo("Mining and placing", "A block is mined by holding the mine key for its break time, and placed from the hotbar. Harder blocks need a better pickaxe.");
        case Topic.crafting:
            return TopicInfo("Crafting", "Recipes are queued and worked one at a time, by hand or at a station the player has used nearby.");
        case Topic.learning:
            return TopicInfo("Learning", "Some recipes are unknown until the player notices something, by breaking a block or by working at a station.");
        case Topic.plants:
            return TopicInfo("Plants", "Living blocks carry genes. A planted plant ripens with time and yields more where the climate suits it.");
        case Topic.breeding:
            return TopicInfo("Breeding", "At a bench two plants can be crossed, and a plant's enzyme can be spliced into the player's own genome.");
        case Topic.chemistry:
            return TopicInfo("Compounds", "The genes of a living block make a compound. A press extracts it and turns extract into doses, a lab changes it, and a dose is swallowed, inhaled or injected.");
        case Topic.body:
            return TopicInfo("The body", "A dose moves from the gut or the lung into the blood and is cleared from there. In the blood it binds the body's receptors, which drive three signals.");
        case Topic.perception:
            return TopicInfo("Perception", "The body's signals shift perception. Perception changes how the body moves and how the world looks, and it reveals blocks that are otherwise not there.");
        case Topic.navigation:
            return TopicInfo("Finding the way", "Beacons, a thread laid behind the player and the compass help to find a place again.");
        case Topic.saves:
            return TopicInfo("Saves", "A save holds the player's edits, inventory, body and place for one world.");
        case Topic.screens:
            return TopicInfo("Screens", "The inventory and the station screens.");
        case Topic.mods:
            return TopicInfo("Mods", "Mods add content as data and can react to what happens in play.");
        case Topic.scripts:
            return TopicInfo("Scripts", "Tests, views and films are scripts that drive the game step by step.");
    }
}

enum MeasureKind : ubyte {
    number,
    text,
}

struct Measure {
    string label;
    const(char)[] text;
    double number = 0;
    MeasureKind kind;

    static Measure of(string label, double number) {
        return Measure(label, null, number, MeasureKind.number);
    }

    static Measure of(string label, const(char)[] text) {
        return Measure(label, text, 0, MeasureKind.text);
    }
}

struct Kept {
    string label;
    double number = 0;
    uint textStart;
    uint textLength;
    MeasureKind kind;
}

enum Verdict : ubyte {
    held,
    failed,
}

enum Outcome : ubyte {
    passed,
    failed,
}

enum Part : ubyte {
    own,
    actsOn,
    actedOnBy,
}

struct Claim {
    string law;
    string file;
    Maybe!Topic onto;
    uint line;
    uint test;
    uint firstMeasure;
    uint measureCount;
    uint times;
    Topic topic;
    Verdict verdict;

    bool isIn(Topic about, Part part) const {
        final switch (part) {
            case Part.own:
                return topic == about && !onto.exists;
            case Part.actsOn:
                return topic == about && onto.exists;
            case Part.actedOnBy:
                return onto.exists && onto.value == about;
        }
    }

    bool isSameLawAs(ref const Claim other) const {
        return law == other.law && topic == other.topic && onto == other.onto;
    }
}

struct Tested {
    string name;
    uint firstClaim;
    uint claimCount;
    uint failureStart;
    uint failureLength;
    Outcome outcome;
}

struct Tally {
    uint held;
    uint failed;
    uint tests;
    uint failedTests;
}

struct Line {
    char[LINE_CAPACITY] text = 0;
    size_t length;

    void add(Args...)(const(char)* format, Args args) {
        length += printed(text[length .. $], format, args).length;
    }

    void addMeasure(string label, MeasureKind kind, double number, const(char)[] words) {
        final switch (kind) {
            case MeasureKind.number:
                add("%.*s %.6g", cast(int) label.length, label.ptr, number);
                break;
            case MeasureKind.text:
                add("%.*s %.*s", cast(int) label.length, label.ptr, cast(int) words.length, words.ptr);
                break;
        }
    }
}

immutable(char)* separatorBefore(size_t index) {
    if (index == 0) {
        return "";
    } else {
        return "; ";
    }
}

Line failureLine(ref const Claim stated, const(Measure)[] given) {
    Line line;
    line.add("claim failed at %.*s:%u: %.*s", cast(int) stated.file.length, stated.file.ptr, stated.line, cast(int) stated.law.length, stated.law.ptr);
    if (given.length > 0) {
        line.add(" (");
        foreach (index, measure; given) {
            line.add("%s", separatorBefore(index));
            line.addMeasure(measure.label, measure.kind, measure.number, measure.text);
        }
        line.add(")");
    }
    return line;
}

Verdict verdictOf(bool condition) {
    if (condition) {
        return Verdict.held;
    } else {
        return Verdict.failed;
    }
}

struct Ledger {
    Array!Tested tests;
    Array!Claim claims;
    Array!Kept measures;
    Array!char text;
    Maybe!uint open;

    void begin(string name) {
        open = Maybe!uint.of(cast(uint) tests.length);
        tests.append(Tested(name, cast(uint) claims.length));
    }

    void end(Outcome outcome, const(char)[] failure) {
        Tested* test = &tests.ptr[open.value];
        test.claimCount = cast(uint) claims.length - test.firstClaim;
        test.failureStart = keepText(failure);
        test.failureLength = cast(uint) failure.length;
        test.outcome = outcome;
        open = Maybe!uint.init;
    }

    uint keepText(const(char)[] words) {
        uint start = cast(uint) text.length;
        if (words.length > 0) {
            text.appendAll(words);
        }
        return start;
    }

    void keep(Claim stated, bool condition, const(Measure)[] given) {
        size_t index = tests.ptr[open.value].firstClaim;
        while (index < claims.length && !(claims.ptr[index].isSameLawAs(stated) && claims.ptr[index].file == stated.file && claims.ptr[index].line == stated.line)) {
            index += 1;
        }
        if (index == claims.length) {
            stated.test = open.value;
            claims.append(stated);
        }
        Claim* kept = &claims.ptr[index];
        kept.times += 1;
        kept.verdict = verdictOf(condition);
        kept.firstMeasure = cast(uint) measures.length;
        kept.measureCount = cast(uint) given.length;
        foreach (measure; given) {
            measures.append(Kept(measure.label, measure.number, keepText(measure.text), cast(uint) measure.text.length, measure.kind));
        }
    }

    const(char)[] wordsOf(ref const Kept kept) const {
        return text.ptr[kept.textStart .. kept.textStart + kept.textLength];
    }

    const(char)[] failureOf(ref const Tested test) const {
        return text.ptr[test.failureStart .. test.failureStart + test.failureLength];
    }

    const(Claim)[] claimsOf(uint test) const {
        return claims.ptr[tests.ptr[test].firstClaim .. tests.ptr[test].firstClaim + tests.ptr[test].claimCount];
    }

    void addMeasures(ref Line line, ref const Claim claim) const {
        foreach (index, ref kept; measures.ptr[claim.firstMeasure .. claim.firstMeasure + claim.measureCount]) {
            line.add("%s", separatorBefore(index));
            line.addMeasure(kept.label, kept.kind, kept.number, wordsOf(kept));
        }
    }

    bool isShown(ref const Claim claim, const(const(char)[])[] selectors) const {
        string name = tests.ptr[claim.test].name;
        size_t index = 0;
        while (index < selectors.length && !(isPrefixOf(selectors[index], name) || selectors[index] == ENUM_NAMES!Topic[claim.topic] || (claim.onto.exists && selectors[index] == ENUM_NAMES!Topic[claim.onto.value]))) {
            index += 1;
        }
        return selectors.length == 0 || index < selectors.length;
    }

    bool isFirstOfLaw(size_t at, Topic about, Part part, const(const(char)[])[] selectors) const {
        size_t index = 0;
        while (index < at && !(claims.ptr[index].isIn(about, part) && claims.ptr[index].isSameLawAs(claims.ptr[at]) && isShown(claims.ptr[index], selectors))) {
            index += 1;
        }
        return index == at;
    }

    uint lawCount(Topic about, Part part, const(const(char)[])[] selectors) const {
        uint count = 0;
        foreach (index, ref claim; claims.slice()) {
            if (claim.isIn(about, part) && isShown(claim, selectors) && isFirstOfLaw(index, about, part, selectors)) {
                count += 1;
            }
        }
        return count;
    }

    uint linkCount(Topic from, Topic onto, const(const(char)[])[] selectors) const {
        uint count = 0;
        foreach (index, ref claim; claims.slice()) {
            if (claim.isIn(from, Part.actsOn) && claim.onto.value == onto && isShown(claim, selectors) && isFirstOfLaw(index, from, Part.actsOn, selectors)) {
                count += 1;
            }
        }
        return count;
    }

    Tally tallyOf(const(const(char)[])[] selectors) const {
        Tally tally;
        foreach (ref claim; claims.slice()) {
            if (isShown(claim, selectors)) {
                final switch (claim.verdict) {
                    case Verdict.held:
                        tally.held += 1;
                        break;
                    case Verdict.failed:
                        tally.failed += 1;
                        break;
                }
            }
        }
        foreach (ref test; tests.slice()) {
            tally.tests += 1;
            if (test.outcome == Outcome.failed) {
                tally.failedTests += 1;
            }
        }
        return tally;
    }

    void release() {
        tests.release();
        claims.release();
        measures.release();
        text.release();
    }
}

__gshared Ledger ledger;

bool isPrefixOf(const(char)[] prefix, const(char)[] name) {
    return prefix.length <= name.length && name[0 .. prefix.length] == prefix;
}

bool isTopicName(const(char)[] name) {
    size_t index = 0;
    while (index < TOPIC_COUNT && ENUM_NAMES!Topic[index] != name) {
        index += 1;
    }
    return index < TOPIC_COUNT;
}

bool namesTopic(const(const(char)[])[] selectors) {
    size_t index = 0;
    while (index < selectors.length && !isTopicName(selectors[index])) {
        index += 1;
    }
    return index < selectors.length;
}

void record(ref Script world, Claim stated, bool condition, const(Measure)[] given) {
    if (!world.isFailed) {
        if (ledger.open.exists) {
            ledger.keep(stated, condition, given);
        }
        if (!condition) {
            Line line = failureLine(stated, given);
            world.fail("%s", line.text.ptr);
        }
    }
}

void claim(string file = __FILE__, uint line = __LINE__)(ref Script world, Topic topic, string law, bool condition, Measure[] measures...) {
    Claim stated;
    stated.law = law;
    stated.file = file;
    stated.line = line;
    stated.topic = topic;
    record(world, stated, condition, measures);
}

void link(string file = __FILE__, uint line = __LINE__)(ref Script world, Topic from, Topic onto, string law, bool condition, Measure[] measures...) {
    Claim stated;
    stated.law = law;
    stated.file = file;
    stated.line = line;
    stated.topic = from;
    stated.onto = Maybe!Topic.of(onto);
    record(world, stated, condition, measures);
}

immutable(char)* wordFor(Verdict verdict) {
    final switch (verdict) {
        case Verdict.held:
            return "held";
        case Verdict.failed:
            return "FAILED";
    }
}

void writeClaimLines(FILE* output, ref const Ledger ledger, uint test, const(const(char)[])[] selectors) {
    foreach (ref claim; ledger.claimsOf(test)) {
        if (ledger.isShown(claim, selectors)) {
            Line line;
            line.add("  %s", wordFor(claim.verdict));
            if (claim.times > 1) {
                line.add(" x%u", claim.times);
            }
            line.add(" [%s", ENUM_NAMES!Topic[claim.topic].ptr);
            if (claim.onto.exists) {
                line.add(" -> %s", ENUM_NAMES!Topic[claim.onto.value].ptr);
            }
            line.add("] %.*s", cast(int) claim.law.length, claim.law.ptr);
            if (claim.measureCount > 0) {
                line.add(" | ");
                ledger.addMeasures(line, claim);
            }
            line.add(" | %.*s:%u", cast(int) claim.file.length, claim.file.ptr, claim.line);
            fprintf(output, "%s\n", line.text.ptr);
        }
    }
}

void writeTally(FILE* output, ref const Ledger ledger, const(const(char)[])[] selectors) {
    Tally tally = ledger.tallyOf(selectors);
    fprintf(output, "%u claims held, %u failed, in %u tests of which %u failed\n", tally.held, tally.failed, tally.tests, tally.failedTests);
}

uint writeProblems(FILE* output, ref const Ledger ledger) {
    uint problems = 0;
    foreach (index, ref claim; ledger.claims.slice()) {
        if (claim.law.length == 0 || claim.law[$ - 1] != SENTENCE_END) {
            fprintf(output, "%.*s:%u: a law is a full sentence that ends with a full stop, and this one is '%.*s'\n", cast(int) claim.file.length, claim.file.ptr, claim.line, cast(int) claim.law.length, claim.law.ptr);
            problems += 1;
        }
        size_t earlier = 0;
        while (earlier < index && !(ledger.claims.ptr[earlier].law == claim.law && !ledger.claims.ptr[earlier].isSameLawAs(claim))) {
            earlier += 1;
        }
        if (earlier < index) {
            const(Claim)* other = &ledger.claims.ptr[earlier];
            fprintf(output, "%.*s:%u: this law is also stated at %.*s:%u about another topic: '%.*s'\n", cast(int) claim.file.length, claim.file.ptr, claim.line, cast(int) other.file.length, other.file.ptr, other.line, cast(int) claim.law.length, claim.law.ptr);
            problems += 1;
        }
    }
    return problems;
}

void writeEvidence(FILE* output, ref const Ledger ledger, size_t first, Topic about, Part part, const(const(char)[])[] selectors) {
    foreach (ref claim; ledger.claims.slice()[first .. $]) {
        if (claim.isIn(about, part) && claim.isSameLawAs(ledger.claims.ptr[first]) && ledger.isShown(claim, selectors)) {
            Line line;
            line.add("  - `%s`: %s", ledger.tests.ptr[claim.test].name.ptr, wordFor(claim.verdict));
            if (claim.measureCount > 0) {
                line.add(", ");
                ledger.addMeasures(line, claim);
            }
            if (claim.times > 1) {
                line.add(" (checked %u times, the last is shown)", claim.times);
            }
            fprintf(output, "%s\n", line.text.ptr);
        }
    }
}

void writePart(FILE* output, ref const Ledger ledger, Topic about, Part part, const(const(char)[])[] selectors) {
    if (ledger.lawCount(about, part, selectors) > 0) {
        final switch (part) {
            case Part.own:
                fprintf(output, "\n");
                break;
            case Part.actsOn:
                fprintf(output, "\nHow it acts on other things:\n\n");
                break;
            case Part.actedOnBy:
                fprintf(output, "\nWhat acts on it:\n\n");
                break;
        }
        foreach (index, ref claim; ledger.claims.slice()) {
            if (claim.isIn(about, part) && ledger.isShown(claim, selectors) && ledger.isFirstOfLaw(index, about, part, selectors)) {
                final switch (part) {
                    case Part.own:
                        fprintf(output, "- %.*s\n", cast(int) claim.law.length, claim.law.ptr);
                        writeEvidence(output, ledger, index, about, part, selectors);
                        break;
                    case Part.actsOn:
                        fprintf(output, "- On %s: %.*s\n", infoOf(claim.onto.value).title.ptr, cast(int) claim.law.length, claim.law.ptr);
                        writeEvidence(output, ledger, index, about, part, selectors);
                        break;
                    case Part.actedOnBy:
                        fprintf(output, "- %s: %.*s\n", infoOf(claim.topic).title.ptr, cast(int) claim.law.length, claim.law.ptr);
                        break;
                }
            }
        }
    }
}

uint lawsAbout(ref const Ledger ledger, Topic about, const(const(char)[])[] selectors) {
    return ledger.lawCount(about, Part.own, selectors) + ledger.lawCount(about, Part.actsOn, selectors) + ledger.lawCount(about, Part.actedOnBy, selectors);
}

void writeUnshown(FILE* output, ref const Ledger ledger) {
    fprintf(output, "\n## Not shown yet\n\nNo test states a claim about these:\n\n");
    foreach (index; 0 .. TOPIC_COUNT) {
        if (lawsAbout(ledger, cast(Topic) index, null) == 0) {
            fprintf(output, "- %s\n", infoOf(cast(Topic) index).title.ptr);
        }
    }
    fprintf(output, "\nThese tests state no claim:\n\n");
    foreach (ref test; ledger.tests.slice()) {
        if (test.claimCount == 0) {
            fprintf(output, "- `%s`\n", test.name.ptr);
        }
    }
}

void writeWiki(FILE* output, ref const Ledger ledger, const(const(char)[])[] selectors) {
    Tally tally = ledger.tallyOf(selectors);
    fprintf(output, "# What caapi does\n\n");
    fprintf(output, "This page was written by `caapi-headless wiki` (caapi %s) from a run of the behavior tests. Each statement is a claim that a test checked in that run. Under it are the test that checked it and what the run measured.\n\n", VERSION.ptr);
    if (tally.failed == 0 && tally.failedTests == 0) {
        fprintf(output, "All %u claims held, in %u tests.\n", tally.held, tally.tests);
    } else {
        fprintf(output, "NOT VERIFIED: in this run %u of %u claims failed and %u of %u tests failed.\n", tally.failed, tally.held + tally.failed, tally.failedTests, tally.tests);
        fprintf(output, "\n## Failed in this run\n\n");
        foreach (ref test; ledger.tests.slice()) {
            if (test.outcome == Outcome.failed) {
                const(char)[] failure = ledger.failureOf(test);
                fprintf(output, "- `%s`: %.*s\n", test.name.ptr, cast(int) failure.length, failure.ptr);
            }
        }
    }
    foreach (index; 0 .. TOPIC_COUNT) {
        Topic about = cast(Topic) index;
        if (lawsAbout(ledger, about, selectors) > 0) {
            TopicInfo info = infoOf(about);
            fprintf(output, "\n## %s\n\n%s\n", info.title.ptr, info.intro.ptr);
            writePart(output, ledger, about, Part.own, selectors);
            writePart(output, ledger, about, Part.actsOn, selectors);
            writePart(output, ledger, about, Part.actedOnBy, selectors);
        }
    }
    if (selectors.length == 0) {
        writeUnshown(output, ledger);
    }
}

void writeDot(FILE* output, ref const Ledger ledger, const(const(char)[])[] selectors) {
    fprintf(output, "digraph claims {\n");
    foreach (index; 0 .. TOPIC_COUNT) {
        Topic about = cast(Topic) index;
        uint laws = ledger.lawCount(about, Part.own, selectors);
        if (lawsAbout(ledger, about, selectors) > 0) {
            fprintf(output, "    %s [label=\"%s\\n%u claims\"];\n", ENUM_NAMES!Topic[index].ptr, infoOf(about).title.ptr, laws);
        } else if (selectors.length == 0) {
            fprintf(output, "    %s [label=\"%s\\nno claims\", style=dashed];\n", ENUM_NAMES!Topic[index].ptr, infoOf(about).title.ptr);
        }
    }
    foreach (from; 0 .. TOPIC_COUNT) {
        foreach (onto; 0 .. TOPIC_COUNT) {
            uint links = ledger.linkCount(cast(Topic) from, cast(Topic) onto, selectors);
            if (links > 0) {
                fprintf(output, "    %s -> %s [label=\"%u\"];\n", ENUM_NAMES!Topic[from].ptr, ENUM_NAMES!Topic[onto].ptr, links);
            }
        }
    }
    fprintf(output, "}\n");
}

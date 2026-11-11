module scripts.claims;

import core.stdc.math : fabs, floor;
import base.array : Array;
import base.maybe : Maybe;
import base.names : ENUM_NAMES;
import base.stdio : FILE, fprintf, printed;
import client.arguments : VERSION;
import client.script : Script;

enum size_t LINE_CAPACITY = 1024;
enum size_t NUMBER_CAPACITY = 32;
enum size_t ANCHOR_CAPACITY = 64;
enum char SENTENCE_END = '.';
enum char CELL_EDGE = '|';
enum uint MOST_ROWS_SHOWN = 12;
enum double MOST_WHOLE_NUMBER = 1e9;
enum int PAGE_DIGITS = 4;
enum int REPORT_DIGITS = 6;
enum string BREAKING_NODE = "end";

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
    falls,
}

enum uint TOPIC_COUNT = Topic.max + 1;

string titleOf(Topic topic) {
    final switch (topic) {
        case Topic.space:
            return "Space";
        case Topic.gravity:
            return "Ground and gravity";
        case Topic.movement:
            return "Movement";
        case Topic.world:
            return "The loaded world";
        case Topic.structures:
            return "Built worlds";
        case Topic.climate:
            return "Climate and terrain";
        case Topic.air:
            return "Air";
        case Topic.blocks:
            return "Mining and placing";
        case Topic.crafting:
            return "Crafting";
        case Topic.learning:
            return "Learning";
        case Topic.plants:
            return "Plants";
        case Topic.breeding:
            return "Breeding";
        case Topic.chemistry:
            return "Compounds";
        case Topic.body:
            return "The body";
        case Topic.perception:
            return "Perception";
        case Topic.navigation:
            return "Finding the way";
        case Topic.saves:
            return "Saves";
        case Topic.screens:
            return "Screens";
        case Topic.mods:
            return "Mods";
        case Topic.falls:
            return "Falling and waking";
    }
}

bool isTopicName(const(char)[] name) {
    size_t index = 0;
    while (index < TOPIC_COUNT && ENUM_NAMES!Topic[index] != name) {
        index += 1;
    }
    return index < TOPIC_COUNT;
}

bool isLetter(char letter) {
    return (letter >= 'a' && letter <= 'z') || (letter >= 'A' && letter <= 'Z');
}

bool isPlainTitle(string title) {
    size_t index = 0;
    while (index < title.length && (isLetter(title[index]) || title[index] == ' ')) {
        index += 1;
    }
    return title.length > 0 && title.length < ANCHOR_CAPACITY && index == title.length;
}

bool areTitlesPlain() {
    uint index = 0;
    while (index < TOPIC_COUNT && isPlainTitle(titleOf(cast(Topic) index))) {
        index += 1;
    }
    return index == TOPIC_COUNT;
}

static assert(areTitlesPlain(), "a topic title may hold only letters and spaces, because the page makes the link to its section from the title");
static assert(!isTopicName(BREAKING_NODE), "a topic named 'end' breaks the map, because that word ends a block in a Mermaid flowchart");

char anchorLetter(char letter) {
    if (letter == ' ') {
        return '-';
    } else if (letter >= 'A' && letter <= 'Z') {
        return cast(char)(letter - 'A' + 'a');
    } else {
        return letter;
    }
}

struct Anchor {
    char[ANCHOR_CAPACITY] text = 0;

    static Anchor of(string title) {
        Anchor made;
        foreach (index, letter; title) {
            made.text[index] = anchorLetter(letter);
        }
        return made;
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
    uint laws;
    uint held;
    uint failed;
    uint tests;
    uint failedTests;
}

const(char)[] numberText(char[] buffer, double number, int digits) {
    if (number == 0) {
        return printed(buffer, "0");
    } else if (number == floor(number) && fabs(number) < MOST_WHOLE_NUMBER) {
        return printed(buffer, "%.0f", number);
    } else {
        return printed(buffer, "%.*g", digits, number);
    }
}

struct Line {
    char[LINE_CAPACITY] text = 0;
    size_t length;

    void add(Args...)(const(char)* format, Args args) {
        length += printed(text[length .. $], format, args).length;
    }

    void addMeasure(string label, MeasureKind kind, double number, const(char)[] words) {
        char[NUMBER_CAPACITY] buffer;
        final switch (kind) {
            case MeasureKind.number:
                const(char)[] digits = numberText(buffer[], number, REPORT_DIGITS);
                add("%.*s %.*s", cast(int) label.length, label.ptr, cast(int) digits.length, digits.ptr);
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

immutable(char)* commaBefore(size_t index) {
    if (index == 0) {
        return "";
    } else {
        return ", ";
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
        stated.test = open.value;
        stated.verdict = verdictOf(condition);
        stated.firstMeasure = cast(uint) measures.length;
        stated.measureCount = cast(uint) given.length;
        foreach (measure; given) {
            measures.append(Kept(measure.label, measure.number, keepText(measure.text), cast(uint) measure.text.length, measure.kind));
        }
        claims.append(stated);
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

    const(Kept)[] measuresOf(ref const Claim claim) const {
        return measures.ptr[claim.firstMeasure .. claim.firstMeasure + claim.measureCount];
    }

    string testOf(ref const Claim claim) const {
        return tests.ptr[claim.test].name;
    }

    bool hasSameLabels(ref const Claim first, ref const Claim second) const {
        const(Kept)[] ours = measuresOf(first);
        const(Kept)[] theirs = measuresOf(second);
        size_t index = 0;
        while (index < ours.length && index < theirs.length && ours[index].label == theirs[index].label) {
            index += 1;
        }
        return ours.length == theirs.length && index == ours.length;
    }

    void addMeasures(ref Line line, ref const Claim claim) const {
        foreach (index, ref kept; measuresOf(claim)) {
            line.add("%s", separatorBefore(index));
            line.addMeasure(kept.label, kept.kind, kept.number, wordsOf(kept));
        }
    }

    bool isShown(ref const Claim claim, const(const(char)[])[] selectors) const {
        string name = testOf(claim);
        size_t index = 0;
        while (index < selectors.length && !(isPrefixOf(selectors[index], name) || selectors[index] == ENUM_NAMES!Topic[claim.topic] || (claim.onto.exists && selectors[index] == ENUM_NAMES!Topic[claim.onto.value]))) {
            index += 1;
        }
        return selectors.length == 0 || index < selectors.length;
    }

    bool isEvidenceOf(ref const Claim claim, size_t law, const(const(char)[])[] selectors) const {
        return claim.isSameLawAs(claims.ptr[law]) && isShown(claim, selectors);
    }

    bool isLawHead(size_t at, const(const(char)[])[] selectors) const {
        size_t index = 0;
        while (index < at && !isEvidenceOf(claims.ptr[index], at, selectors)) {
            index += 1;
        }
        return index == at && isShown(claims.ptr[at], selectors);
    }

    bool isLawFailed(size_t law, const(const(char)[])[] selectors) const {
        size_t index = law;
        while (index < claims.length && !(isEvidenceOf(claims.ptr[index], law, selectors) && claims.ptr[index].verdict == Verdict.failed)) {
            index += 1;
        }
        return index < claims.length;
    }

    uint lawCount(Topic about, Part part, const(const(char)[])[] selectors) const {
        uint count = 0;
        foreach (index, ref claim; claims.slice()) {
            if (claim.isIn(about, part) && isLawHead(index, selectors)) {
                count += 1;
            }
        }
        return count;
    }

    uint linkCount(Topic from, Topic onto, const(const(char)[])[] selectors) const {
        uint count = 0;
        foreach (index, ref claim; claims.slice()) {
            if (claim.isIn(from, Part.actsOn) && claim.onto.value == onto && isLawHead(index, selectors)) {
                count += 1;
            }
        }
        return count;
    }

    bool hasSection(Topic about, const(const(char)[])[] selectors) const {
        return lawCount(about, Part.own, selectors) + lawCount(about, Part.actsOn, selectors) + lawCount(about, Part.actedOnBy, selectors) > 0;
    }

    Tally tallyOf(const(const(char)[])[] selectors) const {
        Tally tally;
        foreach (index, ref claim; claims.slice()) {
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
            if (isLawHead(index, selectors)) {
                tally.laws += 1;
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

immutable(char)* markFor(Verdict verdict) {
    final switch (verdict) {
        case Verdict.held:
            return "";
        case Verdict.failed:
            return " **FAILED**";
    }
}

void writeClaimLines(FILE* output, ref const Ledger ledger, uint test, const(const(char)[])[] selectors) {
    foreach (ref claim; ledger.claimsOf(test)) {
        if (ledger.isShown(claim, selectors)) {
            Line line;
            line.add("  %s [%s", wordFor(claim.verdict), ENUM_NAMES!Topic[claim.topic].ptr);
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
    fprintf(output, "%u laws in %u checks: %u held, %u failed. %u tests ran, %u failed.\n", tally.laws, tally.held + tally.failed, tally.held, tally.failed, tally.tests, tally.failedTests);
}

uint writeProblems(FILE* output, ref const Ledger ledger) {
    uint problems = 0;
    foreach (index, ref claim; ledger.claims.slice()) {
        if (ledger.isLawHead(index, null) && (claim.law.length == 0 || claim.law[$ - 1] != SENTENCE_END)) {
            fprintf(output, "%.*s:%u: a law is a full sentence that ends with a full stop, and this one is '%.*s'\n", cast(int) claim.file.length, claim.file.ptr, claim.line, cast(int) claim.law.length, claim.law.ptr);
            problems += 1;
        }
        size_t earlier = 0;
        while (earlier < index && !(ledger.claims.ptr[earlier].law == claim.law && !ledger.claims.ptr[earlier].isSameLawAs(claim))) {
            earlier += 1;
        }
        if (earlier < index && ledger.isLawHead(index, null)) {
            const(Claim)* other = &ledger.claims.ptr[earlier];
            fprintf(output, "%.*s:%u: this law is also stated at %.*s:%u about another topic: '%.*s'\n", cast(int) claim.file.length, claim.file.ptr, claim.line, cast(int) other.file.length, other.file.ptr, other.line, cast(int) claim.law.length, claim.law.ptr);
            problems += 1;
        }
    }
    return problems;
}

void writeText(FILE* output, const(char)[] text) {
    size_t start = 0;
    foreach (index, letter; text) {
        if (letter == CELL_EDGE) {
            fprintf(output, "%.*s\\%c", cast(int)(index - start), text.ptr + start, CELL_EDGE);
            start = index + 1;
        }
    }
    fprintf(output, "%.*s", cast(int)(text.length - start), text.ptr + start);
}

void writeLink(FILE* output, Topic topic) {
    string title = titleOf(topic);
    Anchor anchor = Anchor.of(title);
    fprintf(output, "[%.*s](#%s)", cast(int) title.length, title.ptr, anchor.text.ptr);
}

void writeTableHead(FILE* output, ref const Ledger ledger, ref const Claim claim) {
    fprintf(output, "| Test |");
    foreach (ref kept; ledger.measuresOf(claim)) {
        fprintf(output, " ");
        writeText(output, kept.label);
        fprintf(output, " |");
    }
    fprintf(output, "\n| --- |");
    foreach (_; ledger.measuresOf(claim)) {
        fprintf(output, " --- |");
    }
    fprintf(output, "\n");
}

void writeTableRow(FILE* output, ref const Ledger ledger, ref const Claim claim) {
    char[NUMBER_CAPACITY] buffer;
    string name = ledger.testOf(claim);
    fprintf(output, "| `%.*s`%s |", cast(int) name.length, name.ptr, markFor(claim.verdict));
    foreach (ref kept; ledger.measuresOf(claim)) {
        final switch (kept.kind) {
            case MeasureKind.number:
                const(char)[] digits = numberText(buffer[], kept.number, PAGE_DIGITS);
                fprintf(output, " %.*s |", cast(int) digits.length, digits.ptr);
                break;
            case MeasureKind.text:
                fprintf(output, " `");
                writeText(output, ledger.wordsOf(kept));
                fprintf(output, "` |");
                break;
        }
    }
    fprintf(output, "\n");
}

void writeCheckers(FILE* output, ref const Ledger ledger, size_t law, const(const(char)[])[] selectors) {
    Maybe!uint last;
    uint listed = 0;
    foreach (ref claim; ledger.claims.slice()[law .. $]) {
        if (ledger.isEvidenceOf(claim, law, selectors) && claim.measureCount == 0 && !(last.exists && last.value == claim.test && claim.verdict == Verdict.held)) {
            string name = ledger.testOf(claim);
            if (listed == 0) {
                fprintf(output, " Checked by ");
            }
            fprintf(output, "%s`%.*s`%s", commaBefore(listed), cast(int) name.length, name.ptr, markFor(claim.verdict));
            last = Maybe!uint.of(claim.test);
            listed += 1;
        }
    }
    if (listed > 0) {
        fprintf(output, ".");
    }
    fprintf(output, "\n\n");
}

void writeTables(FILE* output, ref const Ledger ledger, size_t law, const(const(char)[])[] selectors) {
    Maybe!size_t head;
    uint rows = 0;
    uint hidden = 0;
    foreach (offset, ref claim; ledger.claims.slice()[law .. $]) {
        if (ledger.isEvidenceOf(claim, law, selectors) && claim.measureCount > 0) {
            if (rows < MOST_ROWS_SHOWN || claim.verdict == Verdict.failed) {
                if (!head.exists || !ledger.hasSameLabels(ledger.claims.ptr[head.value], claim)) {
                    if (head.exists) {
                        fprintf(output, "\n");
                    }
                    writeTableHead(output, ledger, claim);
                    head = Maybe!size_t.of(law + offset);
                }
                writeTableRow(output, ledger, claim);
                rows += 1;
            } else {
                hidden += 1;
            }
        }
    }
    if (rows > 0) {
        fprintf(output, "\n");
    }
    if (hidden > 0) {
        fprintf(output, "%u more checks of this law held. `caapi-headless claims` lists every check.\n\n", hidden);
    }
}

void writeLaws(FILE* output, ref const Ledger ledger, Topic about, Part part, const(const(char)[])[] selectors) {
    foreach (index, ref claim; ledger.claims.slice()) {
        if (claim.isIn(about, part) && ledger.isLawHead(index, selectors)) {
            if (claim.onto.exists) {
                writeLink(output, claim.onto.value);
                fprintf(output, ": ");
            }
            fprintf(output, "**%.*s**", cast(int) claim.law.length, claim.law.ptr);
            writeCheckers(output, ledger, index, selectors);
            writeTables(output, ledger, index, selectors);
        }
    }
}

void writeActors(FILE* output, ref const Ledger ledger, Topic about, const(const(char)[])[] selectors) {
    foreach (index, ref claim; ledger.claims.slice()) {
        if (claim.isIn(about, Part.actedOnBy) && ledger.isLawHead(index, selectors)) {
            fprintf(output, "- ");
            writeLink(output, claim.topic);
            fprintf(output, ": %.*s%s\n", cast(int) claim.law.length, claim.law.ptr, markFor(verdictOf(!ledger.isLawFailed(index, selectors))));
        }
    }
    fprintf(output, "\n");
}

void writeSection(FILE* output, ref const Ledger ledger, Topic about, const(const(char)[])[] selectors) {
    string title = titleOf(about);
    fprintf(output, "## %.*s\n\n", cast(int) title.length, title.ptr);
    writeLaws(output, ledger, about, Part.own, selectors);
    if (ledger.lawCount(about, Part.actsOn, selectors) > 0) {
        fprintf(output, "### %.*s: acts on\n\n", cast(int) title.length, title.ptr);
        writeLaws(output, ledger, about, Part.actsOn, selectors);
    }
    if (ledger.lawCount(about, Part.actedOnBy, selectors) > 0) {
        fprintf(output, "### %.*s: acted on by\n\n", cast(int) title.length, title.ptr);
        writeActors(output, ledger, about, selectors);
    }
}

uint linksBetween(ref const Ledger ledger, Topic about, Topic other, Part part, const(const(char)[])[] selectors) {
    final switch (part) {
        case Part.own:
            return 0;
        case Part.actsOn:
            return ledger.linkCount(about, other, selectors);
        case Part.actedOnBy:
            return ledger.linkCount(other, about, selectors);
    }
}

void writeNeighbors(FILE* output, ref const Ledger ledger, Topic about, Part part, const(const(char)[])[] selectors) {
    uint listed = 0;
    fprintf(output, " ");
    foreach (index; 0 .. TOPIC_COUNT) {
        if (linksBetween(ledger, about, cast(Topic) index, part, selectors) > 0) {
            fprintf(output, "%s", commaBefore(listed));
            writeLink(output, cast(Topic) index);
            listed += 1;
        }
    }
    fprintf(output, " |");
}

void writeMap(FILE* output, ref const Ledger ledger, const(const(char)[])[] selectors) {
    fprintf(output, "## Map\n\n```mermaid\nflowchart LR\n");
    foreach (index; 0 .. TOPIC_COUNT) {
        if (ledger.hasSection(cast(Topic) index, selectors)) {
            string title = titleOf(cast(Topic) index);
            fprintf(output, "    %s[%.*s]\n", ENUM_NAMES!Topic[index].ptr, cast(int) title.length, title.ptr);
        }
    }
    foreach (from; 0 .. TOPIC_COUNT) {
        foreach (onto; 0 .. TOPIC_COUNT) {
            if (ledger.linkCount(cast(Topic) from, cast(Topic) onto, selectors) > 0) {
                fprintf(output, "    %s --> %s\n", ENUM_NAMES!Topic[from].ptr, ENUM_NAMES!Topic[onto].ptr);
            }
        }
    }
    fprintf(output, "```\n\n| System | Laws | Acts on | Acted on by |\n| --- | --- | --- | --- |\n");
    foreach (index; 0 .. TOPIC_COUNT) {
        Topic about = cast(Topic) index;
        if (ledger.hasSection(about, selectors)) {
            fprintf(output, "| ");
            writeLink(output, about);
            fprintf(output, " | %u |", ledger.lawCount(about, Part.own, selectors) + ledger.lawCount(about, Part.actsOn, selectors));
            writeNeighbors(output, ledger, about, Part.actsOn, selectors);
            writeNeighbors(output, ledger, about, Part.actedOnBy, selectors);
            fprintf(output, "\n");
        }
    }
    fprintf(output, "\n");
}

void writeHeader(FILE* output, ref const Ledger ledger, const(const(char)[])[] selectors) {
    Tally tally = ledger.tallyOf(selectors);
    fprintf(output, "# What caapi does\n\n");
    fprintf(output, "Written by `caapi-headless wiki` (caapi %s) from a run of the behavior tests. Each statement in bold is a law that a test checked in that run, and the table under it holds what the run measured. Lengths are in units of the curvature radius of the space, and times are in seconds.\n\n", VERSION.ptr);
    if (selectors.length > 0) {
        fprintf(output, "This page holds only what was asked for: ");
        foreach (index, selector; selectors) {
            fprintf(output, "%s`%.*s`", commaBefore(index), cast(int) selector.length, selector.ptr);
        }
        fprintf(output, ".\n\n");
    }
    if (tally.failed == 0 && tally.failedTests == 0) {
        fprintf(output, "All %u laws held, in %u checks.\n\n", tally.laws, tally.held);
    } else {
        fprintf(output, "**NOT VERIFIED.** %u of %u checks failed, and %u of %u tests failed. A test stops at its first failure, so the laws it would have checked after that are missing from this page.\n\n", tally.failed, tally.held + tally.failed, tally.failedTests, tally.tests);
        fprintf(output, "## Failed in this run\n\n| Test | What failed |\n| --- | --- |\n");
        foreach (ref test; ledger.tests.slice()) {
            if (test.outcome == Outcome.failed) {
                fprintf(output, "| `%.*s` | ", cast(int) test.name.length, test.name.ptr);
                writeText(output, ledger.failureOf(test));
                fprintf(output, " |\n");
            }
        }
        fprintf(output, "\n");
    }
}

void writeGaps(FILE* output, ref const Ledger ledger) {
    uint topics = 0;
    uint tests = 0;
    foreach (index; 0 .. TOPIC_COUNT) {
        if (!ledger.hasSection(cast(Topic) index, null)) {
            topics += 1;
        }
    }
    foreach (ref test; ledger.tests.slice()) {
        if (test.claimCount == 0) {
            tests += 1;
        }
    }
    if (topics + tests > 0) {
        fprintf(output, "## Gaps\n\n");
    }
    if (topics > 0) {
        uint listed = 0;
        fprintf(output, "No test states a law about: ");
        foreach (index; 0 .. TOPIC_COUNT) {
            if (!ledger.hasSection(cast(Topic) index, null)) {
                string title = titleOf(cast(Topic) index);
                fprintf(output, "%s%.*s", commaBefore(listed), cast(int) title.length, title.ptr);
                listed += 1;
            }
        }
        fprintf(output, ".\n\n");
    }
    if (tests > 0) {
        uint listed = 0;
        fprintf(output, "These tests state no law: ");
        foreach (ref test; ledger.tests.slice()) {
            if (test.claimCount == 0) {
                fprintf(output, "%s`%.*s`", commaBefore(listed), cast(int) test.name.length, test.name.ptr);
                listed += 1;
            }
        }
        fprintf(output, ".\n");
    }
}

void writeWiki(FILE* output, ref const Ledger ledger, const(const(char)[])[] selectors) {
    writeHeader(output, ledger, selectors);
    writeMap(output, ledger, selectors);
    foreach (index; 0 .. TOPIC_COUNT) {
        if (ledger.hasSection(cast(Topic) index, selectors)) {
            writeSection(output, ledger, cast(Topic) index, selectors);
        }
    }
    if (selectors.length == 0) {
        writeGaps(output, ledger);
    }
}

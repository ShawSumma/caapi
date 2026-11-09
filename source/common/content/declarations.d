module common.content.declarations;

import core.stdc.math : floor;
import base.array : Array;
import base.maybe : Maybe, MaybeIndex;
import base.stdio : printed;
import common.content.graph : Attribute, ContentEdge, ContentGraph, ContentNode, PROBLEM_CAPACITY, Standing, ValueKind;
import common.content.lexer : Lexing, Token;
import plugins.api.content : ContentRef, Holder, Need;

enum uint UNBOUNDED = uint.max;
enum uint MOST_ALIAS_DEPTH = 8;

enum ValueType : ubyte {
    number,
    integer,
    text,
    choice,
}

enum Presence : ubyte {
    required,
    optional,
    defaulted,
}

enum Openness : ubyte {
    closed,
    open,
}

struct KindDecl {
    uint name;
    uint owner;
    Openness openness;
}

struct FieldDecl {
    double low = -double.infinity;
    double high = double.infinity;
    double fallbackNumber = 0;
    uint holder;
    uint key;
    uint firstChoice;
    uint choiceCount;
    uint fallbackText;
    uint owner;
    Holder holding;
    ValueType type;
    Presence presence;
}

struct EdgeDecl {
    uint kind;
    uint edge;
    uint firstTarget;
    uint targetCount;
    uint least;
    uint most;
    uint owner;
}

struct Alias {
    uint name;
    uint firstTarget;
    uint targetCount;
}

struct Declarations {
    Array!KindDecl kinds;
    Array!FieldDecl fields;
    Array!EdgeDecl edges;
    Array!Alias aliases;
    Array!uint pool;

    MaybeIndex!uint kindOf(uint name) const {
        uint index = 0;
        while (index < kinds.length && kinds.ptr[index].name != name) {
            index += 1;
        }
        if (index < kinds.length) {
            return MaybeIndex!uint.of(index);
        } else {
            return MaybeIndex!uint.init;
        }
    }

    MaybeIndex!uint fieldOf(Holder holding, uint holder, uint key) const {
        uint index = 0;
        while (index < fields.length && !(fields.ptr[index].holding == holding && fields.ptr[index].holder == holder && fields.ptr[index].key == key)) {
            index += 1;
        }
        if (index < fields.length) {
            return MaybeIndex!uint.of(index);
        } else {
            return MaybeIndex!uint.init;
        }
    }

    MaybeIndex!uint edgeOf(uint kind, uint edge) const {
        uint index = 0;
        while (index < edges.length && !(edges.ptr[index].kind == kind && edges.ptr[index].edge == edge)) {
            index += 1;
        }
        if (index < edges.length) {
            return MaybeIndex!uint.of(index);
        } else {
            return MaybeIndex!uint.init;
        }
    }

    bool admits(uint firstTarget, uint targetCount, uint kind, uint depth) const {
        foreach (target; pool.slice()[firstTarget .. firstTarget + targetCount]) {
            if (target == kind) {
                return true;
            }
            uint index = 0;
            while (index < aliases.length && aliases.ptr[index].name != target) {
                index += 1;
            }
            if (index < aliases.length && depth < MOST_ALIAS_DEPTH && admits(aliases.ptr[index].firstTarget, aliases.ptr[index].targetCount, kind, depth + 1)) {
                return true;
            }
        }
        return false;
    }

    void release() {
        kinds.release();
        fields.release();
        edges.release();
        aliases.release();
        pool.release();
    }
}

immutable string[4] CARDINALITIES = ["one", "optional", "many", "some"];

struct DeclarationParser {
    mixin Lexing;
    ContentGraph* graph;

    uint name() {
        if (token != Token.word) {
            fail("a name is expected here");
            return 0;
        } else {
            uint made = graph.intern(current());
            advance();
            return made;
        }
    }

    void file() {
        advance();
        while (isGoing() && token != Token.end) {
            if (isWord("kind")) {
                advance();
                uint kind = name();
                Openness openness = Openness.closed;
                if (isWord("open")) {
                    openness = Openness.open;
                    advance();
                }
                if (graph.declarations.kindOf(kind).exists) {
                    reportTwice(kind);
                }
                graph.declarations.kinds.append(KindDecl(kind, graph.owner, openness));
                fields(Holder.node, kind);
            } else if (isWord("extend")) {
                advance();
                fields(Holder.node, name());
            } else if (isWord("type")) {
                advance();
                uint named = name();
                expect("=");
                uint first = cast(uint) graph.declarations.pool.length;
                targets();
                graph.declarations.aliases.append(Alias(named, first, cast(uint) graph.declarations.pool.length - first));
            } else {
                fail("a declaration starts with kind, extend or type");
            }
        }
    }

    void reportTwice(uint kind) {
        char[PROBLEM_CAPACITY] buffer;
        const(char)[] spelled = graph.textOf(kind);
        graph.report(graph.owner, printed(buffer[], "declares the kind '%.*s', which is already declared", cast(int) spelled.length, spelled.ptr));
    }

    void fields(Holder holding, uint holder) {
        expect("{");
        while (isGoing() && token != Token.end && !isSymbol("}")) {
            uint key = name();
            expect(":");
            if (isGoing() && holding == Holder.node && (token == Token.number || isCardinality())) {
                edge(holder, key);
            } else if (isGoing()) {
                field(holding, holder, key);
            }
        }
        expect("}");
    }

    bool isCardinality() const {
        uint index = 0;
        while (index < CARDINALITIES.length && !isWord(CARDINALITIES[index])) {
            index += 1;
        }
        return index < CARDINALITIES.length;
    }

    void edge(uint kind, uint key) {
        uint least = 0;
        uint most = UNBOUNDED;
        if (token == Token.number) {
            least = cast(uint) number();
            expect("..");
            if (token == Token.number) {
                most = cast(uint) number();
            }
        } else if (isWord("one")) {
            least = 1;
            most = 1;
            advance();
        } else if (isWord("optional")) {
            most = 1;
            advance();
        } else if (isWord("some")) {
            least = 1;
            advance();
        } else {
            advance();
        }
        expect("->");
        uint first = cast(uint) graph.declarations.pool.length;
        targets();
        uint index = cast(uint) graph.declarations.edges.length;
        graph.declarations.edges.append(EdgeDecl(kind, key, first, cast(uint) graph.declarations.pool.length - first, least, most, graph.owner));
        if (isSymbol("{")) {
            fields(Holder.edge, index);
        }
    }

    void targets() {
        graph.declarations.pool.append(name());
        while (isGoing() && isSymbol("|")) {
            advance();
            graph.declarations.pool.append(name());
        }
    }

    void field(Holder holding, uint holder, uint key) {
        FieldDecl made;
        made.holding = holding;
        made.holder = holder;
        made.key = key;
        made.owner = graph.owner;
        if (isWord("number") || isWord("integer")) {
            made.type = ValueType.number;
            if (isWord("integer")) {
                made.type = ValueType.integer;
            }
            advance();
            range(made);
        } else if (isWord("text")) {
            made.type = ValueType.text;
            advance();
        } else if (token == Token.text) {
            made.type = ValueType.choice;
            made.firstChoice = cast(uint) graph.declarations.pool.length;
            graph.declarations.pool.append(graph.intern(current()));
            advance();
            while (isGoing() && isSymbol("|")) {
                advance();
                if (token != Token.text) {
                    fail("a choice is a quoted string");
                } else {
                    graph.declarations.pool.append(graph.intern(current()));
                    advance();
                }
            }
            made.choiceCount = cast(uint) graph.declarations.pool.length - made.firstChoice;
        } else {
            fail("a field is number, integer, text, quoted choices, or an edge");
        }
        if (isSymbol("?")) {
            made.presence = Presence.optional;
            advance();
        } else if (isSymbol("=")) {
            made.presence = Presence.defaulted;
            advance();
            if (token == Token.number) {
                made.fallbackNumber = number();
            } else if (token == Token.text) {
                made.fallbackText = graph.intern(current());
                advance();
            } else {
                fail("a default is a number or a quoted string");
            }
        }
        graph.declarations.fields.append(made);
    }

    void range(ref FieldDecl made) {
        if (token == Token.number) {
            made.low = number();
            expect("..");
            if (token == Token.number) {
                made.high = number();
            }
        } else if (isSymbol("..")) {
            advance();
            made.high = number();
        }
    }
}

void declare(ref ContentGraph graph, const(char)[] text, const(char)[] source) {
    DeclarationParser parser;
    parser.text = text;
    parser.graph = &graph;
    parser.file();
    if (!parser.isGoing()) {
        char[PROBLEM_CAPACITY] buffer;
        graph.report(graph.owner, printed(buffer[], "%.*s, line %u: %.*s", cast(int) source.length, source.ptr, parser.failedLine, cast(int) parser.failure.length, parser.failure.ptr));
    }
}

struct Checking {
    ContentGraph* graph;
    uint dropped;

    ref Declarations declarations() return {
        return graph.declarations;
    }

    const(char)[] spelled(uint name) const {
        return graph.textOf(name);
    }

    void report(uint owner, const(char)[] message) {
        graph.report(owner, message);
    }

    void drop(uint node) {
        graph.nodes.ptr[node].standing = Standing.removed;
        dropped += 1;
    }

    bool isValueOf(ref const FieldDecl field, ref const Attribute attribute) const {
        final switch (field.type) {
            case ValueType.number:
                return attribute.value == ValueKind.number && attribute.number >= field.low && attribute.number <= field.high;
            case ValueType.integer:
                return attribute.value == ValueKind.number && attribute.number >= field.low && attribute.number <= field.high && floor(attribute.number) == attribute.number;
            case ValueType.text:
                return attribute.value == ValueKind.text;
            case ValueType.choice:
                uint index = 0;
                while (index < field.choiceCount && !(attribute.value == ValueKind.text && graph.declarations.pool.ptr[field.firstChoice + index] == attribute.text)) {
                    index += 1;
                }
                return index < field.choiceCount;
        }
    }

    bool checkAttributes(Holder holding, uint holder, uint declHolder, Openness openness, const(char)[] subject, uint owner) {
        bool fits = true;
        char[PROBLEM_CAPACITY] buffer;
        foreach (ref attribute; graph.attributesOf(ContentRef(holder, holding))) {
            MaybeIndex!uint field = declarations.fieldOf(holding, declHolder, attribute.key);
            const(char)[] key = spelled(attribute.key);
            if (!field.exists && openness == Openness.closed) {
                report(owner, printed(buffer[], "'%.*s' has '%.*s', which its declaration does not have", cast(int) subject.length, subject.ptr, cast(int) key.length, key.ptr));
            } else if (field.exists && !isValueOf(declarations.fields.ptr[field.value], attribute)) {
                report(owner, printed(buffer[], "'%.*s' has a '%.*s' its declaration does not allow", cast(int) subject.length, subject.ptr, cast(int) key.length, key.ptr));
                fits = false;
            }
        }
        foreach (ref field; declarations.fields.slice()) {
            if (field.holding == holding && field.holder == declHolder && field.presence == Presence.required && graph.attributeIn(ContentRef(holder, holding), field.key) is null) {
                const(char)[] key = spelled(field.key);
                report(owner, printed(buffer[], "'%.*s' has no '%.*s', which its declaration requires", cast(int) subject.length, subject.ptr, cast(int) key.length, key.ptr));
                fits = false;
            }
        }
        return fits;
    }

    void checkNode(uint node) {
        char[PROBLEM_CAPACITY] buffer;
        ContentNode* record = &graph.nodes.ptr[node];
        const(char)[] name = spelled(record.name);
        MaybeIndex!uint kind = declarations.kindOf(record.kind);
        if (!kind.exists) {
            const(char)[] kindName = spelled(record.kind);
            report(record.owner, printed(buffer[], "'%.*s' is a %.*s, which no mod declares", cast(int) name.length, name.ptr, cast(int) kindName.length, kindName.ptr));
            drop(node);
            return;
        }
        bool fits = checkAttributes(Holder.node, node, record.kind, declarations.kinds.ptr[kind.value].openness, name, record.owner);
        foreach (edge; graph.outgoing(node)) {
            fits = checkEdge(edge) && fits;
        }
        Fit counted = checkCounts(node, record.kind, name);
        if (!fits || counted != Fit.whole) {
            drop(node);
        }
    }

    bool checkEdge(uint edge) {
        char[PROBLEM_CAPACITY] buffer;
        ContentEdge* record = &graph.edges.ptr[edge];
        uint fromKind = graph.nodes.ptr[record.from].kind;
        uint toKind = graph.nodes.ptr[record.to].kind;
        const(char)[] kind = spelled(record.kind);
        const(char)[] from = spelled(record.fromName);
        const(char)[] to = spelled(record.toName);
        MaybeIndex!uint decl = declarations.edgeOf(fromKind, record.kind);
        if (!decl.exists) {
            const(char)[] fromKindName = spelled(fromKind);
            report(record.owner, printed(buffer[], "'%.*s' has a %.*s edge, which a %.*s does not declare", cast(int) from.length, from.ptr, cast(int) kind.length, kind.ptr, cast(int) fromKindName.length, fromKindName.ptr));
            record.standing = Standing.removed;
            return true;
        } else if (!declarations.admits(declarations.edges.ptr[decl.value].firstTarget, declarations.edges.ptr[decl.value].targetCount, toKind, 0)) {
            const(char)[] toKindName = spelled(toKind);
            report(record.owner, printed(buffer[], "a %.*s edge runs from '%.*s' to '%.*s', a %.*s, which it does not allow", cast(int) kind.length, kind.ptr, cast(int) from.length, from.ptr, cast(int) to.length, to.ptr, cast(int) toKindName.length, toKindName.ptr));
            record.standing = Standing.removed;
            return true;
        } else {
            return checkAttributes(Holder.edge, edge, decl.value, Openness.closed, kind, record.owner);
        }
    }

    Fit checkCounts(uint node, uint kind, const(char)[] name) {
        Fit fit = Fit.whole;
        foreach (index, ref decl; declarations.edges.slice()) {
            if (decl.kind == kind) {
                uint kept = 0;
                uint lapsed = 0;
                foreach (ref edge; graph.edges.slice()) {
                    if (edge.standing == Standing.kept && edge.from == node && edge.kind == decl.edge) {
                        kept += 1;
                    } else if (edge.standing == Standing.lapsed && edge.from == node && edge.kind == decl.edge) {
                        lapsed += 1;
                    }
                }
                if (kept < decl.least || kept > decl.most) {
                    if (lapsed > 0) {
                        if (fit == Fit.whole) {
                            fit = Fit.lapsed;
                        }
                    } else if (decl.most == UNBOUNDED) {
                        char[PROBLEM_CAPACITY] buffer;
                        const(char)[] edge = spelled(decl.edge);
                        report(graph.nodes.ptr[node].owner, printed(buffer[], "'%.*s' has %u %.*s edges, and its declaration needs at least %u", cast(int) name.length, name.ptr, kept, cast(int) edge.length, edge.ptr, decl.least));
                        fit = Fit.broken;
                    } else {
                        char[PROBLEM_CAPACITY] buffer;
                        const(char)[] edge = spelled(decl.edge);
                        report(graph.nodes.ptr[node].owner, printed(buffer[], "'%.*s' has %u %.*s edges, and its declaration allows %u to %u", cast(int) name.length, name.ptr, kept, cast(int) edge.length, edge.ptr, decl.least, decl.most));
                        fit = Fit.broken;
                    }
                }
            }
        }
        return fit;
    }

    void settleEdges() {
        char[PROBLEM_CAPACITY] buffer;
        foreach (ref edge; graph.edges.slice()) {
            if (edge.standing == Standing.kept && (graph.nodes.ptr[edge.from].standing != Standing.kept || graph.nodes.ptr[edge.to].standing != Standing.kept)) {
                if (graph.nodes.ptr[edge.from].standing != Standing.kept) {
                    edge.standing = Standing.removed;
                } else if (edge.need == Need.optional) {
                    edge.standing = Standing.lapsed;
                } else {
                    const(char)[] kind = spelled(edge.kind);
                    const(char)[] to = spelled(edge.toName);
                    report(edge.owner, printed(buffer[], "a %.*s edge names '%.*s', which was dropped", cast(int) kind.length, kind.ptr, cast(int) to.length, to.ptr));
                    edge.standing = Standing.removed;
                }
            }
        }
    }
}

enum Fit : ubyte {
    whole,
    lapsed,
    broken,
}

void checkDeclarations(ref ContentGraph graph) {
    char[PROBLEM_CAPACITY] buffer;
    foreach (ref field; graph.declarations.fields.slice()) {
        if (field.holding == Holder.node && !graph.declarations.kindOf(field.holder).exists) {
            const(char)[] kind = graph.textOf(field.holder);
            graph.report(field.owner, printed(buffer[], "extends the kind '%.*s', which no mod declares", cast(int) kind.length, kind.ptr));
        }
    }
    foreach (ref edge; graph.declarations.edges.slice()) {
        foreach (target; graph.declarations.pool.slice()[edge.firstTarget .. edge.firstTarget + edge.targetCount]) {
            uint named = 0;
            while (named < graph.declarations.aliases.length && graph.declarations.aliases.ptr[named].name != target) {
                named += 1;
            }
            if (!graph.declarations.kindOf(target).exists && named == graph.declarations.aliases.length) {
                const(char)[] spelled = graph.textOf(target);
                graph.report(edge.owner, printed(buffer[], "an edge declaration names the kind '%.*s', which no mod declares", cast(int) spelled.length, spelled.ptr));
            }
        }
    }
}

void checkContent(ref ContentGraph graph) {
    checkDeclarations(graph);
    Checking checking = Checking(&graph);
    checking.settleEdges();
    uint before = 1;
    while (before > 0) {
        checking.dropped = 0;
        graph.index();
        foreach (node; 0 .. cast(uint) graph.nodes.length) {
            if (graph.nodes.ptr[node].standing == Standing.kept) {
                checking.checkNode(node);
            }
        }
        checking.settleEdges();
        before = checking.dropped;
    }
}

void fillDefaults(ref ContentGraph graph) {
    graph.index();
    foreach (ref field; graph.declarations.fields.slice()) {
        if (field.presence == Presence.defaulted) {
            if (field.holding == Holder.node) {
                foreach (node; 0 .. cast(uint) graph.nodes.length) {
                    if (graph.nodes.ptr[node].standing == Standing.kept && graph.nodes.ptr[node].kind == field.holder && graph.attributeIn(ContentRef(node, Holder.node), field.key) is null) {
                        graph.fillDefault(ContentRef(node, Holder.node), field);
                    }
                }
            } else {
                EdgeDecl decl = graph.declarations.edges.ptr[field.holder];
                foreach (edge; 0 .. cast(uint) graph.edges.length) {
                    ContentEdge* record = &graph.edges.ptr[edge];
                    if (record.standing == Standing.kept && record.kind == decl.edge && graph.nodes.ptr[record.from].kind == decl.kind && graph.attributeIn(ContentRef(edge, Holder.edge), field.key) is null) {
                        graph.fillDefault(ContentRef(edge, Holder.edge), field);
                    }
                }
            }
        }
    }
}

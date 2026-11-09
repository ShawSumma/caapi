module common.content.graph;

import core.stdc.stdlib : free, malloc;
import core.stdc.string : memcpy;
import base.array : Array;
import base.hashmap : HashMap;
import base.maybe : Maybe, MaybeIndex;
import base.murmur : murmurHash3;
import base.stdio : printed;
import common.content.declarations : Declarations, FieldDecl, ValueType, checkContent, fillDefaults;
import plugins.api.content : ContentRef, Holder, Need;

enum size_t PROBLEM_CAPACITY = 256;
enum string ENGINE_OWNER = "engine";

enum Phase : ubyte {
    defining,
    frozen,
}

enum Standing : ubyte {
    kept,
    removed,
    lapsed,
}

enum ValueKind : ubyte {
    number,
    text,
}

struct Text {
    const(char)[] text;

    size_t toHash() const {
        return cast(size_t) murmurHash3(cast(const(ubyte)[]) text).first;
    }

    bool opEquals(ref const Text other) const {
        return text == other.text;
    }
}

immutable Holder[2] HOLDINGS = [Holder.node, Holder.edge];

struct NameKey {
    uint name;

    size_t toHash() const {
        return name;
    }
}

struct ContentNode {
    uint name;
    uint kind;
    uint owner;
    uint ordinal;
    Standing standing;
}

struct ContentEdge {
    uint kind;
    uint fromName;
    uint toName;
    uint from;
    uint to;
    uint owner;
    Standing standing;
    Need need;
}

struct Attribute {
    double number = 0;
    uint holder;
    uint key;
    uint text;
    Holder holding;
    ValueKind value;
}

struct Problem {
    const(char)[] message;
    uint owner;
}

struct Range {
    uint first;
    uint end;
}

MaybeIndex!uint targetOf(ref const ContentGraph graph, uint node, const(char)[] kind) {
    const(uint)[] edges = graph.edgesFrom(node);
    size_t index = 0;
    while (index < edges.length && !graph.isEdgeKind(edges[index], kind)) {
        index += 1;
    }
    if (index < edges.length) {
        return MaybeIndex!uint.of(graph.edges.ptr[edges[index]].to);
    } else {
        return MaybeIndex!uint.init;
    }
}

struct ContentGraph {
    Array!(const(char)[]) names;
    HashMap!(Text, uint) nameIndex;
    Array!ContentNode nodes;
    Array!ContentEdge edges;
    Array!Attribute attributes;
    Array!Problem problems;
    Declarations declarations;
    HashMap!(NameKey, uint) nodeOfName;
    Array!uint fromOffsets;
    Array!uint fromEdges;
    Array!uint toOffsets;
    Array!uint toEdges;
    Array!Range nodeAttributes;
    Array!Range edgeAttributes;
    Array!uint kindCounts;
    uint owner;
    Phase phase;

    uint intern(const(char)[] text) {
        uint* found = nameIndex.find(Text(text));
        if (found !is null) {
            return *found;
        } else {
            char* copy = cast(char*) malloc(text.length + 1);
            memcpy(copy, text.ptr, text.length);
            copy[text.length] = 0;
            const(char)[] kept = copy[0 .. text.length];
            uint index = cast(uint) names.length;
            names.append(kept);
            nameIndex.insert(Text(kept), index);
            return index;
        }
    }

    Maybe!uint interned(const(char)[] text) const {
        const(uint)* found = nameIndex.find(Text(text));
        if (found is null) {
            return Maybe!uint.init;
        } else {
            return Maybe!uint.of(*found);
        }
    }

    const(char)[] textOf(uint name) const {
        return names.ptr[name];
    }

    void ownedBy(const(char)[] mod) {
        owner = intern(mod);
    }

    void report(uint by, const(char)[] message) {
        char* copy = cast(char*) malloc(message.length + 1);
        memcpy(copy, message.ptr, message.length);
        copy[message.length] = 0;
        problems.append(Problem(copy[0 .. message.length], by));
    }

    MaybeIndex!uint nodeNamed(const(char)[] name) const {
        Maybe!uint text = interned(name);
        if (!text.exists) {
            return MaybeIndex!uint.init;
        } else {
            const(uint)* found = nodeOfName.find(NameKey(text.value));
            if (found is null) {
                return MaybeIndex!uint.init;
            } else {
                return MaybeIndex!uint.of(*found);
            }
        }
    }

    ContentRef defineNode(const(char)[] kind, const(char)[] name) {
        assert(phase == Phase.defining);
        uint kindName = intern(kind);
        uint nodeName = intern(name);
        uint* found = nodeOfName.find(NameKey(nodeName));
        if (found is null) {
            uint index = cast(uint) nodes.length;
            nodes.append(ContentNode(nodeName, kindName, owner, 0, Standing.kept));
            nodeOfName.insert(NameKey(nodeName), index);
            return ContentRef(index, Holder.node);
        } else {
            ContentNode* node = &nodes.ptr[*found];
            if (node.kind != kindName) {
                char[PROBLEM_CAPACITY] buffer;
                report(owner, printed(buffer[], "'%.*s' is defined as a %.*s and again as a %.*s", cast(int) name.length, name.ptr, cast(int) textOf(node.kind).length, textOf(node.kind).ptr, cast(int) kind.length, kind.ptr));
            }
            node.standing = Standing.kept;
            return ContentRef(*found, Holder.node);
        }
    }

    ContentRef defineEdge(const(char)[] kind, const(char)[] from, const(char)[] to, Need need) {
        assert(phase == Phase.defining);
        uint index = cast(uint) edges.length;
        edges.append(ContentEdge(intern(kind), intern(from), intern(to), 0, 0, owner, Standing.kept, need));
        return ContentRef(index, Holder.edge);
    }

    void removeNode(const(char)[] name) {
        assert(phase == Phase.defining);
        MaybeIndex!uint node = nodeNamed(name);
        if (node.exists) {
            nodes.ptr[node.value].standing = Standing.removed;
        }
    }

    void removeEdges(const(char)[] kind, const(char)[] from, const(char)[] to) {
        assert(phase == Phase.defining);
        Maybe!uint kindName = interned(kind);
        Maybe!uint fromName = interned(from);
        Maybe!uint toName = interned(to);
        if (kindName.exists && fromName.exists && toName.exists) {
            foreach (ref edge; edges.slice()) {
                if (edge.kind == kindName.value && edge.fromName == fromName.value && edge.toName == toName.value) {
                    edge.standing = Standing.removed;
                }
            }
        }
    }

    void setNumber(ContentRef target, const(char)[] key, double value) {
        Attribute* attribute = attributeFor(target, intern(key));
        attribute.number = value;
        attribute.value = ValueKind.number;
    }

    void setText(ContentRef target, const(char)[] key, const(char)[] value) {
        uint text = intern(value);
        Attribute* attribute = attributeFor(target, intern(key));
        attribute.text = text;
        attribute.value = ValueKind.text;
    }

    Attribute* attributeFor(ContentRef target, uint key) {
        assert(phase == Phase.defining);
        uint index = 0;
        while (index < attributes.length && !(attributes.ptr[index].holder == target.index && attributes.ptr[index].holding == target.holding && attributes.ptr[index].key == key)) {
            index += 1;
        }
        if (index == attributes.length) {
            Attribute made;
            made.holder = target.index;
            made.holding = target.holding;
            made.key = key;
            attributes.append(made);
        }
        return &attributes.ptr[index];
    }

    void freeze() {
        assert(phase == Phase.defining);
        resolveEdges();
        checkContent(this);
        fillDefaults(this);
        numberKinds();
        index();
        phase = Phase.frozen;
    }

    void resolveEdges() {
        char[PROBLEM_CAPACITY] buffer;
        foreach (ref edge; edges.slice()) {
            uint* from = nodeOfName.find(NameKey(edge.fromName));
            uint* to = nodeOfName.find(NameKey(edge.toName));
            if (edge.standing == Standing.kept && from is null) {
                report(edge.owner, printed(buffer[], "a %.*s edge runs from '%.*s', which nothing defines", cast(int) textOf(edge.kind).length, textOf(edge.kind).ptr, cast(int) textOf(edge.fromName).length, textOf(edge.fromName).ptr));
                edge.standing = Standing.removed;
            } else if (edge.standing == Standing.kept && to is null && edge.need == Need.optional) {
                edge.from = *from;
                edge.standing = Standing.lapsed;
            } else if (edge.standing == Standing.kept && to is null) {
                report(edge.owner, printed(buffer[], "a %.*s edge names '%.*s', which nothing defines", cast(int) textOf(edge.kind).length, textOf(edge.kind).ptr, cast(int) textOf(edge.toName).length, textOf(edge.toName).ptr));
                edge.standing = Standing.removed;
            } else if (edge.standing == Standing.kept) {
                edge.from = *from;
                edge.to = *to;
            }
        }
    }

    void index() {
        indexEdges();
        indexAttributes();
    }

    const(uint)[] outgoing(uint node) const return {
        return fromEdges.slice()[fromOffsets.ptr[node] .. fromOffsets.ptr[node + 1]];
    }

    const(Attribute)[] attributesOf(ContentRef target) const return {
        Range range = rangesOf(target.holding).ptr[target.index];
        return attributes.slice()[range.first .. range.end];
    }

    const(Attribute)* attributeIn(ContentRef target, uint key) const {
        const(Attribute)[] held = attributesOf(target);
        size_t index = 0;
        while (index < held.length && held[index].key != key) {
            index += 1;
        }
        if (index < held.length) {
            return &held[index];
        } else {
            return null;
        }
    }

    void fillDefault(ContentRef target, ref const FieldDecl field) {
        Attribute made;
        made.holder = target.index;
        made.holding = target.holding;
        made.key = field.key;
        if (field.type == ValueType.number || field.type == ValueType.integer) {
            made.number = field.fallbackNumber;
            made.value = ValueKind.number;
        } else {
            made.text = field.fallbackText;
            made.value = ValueKind.text;
        }
        attributes.append(made);
    }

    void numberKinds() {
        kindCounts.resize(names.length);
        foreach (ref count; kindCounts.slice()) {
            count = 0;
        }
        foreach (ref node; nodes.slice()) {
            if (node.standing == Standing.kept) {
                node.ordinal = kindCounts.ptr[node.kind];
                kindCounts.ptr[node.kind] += 1;
            }
        }
    }

    void indexEdges() {
        fromOffsets.resize(nodes.length + 1);
        toOffsets.resize(nodes.length + 1);
        foreach (index; 0 .. nodes.length + 1) {
            fromOffsets.ptr[index] = 0;
            toOffsets.ptr[index] = 0;
        }
        foreach (ref edge; edges.slice()) {
            if (edge.standing == Standing.kept) {
                fromOffsets.ptr[edge.from + 1] += 1;
                toOffsets.ptr[edge.to + 1] += 1;
            }
        }
        foreach (index; 1 .. nodes.length + 1) {
            fromOffsets.ptr[index] += fromOffsets.ptr[index - 1];
            toOffsets.ptr[index] += toOffsets.ptr[index - 1];
        }
        fromEdges.resize(fromOffsets.ptr[nodes.length]);
        toEdges.resize(toOffsets.ptr[nodes.length]);
        Array!uint fromFill;
        Array!uint toFill;
        fromFill.appendAll(fromOffsets.slice()[0 .. nodes.length]);
        toFill.appendAll(toOffsets.slice()[0 .. nodes.length]);
        foreach (index, ref edge; edges.slice()) {
            if (edge.standing == Standing.kept) {
                fromEdges.ptr[fromFill.ptr[edge.from]] = cast(uint) index;
                fromFill.ptr[edge.from] += 1;
                toEdges.ptr[toFill.ptr[edge.to]] = cast(uint) index;
                toFill.ptr[edge.to] += 1;
            }
        }
        fromFill.release();
        toFill.release();
    }

    void indexAttributes() {
        nodeAttributes.resize(nodes.length);
        edgeAttributes.resize(edges.length);
        foreach (ref range; nodeAttributes.slice()) {
            range = Range(0, 0);
        }
        foreach (ref range; edgeAttributes.slice()) {
            range = Range(0, 0);
        }
        foreach (ref attribute; attributes.slice()) {
            rangesOf(attribute.holding).ptr[attribute.holder].end += 1;
        }
        uint start = 0;
        foreach (holding; HOLDINGS) {
            foreach (ref range; rangesOf(holding).slice()) {
                uint count = range.end;
                range = Range(start, start);
                start += count;
            }
        }
        Array!Attribute sorted;
        sorted.resize(attributes.length);
        foreach (ref attribute; attributes.slice()) {
            Range* range = &rangesOf(attribute.holding).ptr[attribute.holder];
            sorted.ptr[range.end] = attribute;
            range.end += 1;
        }
        attributes.release();
        attributes = sorted;
    }

    inout(Array!Range)* rangesOf(Holder holding) inout return {
        final switch (holding) {
            case Holder.node:
                return &nodeAttributes;
            case Holder.edge:
                return &edgeAttributes;
        }
    }

    uint countOf(const(char)[] kind) const {
        Maybe!uint name = interned(kind);
        if (!name.exists || name.value >= kindCounts.length) {
            return 0;
        } else {
            return kindCounts.ptr[name.value];
        }
    }

    bool isKind(uint node, const(char)[] kind) const {
        return nodes.ptr[node].standing == Standing.kept && textOf(nodes.ptr[node].kind) == kind;
    }

    const(char)[] nameOf(uint node) const {
        return textOf(nodes.ptr[node].name);
    }

    uint ordinalOf(uint node) const {
        return nodes.ptr[node].ordinal;
    }

    const(uint)[] edgesFrom(uint node) const return {
        assert(phase == Phase.frozen);
        return fromEdges.slice()[fromOffsets.ptr[node] .. fromOffsets.ptr[node + 1]];
    }

    const(uint)[] edgesTo(uint node) const return {
        assert(phase == Phase.frozen);
        return toEdges.slice()[toOffsets.ptr[node] .. toOffsets.ptr[node + 1]];
    }

    bool isEdgeKind(uint edge, const(char)[] kind) const {
        return textOf(edges.ptr[edge].kind) == kind;
    }

    const(Attribute)* attributeOf(ContentRef target, const(char)[] key) const {
        assert(phase == Phase.frozen);
        Maybe!uint name = interned(key);
        if (!name.exists) {
            return null;
        } else {
            Range range = rangesOf(target.holding).ptr[target.index];
            uint index = range.first;
            while (index < range.end && attributes.ptr[index].key != name.value) {
                index += 1;
            }
            if (index < range.end) {
                return &attributes.ptr[index];
            } else {
                return null;
            }
        }
    }

    Maybe!double numberOf(ContentRef target, const(char)[] key) const {
        const(Attribute)* attribute = attributeOf(target, key);
        if (attribute is null || attribute.value != ValueKind.number) {
            return Maybe!double.init;
        } else {
            return Maybe!double.of(attribute.number);
        }
    }

    double number(ContentRef target, const(char)[] key) const {
        return numberOf(target, key).value;
    }

    double numberOr(ContentRef target, const(char)[] key, double fallback) const {
        Maybe!double found = numberOf(target, key);
        if (found.exists) {
            return found.value;
        } else {
            return fallback;
        }
    }

    const(char)[] textAt(ContentRef target, const(char)[] key) const {
        const(Attribute)* attribute = attributeOf(target, key);
        if (attribute is null || attribute.value != ValueKind.text) {
            return null;
        } else {
            return textOf(attribute.text);
        }
    }

    void release() {
        foreach (text; names.slice()) {
            free(cast(void*) text.ptr);
        }
        foreach (ref problem; problems.slice()) {
            free(cast(void*) problem.message.ptr);
        }
        names.release();
        nameIndex.release();
        nodes.release();
        edges.release();
        attributes.release();
        problems.release();
        declarations.release();
        nodeOfName.release();
        fromOffsets.release();
        fromEdges.release();
        toOffsets.release();
        toEdges.release();
        nodeAttributes.release();
        edgeAttributes.release();
        kindCounts.release();
    }
}

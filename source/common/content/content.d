module common.content.content;

static import base.maybe;
import base.array : Array;
import base.stdio : fprintf, printed, stderr;
import plugins.api.api : MaybeIndex;
import common.content.data : loadData;
import common.content.declarations : ValueType, declare;
import common.content.graph : ContentGraph, ENGINE_OWNER, PROBLEM_CAPACITY, Phase, Standing;
import common.content.mods : ModOrder, Reason, Refusal, refusedDependencyOf;
import common.content.settings : MOD_KIND, parseOverrides, parseSettings;
import common.perception : CHANNEL_NAMES;
import plugins.api.content : Content, ContentRef, EdgeView, FieldShape, Happening, Holder, Hook, Manifest, Misfit, Need, Play;

enum string AIR = "engine:air";
enum string HAND = "engine:hand";
enum string ENGINE_DECLARATIONS = "content/engine.decl";
enum string USER_OWNER = "user settings";
enum string USER_SETTINGS = "settings.conf";

__gshared ContentGraph contentGraph;

ref ContentGraph graphOf(const(Content)* content) {
    return *cast(ContentGraph*) content.host;
}

ContentRef contentNode(const(Content)* content, const(char)[] kind, const(char)[] name) {
    return graphOf(content).defineNode(kind, name);
}

ContentRef contentEdge(const(Content)* content, const(char)[] kind, const(char)[] from, const(char)[] to) {
    return graphOf(content).defineEdge(kind, from, to, Need.required);
}

ContentRef contentOptionalEdge(const(Content)* content, const(char)[] kind, const(char)[] from, const(char)[] to) {
    return graphOf(content).defineEdge(kind, from, to, Need.optional);
}

void contentNumber(const(Content)* content, ContentRef target, const(char)[] key, double value) {
    graphOf(content).setNumber(target, key, value);
}

void contentText(const(Content)* content, ContentRef target, const(char)[] key, const(char)[] value) {
    graphOf(content).setText(target, key, value);
}

void contentRemoveNode(const(Content)* content, const(char)[] name) {
    graphOf(content).removeNode(name);
}

void contentRemoveEdges(const(Content)* content, const(char)[] kind, const(char)[] from, const(char)[] to) {
    graphOf(content).removeEdges(kind, from, to);
}

MaybeIndex!Content contentFind(const(Content)* content, const(char)[] name) {
    base.maybe.MaybeIndex!uint node = graphOf(content).nodeNamed(name);
    if (node.exists && graphOf(content).nodes.ptr[node.value].standing == Standing.kept) {
        return MaybeIndex!Content.of(node.value);
    } else {
        return MaybeIndex!Content.init;
    }
}

const(char)[] contentNameOf(const(Content)* content, uint node) {
    return graphOf(content).nameOf(node);
}

const(char)[] contentKindOf(const(Content)* content, uint node) {
    return graphOf(content).textOf(graphOf(content).nodes.ptr[node].kind);
}

uint contentEdgeCount(const(Content)* content, uint node) {
    return cast(uint) graphOf(content).edgesFrom(node).length;
}

EdgeView contentEdgeAt(const(Content)* content, uint node, uint index) {
    ContentGraph* graph = &graphOf(content);
    uint edge = graph.edgesFrom(node)[index];
    return EdgeView(ContentRef(edge, Holder.edge), graph.edges.ptr[edge].to, graph.textOf(graph.edges.ptr[edge].kind));
}

double contentNumberOr(const(Content)* content, ContentRef target, const(char)[] key, double fallback) {
    return graphOf(content).numberOr(target, key, fallback);
}

const(char)[] contentTextAt(const(Content)* content, ContentRef target, const(char)[] key) {
    return graphOf(content).textAt(target, key);
}

base.maybe.MaybeIndex!uint modNode(ref ContentGraph graph, const(char)[] mod) {
    base.maybe.MaybeIndex!uint node = graph.nodeNamed(mod);
    if (node.exists && graph.isKind(node.value, MOD_KIND)) {
        return node;
    } else {
        return base.maybe.MaybeIndex!uint.init;
    }
}

void reportMissingSetting(ref ContentGraph graph, const(char)[] mod, const(char)[] key) {
    char[PROBLEM_CAPACITY] buffer;
    graph.report(graph.owner, printed(buffer[], "reads the setting '%.*s' of '%.*s', which its settings do not have", cast(int) key.length, key.ptr, cast(int) mod.length, mod.ptr));
}

double contentSetting(const(Content)* content, const(char)[] mod, const(char)[] key) {
    ContentGraph* graph = &graphOf(content);
    base.maybe.MaybeIndex!uint node = modNode(*graph, mod);
    base.maybe.Maybe!double found;
    if (node.exists) {
        found = graph.numberOf(ContentRef(node.value, Holder.node), key);
    }
    if (found.exists) {
        return found.value;
    } else {
        reportMissingSetting(*graph, mod, key);
        return 0;
    }
}

const(char)[] contentSettingText(const(Content)* content, const(char)[] mod, const(char)[] key) {
    ContentGraph* graph = &graphOf(content);
    base.maybe.MaybeIndex!uint node = modNode(*graph, mod);
    const(char)[] found;
    if (node.exists) {
        found = graph.textAt(ContentRef(node.value, Holder.node), key);
    }
    if (found is null) {
        reportMissingSetting(*graph, mod, key);
    }
    return found;
}

uint contentOrdinalOf(const(Content)* content, uint node) {
    return graphOf(content).ordinalOf(node);
}

MaybeIndex!Content contentRequire(const(Content)* content, const(char)[] name) {
    MaybeIndex!Content found = contentFind(content, name);
    ContentGraph* graph = &graphOf(content);
    char[PROBLEM_CAPACITY] buffer;
    if (!found.exists && graph.nodeNamed(name).exists) {
        graph.report(graph.owner, printed(buffer[], "asks for '%.*s', which was dropped", cast(int) name.length, name.ptr));
    } else if (!found.exists) {
        graph.report(graph.owner, printed(buffer[], "asks for '%.*s', which no mod defines", cast(int) name.length, name.ptr));
    }
    return found;
}

FieldShape contentShapeOf(const(Content)* content, const(char)[] kind, const(char)[] field) {
    ContentGraph* graph = &graphOf(content);
    base.maybe.Maybe!uint kindName = graph.interned(kind);
    base.maybe.Maybe!uint key = graph.interned(field);
    if (!kindName.exists || !key.exists) {
        return FieldShape.undeclared;
    } else {
        base.maybe.MaybeIndex!uint edge = graph.declarations.edgeOf(kindName.value, key.value);
        base.maybe.MaybeIndex!uint attribute = graph.declarations.fieldOf(Holder.node, kindName.value, key.value);
        if (edge.exists && graph.declarations.edges.ptr[edge.value].most == 1) {
            return FieldShape.single;
        } else if (edge.exists) {
            return FieldShape.multiple;
        } else if (attribute.exists) {
            return shapeOfValue(graph.declarations.fields.ptr[attribute.value].type);
        } else {
            return FieldShape.undeclared;
        }
    }
}

FieldShape shapeOfValue(ValueType type) {
    final switch (type) {
        case ValueType.number:
        case ValueType.integer:
            return FieldShape.number;
        case ValueType.text:
        case ValueType.choice:
            return FieldShape.text;
    }
}

immutable string[Misfit.max + 1] MISFITS = [
    Misfit.undeclared: "reads '%.*s' of '%.*s', which a %.*s does not declare",
    Misfit.shape: "reads '%.*s' of '%.*s' in another shape than a %.*s declares",
    Misfit.overflow: "holds fewer '%.*s' edges of '%.*s' than it has, a %.*s",
];

void contentMisfit(const(Content)* content, uint node, const(char)[] field, Misfit misfit) {
    char[PROBLEM_CAPACITY] buffer;
    ContentGraph* graph = &graphOf(content);
    const(char)[] name = graph.nameOf(node);
    const(char)[] kind = graph.textOf(graph.nodes.ptr[node].kind);
    graph.report(graph.owner, printed(buffer[], MISFITS[misfit].ptr, cast(int) field.length, field.ptr, cast(int) name.length, name.ptr, cast(int) kind.length, kind.ptr));
}

Content contentApi() {
    return Content(&contentGraph, &contentNode, &contentEdge, &contentOptionalEdge, &contentNumber, &contentText, &contentRemoveNode, &contentRemoveEdges, &contentFind, &contentNameOf, &contentKindOf, &contentEdgeCount, &contentEdgeAt, &contentNumberOr, &contentTextAt, &contentSetting, &contentSettingText, &contentOrdinalOf, &contentRequire, &contentShapeOf, &contentMisfit);
}

__gshared Content readApi;
__gshared Array!Hook hooks;

const(char)[] keptText(const(char)[] text) {
    return contentGraph.textOf(contentGraph.intern(text));
}

void fire(const(Play)* play, Happening happening) {
    foreach (hook; hooks.slice()) {
        hook(play, happening);
    }
}

void defineEngine() {
    contentGraph.ownedBy(ENGINE_OWNER);
    declare(contentGraph, import(ENGINE_DECLARATIONS), ENGINE_DECLARATIONS);
    contentGraph.defineNode("material", AIR);
    contentGraph.defineNode("station", HAND);
    foreach (name; CHANNEL_NAMES) {
        contentGraph.defineNode("channel", name);
    }
}

void defineMods(const(Manifest)[] manifests, const(uint)[] order, const(char)[] overrides) {
    Content api = contentApi();
    foreach (mod; order) {
        contentGraph.ownedBy(manifests[mod].name);
        declare(contentGraph, manifests[mod].declarations, manifests[mod].name);
        ContentRef made = contentGraph.defineNode(MOD_KIND, manifests[mod].name);
        parseSettings(contentGraph, made, manifests[mod].settings, manifests[mod].name);
        loadData(contentGraph, manifests[mod].data, manifests[mod].name);
        if (manifests[mod].define !is null) {
            manifests[mod].define(&api);
        }
    }
    contentGraph.ownedBy(USER_OWNER);
    parseOverrides(contentGraph, overrides, USER_SETTINGS);
}

void resolveMods(const(Manifest)[] manifests, ref ModOrder order) {
    readApi = contentApi();
    foreach (mod; order.order.slice()) {
        base.maybe.MaybeIndex!uint dependency = refusedDependencyOf(manifests, order, mod);
        if (dependency.exists) {
            order.refused.append(Refusal(mod, dependency.value, Reason.refusedDependency));
        } else {
            size_t before = contentGraph.problems.length;
            contentGraph.ownedBy(manifests[mod].name);
            if (manifests[mod].resolve !is null) {
                manifests[mod].resolve(&readApi);
            }
            if (contentGraph.problems.length > before) {
                order.refused.append(Refusal(mod, 0, Reason.unbound));
            } else if (manifests[mod].hook !is null) {
                hooks.append(manifests[mod].hook);
            }
        }
    }
}

uint reportProblems() {
    foreach (ref problem; contentGraph.problems.slice()) {
        const(char)[] owner = contentGraph.textOf(problem.owner);
        fprintf(stderr, "content from '%.*s': %.*s\n", cast(int) owner.length, owner.ptr, cast(int) problem.message.length, problem.message.ptr);
    }
    return cast(uint) contentGraph.problems.length;
}

ref const(ContentGraph) content() {
    assert(contentGraph.phase == Phase.frozen);
    return contentGraph;
}

module plugins.api.content;

import plugins.api.api : MaybeIndex;

enum Holder : ubyte {
    node,
    edge,
}

struct ContentRef {
    uint index;
    Holder holding;
}

enum Need : ubyte {
    required,
    optional,
}

struct Version {
    uint major;
    uint minor;
    uint patch;
}

struct Dependency {
    const(char)[] name;
    Version least;
    Need need;
}

struct EdgeView {
    ContentRef edge;
    uint to;
    const(char)[] kind;
}

struct Content {
    void* host;
    ContentRef function(const(Content)* content, const(char)[] kind, const(char)[] name) node;
    ContentRef function(const(Content)* content, const(char)[] kind, const(char)[] from, const(char)[] to) edge;
    ContentRef function(const(Content)* content, const(char)[] kind, const(char)[] from, const(char)[] to) optionalEdge;
    void function(const(Content)* content, ContentRef target, const(char)[] key, double value) number;
    void function(const(Content)* content, ContentRef target, const(char)[] key, const(char)[] value) text;
    void function(const(Content)* content, const(char)[] name) removeNode;
    void function(const(Content)* content, const(char)[] kind, const(char)[] from, const(char)[] to) removeEdges;
    MaybeIndex!Content function(const(Content)* content, const(char)[] name) find;
    const(char)[] function(const(Content)* content, uint node) nameOf;
    const(char)[] function(const(Content)* content, uint node) kindOf;
    uint function(const(Content)* content, uint node) edgeCount;
    EdgeView function(const(Content)* content, uint node, uint index) edgeAt;
    double function(const(Content)* content, ContentRef target, const(char)[] key, double fallback) numberOr;
    const(char)[] function(const(Content)* content, ContentRef target, const(char)[] key) textAt;
    double function(const(Content)* content, const(char)[] mod, const(char)[] key) setting;
    const(char)[] function(const(Content)* content, const(char)[] mod, const(char)[] key) settingText;
    uint function(const(Content)* content, uint node) ordinalOf;
    MaybeIndex!Content function(const(Content)* content, const(char)[] name) require;
    FieldShape function(const(Content)* content, const(char)[] kind, const(char)[] field) shapeOf;
    void function(const(Content)* content, uint node, const(char)[] field, Misfit misfit) misfit;
}

enum FieldShape : ubyte {
    undeclared,
    number,
    text,
    single,
    multiple,
}

enum Misfit : ubyte {
    undeclared,
    shape,
    overflow,
}

enum Event : ubyte {
    broke,
    placed,
    crafted,
    dosed,
}

struct Happening {
    const(char)[] subject;
    Event event;
}

struct Play {
    void* host;
    const(Content)* content;
    void function(const(Play)* play, const(char)[] item, uint count) give;
    void function(const(Play)* play, const(char)[] insight) learn;
    void function(const(Play)* play, const(char)[] text) note;
}

enum size_t SETTING_KEY_CAPACITY = 64;
enum uint DECIMAL = 10;

double settingAt(const(Content)* content, const(char)[] mod, const(char)[] list, uint index) {
    char[SETTING_KEY_CAPACITY] key;
    size_t length = 0;
    foreach (c; list) {
        key[length] = c;
        length += 1;
    }
    key[length] = '.';
    length += 1;
    char[SETTING_KEY_CAPACITY] reversed;
    size_t digits = 0;
    uint left = index;
    while (left > 0 || digits == 0) {
        reversed[digits] = cast(char)('0' + left % DECIMAL);
        left /= DECIMAL;
        digits += 1;
    }
    while (digits > 0) {
        digits -= 1;
        key[length] = reversed[digits];
        length += 1;
    }
    return content.setting(content, mod, key[0 .. length]);
}

enum string BASE = "base";
enum Version FIRST_VERSION = Version(1, 0, 0);

Dependency dependencyOn(const(char)[] name) {
    return Dependency(name, FIRST_VERSION, Need.required);
}

immutable Dependency[1] ON_BASE = [dependencyOn(BASE)];

alias Define = void function(const(Content)* content);
alias Resolve = void function(const(Content)* content);
alias Hook = void function(const(Play)* play, Happening happening);

struct Manifest {
    const(char)[] name;
    Version current;
    const(Dependency)[] dependencies;
    Define define;
    Resolve resolve;
    Hook hook;
    const(char)[] settings;
    const(char)[] declarations;
    const(char)[] data;
}

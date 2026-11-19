module plugins.api.binding;

import plugins.api.api : Material, MaybeIndex, tagNamed;
import plugins.api.content : Content, ContentRef, EdgeView, FieldShape, Holder, Misfit, settingAt;

enum string MATERIAL_KIND = "material";
enum string LOWER = "abcdefghijklmnopqrstuvwxyz";

struct Named {
    uint tag;
}

struct Text {
    const(char)[] text;
}

enum string WEIGHT_FIELD = "weight";

struct Weighted(T) {
    T target;
    double weight = 1;
}

struct List(T, size_t capacity) {
    T[capacity] items;
    uint count;

    inout(T)[] slice() inout return {
        return items[0 .. count];
    }
}

template kebabOf(string name, char previous = 'a') {
    static if (name.length == 0) {
        enum string kebabOf = "";
    } else static if (name[0] >= 'A' && name[0] <= 'Z') {
        enum string kebabOf = "-" ~ LOWER[name[0] - 'A' .. name[0] - 'A' + 1] ~ kebabOf!(name[1 .. $], name[0]);
    } else static if (name[0] >= '0' && name[0] <= '9' && !(previous >= '0' && previous <= '9')) {
        enum string kebabOf = "-" ~ name[0 .. 1] ~ kebabOf!(name[1 .. $], name[0]);
    } else {
        enum string kebabOf = name[0 .. 1] ~ kebabOf!(name[1 .. $], name[0]);
    }
}

T bound(T)(const(Content)* content, const(char)[] name) {
    T made;
    MaybeIndex!Content found = content.require(content, name);
    if (found.exists) {
        content.readNode(found.value, made);
    }
    return made;
}

T settingsOf(T)(const(Content)* content, const(char)[] mod) {
    T made;
    static foreach (index; 0 .. T.tupleof.length) {
        content.readSetting!(kebabOf!(__traits(identifier, T.tupleof[index])))(mod, made.tupleof[index]);
    }
    return made;
}

void readSetting(string key, F)(const(Content)* content, const(char)[] mod, ref F into) {
    static if (is(F == E[count], E, size_t count)) {
        foreach (index; 0 .. cast(uint) count) {
            into[index] = cast(E) content.settingAt(mod, key, index);
        }
    } else {
        into = cast(F) content.setting(content, mod, key);
    }
}

void readNode(T)(const(Content)* content, uint node, ref T into) {
    const(char)[] kind = content.kindOf(content, node);
    static foreach (index; 0 .. T.tupleof.length) {
        content.readField!(kebabOf!(__traits(identifier, T.tupleof[index])))(node, kind, into.tupleof[index]);
    }
}

void readField(string field, F)(const(Content)* content, uint node, const(char)[] kind, ref F into) {
    FieldShape shape = content.shapeOf(content, kind, field);
    if (shape == FieldShape.undeclared) {
        content.misfit(content, node, field, Misfit.undeclared);
    } else if (shape != shapeFor!F) {
        content.misfit(content, node, field, Misfit.shape);
    } else {
        static if (is(F == List!(U, capacity), U, size_t capacity)) {
            foreach (index; 0 .. content.edgeCount(content, node)) {
                EdgeView view = content.edgeAt(content, node, index);
                if (view.kind == field && into.count == capacity) {
                    content.misfit(content, node, field, Misfit.overflow);
                } else if (view.kind == field) {
                    static if (is(U == Weighted!V, V)) {
                        content.readTarget(node, view.to, field, into.items[into.count].target);
                        into.items[into.count].weight = content.numberOr(content, view.edge, WEIGHT_FIELD, 1);
                    } else {
                        content.readTarget(node, view.to, field, into.items[into.count]);
                    }
                    into.count += 1;
                }
            }
        } else static if (is(F == Named)) {
            into = Named(tagNamed(content.textAt(content, ContentRef(node, Holder.node), field)));
        } else static if (is(F == Text)) {
            into = Text(content.textAt(content, ContentRef(node, Holder.node), field));
        } else static if (shapeFor!F == FieldShape.single) {
            foreach (index; 0 .. content.edgeCount(content, node)) {
                EdgeView view = content.edgeAt(content, node, index);
                if (view.kind == field) {
                    content.readTarget(node, view.to, field, into);
                }
            }
        } else static if (is(F == enum)) {
            const(char)[] text = content.textAt(content, ContentRef(node, Holder.node), field);
            uint matched = 0;
            static foreach (member; __traits(allMembers, F)) {
                if (text == kebabOf!member) {
                    into = __traits(getMember, F, member);
                    matched += 1;
                }
            }
            if (matched == 0) {
                content.misfit(content, node, field, Misfit.shape);
            }
        } else {
            into = cast(F) content.numberOr(content, ContentRef(node, Holder.node), field, into);
        }
    }
}

void readTarget(T)(const(Content)* content, uint from, uint to, const(char)[] field, ref T into) {
    static if (is(T == Material)) {
        if (content.kindOf(content, to) == MATERIAL_KIND) {
            into = Material(cast(ubyte) content.ordinalOf(content, to));
        } else {
            content.misfit(content, from, field, Misfit.shape);
        }
    } else {
        content.readNode(to, into);
    }
}

template shapeFor(F) {
    static if (is(F == List!(U, capacity), U, size_t capacity)) {
        enum FieldShape shapeFor = FieldShape.multiple;
    } else static if (is(F == Named) || is(F == Text)) {
        enum FieldShape shapeFor = FieldShape.text;
    } else static if (is(F == struct)) {
        enum FieldShape shapeFor = FieldShape.single;
    } else static if (is(F == enum)) {
        enum FieldShape shapeFor = FieldShape.text;
    } else static if (__traits(isArithmetic, F)) {
        enum FieldShape shapeFor = FieldShape.number;
    } else {
        static assert(false, "a bound field is a number, an enum, a Named, a Text, a Material, a struct or a List");
    }
}

module plugins.game.bindings;

import base.array : Array;
import base.maybe : Maybe;
import base.names : ENUM_NAMES;
import plugins.game.config : ConfigEntry;
import plugins.game.game : Game;

enum size_t KEY_NAME_CAPACITY = 24;
enum string BINDING_PREFIX = "bind_";

enum Action : ubyte {
    forward,
    back,
    left,
    right,
    jump,
    sink,
    turnLeft,
    turnRight,
    lookUp,
    lookDown,
    mine,
    use,
    inventory,
    journal,
    previousSlot,
    nextSlot,
    slot1,
    slot2,
    slot3,
    slot4,
    slot5,
    slot6,
    slot7,
    slot8,
    slot9,
    slot10,
    slot11,
    slot12,
    fly,
    noclip,
    previousWorld,
    nextWorld,
    throwBlock,
    nextPreset,
}

enum uint ACTION_COUNT = Action.max + 1;
enum uint MOST_EXTRAS = 8;
enum uint MOST_BOUND = ACTION_COUNT + MOST_EXTRAS;

enum Rules : ubyte {
    survival,
    creative,
}

struct ActionInfo {
    string label;
    string key;
    Rules needs;
}

immutable ActionInfo[ACTION_COUNT] ACTIONS = [
    Action.forward: ActionInfo("walk forward", "w", Rules.survival),
    Action.back: ActionInfo("walk back", "s", Rules.survival),
    Action.left: ActionInfo("step left", "a", Rules.survival),
    Action.right: ActionInfo("step right", "d", Rules.survival),
    Action.jump: ActionInfo("jump", "space", Rules.survival),
    Action.sink: ActionInfo("crouch, sink when flying", "Shift_L", Rules.survival),
    Action.turnLeft: ActionInfo("turn left", "Left", Rules.survival),
    Action.turnRight: ActionInfo("turn right", "Right", Rules.survival),
    Action.lookUp: ActionInfo("look up", "Up", Rules.survival),
    Action.lookDown: ActionInfo("look down", "Down", Rules.survival),
    Action.mine: ActionInfo("mine (hold)", "button1", Rules.survival),
    Action.use: ActionInfo("place or use", "button3", Rules.survival),
    Action.inventory: ActionInfo("inventory", "e", Rules.survival),
    Action.journal: ActionInfo("journal", "j", Rules.survival),
    Action.previousSlot: ActionInfo("previous slot", "button4", Rules.survival),
    Action.nextSlot: ActionInfo("next slot", "button5", Rules.survival),
    Action.slot1: ActionInfo("slot 1", "1", Rules.survival),
    Action.slot2: ActionInfo("slot 2", "2", Rules.survival),
    Action.slot3: ActionInfo("slot 3", "3", Rules.survival),
    Action.slot4: ActionInfo("slot 4", "4", Rules.survival),
    Action.slot5: ActionInfo("slot 5", "5", Rules.survival),
    Action.slot6: ActionInfo("slot 6", "6", Rules.survival),
    Action.slot7: ActionInfo("slot 7", "7", Rules.survival),
    Action.slot8: ActionInfo("slot 8", "8", Rules.survival),
    Action.slot9: ActionInfo("slot 9", "9", Rules.survival),
    Action.slot10: ActionInfo("slot 10", "0", Rules.survival),
    Action.slot11: ActionInfo("slot 11", "minus", Rules.survival),
    Action.slot12: ActionInfo("slot 12", "equal", Rules.survival),
    Action.fly: ActionInfo("walk or fly", "v", Rules.creative),
    Action.noclip: ActionInfo("noclip", "n", Rules.creative),
    Action.previousWorld: ActionInfo("previous world", "bracketleft", Rules.creative),
    Action.nextWorld: ActionInfo("next world", "bracketright", Rules.creative),
    Action.throwBlock: ActionInfo("throw a block", "t", Rules.creative),
    Action.nextPreset: ActionInfo("next perception preset", "p", Rules.creative),
];

struct Extra {
    string name;
    ActionInfo info;
    void function(ref Game game) press;
    void function(ref Game game) release;
}

__gshared Array!Extra extras;

struct Bound {
    ubyte id;

    static Bound of(Action action) {
        return Bound(action);
    }
}

Bound addAction(Extra extra) {
    assert(extras.length < MOST_EXTRAS);
    extras.append(extra);
    return Bound(cast(ubyte)(ACTION_COUNT + extras.length - 1));
}

uint boundCount() {
    return ACTION_COUNT + cast(uint) extras.length;
}

bool isExtra(Bound bound) {
    return bound.id >= ACTION_COUNT;
}

ref const(Extra) extraOf(Bound bound) {
    return extras.ptr[bound.id - ACTION_COUNT];
}

ActionInfo infoOf(Bound bound) {
    if (isExtra(bound)) {
        return extraOf(bound).info;
    } else {
        return ACTIONS[bound.id];
    }
}

const(char)[] nameOf(Bound bound) {
    if (isExtra(bound)) {
        return extraOf(bound).name;
    } else {
        return ENUM_NAMES!Action[bound.id];
    }
}

Maybe!Bound boundNamed(const(char)[] name) {
    uint id = 0;
    while (id < boundCount() && nameOf(Bound(cast(ubyte) id)) != name) {
        id += 1;
    }
    if (id < boundCount()) {
        return Maybe!Bound.of(Bound(cast(ubyte) id));
    } else {
        return Maybe!Bound.init;
    }
}

struct KeyName {
    char[KEY_NAME_CAPACITY] text;
    ubyte length;

    static KeyName of(const(char)[] name) {
        KeyName made;
        size_t length = name.length;
        if (length > KEY_NAME_CAPACITY) {
            length = KEY_NAME_CAPACITY;
        }
        foreach (index; 0 .. length) {
            made.text[index] = name[index];
        }
        made.length = cast(ubyte) length;
        return made;
    }

    const(char)[] slice() const return {
        return text[0 .. length];
    }
}

char lowered(char c) {
    if (c >= 'A' && c <= 'Z') {
        return cast(char)(c - 'A' + 'a');
    } else {
        return c;
    }
}

bool isSameKey(const(char)[] a, const(char)[] b) {
    size_t index = 0;
    while (index < a.length && index < b.length && lowered(a[index]) == lowered(b[index])) {
        index += 1;
    }
    return index == a.length && index == b.length;
}

bool isAllowed(Bound bound, Rules rules) {
    return infoOf(bound).needs == Rules.survival || rules == Rules.creative;
}

struct Bindings {
    KeyName[MOST_BOUND] keys;

    static Bindings defaults() {
        Bindings made;
        foreach (id; 0 .. boundCount()) {
            made.keys[id] = KeyName.of(infoOf(Bound(cast(ubyte) id)).key);
        }
        return made;
    }

    Maybe!Bound boundOf(const(char)[] name, Rules rules) const {
        uint id = 0;
        while (id < boundCount() && !(keys[id].length > 0 && isSameKey(keys[id].slice(), name) && isAllowed(Bound(cast(ubyte) id), rules))) {
            id += 1;
        }
        if (id < boundCount()) {
            return Maybe!Bound.of(Bound(cast(ubyte) id));
        } else {
            return Maybe!Bound.init;
        }
    }

    void bind(Bound bound, const(char)[] name) {
        foreach (id; 0 .. boundCount()) {
            if (isSameKey(keys[id].slice(), name) && infoOf(Bound(cast(ubyte) id)).needs == infoOf(bound).needs) {
                keys[id] = KeyName.init;
            }
        }
        keys[bound.id] = KeyName.of(name);
    }

    void apply(ConfigEntry entry) {
        if (entry.key.length > BINDING_PREFIX.length && entry.key[0 .. BINDING_PREFIX.length] == BINDING_PREFIX) {
            Maybe!Bound bound = boundNamed(entry.key[BINDING_PREFIX.length .. $]);
            if (bound.exists) {
                keys[bound.value.id] = KeyName.of(entry.value);
            }
        }
    }
}

module client.bindings;

import base.maybe : Maybe;
import base.names : ENUM_NAMES;
import client.config : ConfigEntry;

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
    eat,
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
    dose,
    nextPreset,
}

enum uint ACTION_COUNT = Action.max + 1;

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
    Action.eat: ActionInfo("eat what you hold (hold)", "f", Rules.survival),
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
    Action.dose: ActionInfo("take a test dose", "o", Rules.creative),
    Action.nextPreset: ActionInfo("next perception preset", "p", Rules.creative),
];

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

bool isAllowed(Action action, Rules rules) {
    return ACTIONS[action].needs == Rules.survival || rules == Rules.creative;
}

struct Bindings {
    KeyName[ACTION_COUNT] keys;

    static Bindings defaults() {
        Bindings made;
        foreach (index, info; ACTIONS) {
            made.keys[index] = KeyName.of(info.key);
        }
        return made;
    }

    Maybe!Action actionOf(const(char)[] name, Rules rules) const {
        uint index = 0;
        while (index < ACTION_COUNT && !(keys[index].length > 0 && isSameKey(keys[index].slice(), name) && isAllowed(cast(Action) index, rules))) {
            index += 1;
        }
        if (index < ACTION_COUNT) {
            return Maybe!Action.of(cast(Action) index);
        } else {
            return Maybe!Action.init;
        }
    }

    void bind(Action action, const(char)[] name) {
        foreach (index, ref key; keys) {
            if (isSameKey(key.slice(), name) && ACTIONS[index].needs == ACTIONS[action].needs) {
                key = KeyName.init;
            }
        }
        keys[action] = KeyName.of(name);
    }

    void apply(ConfigEntry entry) {
        if (entry.key.length > BINDING_PREFIX.length && entry.key[0 .. BINDING_PREFIX.length] == BINDING_PREFIX) {
            const(char)[] wanted = entry.key[BINDING_PREFIX.length .. $];
            uint index = 0;
            while (index < ACTION_COUNT && ENUM_NAMES!Action[index] != wanted) {
                index += 1;
            }
            if (index < ACTION_COUNT) {
                keys[index] = KeyName.of(entry.value);
            }
        }
    }
}

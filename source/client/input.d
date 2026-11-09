module client.input;

import base.maybe : Maybe;
import base.stdio : printed;
import client.bindings : ACTION_COUNT, Action, Bindings, KeyName, Rules, isSameKey;
import client.game : Game, Key, KeyStroke, Screen;
import common.character.controller : MovementMode;
import common.inventory : Cycle;
import plugins.api.flags : Flags;

enum string ESCAPE_KEY = "Escape";
enum size_t BUTTON_NAME_CAPACITY = 12;

enum Request : ubyte {
    nothing,
    previousWorld,
    nextWorld,
    releaseMouse,
    bindingsChanged,
}

struct KeyLabel {
    string name;
    string label;
}

immutable KeyLabel[] KEY_LABELS = [
    KeyLabel("button1", "left mouse"),
    KeyLabel("button2", "middle mouse"),
    KeyLabel("button3", "right mouse"),
    KeyLabel("button4", "wheel up"),
    KeyLabel("button5", "wheel down"),
    KeyLabel("Shift_L", "left shift"),
    KeyLabel("bracketleft", "["),
    KeyLabel("bracketright", "]"),
    KeyLabel("minus", "-"),
    KeyLabel("equal", "="),
    KeyLabel("Left", "left arrow"),
    KeyLabel("Right", "right arrow"),
    KeyLabel("Up", "up arrow"),
    KeyLabel("Down", "down arrow"),
    KeyLabel("Return", "enter"),
];

const(char)[] keyLabel(const(char)[] name) {
    size_t index = 0;
    while (index < KEY_LABELS.length && !isSameKey(KEY_LABELS[index].name, name)) {
        index += 1;
    }
    if (index < KEY_LABELS.length) {
        return KEY_LABELS[index].label;
    } else if (name.length == 0) {
        return "unbound";
    } else {
        return name;
    }
}

immutable Maybe!Key[ACTION_COUNT] HELD_KEYS = [
    Action.forward: Maybe!Key.of(Key.forward),
    Action.back: Maybe!Key.of(Key.back),
    Action.left: Maybe!Key.of(Key.left),
    Action.right: Maybe!Key.of(Key.right),
    Action.jump: Maybe!Key.of(Key.up),
    Action.sink: Maybe!Key.of(Key.down),
    Action.turnLeft: Maybe!Key.of(Key.yawLeft),
    Action.turnRight: Maybe!Key.of(Key.yawRight),
    Action.lookUp: Maybe!Key.of(Key.pitchUp),
    Action.lookDown: Maybe!Key.of(Key.pitchDown),
    Action.mine: Maybe!Key.of(Key.mine),
    Action.eat: Maybe!Key.of(Key.eat),
];

Maybe!Key heldKeyOf(Action action) {
    return HELD_KEYS[action];
}

struct Controls {
    Bindings bindings = Bindings.defaults();
    Flags!Key held;
    Maybe!Action awaiting;

    Request keyDown(ref Game game, const(char)[] name, KeyStroke press) {
        if (awaiting.exists) {
            if (!isSameKey(name, ESCAPE_KEY)) {
                bindings.bind(awaiting.value, name);
            }
            awaiting = Maybe!Action.init;
            return Request.bindingsChanged;
        } else if (isSameKey(name, ESCAPE_KEY) && game.screen != Screen.none) {
            game.closeScreen();
            return Request.nothing;
        } else if (isSameKey(name, ESCAPE_KEY)) {
            return Request.releaseMouse;
        } else {
            Maybe!Action action = bindings.actionOf(name, game.rules);
            if (!action.exists) {
                return Request.nothing;
            } else if (heldKeyOf(action.value).exists) {
                held.set(heldKeyOf(action.value).value);
                return Request.nothing;
            } else if (press == KeyStroke.first) {
                return run(game, action.value);
            } else {
                return Request.nothing;
            }
        }
    }

    void keyUp(ref Game game, const(char)[] name) {
        Maybe!Action action = bindings.actionOf(name, game.rules);
        if (action.exists && heldKeyOf(action.value).exists) {
            held.clear(heldKeyOf(action.value).value);
        }
    }

    void letGoAll() {
        held = Flags!Key.init;
    }

    Request run(ref Game game, Action action) {
        final switch (action) {
            case Action.forward:
            case Action.back:
            case Action.left:
            case Action.right:
            case Action.jump:
            case Action.sink:
            case Action.turnLeft:
            case Action.turnRight:
            case Action.lookUp:
            case Action.lookDown:
            case Action.mine:
            case Action.eat:
                return Request.nothing;
            case Action.slot1:
            case Action.slot2:
            case Action.slot3:
            case Action.slot4:
            case Action.slot5:
            case Action.slot6:
            case Action.slot7:
            case Action.slot8:
            case Action.slot9:
            case Action.slot10:
            case Action.slot11:
            case Action.slot12:
                game.inventory.select(action - Action.slot1);
                return Request.nothing;
            case Action.use:
                if (held.has(Key.down)) {
                    game.placeBlock();
                } else {
                    game.interact();
                }
                return Request.nothing;
            case Action.inventory:
                game.toggleCharacter();
                return Request.nothing;
            case Action.previousSlot:
                game.inventory.cycle(Cycle.back);
                return Request.nothing;
            case Action.nextSlot:
                game.inventory.cycle(Cycle.ahead);
                return Request.nothing;
            case Action.fly:
                game.toggleMode(MovementMode.walk);
                return Request.nothing;
            case Action.noclip:
                game.toggleMode(MovementMode.noclip);
                return Request.nothing;
            case Action.previousWorld:
                return Request.previousWorld;
            case Action.nextWorld:
                return Request.nextWorld;
            case Action.throwBlock:
                game.throwBlock();
                return Request.nothing;
            case Action.dose:
                game.doseNext();
                return Request.nothing;
            case Action.nextPreset:
                game.nextPreset();
                return Request.nothing;
        }
    }
}

const(char)[] buttonName(uint button, char[] buffer) {
    return printed(buffer, "button%u", button);
}

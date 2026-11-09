module unit.bindings;

import client.bindings : Action, Bindings, Rules;
import client.config : ClientConfig, ConfigEntry;

unittest {
    Bindings bindings = Bindings.defaults();
    assert(bindings.actionOf("w", Rules.survival).value == Action.forward);
    assert(bindings.actionOf("W", Rules.survival).value == Action.forward);
    assert(!bindings.actionOf("n", Rules.survival).exists);
    assert(bindings.actionOf("n", Rules.creative).value == Action.noclip);
    bindings.bind(Action.jump, "w");
    assert(bindings.actionOf("w", Rules.survival).value == Action.jump);
    assert(bindings.keys[Action.forward].length == 0);
}

unittest {
    ClientConfig config = ClientConfig.fromText("bind_inventory = i\nbind_unknown = q\nreach = 0.75\n");
    assert(config.bindings.actionOf("i", Rules.survival).value == Action.inventory);
    assert(config.reach.value == 0.75f);
    assert(ConfigEntry.fromLine("# bind_jump = x").key.length == 0);
}

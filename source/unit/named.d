module unit.named;

import common.items : Item, itemNamed;
import plugins.api.api : Material;

Item named(const(char)[] name) {
    return itemNamed(name).value;
}

Material blockNamed(const(char)[] name) {
    return named(name).block;
}

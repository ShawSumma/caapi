module plugins.buildings.types;

import plugins.buildings.building : Lots, Palette, Spec;
import brownstone = plugins.buildings.brownstone;
import civic = plugins.buildings.civic;
import deco = plugins.buildings.deco;
import glass = plugins.buildings.glass;
import modern = plugins.buildings.modern;
import rowhouse = plugins.buildings.rowhouse;
import tenement = plugins.buildings.tenement;
import warehouse = plugins.buildings.warehouse;

enum Type : ubyte {
    brownstone,
    civic,
    deco,
    glass,
    modern,
    rowhouse,
    tenement,
    warehouse,
}

int[2] stories(Type type) {
    final switch (type) {
        case Type.brownstone:
            return brownstone.STORIES;
        case Type.civic:
            return civic.STORIES;
        case Type.deco:
            return deco.STORIES;
        case Type.glass:
            return glass.STORIES;
        case Type.modern:
            return modern.STORIES;
        case Type.rowhouse:
            return rowhouse.STORIES;
        case Type.tenement:
            return tenement.STORIES;
        case Type.warehouse:
            return warehouse.STORIES;
    }
}

immutable(Palette)[] palettes(Type type) {
    final switch (type) {
        case Type.brownstone:
            return brownstone.PALETTES[];
        case Type.civic:
            return civic.PALETTES[];
        case Type.deco:
            return deco.PALETTES[];
        case Type.glass:
            return glass.PALETTES[];
        case Type.modern:
            return modern.PALETTES[];
        case Type.rowhouse:
            return rowhouse.PALETTES[];
        case Type.tenement:
            return tenement.PALETTES[];
        case Type.warehouse:
            return warehouse.PALETTES[];
    }
}

void build(Type type, ref const Lots lots, Spec spec) {
    final switch (type) {
        case Type.brownstone:
            brownstone.build(lots, spec);
            break;
        case Type.civic:
            civic.build(lots, spec);
            break;
        case Type.deco:
            deco.build(lots, spec);
            break;
        case Type.glass:
            glass.build(lots, spec);
            break;
        case Type.modern:
            modern.build(lots, spec);
            break;
        case Type.rowhouse:
            rowhouse.build(lots, spec);
            break;
        case Type.tenement:
            tenement.build(lots, spec);
            break;
        case Type.warehouse:
            warehouse.build(lots, spec);
            break;
    }
}

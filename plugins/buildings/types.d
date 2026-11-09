module plugins.buildings.types;

import plugins.api.binding : bound;
import plugins.api.content : Content;
import plugins.buildings.building : Form, Lots, Materials, Spec, Traits, materials;
import brownstone = plugins.buildings.brownstone;
import civic = plugins.buildings.civic;
import deco = plugins.buildings.deco;
import glass = plugins.buildings.glass;
import modern = plugins.buildings.modern;
import rowhouse = plugins.buildings.rowhouse;
import tenement = plugins.buildings.tenement;
import warehouse = plugins.buildings.warehouse;

void resolveBuildings(const(Content)* content) {
    materials = content.bound!Materials("buildings:materials");
}

void build(ref const Traits traits, ref const Lots lots, Spec spec) {
    final switch (traits.form) {
        case Form.brownstone:
            brownstone.build(lots, spec, traits);
            break;
        case Form.civic:
            civic.build(lots, spec, traits);
            break;
        case Form.deco:
            deco.build(lots, spec, traits);
            break;
        case Form.glass:
            glass.build(lots, spec, traits);
            break;
        case Form.modern:
            modern.build(lots, spec, traits);
            break;
        case Form.rowhouse:
            rowhouse.build(lots, spec, traits);
            break;
        case Form.tenement:
            tenement.build(lots, spec, traits);
            break;
        case Form.warehouse:
            warehouse.build(lots, spec, traits);
            break;
    }
}

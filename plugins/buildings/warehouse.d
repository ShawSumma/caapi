module plugins.buildings.warehouse;

import plugins.api.api : Rhythm;
import plugins.buildings.building : Lots, Parts, STORY, Spec, Traits, banded, chimney, crown, enter, makeParts, pick, roof, shell, tiers, waterTower;

enum Rhythm HIGH_ROWS = Rhythm(STORY, 2, 1);

void build(ref const Lots lots, Spec spec, ref const Traits traits) {
    Parts parts;
    makeParts(parts, lots, spec);
    foreach (ref part; parts.slice()) {
        foreach (tier; tiers(part, spec, 0).slice()) {
            banded(part, shell(part, spec.palette, tier), tier, HIGH_ROWS);
            if (tier.isRoofed()) {
                roof(part, spec.palette, traits.roof, tier);
            }
        }
    }
    enter(parts, spec);
    uint choice = pick(parts, 3);
    if (choice == 0) {
        crown(parts, spec.palette, &chimney);
    } else if (choice == 1) {
        crown(parts, spec.palette, &waterTower);
    }
}

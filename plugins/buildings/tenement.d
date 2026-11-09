module plugins.buildings.tenement;

import plugins.buildings.building : Lots, Parts, Spec, Traits, chimney, crown, enter, makeParts, masonry, pick, roof, shell, storefront, tiers, waterTower;

void build(ref const Lots lots, Spec spec, ref const Traits traits) {
    Parts parts;
    makeParts(parts, lots, spec);
    foreach (ref part; parts.slice()) {
        foreach (tier; tiers(part, spec, 0).slice()) {
            masonry(part, spec.palette, shell(part, spec.palette, tier), tier);
            if (tier.isRoofed()) {
                roof(part, spec.palette, traits.roof, tier);
            }
        }
        storefront(part);
    }
    enter(parts, spec);
    uint choice = pick(parts, 3);
    if (choice < 2) {
        crown(parts, spec.palette, &waterTower);
    } else {
        crown(parts, spec.palette, &chimney);
    }
}

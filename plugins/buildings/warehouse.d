module plugins.buildings.warehouse;

import plugins.api.api : Material, Rhythm;
import plugins.buildings.building : Lots, Palette, Parts, STORY, Spec, banded, chimney, crown, enter, makeParts, pick, roof, shell, tiers, waterTower;

enum int[2] STORIES = [2, 4];
enum Material ROOF = Material.basalt;
enum Rhythm HIGH_ROWS = Rhythm(STORY, 2, 1);

immutable Palette[4] PALETTES = [
    Palette(Material.redSandstone, Material.greyBrick, Material.concrete),
    Palette(Material.greyBrick, Material.steel, Material.concrete),
    Palette(Material.concrete, Material.steel, Material.concrete),
    Palette(Material.clay, Material.basalt, Material.woodPlanks),
];

void build(ref const Lots lots, Spec spec) {
    Parts parts;
    makeParts(parts, lots, spec);
    foreach (ref part; parts.slice()) {
        foreach (tier; tiers(part, spec, 0).slice()) {
            banded(part, shell(part, spec.palette, tier), tier, HIGH_ROWS);
            if (tier.isRoofed) {
                roof(part, spec.palette, ROOF, tier);
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

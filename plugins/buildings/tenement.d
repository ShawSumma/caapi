module plugins.buildings.tenement;

import plugins.api.api : Material;
import plugins.buildings.building : Lots, Palette, Parts, Spec, chimney, crown, enter, makeParts, masonry, pick, roof, shell, storefront, tiers, waterTower;

enum int[2] STORIES = [5, 9];
enum Material ROOF = Material.basalt;

immutable Palette[5] PALETTES = [
    Palette(Material.greyBrick, Material.whiteBrick, Material.woodPlanks),
    Palette(Material.whiteBrick, Material.greyBrick, Material.woodPlanks),
    Palette(Material.redSandstone, Material.whiteBrick, Material.woodPlanks),
    Palette(Material.clay, Material.limestone, Material.woodPlanks),
    Palette(Material.andesite, Material.sandstone, Material.woodPlanks),
];

void build(ref const Lots lots, Spec spec) {
    Parts parts;
    makeParts(parts, lots, spec);
    foreach (ref part; parts.slice()) {
        foreach (tier; tiers(part, spec, 0).slice()) {
            masonry(part, spec.palette, shell(part, spec.palette, tier), tier);
            if (tier.isRoofed) {
                roof(part, spec.palette, ROOF, tier);
            }
        }
        storefront(part);
    }
    enter(parts, spec);
    if (pick(parts, 3) < 2) {
        crown(parts, spec.palette, &waterTower);
    } else {
        crown(parts, spec.palette, &chimney);
    }
}

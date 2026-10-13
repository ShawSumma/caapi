module plugins.buildings.brownstone;

import plugins.api.api : Material;
import plugins.buildings.building : Lots, Palette, Parts, Spec, chimney, crown, enter, makeParts, masonry, pick, roof, shell, tiers;

enum int[2] STORIES = [4, 5];
enum Material ROOF = Material.slate;

immutable Palette[5] PALETTES = [
    Palette(Material.redSandstone, Material.sandstone, Material.woodPlanks),
    Palette(Material.redSandstone, Material.limestone, Material.woodPlanks),
    Palette(Material.shale, Material.limestone, Material.woodPlanks),
    Palette(Material.clay, Material.sandstone, Material.woodPlanks),
    Palette(Material.spruceWood, Material.diorite, Material.woodPlanks),
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
    }
    enter(parts, spec);
    if (pick(parts, 2) == 0) {
        crown(parts, spec.palette, &chimney);
    }
}

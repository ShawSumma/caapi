module plugins.buildings.rowhouse;

import plugins.api.api : Box, Material;
import plugins.buildings.building : Lots, Palette, Part, Parts, Spec, Split, Tier, chimney, crown, enter, footprint, isEmpty, makeParts, pick, punched, roof, shell, tiers;

enum int[2] STORIES = [2, 3];
enum Material ROOF = Material.woodPlanks;
enum int PIER_SPACING = 2;

immutable Palette[5] PALETTES = [
    Palette(Material.whiteBrick, Material.spruceWood, Material.woodPlanks, Material.none, Material.slate),
    Palette(Material.woodPlanks, Material.whiteBrick, Material.woodPlanks, Material.none, Material.redSandstone),
    Palette(Material.birchWood, Material.spruceWood, Material.woodPlanks, Material.none, Material.shale),
    Palette(Material.sandstone, Material.clay, Material.woodPlanks, Material.none, Material.clay),
    Palette(Material.limestone, Material.greyBrick, Material.woodPlanks, Material.none, Material.slate),
];

void hipRoof(ref const Part part, Palette palette, Tier tier) {
    int rise = 1;
    Box box = footprint(part, tier.shrink + rise, Split.above, tier.high + rise, tier.high + rise);
    while (!isEmpty(box)) {
        part.tower.paint(palette.roof, box);
        rise += 1;
        box = footprint(part, tier.shrink + rise, Split.above, tier.high + rise, tier.high + rise);
    }
}

void build(ref const Lots lots, Spec spec) {
    Parts parts;
    makeParts(parts, lots, spec);
    foreach (ref part; parts.slice()) {
        foreach (tier; tiers(part, spec, 0).slice()) {
            punched(part, spec.palette, shell(part, spec.palette, tier), tier, PIER_SPACING);
            if (tier.isRoofed()) {
                roof(part, spec.palette, ROOF, tier);
            }
        }
        hipRoof(part, spec.palette, part.top);
    }
    enter(parts, spec);
    if (pick(parts, 3) < 2) {
        crown(parts, spec.palette, &chimney);
    }
}

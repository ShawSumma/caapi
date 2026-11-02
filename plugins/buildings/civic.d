module plugins.buildings.civic;

import core.stdc.math : floor, sqrt;
import plugins.api.api : Box, Material;
import plugins.buildings.building : Bound, Lots, Palette, Part, Parts, SIDES, STORY, Spec, Split, Tier, along, crown, enter, faceOf, footprint, makeParts, masonry, middle, movedOut, narrowestOf, pick, pyramid, roof, setbacks, shell, strips, tiers, withAlong;
import plugins.turtle.turtle : boxOf, floorDiv;

enum int[2] STORIES = [3, 6];
enum int SETBACKS = 1;
enum Material ROOF = Material.slate;
enum int COLUMN_SPACING = 3;

immutable Palette[4] PALETTES = [
    Palette(Material.marble, Material.limestone, Material.marble, Material.none, Material.slate),
    Palette(Material.limestone, Material.marble, Material.marble, Material.none, Material.steel),
    Palette(Material.sandstone, Material.limestone, Material.woodPlanks, Material.none, Material.clay),
    Palette(Material.granite, Material.marble, Material.marble, Material.none, Material.slate),
];

void arcade(ref const Part part, Palette palette) {
    Box box = footprint(part, 0, Split.below, 1, STORY - 1);
    foreach (side; SIDES) {
        if (part.kinds[side] == Bound.street) {
            Box face = faceOf(box, side);
            part.tower.paint(Material.none, face);
            foreach (column; strips(face, COLUMN_SPACING).slice()) {
                part.tower.paint(palette.trim, column);
            }
            Box behind = movedOut(face, side, -1);
            int[2] run = along(behind, side);
            part.tower.paint(Material.glass, withAlong(behind, side, [run[0] + 1, run[1] - 1]));
        }
    }
}

void dome(ref const Part part, Palette palette, Tier tier) {
    Box roofBox = footprint(part, tier.shrink + 1, Split.above, tier.high, tier.high);
    int reach = floorDiv(narrowestOf(roofBox) - 1, 2);
    int x = middle(roofBox.low[0], roofBox.high[0]);
    int y = middle(roofBox.low[1], roofBox.high[1]);
    foreach (level; 0 .. reach + 1) {
        int spread = cast(int) floor(sqrt(cast(double)(reach * reach - level * level)) + 0.5);
        int z = tier.high + level + 1;
        part.tower.paint(palette.roof, boxOf([x - spread, x + spread], [y - spread, y + spread], [z, z]));
    }
}

void build(ref const Lots lots, Spec spec) {
    Parts parts;
    makeParts(parts, lots, spec);
    int chosen = setbacks(parts, SETBACKS);
    foreach (ref part; parts.slice()) {
        foreach (tier; tiers(part, spec, chosen).slice()) {
            masonry(part, spec.palette, shell(part, spec.palette, tier), tier);
            if (tier.isRoofed()) {
                roof(part, spec.palette, ROOF, tier);
            }
        }
        arcade(part, spec.palette);
    }
    enter(parts, spec);
    if (pick(parts, 3) < 2) {
        crown(parts, spec.palette, &dome);
    } else {
        crown(parts, spec.palette, &pyramid);
    }
}

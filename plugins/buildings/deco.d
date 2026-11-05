module plugins.buildings.deco;

import plugins.api.api : Box, Material, Span;
import plugins.buildings.building : Lots, Palette, Part, Parts, Spec, Split, Tier, crown, enter, footprint, makeParts, masonry, middle, pick, pyramid, roof, setbacks, shell, storefront, tiers, xSpan, ySpan;
import plugins.turtle.turtle : boxOf;

enum Span STORIES = Span(14, 34);
enum int SETBACKS = 2;
enum Material ROOF = Material.slate;
enum int SPIRE = 10;

immutable Palette[5] PALETTES = [
    Palette(Material.limestone, Material.steel, Material.concrete),
    Palette(Material.sandstone, Material.marble, Material.concrete),
    Palette(Material.whiteBrick, Material.steel, Material.concrete),
    Palette(Material.diorite, Material.granite, Material.concrete),
    Palette(Material.dolomite, Material.slate, Material.concrete),
];

void spire(ref const Part part, Palette palette, Tier tier) {
    Box roofBox = footprint(part, tier.shrink, Split.above, tier.high, tier.high);
    int x = middle(xSpan(roofBox));
    int y = middle(ySpan(roofBox));
    part.tower.paint(palette.trim, boxOf(Span(x - 1, x + 1), Span(y - 1, y + 1), Span(tier.high + 1, tier.high + 2)));
    part.tower.paint(palette.trim, boxOf(Span(x, x), Span(y, y), Span(tier.high + 3, tier.high + SPIRE)));
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
        storefront(part);
    }
    enter(parts, spec);
    uint choice = pick(parts, 3);
    if (choice < 2) {
        crown(parts, spec.palette, &spire);
    } else {
        crown(parts, spec.palette, &pyramid);
    }
}

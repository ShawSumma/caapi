module client.graphics.voxels.textures;

import core.stdc.math : floorf;
import core.stdc.stdlib : free, malloc;
import base.numbers : clamped, higherOf;
import base.splitmix : SplitMix;
import client.meshing : WINDOWS_PER_SIDE;
import common.material : MATERIAL_COLORS;
import plugins.api.api : Material;

enum uint TEXELS_PER_WINDOW = 16;
enum uint TEXTURE_SIZE = WINDOWS_PER_SIDE * TEXELS_PER_WINDOW;
enum uint TEXTURE_MIPS = 9;
enum uint TEXTURE_LAYERS = Material.max;
enum uint TEXEL_BYTES = 4;
enum uint COLOR_CHANNELS = 3;
enum ubyte TEXTURE_OPAQUE = 255;
enum ubyte TEXTURE_CLEAR = 0;
enum float CHANNEL_MOST = 255;
enum uint CORNERS_PER_TEXEL = 4;
enum ulong OCTAVE_SALT = 0x9E3779B97F4A7C15;
enum uint LAYER_SHIFT = 37;

struct Octave {
    uint cell;
    float weight;
}

immutable Octave[4] OCTAVES = [
    Octave(1, 0.2f),
    Octave(2, 0.25f),
    Octave(8, 0.3f),
    Octave(32, 0.25f),
];

immutable float[Material.max + 1] GRAIN = [
    Material.none: 0,
    Material.dirt: 0.13f,
    Material.sand: 0.05f,
    Material.redSand: 0.06f,
    Material.silt: 0.08f,
    Material.clay: 0.08f,
    Material.mud: 0.1f,
    Material.sandyLoam: 0.1f,
    Material.siltyLoam: 0.1f,
    Material.clayLoam: 0.1f,
    Material.gravel: 0.22f,
    Material.grass: 0.12f,
    Material.lushGrass: 0.12f,
    Material.coarseGrass: 0.14f,
    Material.tanGrass: 0.12f,
    Material.mudGrass: 0.12f,
    Material.caveGrass: 0.12f,
    Material.snow: 0.02f,
    Material.ice: 0.03f,
    Material.iceSlush: 0.04f,
    Material.limestone: 0.08f,
    Material.dolomite: 0.08f,
    Material.shale: 0.1f,
    Material.slate: 0.1f,
    Material.sandstone: 0.08f,
    Material.redSandstone: 0.09f,
    Material.marble: 0.04f,
    Material.granite: 0.14f,
    Material.diorite: 0.14f,
    Material.andesite: 0.1f,
    Material.gabbro: 0.14f,
    Material.basalt: 0.1f,
    Material.olivine: 0.14f,
    Material.water: 0.04f,
    Material.lava: 0.3f,
    Material.oakWood: 0.1f,
    Material.oakLeaves: 0.1f,
    Material.birchWood: 0.05f,
    Material.birchLeaves: 0.1f,
    Material.spruceWood: 0.1f,
    Material.spruceLeaves: 0.1f,
    Material.woodPlanks: 0.07f,
    Material.greyBrick: 0.07f,
    Material.whiteBrick: 0.05f,
    Material.concrete: 0.05f,
    Material.steel: 0.03f,
    Material.glass: 0,
    Material.jungleWood: 0.1f,
    Material.jungleLeaves: 0.1f,
    Material.acaciaWood: 0.1f,
    Material.acaciaLeaves: 0.1f,
    Material.cherryLeaves: 0.08f,
    Material.mapleLeaves: 0.1f,
    Material.willowLeaves: 0.1f,
    Material.cactus: 0.08f,
    Material.wallpaper: 0.025f,
    Material.stainedWallpaper: 0.05f,
    Material.carpet: 0.07f,
    Material.dampCarpet: 0.09f,
    Material.ceilingTile: 0.02f,
    Material.lightPanel: 0,
    Material.redCarpet: 0.07f,
    Material.sunlight: 0,
    Material.plaster: 0.025f,
    Material.wetConcrete: 0.07f,
];

float latticeAt(ulong salt, uint u, uint v) {
    return 2 * SplitMix(salt ^ (cast(ulong) u << 20) ^ v).roll() - 1;
}

float smoothed(float share) {
    return share * share * (3 - 2 * share);
}

float octaveAt(ulong salt, uint cell, uint u, uint v) {
    uint side = TEXTURE_SIZE / cell;
    uint lowU = u / cell;
    uint lowV = v / cell;
    uint highU = (lowU + 1) % side;
    uint highV = (lowV + 1) % side;
    float acrossU = smoothed((u % cell) / cast(float) cell);
    float acrossV = smoothed((v % cell) / cast(float) cell);
    float near = latticeAt(salt, lowU, lowV) * (1 - acrossU) + latticeAt(salt, highU, lowV) * acrossU;
    float far = latticeAt(salt, lowU, highV) * (1 - acrossU) + latticeAt(salt, highU, highV) * acrossU;
    return near * (1 - acrossV) + far * acrossV;
}

float[] makeNoise() {
    float[] noise = (cast(float*) malloc(TEXTURE_SIZE * TEXTURE_SIZE * float.sizeof))[0 .. TEXTURE_SIZE * TEXTURE_SIZE];
    foreach (v; 0 .. TEXTURE_SIZE) {
        foreach (u; 0 .. TEXTURE_SIZE) {
            float sum = 0;
            foreach (index, octave; OCTAVES) {
                sum += octave.weight * octaveAt(OCTAVE_SALT * (index + 1), octave.cell, u, v);
            }
            noise[v * TEXTURE_SIZE + u] = sum;
        }
    }
    return noise;
}

bool insideFrame(uint u, uint v) {
    return u >= TEXELS_PER_WINDOW && v >= TEXELS_PER_WINDOW && u < TEXTURE_SIZE - TEXELS_PER_WINDOW && v < TEXTURE_SIZE - TEXELS_PER_WINDOW;
}

size_t mipBytes(uint mip) {
    size_t side = TEXTURE_SIZE >> mip;
    return side * side * TEXEL_BYTES * TEXTURE_LAYERS;
}

size_t mipOffset(uint mip) {
    size_t offset = 0;
    foreach (level; 0 .. mip) {
        offset += mipBytes(level);
    }
    return offset;
}

size_t textureBytes() {
    return mipOffset(TEXTURE_MIPS);
}

ubyte shaded(ubyte channel, float shade) {
    return cast(ubyte) clamped(floorf(channel * shade + 0.5f), 0.0f, CHANNEL_MOST);
}

void fillFirstMip(ubyte[] pixels) {
    float[] noise = makeNoise();
    size_t at = 0;
    foreach (layer; 0 .. TEXTURE_LAYERS) {
        Material material = cast(Material)(layer + 1);
        float grain = GRAIN[material];
        uint shift = layer * LAYER_SHIFT;
        foreach (v; 0 .. TEXTURE_SIZE) {
            foreach (u; 0 .. TEXTURE_SIZE) {
                float shade = 1 + grain * noise[((v + shift) % TEXTURE_SIZE) * TEXTURE_SIZE + (u + shift) % TEXTURE_SIZE];
                pixels[at] = shaded(MATERIAL_COLORS[material].red, shade);
                pixels[at + 1] = shaded(MATERIAL_COLORS[material].green, shade);
                pixels[at + 2] = shaded(MATERIAL_COLORS[material].blue, shade);
                pixels[at + COLOR_CHANNELS] = TEXTURE_OPAQUE;
                if (material == Material.glass && insideFrame(u, v)) {
                    pixels[at + COLOR_CHANNELS] = TEXTURE_CLEAR;
                }
                at += TEXEL_BYTES;
            }
        }
    }
    free(noise.ptr);
}

void downsample(const(ubyte)[] from, ubyte[] to, uint side) {
    foreach (layer; 0 .. TEXTURE_LAYERS) {
        foreach (y; 0 .. side / 2) {
            foreach (x; 0 .. side / 2) {
                uint[COLOR_CHANNELS] sum = 0;
                uint opaque = 0;
                ubyte alpha = TEXTURE_CLEAR;
                foreach (corner; 0 .. CORNERS_PER_TEXEL) {
                    size_t source = (layer * side * side + (y * 2 + corner / 2) * side + x * 2 + corner % 2) * TEXEL_BYTES;
                    if (from[source + COLOR_CHANNELS] != TEXTURE_CLEAR) {
                        foreach (channel; 0 .. COLOR_CHANNELS) {
                            sum[channel] += from[source + channel];
                        }
                        opaque += 1;
                    }
                    alpha = higherOf(alpha, from[source + COLOR_CHANNELS]);
                }
                size_t target = (layer * (side / 2) * (side / 2) + y * (side / 2) + x) * TEXEL_BYTES;
                foreach (channel; 0 .. COLOR_CHANNELS) {
                    to[target + channel] = cast(ubyte)(sum[channel] / higherOf(opaque, 1u));
                }
                to[target + COLOR_CHANNELS] = alpha;
            }
        }
    }
}

ubyte[] makeTexturePixels() {
    ubyte[] pixels = (cast(ubyte*) malloc(textureBytes()))[0 .. textureBytes()];
    fillFirstMip(pixels);
    foreach (mip; 1 .. TEXTURE_MIPS) {
        downsample(pixels[mipOffset(mip - 1) .. mipOffset(mip)], pixels[mipOffset(mip) .. mipOffset(mip) + mipBytes(mip)], TEXTURE_SIZE >> (mip - 1));
    }
    return pixels;
}

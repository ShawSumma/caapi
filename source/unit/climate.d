module unit.climate;

import base.maybe : Maybe;
import common.worldgen.climate : BROAD_RELIEF, Climate, CubeClimate, HEAT, NodeClimate, SOIL_DEPTH, boundOf, groundAt, uniformRock;
import plugins.api.api : Material;

enum uint SAMPLES = 50;
enum uint GENERATIONS = 2000;
enum float TOLERANCE = 1e-4f;

unittest {
    NodeClimate[8] around;
    foreach (index; 0 .. 8) {
        around[index] = NodeClimate.fromParents(around[0 .. index], index * 977);
    }
    CubeClimate cube = CubeClimate.fromAround(around);
    assert(cube.corners[7].relief == around[0].climate().relief);
    foreach (sample; 0 .. SAMPLES) {
        float t = cast(float) sample / SAMPLES;
        Climate inside = cube.at([t, 1 - t, t * t]);
        assert(inside.relief >= cube.lowest.relief - TOLERANCE && inside.relief <= cube.highest.relief + TOLERANCE);
        Maybe!Material rock = uniformRock(SOIL_DEPTH + t * 4, SOIL_DEPTH + t * 4, inside, inside);
        assert(rock.exists && rock.value == groundAt(SOIL_DEPTH + t * 4, SOIL_DEPTH, inside));
    }
    NodeClimate walked;
    foreach (generation; 0 .. GENERATIONS) {
        NodeClimate[1] parent = [walked];
        walked = NodeClimate.fromParents(parent[], generation * 0x9E37);
        assert(walked.broad <= boundOf(BROAD_RELIEF) && walked.broad >= -boundOf(BROAD_RELIEF));
        assert(walked.heat <= boundOf(HEAT) && walked.heat >= -boundOf(HEAT));
    }
}

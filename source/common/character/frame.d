module common.character.frame;

import core.stdc.math : floorf;
import common.dodeca : VERTEX_COUNT, Vertex, nodeToDual;
import common.graph : Graph;
import common.math : MIsometry, MPoint, MVector;
import common.node : ChunkLayout;
import common.position : Position;
import common.vector3 : dot, magnitude, scaled;

enum UpMode : ubyte {
    world,
    grid,
    camera,
}

struct BlockAt {
    float[3] faceUp = [0, 0, 0];
    bool isFound;

    static BlockAt find(ref const Graph graph, Position position, float[3] worldUp, float soleDepth) {
        BlockAt found;
        MPoint!float point = (position.local * MIsometry!float.fromDisplacement(worldUp.scaled(-soleDepth))) * MPoint!float.origin();
        uint vertex = 0;
        while (vertex < VERTEX_COUNT && !found.isFound) {
            found = BlockAt.inChunk(graph.layout, cast(Vertex) vertex, position, point, worldUp);
            vertex += 1;
        }
        return found;
    }

    static BlockAt inChunk(ref const ChunkLayout layout, Vertex vertex, Position position, MPoint!float point, float[3] worldUp) {
        MVector!float dual = vertex.nodeToDual * point.vec;
        float[3] klein = [dual.data[0] / dual.data[3], dual.data[1] / dual.data[3], dual.data[2] / dual.data[3]];
        float[3] grid = [layout.dualToGrid(klein[0]), layout.dualToGrid(klein[1]), layout.dualToGrid(klein[2])];
        if (!isInsideGrid(grid, layout.dimension)) {
            return BlockAt.init;
        } else {
            MIsometry!float dualToBody = (vertex.nodeToDual * position.local).inverse();
            float[3] best = faceNormal(dualToBody, klein, 0);
            foreach (candidate; 1 .. 3) {
                float[3] normal = faceNormal(dualToBody, klein, candidate);
                if (absolute(normal.dot(worldUp)) > absolute(best.dot(worldUp))) {
                    best = normal;
                }
            }
            float[3] up = best;
            if (best.dot(worldUp) < 0) {
                up = best.scaled(-1);
            }
            return BlockAt(up, true);
        }
    }
}

bool isInsideGrid(float[3] grid, ubyte dimension) {
    return grid[0] >= 0 && grid[0] < dimension && grid[1] >= 0 && grid[1] < dimension && grid[2] >= 0 && grid[2] < dimension;
}

float absolute(float value) {
    if (value < 0) {
        return -value;
    } else {
        return value;
    }
}

float[3] faceNormal(MIsometry!float dualToBody, float[3] klein, size_t axis) {
    float[4] normal = [0, 0, 0, 0];
    normal[axis] = 1;
    normal[3] = klein[axis];
    float[3] spatial = (dualToBody * MVector!float(normal).normalizedDirection().vec).xyz();
    return spatial.scaled(1.0f / spatial.magnitude);
}

struct BodyFrame {
    float[3] gravityUp;
    float[3] viewUp;

    static BodyFrame make(ref const Graph graph, Position position, float[3] worldUp, float soleDepth, UpMode upMode) {
        BlockAt block = BlockAt.find(graph, position, worldUp, soleDepth);
        float[3] gravityUp = worldUp;
        float[3] viewUp = worldUp;
        if (block.isFound) {
            final switch (upMode) {
                case UpMode.world:
                    break;
                case UpMode.grid:
                    gravityUp = block.faceUp;
                    viewUp = block.faceUp;
                    break;
                case UpMode.camera:
                    viewUp = block.faceUp;
                    break;
            }
        }
        return BodyFrame(gravityUp, viewUp);
    }
}

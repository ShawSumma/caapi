module common.character.warp;

import core.stdc.math : fabsf, fmaxf, fminf, powf, sqrtf;
import common.dodeca : SIDE_COUNT, Side, VERTEX_COUNT, Vertex, chunkToNode, nodeToDual, reflection;
import common.graph : Graph, ROOT_NODE;
import common.math : MIsometry, MPoint, MVector, clamped;
import common.node : ChunkLayout;
import common.position : Position;
import common.settings : metersToAbsoluteFor;
import common.worldgen.generation : Worldgen;

enum float GRID_SLOPE_STEP = 1e-4f;
enum uint POLAR_ITERATIONS = 8;
enum float WARP_BLEND_CELLS = 3.0f;
enum uint BLEND_FRAME_CAPACITY = VERTEX_COUNT * (SIDE_COUNT + 1);
enum float PERMUTATION_SNAP_EXPONENT = 8.0f;
enum float TEST_TOLERANCE = 1e-4f;
enum float TEST_CUBE_TOLERANCE = 0.1f;
enum ubyte TEST_DIMENSION = 12;

enum float TEST_STEP_METERS = 0.01f;
enum uint TEST_STEPS = 3000;
enum float TEST_MAX_JUMP = 0.01f;
enum float TEST_CLEAR_AXIS_RATIO = 0.8f;

immutable float[3][3] TEST_DIRECTIONS = [
    [0.6f, 0.0f, 0.8f],
    [0.0f, 0.8f, 0.6f],
    [0.48f, 0.6f, 0.64f],
];

immutable int[3][3] TEST_CELLS = [
    [1, 1, 1],
    [5, 6, 7],
    [10, 10, 10],
];

enum float[3][3] IDENTITY_WARP = [
    [1, 0, 0],
    [0, 1, 0],
    [0, 0, 1],
];

float[3][3] blockWarp(ref const Graph graph, Position position, float metersToAbsolute) {
    Vertex deepest = deepestVertex(graph.layout, position.local * MPoint!float.origin());
    return stretchOf(scaled(gridJacobian(graph.layout, deepest.nodeToDual * position.local), metersToAbsolute));
}

Vertex deepestVertex(ref const ChunkLayout layout, MPoint!float point) {
    Vertex deepest = Vertex.init;
    float deepestMargin = -float.infinity;
    foreach (vertexIndex; 0 .. VERTEX_COUNT) {
        float margin = gridMargin(layout, (cast(Vertex) vertexIndex).nodeToDual * point.vec);
        if (margin > deepestMargin) {
            deepestMargin = margin;
            deepest = cast(Vertex) vertexIndex;
        }
    }
    return deepest;
}

float gridMargin(ref const ChunkLayout layout, MVector!float dual) {
    float margin = float.infinity;
    foreach (axis; 0 .. 3) {
        float grid = layout.dualToGrid(dual.data[axis] / dual.data[3]);
        margin = fminf(margin, fminf(grid, layout.dimension - grid));
    }
    return margin;
}

struct BlendFrame {
    MIsometry!float toDual;
    float weight;
}

struct BlendFrames {
    BlendFrame[BLEND_FRAME_CAPACITY] frames;
    float totalWeight = 0;
    uint count;

    static BlendFrames around(ref const ChunkLayout layout, MIsometry!float local) {
        BlendFrames blend;
        foreach (vertexIndex; 0 .. VERTEX_COUNT) {
            MIsometry!float toDual = (cast(Vertex) vertexIndex).nodeToDual;
            blend.add(layout, toDual * local);
            foreach (sideIndex; 0 .. SIDE_COUNT) {
                blend.add(layout, toDual * (cast(Side) sideIndex).reflection * local);
            }
        }
        return blend;
    }

    void add(ref const ChunkLayout layout, MIsometry!float toDual) {
        float weight = blendWeight(gridMargin(layout, (toDual * MPoint!float.origin()).vec));
        if (weight > 0) {
            frames[count] = BlendFrame(toDual, weight);
            count += 1;
            totalWeight += weight;
        }
    }

    const(BlendFrame)[] slice() const return {
        return frames[0 .. count];
    }
}

float[3][3] smoothWarp(ref const Graph graph, Position position, float metersToAbsolute) {
    BlendFrames blend = BlendFrames.around(graph.layout, position.local);
    float[3][3] sum = 0;
    foreach (frame; blend.slice()) {
        float[3][3] warp = stretchOf(scaled(gridJacobian(graph.layout, frame.toDual), metersToAbsolute));
        foreach (row; 0 .. 3) {
            foreach (column; 0 .. 3) {
                sum[row][column] += frame.weight * warp[row][column];
            }
        }
    }
    return scaled(sum, 1.0f / blend.totalWeight);
}

float[3] smoothGridDirection(ref const Graph graph, Position position, float[3][3] jacobian, float[3] grid) {
    BlendFrames blend = BlendFrames.around(graph.layout, position.local);
    float[3][3] fromGrid = inverted(jacobian);
    float[3] sum = [0, 0, 0];
    foreach (frame; blend.slice()) {
        float[3][3] frameJacobian = gridJacobian(graph.layout, frame.toDual);
        float[3] frameGrid = applied(softPermutation(multiplied(frameJacobian, fromGrid)), grid);
        float[3] direction = applied(inverted(frameJacobian), frameGrid);
        float length = lengthOf(direction);
        foreach (axis; 0 .. 3) {
            sum[axis] += frame.weight * direction[axis] / length;
        }
    }
    float total = lengthOf(sum);
    return [sum[0] / total, sum[1] / total, sum[2] / total];
}

float[3][3] softPermutation(float[3][3] matrix) {
    float[3][3] result;
    foreach (column; 0 .. 3) {
        float[3] snapped;
        foreach (row; 0 .. 3) {
            snapped[row] = matrix[row][column] * powf(fabsf(matrix[row][column]), PERMUTATION_SNAP_EXPONENT - 1);
        }
        float length = lengthOf(snapped);
        foreach (row; 0 .. 3) {
            result[row][column] = snapped[row] / length;
        }
    }
    return result;
}

float blendWeight(float margin) {
    float t = clamped((margin + WARP_BLEND_CELLS) / (2 * WARP_BLEND_CELLS), 0.0f, 1.0f);
    return t * t * (3 - 2 * t);
}

float[3][3] gridJacobian(ref const ChunkLayout layout, MIsometry!float toDual) {
    MVector!float point = (toDual * MPoint!float.origin()).vec;
    float[3] klein = [point.data[0] / point.data[3], point.data[1] / point.data[3], point.data[2] / point.data[3]];
    float[3][3] jacobian;
    foreach (bodyAxis; 0 .. 3) {
        float[4] basis = [0, 0, 0, 0];
        basis[bodyAxis] = 1;
        MVector!float direction = toDual * MVector!float(basis);
        foreach (gridAxis; 0 .. 3) {
            float kleinRate = (direction.data[gridAxis] - klein[gridAxis] * direction.data[3]) / point.data[3];
            jacobian[gridAxis][bodyAxis] = gridSlope(layout, klein[gridAxis]) * kleinRate;
        }
    }
    return jacobian;
}

float gridSlope(ref const ChunkLayout layout, float klein) {
    return (layout.dualToGrid(klein + GRID_SLOPE_STEP) - layout.dualToGrid(klein - GRID_SLOPE_STEP)) / (2 * GRID_SLOPE_STEP);
}

float[3][3] stretchOf(float[3][3] matrix) {
    float[3][3] rotation = matrix;
    foreach (_; 0 .. POLAR_ITERATIONS) {
        float[3][3] inverseTransposed = transposed(inverted(rotation));
        foreach (row; 0 .. 3) {
            foreach (column; 0 .. 3) {
                rotation[row][column] = 0.5f * (rotation[row][column] + inverseTransposed[row][column]);
            }
        }
    }
    float[3][3] stretch = multiplied(transposed(rotation), matrix);
    float[3][3] symmetric;
    foreach (row; 0 .. 3) {
        foreach (column; 0 .. 3) {
            symmetric[row][column] = 0.5f * (stretch[row][column] + stretch[column][row]);
        }
    }
    return symmetric;
}

float[3][3] scaled(float[3][3] matrix, float factor) {
    float[3][3] result;
    foreach (row; 0 .. 3) {
        foreach (column; 0 .. 3) {
            result[row][column] = matrix[row][column] * factor;
        }
    }
    return result;
}

float[3][3] transposed(float[3][3] matrix) {
    float[3][3] result;
    foreach (row; 0 .. 3) {
        foreach (column; 0 .. 3) {
            result[row][column] = matrix[column][row];
        }
    }
    return result;
}

float[3][3] multiplied(float[3][3] a, float[3][3] b) {
    float[3][3] result;
    foreach (row; 0 .. 3) {
        foreach (column; 0 .. 3) {
            float sum = 0;
            foreach (k; 0 .. 3) {
                sum += a[row][k] * b[k][column];
            }
            result[row][column] = sum;
        }
    }
    return result;
}

float[3] applied(float[3][3] matrix, float[3] v) {
    return [
        matrix[0][0] * v[0] + matrix[0][1] * v[1] + matrix[0][2] * v[2],
        matrix[1][0] * v[0] + matrix[1][1] * v[1] + matrix[1][2] * v[2],
        matrix[2][0] * v[0] + matrix[2][1] * v[1] + matrix[2][2] * v[2],
    ];
}

float[3][3] inverted(float[3][3] m) {
    float[3][3] cofactor = [
        [m[1][1] * m[2][2] - m[1][2] * m[2][1], m[0][2] * m[2][1] - m[0][1] * m[2][2], m[0][1] * m[1][2] - m[0][2] * m[1][1]],
        [m[1][2] * m[2][0] - m[1][0] * m[2][2], m[0][0] * m[2][2] - m[0][2] * m[2][0], m[0][2] * m[1][0] - m[0][0] * m[1][2]],
        [m[1][0] * m[2][1] - m[1][1] * m[2][0], m[0][1] * m[2][0] - m[0][0] * m[2][1], m[0][0] * m[1][1] - m[0][1] * m[1][0]],
    ];
    float determinant = m[0][0] * cofactor[0][0] + m[0][1] * cofactor[1][0] + m[0][2] * cofactor[2][0];
    return scaled(cofactor, 1.0f / determinant);
}

unittest {
    Graph graph = Graph.make(TEST_DIMENSION, Worldgen.makeTerrain());
    float metersToAbsolute = metersToAbsoluteFor(TEST_DIMENSION, 1.0f);
    foreach (vertexIndex; 0 .. VERTEX_COUNT) {
        Vertex vertex = cast(Vertex) vertexIndex;
        foreach (cell; TEST_CELLS) {
            float[3] center = graph.layout.cellCenter(cell);
            Position position = Position(ROOT_NODE, MIsometry!float.fromTranslation(MPoint!float.origin(), chunkPointInNode(vertex, center)));
            float[3][3] warp = blockWarp(graph, position, metersToAbsolute);
            float[3][3] edges;
            foreach (axis; 0 .. 3) {
                float[3] low = center;
                float[3] high = center;
                low[axis] = graph.layout.gridToChunk(cell[axis]);
                high[axis] = graph.layout.gridToChunk(cell[axis] + 1);
                float[4] lowBody = (position.local.inverse() * chunkPointInNode(vertex, low)).vec.data;
                float[4] highBody = (position.local.inverse() * chunkPointInNode(vertex, high)).vec.data;
                edges[axis] = applied(warp, [highBody[0] - lowBody[0], highBody[1] - lowBody[1], highBody[2] - lowBody[2]]);
            }
            foreach (axis; 0 .. 3) {
                assert(fabsf(lengthOf(edges[axis]) / metersToAbsolute - 1) < TEST_CUBE_TOLERANCE);
                float[3] other = edges[(axis + 1) % 3];
                float cosine = (edges[axis][0] * other[0] + edges[axis][1] * other[1] + edges[axis][2] * other[2]) / (lengthOf(edges[axis]) * lengthOf(other));
                assert(fabsf(cosine) < TEST_CUBE_TOLERANCE);
            }
        }
    }
    graph.release();
}

unittest {
    Graph graph = Graph.make(TEST_DIMENSION, Worldgen.makeTerrain());
    float metersToAbsolute = metersToAbsoluteFor(TEST_DIMENSION, 1.0f);
    float step = TEST_STEP_METERS * metersToAbsolute;
    foreach (direction; TEST_DIRECTIONS) {
        Position position = Position.origin();
        float[3][3] previous = smoothWarp(graph, position, metersToAbsolute);
        foreach (_; 0 .. TEST_STEPS) {
            position = graph.normalized(Position(position.node, position.local * MIsometry!float.fromDisplacement([direction[0] * step, direction[1] * step, direction[2] * step])));
            float[3][3] current = smoothWarp(graph, position, metersToAbsolute);
            float jump = 0;
            foreach (row; 0 .. 3) {
                foreach (column; 0 .. 3) {
                    jump = fmaxf(jump, fabsf(current[row][column] - previous[row][column]));
                }
            }
            assert(jump < TEST_MAX_JUMP);
            previous = current;
        }
    }
    graph.release();
}

unittest {
    Graph graph = Graph.make(TEST_DIMENSION, Worldgen.makeTerrain());
    float metersToAbsolute = metersToAbsoluteFor(TEST_DIMENSION, 1.0f);
    float step = TEST_STEP_METERS * metersToAbsolute;
    float[3] up = [0, 1, 0];
    foreach (direction; TEST_DIRECTIONS) {
        Position position = Position.origin();
        TestUp previous = testGridUp(graph, position, up);
        foreach (_; 0 .. TEST_STEPS) {
            position = graph.normalized(Position(position.node, position.local * MIsometry!float.fromDisplacement([direction[0] * step, direction[1] * step, direction[2] * step])));
            TestUp current = testGridUp(graph, position, up);
            float[3] a = previous.direction;
            float[3] b = current.direction;
            assert(!(previous.isClear && current.isClear) || fabsf(a[0] - b[0]) + fabsf(a[1] - b[1]) + fabsf(a[2] - b[2]) < TEST_MAX_JUMP);
            previous = current;
        }
    }
    graph.release();
}

struct TestUp {
    float[3] direction;
    bool isClear;
}

TestUp testGridUp(ref const Graph graph, Position position, float[3] metricUp) {
    Vertex vertex = deepestVertex(graph.layout, position.local * MPoint!float.origin());
    float[3][3] jacobian = gridJacobian(graph.layout, vertex.nodeToDual * position.local);
    float[3] grid = applied(jacobian, metricUp);
    size_t axis = 0;
    foreach (candidate; 1 .. 3) {
        if (fabsf(grid[candidate]) > fabsf(grid[axis])) {
            axis = candidate;
        }
    }
    float runnerUp = fmaxf(fabsf(grid[(axis + 1) % 3]), fabsf(grid[(axis + 2) % 3]));
    float[3] snapped = [0, 0, 0];
    snapped[axis] = grid[axis] / fabsf(grid[axis]);
    return TestUp(smoothGridDirection(graph, position, jacobian, snapped), runnerUp < TEST_CLEAR_AXIS_RATIO * fabsf(grid[axis]));
}

MPoint!float chunkPointInNode(Vertex vertex, float[3] chunk) {
    return (vertex.chunkToNode * MVector!float([chunk[0], chunk[1], chunk[2], 1.0f])).normalizedPoint();
}

float lengthOf(float[3] v) {
    return sqrtf(v[0] * v[0] + v[1] * v[1] + v[2] * v[2]);
}

unittest {
    float[3][3] sheared = [
        [2, 1, 0],
        [0, 1, 0],
        [0, 0, 3],
    ];
    float[3][3] stretch = stretchOf(sheared);
    float[3][3] squared = multiplied(stretch, stretch);
    float[3][3] expected = multiplied(transposed(sheared), sheared);
    foreach (row; 0 .. 3) {
        foreach (column; 0 .. 3) {
            assert(squared[row][column] - expected[row][column] < TEST_TOLERANCE && expected[row][column] - squared[row][column] < TEST_TOLERANCE);
        }
    }
}

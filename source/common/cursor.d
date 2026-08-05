module common.cursor;

import common.dodeca : Side, Vertex, vertexCanonicalSides, vertexFromThreeSides, sideAdjacentTo;
import common.graph : Graph, NodeId;
import common.node : ChunkId;

// Directions for navigating the cubic dual.
enum Dir {
    Left,
    Right,
    Down,
    Up,
    Forward,
    Back,
}

Dir negateDir(Dir d) {
    final switch (d) {
        case Dir.Left:
            return Dir.Right;
        case Dir.Right:
            return Dir.Left;
        case Dir.Down:
            return Dir.Up;
        case Dir.Up:
            return Dir.Down;
        case Dir.Forward:
            return Dir.Back;
        case Dir.Back:
            return Dir.Forward;
    }
}

// Navigates the cubic dual of a graph.
struct Cursor {
    NodeId node;
    Side a;
    Side b;
    Side c;

    static Cursor fromVertex(NodeId node, Vertex vertex) {
        Side[3] sides = vertexCanonicalSides(vertex);
        return Cursor(node, sides[0], sides[1], sides[2]);
    }

    // Get the neighbour towards dir.
    Cursor step(const ref Graph graph, Dir dir) const {
        Side aPrime = getNeighborSide(a, b, c);
        Side bPrime = getNeighborSide(b, a, c);
        Side cPrime = getNeighborSide(c, b, a);

        if (aPrime == Side.init && bPrime == Side.init && cPrime == Side.init) {
            return Cursor.init;
        }

        Side[3] sides;
        Side neighborSide;
        final switch (dir) {
            case Dir.Left:
                sides = [a, b, cPrime];
                neighborSide = c;
                break;
            case Dir.Right:
                sides = [a, b, cPrime];
                neighborSide = cPrime;
                break;
            case Dir.Down:
                sides = [a, bPrime, c];
                neighborSide = b;
                break;
            case Dir.Up:
                sides = [a, bPrime, c];
                neighborSide = bPrime;
                break;
            case Dir.Forward:
                sides = [aPrime, b, c];
                neighborSide = a;
                break;
            case Dir.Back:
                sides = [aPrime, b, c];
                neighborSide = aPrime;
                break;
        }

        NodeId n = graph.neighbor(node, neighborSide);
        if (n == NodeId.init) {
            return Cursor.init;
        }
        return Cursor(n, sides[0], sides[1], sides[2]);
    }

    ChunkId canonicalize(const ref Graph graph) const {
        Vertex vertex = vertexFromThreeSides([a, b, c]);
        if (vertex == cast(Vertex) 255) {
            return ChunkId.init;
        }
        ChunkId chunk = ChunkId(node, vertex);
        Side[3] sides = vertexCanonicalSides(vertex);
        ChunkId result = chunk;
        foreach (side; sides) {
            NodeId n = graph.neighbor(result.node, side);
            if (n != NodeId.init && graph.depth(n) < graph.depth(result.node)) {
                result.node = n;
            }
        }
        return result;
    }
}

Side getNeighborSide(Side opposite, Side shared1, Side shared2) {
    foreach (sIdx; 0 .. Side.max + 1) {
        Side s = cast(Side) sIdx;
        if (s == opposite || s == shared1 || s == shared2) {
            continue;
        }
        bool adjOpposite = sideAdjacentTo(s, opposite);
        bool adjShared1 = sideAdjacentTo(s, shared1);
        bool adjShared2 = sideAdjacentTo(s, shared2);
        if (!adjOpposite && adjShared1 && adjShared2) {
            return s;
        }
    }
    return Side.init;
}

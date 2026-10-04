module common.character.sweep;

import core.math : sqrt;
import core.stdc.math : atanhf, tanhf;
import common.collision.chunk : MAX_FEATURE_SURFACES;
import common.collision.graph : Capsule, GraphCollisionHit, shapeCast;
import common.graph : Graph;
import common.math : MDirection, MIsometry, MPoint, MVector;
import common.proto : Position;
import common.ray : Ray;
import common.vector3 : ZERO_VECTOR, dot, magnitude, scaled;

enum double MIN_DISPLACEMENT_SQUARED = 1e-16;

struct Sweep {
    MIsometry!float transform;
    float[3] displacement;
    float[3][MAX_FEATURE_SURFACES] surfaces;
    float[3] normal;
    float gap;
    uint surfaceCount;
    bool hasContact;
    bool isLowestSection;

    static Sweep fromCapsule(ref const Graph graph, Capsule capsule, Position position, float[3] displacement) {
        float displacementSquared = displacement.dot(displacement);
        if (displacementSquared < MIN_DISPLACEMENT_SQUARED) {
            return Sweep.fromFreeMove(ZERO_VECTOR);
        } else {
            float distance = sqrt(displacementSquared);
            float[3] direction = displacement.scaled(1.0f / distance);
            Ray ray = Ray(MPoint!float.origin(), MDirection!float(MVector!float([direction[0], direction[1], direction[2], 0])));
            GraphCollisionHit hit = graph.shapeCast(capsule, position, ray, tanhf(distance));
            if (hit.isHit()) {
                return Sweep.fromContact(hit, direction.scaled(atanhf(hit.stopDistance)));
            } else {
                return Sweep.fromFreeMove(direction.scaled(distance));
            }
        }
    }

    static Sweep fromFreeMove(float[3] displacement) {
        return Sweep(MIsometry!float.fromDisplacement(displacement), displacement);
    }

    static Sweep fromContact(GraphCollisionHit hit, float[3] displacement) {
        MIsometry!float transform = MIsometry!float.fromDisplacement(displacement);
        MIsometry!float toContactFrame = transform.inverse();
        float[3][MAX_FEATURE_SURFACES] surfaces;
        foreach (i; 0 .. hit.surfaceCount) {
            surfaces[i] = unitDirection(toContactFrame, hit.surfaces[i]);
        }
        return Sweep(transform, displacement, surfaces, unitDirection(toContactFrame, hit.normal), hit.gap, hit.surfaceCount, true, hit.isLowestSection);
    }
}

float[3] unitDirection(MIsometry!float toContactFrame, MVector!float v) {
    float[3] direction = (toContactFrame * v).xyz();
    return direction.scaled(1.0f / direction.magnitude);
}

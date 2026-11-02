module unit.controller;

import base.vector3 : dot, magnitude;
import common.character.controller : PlaneSet, SkinRule, alongGround, clipToPlanes;
import common.character.sweep : ContactPlane;

enum float TOLERANCE = 1e-5f;

unittest {
    float[3] floorNormal = [0, 1, 0];
    float[3] wallNormal = [-1, 0, 0];
    ContactPlane[2] planes = [
        ContactPlane(floorNormal, 0),
        ContactPlane(wallNormal, 0),
    ];
    float[3] intoCorner = [1, -0.5f, 1];
    float[3] clipped = clipToPlanes(planes, intoCorner, SkinRule.restore);
    assert(clipped[0] > -TOLERANCE && clipped[0] < TOLERANCE);
    assert(clipped[1] > -TOLERANCE && clipped[1] < TOLERANCE);
    assert(clipped[2] > 1 - TOLERANCE);
    assert(clipped.magnitude <= intoCorner.magnitude);
}

unittest {
    float[3] slopeNormal = [-0.5f, 0.8660254f, 0];
    float[3] uphill = [1, 0, 0];
    float[3] downhill = [-1, 0, 0];
    float[3] across = [0, 0, 1];
    float cosine = slopeNormal[1];
    assert(alongGround(uphill, slopeNormal).magnitude > cosine - TOLERANCE && alongGround(uphill, slopeNormal).magnitude < cosine + TOLERANCE);
    assert(alongGround(uphill, slopeNormal)[1] > 0);
    assert(alongGround(downhill, slopeNormal).magnitude > cosine - TOLERANCE && alongGround(downhill, slopeNormal).magnitude < cosine + TOLERANCE);
    assert(alongGround(downhill, slopeNormal)[1] < 0);
    assert(alongGround(across, slopeNormal).magnitude > 1 - TOLERANCE);
}

unittest {
    float[3] wallNormal = [-1, 0, 0];
    float skinDeficit = 0.25f;
    ContactPlane[1] touching = [ContactPlane(wallNormal, skinDeficit)];
    float[3] along = [0, 0, 1];
    float[3] restored = clipToPlanes(touching, along, SkinRule.restore);
    assert(restored.dot(wallNormal) >= skinDeficit);
    float[3] clippedVelocity = clipToPlanes(touching, along, SkinRule.ignore);
    assert(clippedVelocity[0] == along[0] && clippedVelocity[1] == along[1] && clippedVelocity[2] == along[2]);
}

unittest {
    float[3] a = [-1, 0, 0];
    float[3] b = [0, 0, -1];
    float[3] c = [0, -1, 0];
    ContactPlane[3] boxed = [
        ContactPlane(a, 0),
        ContactPlane(b, 0),
        ContactPlane(c, 0),
    ];
    float[3] intoAll = [1, 1, 1];
    assert(clipToPlanes(boxed, intoAll, SkinRule.restore).magnitude == 0);
}

unittest {
    float[3] floorNormal = [0, 1, 0];
    float[3] ceilingNormal = [0, -1, 0];
    ContactPlane[2] squeezed = [
        ContactPlane(floorNormal, 0.01f),
        ContactPlane(ceilingNormal, 0.02f),
    ];
    float[3] alongSlot = [1, -0.1f, 0];
    float[3] clipped = clipToPlanes(squeezed, alongSlot, SkinRule.restore);
    assert(clipped[0] > 1 - TOLERANCE);
    assert(clipped[1] > -TOLERANCE && clipped[1] < TOLERANCE);
}

unittest {
    float[3] first = [-1, 0, 0];
    float[3] nearlySame = [-1, 1e-5f, 0];
    PlaneSet set;
    set.add(ContactPlane(first, 0.5f));
    set.add(ContactPlane(nearlySame, 0.1f));
    assert(set.count == 1);
    assert(set.planes[0].separation == 0.5f);
}

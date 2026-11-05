module unit.controller;

import base.vector3 : Vec3, dot, magnitude;
import common.character.controller : PlaneSet, SkinRule, alongGround, clipToPlanes;
import common.character.sweep : ContactPlane;

enum float TOLERANCE = 1e-5f;

unittest {
    Vec3!float floorNormal = Vec3!float(0, 1, 0);
    Vec3!float wallNormal = Vec3!float(-1, 0, 0);
    ContactPlane[2] planes = [
        ContactPlane(floorNormal, 0),
        ContactPlane(wallNormal, 0),
    ];
    Vec3!float intoCorner = Vec3!float(1, -0.5f, 1);
    Vec3!float clipped = clipToPlanes(planes, intoCorner, SkinRule.restore);
    assert(clipped.x > -TOLERANCE && clipped.x < TOLERANCE);
    assert(clipped.y > -TOLERANCE && clipped.y < TOLERANCE);
    assert(clipped.z > 1 - TOLERANCE);
    assert(clipped.magnitude <= intoCorner.magnitude);
}

unittest {
    Vec3!float slopeNormal = Vec3!float(-0.5f, 0.8660254f, 0);
    Vec3!float uphill = Vec3!float(1, 0, 0);
    Vec3!float downhill = Vec3!float(-1, 0, 0);
    Vec3!float across = Vec3!float(0, 0, 1);
    float cosine = slopeNormal.y;
    assert(alongGround(uphill, slopeNormal).magnitude > cosine - TOLERANCE && alongGround(uphill, slopeNormal).magnitude < cosine + TOLERANCE);
    assert(alongGround(uphill, slopeNormal).y > 0);
    assert(alongGround(downhill, slopeNormal).magnitude > cosine - TOLERANCE && alongGround(downhill, slopeNormal).magnitude < cosine + TOLERANCE);
    assert(alongGround(downhill, slopeNormal).y < 0);
    assert(alongGround(across, slopeNormal).magnitude > 1 - TOLERANCE);
}

unittest {
    Vec3!float wallNormal = Vec3!float(-1, 0, 0);
    float skinDeficit = 0.25f;
    ContactPlane[1] touching = [ContactPlane(wallNormal, skinDeficit)];
    Vec3!float along = Vec3!float(0, 0, 1);
    Vec3!float restored = clipToPlanes(touching, along, SkinRule.restore);
    assert(restored.dot(wallNormal) >= skinDeficit);
    Vec3!float clippedVelocity = clipToPlanes(touching, along, SkinRule.ignore);
    assert(clippedVelocity == along);
}

unittest {
    Vec3!float a = Vec3!float(-1, 0, 0);
    Vec3!float b = Vec3!float(0, 0, -1);
    Vec3!float c = Vec3!float(0, -1, 0);
    ContactPlane[3] boxed = [
        ContactPlane(a, 0),
        ContactPlane(b, 0),
        ContactPlane(c, 0),
    ];
    Vec3!float intoAll = Vec3!float(1, 1, 1);
    assert(clipToPlanes(boxed, intoAll, SkinRule.restore).magnitude == 0);
}

unittest {
    Vec3!float floorNormal = Vec3!float(0, 1, 0);
    Vec3!float ceilingNormal = Vec3!float(0, -1, 0);
    ContactPlane[2] squeezed = [
        ContactPlane(floorNormal, 0.01f),
        ContactPlane(ceilingNormal, 0.02f),
    ];
    Vec3!float alongSlot = Vec3!float(1, -0.1f, 0);
    Vec3!float clipped = clipToPlanes(squeezed, alongSlot, SkinRule.restore);
    assert(clipped.x > 1 - TOLERANCE);
    assert(clipped.y > -TOLERANCE && clipped.y < TOLERANCE);
}

unittest {
    Vec3!float first = Vec3!float(-1, 0, 0);
    Vec3!float nearlySame = Vec3!float(-1, 1e-5f, 0);
    PlaneSet set;
    set.add(ContactPlane(first, 0.5f));
    set.add(ContactPlane(nearlySame, 0.1f));
    assert(set.count == 1);
    assert(set.planes[0].separation == 0.5f);
}

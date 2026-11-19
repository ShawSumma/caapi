module common.settings;

import core.stdc.math : sqrtf;
import base.units : Acceleration, AngularSpeed, Blocks, Length, Rate, Ratio, Speed;
import common.material : MaterialSet;

enum ubyte CHUNK_DIMENSION = 12;

struct CharacterConfig {
    MaterialSet solid;
    Speed noclipSpeed;
    Speed flySpeed;
    Speed walkSpeed;
    Rate walkResponse;
    Acceleration steering;
    Acceleration gravity;
    AngularSpeed upTurnRate;
    Ratio leastTurningGravity;
    Length jumpHeight;
    Blocks stepHeight;
    Ratio footFriction;
    Length skin;
    Length radius;
    Length height;
    Length eyeHeight;

    Speed jumpSpeed() const {
        return Speed(sqrtf((gravity * jumpHeight * 2.0f).value));
    }

    float minSupportCosine() const {
        return 1.0f / sqrtf(1.0f + (footFriction * footFriction).value);
    }

    Length halfHeight() const {
        return height / 2.0f;
    }

    Length eyeOffset() const {
        return eyeHeight - halfHeight;
    }
}

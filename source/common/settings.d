module common.settings;

import core.stdc.math : sqrtf;
import base.units : Acceleration, AngularSpeed, Blocks, Length, Rate, Ratio, Speed;
import common.material : MaterialSet, PLAIN_SOLID;

enum ubyte CHUNK_DIMENSION = 12;

struct CharacterConfig {
    MaterialSet solid = PLAIN_SOLID;
    Speed noclipSpeed = Speed(0.6f);
    Speed flySpeed = Speed(0.4f);
    Speed walkSpeed = Speed(0.225f);
    Rate walkResponse = Rate(12.1f);
    Acceleration steering = Acceleration(0.4f);
    Acceleration gravity = Acceleration(1.6f);
    AngularSpeed upTurnRate = AngularSpeed(4.0f);
    Ratio leastTurningGravity = Ratio(0.1f);
    Length jumpHeight = Length(0.085f);
    Blocks stepHeight = Blocks(1);
    Ratio footFriction = Ratio(1.75f);
    Length skin = Length(0.0005f);
    Length radius = Length(0.0125f);
    Length height = Length(0.09f);
    Length eyeHeight = Length(0.075f);

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

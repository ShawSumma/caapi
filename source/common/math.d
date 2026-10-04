module common.math;

import core.math : sqrt;
import core.stdc.math : acosh, cosh, sinh;

enum float PI = 3.14159265358979323846f;

bool isNan(float value) {
    return value != value;
}

bool isInfinite(float value) {
    return value == float.infinity || value == -float.infinity;
}

struct MVector(N) {
    N[4] data = [0, 0, 0, 0];

    static MVector origin() {
        return MVector([0, 0, 0, 1]);
    }

    N mip(MVector other) const {
        return data[0] * other.data[0] + data[1] * other.data[1] + data[2] * other.data[2] - data[3] * other.data[3];
    }

    MPoint!N normalizedPoint() const {
        return MPoint!N(this / sqrt(-mip(this)));
    }

    MDirection!N normalizedDirection() const {
        return MDirection!N(this / sqrt(mip(this)));
    }

    N[3] xyz() const {
        N[3] result = data[0 .. 3];
        return result;
    }

    Matrix4!N minkowskiOuterProduct(MVector other) const {
        MVector lowered = MVector([other.data[0], other.data[1], other.data[2], -other.data[3]]);
        Matrix4!N result;
        foreach (col; 0 .. 4) {
            foreach (row; 0 .. 4) {
                result.data[col][row] = data[row] * lowered.data[col];
            }
        }
        return result;
    }

    MVector opBinary(string op)(MVector rhs) const if (op == "+" || op == "-") {
        MVector result;
        foreach (i; 0 .. 4) {
            result.data[i] = mixin("data[i] " ~ op ~ " rhs.data[i]");
        }
        return result;
    }

    MVector opBinary(string op)(N rhs) const if (op == "*" || op == "/") {
        MVector result;
        foreach (i; 0 .. 4) {
            result.data[i] = mixin("data[i] " ~ op ~ " rhs");
        }
        return result;
    }

    MVector opUnary(string op)() const if (op == "-") {
        MVector result;
        foreach (i; 0 .. 4) {
            result.data[i] = -data[i];
        }
        return result;
    }

    MVector!M toType(M)() const {
        MVector!M result;
        foreach (i; 0 .. 4) {
            result.data[i] = cast(M) data[i];
        }
        return result;
    }
}

struct MPoint(N) {
    MVector!N vec;

    static MPoint origin() {
        return MPoint(MVector!N.origin());
    }

    N mip(MVector!N other) const {
        return vec.mip(other);
    }

    MPoint midpoint(MPoint other) const {
        return (vec + other.vec).normalizedPoint();
    }

    N distance(MPoint other) const {
        return cast(N) acosh(-vec.mip(other.vec));
    }

    MPoint!M toType(M)() const {
        return MPoint!M(vec.toType!M());
    }
}

struct MDirection(N) {
    MVector!N vec;

    N mip(MVector!N other) const {
        return vec.mip(other);
    }

    MDirection opUnary(string op)() const if (op == "-") {
        return MDirection(-vec);
    }

    MDirection!M toType(M)() const {
        return MDirection!M(vec.toType!M());
    }
}

struct Matrix4(N) {
    N[4][4] data = 0;

    static Matrix4 identity() {
        Matrix4 result;
        foreach (i; 0 .. 4) {
            result.data[i][i] = 1;
        }
        return result;
    }

    static Matrix4 fromScale(N scale) {
        Matrix4 result;
        result.data[0][0] = scale;
        result.data[1][1] = scale;
        result.data[2][2] = scale;
        result.data[3][3] = 1;
        return result;
    }

    MVector!N opBinary(string op)(MVector!N v) const if (op == "*") {
        MVector!N result;
        foreach (row; 0 .. 4) {
            N sum = 0;
            foreach (col; 0 .. 4) {
                sum += data[col][row] * v.data[col];
            }
            result.data[row] = sum;
        }
        return result;
    }

    Matrix4 opBinary(string op)(Matrix4 rhs) const if (op == "*") {
        Matrix4 result;
        foreach (col; 0 .. 4) {
            foreach (row; 0 .. 4) {
                N sum = 0;
                foreach (k; 0 .. 4) {
                    sum += data[k][row] * rhs.data[col][k];
                }
                result.data[col][row] = sum;
            }
        }
        return result;
    }

    Matrix4 opBinary(string op)(N rhs) const if (op == "*") {
        Matrix4 result;
        foreach (col; 0 .. 4) {
            foreach (row; 0 .. 4) {
                result.data[col][row] = data[col][row] * rhs;
            }
        }
        return result;
    }

    Matrix4 opBinary(string op)(Matrix4 rhs) const if (op == "+" || op == "-") {
        Matrix4 result;
        foreach (col; 0 .. 4) {
            foreach (row; 0 .. 4) {
                result.data[col][row] = mixin("data[col][row] " ~ op ~ " rhs.data[col][row]");
            }
        }
        return result;
    }
}

struct MIsometry(N) {
    Matrix4!N mat;

    static MIsometry identity() {
        return MIsometry(Matrix4!N.identity());
    }

    static MIsometry fromReflection(MDirection!N normal) {
        Matrix4!N outer = normal.vec.minkowskiOuterProduct(normal.vec);
        return MIsometry(Matrix4!N.identity() - outer * cast(N) 2);
    }

    static MIsometry fromTranslation(MPoint!N a, MPoint!N b) {
        MVector!N aPlusB = a.vec + b.vec;
        Matrix4!N outerBA = b.vec.minkowskiOuterProduct(a.vec) * cast(N) 2;
        Matrix4!N outerAB = aPlusB.minkowskiOuterProduct(aPlusB);
        N denominator = cast(N) 1 - a.vec.mip(b.vec);
        return MIsometry(Matrix4!N.identity() - outerBA + outerAB * (cast(N) 1 / denominator));
    }

    static MIsometry fromDisplacement(N[3] v) {
        N norm = sqrt(v[0] * v[0] + v[1] * v[1] + v[2] * v[2]);
        if (norm == 0) {
            return identity();
        } else {
            N sinhcValue = cast(N) sinh(norm) / norm;
            N coshValue = cast(N) cosh(norm);
            MVector!N target = MVector!N([v[0] * sinhcValue, v[1] * sinhcValue, v[2] * sinhcValue, coshValue]);
            return fromTranslation(MPoint!N.origin(), MPoint!N(target));
        }
    }

    static MIsometry fromColumnsUnchecked(MDirection!N[3] dirs, MPoint!N point) {
        Matrix4!N result;
        foreach (col; 0 .. 3) {
            foreach (row; 0 .. 4) {
                result.data[col][row] = dirs[col].vec.data[row];
            }
        }
        foreach (row; 0 .. 4) {
            result.data[3][row] = point.vec.data[row];
        }
        return MIsometry(result);
    }

    MIsometry inverse() const {
        Matrix4!N result;
        foreach (i; 0 .. 3) {
            foreach (j; 0 .. 3) {
                result.data[j][i] = mat.data[i][j];
            }
        }
        foreach (i; 0 .. 3) {
            result.data[i][3] = -mat.data[3][i];
            result.data[3][i] = -mat.data[i][3];
        }
        result.data[3][3] = mat.data[3][3];
        return MIsometry(result);
    }

    MVector!N opBinary(string op)(MVector!N v) const if (op == "*") {
        return mat * v;
    }

    MPoint!N opBinary(string op)(MPoint!N p) const if (op == "*") {
        return MPoint!N(mat * p.vec);
    }

    MDirection!N opBinary(string op)(MDirection!N d) const if (op == "*") {
        return MDirection!N(mat * d.vec);
    }

    MIsometry opBinary(string op)(MIsometry rhs) const if (op == "*") {
        return MIsometry(mat * rhs.mat);
    }

    N[4] row(size_t index) const {
        N[4] result;
        foreach (col; 0 .. 4) {
            result[col] = mat.data[col][index];
        }
        return result;
    }

    MIsometry!M toType(M)() const {
        Matrix4!M result;
        foreach (col; 0 .. 4) {
            foreach (row; 0 .. 4) {
                result.data[col][row] = cast(M) mat.data[col][row];
            }
        }
        return MIsometry!M(result);
    }

    MIsometry renormalized() const {
        MVector!N translationColumn = MVector!N(mat.data[3]);
        MIsometry normalizedTranslation = fromTranslation(MPoint!N.origin(), translationColumn.normalizedPoint());
        MIsometry orientation = normalizedTranslation.inverse() * this;
        N[3][3] orthonormal;
        foreach (col; 0 .. 3) {
            N[3] v;
            foreach (k; 0 .. 3) {
                v[k] = orientation.mat.data[col][k];
            }
            foreach (previous; 0 .. col) {
                N dot = 0;
                foreach (k; 0 .. 3) {
                    dot += v[k] * orthonormal[previous][k];
                }
                foreach (k; 0 .. 3) {
                    v[k] -= dot * orthonormal[previous][k];
                }
            }
            N norm = sqrt(v[0] * v[0] + v[1] * v[1] + v[2] * v[2]);
            foreach (k; 0 .. 3) {
                orthonormal[col][k] = v[k] / norm;
            }
        }
        Matrix4!N orientationMatrix;
        foreach (col; 0 .. 3) {
            foreach (row; 0 .. 3) {
                orientationMatrix.data[col][row] = orthonormal[col][row];
            }
        }
        orientationMatrix.data[3][3] = 1;
        return normalizedTranslation * MIsometry(orientationMatrix);
    }
}

float[3] limitToUnitLength(float[3] v) {
    float norm = sqrt(v[0] * v[0] + v[1] * v[1] + v[2] * v[2]);
    if (norm > 1.0f) {
        float[3] limited = [v[0] / norm, v[1] / norm, v[2] / norm];
        return limited;
    } else {
        return v;
    }
}

float[3] projectToPlane(float[3] subject, float[3] normal, float[3] projectionDirection, float distance) {
    float subjectAlongNormal = subject[0] * normal[0] + subject[1] * normal[1] + subject[2] * normal[2];
    float directionAlongNormal = projectionDirection[0] * normal[0] + projectionDirection[1] * normal[1] + projectionDirection[2] * normal[2];
    float t = (distance - subjectAlongNormal) / directionAlongNormal;
    float[3] result = [
        subject[0] + projectionDirection[0] * t,
        subject[1] + projectionDirection[1] * t,
        subject[2] + projectionDirection[2] * t,
    ];
    return result;
}

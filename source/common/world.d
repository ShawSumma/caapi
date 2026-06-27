module common.world;

/// Edge length of a cube in voxels. Voxels are stored without margins here;
/// face stitching reads neighbor cubes directly.
enum int DIM = 12;

enum Material : ushort {
    Void = 0,
    Stone,
    Dirt,
    Grass,
    Sand,
    Water,
    Snow,
}

/// Linear index into a DIM^3 voxel array.
size_t voxelIndex(int x, int y, int z) {
    return cast(size_t)(x + y * DIM + z * DIM * DIM);
}

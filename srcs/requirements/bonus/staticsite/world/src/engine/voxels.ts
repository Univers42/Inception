// A dense voxel grid: one byte per cell, 0 for air, otherwise a material id
// that indexes the level's palette (MAT below). Colour lives in the palette,
// not in the grid, so a level re-tints without re-meshing.

export const MAT = {
    air: 0,
    concrete: 1,
    glass: 2,
    street: 3,
    brass: 4,
    carpetA: 5,
    carpetB: 6,
    wall: 7,
    limestone: 8,
    weathered: 9,
    paper: 10,
    wood: 11,
    trim: 12,
    // emissive from here on: the shader skips light and AO for them
    lamp: 13,
    sign: 14,
    window: 15,
} as const

export const MATERIAL_COUNT = 16
export const FIRST_EMISSIVE = MAT.lamp

export class VoxelGrid {
    readonly data: Uint8Array

    constructor(
        readonly sx: number,
        readonly sy: number,
        readonly sz: number,
    ) {
        this.data = new Uint8Array(sx * sy * sz)
    }

    index(x: number, y: number, z: number): number {
        return x + this.sx * (y + this.sy * z)
    }

    get(x: number, y: number, z: number): number {
        if (x < 0 || y < 0 || z < 0 || x >= this.sx || y >= this.sy || z >= this.sz) return 0
        return this.data[x + this.sx * (y + this.sy * z)]
    }

    set(x: number, y: number, z: number, m: number): void {
        if (x < 0 || y < 0 || z < 0 || x >= this.sx || y >= this.sy || z >= this.sz) return
        this.data[x + this.sx * (y + this.sy * z)] = m
    }

    /** Fill the inclusive-exclusive box [x0,x1) × [y0,y1) × [z0,z1). */
    box(x0: number, y0: number, z0: number, x1: number, y1: number, z1: number, m: number): void {
        for (let z = Math.max(0, z0); z < Math.min(this.sz, z1); z++)
            for (let y = Math.max(0, y0); y < Math.min(this.sy, y1); y++)
                for (let x = Math.max(0, x0); x < Math.min(this.sx, x1); x++) this.data[x + this.sx * (y + this.sy * z)] = m
    }
}

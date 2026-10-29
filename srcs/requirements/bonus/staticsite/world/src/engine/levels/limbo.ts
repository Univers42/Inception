// Level 3, limbo (MariaDB): a bleached shore of modernist slabs eroding into
// the sea.
//
// After the method the film's effects team described (Art of VFX, 2010): a
// space-filling routine fills the land with blocks whose height follows the
// ground's elevation, then rules carve streets and damage. In voxels: lots
// from a recursive split, height from the elevation, and a damage field that
// is strongest at the shore, so the city breaks off toward the water. The
// visitor walks a promenade along the shore, the sea on one side, where
// more towers stand in the water.
import { clamp, fbm2, hash3, noise3, rng, smoothstep } from '../noise'
import { MAT, VoxelGrid } from '../voxels'

export const LIMBO = {
    sx: 136,
    sy: 40,
    sz: 72,
    // the shoreline: land for z below shore(x), sea beyond
    promenade: 6, // voxels between the city and the water's edge
}

export function shore(x: number, seed = 7): number {
    return 50 + 5 * (fbm2(x / 40, 0.5, seed) - 0.5) * 2
}

export function buildLimbo(seed = 7): VoxelGrid {
    const { sx, sy, sz, promenade } = LIMBO
    const g = new VoxelGrid(sx, sy, sz)
    const r = rng(seed)

    // the ground: a low limestone shelf, its height from the elevation
    const elevation = (x: number, z: number) => {
        const e = Math.pow(fbm2(x / 34, z / 34, seed + 3), 1.6)
        return e * smoothstep(shore(x, seed) + 2, shore(x, seed) - 18, z)
    }
    for (let x = 0; x < sx; x++) {
        const edge = Math.floor(shore(x, seed))
        for (let z = 0; z < sz; z++) {
            if (z > edge) continue
            const h = 1 + Math.floor(elevation(x, z) * 5)
            // the promenade's paving joints cross the walk every 6 voxels:
            // on a plain floor nothing showed the camera was moving
            const walk = z > edge - promenade
            g.box(x, 0, z, x + 1, h, z + 1, walk ? (x % 6 === 0 ? MAT.trim : MAT.paper) : MAT.limestone)
        }
    }

    // slabs: lots over the land behind the promenade
    type Lot = { x0: number; z0: number; x1: number; z1: number }
    const lots: Lot[] = []
    const split = (lot: Lot) => {
        const w = lot.x1 - lot.x0
        const d = lot.z1 - lot.z0
        if ((w < 12 && d < 12) || (w <= 6 && d <= 6)) {
            lots.push(lot)
            return
        }
        if (w >= d) {
            const cut = lot.x0 + 3 + Math.floor(r() * (w - 6))
            split({ ...lot, x1: cut })
            split({ ...lot, x0: cut + 2 })
        } else {
            const cut = lot.z0 + 3 + Math.floor(r() * (d - 6))
            split({ ...lot, z1: cut })
            split({ ...lot, z0: cut + 2 })
        }
    }
    for (let x = 2; x < sx - 2; x += 22) split({ x0: x, z0: 2, x1: Math.min(x + 20, sx - 2), z1: 40 })

    for (const lot of lots) {
        const cx = (lot.x0 + lot.x1) >> 1
        const cz = (lot.z0 + lot.z1) >> 1
        const front = Math.floor(shore(cx, seed)) - promenade - 1
        const z1 = Math.min(lot.z1, front)
        if (z1 - lot.z0 < 3) continue
        const e = elevation(cx, cz)
        const h = Math.min(sy - 2, Math.floor(6 + e * 34 + hash3(cx, 0, cz, seed) * 6))
        for (let z = lot.z0; z < z1; z++) {
            const toShore = Math.max(0, front - z)
            for (let x = lot.x0; x < lot.x1; x++) {
                for (let y = 1; y <= h; y++) {
                    // damage: strongest at the shore, noisy, slightly worse up high
                    const dmg = clamp(1 - toShore / 16, 0, 1) * 0.9 + 0.35 * noise3(x / 6, y / 6, z / 6, seed) + 0.01 * y
                    if (dmg > 0.78) continue
                    const band = y % 5 === 0
                    g.set(x, y, z, dmg > 0.55 ? MAT.weathered : band ? MAT.trim : MAT.limestone)
                }
            }
        }
    }

    // The city keeps going under the water: towers standing in the sea, their
    // feet below the surface, eaten from the top and the seaward side.
    for (let k = 0; k < 14; k++) {
        const w = 3 + Math.floor(r() * 5)
        const d = 3 + Math.floor(r() * 4)
        const x0 = 2 + Math.floor(r() * (sx - w - 4))
        const z0 = Math.ceil(shore(x0 + w / 2, seed)) + 4 + Math.floor(r() * 9)
        if (z0 + d >= sz) continue
        const h = 7 + Math.floor(r() * 26)
        for (let x = x0; x < x0 + w; x++) {
            for (let z = z0; z < z0 + d; z++) {
                for (let y = 0; y <= h; y++) {
                    const dmg = 0.25 + 0.45 * noise3(x / 4, y / 5, z / 4, seed + k) + 0.5 * smoothstep(h * 0.55, h, y) + 0.02 * (z - z0)
                    if (dmg > 0.72) continue
                    g.set(x, y, z, dmg > 0.5 ? MAT.weathered : y % 5 === 0 ? MAT.trim : MAT.limestone)
                }
            }
        }
    }
    return g
}

/** The spinning top: a voxelised lathe profile, brass with a steel tip. */
export function buildTotem(): VoxelGrid {
    const g = new VoxelGrid(13, 18, 13)
    const profile = [0.6, 1.2, 2, 2.9, 3.8, 4.6, 5.2, 5.6, 5.6, 5.3, 4.6, 1.4, 1.2, 1.2, 1.2, 1.4, 1.4, 1]
    for (let y = 0; y < profile.length; y++) {
        const rr = profile[y]
        for (let z = 0; z < 13; z++)
            for (let x = 0; x < 13; x++) {
                const dx = x - 6
                const dz = z - 6
                if (dx * dx + dz * dz <= rr * rr) g.set(x, y, z, y < 2 ? MAT.trim : y === 8 ? MAT.sign : MAT.brass)
            }
    }
    return g
}

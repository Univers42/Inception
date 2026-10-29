// Level 1, the door (nginx): a city at blue hour whose street folds up.
//
// Blocks split into lots, tower heights from three-octave noise, taller toward
// the hinge where the street rolls up; glass curtain walls banded by concrete
// floors, setbacks, a parapet, the odd sky-bridge. A brass gate spans the
// avenue before the hinge: the only door, the way into the dream.
//
// Original massing: voxels as architecture (a foam model, not game terrain),
// no textures, no characters.
import { fbm2, hash3, rng, smoothstep } from '../noise'
import type { Lamp } from '../lamps'
import { MAT, VoxelGrid } from '../voxels'

export const CITY = {
    sx: 96,
    sy: 46,
    sz: 176,
    avenue: [42, 54] as const, // x range left free for the walk
    gate: 38, // z of the gate
    z0: 74, // hinge: the street folds beyond it
    radius: 30,
}

type Lot = { x0: number; z0: number; x1: number; z1: number }

const isLampRow = (z: number) => z % 12 === 6 && z > 8

/** The avenue's lamps as lights: each post's head, a voxel out over the
 *  street, and one light for the gate's row of lamps under its lintel. */
export function cityLamps(): Lamp[] {
    const [ax0, ax1] = CITY.avenue
    const lamps: Lamp[] = []
    // three of them failing: rows 3 and 8 on one kerb, row 5 on the other
    const failing = (row: number, side: number) => (side === 0 ? row === 3 || row === 8 : row === 5)
    for (let z = 0; z < CITY.sz; z++) {
        if (!isLampRow(z)) continue
        const row = (z - 6) / 12
        const sides: Array<[number, number, number]> = [
            [ax0 + 0.6, ax0 - 1, 0],
            [ax1 - 0.6, ax1, 1],
        ]
        for (const [x, cellX, side] of sides) {
            const lamp: Lamp = { x, y: 6.2, z: z + 0.5, color: '#ffc477', power: 20, range: 18 }
            if (failing(row, side)) lamp.flicker = { seed: row * 2 + side, cell: [cellX, 6, z] }
            lamps.push(lamp)
        }
    }
    lamps.push({ x: (ax0 + ax1) / 2, y: 18.5, z: CITY.gate - 2, color: '#f0b45a', power: 30, range: 30 })
    return lamps
}

function splitLots(lot: Lot, r: () => number, out: Lot[]): void {
    const w = lot.x1 - lot.x0
    const d = lot.z1 - lot.z0
    if ((w < 10 && d < 10) || (w <= 7 && d <= 7) || (r() < 0.22 && w < 14 && d < 14)) {
        out.push(lot)
        return
    }
    if (w >= d) {
        const cut = lot.x0 + 4 + Math.floor(r() * (w - 8))
        splitLots({ ...lot, x1: cut }, r, out)
        splitLots({ ...lot, x0: cut + 1 }, r, out)
    } else {
        const cut = lot.z0 + 4 + Math.floor(r() * (d - 8))
        splitLots({ ...lot, z1: cut }, r, out)
        splitLots({ ...lot, z0: cut + 1 }, r, out)
    }
}

function tower(g: VoxelGrid, lot: Lot, h: number, glass: boolean): void {
    const setback = Math.floor(h * 0.62)
    for (let y = 1; y <= h; y++) {
        const inset = y > setback ? 1 : 0
        const x0 = lot.x0 + inset
        const x1 = lot.x1 - inset
        const z0 = lot.z0 + inset
        const z1 = lot.z1 - inset
        if (x1 - x0 < 2 || z1 - z0 < 2) break
        const band = y % 4 === 0 || y === 1
        for (let z = z0; z < z1; z++) {
            for (let x = x0; x < x1; x++) {
                const edge = x === x0 || x === x1 - 1 || z === z0 || z === z1 - 1
                const corner = (x === x0 || x === x1 - 1) && (z === z0 || z === z1 - 1)
                let m: number = MAT.concrete
                if (glass && edge && !corner && !band) m = MAT.glass
                g.set(x, y, z, m)
            }
        }
    }
    // parapet ring
    const inset = h > setback ? 1 : 0
    for (let x = lot.x0 + inset; x < lot.x1 - inset; x++) {
        g.set(x, h + 1, lot.z0 + inset, MAT.trim)
        g.set(x, h + 1, lot.z1 - inset - 1, MAT.trim)
    }
    for (let z = lot.z0 + inset; z < lot.z1 - inset; z++) {
        g.set(lot.x0 + inset, h + 1, z, MAT.trim)
        g.set(lot.x1 - inset - 1, h + 1, z, MAT.trim)
    }
}

export function buildCity(seed = 42, scale = 1): VoxelGrid {
    const sz = Math.round(CITY.sz * scale)
    const g = new VoxelGrid(CITY.sx, CITY.sy, sz)
    const r = rng(seed)
    const [ax0, ax1] = CITY.avenue

    // the ground: avenue and side streets, kerbs along the avenue
    g.box(0, 0, 0, CITY.sx, 1, sz, MAT.street)
    for (let z = 0; z < sz; z++) {
        g.set(ax0 - 1, 1, z, MAT.trim)
        g.set(ax1, 1, z, MAT.trim)
        // lamp posts every 12 voxels on both kerbs, before the gate's plaza ends
        if (isLampRow(z)) {
            for (let y = 2; y < 6; y++) {
                g.set(ax0 - 1, y, z, MAT.trim)
                g.set(ax1, y, z, MAT.trim)
            }
            g.set(ax0 - 1, 6, z, MAT.lamp)
            g.set(ax1, 6, z, MAT.lamp)
        }
    }

    const columns: [number, number][] = [
        [2, 14],
        [18, 30],
        [33, ax0 - 3],
        [ax1 + 3, 63],
        [66, 78],
        [82, 94],
    ]
    const lots: Lot[] = []
    for (const [x0, x1] of columns) {
        for (let z = 2; z < sz - 4; z += 16) {
            // the plaza before the gate stays open on the avenue side
            if (z < 26 && x1 >= ax0 - 6 && x0 <= ax1 + 6) continue
            splitLots({ x0, z0: z, x1, z1: Math.min(z + 13, sz - 2) }, r, lots)
        }
    }

    for (const lot of lots) {
        const cx = (lot.x0 + lot.x1) / 2
        const cz = (lot.z0 + lot.z1) / 2
        const n = fbm2(cx / 28, cz / 28, seed)
        const nearHinge = smoothstep(150, 0, Math.abs(cz - CITY.z0))
        const nearAvenue = smoothstep(46, 6, Math.abs(cx - (ax0 + ax1) / 2))
        const jitter = Math.floor(hash3(lot.x0, 0, lot.z0, seed) * 5)
        const h = Math.min(CITY.sy - 3, Math.floor(4 + n * n * 30 * (0.55 + 0.6 * nearHinge) * (0.7 + 0.5 * nearAvenue) + jitter))
        tower(g, lot, Math.max(3, h), hash3(lot.x1, 1, lot.z1, seed) < 0.62)
    }

    // sky-bridges across side streets, high up: Escher links between towers
    for (let i = 0; i < 26; i++) {
        const z = 30 + Math.floor(r() * (sz - 40))
        const y = 12 + Math.floor(r() * 16)
        const x = [2, 14, 30, 66, 78][Math.floor(r() * 5)]
        if (g.get(x - 1, y, z) && g.get(x + 5, y, z)) g.box(x, y, z, x + 5, y + 1, z + 2, MAT.concrete)
    }

    // the gate: two brass pillars and a lintel over the avenue
    const gz = CITY.gate
    g.box(ax0 - 2, 1, gz, ax0, 19, gz + 2, MAT.brass)
    g.box(ax1, 1, gz, ax1 + 2, 19, gz + 2, MAT.brass)
    g.box(ax0 - 2, 19, gz, ax1 + 2, 21, gz + 2, MAT.brass)
    g.box(ax0, 17, gz, ax1, 18, gz + 2, MAT.trim)
    // a row of lamps under the lintel's face
    for (let x = ax0 + 2; x < ax1 - 2; x += 2) g.set(x, 20, gz - 1, MAT.sign)
    return g
}

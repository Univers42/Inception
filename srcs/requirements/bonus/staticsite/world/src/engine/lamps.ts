// The point lights of a level: where its lamps hang, in the level's own grid
// coordinates (the frame the voxel shader lights in, before the fold and the
// corridor's turn). The shader takes the MAX_LAMPS nearest to the camera,
// picked again every frame; a level has a few dozen, so a full scan is cheaper
// than any index.
//
// Caveat: a lamp beyond the nearest MAX_LAMPS contributes nothing, so a far
// pool of light can pop in as the camera walks. With lamps every 12 voxels and
// fog at 30+, the popping happens inside the fog.
export const MAX_LAMPS = 12
export const MAX_FLICKERS = 4

export type Lamp = {
    x: number
    y: number
    z: number
    color: string
    power: number
    range: number
    // a failing lamp: its seed, and the voxel that glows for it, so the light
    // it casts and the bulb you see stutter together
    flicker?: { seed: number; cell: [number, number, number] }
}

/** A failing lamp's brightness at time t: steady, then now and then (a few
 *  seconds in every fourteen) a burst of stutter. */
export function flickerAt(seed: number, t: number): number {
    if (Math.sin(t * 0.45 + seed * 7.3) < 0.82) return 1
    return Math.sin(t * 37 + seed) + Math.sin(t * 23.3 + seed * 2) > 0.2 ? 1 : 0.1
}

export function nearestLamps(lamps: Lamp[], x: number, y: number, z: number, n: number): Lamp[] {
    return lamps
        .map((l) => ({ l, d: (l.x - x) ** 2 + (l.y - y) ** 2 + (l.z - z) ** 2 }))
        .sort((a, b) => a.d - b.d)
        .slice(0, n)
        .map((e) => e.l)
}

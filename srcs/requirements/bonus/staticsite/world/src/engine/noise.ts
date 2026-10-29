// Deterministic randomness for the generators: the same seed draws the same
// city on every visit and in every test, so screenshots are comparable.

/** mulberry32: a 32-bit seeded generator, uniform in [0, 1). */
export function rng(seed: number): () => number {
    let a = seed >>> 0
    return () => {
        a = (a + 0x6d2b79f5) >>> 0
        let t = a
        t = Math.imul(t ^ (t >>> 15), t | 1)
        t ^= t + Math.imul(t ^ (t >>> 7), t | 61)
        return ((t ^ (t >>> 14)) >>> 0) / 4294967296
    }
}

/** Integer hash of a lattice point, uniform in [0, 1). */
export function hash3(x: number, y: number, z: number, seed = 0): number {
    let h = Math.imul(x | 0, 374761393) + Math.imul(y | 0, 668265263) + Math.imul(z | 0, 2147483647) + Math.imul(seed | 0, 1442695041)
    h = Math.imul(h ^ (h >>> 13), 1274126177)
    h ^= h >>> 16
    return (h >>> 0) / 4294967296
}

const smooth = (t: number) => t * t * (3 - 2 * t)

/** Value noise on the integer lattice, smoothly interpolated, in [0, 1). */
export function noise2(x: number, z: number, seed = 0): number {
    const x0 = Math.floor(x)
    const z0 = Math.floor(z)
    const fx = smooth(x - x0)
    const fz = smooth(z - z0)
    const a = hash3(x0, 0, z0, seed)
    const b = hash3(x0 + 1, 0, z0, seed)
    const c = hash3(x0, 0, z0 + 1, seed)
    const d = hash3(x0 + 1, 0, z0 + 1, seed)
    return a + (b - a) * fx + (c - a) * fz + (a - b - c + d) * fx * fz
}

/** Three octaves (amplitudes 1, .5, .25), normalised back to [0, 1). */
export function fbm2(x: number, z: number, seed = 0): number {
    return (noise2(x, z, seed) + 0.5 * noise2(x * 2, z * 2, seed + 1) + 0.25 * noise2(x * 4, z * 4, seed + 2)) / 1.75
}

export const clamp = (v: number, lo: number, hi: number) => (v < lo ? lo : v > hi ? hi : v)
export const smoothstep = (a: number, b: number, v: number) => smooth(clamp((v - a) / (b - a), 0, 1))

/** Value noise in 3D, trilinear with smoothstep weights, in [0, 1). */
export function noise3(x: number, y: number, z: number, seed = 0): number {
    const x0 = Math.floor(x)
    const y0 = Math.floor(y)
    const z0 = Math.floor(z)
    const fx = smooth(x - x0)
    const fy = smooth(y - y0)
    const fz = smooth(z - z0)
    const lerp = (a: number, b: number, t: number) => a + (b - a) * t
    const plane = (zz: number) =>
        lerp(lerp(hash3(x0, y0, zz, seed), hash3(x0 + 1, y0, zz, seed), fx), lerp(hash3(x0, y0 + 1, zz, seed), hash3(x0 + 1, y0 + 1, zz, seed), fx), fy)
    return lerp(plane(z0), plane(z0 + 1), fz)
}

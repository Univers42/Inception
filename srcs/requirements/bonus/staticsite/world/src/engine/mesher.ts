// Greedy meshing with baked ambient occlusion (0fps.net, 2012–2013).
//
// Only faces between a solid cell and air are drawn, and coplanar neighbours
// with the same material and the same four corner-AO values merge into one
// quad, so the occlusion stays exact. On a 96×192 city that is 108,300 culled
// quads → 14,549 (7.4×); one instanced cube per voxel ran 10× slower under
// software WebGL (research, 2026-10-28), which is what the GPU-less 42 seats
// fall back to.
//
// Per vertex the shader gets: position, aAo (0..3, 0 = darkest), aFace
// (0 +x, 1 −x, 2 +y, 3 −y, 4 +z, 5 −z) and aMat (palette index).
//
// Caveat: greedy quads create T-junctions where a big quad meets small ones.
// With flat colours they do not show; under MSAA a pixel can sparkle along
// such an edge on some GPUs.
import type { VoxelGrid } from './voxels'

export type MeshData = {
    position: Float32Array
    ao: Float32Array
    face: Float32Array
    mat: Float32Array
    index: Uint32Array
    quads: number
}

class Growable {
    buf: Float32Array
    n = 0
    constructor(size: number) {
        this.buf = new Float32Array(size)
    }
    push(v: number) {
        if (this.n === this.buf.length) {
            const next = new Float32Array(this.buf.length * 2)
            next.set(this.buf)
            this.buf = next
        }
        this.buf[this.n++] = v
    }
    done(): Float32Array {
        return this.buf.slice(0, this.n)
    }
}

// corner offsets (along u, along v) in quad order: (−,−) (+,−) (+,+) (−,+)
const CORNERS = [
    [-1, -1],
    [1, -1],
    [1, 1],
    [-1, 1],
]

export function greedyMesh(g: VoxelGrid): MeshData {
    const dims = [g.sx, g.sy, g.sz]
    const pos = new Growable(1 << 16)
    const ao = new Growable(1 << 14)
    const face = new Growable(1 << 14)
    const mat = new Growable(1 << 14)
    const index: number[] = []
    let quads = 0
    const q = [0, 0, 0]
    const t = [0, 0, 0]
    const solidAt = (u: number, v: number, ou: number, ov: number) => {
        t[0] = q[0]
        t[1] = q[1]
        t[2] = q[2]
        t[u] += ou
        t[v] += ov
        return g.get(t[0], t[1], t[2]) !== 0 ? 1 : 0
    }

    for (let d = 0; d < 3; d++) {
        const u = (d + 1) % 3
        const v = (d + 2) % 3
        const du = dims[u]
        const dv = dims[v]
        const mask = new Int32Array(du * dv)
        for (const s of [1, -1]) {
            const faceId = d * 2 + (s > 0 ? 0 : 1)
            for (let i = 0; i < dims[d]; i++) {
                let n = 0
                for (let b = 0; b < dv; b++) {
                    for (let a = 0; a < du; a++, n++) {
                        q[d] = i
                        q[u] = a
                        q[v] = b
                        const m = g.get(q[0], q[1], q[2])
                        mask[n] = 0
                        if (!m) continue
                        q[d] = i + s
                        if (g.get(q[0], q[1], q[2])) continue
                        let key = m | (1 << 16)
                        for (let k = 0; k < 4; k++) {
                            const cu = CORNERS[k][0]
                            const cv = CORNERS[k][1]
                            const s1 = solidAt(u, v, cu, 0)
                            const s2 = solidAt(u, v, 0, cv)
                            const c = solidAt(u, v, cu, cv)
                            const level = s1 && s2 ? 0 : 3 - (s1 + s2 + c)
                            key |= level << (8 + 2 * k)
                        }
                        mask[n] = key
                    }
                }
                const plane = i + (s > 0 ? 1 : 0)
                n = 0
                for (let b = 0; b < dv; b++) {
                    for (let a = 0; a < du; ) {
                        const key = mask[n]
                        if (!key) {
                            a++
                            n++
                            continue
                        }
                        let w = 1
                        while (a + w < du && mask[n + w] === key) w++
                        let h = 1
                        grow: while (b + h < dv) {
                            for (let k = 0; k < w; k++) if (mask[n + k + h * du] !== key) break grow
                            h++
                        }
                        // corners in (u, v), counter-clockwise seen from +d
                        const cu = [a, a + w, a + w, a]
                        const cv = [b, b, b + h, b + h]
                        const order = s > 0 ? [0, 1, 2, 3] : [0, 3, 2, 1]
                        const base = quads * 4
                        const aoq: number[] = []
                        for (const k of order) {
                            t[d] = plane
                            t[u] = cu[k]
                            t[v] = cv[k]
                            pos.push(t[0])
                            pos.push(t[1])
                            pos.push(t[2])
                            const level = (key >> (8 + 2 * k)) & 3
                            aoq.push(level)
                            ao.push(level)
                            face.push(faceId)
                            mat.push(key & 255)
                        }
                        // split along the diagonal that keeps the occlusion
                        // gradient isotropic (0fps, part 3)
                        if (aoq[0] + aoq[2] > aoq[1] + aoq[3]) index.push(base, base + 1, base + 2, base, base + 2, base + 3)
                        else index.push(base + 1, base + 2, base + 3, base + 1, base + 3, base)
                        quads++
                        for (let l = 0; l < h; l++) for (let k = 0; k < w; k++) mask[n + k + l * du] = 0
                        a += w
                        n += w
                    }
                }
            }
        }
    }
    return { position: pos.done(), ao: ao.done(), face: face.done(), mat: mat.done(), index: Uint32Array.from(index), quads }
}

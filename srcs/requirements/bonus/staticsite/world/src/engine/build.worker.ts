// Generates and meshes the levels off the main thread: the city alone took
// 289–527 ms to mesh in a single thread (research, 2026-10-28), long enough to
// stall scrolling. The city is posted first so the first level can draw while
// the deeper ones are still being built.
import { greedyMesh, type MeshData } from './mesher'
import { buildCity } from './levels/city'
import { buildHallway } from './levels/hallway'
import { buildLimbo, buildTotem } from './levels/limbo'

export type BuildRequest = { scale: number }
export type Built = { name: 'city' | 'hall' | 'limbo' | 'totem'; mesh: MeshData; ms: number }

const post = (name: Built['name'], build: () => MeshData) => {
    const t0 = performance.now()
    const mesh = build()
    const message: Built = { name, mesh, ms: performance.now() - t0 }
    ;(self as unknown as Worker).postMessage(message, [mesh.position.buffer, mesh.ao.buffer, mesh.face.buffer, mesh.mat.buffer, mesh.index.buffer])
}

self.onmessage = (e: MessageEvent<BuildRequest>) => {
    post('city', () => greedyMesh(buildCity(42, e.data.scale)))
    post('hall', () => greedyMesh(buildHallway()))
    post('limbo', () => greedyMesh(buildLimbo()))
    post('totem', () => greedyMesh(buildTotem()))
}

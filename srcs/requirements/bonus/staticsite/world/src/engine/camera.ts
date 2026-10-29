// The choreography: where the eye is for a given position in the descent.
//
// `x` runs from 0 to 5: the integer part is the chapter (0 surface, 1 the
// door, 2 the dream, 3 limbo, 4 the kick), the fraction how far through it the
// reader has scrolled. Each chapter is a pure function of its fraction, so the
// same scroll position always shows the same frame, and reduced motion can
// jump straight to a chapter's middle.
import { Vector3 } from 'three'
import { CITY } from './levels/city'
import { HALL } from './levels/hallway'
import { LIMBO, shore } from './levels/limbo'
import { clamp, smoothstep } from './noise'

export type Scene = 'city' | 'hall' | 'limbo'

export type Shot = {
    scene: Scene
    pos: Vector3
    look: Vector3
    fold: number // city: radians the street has rolled up
    turn: number // hallway: radians the corridor has turned
    dark: number // 0..1 veil to black (falling through a floor)
    bright: number // 0..1 veil to white (arriving in limbo)
    spin: boolean // the totem is in view
}

export const CHAPTERS = 5

const mid = (CITY.avenue[0] + CITY.avenue[1]) / 2
const smoother = (t: number) => t * t * t * (t * (t * 6 - 15) + 10)
const lerp = (a: number, b: number, t: number) => a + (b - a) * t
const shot = (scene: Scene, p: [number, number, number], l: [number, number, number], extra: Partial<Shot> = {}): Shot => ({
    scene,
    pos: new Vector3(...p),
    look: new Vector3(...l),
    fold: 0,
    turn: 0,
    dark: 0,
    bright: 0,
    spin: false,
    ...extra,
})

// the hallway's frame: the corridor turns about its own axis, which the world
// places at the origin, so positions here are relative to that axis
const hallEye = 3.6 - HALL.axis.y

function surface(t: number): Shot {
    const z = lerp(2, 16, smoother(t))
    return shot('city', [mid + Math.sin(t * Math.PI) * 1.6, lerp(3.2, 2.2, t), z], [mid, lerp(12, 8, t), CITY.gate + 40])
}

function door(t: number): Shot {
    const walk = smoothstep(0, 0.8, t)
    const z = lerp(16, CITY.z0 - 8, walk)
    const fold = smoothstep(0.18, 0.78, t) * Math.PI
    const up = smoothstep(0.55, 0.85, t)
    const fall = smoothstep(0.84, 1, t)
    const look: [number, number, number] = [mid, lerp(2 + fold * 3, 58, up), lerp(z + 40, CITY.z0 + 4, up)]
    return shot('city', [mid, 2.2 - fall * 9, z], look, { fold, dark: fall })
}

function dream(t: number): Shot {
    const arrive = smoothstep(0, 0.12, t)
    const z = lerp(-4, HALL.module * HALL.modules - 6, smoothstep(0.08, 0.92, t))
    const turn = 2 * Math.PI * smoother(clamp((t - 0.16) / 0.68, 0, 1))
    const leave = smoothstep(0.9, 1, t)
    return shot('hall', [0, hallEye + (1 - arrive) * 3, z], [0, hallEye - 0.2, z + 12], { turn, dark: 1 - arrive, bright: leave })
}

function limbo(t: number): Shot {
    const x = lerp(8, LIMBO.sx - 24, smoothstep(0.05, 1, t))
    const z = shore(x) - LIMBO.promenade / 2 - 1
    const arrive = smoothstep(0, 0.14, t)
    return shot('limbo', [x, 2.4 + (1 - arrive) * 6, z], [x + 14, 3 + Math.sin(t * 3) * 0.5, z + 9 - t * 6], { bright: 1 - arrive })
}

function kick(t: number): Shot {
    const x = LIMBO.sx - 16
    const z = shore(x) - LIMBO.promenade / 2 - 1
    const close = smoother(t)
    return shot('limbo', [lerp(x - 8, x - 3, close), lerp(3, 2, close), z - lerp(0, 2, close)], [x + 4, lerp(3, 1.6, close), z - 1], { spin: true })
}

const SHOTS = [surface, door, dream, limbo, kick]

export function shotAt(x: number): Shot {
    const c = clamp(x, 0, CHAPTERS - 1e-6)
    const i = Math.floor(c)
    return SHOTS[i](c - i)
}

/** Where the totem stands: at the end of the promenade. */
export function totemSpot(): Vector3 {
    const x = LIMBO.sx - 12
    return new Vector3(x, 1, shore(x) - LIMBO.promenade / 2 - 2)
}

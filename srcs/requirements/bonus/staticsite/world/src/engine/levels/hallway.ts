// Level 2, the dream (WordPress + php-fpm): a hotel corridor that turns.
//
// Built in its own frame (axis +z), 5 wide and 4 high inside, in modules of 8
// voxels: a door alcove with a brass frame and a lit number plate, alternating
// sides; a sconce between doors; a light in the ceiling; carpet with a border.
// Every fourth module a brass ring runs round the walls: a nod to the rings of
// the rotating set, not a copy of it. The world turns the whole corridor about
// its axis while the camera walks, so walls become the floor.
import type { Lamp } from '../lamps'
import { MAT, VoxelGrid } from '../voxels'

export const HALL = {
    sx: 13,
    sy: 9,
    module: 8,
    modules: 14,
    inside: { x0: 4, x1: 9, y0: 2, y1: 6 },
    // the axis the corridor turns about, in grid coordinates
    axis: { x: 6.5, y: 4 },
}

/** Each module's sconce and ceiling light, and the bright doorway at the end,
 *  half a voxel out from the voxels the builder lights up. */
export function hallLamps(): Lamp[] {
    const { module, modules, inside, axis } = HALL
    const lamps: Lamp[] = []
    for (let k = 0; k < modules; k++) {
        const z0 = k * module
        const left = k % 2 === 0
        const sconce: Lamp = { x: left ? inside.x1 - 0.4 : inside.x0 + 0.4, y: inside.y0 + 2.5, z: z0 + 4.5, color: '#ffcf8a', power: 2.2, range: 7 }
        // two sconces are failing, as in any hotel this old
        if (k === 2 || k === 9) sconce.flicker = { seed: 40 + k, cell: [left ? inside.x1 : inside.x0 - 1, inside.y0 + 2, z0 + 4] }
        lamps.push(sconce)
        lamps.push({ x: axis.x, y: inside.y1 - 0.4, z: z0 + 6.5, color: '#ffe2b8', power: 2.4, range: 8 })
    }
    lamps.push({ x: axis.x, y: axis.y, z: module * modules - 1, color: '#fff3dc', power: 14, range: 22 })
    return lamps
}

export function buildHallway(): VoxelGrid {
    const { sx, sy, module, modules, inside } = HALL
    const sz = module * modules + 2
    const g = new VoxelGrid(sx, sy, sz)
    g.box(0, 0, 0, sx, sy, sz, MAT.wall)
    g.box(inside.x0, inside.y0, 0, inside.x1, inside.y1, sz - 1, MAT.air)

    for (let z = 0; z < sz - 1; z++) {
        // carpet: a runner with a darker border and a band every module
        for (let x = inside.x0; x < inside.x1; x++) {
            const border = x === inside.x0 || x === inside.x1 - 1 || z % module === 0
            g.set(x, inside.y0 - 1, z, border ? MAT.carpetB : MAT.carpetA)
        }
        // wainscot along the bottom of both walls, ceiling in trim
        g.set(inside.x0 - 1, inside.y0, z, MAT.wood)
        g.set(inside.x1, inside.y0, z, MAT.wood)
        for (let x = inside.x0; x < inside.x1; x++) g.set(x, inside.y1, z, MAT.trim)
    }

    for (let k = 0; k < modules; k++) {
        const z0 = k * module
        const left = k % 2 === 0
        // the door alcove: two deep, two wide, three high, then the door
        const wallX = left ? inside.x0 - 1 : inside.x1
        const recess = left ? [inside.x0 - 2, inside.x0] : [inside.x1, inside.x1 + 2]
        g.box(recess[0], inside.y0, z0 + 3, recess[1], inside.y0 + 3, z0 + 5, MAT.air)
        const doorX = left ? inside.x0 - 3 : inside.x1 + 2
        g.box(doorX, inside.y0, z0 + 3, doorX + 1, inside.y0 + 3, z0 + 5, MAT.wood)
        // brass frame on the wall face around the opening
        for (let y = inside.y0; y <= inside.y0 + 3; y++) {
            g.set(wallX, y, z0 + 2, MAT.brass)
            g.set(wallX, y, z0 + 5, MAT.brass)
        }
        g.set(wallX, inside.y0 + 3, z0 + 3, MAT.brass)
        g.set(wallX, inside.y0 + 3, z0 + 4, MAT.sign)
        // a sconce on the other wall, a light in the ceiling
        const otherX = left ? inside.x1 : inside.x0 - 1
        g.set(otherX, inside.y0 + 2, z0 + 4, MAT.lamp)
        g.set(Math.floor(HALL.axis.x), inside.y1, z0 + 6, MAT.lamp)
        // every fourth module, a brass ring round the inside
        if (k % 4 === 3) {
            for (let y = inside.y0 - 1; y <= inside.y1; y++) {
                g.set(inside.x0 - 1, y, z0 + 7, MAT.brass)
                g.set(inside.x1, y, z0 + 7, MAT.brass)
            }
            for (let x = inside.x0 - 1; x <= inside.x1; x++) {
                g.set(x, inside.y0 - 1, z0 + 7, MAT.brass)
                g.set(x, inside.y1, z0 + 7, MAT.brass)
            }
        }
    }
    // the far end: a lit doorway, the way down to limbo
    const end = sz - 2
    g.box(inside.x0, inside.y0, end, inside.x1, inside.y1, end + 1, MAT.window)
    return g
}

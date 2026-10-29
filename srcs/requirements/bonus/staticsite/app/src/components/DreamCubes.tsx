import type { CSSProperties } from 'react'
import { motion, useTransform, type MotionValue } from 'framer-motion'

// Three nested cubes, one per dream level, in CSS 3D: six bordered faces each,
// composited by the GPU, no canvas and no video. Going deeper passes *through*
// them: as level 2 arrives the outer cube grows past the viewer and fades, as
// level 3 arrives the middle one does, and the innermost is what is left.
// The kit this page follows (motionsites.ai) puts a CDN video here; this is a
// couple of KB, makes no third-party request, and holds still under reduced
// motion (the turning is a CSS animation the media query switches off).
const FACES = ['front', 'back', 'right', 'left', 'top', 'bottom'] as const

function Cube({ size, depth, turn }: { size: number; depth: 1 | 2 | 3; turn: string }) {
    const style = { '--size': `${size}px`, '--tint': `var(--level-${depth})`, animationDuration: turn } as CSSProperties
    return (
        <div className={`cube${depth === 2 ? ' cube-reverse' : ''}`} style={style}>
            {FACES.map((f) => (
                <span key={f} className={`cube-face cube-${f}`} />
            ))}
        </div>
    )
}

// p is the levels track's progress: level i shows for p in [i/3, (i+1)/3), so
// each cube is gone just before the level that replaces it settles.
export function DreamCubes({ progress }: { progress: MotionValue<number> }) {
    const outerScale = useTransform(progress, [0.18, 0.36], [1, 3.6])
    const outerOpacity = useTransform(progress, [0.22, 0.36], [1, 0])
    const middleScale = useTransform(progress, [0.51, 0.69], [1, 3.6])
    const middleOpacity = useTransform(progress, [0.55, 0.69], [1, 0])
    const innerScale = useTransform(progress, [0, 0.69, 1], [1, 1.45, 1.8])
    return (
        <div aria-hidden="true" className="dream-cubes">
            <motion.div className="cube-slot" style={{ scale: innerScale }}>
                <Cube size={96} depth={3} turn="26s" />
            </motion.div>
            <motion.div className="cube-slot" style={{ scale: middleScale, opacity: middleOpacity }}>
                <Cube size={180} depth={2} turn="34s" />
            </motion.div>
            <motion.div className="cube-slot" style={{ scale: outerScale, opacity: outerOpacity }}>
                <Cube size={290} depth={1} turn="44s" />
            </motion.div>
        </div>
    )
}

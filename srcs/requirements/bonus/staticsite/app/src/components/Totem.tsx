import { motion, useReducedMotion } from 'framer-motion'

type TotemProps = {
    size?: number
    // Bumped by the levels on every change of depth: each bump spins the top
    // once, so the navbar mark answers the scroll the way the film's totem
    // answers "am I still dreaming?".
    spins?: number
    className?: string
}

export function Totem({ size = 22, spins = 0, className }: TotemProps) {
    const reduce = useReducedMotion()
    return (
        <motion.svg
            key={reduce ? 'still' : spins}
            width={size}
            height={size}
            viewBox="0 0 32 32"
            fill="none"
            aria-hidden="true"
            className={className}
            style={{ transformPerspective: 160 }}
            initial={reduce || spins === 0 ? false : { rotateY: 0 }}
            animate={reduce ? undefined : { rotateY: 720 }}
            transition={{ duration: 1.1, ease: [0.22, 1, 0.36, 1] }}
        >
            <defs>
                <linearGradient id="totem-body" x1="5" y1="10" x2="27" y2="10" gradientUnits="userSpaceOnUse">
                    <stop offset="0" stopColor="#c9862a" />
                    <stop offset="0.45" stopColor="#f6c77f" />
                    <stop offset="1" stopColor="#a8691c" />
                </linearGradient>
            </defs>
            <path d="M16 2.5v6" stroke="#f0b45a" strokeWidth="2.2" strokeLinecap="round" />
            <path d="M4.5 11.5C9 7.8 23 7.8 27.5 11.5L16.4 29.2a.5.5 0 0 1-.8 0z" fill="url(#totem-body)" />
            <path d="M6.5 12.6c5.6 2.3 13.4 2.3 19 0" stroke="#1a1206" strokeOpacity=".35" strokeWidth="1.2" />
        </motion.svg>
    )
}

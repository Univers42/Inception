import { useEffect, useRef } from 'react'
import { useReducedMotion } from 'framer-motion'

// The kit this design comes from (motionsites.ai "Orbit Engineers") puts a CDN
// video behind each section. Here each dream level is drawn instead: no third-
// party request, ~2 KB of code, and a frame that can be frozen for visitors who
// ask for reduced motion. Only one scene runs at a time, plus the outgoing one
// during the cross-fade; drawing stops while the tab is hidden or the stage is
// off screen.

type Scene = (ctx: CanvasRenderingContext2D, w: number, h: number, t: number, tint: string) => void

function rgba(hex: string, alpha: number) {
    const m = /^#?([0-9a-f]{2})([0-9a-f]{2})([0-9a-f]{2})$/i.exec(hex.trim())
    if (!m) return `rgba(141, 180, 216, ${alpha})`
    return `rgba(${parseInt(m[1], 16)}, ${parseInt(m[2], 16)}, ${parseInt(m[3], 16)}, ${alpha})`
}

function glow(ctx: CanvasRenderingContext2D, x: number, y: number, r: number, color: string) {
    const g = ctx.createRadialGradient(x, y, 0, x, y, r)
    g.addColorStop(0, color)
    g.addColorStop(1, 'rgba(0, 0, 0, 0)')
    ctx.fillStyle = g
    ctx.fillRect(x - r, y - r, r * 2, r * 2)
}

// A receding grid plane, from the horizon down to the bottom edge.
function plane(ctx: CanvasRenderingContext2D, w: number, h: number, horizon: number, t: number, tint: string, strength: number) {
    const depth = h - horizon
    const cx = w / 2
    ctx.lineWidth = 1
    for (let i = 0; i < 26; i++) {
        const z = (i + ((t * 0.22) % 1)) / 26
        const y = horizon + depth * Math.pow(z, 2.3)
        ctx.strokeStyle = rgba(tint, z * 0.6 * strength)
        ctx.beginPath()
        ctx.moveTo(0, y)
        ctx.lineTo(w, y)
        ctx.stroke()
    }
    for (let k = -16; k <= 16; k++) {
        ctx.strokeStyle = rgba(tint, 0.22 * strength)
        ctx.beginPath()
        ctx.moveTo(cx + k * 6, horizon)
        ctx.lineTo(cx + k * (w / 9), h)
        ctx.stroke()
    }
}

// Level 1: Paris folding over itself; the upper city is the floor's mirror,
// hinged at the horizon, breathing between half-folded and nearly closed.
const foldingCity: Scene = (ctx, w, h, t, tint) => {
    const horizon = h * 0.56
    plane(ctx, w, h, horizon, t, tint, 1)
    const fold = 0.5 + 0.22 * Math.sin(t * 0.21)
    ctx.save()
    ctx.translate(0, horizon)
    ctx.scale(1, -fold)
    ctx.translate(0, -horizon)
    plane(ctx, w, h, horizon, t * 0.8, tint, 0.55)
    ctx.restore()
    glow(ctx, w / 2, horizon, Math.max(w, h) * 0.45, rgba(tint, 0.14))
}

// Level 2: the hotel corridor, frames rushing past while the hallway turns.
const corridor: Scene = (ctx, w, h, t, tint) => {
    const cx = w / 2
    const cy = h * 0.5
    glow(ctx, cx, cy, Math.min(w, h) * 0.35, rgba(tint, 0.2))
    ctx.lineWidth = 1.2
    for (let i = 0; i < 18; i++) {
        const z = (i + ((t * 0.3) % 1)) / 18
        const s = Math.pow(z, 2.6)
        const rw = w * 1.35 * s
        const rh = h * 1.35 * s
        ctx.save()
        ctx.translate(cx, cy)
        ctx.rotate(t * 0.1 + z * 1.1)
        ctx.strokeStyle = rgba(tint, Math.min(0.55, z * 0.6))
        ctx.strokeRect(-rw / 2, -rh / 2, rw, rh)
        ctx.restore()
    }
}

// Deterministic particles, so the server-rendered page and every visit agree.
const SAND = Array.from({ length: 150 }, (_, i) => {
    const r = (n: number) => {
        const x = Math.sin(i * 12.9898 + n * 78.233) * 43758.5453
        return x - Math.floor(x)
    }
    return { x: r(1), y: r(2), speed: 0.012 + r(3) * 0.03, size: 0.6 + r(4) * 1.6, phase: r(5) * Math.PI * 2 }
})

// Level 3: limbo, a slow shore of crumbling sand drifting up from the waves.
const limbo: Scene = (ctx, w, h, t, tint) => {
    glow(ctx, w * 0.5, h * 1.05, Math.max(w, h) * 0.7, rgba(tint, 0.16))
    for (const p of SAND) {
        const y = (((p.y - t * p.speed) % 1) + 1) % 1
        const x = p.x * w + Math.sin(t * 0.4 + p.phase) * 14
        ctx.fillStyle = rgba(tint, 0.15 + 0.5 * (1 - y))
        ctx.beginPath()
        ctx.arc(x, y * h, p.size, 0, Math.PI * 2)
        ctx.fill()
    }
    ctx.lineWidth = 1
    for (let j = 0; j < 7; j++) {
        const base = h * 0.74 + j * 16
        ctx.strokeStyle = rgba(tint, 0.3 - j * 0.035)
        ctx.beginPath()
        for (let x = 0; x <= w; x += 12) {
            const y = base + Math.sin(x * 0.008 + t * 0.5 + j * 0.7) * (5 + j * 1.5)
            if (x === 0) ctx.moveTo(x, y)
            else ctx.lineTo(x, y)
        }
        ctx.stroke()
    }
}

const SCENES: Scene[] = [foldingCity, corridor, limbo]
const TINTS = ['--level-1', '--level-2', '--level-3']
const FALLBACK = ['#8db4d8', '#5cc2b4', '#cdb48e']
// The frozen frame shown under reduced motion: a moment where each scene reads.
const STILL_T = 7

export function DreamCanvas({ scene }: { scene: number }) {
    const ref = useRef<HTMLCanvasElement>(null)
    const reduce = useReducedMotion()

    useEffect(() => {
        const canvas = ref.current
        const ctx = canvas?.getContext('2d')
        if (!canvas || !ctx) return
        const draw = SCENES[scene]
        const tint = getComputedStyle(document.documentElement).getPropertyValue(TINTS[scene]).trim() || FALLBACK[scene]
        const dpr = Math.min(window.devicePixelRatio || 1, 2)
        let raf = 0
        let visible = true
        const start = performance.now()

        const paint = (now: number) => {
            const w = canvas.clientWidth
            const h = canvas.clientHeight
            ctx.clearRect(0, 0, w, h)
            draw(ctx, w, h, reduce ? STILL_T : (now - start) / 1000, tint)
        }
        const loop = (now: number) => {
            paint(now)
            raf = requestAnimationFrame(loop)
        }
        const run = () => {
            cancelAnimationFrame(raf)
            if (reduce) paint(0)
            else if (visible && !document.hidden) raf = requestAnimationFrame(loop)
        }
        const resize = () => {
            canvas.width = Math.round(canvas.clientWidth * dpr)
            canvas.height = Math.round(canvas.clientHeight * dpr)
            ctx.setTransform(dpr, 0, 0, dpr, 0, 0)
            if (reduce) paint(0)
        }

        resize()
        const ro = new ResizeObserver(resize)
        ro.observe(canvas)
        const io = new IntersectionObserver(([entry]) => {
            visible = entry.isIntersecting
            run()
        })
        io.observe(canvas)
        document.addEventListener('visibilitychange', run)
        run()

        return () => {
            cancelAnimationFrame(raf)
            ro.disconnect()
            io.disconnect()
            document.removeEventListener('visibilitychange', run)
        }
    }, [scene, reduce])

    return <canvas ref={ref} className="block h-full w-full" aria-hidden="true" />
}

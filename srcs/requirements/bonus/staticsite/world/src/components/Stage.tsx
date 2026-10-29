import { useEffect, useRef } from 'react'
import { subscribe } from '../scroll'
import { onMotion } from '../motion'
import { probeTier } from '../engine/probe'

// The fixed stage behind the chapters: the 3D world when the browser can
// afford it, the still poster otherwise. three.js is downloaded only here,
// after the page has painted and gone idle, so the headline is the first
// thing on screen and nothing waits on WebGL. <html data-world> says which
// world is showing: pending, ready or none.
export function Stage() {
    const canvas = useRef<HTMLCanvasElement>(null)
    const dark = useRef<HTMLDivElement>(null)
    const bright = useRef<HTMLDivElement>(null)

    useEffect(() => {
        const root = document.documentElement
        const { tier, renderer } = probeTier()
        root.dataset.tier = tier
        if (renderer) root.dataset.renderer = renderer
        if (tier === 'none' || !canvas.current) {
            root.dataset.world = 'none'
            return
        }
        root.dataset.world = 'pending'
        let disposed = false
        let cleanup: Array<() => void> = []
        const start = () =>
            import('../engine/world').then(({ createWorld }) => {
                if (disposed || !canvas.current) return
                let reduced = false
                const world = createWorld({
                    canvas: canvas.current,
                    tier,
                    reducedMotion: reduced,
                    onReady: () => {
                        root.dataset.world = 'ready'
                    },
                    onVeil: (d, b) => {
                        dark.current?.style.setProperty('opacity', d.toFixed(3))
                        bright.current?.style.setProperty('opacity', b.toFixed(3))
                    },
                    onFail: () => {
                        root.dataset.world = 'none'
                    },
                })
                cleanup = [
                    subscribe((p) => world.setTarget(p.x)),
                    onMotion((r) => {
                        reduced = r
                        world.setReducedMotion(r)
                    }),
                    () => world.dispose(),
                ]
            }, () => {
                root.dataset.world = 'none'
            })
        // Safari has no requestIdleCallback: a short timeout stands in for it.
        const idle = (window as { requestIdleCallback?: Window['requestIdleCallback'] }).requestIdleCallback
        const handle = idle ? idle(start, { timeout: 1200 }) : window.setTimeout(start, 300)
        return () => {
            disposed = true
            if (idle) window.cancelIdleCallback(handle)
            else window.clearTimeout(handle)
            cleanup.forEach((fn) => fn())
        }
    }, [])

    return (
        <div className="stage" aria-hidden="true">
            <div className="poster">
                <span className="poster-city" />
                <span className="poster-fold" />
                <span className="poster-hall" />
                <span className="poster-limbo" />
            </div>
            <canvas ref={canvas} className="world" />
            <div ref={dark} className="veil veil-dark" />
            <div ref={bright} className="veil veil-bright" />
            <div className="vignette" />
        </div>
    )
}

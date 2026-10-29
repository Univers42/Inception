import { motion, type HTMLMotionProps } from 'framer-motion'

// Fades a block in once it scrolls into view. `data-reveal` lets styles.css
// show it at full opacity when JavaScript never ran (the server-rendered HTML
// carries the hidden starting state inline).
export function reveal(delay = 0) {
    return {
        'data-reveal': '',
        initial: { opacity: 0, y: 20 },
        whileInView: { opacity: 1, y: 0 },
        viewport: { once: true, margin: '0px 0px -12% 0px' },
        transition: { duration: 0.6, delay, ease: [0.22, 1, 0.36, 1] as const },
    }
}

export function Reveal({ delay = 0, ...props }: HTMLMotionProps<'div'> & { delay?: number }) {
    return <motion.div {...reveal(delay)} {...props} />
}

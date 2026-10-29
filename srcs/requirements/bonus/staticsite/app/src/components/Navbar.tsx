import { useEffect, useId, useState } from 'react'
import { AnimatePresence, motion, useMotionValueEvent, useScroll } from 'framer-motion'
import { LogIn, Menu, X } from 'lucide-react'
import { LINKS } from '../content'
import { Totem } from './Totem'

const NAV = [
    { label: 'Levels', href: '#levels' },
    { label: 'Stack', href: '#stack' },
    { label: 'Deeper', href: LINKS.deeper },
    { label: 'Blog', href: LINKS.blog },
    { label: 'Wiki', href: LINKS.wiki },
    { label: 'Lab', href: LINKS.lab },
]

export function Navbar({ spins }: { spins: number }) {
    const [scrolled, setScrolled] = useState(false)
    const [open, setOpen] = useState(false)
    const panelId = useId()
    const { scrollY } = useScroll()
    useMotionValueEvent(scrollY, 'change', (y) => setScrolled(y > 24))

    useEffect(() => {
        if (!open) return
        const onKey = (e: KeyboardEvent) => e.key === 'Escape' && setOpen(false)
        window.addEventListener('keydown', onKey)
        return () => window.removeEventListener('keydown', onKey)
    }, [open])

    return (
        <header className="fixed inset-x-0 top-0 z-[40] flex justify-center px-4 pt-[max(1rem,env(safe-area-inset-top))]">
            <nav
                aria-label="Primary"
                className={`glass relative flex w-full max-w-5xl items-center justify-between gap-4 rounded-full py-2 pr-2 pl-5 transition-shadow duration-300 ${scrolled ? 'shadow-[0_18px_40px_-18px_rgb(0_0_0/0.8)]' : ''}`}
            >
                <a href="/" className="flex min-h-[44px] items-center gap-2.5 font-medium tracking-tight">
                    <Totem spins={spins} />
                    <span className="text-[1.05rem]">inception</span>
                </a>

                <ul className="hidden items-center gap-1 md:flex">
                    {NAV.map((item) => (
                        <li key={item.href}>
                            <a href={item.href} className="inline-flex min-h-[44px] items-center rounded-full px-4 text-sm text-muted transition-colors duration-200 hover:bg-white/5 hover:text-text">
                                {item.label}
                            </a>
                        </li>
                    ))}
                </ul>

                <div className="flex items-center gap-2">
                    <a
                        href={LINKS.admin}
                        className="hidden min-h-[44px] items-center gap-1.5 rounded-full px-3 text-sm text-muted transition-colors duration-200 hover:bg-white/5 hover:text-text sm:inline-flex"
                    >
                        <LogIn size={15} aria-hidden="true" />
                        Sign in
                    </a>
                    <a href={LINKS.blog} className="btn btn-primary hidden sm:inline-flex">Read the blog</a>
                    <button
                        type="button"
                        className="inline-flex size-11 items-center justify-center rounded-full text-text hover:bg-white/5 md:hidden"
                        aria-expanded={open}
                        aria-controls={panelId}
                        aria-label={open ? 'Close menu' : 'Open menu'}
                        onClick={() => setOpen((v) => !v)}
                    >
                        {open ? <X size={20} aria-hidden="true" /> : <Menu size={20} aria-hidden="true" />}
                    </button>
                </div>

                <AnimatePresence>
                    {open && (
                        <motion.ul
                            id={panelId}
                            className="glass absolute inset-x-0 top-[calc(100%+0.5rem)] flex flex-col gap-1 rounded-3xl p-3 md:hidden"
                            initial={{ opacity: 0, y: -8, scale: 0.98 }}
                            animate={{ opacity: 1, y: 0, scale: 1 }}
                            exit={{ opacity: 0, y: -6, scale: 0.98, transition: { duration: 0.15 } }}
                            transition={{ duration: 0.22, ease: [0.16, 1, 0.3, 1] }}
                        >
                            {NAV.map((item) => (
                                <li key={item.href}>
                                    <a href={item.href} onClick={() => setOpen(false)} className="flex min-h-[48px] items-center rounded-2xl px-4 text-text hover:bg-white/5">
                                        {item.label}
                                    </a>
                                </li>
                            ))}
                            <li className="mt-1 border-t border-line pt-1">
                                <a href={LINKS.admin} onClick={() => setOpen(false)} className="flex min-h-[48px] items-center gap-2 rounded-2xl px-4 text-muted hover:bg-white/5 hover:text-text">
                                    <LogIn size={16} aria-hidden="true" />
                                    Sign in (maintainers)
                                </a>
                            </li>
                        </motion.ul>
                    )}
                </AnimatePresence>
            </nav>
        </header>
    )
}

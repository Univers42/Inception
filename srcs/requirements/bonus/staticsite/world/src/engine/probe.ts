// Which world this browser can afford, decided before three.js is downloaded.
//
// 'gpu': hardware WebGL2. 'software': WebGL through SwiftShader or llvmpipe,
// what Firefox gets on the 42 seats, whose GPU has no driver. 'none': no
// WebGL at all, which is what branded Chrome 139+ gets there (its automatic
// SwiftShader fallback is gone); the page then keeps its still frames.
//
// Caveat: the renderer string is only a starting point. A masked or spoofed
// one (privacy.resistFingerprinting, Safari's generic "Apple GPU") reads as
// 'gpu' even on a slow machine; the frame-time governor in world.ts is what
// corrects it, by lowering the resolution.
export type Tier = 'gpu' | 'software' | 'none'

const SOFTWARE = /swiftshader|llvmpipe|lavapipe|softpipe|software|basic render/i

export function probeTier(): { tier: Tier; renderer: string } {
    try {
        const canvas = document.createElement('canvas')
        const gl = canvas.getContext('webgl2')
        if (!gl) return { tier: 'none', renderer: '' }
        let renderer = String(gl.getParameter(gl.RENDERER))
        if (/^WebKit WebGL$/.test(renderer)) {
            const info = gl.getExtension('WEBGL_debug_renderer_info')
            if (info) renderer = String(gl.getParameter(info.UNMASKED_RENDERER_WEBGL))
        }
        gl.getExtension('WEBGL_lose_context')?.loseContext()
        return { tier: SOFTWARE.test(renderer) ? 'software' : 'gpu', renderer }
    } catch {
        return { tier: 'none', renderer: '' }
    }
}

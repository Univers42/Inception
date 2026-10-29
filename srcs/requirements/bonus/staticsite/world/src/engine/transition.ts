// Crossing between dream levels, on the GPU tier: a pass between the bloom and
// the tone map, so it works on the HDR image. Falling into the street is a
// rush (a zoom blur toward the centre, colour fringes at the edges) while an
// iris closes to black, and the corridor opens out of the same iris; walking
// into the corridor's last door floods the frame with a warm white, and limbo
// surfaces out of it. The software tier keeps the CSS veils, which cost
// nothing.
import { ShaderPass } from 'three/addons/postprocessing/ShaderPass.js'

export type Transition = ShaderPass & { set: (dark: number, bright: number, aspect: number, time: number) => void }

export function transitionPass(): Transition {
    const pass = new ShaderPass({
        uniforms: {
            tDiffuse: { value: null },
            uDark: { value: 0 },
            uBright: { value: 0 },
            uAspect: { value: 1 },
            uTime: { value: 0 },
        },
        vertexShader: /* glsl */ `
            varying vec2 vUv;
            void main() {
                vUv = uv;
                gl_Position = projectionMatrix * modelViewMatrix * vec4(position, 1.0);
            }`,
        fragmentShader: /* glsl */ `
            uniform sampler2D tDiffuse;
            uniform float uDark;
            uniform float uBright;
            uniform float uAspect;
            uniform float uTime;
            varying vec2 vUv;
            float hash(vec2 p) { return fract(sin(dot(p, vec2(12.9898, 78.233))) * 43758.5453); }
            void main() {
                vec2 d = vUv - 0.5;
                float warp = max(uDark, uBright);
                float r = length(d * vec2(uAspect, 1.0));
                vec3 c;
                if (warp < 0.002) {
                    c = texture2D(tDiffuse, vUv).rgb;
                } else {
                    // the rush: samples pulled toward the centre, weighted to the near end
                    c = vec3(0.0);
                    float total = 0.0;
                    for (int i = 0; i < 10; i++) {
                        float k = float(i) / 9.0;
                        float w = 1.0 - 0.6 * k;
                        c += texture2D(tDiffuse, 0.5 + d * (1.0 - warp * 0.32 * k)).rgb * w;
                        total += w;
                    }
                    c /= total;
                    // colour fringes, growing toward the edges
                    float ca = warp * 0.025 * r;
                    c.r = mix(c.r, texture2D(tDiffuse, 0.5 + d * (1.0 + ca)).r, warp);
                    c.b = mix(c.b, texture2D(tDiffuse, 0.5 + d * (1.0 - ca)).b, warp);
                }
                // the iris: a soft circle that closes to black as the fall ends
                float radius = 1.15 * (1.0 - uDark);
                c *= 1.0 - smoothstep(radius - 0.3, radius, r) * step(0.001, uDark);
                // the flood: warm white from the centre outward, past what the
                // tone map can hold, so it burns out rather than turning grey
                float flood = clamp(uBright * 1.6 - r * 0.8, 0.0, 1.0);
                c = mix(c, vec3(5.0, 4.6, 3.9), flood * flood);
                // a little grain while crossing: the frame stays a frame
                c += (hash(vUv * 731.0 + fract(uTime) * 61.0) - 0.5) * 0.04 * warp;
                gl_FragColor = vec4(c, 1.0);
            }`,
    }) as Transition
    pass.set = (dark, bright, aspect, time) => {
        const u = pass.uniforms
        u.uDark.value = dark
        u.uBright.value = bright
        u.uAspect.value = aspect
        u.uTime.value = time
    }
    return pass
}

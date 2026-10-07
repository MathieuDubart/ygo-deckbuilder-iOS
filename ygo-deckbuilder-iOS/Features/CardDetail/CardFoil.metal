#include <metal_stdlib>
#include <SwiftUI/SwiftUI_Metal.h>

using namespace metal;

// Brillance des cartes selon leur rareté, dessinée au pixel.
// `kind` : 0 aucune, 1 vernis (Rare), 2 holographique (Super/Ultra), 3 Secret,
//          4 prismatique (Starlight, Ghost, Collector's, Quarter Century).
// `tilt` : inclinaison de la carte, déjà ramenée à -1…1 côté Swift — elle déplace la lumière.

static float3 hueToRGB(float h) {
    float3 p = abs(fract(h + float3(1.0, 2.0 / 3.0, 1.0 / 3.0)) * 6.0 - 3.0);
    return clamp(p - 1.0, 0.0, 1.0);
}

static float sparkleNoise(float2 p) {
    float3 q = fract(float3(p.x, p.y, p.x) * 0.1031);
    q += dot(q, float3(q.y, q.z, q.x) + 33.33);
    return fract((q.x + q.y) * q.z);
}

[[ stitchable ]] half4 cardFoil(float2 position, half4 color, float2 size, float2 tilt,
                                float kind, float time) {
    if (kind < 0.5 || size.x <= 0.0 || size.y <= 0.0) {
        return half4(0.0h);
    }

    float2 uv = position / size;
    // Inclinaison déjà normalisée côté Swift : la lumière suit le poignet
    float2 light = clamp(tilt, -1.0, 1.0);

    // Position dans la bande lumineuse diagonale. `pow` n'aime pas les bases négatives
    // quand MTL_FAST_MATH est actif : on élève au carré à la main.
    float d = uv.x + uv.y * 0.6 - light.x * 0.9 + light.y * 0.5;
    float band = (d - 0.8) * 2.4;
    float sweep = exp(-band * band);

    float3 rgb = float3(1.0);
    float alpha = 0.0;

    if (kind < 1.5) {
        // Vernis : un simple reflet blanc, discret
        alpha = sweep * 0.22;
    } else if (kind < 2.5) {
        // Holographique : reflet teinté qui glisse avec l'inclinaison
        float hue = d * 0.45 + time * 0.03;
        rgb = mix(float3(1.0), hueToRGB(hue), 0.55);
        alpha = sweep * 0.42;
    } else if (kind < 3.5) {
        // Secret : fines rayures diagonales irisées
        float stripes = 0.5 + 0.5 * sin((uv.x - uv.y) * 150.0 + light.x * 8.0);
        float hue = d * 0.9 + stripes * 0.12 + time * 0.04;
        rgb = hueToRGB(hue);
        alpha = (sweep * 0.5 + 0.12) * (0.45 + 0.55 * stripes);
    } else {
        // Prismatique : arc-en-ciel large, rayures serrées et paillettes
        float stripes = 0.5 + 0.5 * sin((uv.x * 0.6 - uv.y) * 220.0 + light.y * 10.0);
        float hue = d * 1.3 + stripes * 0.18 + time * 0.06;
        rgb = hueToRGB(hue);
        alpha = (sweep * 0.55 + 0.2) * (0.5 + 0.5 * stripes);
        float grain = sparkleNoise(floor(uv * size * 0.35) + floor(time * 5.0));
        if (grain > 0.986) {
            rgb = float3(1.0);
            alpha = min(alpha + 0.5, 0.95);
        }
    }

    // Les bords restent nets : la brillance s'éteint sur quelques pixels
    float edge = smoothstep(0.0, 0.02, uv.x) * (1.0 - smoothstep(0.98, 1.0, uv.x))
        * smoothstep(0.0, 0.015, uv.y) * (1.0 - smoothstep(0.985, 1.0, uv.y));
    alpha *= edge * float(color.a);

    return half4(half3(rgb * alpha), half(alpha));
}

#include <metal_stdlib>
#include <RealityKit/RealityKit.h>

using namespace metal;

// Surface des cartes en 3D (RealityKit, CustomMaterial).
//
// La dorure n'est pas un filtre posé sur l'image : elle suit la géométrie. La direction de
// vue projetée dans le plan de la carte donne l'inclinaison physique, donc la bande lumineuse
// se déplace comme sur une vraie carte qu'on bouge dans la main.
//
// custom_parameter : x = traitement (CardFoil.rawValue), y = force 0…1,
//                    z = 1 si les UV sont retournés verticalement, w = inutilisé.

constant float kCardAspect = 59.0 / 86.0;  // largeur / hauteur d'une carte

// Zones d'une carte moderne, en UV (origine en haut à gauche) : x0, y0, x1, y1.
constant float4 kNameBox = float4(0.062, 0.036, 0.805, 0.100);
constant float4 kArtBox = float4(0.117, 0.145, 0.883, 0.639);
constant float4 kBorderBox = float4(0.055, 0.030, 0.945, 0.965);

// Sens de balayage de la bande lumineuse. `view_direction` n'étant pas documentée comme
// allant de la surface vers la caméra ou l'inverse, c'est la seule valeur à passer à -1.0
// si la lumière part du mauvais côté quand on incline la carte.
constant float kLeanSign = 1.0;

// Traitements, alignés sur CardFoil.rawValue côté Swift.
constant int kNone = 0;
constant int kRareName = 1;
constant int kSuperArt = 2;
constant int kUltra = 3;
constant int kUltimate = 4;
constant int kSecret = 5;
constant int kPrismatic = 6;
constant int kGhost = 7;
constant int kStarlight = 8;
constant int kMosaic = 9;
constant int kStarfoil = 10;
constant int kShatter = 11;
constant int kGold = 12;

static float3 hueToRGB(float h) {
    float3 p = abs(fract(h + float3(1.0, 2.0 / 3.0, 1.0 / 3.0)) * 6.0 - 3.0);
    return clamp(p - 1.0, 0.0, 1.0);
}

static float hash12(float2 p) {
    float3 q = fract(float3(p.x, p.y, p.x) * 0.1031);
    q += dot(q, float3(q.y, q.z, q.x) + 33.33);
    return fract((q.x + q.y) * q.z);
}

/// Masque doux d'une zone rectangulaire.
static float boxMask(float2 uv, float4 box, float feather) {
    float2 lo = smoothstep(box.xy - feather, box.xy + feather, uv);
    float2 hi = 1.0 - smoothstep(box.zw - feather, box.zw + feather, uv);
    return lo.x * lo.y * hi.x * hi.y;
}

/// Distance signée au rectangle arrondi de la carte (négatif = dans le carton).
static float cardCornerSDF(float2 uv, float radius) {
    float2 p = (uv - 0.5) * float2(1.0, 1.0 / kCardAspect);
    float2 halfSize = float2(0.5, 0.5 / kCardAspect) - radius;
    float2 d = abs(p) - halfSize;
    return length(max(d, 0.0)) + min(max(d.x, d.y), 0.0) - radius;
}

/// Motif de la dorure, son relief, et le gradient analytique du motif. Le gradient est
/// calculé à la main plutôt qu'avec dfdx/dfdy : les dérivées ne sont pas disponibles dans une
/// fonction `[[visible]]`, et sur des motifs aussi fins elles ne donneraient que de l'aliasing.
struct FoilPattern {
    float value;
    float2 gradient;
    float relief;
    float hueShift;
};

static FoilPattern patternFor(int kind, float2 uv) {
    FoilPattern out;
    out.value = 1.0;
    out.gradient = float2(0.0);
    out.relief = 0.0;
    out.hueShift = 0.0;

    if (kind == kSecret || kind == kPrismatic) {
        // Secret / Prismatic : lignes diagonales très fines
        float density = (kind == kPrismatic) ? 620.0 : 420.0;
        out.value = 0.45 + 0.55 * (0.5 + 0.5 * sin((uv.x - uv.y) * density));
        out.hueShift = out.value * 0.25;
    } else if (kind == kStarlight) {
        // Starlight / Collector's / Quarter Century : micro-relief croisé
        float a = 760.0;
        out.value = 0.5 + 0.5 * sin(uv.x * a) * sin(uv.y * a);
        out.gradient = 0.5 * a * float2(cos(uv.x * a) * sin(uv.y * a),
                                        sin(uv.x * a) * cos(uv.y * a));
        out.relief = 0.55;
        out.hueShift = out.value * 0.4;
    } else if (kind == kUltimate) {
        // Ultimate : gaufrage large, le relief prime sur la couleur
        out.value = 0.6 + 0.4 * sin(uv.x * 90.0) * sin(uv.y * 120.0);
        out.gradient = 0.4 * float2(90.0 * cos(uv.x * 90.0) * sin(uv.y * 120.0),
                                    120.0 * sin(uv.x * 90.0) * cos(uv.y * 120.0));
        out.relief = 0.8;
    } else if (kind == kMosaic) {
        // Mosaic : grain carré régulier
        out.value = 0.35 + 0.65 * hash12(floor(uv * float2(180.0, 260.0)));
    } else if (kind == kStarfoil) {
        // Starfoil : semis d'étoiles
        float2 grid = uv * float2(26.0, 38.0);
        float2 local = fract(grid) - 0.5;
        float shape = 1.0 - smoothstep(0.0, 0.34,
                                       min(abs(local.x) + abs(local.y), length(local) * 1.6));
        out.value = 0.25 + 0.75 * (hash12(floor(grid)) > 0.82 ? shape : 0.0);
    } else if (kind == kShatter) {
        // Shatterfoil : éclats
        float crack = sin(uv.x * 190.0 + sin(uv.y * 23.0) * 7.0)
            + sin(uv.y * 150.0 + sin(uv.x * 17.0) * 5.0);
        out.value = 0.3 + 0.7 * smoothstep(0.2, 1.6, abs(crack));
    } else if (kind == kGhost) {
        // Ghost : relief doux, presque sans couleur
        out.value = 0.5 + 0.5 * sin(uv.y * 240.0);
        out.gradient = float2(0.0, 0.5 * 240.0 * cos(uv.y * 240.0));
        out.relief = 0.6;
    }
    return out;
}

/// Zone vernie, selon le traitement.
static float regionMask(int kind, float2 uv) {
    float name = boxMask(uv, kNameBox, 0.006);
    float art = boxMask(uv, kArtBox, 0.008);
    if (kind == kRareName) { return name; }
    if (kind == kSuperArt || kind == kGhost) { return art; }
    if (kind == kUltra || kind == kUltimate) { return max(art, name); }
    if (kind == kGold) { return max(name, 1.0 - boxMask(uv, kBorderBox, 0.01)); }
    return 1.0;  // Secret et dérivés : toute la carte
}

/// Couleur dominante du traitement, avant irisation.
static float3 tintFor(int kind) {
    if (kind == kRareName || kind == kUltra || kind == kUltimate || kind == kGold) {
        return float3(1.0, 0.82, 0.38);   // doré
    }
    if (kind == kGhost) {
        return float3(0.86, 0.90, 0.94);  // argenté
    }
    return float3(1.0);
}

/// Repère du plan de la carte. `generateBox` ne garantit pas les tangentes : sans elles on
/// obtiendrait des NaN, donc on retombe sur les axes de la face avant.
static void cardFrame(realitykit::surface_parameters params, thread float3 &t, thread float3 &b) {
    float3 rawT = params.geometry().tangent();
    float3 rawB = params.geometry().bitangent();
    if (dot(rawT, rawT) < 1e-6 || dot(rawB, rawB) < 1e-6) {
        t = float3(1.0, 0.0, 0.0);
        b = float3(0.0, 1.0, 0.0);
    } else {
        t = normalize(rawT);
        b = normalize(rawB);
    }
}

/// Face avant : illustration, dorure de la rareté, coins arrondis.
[[visible]]
void cardFrontSurface(realitykit::surface_parameters params)
{
    constexpr sampler cardSampler(coord::normalized, address::clamp_to_edge,
                                  filter::linear, mip_filter::linear);

    float4 settings = params.uniforms().custom_parameter();
    int kind = int(settings.x + 0.5);
    float strength = settings.y;

    float2 uv = params.geometry().uv0();
    if (settings.z > 0.5) { uv.y = 1.0 - uv.y; }

    params.surface().set_base_color(params.textures().base_color().sample(cardSampler, uv).rgb);
    params.surface().set_metallic(0.0h);

    // Coins arrondis : le carton s'arrête avant le coin du rectangle
    params.surface().set_opacity(cardCornerSDF(uv, 0.055) < 0.0 ? 1.0h : 0.0h);

    if (kind == kNone || strength <= 0.0) {
        params.surface().set_roughness(0.62h);
        params.surface().set_emissive_color(half3(0.0h));
        return;
    }

    float mask = regionMask(kind, uv) * strength;

    // Inclinaison réelle : direction de vue projetée dans le plan de la carte
    float3 n = normalize(params.geometry().normal());
    float3 v = normalize(params.geometry().view_direction());
    float3 t;
    float3 b;
    cardFrame(params, t, b);
    float2 lean = kLeanSign * float2(dot(v, t), dot(v, b));
    float grazing = 1.0 - saturate(abs(dot(n, v)));

    FoilPattern pattern = patternFor(kind, uv);

    // Bande lumineuse : elle balaie la carte quand on la tourne
    float band = (uv.x - 0.5) * 1.1 + (uv.y - 0.5) * 0.75 - lean.x * 1.7 + lean.y * 1.2;
    float sweep = exp(-band * band * 2.0);

    // Irisation : la teinte dépend de l'angle de vue, comme une vraie diffraction
    float hue = band * 0.5 + grazing * 0.9 + pattern.hueShift;
    float3 tint = tintFor(kind);
    // Un doré reste doré : on ne l'irise que légèrement
    float colorMix = (kind == kRareName || kind == kGold) ? 0.18 : 0.75;
    float3 rgb = mix(tint, hueToRGB(hue) * tint, colorMix);

    float shine = mask * pattern.value * (sweep * 0.75 + 0.25 * grazing);
    params.surface().set_emissive_color(half3(rgb * shine * 0.9));

    // La dorure est plus lisse que le carton : elle accroche davantage la lumière
    params.surface().set_roughness(half(mix(0.62, 0.10, mask * pattern.value)));

    // Gaufrage : on incline la normale au rythme du motif
    if (pattern.relief > 0.0) {
        float2 slope = pattern.gradient * pattern.relief * mask * 0.02;
        params.surface().set_normal(normalize(float3(-slope, 1.0)));
    }
}

/// Dos de la carte : la texture du dos, avec un vernis léger.
[[visible]]
void cardBackSurface(realitykit::surface_parameters params)
{
    constexpr sampler cardSampler(coord::normalized, address::clamp_to_edge,
                                  filter::linear, mip_filter::linear);

    float4 settings = params.uniforms().custom_parameter();
    float2 uv = params.geometry().uv0();
    if (settings.z > 0.5) { uv.y = 1.0 - uv.y; }
    uv.x = 1.0 - uv.x;

    params.surface().set_base_color(params.textures().base_color().sample(cardSampler, uv).rgb);
    params.surface().set_metallic(0.0h);
    params.surface().set_roughness(0.55h);
    params.surface().set_emissive_color(half3(0.0h));
    params.surface().set_opacity(cardCornerSDF(uv, 0.055) < 0.0 ? 1.0h : 0.0h);
}

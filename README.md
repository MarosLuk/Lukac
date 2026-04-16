# Lukac · Blueprint → 3D

Tri verzie blueprintu s integrovanou 3D vizualizáciou (Three.js).

## Live demo

- **Landing:** https://marosluk.github.io/Lukac/
- **v1 — Prechodový kus:** https://marosluk.github.io/Lukac/v1/
- **v2 — Montáž brány:** https://marosluk.github.io/Lukac/v2/
- **v3 — Interaktívna brána:** https://marosluk.github.io/Lukac/v3/

## Branches

| Branch | Popis |
|---|---|
| `main` | Landing + všetky 3 verzie v podpriečinkoch `v1/`, `v2/`, `v3/` (slúži pre GitHub Pages) |
| `version1` | Prechodový kus — 3-pohľadový výkres + auto-rotujúci 3D model |
| `version2` | Montáž brány — staggered fly-in animácia zostavy |
| `version3` | Interaktívna brána — orbit kontrola + klik-na-diel fokus |

## Štruktúra

```
.
├── index.html        # Landing page s odkazmi na verzie
├── .nojekyll         # Zakáže Jekyll (aby Pages servovalo podpriečinky)
├── v1/index.html     # Version 1
├── v2/index.html     # Version 2
└── v3/index.html     # Version 3
```

## Stack

- Čistý HTML + CSS + JavaScript (žiadny build)
- Three.js r160 (CDN, classic build)
- SVG animácie pre blueprint pohľady
- Framer-Motion nie je — všetky animácie sú manuálne via `requestAnimationFrame`

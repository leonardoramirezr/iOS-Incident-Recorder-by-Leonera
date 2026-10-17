// Genera los SVG de las opciones de ícono. Uso: node gen.js && node render.js
const fs = require('fs'), path = require('path');

const svg = (defs, body) => `<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 1024 1024" width="1024" height="1024">
<defs>${COMMON}${defs}</defs>${body}</svg>\n`;

// Gradientes y filtros compartidos
const COMMON = `
<linearGradient id="metal" x1="0" y1="0" x2="0.4" y2="1">
  <stop offset="0" stop-color="#F5F5F7"/><stop offset="0.35" stop-color="#B8B8BE"/>
  <stop offset="0.6" stop-color="#6E6E73"/><stop offset="1" stop-color="#2C2C2E"/></linearGradient>
<linearGradient id="metalRev" x1="0" y1="1" x2="0.3" y2="0">
  <stop offset="0" stop-color="#E5E5EA"/><stop offset="0.5" stop-color="#636366"/><stop offset="1" stop-color="#1C1C1E"/></linearGradient>
<radialGradient id="glass" cx="0.36" cy="0.3" r="0.85">
  <stop offset="0" stop-color="#4A6AA8"/><stop offset="0.25" stop-color="#1B2A4F"/>
  <stop offset="0.6" stop-color="#070B17"/><stop offset="1" stop-color="#000"/></radialGradient>
<radialGradient id="glassInner" cx="0.6" cy="0.65" r="0.7">
  <stop offset="0" stop-color="#5B2A7A" stop-opacity="0.9"/><stop offset="0.5" stop-color="#13183A"/><stop offset="1" stop-color="#02030A"/></radialGradient>
<linearGradient id="flare" x1="0" y1="0" x2="1" y2="1">
  <stop offset="0" stop-color="#7CF3C8"/><stop offset="0.5" stop-color="#8E7CFF"/><stop offset="1" stop-color="#FF7CC8"/></linearGradient>
<radialGradient id="recBall" cx="0.38" cy="0.3" r="0.8">
  <stop offset="0" stop-color="#FF9A8F"/><stop offset="0.35" stop-color="#FF3B30"/><stop offset="1" stop-color="#A30E06"/></radialGradient>
<radialGradient id="redGlow" cx="0.5" cy="0.5" r="0.5">
  <stop offset="0" stop-color="#FF453A" stop-opacity="0.9"/><stop offset="0.4" stop-color="#FF3B30" stop-opacity="0.35"/><stop offset="1" stop-color="#FF3B30" stop-opacity="0"/></radialGradient>
<linearGradient id="gloss" x1="0" y1="0" x2="0" y2="1">
  <stop offset="0" stop-color="#fff" stop-opacity="0.7"/><stop offset="1" stop-color="#fff" stop-opacity="0"/></linearGradient>
<filter id="shadow" x="-30%" y="-30%" width="160%" height="170%">
  <feDropShadow dx="0" dy="28" stdDeviation="30" flood-color="#000" flood-opacity="0.55"/></filter>
<filter id="softShadow" x="-30%" y="-30%" width="160%" height="160%">
  <feDropShadow dx="0" dy="10" stdDeviation="12" flood-color="#000" flood-opacity="0.45"/></filter>
<filter id="blur20"><feGaussianBlur stdDeviation="20"/></filter>
<filter id="blur6"><feGaussianBlur stdDeviation="6"/></filter>
`;

// Lente de cámara detallada
function lens(cx, cy, r) {
  const ticks = Array.from({ length: 60 }, (_, i) => {
    const a = (i / 60) * Math.PI * 2, r1 = r * 0.86, r2 = r * 0.93;
    return `<line x1="${cx + r1 * Math.cos(a)}" y1="${cy + r1 * Math.sin(a)}" x2="${cx + r2 * Math.cos(a)}" y2="${cy + r2 * Math.sin(a)}"/>`;
  }).join('');
  return `<g>
  <circle cx="${cx}" cy="${cy}" r="${r}" fill="url(#metal)"/>
  <circle cx="${cx}" cy="${cy}" r="${r * 0.95}" fill="#1C1C1E"/>
  <g stroke="#48484A" stroke-width="${r * 0.012}">${ticks}</g>
  <circle cx="${cx}" cy="${cy}" r="${r * 0.82}" fill="url(#metalRev)"/>
  <circle cx="${cx}" cy="${cy}" r="${r * 0.76}" fill="url(#glass)"/>
  <circle cx="${cx}" cy="${cy}" r="${r * 0.5}" fill="url(#glassInner)" stroke="#2C3B66" stroke-width="${r * 0.025}"/>
  <circle cx="${cx}" cy="${cy}" r="${r * 0.26}" fill="#000" stroke="#1E2748" stroke-width="${r * 0.02}"/>
  <path d="M ${cx - r * 0.62} ${cy + r * 0.12} A ${r * 0.63} ${r * 0.63} 0 0 0 ${cx + r * 0.1} ${cy + r * 0.62}"
        fill="none" stroke="url(#flare)" stroke-width="${r * 0.05}" stroke-linecap="round" opacity="0.55"/>
  <ellipse cx="${cx - r * 0.3}" cy="${cy - r * 0.34}" rx="${r * 0.26}" ry="${r * 0.13}" fill="#fff" opacity="0.32" transform="rotate(-38 ${cx - r * 0.3} ${cy - r * 0.34})"/>
  <circle cx="${cx + r * 0.3}" cy="${cy + r * 0.28}" r="${r * 0.05}" fill="#fff" opacity="0.5"/>
  <circle cx="${cx - r * 0.12}" cy="${cy - r * 0.12}" r="${r * 0.035}" fill="#fff" opacity="0.7"/>
</g>`;
}

// Luz roja de grabación con resplandor
const recLight = (cx, cy, r) => `
  <circle cx="${cx}" cy="${cy}" r="${r * 3}" fill="url(#redGlow)"/>
  <circle cx="${cx}" cy="${cy}" r="${r * 1.18}" fill="#3A0A08"/>
  <circle cx="${cx}" cy="${cy}" r="${r}" fill="url(#recBall)"/>
  <ellipse cx="${cx - r * 0.25}" cy="${cy - r * 0.42}" rx="${r * 0.45}" ry="${r * 0.25}" fill="#fff" opacity="0.6"/>`;

// Polígono con esquinas redondeadas
function roundedPoly(pts, r) {
  let d = '';
  pts.forEach((p, i) => {
    const prev = pts[(i + pts.length - 1) % pts.length], next = pts[(i + 1) % pts.length];
    const toward = (a, b, dist) => { const dx = b[0] - a[0], dy = b[1] - a[1], l = Math.hypot(dx, dy); return [a[0] + dx / l * dist, a[1] + dy / l * dist]; };
    const a = toward(p, prev, r), b = toward(p, next, r);
    d += `${i ? 'L' : 'M'} ${a[0].toFixed(1)} ${a[1].toFixed(1)} Q ${p[0]} ${p[1]} ${b[0].toFixed(1)} ${b[1].toFixed(1)} `;
  });
  return d + 'Z';
}

const out = {};

// 1. Triángulo de advertencia con lente: el incidente visto por la cámara
{
  const tri = roundedPoly([[512, 150], [890, 820], [134, 820]], 80);
  const triIn = roundedPoly([[512, 205], [842, 790], [182, 790]], 62);
  out['1-alerta-lente'] = svg(`
<radialGradient id="bg1" cx="0.5" cy="0.42" r="0.75">
  <stop offset="0" stop-color="#3D2410"/><stop offset="0.55" stop-color="#140C07"/><stop offset="1" stop-color="#000"/></radialGradient>
<linearGradient id="amber" x1="0" y1="0" x2="0" y2="1">
  <stop offset="0" stop-color="#FFE27A"/><stop offset="0.45" stop-color="#FFB020"/><stop offset="1" stop-color="#E06A00"/></linearGradient>
<linearGradient id="amberSide" x1="0" y1="0" x2="0" y2="1">
  <stop offset="0" stop-color="#B85200"/><stop offset="1" stop-color="#6E2E00"/></linearGradient>
<clipPath id="triClip"><path d="${tri}"/></clipPath>`, `
<rect width="1024" height="1024" fill="url(#bg1)"/>
<circle cx="512" cy="500" r="420" fill="#FF9F0A" opacity="0.18" filter="url(#blur20)"/>
<g filter="url(#shadow)">
  <path d="${tri}" fill="url(#amberSide)" transform="translate(0 22)"/>
  <path d="${tri}" fill="url(#amber)"/>
</g>
<path d="${triIn}" fill="none" stroke="#7A3500" stroke-opacity="0.35" stroke-width="10"/>
<path d="${tri}" fill="none" stroke="#FFF6D6" stroke-opacity="0.8" stroke-width="5"/>
<g clip-path="url(#triClip)"><ellipse cx="440" cy="250" rx="420" ry="190" fill="url(#gloss)" opacity="0.45"/></g>
<g filter="url(#softShadow)">${lens(512, 575, 175)}</g>
${recLight(512, 318, 34)}
`);
}

// 2. Videocámara con insignia de incidente
{
  const badge = roundedPoly([[760, 600], [915, 875], [605, 875]], 34);
  out['2-camara-incidente'] = svg(`
<linearGradient id="bg2" x1="0" y1="0" x2="0.3" y2="1">
  <stop offset="0" stop-color="#22345E"/><stop offset="0.6" stop-color="#0C1428"/><stop offset="1" stop-color="#04060D"/></linearGradient>
<linearGradient id="body" x1="0" y1="0" x2="0" y2="1">
  <stop offset="0" stop-color="#5A5A60"/><stop offset="0.12" stop-color="#3A3A3E"/><stop offset="1" stop-color="#121214"/></linearGradient>
<linearGradient id="amber2" x1="0" y1="0" x2="0" y2="1">
  <stop offset="0" stop-color="#FFE27A"/><stop offset="0.5" stop-color="#FFB020"/><stop offset="1" stop-color="#E06A00"/></linearGradient>
<pattern id="grip" width="18" height="18" patternUnits="userSpaceOnUse">
  <rect width="18" height="18" fill="#1A1A1C"/><circle cx="9" cy="9" r="3.5" fill="#2E2E31"/></pattern>`, `
<rect width="1024" height="1024" fill="url(#bg2)"/>
<circle cx="300" cy="230" r="300" fill="#3D6BFF" opacity="0.18" filter="url(#blur20)"/>
<g filter="url(#shadow)">
  <rect x="330" y="205" width="364" height="70" rx="35" fill="url(#body)" stroke="#6E6E73" stroke-width="3"/>
  <rect x="360" y="255" width="44" height="80" fill="#2A2A2D"/><rect x="620" y="255" width="44" height="80" fill="#2A2A2D"/>
  <rect x="150" y="310" width="724" height="500" rx="110" fill="url(#body)"/>
</g>
<rect x="150" y="310" width="724" height="500" rx="110" fill="none" stroke="#8E8E93" stroke-opacity="0.6" stroke-width="4"/>
<rect x="176" y="560" width="70" height="200" rx="30" fill="url(#grip)"/>
<rect x="778" y="560" width="70" height="200" rx="30" fill="url(#grip)"/>
<rect x="190" y="335" width="644" height="70" rx="35" fill="url(#gloss)" opacity="0.18"/>
${lens(512, 565, 225)}
${recLight(784, 392, 26)}
<text x="740" y="402" text-anchor="end" font-family="Helvetica, Arial, sans-serif" font-weight="800" font-size="34" fill="#FF453A" letter-spacing="2">REC</text>
<g filter="url(#softShadow)">
  <path d="${badge}" fill="#fff"/>
  <path d="${roundedPoly([[760, 628], [892, 860], [628, 860]], 26)}" fill="url(#amber2)"/>
</g>
<rect x="747" y="700" width="26" height="92" rx="13" fill="#2B1400"/>
<circle cx="760" cy="822" r="16" fill="#2B1400"/>
<path d="${roundedPoly([[760, 628], [892, 860], [628, 860]], 26)}" fill="none" stroke="#FFF6D6" stroke-opacity="0.7" stroke-width="3"/>
`);
}

// 3. Torreta de emergencia con lente dentro del domo
{
  const dome = 'M 312 720 L 312 470 C 312 330 400 250 512 250 C 624 250 712 330 712 470 L 712 720 Z';
  const ribs = Array.from({ length: 9 }, (_, i) => `<line x1="${352 + i * 40}" y1="260" x2="${352 + i * 40}" y2="720"/>`).join('');
  const bokeh = [[150, 180, 40, '#FF453A'], [880, 140, 28, '#0A84FF'], [120, 640, 22, '#0A84FF'], [900, 600, 36, '#FF453A'], [820, 300, 16, '#FFD60A']]
    .map(([x, y, r, c]) => `<circle cx="${x}" cy="${y}" r="${r}" fill="${c}" opacity="0.25" filter="url(#blur6)"/>`).join('');
  out['3-torreta'] = svg(`
<linearGradient id="bg3" x1="0" y1="0" x2="0" y2="1">
  <stop offset="0" stop-color="#101A3A"/><stop offset="1" stop-color="#02030A"/></linearGradient>
<linearGradient id="domeGlass" x1="0" y1="0" x2="1" y2="0">
  <stop offset="0" stop-color="#8E0B05" stop-opacity="0.95"/><stop offset="0.28" stop-color="#FF3B30" stop-opacity="0.55"/>
  <stop offset="0.5" stop-color="#FF6A5E" stop-opacity="0.22"/><stop offset="0.72" stop-color="#FF3B30" stop-opacity="0.55"/><stop offset="1" stop-color="#6E0804" stop-opacity="0.95"/></linearGradient>
<linearGradient id="ray" x1="0" y1="0" x2="1" y2="0">
  <stop offset="0" stop-color="#FF3B30" stop-opacity="0"/><stop offset="1" stop-color="#FF3B30" stop-opacity="0.75"/></linearGradient>
<linearGradient id="base" x1="0" y1="0" x2="0" y2="1">
  <stop offset="0" stop-color="#F2F2F7"/><stop offset="0.3" stop-color="#AEAEB2"/><stop offset="0.7" stop-color="#48484A"/><stop offset="1" stop-color="#1C1C1E"/></linearGradient>
<clipPath id="domeClip"><path d="${dome}"/></clipPath>`, `
<rect width="1024" height="1024" fill="url(#bg3)"/>
${bokeh}
<path d="M 0 330 L 400 450 L 400 560 L 0 700 Z" fill="url(#ray)" opacity="0.7" filter="url(#blur6)"/>
<path d="M 0 330 L 400 450 L 400 560 L 0 700 Z" fill="url(#ray)" opacity="0.7" filter="url(#blur6)" transform="translate(1024 0) scale(-1 1)"/>
<ellipse cx="512" cy="480" rx="330" ry="300" fill="#FF3B30" opacity="0.35" filter="url(#blur20)"/>
<g filter="url(#shadow)">
  <path d="M 230 720 L 794 720 L 834 840 L 190 840 Z" fill="url(#base)"/>
  <rect x="180" y="830" width="664" height="40" rx="16" fill="#1C1C1E"/>
  <path d="${dome}" fill="#3A0402"/>
</g>
${lens(512, 500, 150)}
<path d="${dome}" fill="url(#domeGlass)"/>
<g clip-path="url(#domeClip)">
  <g stroke="#FFB4AE" stroke-opacity="0.18" stroke-width="6">${ribs}</g>
  <rect x="340" y="270" width="60" height="440" rx="30" fill="#fff" opacity="0.35"/>
  <rect x="420" y="290" width="18" height="400" rx="9" fill="#fff" opacity="0.25"/>
  <ellipse cx="512" cy="270" rx="200" ry="60" fill="url(#gloss)" opacity="0.5"/>
</g>
<path d="${dome}" fill="none" stroke="#FFD0CB" stroke-opacity="0.6" stroke-width="5"/>
<rect x="290" y="705" width="444" height="34" rx="12" fill="url(#base)"/>
${recLight(512, 780, 24)}
`);
}

// 4. Visor de grabación con cinta de incidente
{
  const tape = (rot) => `<g transform="rotate(${rot} 512 560)" filter="url(#softShadow)">
    <rect x="-200" y="505" width="1424" height="110" fill="url(#tapeFill)"/>
    <rect x="-200" y="505" width="1424" height="12" fill="#1C1C1E"/><rect x="-200" y="603" width="1424" height="12" fill="#1C1C1E"/>
    ${[-760, -375, 375, 760].map(dx => `<text x="${512 + dx}" y="574" text-anchor="middle" font-family="Helvetica, Arial, sans-serif" font-weight="900" font-size="44" letter-spacing="3" fill="#1C1C1E">INCIDENTE</text>`).join('')}
    ${[-568, 568].map(dx => `<text x="${512 + dx}" y="572" text-anchor="middle" font-family="Helvetica, Arial, sans-serif" font-size="34" fill="#1C1C1E">▲</text>`).join('')}
    <rect x="-200" y="505" width="1424" height="45" fill="#fff" opacity="0.18"/>
  </g>`;
  const brackets = [[150, 150, 1, 1], [874, 150, -1, 1], [150, 874, 1, -1], [874, 874, -1, -1]]
    .map(([x, y, sx, sy]) => `<path d="M ${x} ${y + sy * 90} L ${x} ${y} L ${x + sx * 90} ${y}" fill="none" stroke="#fff" stroke-width="14" stroke-linecap="round" stroke-linejoin="round"/>`).join('');
  out['4-visor-cinta'] = svg(`
<radialGradient id="bg4" cx="0.5" cy="0.45" r="0.8">
  <stop offset="0" stop-color="#2A2F3A"/><stop offset="0.6" stop-color="#0E1117"/><stop offset="1" stop-color="#000"/></radialGradient>
<linearGradient id="tapeFill" x1="0" y1="0" x2="0" y2="1">
  <stop offset="0" stop-color="#FFE45C"/><stop offset="1" stop-color="#F5B800"/></linearGradient>
<pattern id="scan" width="8" height="8" patternUnits="userSpaceOnUse"><rect width="8" height="1.5" fill="#fff" opacity="0.04"/></pattern>
<radialGradient id="ringRed" cx="0.4" cy="0.3" r="0.9">
  <stop offset="0" stop-color="#FF8A80"/><stop offset="0.4" stop-color="#FF3B30"/><stop offset="1" stop-color="#8E0B05"/></radialGradient>`, `
<rect width="1024" height="1024" fill="url(#bg4)"/>
<rect width="1024" height="1024" fill="url(#scan)"/>
${tape(-24)}
${tape(24)}
<circle cx="512" cy="540" r="290" fill="#FF3B30" opacity="0.3" filter="url(#blur20)"/>
<g filter="url(#shadow)"><circle cx="512" cy="540" r="215" fill="url(#metal)"/></g>
<circle cx="512" cy="540" r="196" fill="#1C1C1E"/>
<circle cx="512" cy="540" r="168" fill="url(#ringRed)"/>
<ellipse cx="470" cy="452" rx="105" ry="55" fill="#fff" opacity="0.45" transform="rotate(-20 470 452)"/>
<circle cx="512" cy="540" r="168" fill="none" stroke="#FFB4AE" stroke-opacity="0.5" stroke-width="4"/>
${brackets}
<circle cx="200" cy="230" r="20" fill="#FF3B30"/><circle cx="200" cy="230" r="44" fill="url(#redGlow)"/>
<text x="236" y="245" font-family="Helvetica, Arial, sans-serif" font-weight="800" font-size="46" fill="#fff" letter-spacing="3">REC</text>
<g transform="translate(720 207)"><rect width="96" height="46" rx="10" fill="none" stroke="#fff" stroke-width="6"/>
  <rect x="98" y="14" width="10" height="18" rx="3" fill="#fff"/><rect x="9" y="9" width="62" height="28" rx="5" fill="#34C759"/></g>
<text x="512" y="905" text-anchor="middle" font-family="Menlo, 'DejaVu Sans Mono', monospace" font-weight="700" font-size="46" fill="#fff" opacity="0.92" letter-spacing="4">00:01:24</text>
`);
}

for (const [name, content] of Object.entries(out)) fs.writeFileSync(path.join(__dirname, `${name}.svg`), content);

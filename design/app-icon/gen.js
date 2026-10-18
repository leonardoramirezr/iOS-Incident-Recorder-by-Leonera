// Genera AppIcon.svg (ícono de la app). Uso: node gen.js && node render.js
const fs = require('fs'), path = require('path');

const svg = (defs, body) => `<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 1024 1024" width="1024" height="1024">
<defs>${COMMON}${defs}</defs>${body}</svg>\n`;

const COMMON = `
<linearGradient id="metal" x1="0" y1="0" x2="0.4" y2="1">
  <stop offset="0" stop-color="#F5F5F7"/><stop offset="0.35" stop-color="#B8B8BE"/>
  <stop offset="0.6" stop-color="#6E6E73"/><stop offset="1" stop-color="#2C2C2E"/></linearGradient>
<radialGradient id="redGlow" cx="0.5" cy="0.5" r="0.5">
  <stop offset="0" stop-color="#FF453A" stop-opacity="0.9"/><stop offset="0.4" stop-color="#FF3B30" stop-opacity="0.35"/><stop offset="1" stop-color="#FF3B30" stop-opacity="0"/></radialGradient>
<filter id="shadow" x="-30%" y="-30%" width="160%" height="170%">
  <feDropShadow dx="0" dy="28" stdDeviation="30" flood-color="#000" flood-opacity="0.55"/></filter>
<filter id="softShadow" x="-30%" y="-30%" width="160%" height="160%">
  <feDropShadow dx="0" dy="10" stdDeviation="12" flood-color="#000" flood-opacity="0.45"/></filter>
<filter id="blur20"><feGaussianBlur stdDeviation="20"/></filter>
`;

let out;
// Visor de grabación con cinta de incidente
{
  const tape = (rot) => `<g transform="rotate(${rot} 512 560)" filter="url(#softShadow)">
    <rect x="-200" y="505" width="1424" height="110" fill="url(#tapeFill)"/>
    <rect x="-200" y="505" width="1424" height="12" fill="#1C1C1E"/><rect x="-200" y="603" width="1424" height="12" fill="#1C1C1E"/>
    ${[-760, -375, 375, 760].map(dx => `<text x="${512 + dx}" y="574" text-anchor="middle" font-family="Helvetica, Arial, sans-serif" font-weight="900" font-size="44" letter-spacing="3" fill="#1C1C1E">INCIDENT</text>`).join('')}
    ${[-568, 568].map(dx => `<text x="${512 + dx}" y="572" text-anchor="middle" font-family="Helvetica, Arial, sans-serif" font-size="34" fill="#1C1C1E">▲</text>`).join('')}
    <rect x="-200" y="505" width="1424" height="45" fill="#fff" opacity="0.18"/>
  </g>`;
  const brackets = [[150, 150, 1, 1], [874, 150, -1, 1], [150, 874, 1, -1], [874, 874, -1, -1]]
    .map(([x, y, sx, sy]) => `<path d="M ${x} ${y + sy * 90} L ${x} ${y} L ${x + sx * 90} ${y}" fill="none" stroke="#fff" stroke-width="14" stroke-linecap="round" stroke-linejoin="round"/>`).join('');
  out = svg(`
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

fs.writeFileSync(path.join(__dirname, 'AppIcon.svg'), out);

# Opciones de ícono de la app

Cuatro propuestas en estilo de ícono iOS (cuadrado completo de 1024×1024 sin esquinas
redondeadas: iOS aplica la máscara). Cada una tiene su `.svg` editable y su `.png` final.
`comparativa.png` las muestra con la máscara a tamaño grande y pequeño.

Base conceptual: **incidente** + **grabar**.

| # | Opción | Idea |
|---|--------|------|
| 1 | `1-alerta-lente` | Triángulo de advertencia ámbar con volumen y brillo; dentro, una lente de cámara detallada y la luz roja de grabación. |
| 2 | `2-camara-incidente` | Videocámara de metal oscuro con lente, luz `REC` encendida y una insignia de advertencia en la esquina. |
| 3 | `3-torreta` | Torreta de emergencia: domo de vidrio rojo con la lente visible dentro, haces de luz y luz de grabación en la base. |
| 4 | `4-visor-cinta` | Visor de cámara (`REC`, batería, tiempo) con cinta amarilla de "INCIDENTE" cruzada detrás del botón de grabar. |

Para regenerar: `node gen.js && node render.js` (los SVG salen de `gen.js`; los PNG se renderizan con Playwright/Chromium).
Para usar una opción, copia su `.png` a
`IncidentRecorder/Resources/Assets.xcassets/AppIcon.appiconset/AppIcon.png`.

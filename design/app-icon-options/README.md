# Opciones de ícono de la app

Cuatro propuestas en estilo de ícono iOS (cuadrado completo de 1024×1024 sin esquinas
redondeadas: iOS aplica la máscara). Cada una tiene su `.svg` editable y su `.png` final.
`comparativa.png` las muestra con la máscara a tamaño grande y pequeño.

| # | Opción | Idea |
|---|--------|------|
| 1 | `1-doble-camara` | Módulo de cámaras del iPhone: lente trasera grande, frontal pequeña y punto rojo de grabación. Fondo grafito. |
| 2 | `2-escudo` | Escudo blanco con el botón de grabar sobre fondo índigo: protección y seguridad. |
| 3 | `3-bloques-subida` | Anillo de 12 segmentos (bloques de 1 minuto, los azules ya subidos) alrededor de un botón rojo con flecha de subida. Fondo claro. |
| 4 | `4-ubicacion` | Pin de mapa con el botón de grabar y un recorrido punteado sobre fondo rojo. |

Para regenerar los PNG: `node render.js` (usa Playwright/Chromium).
Para usar una opción, copia su `.png` a
`IncidentRecorder/Resources/Assets.xcassets/AppIcon.appiconset/AppIcon.png`.

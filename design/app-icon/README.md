# Ícono de la app

`AppIcon.svg` es la fuente del ícono: un visor de cámara grabando (`REC`, batería, tiempo)
con cinta amarilla de "INCIDENT" cruzada detrás del botón de grabar. Es un cuadrado
completo de 1024×1024 sin esquinas redondeadas; iOS aplica la máscara.

Para regenerarlo tras editar `gen.js`:

```sh
node design/app-icon/gen.js && node design/app-icon/render.js
convert IncidentRecorder/Resources/Assets.xcassets/AppIcon.appiconset/AppIcon.png -alpha off \
  PNG24:IncidentRecorder/Resources/Assets.xcassets/AppIcon.appiconset/AppIcon.png
```

`render.js` usa Playwright/Chromium y escribe directamente en
`IncidentRecorder/Resources/Assets.xcassets/AppIcon.appiconset/AppIcon.png`. El último paso
quita el canal alfa, porque el App Store rechaza íconos con transparencia.

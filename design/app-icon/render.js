// Renderiza AppIcon.svg a 1024×1024 en el catálogo de assets de la app.
const { chromium } = require('/opt/node22/lib/node_modules/playwright');
const fs = require('fs'), path = require('path');
const dest = path.join(__dirname, '../../IncidentRecorder/Resources/Assets.xcassets/AppIcon.appiconset/AppIcon.png');
(async () => {
  const b = await chromium.launch();
  const p = await b.newPage({ viewport: { width: 1024, height: 1024 } });
  await p.setContent(`<style>html,body{margin:0;background:#000}</style>${fs.readFileSync(path.join(__dirname, 'AppIcon.svg'), 'utf8')}`);
  // Fondo opaco: PNG sin transparencia (el App Store rechaza íconos con transparencia).
  await p.screenshot({ path: dest, type: 'png', omitBackground: false });
  await b.close();
})();

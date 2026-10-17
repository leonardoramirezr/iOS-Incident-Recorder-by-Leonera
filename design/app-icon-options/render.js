const { chromium } = require('/opt/node22/lib/node_modules/playwright');
const fs = require('fs'), path = require('path');
(async () => {
  const dir = __dirname, b = await chromium.launch();
  const p = await b.newPage({ viewport: { width: 1024, height: 1024 } });
  const files = fs.readdirSync(dir).filter(f => /^\d.*\.svg$/.test(f)).sort();
  for (const f of files) {
    await p.setContent(`<style>html,body{margin:0}</style>${fs.readFileSync(path.join(dir, f), 'utf8')}`);
    await p.screenshot({ path: path.join(dir, f.replace('.svg', '.png')), omitBackground: true });
  }
  // hoja comparativa con máscara de ícono iOS
  const tiles = files.map(f => `<figure><div class="i" style="background-image:url(data:image/svg+xml;base64,${fs.readFileSync(path.join(dir, f)).toString('base64')})"></div><div class="s" style="background-image:url(data:image/svg+xml;base64,${fs.readFileSync(path.join(dir, f)).toString('base64')})"></div><figcaption>${f.replace('.svg','')}</figcaption></figure>`).join('');
  await p.setViewportSize({ width: 1600, height: 560 });
  await p.setContent(`<style>body{margin:0;background:#F2F2F7;font:600 26px -apple-system,Helvetica,sans-serif;display:flex;gap:40px;justify-content:center;align-items:center;height:560px}
  figure{margin:0;text-align:center;color:#3A3A3C} .i{width:320px;height:320px;border-radius:72px;background-size:cover;box-shadow:0 10px 30px rgba(0,0,0,.18)}
  .s{width:120px;height:120px;border-radius:27px;background-size:cover;margin:24px auto 12px;box-shadow:0 4px 12px rgba(0,0,0,.15)}</style>${tiles}`);
  await p.screenshot({ path: path.join(dir, 'comparativa.png') });
  await b.close();
})();

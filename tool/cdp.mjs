// Cliente CDP mínimo para testar o app de verdade no Chrome em :9222 (o de depuração, perfil
// ~/.chrome-devtools-profile; ver CLAUDE.md, "Teste de uso"). Sem dependências (Node ≥ 22).
// uso: node tool/cdp.mjs <comando> [args]
//   open <url>                 → abre aba nova, imprime o id
//   tabs                       → lista abas
//   eval <tabId> <js>          → avalia (await ok), imprime o resultado em JSON
//   shot <tabId> <arquivo.png> [largura altura]  → screenshot (opcionalmente com viewport emulado)
//   click <tabId> x y          → clique real de mouse
//   key <tabId> <tecla> [mods] → tecla real (mods: 1 alt 2 ctrl 4 meta 8 shift)
//   drag <tabId> x1 y1 x2 y2
//   close <tabId>
//   reset <tabId>              → tira a emulação de viewport
//   run <tabId> passos.json [largura altura]
//                              → vários passos numa sessão só (com largura/altura, emula o aparelho):
//     ["click",x,y] ["dbl",x,y] ["rclick",x,y] ["down",x,y] ["move",x,y] ["up",x,y] ["hover",x,y] ["drag",x1,y1,x2,y2]
//     (toque longo + arrasto: down, wait 700, vários move, up)
//     ["wheel",x,y,dx,dy,mods] ["type","texto"] ["key","a",mods] ["keydown","a"] ["keyup","a"]
//     ["wait",ms] ["shot","f.png"] ["eval","js"] ["probe"] ["file","nome.wav",...]
//     mods: 1 alt, 2 ctrl, 4 meta (Cmd), 8 shift. Coordenadas em pixels CSS; o shot sai nessa escala.
//     "probe" lê jopendawEngine.probe() (posição e picos do motor: confere que o som sai sem ouvir).
//     "file" faz o próximo seletor de arquivos do app receber esses arquivos (servidos em /nome).
//     Erros e avisos do console aparecem no fim.
const base = 'http://127.0.0.1:9222';
const [cmd, ...args] = process.argv.slice(2);

async function ws(tabId) {
  const tabs = await (await fetch(`${base}/json`)).json();
  const t = tabs.find((x) => x.id === tabId);
  if (!t) throw new Error('aba não encontrada: ' + tabId);
  const sock = new WebSocket(t.webSocketDebuggerUrl);
  await new Promise((r, j) => { sock.onopen = r; sock.onerror = j; });
  let id = 0;
  const pending = new Map();
  const errors = [];
  sock.onmessage = (e) => {
    const m = JSON.parse(e.data);
    if (m.id && pending.has(m.id)) { pending.get(m.id)(m); pending.delete(m.id); }
    else if (m.method === 'Runtime.exceptionThrown') errors.push('EXC ' + (m.params.exceptionDetails.exception?.description || m.params.exceptionDetails.text).slice(0, 400));
    else if (m.method === 'Runtime.consoleAPICalled' && (m.params.type === 'error' || m.params.type === 'warning')) errors.push(m.params.type.toUpperCase() + ' ' + m.params.args.map((a) => a.value ?? a.description ?? '').join(' ').slice(0, 400));
  };
  const send = (method, params = {}) => new Promise((r) => { const i = ++id; pending.set(i, r); sock.send(JSON.stringify({ id: i, method, params })); });
  await send('Runtime.enable');
  await send('Page.bringToFront');
  await send('Emulation.setFocusEmulationEnabled', { enabled: true });
  return { send, errors, close: () => sock.close() };
}

const sleep = (ms) => new Promise((r) => setTimeout(r, ms));

// `buttons` coerente com o evento (apertado no press, solto no release): sem ele o Chrome entrega
// pointerdown sem botão e o Flutter perde cliques em alvos que também aceitam arrastar.
async function mouse(c, type, x, y, extra = {}) {
  const bit = { left: 1, right: 2, middle: 4 }[extra.button ?? 'left'] ?? 0;
  const buttons = type === 'mousePressed' ? bit : 0;
  await c.send('Input.dispatchMouseEvent', { type, x, y, button: 'left', clickCount: 1, buttons, ...extra });
}

const KEYS = {
  ' ': ['Space', ' ', 32], Space: ['Space', ' ', 32], Enter: ['Enter', '\r', 13], Delete: ['Delete', '', 46], Backspace: ['Backspace', '', 8],
  Escape: ['Escape', '', 27], ArrowUp: ['ArrowUp', '', 38], ArrowDown: ['ArrowDown', '', 40], ArrowLeft: ['ArrowLeft', '', 37], ArrowRight: ['ArrowRight', '', 39],
};

try {
  if (cmd === 'tabs') {
    const tabs = await (await fetch(`${base}/json`)).json();
    for (const t of tabs.filter((t) => t.type === 'page')) console.log(t.id, t.url, t.title);
  } else if (cmd === 'open') {
    const t = await (await fetch(`${base}/json/new?${encodeURIComponent(args[0])}`, { method: 'PUT' })).json();
    console.log(t.id);
  } else if (cmd === 'close') {
    await fetch(`${base}/json/close/${args[0]}`);
  } else {
    const c = await ws(args[0]);
    if (cmd === 'run') {
      // passos: [["click",x,y],["dbl",x,y],["type","txt"],["key","Enter",mods],["drag",x1,y1,x2,y2],["wait",ms],["shot","f.png"],["eval","js"]]
      const steps = JSON.parse((await import('fs')).readFileSync(args[1], 'utf8'));
      if (args[2]) {
        const w = +args[2], h = +args[3];
        await c.send('Emulation.setDeviceMetricsOverride', { width: w, height: h, deviceScaleFactor: 2, mobile: w < 800 });
        await sleep(800);
      } else {
        await c.send('Emulation.clearDeviceMetricsOverride');
      }
      for (const [op, ...a] of steps) {
        if (op === 'click') { await mouse(c, 'mouseMoved', a[0], a[1], { button: 'none' }); await mouse(c, 'mousePressed', a[0], a[1]); await sleep(40); await mouse(c, 'mouseReleased', a[0], a[1]); }
        else if (op === 'rclick') { await mouse(c, 'mousePressed', a[0], a[1], { button: 'right' }); await mouse(c, 'mouseReleased', a[0], a[1], { button: 'right' }); }
        else if (op === 'dbl') { await mouse(c, 'mousePressed', a[0], a[1]); await mouse(c, 'mouseReleased', a[0], a[1]); await sleep(60); await mouse(c, 'mousePressed', a[0], a[1], { clickCount: 2 }); await mouse(c, 'mouseReleased', a[0], a[1], { clickCount: 2 }); }
        else if (op === 'type') await c.send('Input.insertText', { text: a[0] });
        else if (op === 'key' || op === 'keydown' || op === 'keyup') {
          const k = a[0], mods = +(a[1] || 0);
          // modificadores como teclas de verdade (o Flutter acompanha o estado pelo keydown deles)
          const MODS = [[4, 'Meta', 'MetaLeft', 91], [2, 'Control', 'ControlLeft', 17], [8, 'Shift', 'ShiftLeft', 16], [1, 'Alt', 'AltLeft', 18]].filter(([bit]) => mods & bit);
          let acc = 0;
          if (op !== 'keyup') for (const [bit, key, code, vk] of MODS) { acc |= bit; await c.send('Input.dispatchKeyEvent', { type: 'rawKeyDown', key, code, windowsVirtualKeyCode: vk, modifiers: acc }); }
          const [code, text, vk] = KEYS[k] || [`Key${k.toUpperCase()}`, k, k.toUpperCase().charCodeAt(0)];
          const t = mods & 6 ? '' : text;
          const key = k === 'Space' ? ' ' : k;
          if (op !== 'keyup') await c.send('Input.dispatchKeyEvent', { type: t ? 'keyDown' : 'rawKeyDown', key, code, text: t, windowsVirtualKeyCode: vk, modifiers: mods });
          if (op === 'key') await sleep(30);
          if (op !== 'keydown') await c.send('Input.dispatchKeyEvent', { type: 'keyUp', key, code, windowsVirtualKeyCode: vk, modifiers: mods });
          if (op !== 'keydown') for (const [bit, mkey, mcode, mvk] of MODS.reverse()) { acc &= ~bit; await c.send('Input.dispatchKeyEvent', { type: 'keyUp', key: mkey, code: mcode, windowsVirtualKeyCode: mvk, modifiers: acc }); }
        }
        else if (op === 'drag') { const [x1, y1, x2, y2] = a; await mouse(c, 'mouseMoved', x1, y1, { button: 'none' }); await mouse(c, 'mousePressed', x1, y1); for (let i = 1; i <= 12; i++) { await mouse(c, 'mouseMoved', x1 + (x2 - x1) * i / 12, y1 + (y2 - y1) * i / 12, { buttons: 1 }); await sleep(16); } await mouse(c, 'mouseReleased', x2, y2); }
        else if (op === 'wait') await sleep(a[0]);
        else if (op === 'down') { await mouse(c, 'mouseMoved', a[0], a[1], { button: 'none' }); await mouse(c, 'mousePressed', a[0], a[1]); }
        else if (op === 'up') await mouse(c, 'mouseReleased', a[0], a[1]);
        else if (op === 'move') await mouse(c, 'mouseMoved', a[0], a[1], { buttons: 1 });
        else if (op === 'hover') await mouse(c, 'mouseMoved', a[0], a[1], { button: 'none' });
        else if (op === 'wheel') await c.send('Input.dispatchMouseEvent', { type: 'mouseWheel', x: a[0], y: a[1], deltaX: a[2] || 0, deltaY: a[3] || 0, modifiers: a[4] || 0 });
        else if (op === 'file') await c.send('Runtime.evaluate', { awaitPromise: true, expression: `(async () => { const blobs = await Promise.all(${JSON.stringify(a)}.map(async (n) => new File([await (await fetch('/' + n)).blob()], n))); window.__origClick ??= HTMLInputElement.prototype.click; HTMLInputElement.prototype.click = function () { if (this.type === 'file') { const dt = new DataTransfer(); blobs.forEach((b) => dt.items.add(b)); this.files = dt.files; this.dispatchEvent(new Event('change', { bubbles: true })); HTMLInputElement.prototype.click = window.__origClick; return; } return window.__origClick.call(this); }; })()` });
        else if (op === 'probe') { const r = await c.send('Runtime.evaluate', { expression: 'JSON.stringify(jopendawEngine.probe())', returnByValue: true }); console.log('probe', r.result.result.value); }
        else if (op === 'shot') { const m = await c.send('Page.getLayoutMetrics'); const v = m.result.cssVisualViewport; const r = await c.send('Page.captureScreenshot', { format: 'png', clip: { x: 0, y: 0, width: v.clientWidth, height: v.clientHeight, scale: 0.5 } }); (await import('fs')).writeFileSync(a[0], Buffer.from(r.result.data, 'base64')); console.log('shot', a[0]); }
        else if (op === 'eval') { const r = await c.send('Runtime.evaluate', { expression: a[0], awaitPromise: true, returnByValue: true, userGesture: true }); console.log('eval', JSON.stringify(r.result.exceptionDetails ? r.result.exceptionDetails.exception?.description : r.result.result.value)); }
        await sleep(120);
      }
      await sleep(200);
      if (c.errors.length) console.log('ERROS DO CONSOLE:\n  ' + c.errors.join('\n  '));
    } else if (cmd === 'eval') {
      const r = await c.send('Runtime.evaluate', { expression: args[1], awaitPromise: true, returnByValue: true, userGesture: true });
      console.log(JSON.stringify(r.result.exceptionDetails ? r.result.exceptionDetails : r.result.result.value, null, 1));
    } else if (cmd === 'shot') {
      if (args[2]) await c.send('Emulation.setDeviceMetricsOverride', { width: +args[2], height: +args[3], deviceScaleFactor: 1, mobile: +args[2] < 800 });
      if (args[2]) await sleep(1500);
      const r = await c.send('Page.captureScreenshot', { format: 'png' });
      (await import('fs')).writeFileSync(args[1], Buffer.from(r.result.data, 'base64'));
      console.log('ok', args[1]);
    } else if (cmd === 'reset') {
      await c.send('Emulation.clearDeviceMetricsOverride');
    } else if (cmd === 'click') {
      const [x, y] = [+args[1], +args[2]];
      await mouse(c, 'mouseMoved', x, y, { button: 'none' });
      await mouse(c, 'mousePressed', x, y);
      await sleep(40);
      await mouse(c, 'mouseReleased', x, y);
    } else if (cmd === 'dblclick') {
      const [x, y] = [+args[1], +args[2]];
      await mouse(c, 'mousePressed', x, y);
      await mouse(c, 'mouseReleased', x, y);
      await sleep(60);
      await mouse(c, 'mousePressed', x, y, { clickCount: 2 });
      await mouse(c, 'mouseReleased', x, y, { clickCount: 2 });
    } else if (cmd === 'drag') {
      const [x1, y1, x2, y2] = args.slice(1).map(Number);
      await mouse(c, 'mouseMoved', x1, y1, { button: 'none' });
      await mouse(c, 'mousePressed', x1, y1);
      for (let i = 1; i <= 12; i++) { await mouse(c, 'mouseMoved', x1 + (x2 - x1) * i / 12, y1 + (y2 - y1) * i / 12, { buttons: 1 }); await sleep(16); }
      await mouse(c, 'mouseReleased', x2, y2);
    } else if (cmd === 'key') {
      const k = args[1];
      const mods = +(args[2] || 0);
      const [code, text, vk] = KEYS[k] || [`Key${k.toUpperCase()}`, k, k.toUpperCase().charCodeAt(0)];
      const t = mods & 6 ? '' : text;
      await c.send('Input.dispatchKeyEvent', { type: t ? 'keyDown' : 'rawKeyDown', key: k === 'Space' ? ' ' : k, code, text: t, windowsVirtualKeyCode: vk, modifiers: mods });
      await sleep(30);
      await c.send('Input.dispatchKeyEvent', { type: 'keyUp', key: k === 'Space' ? ' ' : k, code, windowsVirtualKeyCode: vk, modifiers: mods });
    } else if (cmd === 'type') {
      await c.send('Input.insertText', { text: args[1] });
    }
    c.close();
  }
} catch (e) {
  console.error('erro:', e.message);
  process.exit(1);
}

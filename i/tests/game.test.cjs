const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');
const { test } = require('node:test');

const html = fs.readFileSync(path.join(__dirname, '..', 'index.html'), 'utf8');
const source = html.match(/<script>([\s\S]*?)<\/script>/)[1];
const SAVE_KEY = 'fabricaDoVentoy_save';

// Executar o jogo com relógio e armazenamento isolados do progresso no navegador.
function game(saved) {
  const nodes = new Map();
  const storage = new Map(saved ? [[SAVE_KEY, JSON.stringify(saved)]] : []);
  const intervals = new Map();
  let now = 0;
  function element(id = '') {
    return {
      id, value: '', textContent: '', disabled: false, hidden: false, children: [], listeners: {},
      style: { setProperty() {} }, classList: { replace() {} },
      get innerHTML() { return this.markup || ''; },
      set innerHTML(value) { this.markup = value; this.children = []; },
      appendChild(child) {
        this.children.push(child);
        if (id === 'inpModelo' && !this.value) this.value = child.value;
      },
      addEventListener(type, listener) { this.listeners[type] = listener; },
      getBoundingClientRect() { return { left: 0, top: 0, width: 360, height: 320 }; },
      focus() {}, remove() {}
    };
  }
  const context = vm.createContext({
    document: {
      getElementById(id) { if (!nodes.has(id)) nodes.set(id, element(id)); return nodes.get(id); },
      createElement: () => element()
    },
    localStorage: {
      getItem: key => storage.get(key) || null,
      setItem: (key, value) => storage.set(key, value),
      removeItem: key => storage.delete(key)
    },
    performance: { now: () => now },
    setInterval: (fn, delay) => intervals.set(delay, fn), setTimeout() {},
    window: { addEventListener() {} }, confirm: () => true, console
  });
  vm.runInContext(source, context);
  return {
    run: code => vm.runInContext(code, context),
    node: id => nodes.get(id),
    saved: () => JSON.parse(storage.get(SAVE_KEY) || 'null'),
    tick(ms) { now += ms; intervals.get(100)(); },
    click() { nodes.get('btnFabrica').listeners.click({ detail: 0 }); }
  };
}

test('início sem dinheiro bloqueia compras e turbo exige um pendrive', () => {
  const g = game();
  assert.equal(g.node('btnAutoPendrive').disabled, true);
  assert.equal(g.node('btnTurboPendrives').disabled, true);
  g.run('estado.dinheiro = 1000; comprarTurboPendrives()');
  assert.equal(g.run('estado.dinheiro'), 1000);
  assert.equal(g.run('estado.turboPendrives'), 0);
  g.run('estado.dinheiro = 14; comprarPendriveAutomatico()');
  assert.equal(g.run('estado.autoPendrives'), 0);
  assert.equal(g.run('estado.dinheiro'), 14);
});

test('compras aumentam o preço, os cliques e salvam imediatamente', () => {
  const g = game();
  g.run('estado.dinheiro = 100; comprarPendriveAutomatico(); comprarPendriveAutomatico()');
  assert.equal(g.run('estado.dinheiro'), 68);
  assert.equal(g.run('custoPendriveAutomatico()'), 19);
  assert.equal(g.run('cliquesAutomaticos()'), 2);
  assert.equal(g.node('autoPendriveRing').children.length, 2);
  assert.equal(g.saved().autoPendrives, 2);
  g.tick(1000);
  assert.equal(g.run('estado.pendrives'), 2);
  assert.equal(g.run('estado.dinheiro'), 72);
});

test('turbo dobra a velocidade e luvas fortalecem cliques manuais e automáticos', () => {
  const g = game({ dinheiro: 1000, autoPendrives: 3 });
  g.run('comprarTurboPendrives()');
  assert.equal(g.run('cliquesAutomaticos()'), 6);
  assert.equal(g.run('estado.dinheiro'), 850);
  assert.equal(g.run('custoTurboPendrives()'), 375);
  g.run('comprarLuva()');
  assert.equal(g.run('ppsPendrivesAutomaticos()'), 12);
  g.click();
  assert.equal(g.run('estado.pendrives'), 2);
  g.run('comprarTurboPendrives()');
  assert.equal(g.run('ppsPendrivesAutomaticos()'), 24);
});

test('produção combina máquinas e cliques uma vez por tempo decorrido', () => {
  const g = game({
    pendrives: 10, dinheiro: 100, totalProduzido: 10,
    autoPendrives: 2, turboPendrives: 1, luvas: 2, cafes: 1,
    maquinas: [{ id: 1, nome: 'Prensa', modelo: 'prensa', nivel: 1, criadaEm: '' }]
  });
  assert.equal(g.run('ppsTotal()'), 19.5);
  g.tick(2500);
  assert.equal(g.run('estado.pendrives'), 58.75);
  assert.equal(g.run('estado.totalProduzido'), 58.75);
  assert.equal(g.run('estado.dinheiro'), 197.5);
  g.tick(0);
  assert.equal(g.run('estado.pendrives'), 58.75);
});

test('saves antigos mantêm progresso e recebem automação zerada', () => {
  const g = game({ pendrives: 345, dinheiro: 456, luvas: 4, cafes: 2, proximoId: 7, maquinas: [] });
  assert.equal(g.run('estado.pendrives'), 345);
  assert.equal(g.run('estado.dinheiro'), 456);
  assert.equal(g.run('estado.luvas'), 4);
  assert.equal(g.run('estado.proximoId'), 7);
  assert.equal(g.run('estado.autoPendrives'), 0);
  assert.equal(g.run('estado.turboPendrives'), 0);
});

test('recarregar preserva pendrives e turbo; reset também limpa a automação', () => {
  const g = game({ dinheiro: 1000, autoPendrives: 2 });
  g.run('comprarTurboPendrives()');
  const loaded = game(g.saved());
  assert.equal(loaded.run('cliquesAutomaticos()'), 4);
  assert.equal(loaded.node('autoPendriveRing').children.length, 2);
  loaded.run('resetarJogo()');
  assert.equal(loaded.run('ppsTotal()'), 0);
  assert.equal(loaded.run('estado.turboPendrives'), 0);
  assert.equal(loaded.node('autoPendriveRing').hidden, true);
  assert.equal(loaded.node('autoPendriveRing').children.length, 0);
  assert.equal(loaded.saved(), null);
});

test('limite visual não limita produção de grandes quantidades', () => {
  const g = game({ autoPendrives: 200 });
  assert.equal(g.node('autoPendriveRing').children.length, 24);
  assert.equal(g.run('cliquesAutomaticos()'), 200);
  g.tick(1000);
  assert.equal(g.run('estado.pendrives'), 200);
});

// Regenerates test/fixtures/geometry.json from the editor's own engine (src/core.js).
// Run from packages/flow_studio:  node tool/geometry_fixtures.js
const fs = require('fs'), path = require('path'), vm = require('vm');
const root = path.resolve(__dirname, '../../..');
const ctx = { window: {}, Math, JSON, Number, Object, Array, String, Set, btoa, atob, unescape, escape, encodeURIComponent, decodeURIComponent };
vm.runInNewContext(fs.readFileSync(path.join(root, 'src/core.js'), 'utf8'), ctx);
const F = ctx.window.FlowCore;

let seed = 7;
const rand = () => ((seed = (seed * 1103515245 + 12345) % 2147483648) / 2147483648);
const ports = ['top', 'bottom', 'left', 'right', 'center'], routes = ['orthogonal', 'straight', 'curved'], styles = ['solid', 'dashed', 'dotted'];

function strip(p) { return { ...F.clone({ ...p, assets: {} }) }; }
function random(i) {
  const p = F.preset('blank'); p.title = 'random ' + i;
  const count = 3 + Math.floor(rand() * 5);
  for (let n = 0; n < count; n++) p.nodes.push(F.node('n' + n, 'solar', 'N' + n, 50 + rand() * 900, 50 + rand() * 550, 20 + rand() * 150, 20 + rand() * 150));
  for (let e = 0; e < count + 2; e++) {
    const a = Math.floor(rand() * count); let b = Math.floor(rand() * count); if (a === b) b = (b + 1) % count;
    const wp = []; const k = Math.floor(rand() * 5); for (let j = 0; j < k; j++) wp.push([Math.round(rand() * 1000 * 10) / 10, Math.round(rand() * 650 * 10) / 10]);
    const edge = F.edge('e' + e, 'n' + a, 'n' + b, ports[Math.floor(rand() * 5)], ports[Math.floor(rand() * 5)], wp);
    edge.auto = rand() < .4; edge.radius = [0, 4, 12, 30, 100][Math.floor(rand() * 5)];
    if (i >= 10) { // the first 10 keep every optional field at its default
      edge.route = routes[Math.floor(rand() * 3)];
      if (rand() < .6) edge.sourceOffset = Math.round((rand() - .5) * 120 * 10) / 10;
      if (rand() < .6) edge.targetOffset = Math.round((rand() - .5) * 120 * 10) / 10;
      edge.pulses = 1 + Math.floor(rand() * 12); edge.pulseLength = Math.round((.02 + rand() * .88) * 100) / 100;
      edge.glow = Math.round(rand() * 100) / 100; edge.trackStyle = styles[Math.floor(rand() * 3)]; edge.trackWidth = Math.round((.5 + rand() * 8) * 10) / 10;
    }
    p.edges.push(edge);
  }
  return p;
}

const projects = ['hybrid', 'generator', 'pump'].map(k => F.preset(k));
projects.push(JSON.parse(fs.readFileSync(path.join(root, 'examples/hybrid-energy-flow.flow.json'), 'utf8')));
for (let i = 0; i < 40; i++) projects.push(random(i));
// Hand-made curved / offset cases: 2-point curves for every port pair, Catmull-Rom through waypoints, shifted ports.
{
  const p = F.preset('blank'); p.title = 'curves and offsets';
  p.nodes.push(F.node('a', 'solar', 'A', 200, 200, 120, 90), F.node('b', 'solar', 'B', 700, 450, 100, 140), F.node('c', 'solar', 'C', 260, 520, 60, 60));
  let k = 0;
  for (const sp of ports) for (const tp of ports) {
    const e = F.edge('c' + k++, 'a', 'b', sp, tp); e.auto = true; e.route = 'curved'; p.edges.push(e);
  }
  const add = (from, to, sp, tp, wp, f) => { const e = F.edge('m' + k++, from, to, sp, tp, wp); Object.assign(e, f); p.edges.push(e); };
  add('a', 'b', 'right', 'left', [[400, 260]], { route: 'curved' });
  add('a', 'b', 'bottom', 'top', [[260, 330], [520, 300], [700, 330]], { route: 'curved', sourceOffset: -30, targetOffset: 25 });
  add('c', 'b', 'center', 'center', [[400, 600], [600, 560]], { route: 'curved' });
  add('a', 'c', 'left', 'right', [[100, 300], [100, 520], [200, 600], [330, 600]], { route: 'curved', targetOffset: -12.5 });
  add('a', 'b', 'right', 'left', [], { auto: true, sourceOffset: 20, targetOffset: -40 });
  add('a', 'b', 'top', 'bottom', [], { auto: true, sourceOffset: -50.5, targetOffset: 33 });
  add('a', 'b', 'center', 'center', [], { auto: true, sourceOffset: 99, targetOffset: 99 });
  add('a', 'b', 'right', 'top', [], { auto: true, route: 'straight', sourceOffset: 10, targetOffset: 10 });
  add('a', 'b', 'bottom', 'left', [[250, 400], [500, 400]], { route: 'straight', sourceOffset: 40, radius: 30 });
  add('c', 'a', 'top', 'bottom', [], { auto: true, route: 'curved', sourceOffset: 2048, targetOffset: -2048 });
  p.edges.forEach((e, j) => { e.pulses = 1 + j % 12; e.trackStyle = styles[j % 3]; e.trackWidth = .5 + j % 7; e.pulseLength = [.02, .12, .5, .9][j % 4]; });
  projects.push(p);
}

const cases = projects.map(p => ({
  project: strip(p),
  paths: Object.fromEntries(p.edges.map(e => [e.id, F.pathData(F.shape(p, e))])),
  // Track dash pattern (null = solid) and pulse [dash, gap] for a 1000px-long path.
  dashes: Object.fromEntries(p.edges.map(e => [e.id, { track: F.trackDash(e), pulse: F.pulseDash(1000, e) }])),
}));
fs.writeFileSync(path.join(__dirname, '../test/fixtures/geometry.json'), JSON.stringify(cases));
console.log('Wrote', cases.length, 'projects,', cases.reduce((s, c) => s + Object.keys(c.paths).length, 0), 'lines');

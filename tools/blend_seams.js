// =============================================================================
//  Terrain seam blender
// =============================================================================
//  Reads every Mars terrain tile placed in main.tscn, applies its transform
//  (scale / rotation / mirror), and writes a height-correction grid per tile to
//  res://assets/terrain_seams/<TileName>.json.
//
//  Near each tile's rim its surface is blended toward the neighbouring tiles:
//    weight(tile, p) = smoothstep(0, BAND, distance from p to that tile's edge)
//    H(p)            = sum(weight * height) / sum(weight)   over tiles covering p
//    correction      = H(p) - own height(p)
//  so tiles meet at a common surface. Interiors are untouched.
//
//  RE-RUN THIS WHENEVER YOU MOVE, ADD, DUPLICATE OR DELETE A TILE:
//      cd tools
//      npm install @gltf-transform/core @gltf-transform/extensions   (once)
//      node blend_seams.js [band] [margin]
//          band   blend width across each edge in metres (default 40)
//          margin how far every tile is grown outward per side so that
//                 neighbours always overlap and no cracks remain (default 3)
// =============================================================================
const fs = require('fs');
const path = require('path');
const { NodeIO } = require('@gltf-transform/core');
const { ALL_EXTENSIONS } = require('@gltf-transform/extensions');

const PROJ = path.resolve(__dirname, '..') + '/';
const OUT = PROJ + 'assets/terrain_seams/';
const CELL = 2.0;
const BAND = Number(process.argv[2] || 40);
const MIN_W = 1e-4;
const MARGIN = Number(process.argv[3] || 3);  // grow every tile this many metres per side
const TOP_NORMAL_MIN = 0.35;                  // vertex counts as top surface if normal.z >= this
const HALF = BAND / 2;  // blend runs HALF metres either side of a tile edge
const EXTEND = HALF;    // tiles must reach as far past their edge as the blend

const tscn = fs.readFileSync(PROJ + 'main.tscn', 'utf8').replace(/\r\n/g, '\n');
const ext = {};
for (const m of tscn.matchAll(/\[ext_resource [^\]]*path="([^"]+)" id="([^"]+)"\]/g)) ext[m[2]] = m[1];
const tiles = [];
for (const b of tscn.split(/\n(?=\[)/)) {
  const h = b.match(/^\[node name="([^"]+)" parent="\."[^\]]*instance=ExtResource\("([^"]+)"\)/);
  if (!h) continue;
  const res = ext[h[2]];
  if (!res || !res.includes('/models/Mars/')) continue;
  const t = b.match(/\ntransform = Transform3D\(([^)]*)\)/);
  const v = t ? t[1].split(',').map(Number) : [1,0,0,0,1,0,0,0,1,0,0,0];
  tiles.push({ name: h[1], file: PROJ + res.replace('res://', ''), r: v.slice(0, 9), o: v.slice(9, 12) });
}
const smooth = (e0, e1, x) => { const t = Math.min(Math.max((x - e0) / (e1 - e0), 0), 1); return t * t * (3 - 2 * t); };

(async () => {
  const io = new NodeIO().registerExtensions(ALL_EXTENSIONS);
  const cache = {};
  for (const t of tiles) {
    if (!cache[t.file]) {
      // Only TOP-SURFACE vertices (normal facing up in the model's local
      // frame, where Z is elevation). Side walls and the slab's underside are
      // excluded: on tilted tiles they stick out past the top edge and would
      // otherwise be read as a bogus, very low "edge height".
      const doc = await io.read(t.file);
      const pos = [];
      for (const node of doc.getRoot().listNodes()) {
        const mesh = node.getMesh(); if (!mesh) continue;
        const w = node.getWorldMatrix();
        for (const prim of mesh.listPrimitives()) {
          const a = prim.getAttribute('POSITION').getArray();
          const nAttr = prim.getAttribute('NORMAL');
          const n = nAttr ? nAttr.getArray() : null;
          for (let i = 0; i < a.length; i += 3) {
            if (n) {
              const nz = w[2]*n[i] + w[6]*n[i+1] + w[10]*n[i+2];
              const nl = Math.hypot(w[0]*n[i]+w[4]*n[i+1]+w[8]*n[i+2], w[1]*n[i]+w[5]*n[i+1]+w[9]*n[i+2], nz) || 1;
              if (nz / nl < TOP_NORMAL_MIN) continue;
            }
            const x = a[i], y = a[i+1], z = a[i+2];
            pos.push(w[0]*x+w[4]*y+w[8]*z+w[12], w[1]*x+w[5]*y+w[9]*z+w[13], w[2]*x+w[6]*y+w[10]*z+w[14]);
          }
        }
      }
      cache[t.file] = Float32Array.from(pos);
    }
    const p = cache[t.file], r = t.r, o = t.o;

    // --- Local edge expansion (closes cracks between tiles) ---------------
    // Grow the tile MARGIN world-metres outward on every side, in its own
    // local plane. Applied identically by the shader and collision at runtime.
    let lx0 = Infinity, lx1 = -Infinity, ly0 = Infinity, ly1 = -Infinity;
    for (let i = 0; i < p.length; i += 3) {
      if (p[i] < lx0) lx0 = p[i]; if (p[i] > lx1) lx1 = p[i];
      if (p[i+1] < ly0) ly0 = p[i+1]; if (p[i+1] > ly1) ly1 = p[i+1];
    }
    const sx = Math.hypot(r[0], r[3], r[6]), sy = Math.hypot(r[1], r[4], r[7]);
    const kx = 1 + 2 * MARGIN / (sx * (lx1 - lx0));
    const ky = 1 + 2 * MARGIN / (sy * (ly1 - ly0));
    const cx = (lx0 + lx1) / 2, cy = (ly0 + ly1) / 2;
    t.expand = [kx, ky, cx, cy];

    const W = new Float32Array(p.length);
    let minX = Infinity, maxX = -Infinity, minZ = Infinity, maxZ = -Infinity;
    for (let i = 0; i < p.length; i += 3) {
      const x = cx + (p[i] - cx) * kx, y = cy + (p[i+1] - cy) * ky, z = p[i+2];
      const wx = r[0]*x + r[1]*y + r[2]*z + o[0];
      const wy = r[3]*x + r[4]*y + r[5]*z + o[1];
      const wz = r[6]*x + r[7]*y + r[8]*z + o[2];
      W[i] = wx; W[i+1] = wy; W[i+2] = wz;
      if (wx < minX) minX = wx; if (wx > maxX) maxX = wx; if (wz < minZ) minZ = wz; if (wz > maxZ) maxZ = wz;
    }
    t.minX = minX; t.minZ = minZ; t.maxX = maxX; t.maxZ = maxZ;
    t.nx = Math.ceil((maxX - minX) / CELL); t.nz = Math.ceil((maxZ - minZ) / CELL);
    // top-surface height per cell
    const h = new Float32Array(t.nx * t.nz).fill(NaN);
    for (let i = 0; i < W.length; i += 3) {
      const ix = Math.min(t.nx - 1, Math.floor((W[i] - minX) / CELL));
      const iz = Math.min(t.nz - 1, Math.floor((W[i+2] - minZ) / CELL));
      const k = iz * t.nx + ix;
      if (!(h[k] >= W[i+1])) h[k] = W[i+1];
    }
    // fill any empty cells from neighbours
    for (let pass = 0; pass < 8; pass++) for (let iz = 0; iz < t.nz; iz++) for (let ix = 0; ix < t.nx; ix++) {
      const k = iz * t.nx + ix; if (!isNaN(h[k])) continue;
      let s = 0, n = 0;
      for (const [dx, dz] of [[1,0],[-1,0],[0,1],[0,-1]]) {
        const jx = ix + dx, jz = iz + dz; if (jx < 0 || jz < 0 || jx >= t.nx || jz >= t.nz) continue;
        const v = h[jz * t.nx + jx]; if (!isNaN(v)) { s += v; n++; }
      }
      if (n) h[k] = s / n;
    }
    t.h = h;
  }

  const heightAt = (t, x, z) => {
    // Coverage is decided on the tile's own grid, so a tile always covers
    // every one of its own sample points (incl. the last partial row/column).
    // Tiles also "reach" EXTEND metres past their edge (edge height held
    // constant) so that two tiles separated by a small gap still see each
    // other and their rims meet at a common height.
    let ix = Math.floor((x - t.minX) / CELL);
    let iz = Math.floor((z - t.minZ) / CELL);
    const r = Math.ceil(EXTEND / CELL);
    if (ix < -r || iz < -r || ix >= t.nx + r || iz >= t.nz + r) return undefined;
    ix = Math.min(Math.max(ix, 0), t.nx - 1);
    iz = Math.min(Math.max(iz, 0), t.nz - 1);
    const v = t.h[iz * t.nx + ix]; return isNaN(v) ? undefined : v;
  };
  // Signed distance to the tile's edge: positive inside, negative outside.
  // Weight fades 1 -> 0 across +-HALF metres centred on the edge, so where two
  // tiles meet both weigh 0.5 and the height difference is spread evenly
  // over the full band instead of being squeezed into a cliff.
  const weightAt = (t, x, z) => {
    const d = Math.min(x - t.minX, t.maxX - x, z - t.minZ, t.maxZ - z);
    return Math.max(MIN_W, smooth(-HALF, HALF, d));
  };

  for (const f of fs.readdirSync(OUT)) if (f.endsWith('.json')) fs.unlinkSync(OUT + f);
  console.log(`band=${BAND}m  cell=${CELL}m  tiles=${tiles.length}`);
  for (const t of tiles) {
    const data = new Array(t.nx * t.nz).fill(0);
    let maxAbs = 0, changed = 0;
    for (let iz = 0; iz < t.nz; iz++) for (let ix = 0; ix < t.nx; ix++) {
      const x = t.minX + (ix + 0.5) * CELL, z = t.minZ + (iz + 0.5) * CELL;
      const own = t.h[iz * t.nx + ix]; if (isNaN(own)) continue;
      let sw = 0, sh = 0;
      for (const u of tiles) {
        const hu = heightAt(u, x, z); if (hu === undefined) continue;
        const w = weightAt(u, x, z); sw += w; sh += w * hu;
      }
      const d = sh / sw - own;
      data[iz * t.nx + ix] = Math.round(d * 1000) / 1000;
      if (Math.abs(d) > 0.01) changed++;
      maxAbs = Math.max(maxAbs, Math.abs(d));
    }
    fs.writeFileSync(OUT + t.name + '.json', JSON.stringify({
      tile: t.name, cell: CELL, band: BAND, margin: MARGIN, expand: t.expand,
      min_x: t.minX, min_z: t.minZ, nx: t.nx, nz: t.nz, max_abs: maxAbs, data }));
    console.log(`  ${t.name.padEnd(22)} grid ${t.nx}x${t.nz}  cells adjusted ${String(changed).padStart(6)}  max correction ${maxAbs.toFixed(2)} m`);
  }
})();

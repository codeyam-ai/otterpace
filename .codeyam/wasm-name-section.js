// codeyam-generated — DO NOT EDIT.
// codeyam-editor: 0.1.7  build: 283adba28f3fc30f058c87b4f92900dccc81f9e5  source-sha256: aa5694243e6362c732bd09f716566510b1fec8b8d697594b743123636512549c
// Read the parts of a wasm binary that rendered-source attribution needs: each
// defined function's name and the byte range of its body. Parsed from the bytes
// rather than asked of DevTools (`Debugger.disassembleWasmModule`), whose text
// for a real app (14 MB of wasm) overflows a JS string.

function readLeb(bytes, pos) {
  let result = 0;
  let shift = 0;
  let byte;
  do {
    byte = bytes[pos++];
    result += (byte & 0x7f) * 2 ** shift;
    shift += 7;
  } while (byte & 0x80);
  return [result, pos];
}

function readName(bytes, pos) {
  const [len, start] = readLeb(bytes, pos);
  const name = Buffer.from(bytes.subarray(start, start + len)).toString("utf8");
  return [name, start + len];
}

// The function imports in an import section. Function indices count imports
// first, so the name section's indices are offset from the code section's by
// this many.
function countImportedFunctions(bytes, pos) {
  let count;
  let imported = 0;
  [count, pos] = readLeb(bytes, pos);
  for (let i = 0; i < count; i++) {
    [, pos] = readName(bytes, pos); // module
    [, pos] = readName(bytes, pos); // field
    const kind = bytes[pos++];
    if (kind === 0) {
      [, pos] = readLeb(bytes, pos); // type index
      imported++;
    } else if (kind === 1) {
      pos += 1; // reftype
      const flags = bytes[pos++];
      [, pos] = readLeb(bytes, pos);
      if (flags & 1) [, pos] = readLeb(bytes, pos);
    } else if (kind === 2) {
      const flags = bytes[pos++];
      [, pos] = readLeb(bytes, pos);
      if (flags & 1) [, pos] = readLeb(bytes, pos);
    } else if (kind === 3) {
      pos += 2; // valtype + mutability
    } else if (kind === 4) {
      pos += 1; // tag attribute
      [, pos] = readLeb(bytes, pos);
    }
  }
  return imported;
}

// Each code-section body as `[start, end)`: the ranges V8 reports as
// `functionBodyOffsets`, give or take the locals header at the start.
function readBodies(bytes, pos) {
  const bodies = [];
  let count;
  [count, pos] = readLeb(bytes, pos);
  for (let i = 0; i < count; i++) {
    let size;
    [size, pos] = readLeb(bytes, pos);
    bodies.push([pos, pos + size]);
    pos += size;
  }
  return bodies;
}

// The function-name subsection of a `name` custom section, merged into `names`.
function readFunctionNames(bytes, pos, end, names) {
  while (pos < end) {
    const sub = bytes[pos++];
    let size;
    [size, pos] = readLeb(bytes, pos);
    const subEnd = pos + size;
    if (sub === 1) {
      let count;
      let p;
      [count, p] = readLeb(bytes, pos);
      for (let i = 0; i < count; i++) {
        let index;
        let name;
        [index, p] = readLeb(bytes, p);
        [name, p] = readName(bytes, p);
        names.set(index, name);
      }
    }
    pos = subEnd;
  }
}

// The module's imported-function count, its `name` section's function names
// (function index → name), and each defined function's body range. A module
// without a name section yields an empty map: there is nothing to attribute.
function parseWasmFunctionNames(bytes) {
  const names = new Map();
  let bodies = [];
  let importedFunctions = 0;
  let pos = 8; // magic + version
  while (pos < bytes.length) {
    const id = bytes[pos++];
    let size;
    [size, pos] = readLeb(bytes, pos);
    const end = pos + size;
    if (id === 2) {
      importedFunctions = countImportedFunctions(bytes, pos);
    } else if (id === 10) {
      bodies = readBodies(bytes, pos);
    } else if (id === 0) {
      const [sectionName, p] = readName(bytes, pos);
      if (sectionName === "name") readFunctionNames(bytes, p, end, names);
    }
    pos = end;
  }
  return { importedFunctions, names, bodies };
}

module.exports = { parseWasmFunctionNames };

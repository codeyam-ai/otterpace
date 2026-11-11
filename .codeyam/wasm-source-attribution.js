// codeyam-generated — DO NOT EDIT.
// codeyam-editor: 0.1.7  build: 283adba28f3fc30f058c87b4f92900dccc81f9e5  source-sha256: d15087f22047b95375c0e11d736bf235bc7e4e062996330e3b00b5e705668f75
// Map a wasm function back to the workspace source file that declares it, and
// decide which function-entry breakpoints still have something to learn.
//
// Stack assumption: Rust workspace crates compiled to wasm with rustc's
// demangled paths kept in the name section (a trunk dev build keeps them), and
// crate roots discovered through `cargo metadata`. Other stacks attribute
// through their own source (see docs/rendered-source-attribution.md).

const fs = require("fs");
const path = require("path");
const { execFileSync } = require("child_process");

// Workspace crates as `crate_ident → { srcDir, roots }`, project-relative.
// `roots` holds every target root (lib.rs AND main.rs share a crate name), so
// a path that names no module file is attributed to all of them — reporting
// more files is the safe direction.
function workspaceCrates(projectDir, exec = execFileSync) {
  const raw = exec("cargo", ["metadata", "--no-deps", "--format-version", "1", "--offline"], {
    cwd: projectDir,
    encoding: "utf8",
    maxBuffer: 64 * 1024 * 1024,
  });
  const crates = new Map();
  for (const pkg of JSON.parse(raw).packages) {
    for (const target of pkg.targets) {
      if (!target.kind.some((k) => k === "lib" || k === "bin" || k === "cdylib")) continue;
      const ident = target.name.replace(/-/g, "_");
      const root = path.relative(projectDir, target.src_path).split(path.sep).join("/");
      const entry = crates.get(ident) || { srcDir: path.posix.dirname(root), roots: [] };
      if (!entry.roots.includes(root)) entry.roots.push(root);
      crates.set(ident, entry);
    }
  }
  return crates;
}

// The file a module path's segments resolve to, descending `<seg>.rs` or
// `<seg>/mod.rs` from the crate's source dir while such a file exists. Segments
// past the last file are items or inline modules inside it. `null` when not
// even the first segment names a module file — the caller then reports every
// root. A crate root is never a submodule: `app::main` is the item `main`,
// not a module backed by the bin root `main.rs`.
function resolveModuleFile(projectDir, crate, segments, exists = fs.existsSync) {
  let dir = crate.srcDir;
  let file = null;
  for (const seg of segments) {
    const flat = `${dir}/${seg}.rs`;
    const nested = `${dir}/${seg}/mod.rs`;
    if (crate.roots.includes(flat)) {
      break;
    } else if (exists(path.join(projectDir, flat))) {
      file = flat;
    } else if (exists(path.join(projectDir, nested))) {
      file = nested;
    } else {
      break;
    }
    dir = `${dir}/${seg}`;
  }
  return file;
}

const PATH_PATTERN = /[A-Za-z_][A-Za-z0-9_]*(?:::[A-Za-z_][A-Za-z0-9_]*)+/g;
const LEGACY_HASH_SEGMENT = /^h[0-9a-f]{16}$/;

// Every workspace source file a demangled function name points into. A name
// can mention several paths (`<app::a::T as app::b::Tr>::f`, or a generic
// instantiated with an app closure); all of them are reported, since the code
// may live in either module. Names outside the workspace map to nothing.
function filesForFunctionName(name, crates, projectDir, exists = fs.existsSync) {
  const files = new Set();
  // v0-mangled names carry a crate disambiguator: `app[3429bd42a6f35fe9]::…`.
  const plain = name.replace(/\[[0-9a-f]+\]/g, "");
  for (const match of plain.matchAll(PATH_PATTERN)) {
    const [head, ...rest] = match[0].split("::");
    const crate = crates.get(head);
    if (!crate) continue;
    const segments = rest.filter((s) => !LEGACY_HASH_SEGMENT.test(s));
    const file = resolveModuleFile(projectDir, crate, segments, exists);
    if (file) files.add(file);
    else crate.roots.forEach((r) => files.add(r));
  }
  return files;
}

// The watched function whose body holds byte offset `column`, or undefined.
function functionRangeAt(ranges, column) {
  return ranges.find((r) => column >= r.start && column < r.end);
}

// The ranges whose breakpoint can go: every live one whose files are all
// already reported, since a hit there would teach nothing. This caps pauses at
// about one per FILE — on egui, one pause per function stalled the app's WebGL
// startup and it never signalled ready. `"function"` granularity keeps every
// breakpoint until its own function runs (a measurement mode).
function retirableBreakpoints(ranges, sources, granularity) {
  if (granularity === "function") return [];
  return ranges.filter((r) => r.breakpointId && [...r.files].every((f) => sources.has(f)));
}

module.exports = {
  workspaceCrates,
  resolveModuleFile,
  filesForFunctionName,
  functionRangeAt,
  retirableBreakpoints,
};

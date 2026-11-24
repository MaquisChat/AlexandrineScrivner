// Checks the session.json schema against real files:
//   every examples/*/session.json and every valid/*.json must be accepted,
//   every invalid/*.json must be rejected.
// Run with: npm run validate   (from this folder)
import { readFileSync, readdirSync, existsSync } from "node:fs";
import { join, dirname } from "node:path";
import { fileURLToPath } from "node:url";
import Ajv2020 from "ajv/dist/2020.js";

const here = dirname(fileURLToPath(import.meta.url));
const readJson = (path) => JSON.parse(readFileSync(path, "utf8"));

const schema = readJson(join(here, "field-session.v1.schema.json"));
const ajv = new Ajv2020({ strict: true, allErrors: true });
const validate = ajv.compile(schema);
const kinds = ["marker", "text", "photo", "video", "ink"];

const sentence = (e) => `${e.instancePath || "(top level)"} ${e.message}`;

// An item is one of five shapes. When an item fits none, the validator reports a failure for
// every shape, which hides the real fault. So an item is checked again against the one shape
// its "kind" names, and those are the reasons shown.
function reasons(errors, data) {
  const out = [];
  const seenItems = new Set();
  for (const e of errors ?? []) {
    const item = /^\/items\/(\d+)/.exec(e.instancePath);
    if (!item) {
      out.push(sentence(e));
      continue;
    }
    const index = Number(item[1]);
    if (seenItems.has(index)) continue;
    seenItems.add(index);
    const kind = data?.items?.[index]?.kind;
    if (!kinds.includes(kind)) {
      out.push(`/items/${index}/kind must be one of: ${kinds.join(", ")}`);
      continue;
    }
    const shape = ajv.getSchema(`${schema.$id}#/$defs/${kind}`);
    shape(data.items[index]);
    for (const inner of shape.errors ?? []) {
      out.push(`/items/${index}${inner.instancePath} ${inner.message}`);
    }
  }
  return [...new Set(out)].slice(0, 3).join("; ");
}

let failed = false;
let valid = 0;
let rejected = 0;

function mustAccept(file, shown) {
  const data = readJson(file);
  if (validate(data)) {
    console.log(`ok   ${shown}`);
    valid += 1;
  } else {
    console.log(`FAIL ${shown}: ${reasons(validate.errors, data)}`);
    failed = true;
  }
}

const examplesDir = join(here, "examples");
let examples = 0;
for (const name of readdirSync(examplesDir).sort()) {
  const file = join(examplesDir, name, "session.json");
  if (!existsSync(file)) continue;
  mustAccept(file, `examples/${name}/session.json`);
  examples += 1;
}

const validDir = join(here, "valid");
for (const name of readdirSync(validDir).filter((n) => n.endsWith(".json")).sort()) {
  mustAccept(join(validDir, name), `valid/${name}`);
}

const invalidDir = join(here, "invalid");
for (const name of readdirSync(invalidDir).filter((n) => n.endsWith(".json")).sort()) {
  const shown = `invalid/${name}`;
  const data = readJson(join(invalidDir, name));
  if (validate(data)) {
    console.log(`FAIL ${shown}: the schema accepted a sample that must be rejected`);
    failed = true;
  } else {
    console.log(`ok   ${shown} (rejected: ${reasons(validate.errors, data)})`);
    rejected += 1;
  }
}

if (examples === 0) {
  console.log("FAIL no example session was found to check");
  failed = true;
}

if (failed) {
  console.log("SCHEMA CHECK FAILED");
  process.exit(1);
}
console.log(`SCHEMA CHECK OK (${valid} valid, ${rejected} rejected)`);

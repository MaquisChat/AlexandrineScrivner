// Checks the session.json schema against real files:
//   every examples/*/session.json must be accepted,
//   every invalid/*.json must be rejected.
// Run with: npm run validate   (from this folder)
import { readFileSync, readdirSync, existsSync } from "node:fs";
import { join, dirname } from "node:path";
import { fileURLToPath } from "node:url";
import Ajv2020 from "ajv/dist/2020.js";

const here = dirname(fileURLToPath(import.meta.url));
const readJson = (path) => JSON.parse(readFileSync(path, "utf8"));

const ajv = new Ajv2020({ strict: true, allErrors: true });
const validate = ajv.compile(readJson(join(here, "field-session.v1.schema.json")));

const describe = (errors) =>
  (errors ?? []).filter((e) => e.keyword !== "if").slice(0, 3).map((e) => `${e.instancePath || "(top level)"} ${e.message}`).join("; ");

let failed = false;
let valid = 0;
let rejected = 0;

const examplesDir = join(here, "examples");
for (const name of readdirSync(examplesDir).sort()) {
  const file = join(examplesDir, name, "session.json");
  if (!existsSync(file)) continue;
  const shown = `examples/${name}/session.json`;
  if (validate(readJson(file))) {
    console.log(`ok   ${shown}`);
    valid += 1;
  } else {
    console.log(`FAIL ${shown}: ${describe(validate.errors)}`);
    failed = true;
  }
}

const invalidDir = join(here, "invalid");
for (const name of readdirSync(invalidDir).filter((n) => n.endsWith(".json")).sort()) {
  const shown = `invalid/${name}`;
  if (validate(readJson(join(invalidDir, name)))) {
    console.log(`FAIL ${shown}: the schema accepted a sample that must be rejected`);
    failed = true;
  } else {
    console.log(`ok   ${shown} (rejected: ${describe(validate.errors)})`);
    rejected += 1;
  }
}

if (valid === 0) {
  console.log("FAIL no example session was found to check");
  failed = true;
}

if (failed) {
  console.log("SCHEMA CHECK FAILED");
  process.exit(1);
}
console.log(`SCHEMA CHECK OK (${valid} valid, ${rejected} rejected)`);

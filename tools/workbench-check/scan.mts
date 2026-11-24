// Runs the research workbench's own import code over a session folder and compares what the
// workbench would take from it with what the session's own record says.
//
// Started by tools/workbench-check.sh, with the workbench's own tsx, from inside a workbench
// checkout:  tsx scan.mts WORKBENCH_CHECKOUT SESSION_FOLDER NAMING_CASES_JSON
//
// It uses three things from the workbench, by path:
//   deviceAdapter    packages/library/src/import/device.ts   what its device import finds in a folder
//   extractExif      packages/library/src/extract/exif.ts    what it reads from inside one media file
//   sanitizeSegment  packages/core/src/naming.ts             how it cleans a folder name
import { readFileSync } from "node:fs";
import { join, resolve } from "node:path";
import { pathToFileURL } from "node:url";

const [workbenchArg, sessionArg, namingArg] = process.argv.slice(2);
if (!workbenchArg || !sessionArg || !namingArg) {
  console.log("usage: tsx scan.mts WORKBENCH_CHECKOUT SESSION_FOLDER NAMING_CASES_JSON");
  process.exit(2);
}
const workbench = resolve(workbenchArg);
const folder = resolve(sessionArg);
const fromWorkbench = (path: string) => import(pathToFileURL(join(workbench, path)).href);

const { deviceAdapter } = await fromWorkbench("packages/library/src/import/device.ts");
const { extractExif, shutdownExif } = await fromWorkbench("packages/library/src/extract/exif.ts");
const { sanitizeSegment } = await fromWorkbench("packages/core/src/naming.ts");

interface Place { lat: number; lon: number; alt?: number }
interface Expected { type: string; at: number; utcOffset: string; gps?: Place }

// What session.json says about each media file.
const session = JSON.parse(readFileSync(join(folder, "session.json"), "utf8"));
const expected = new Map<string, Expected>();
for (const span of session.spans) {
  expected.set(span.file, { type: "field-recording", at: Date.parse(span.startedAt), utcOffset: span.utcOffset });
}
for (const item of session.items) {
  if (item.kind === "photo") {
    expected.set(item.file, { type: "field-photo", at: Date.parse(item.at), utcOffset: item.utcOffset, gps: item.gps });
  } else if (item.kind === "video") {
    expected.set(item.file, { type: "field-video", at: Date.parse(item.at), utcOffset: item.utcOffset, gps: item.gps });
  }
}

let failures = 0;
const fail = (line: string) => {
  failures += 1;
  console.log(`FAIL ${line}`);
};

// 1. What the workbench's device import finds in the folder.
console.log("== What the workbench's device import finds");
const notes: string[] = [];
const seen = new Set<string>();
const scan = deviceAdapter(folder, { researcherName: "R" }).scan(new AbortController().signal, { note: (text: string) => notes.push(text) });
for await (const item of scan) {
  const key: string = item.key;
  const type: string = item.referenceMetadata?.type;
  const title: string = item.referenceMetadata?.title?.variants?.[0]?.value ?? "";
  const want = expected.get(key);
  if (!want) {
    fail(`${key}: the workbench would import this, but session.json does not list it (as ${type}, "${title}")`);
    continue;
  }
  seen.add(key);
  const problems: string[] = [];
  if (item.files.length !== 1 || item.pairs) problems.push(`arrived as ${item.files.length} files joined together, not one file on its own`);
  if (type !== want.type) problems.push(`arrived as ${type}, not ${want.type}`);

  const file = item.files[0];
  const metadata = file.metadata ?? {};
  if (!metadata.capturedAt) {
    problems.push("the workbench found no capture time with a known time zone");
  } else if (Math.abs(Date.parse(metadata.capturedAt) - want.at) > 1000) {
    problems.push(`capture time ${metadata.capturedAt}, but session.json says ${new Date(want.at).toISOString()}`);
  }
  if (metadata.tzOffset !== want.utcOffset) {
    problems.push(`offset from UTC ${metadata.tzOffset ?? "none"}, but session.json says ${want.utcOffset}`);
  }

  // 2. What the workbench reads from inside the file about its place.
  const media = (await extractExif(join(folder, key))).media ?? {};
  const gps: Place | undefined = media.gps;
  if (want.gps && !gps) {
    problems.push("the workbench found no place in the file, but session.json gives one");
  } else if (!want.gps && gps) {
    problems.push(`the workbench found a place in the file (${gps.lat}, ${gps.lon}), but session.json has none for it`);
  } else if (want.gps && gps) {
    const apart = Math.max(Math.abs(want.gps.lat - gps.lat), Math.abs(want.gps.lon - gps.lon));
    if (apart > 0.0001) problems.push(`place ${gps.lat}, ${gps.lon}, but session.json says ${want.gps.lat}, ${want.gps.lon}`);
    if (want.gps.alt !== undefined && gps.alt !== undefined && Math.abs(want.gps.alt - gps.alt) > 1) {
      problems.push(`altitude ${gps.alt} m, but session.json says ${want.gps.alt} m`);
    }
  }
  if (media.capturedAtSource === "modified") problems.push("the workbench fell back to the file's modified time, which it treats as unverified");

  const summary = `${type}, "${title}", ${file.mime}, taken ${metadata.capturedAt ?? "?"} (${metadata.tzOffset ?? "no offset"})` +
    (gps ? `, at ${gps.lat}, ${gps.lon}${gps.alt !== undefined ? `, ${gps.alt} m` : ""}` : ", no place") +
    (metadata.device ? `, ${metadata.device}` : "");
  if (problems.length) fail(`${key}: ${problems.join("; ")}`);
  else console.log(`ok   ${key}: ${summary}`);
}
for (const key of expected.keys()) {
  if (!seen.has(key)) fail(`${key}: session.json lists it, but the workbench's device import did not pick it up`);
}
for (const note of notes) console.log(`note from the workbench: ${note}`);

// 3. Would the workbench rename a folder the recorder made?
console.log("== Folder names through the workbench's own cleaning");
const cases: Array<{ title: string; folder: string }> = JSON.parse(readFileSync(resolve(namingArg), "utf8"));
let unchanged = 0;
for (const { title, folder: name } of cases) {
  const cleaned: string = sanitizeSegment(name);
  if (cleaned === name) unchanged += 1;
  else fail(`a session titled ${JSON.stringify(title)} gets the folder name ${JSON.stringify(name)}, which the workbench would change to ${JSON.stringify(cleaned)}`);
}
console.log(`${unchanged} of ${cases.length} folder names are left exactly as they are`);

await shutdownExif();
console.log(`RESULT ${failures === 0 ? "OK" : "FAILED"} files=${expected.size} names=${cases.length} failures=${failures}`);
process.exit(failures === 0 ? 0 : 1);

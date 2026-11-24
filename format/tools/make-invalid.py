"""Writes format/invalid/*.json: the worked example's session.json with one thing wrong in each.

The schema check (npm run validate, in format/) must reject every one of them, and so must the
Swift reader (SchemaSamplesTests). Run this again whenever the worked example changes.

Usage, from the top of the repository: python3 format/tools/make-invalid.py .
"""
import copy
import glob
import json
import os
import sys

root = sys.argv[1]
examples = sorted(glob.glob(os.path.join(root, "format", "examples", "*", "session.json")))
assert len(examples) == 1, examples
with open(examples[0], encoding="utf-8") as handle:
    good = json.load(handle)

out_dir = os.path.join(root, "format", "invalid")
os.makedirs(out_dir, exist_ok=True)
for stale in glob.glob(os.path.join(out_dir, "*.json")):
    os.remove(stale)


def first(doc, kind):
    return next(item for item in doc["items"] if item["kind"] == kind)


def placed(doc, kind):
    return next(item for item in doc["items"] if item["kind"] == kind and "spanId" in item)


samples = {}

doc = copy.deepcopy(good)
del doc["device"]
samples["missing-device"] = doc

doc = copy.deepcopy(good)
doc["version"] = 2
samples["wrong-version"] = doc

doc = copy.deepcopy(good)
doc["exportedAt"] = "2026-11-23T12:00:00.000Z"
samples["unknown-top-level-key"] = doc

doc = copy.deepcopy(good)
first(doc, "text")["kind"] = "song"
samples["unknown-item-kind"] = doc

doc = copy.deepcopy(good)
doc["spans"][0]["startedAt"] = "2026-11-23T10:42:10Z"
samples["instant-without-milliseconds"] = doc

doc = copy.deepcopy(good)
doc["spans"][0]["sha256"] = doc["spans"][0]["sha256"].upper()
samples["uppercase-hash"] = doc

doc = copy.deepcopy(good)
del placed(doc, "text")["spanId"]
samples["offset-without-span"] = doc

doc = copy.deepcopy(good)
del doc["spans"][0]["endedBy"]
samples["span-duration-without-ended-by"] = doc

doc = copy.deepcopy(good)
first(doc, "photo")["file"] = "/photos/photo-0001.heic"
samples["absolute-file-path"] = doc

doc = copy.deepcopy(good)
first(doc, "photo")["file"] = "photos/.photo-0001.heic"
samples["hidden-file-path"] = doc

doc = copy.deepcopy(good)
text = placed(doc, "text")
doc["items"].append({
    "id": "01a207ff-bc48-7000-8000-000000000001",
    "kind": "ink",
    "at": text["at"],
    "utcOffset": text["utcOffset"],
    "file": "ink/ink-0001.png",
    "data": "ink/ink-0001.drawing",
    "strokes": [{"at": text["at"], "bounds": [0, 0, 10]}],
})
samples["bounds-with-three-numbers"] = doc

doc = copy.deepcopy(good)
text = placed(doc, "text")
doc["items"].append({
    "id": "01a207ff-bc48-7000-8000-000000000002",
    "kind": "ink",
    "at": text["at"],
    "utcOffset": text["utcOffset"],
    "file": "ink/ink-0001.png",
    "data": "ink/ink-0001.drawing",
    "strokes": [{"at": text["at"], "offsetMs": 1000, "bounds": [0, 0, 10, 10]}],
})
samples["stroke-offset-without-span"] = doc

doc = copy.deepcopy(good)
doc["startLocation"]["lat"] = 91
samples["latitude-out-of-range"] = doc

doc = copy.deepcopy(good)
placed(doc, "text")["offsetMs"] = -1
samples["negative-offset"] = doc

doc = copy.deepcopy(good)
del first(doc, "video")["sound"]
samples["video-without-sound"] = doc

for name, doc in samples.items():
    with open(os.path.join(out_dir, name + ".json"), "w", encoding="utf-8") as handle:
        json.dump(doc, handle, indent=2, ensure_ascii=False)
        handle.write("\n")
print(f"wrote {len(samples)} samples")

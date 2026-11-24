"""Makes small, real media files for a session folder, from what its session.json says.

For every recording span, photo and video clip that session.json lists, this writes a file of the
right kind and length, and writes inside it the same times and places an iPhone's own camera
would (design spec, section 6.3). The files hold a tone, a flat colour or a test pattern: nothing
recorded from life.

It is used once, to give the worked example in format/examples real media. After running it,
regenerate the example so its checksums match the new files:

    UPDATE_EXAMPLE=1 swift test --package-path Core

Usage, from the top of the repository:

    python3 format/tools/make-example-media.py SESSION_FOLDER EXIFTOOL

EXIFTOOL is the path printed by tools/get-exiftool.sh. Also needs ffmpeg (with libx264 and aac)
and the Python package pillow-heif.
"""
import json
import os
import subprocess
import sys
from datetime import datetime, timedelta, timezone

from PIL import Image
import pillow_heif

MAKE = "Apple"
MODEL = "iPhone 17 Pro"
LENS = "iPhone 17 Pro back camera 6.765mm f/1.78"
PHOTO_COLOURS = [(196, 138, 74), (88, 122, 146), (120, 150, 96), (150, 110, 140)]


def instant(text):
    """session.json's "2026-11-23T04:57:10.120Z" as a datetime in UTC."""
    return datetime.strptime(text, "%Y-%m-%dT%H:%M:%S.%fZ").replace(tzinfo=timezone.utc)


def offset_seconds(text):
    """"+05:45" as seconds east of UTC."""
    sign = -1 if text[0] == "-" else 1
    return sign * (int(text[1:3]) * 3600 + int(text[4:6]) * 60)


def local(moment, offset_text):
    """The clock reading at that offset, as ExifTool wants it: "2026:11:23 10:42:10"."""
    return (moment + timedelta(seconds=offset_seconds(offset_text))).strftime("%Y:%m:%d %H:%M:%S")


def run(command):
    subprocess.run(command, check=True)


def ffmpeg(arguments, out):
    # bitexact and no metadata: nothing is written into the file except what this script puts there.
    run(["ffmpeg", "-hide_banner", "-loglevel", "error", "-y", "-threads", "1"] + arguments +
        ["-map_metadata", "-1", "-fflags", "+bitexact", out])


def tone(seconds, frequency):
    return ["-f", "lavfi", "-i", f"sine=frequency={frequency}:sample_rate=16000:duration={seconds:.3f}"]


AUDIO_CODEC = ["-filter:a", "volume=0.05", "-ac", "1", "-c:a", "aac", "-b:a", "12k", "-flags:a", "+bitexact"]


def quicktime_tags(exiftool, path, moment, offset_text, gps):
    utc = moment.strftime("%Y:%m:%d %H:%M:%S") + "Z"
    tags = [f"-QuickTime:{name}={utc}" for name in
            ("CreateDate", "ModifyDate", "TrackCreateDate", "TrackModifyDate", "MediaCreateDate", "MediaModifyDate")]
    tags += [
        f"-Keys:CreationDate={local(moment, offset_text)}{offset_text}",
        f"-Keys:Make={MAKE}",
        f"-Keys:Model={MODEL}",
    ]
    if gps:
        # ExifTool takes "lat, lon, alt" and writes Apple's ISO 6709 form, e.g. +27.7046+085.3076+1300.000/
        place = f"{gps['lat']}, {gps['lon']}" + (f", {gps['alt']}" if "alt" in gps else "")
        tags.append(f"-Keys:GPSCoordinates={place}")
    run([exiftool, "-q", "-overwrite_original", "-api", "QuickTimeUTC=1"] + tags + [path])


def make_audio(exiftool, path, span):
    seconds = span["durationMs"] / 1000
    ffmpeg(tone(seconds, 220) + AUDIO_CODEC, path)
    quicktime_tags(exiftool, path, instant(span["startedAt"]), span["utcOffset"], None)


def make_clip(exiftool, path, item):
    seconds = item["durationMs"] / 1000
    picture = ["-f", "lavfi", "-i", f"testsrc2=size=160x120:rate=5:duration={seconds:.3f}"]
    video = ["-c:v", "libx264", "-preset", "veryslow", "-crf", "36", "-pix_fmt", "yuv420p", "-flags:v", "+bitexact"]
    if item["sound"]:
        ffmpeg(picture + tone(seconds, 330) + video + AUDIO_CODEC, path)
    else:
        ffmpeg(picture + video + ["-an"], path)
    quicktime_tags(exiftool, path, instant(item["at"]), item["utcOffset"], item.get("gps"))


def make_photo(exiftool, path, item, number):
    Image.new("RGB", (320, 240), PHOTO_COLOURS[number % len(PHOTO_COLOURS)]).save(path, quality=60)
    moment = instant(item["at"])
    offset_text = item["utcOffset"]
    clock = local(moment, offset_text)
    milliseconds = f"{moment.microsecond // 1000:03d}"
    tags = [
        f"-DateTimeOriginal={clock}", f"-SubSecTimeOriginal={milliseconds}", f"-OffsetTimeOriginal={offset_text}",
        f"-CreateDate={clock}", f"-SubSecTimeDigitized={milliseconds}", f"-OffsetTimeDigitized={offset_text}",
        f"-Make={MAKE}", f"-Model={MODEL}", f"-LensModel={LENS}",
    ]
    gps = item.get("gps")
    if gps:
        tags += [
            f"-GPSLatitude={abs(gps['lat'])}", f"-GPSLatitudeRef={'S' if gps['lat'] < 0 else 'N'}",
            f"-GPSLongitude={abs(gps['lon'])}", f"-GPSLongitudeRef={'W' if gps['lon'] < 0 else 'E'}",
        ]
        if "alt" in gps:
            tags += [f"-GPSAltitude={abs(gps['alt'])}", f"-GPSAltitudeRef={1 if gps['alt'] < 0 else 0}"]
    run([exiftool, "-q", "-overwrite_original"] + tags + [path])


def main():
    if len(sys.argv) != 3:
        sys.exit(__doc__)
    folder, exiftool = sys.argv[1], sys.argv[2]
    with open(os.path.join(folder, "session.json"), encoding="utf-8") as handle:
        session = json.load(handle)
    pillow_heif.register_heif_opener()

    made = []
    for span in session["spans"]:
        path = os.path.join(folder, span["file"])
        make_audio(exiftool, path, span)
        made.append(path)
    photos = 0
    for item in session["items"]:
        if item["kind"] not in ("photo", "video"):
            continue
        path = os.path.join(folder, item["file"])
        if item["kind"] == "photo":
            make_photo(exiftool, path, item, photos)
            photos += 1
        else:
            make_clip(exiftool, path, item)
        made.append(path)

    total = 0
    for path in made:
        size = os.path.getsize(path)
        total += size
        print(f"{size:>9,}  {os.path.relpath(path, folder)}")
    print(f"{total:>9,}  in all")


if __name__ == "__main__":
    main()

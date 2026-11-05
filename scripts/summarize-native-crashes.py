"""Keep native startup failure evidence and print useful frames in Actions logs."""

import json
import shutil
from pathlib import Path


def summarize(path):
    text = path.read_text(encoding="utf-8", errors="replace")
    print(f"\nCrash report: {path.name}")
    if path.suffix != ".ips":
        print(text[:24000])
        return
    try:
        # Apple's .ips format contains a metadata object followed by the report.
        decoder = json.JSONDecoder()
        _, end = decoder.raw_decode(text)
        report, _ = decoder.raw_decode(text[end:].lstrip())
    except (ValueError, TypeError):
        print(text[:24000])
        return
    for key in ("procName", "exception", "termination", "asi", "faultingThread"):
        if key in report:
            print(key + ": " + json.dumps(report[key], ensure_ascii=False))
    images = report.get("usedImages", [])
    for thread in report.get("threads", []):
        if not thread.get("triggered"):
            continue
        print("Crashed thread:")
        for frame in thread.get("frames", [])[:80]:
            index = frame.get("imageIndex", -1)
            name = images[index].get("name", "?") if 0 <= index < len(images) else "?"
            print(name, json.dumps(frame, ensure_ascii=False))


def main():
    output = Path("build/native-failure")
    output.mkdir(parents=True, exist_ok=True)
    roots = [
        Path.home() / "Library/Logs/DiagnosticReports",
        Path.home() / "Library/Developer/CoreSimulator/Devices",
    ]
    reports = []
    for root in roots:
        if root.exists():
            reports.extend(root.rglob("*ProfileBrowser*.ips"))
            reports.extend(root.rglob("*ProfileBrowser*.crash"))
    for index, report in enumerate(sorted(reports, key=lambda p: p.stat().st_mtime, reverse=True)[:12]):
        shutil.copy2(report, output / f"{index}-{report.name}")
        summarize(report)
    if not reports:
        print("No ProfileBrowser crash reports found; xcresult diagnostics will also be exported.")


if __name__ == "__main__":
    main()

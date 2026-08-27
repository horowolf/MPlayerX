#!/usr/bin/env python3
"""Regenerate localization/<version>/<lang>.lproj/MainMenu.strings.

The menu bar lives in a nib, so it is localized by shipping one
Base.lproj/MainMenu.nib plus a per-language .strings file keyed by object id,
which AppKit applies while loading the nib. Object ids change whenever
MainMenu.xib is edited in Xcode, so those files have to be regenerated rather
than hand-maintained -- that is what this script is for.

Translations come from the 1.0.x localized xibs still kept under
localization/<version>/<lang>.lproj/. Those are the pre-Swift nibs: they can no
longer be compiled and shipped (a nib built from one makes the app exit at
launch, see the note in the Makefile), but they remain the only record of what
each menu title was translated to. English title in the current nib is looked
up in a table extracted from them by object id.

    python3 tools/regenerate-menu-strings.py [version]

Run it from the repository root after any change to MainMenu.xib, then rebuild.
"""
import io
import os
import re
import sys

STRING_KEYS = ["NSContents", "NSAlternateContents", "NSToolTip", "NSTitle", "NSLabel"]
LEGACY_XIBS = ["MainMenu.xib", "Pref.xib", "VideoTuner.xib", "Equalizer.xib",
               "Inspector.xib", "SubEncoding.xib"]
NIB = "MPlayerX/Base.lproj/MainMenu.xib"

# Corrections applied on top of what the old xibs say. zh_TW was produced by
# converting the Simplified file, so besides Mainland vocabulary it carries
# outright errors: 頻道 is a television channel, not an audio one, and 預設 is
# "default", not "reset". zh_CN has neither and needs no overrides.
OVERRIDES = {
    "zh_TW.lproj": {
        "Half Size": "一半大小",
        "Channels": "聲道",
        "Reset Audio Delay": "重設聲音延遲",
        "Reset Subtitle Delay": "重設字幕延遲",
        "Reset To Normal Speed": "恢復正常播放速度",
        "Toggle Fillscreen": "切換填滿螢幕",
        "Quit MPlayerX": "結束 MPlayerX",
        "Clear Menu": "清除選單",
        "Snapshot": "快照",
        "Save As…": "另存新檔…",
        "Open Recent": "最近開啟的項目",
        "Fit To Screen": "符合螢幕大小",
        "Restore Aspect Ratio": "還原影格長寬比",
        "Restore": "還原",
        "Reset Frame Size": "重設畫面大小",
    "Move Frame To Center": "畫面置中",
        "Increase Window Size": "放大視窗",
        "Decrease Window Size": "縮小視窗",
        "Increase Frame Size": "放大畫面",
        "Increase Frame Size (minor)": "放大畫面（微調）",
        "Decrease Frame Size": "縮小畫面",
        "Decrease Frame Size (minor)": "縮小畫面（微調）",
        "Increase Volume": "提高音量",
        "Decrease Volume": "降低音量",
        "Increase Audio Delay": "增加聲音延遲",
        "Decrease Audio Delay": "減少聲音延遲",
        "Increase Subtitle Size": "放大字幕",
        "Decrease Subtitle Size": "縮小字幕",
        "Increase Subtitle Delay": "增加字幕延遲",
        "Decrease Subtitle Delay": "減少字幕延遲",
        "Left only": "僅左聲道",
        "Right only": "僅右聲道",
        "Left expanded": "左聲道擴展",
        "Right expanded": "右聲道擴展",
        "Show Letterbox": "顯示字幕黑邊",
        "Video Tuner": "影像調整器",
        "Equalizer": "等化器",
        "Donate...": "贊助…",
    },
}


def unescape(text):
    for a, b in (("&lt;", "<"), ("&gt;", ">"), ("&quot;", '"'),
                 ("&apos;", "'"), ("&amp;", "&")):
        text = text.replace(a, b)
    return text


def legacy_strings(path):
    """object id -> localizable text, from a 1.0.x NSKeyedArchiver-format xib"""
    text = io.open(path, encoding="utf-8", errors="replace").read()
    ids = [(m.start(), m.group(1)) for m in re.finditer(r'id="(\d+)"', text)]
    found = {}
    pattern = r'<string key="(%s)">(.*?)</string>' % "|".join(STRING_KEYS)
    for m in re.finditer(pattern, text, re.S):
        earlier = [i for i in ids if i[0] < m.start()]
        if earlier:
            found[earlier[-1][1]] = unescape(m.group(2))
    return found


def fold(text):
    """match "Open URL" against the menu item's "Open URL..." and the like"""
    text = text.strip().rstrip(".…:").replace("...", "").strip()
    return re.sub(r"\s+", " ", text).lower()


def main():
    version = sys.argv[1] if len(sys.argv) > 1 else "2.1.0"
    root = os.path.join("localization", version)
    if not os.path.isdir(root) or not os.path.exists(NIB):
        sys.exit("run this from the repository root (looked for %s and %s)" % (root, NIB))

    # English text -> {language: translation}
    table = {}
    for xib in LEGACY_XIBS:
        base = os.path.join(root, "English.lproj", xib)
        if not os.path.exists(base):
            continue
        english = legacy_strings(base)
        for lang in sorted(os.listdir(root)):
            if not lang.endswith(".lproj") or lang == "English.lproj":
                continue
            path = os.path.join(root, lang, xib)
            if not os.path.exists(path):
                continue
            translated = legacy_strings(path)
            for oid, text in english.items():
                other = translated.get(oid)
                if other and other != text and text.strip():
                    table.setdefault(text, {}).setdefault(lang, other)
    folded = {}
    for text, langs in table.items():
        folded.setdefault(fold(text), langs)

    # every object in the current nib that carries a user-visible title
    nib = io.open(NIB, encoding="utf-8").read()
    titled = []
    for m in re.finditer(r'<(menuItem|menu|window|button|textField)\s([^>]*)>', nib):
        attrs = m.group(2)
        if 'isSeparatorItem="YES"' in attrs:
            continue
        oid = re.search(r'id="([^"]+)"', attrs)
        title = re.search(r'title="([^"]*)"', attrs)
        if oid and title and title.group(1).strip():
            titled.append((oid.group(1), unescape(title.group(1))))
    print("titled objects in %s: %d" % (NIB, len(titled)))

    def escape(text):
        return (text.replace("\\", "\\\\").replace('"', '\\"').replace("\n", "\\n"))

    for lang in sorted(d for d in os.listdir(root)
                       if d.endswith(".lproj") and d != "English.lproj"):
        overrides = OVERRIDES.get(lang, {})
        lines, hits = [], 0
        for oid, title in titled:
            translation = overrides.get(title)
            if translation is None:
                translation = (table.get(title, {}).get(lang)
                               or folded.get(fold(title), {}).get(lang))
            if not translation or translation == title:
                continue
            lines.append('/* %s */\n"%s.title" = "%s";\n'
                         % (escape(title), oid, escape(translation)))
            hits += 1
        out = os.path.join(root, lang, "MainMenu.strings")
        io.open(out, "wb").write(("\n".join(lines) + "\n").encode("utf-16"))
        print("  %-16s %3d/%d titles" % (lang, hits, len(titled)))


if __name__ == "__main__":
    main()

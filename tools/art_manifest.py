#!/usr/bin/env python3
"""Generate the art checklist from Main.gd.

Every slot the game can ask for is derived from the data tables rather than
listed by hand, so the checklist cannot drift from the content: add an enemy
to enemy_defs and its rows appear here on the next run. Ticks come from the
filesystem, so the same file is also the progress report.

    python3 tools/art_manifest.py
"""
import os
import re
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SOURCE = os.path.join(ROOT, "godot_project", "scripts", "Main.gd")
ART = os.path.join(ROOT, "godot_project", "art")
OUT = os.path.join(ART, "MANIFEST.md")

# How each category is authored. Sizes are the frame the art is fitted into
# at the 1024x576 design size, doubled for authoring headroom.
KINDS = {
    "stage": ("立ち絵", "縦長 / 透過PNG", "600 x 900 以上（2:3 〜 3:5）"),
    "cg":    ("全画面CG", "16:9 / 不透過", "1920 x 1080"),
    "bg":    ("背景", "16:9 / 不透過", "1920 x 1080"),
    "face":  ("マップ顔", "正方形 / 透過PNG", "256 x 256"),
}

# Priority tiers. P0 is the line below which the game shows a magenta
# placeholder to the player; everything else degrades to something real.
P0 = "P0"  # 無いと画面が壊れて見える
P1 = "P1"  # 商品として要る
P2 = "P2"  # あると良い


def read_source():
    with open(SOURCE, encoding="utf-8") as handle:
        return handle.read()


def enemies(text):
    """[(art id, 表示名)] in table order."""
    block = re.search(r"var enemy_defs := \[(.*?)\n\]", text, re.S)
    rows = re.findall(r'\{"name": "([^"]+)", "art": "([^"]+)"', block.group(1))
    return [(art, name) for name, art in rows]


def heroes(text):
    """Only live rows — the shelved heroes are commented out."""
    block = re.search(r"var hero_defs := \{(.*?)\n\}", text, re.S)
    out = []
    for chunk in re.finditer(
        r'"name": "([^"]+)",\s*\n\s*"art": "([^"]+)"', block.group(1)
    ):
        out.append((chunk.group(2), chunk.group(1)))
    return out


def events(text):
    block = re.search(r"var event_defs := \{(.*?)\n\}\n", text, re.S)
    return re.findall(r'\n\t"([a-z_]+)": \{"name": "([^"]+)"', block.group(1))


def node_kinds(text):
    block = re.search(r"const NODE_DEFS := \{(.*?)\n\}", text, re.S)
    return re.findall(r'"([a-z]+)": \{"label": "([^"]+)"', block.group(1))


def hit_frames(kind, actor, state):
    """A hit clip is a numbered run; list the first four as the ask."""
    return [f"{actor}_{state}_{i}" for i in range(4)]


def exists(kind, stem):
    """True if the slot has a file — still or first frame of a run."""
    directory = os.path.join(ART, kind)
    for candidate in (f"{stem}.png", f"{stem}_0.png"):
        if os.path.exists(os.path.join(directory, candidate)):
            return True
    return False


def rows_for(text):
    """Every slot, as (kind, stem, priority, what it is)."""
    out = []

    # --- backgrounds ---------------------------------------------------
    # Backgrounds never show a placeholder — they fall through to the drawn
    # table top — so none of them are P0 no matter how much they are wanted.
    out.append(("bg", "scene_default", P1,
                "全画面の下地。**これ1枚で全画面をカバーする**ので最初に描く"))
    out.append(("bg", "scene_title", P1,
                "タイトルのキービジュアル。ストアと配信で最初に映る画面"))
    out.append(("bg", "scene_map", P1, "ノードマップの背景"))
    out.append(("bg", "scene_battle", P1, "通常戦闘の背景"))
    for key, label in node_kinds(text):
        if key in ("battle", "boss", "elite"):
            continue
        out.append(("bg", f"scene_{key}", P2, f"{label}ノードの背景"))
    out.append(("bg", "scene_elite", P2, "強敵戦の背景（無ければ戦闘背景）"))
    out.append(("bg", "scene_boss", P2, "ボス戦の背景（無ければ戦闘背景）"))
    out.append(("bg", "scene_gallery", P2, "回想画面の背景（無ければマップ背景）"))

    # --- the player ----------------------------------------------------
    for art, name in heroes(text):
        out.append(("stage", f"{art}_idle", P0, f"自機「{name}」の立ち絵・通常"))
        for frame in hit_frames("stage", art, "hit"):
            out.append(("stage", frame, P1, f"自機「{name}」被弾アニメ"))
        out.append(("stage", f"{art}_down", P2, f"自機「{name}」瀕死（HP35%以下）"))

    # --- the enemies ---------------------------------------------------
    roster = enemies(text)
    for art, name in roster:
        out.append(("stage", f"{art}_idle", P0, f"「{name}」の立ち絵・通常"))
    for art, name in roster:
        out.append(("cg", f"{art}_win", P0, f"「{name}」に勝利したときのCG"))
        out.append(("cg", f"{art}_lose", P0, f"「{name}」に敗北したときのCG"))
    for art, name in roster:
        out.append(("face", f"{art}_node", P1, f"「{name}」のマップ顔"))
    for art, name in roster:
        for frame in hit_frames("stage", art, "hit"):
            out.append(("stage", frame, P2, f"「{name}」被弾アニメ"))
        out.append(("stage", f"{art}_down", P2, f"「{name}」瀕死"))

    # --- everything else -----------------------------------------------
    for key, label in node_kinds(text):
        if key in ("battle", "elite", "boss"):
            continue
        out.append(("face", f"{key}_node", P2, f"{label}ノードのマップ顔"))
    for key, name in events(text):
        out.append(("cg", f"{key}_scene", P2, f"イベント「{name}」の挿絵"))

    return out


def main():
    text = read_source()
    rows = rows_for(text)

    tiers = {P0: [], P1: [], P2: []}
    for row in rows:
        tiers[row[2]].append(row)

    done = sum(1 for kind, stem, _, _ in rows if exists(kind, stem))
    lines = []
    lines.append("# スプライト必要箇所 一覧")
    lines.append("")
    lines.append("`tools/art_manifest.py` が `Main.gd` のデータ表から生成します。")
    lines.append("敵やイベントを増やしたら再実行してください。手で編集しても次の")
    lines.append("実行で消えます。チェック欄は実ファイルの有無を見ています。")
    lines.append("")
    lines.append("```")
    lines.append("python3 tools/art_manifest.py")
    lines.append("```")
    lines.append("")
    lines.append(f"**進捗: {done} / {len(rows)}**")
    lines.append("")
    lines.append("## 優先度の意味")
    lines.append("")
    lines.append("| | 意味 |")
    lines.append("| --- | --- |")
    lines.append("| **P0** | 無いとプレイヤーにマゼンタのプレースホルダが見える。ここが商品の下限 |")
    lines.append("| **P1** | 無くても既存の描画で成立するが、商品としては要る |")
    lines.append("| **P2** | あると良い。無ければ静かに他のスロットへ落ちる |")
    lines.append("")
    lines.append("## 規格")
    lines.append("")
    lines.append("| 種別 | フォルダ | 形式 | 推奨サイズ |")
    lines.append("| --- | --- | --- | --- |")
    for kind, (label, form, size) in KINDS.items():
        lines.append(f"| {label} | `art/{kind}/` | {form} | {size} |")
    lines.append("")
    lines.append("連番（`_0`, `_1`, …）はアニメーションになります。番号は0から連続")
    lines.append("している必要があり、抜けたところでクリップが終わります。")
    lines.append("")

    titles = {
        P0: "P0 — これが無いと画面が壊れて見える",
        P1: "P1 — 商品として要る",
        P2: "P2 — あると良い",
    }
    for tier in (P0, P1, P2):
        group = tiers[tier]
        got = sum(1 for kind, stem, _, _ in group if exists(kind, stem))
        lines.append(f"## {titles[tier]}　（{got} / {len(group)}）")
        lines.append("")
        lines.append("| | パス | 内容 |")
        lines.append("| --- | --- | --- |")
        for kind, stem, _, what in group:
            tick = "x" if exists(kind, stem) else " "
            lines.append(f"| [{tick}] | `art/{kind}/{stem}.png` | {what} |")
        lines.append("")

    with open(OUT, "w", encoding="utf-8") as handle:
        handle.write("\n".join(lines) + "\n")

    print(f"{len(rows)} slots -> {os.path.relpath(OUT, ROOT)}")
    for tier in (P0, P1, P2):
        group = tiers[tier]
        got = sum(1 for kind, stem, _, _ in group if exists(kind, stem))
        print(f"  {tier}: {got} / {len(group)}")
    return 0


if __name__ == "__main__":
    sys.exit(main())

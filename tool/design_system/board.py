#!/usr/bin/env python3
"""Draws the before and after board of a visible change, from the catalog.

The board is one PNG: for every catalog scene that changed between a base
revision and the working tree, a row with the scene as the base draws it and
as the tree draws it, side by side, its caption under them. New and removed
scenes have their row too, with the empty side saying which.

    python3 tool/design_system/board.py --base dev --auto
    python3 tool/design_system/board.py --base dev --card TagChip \\
        --scene 'selected' --theme dark --platform phone

The cards come from --card, or with --auto from the diff: a card whose
README paragraph naming its catalog test (`Rendered from ... by
test/design_catalog/<x>_catalog_test.dart`) names a changed file, or whose
catalog test changed. The base revision
is checked out once per commit in a detached worktree under
.ai/scratch/board-base/<sha> and its sheets are kept there, so a second board
against the same base renders only the tree. A sheet is the same from one
render to the next only while the clock reads the same (the app words a time
against it, to the minute in places): so when a scene looks changed, the
base's sheets of its card are drawn again, and a scene that differs between
two renders of the base is shown as unstable, not as changed. The two renders run one after
the other, never at once.

Scenes are paired by the id each sheet's manifest gives them
(`<platform>.<theme>.scenes.json`, written by test/design_catalog/catalog.dart),
then by caption likeness, and compared pixel for pixel: the render is
deterministic on one machine. A base whose catalog predates the manifest is
drawn with the tree's catalog harness; if that fails, its whole sheet stands
in for each scene, and the board says so.

Exit status: 0 with a board, 1 on an error, 3 when nothing changed.
"""

from __future__ import annotations

import argparse
import difflib
import json
import re
import shutil
import subprocess
import sys
from dataclasses import dataclass
from pathlib import Path

from PIL import Image, ImageDraw, ImageFont

Image.MAX_IMAGE_PIXELS = None  # a sheet runs to 70,000 px and is ours

ROOT = Path(__file__).resolve().parents[2]
COMPONENTS = ROOT / "design" / "system" / "components"
CATALOG_DIR = "test/design_catalog"
HARNESS = f"{CATALOG_DIR}/catalog.dart"
SHEETS = "build/design_catalog"
BASES = ROOT / ".ai" / "scratch" / "board-base"
KEEP_BASES = 2
FONT = ROOT / "assets" / "fonts" / "Onest.ttf"



def _dark(name: str) -> tuple[int, ...]:
    """A dark-room colour token from design/system/tokens.json, as RGB over
    the ground for a translucent one."""
    tokens = json.loads((ROOT / "design" / "system" / "tokens.json").read_text())
    value = next(t["value"] for t in tokens["color"]["tokens"] if t["name"] == name)
    value = value["dark"] if isinstance(value, dict) else value
    rgba = re.fullmatch(r"rgba\((\d+),\s*(\d+),\s*(\d+),\s*([\d.]+)\)", value)
    if rgba:
        *rgb, alpha = (float(c) for c in rgba.groups())
        ground = _dark("room-ground")
        return tuple(round(g + (c - g) * alpha) for c, g in zip(rgb, ground))
    return tuple(int(value[i:i + 2], 16) for i in (1, 3, 5))


# The dark room the board is read in.
GROUND = _dark("room-ground")
RAISED = _dark("room-raised")
INK = _dark("ink-primary")
DIM = _dark("ink-tertiary")
PAD = 16  # shadows bleed past a scene's box
GAP = 32
MARGIN = 48


class BoardError(Exception):
    pass


def git(*args: str, cwd: Path = ROOT) -> str:
    done = subprocess.run(
        ["git", *args], cwd=cwd, capture_output=True, text=True
    )
    if done.returncode != 0:
        raise BoardError(f"git {' '.join(args)}: {done.stderr.strip()}")
    return done.stdout.strip()


# --- Which cards -------------------------------------------------------------

@dataclass(frozen=True)
class Card:
    name: str
    test: str  # repo-relative catalog test
    sources: frozenset[str]  # repo-relative files the README names


def _catalog_paragraph(readme: str) -> str | None:
    """The README paragraph that names its catalog test, its lines joined:
    `Rendered from ... by test/design_catalog/<x>_catalog_test.dart`, or the
    older `The catalog test is ...`."""
    for paragraph in re.split(r"\n\s*\n", readme):
        if re.search(r"`test/design_catalog/\w+_catalog_test\.dart`", paragraph):
            return " ".join(paragraph.split())
    return None


def cards() -> dict[str, Card]:
    """Every card whose README names its catalog test, with the files the
    same paragraph names in backticks (a bare file name taken in the folder
    of the path before it)."""
    found: dict[str, Card] = {}
    for readme in sorted(COMPONENTS.glob("*/README.md")):
        paragraph = _catalog_paragraph(readme.read_text())
        if paragraph is None:
            continue
        test = re.search(r"`(test/design_catalog/\w+_catalog_test\.dart)`", paragraph)
        sources: set[str] = set()
        folder = ""
        for name in re.findall(r"`([\w./]+\.dart)`", paragraph):
            if name == test.group(1):
                continue
            if "/" in name:
                folder = name.rsplit("/", 1)[0]
                sources.add(name)
            elif folder:
                sources.add(f"{folder}/{name}")
        found[readme.parent.name] = Card(
            readme.parent.name, test.group(1), frozenset(sources)
        )
    return found


def changed_files(base: str) -> list[str]:
    """Files the working tree changes against where it left [base]."""
    fork = git("merge-base", base, "HEAD")
    tracked = git("diff", "--name-only", fork).splitlines()
    untracked = git("ls-files", "--others", "--exclude-standard").splitlines()
    return sorted({*tracked, *untracked} - {""})


def auto_cards(base: str, known: dict[str, Card]) -> list[Card]:
    changed = set(changed_files(base))
    return [
        card
        for card in known.values()
        if card.test in changed or card.sources & changed
    ]


# --- Rendering ---------------------------------------------------------------

def _flutter_test(cwd: Path, tests: list[str], label: str) -> None:
    print(f"board · rendering {label}: {', '.join(Path(t).stem for t in tests)}",
          file=sys.stderr)
    done = subprocess.run(
        ["flutter", "test", "--tags", "catalog", "--run-skipped", *tests],
        cwd=cwd, capture_output=True, text=True,
    )
    if done.returncode != 0:
        tail = "\n".join(done.stdout.replace("\r", "\n").splitlines()[-30:])
        raise BoardError(f"the catalog failed on {label}:\n{tail}")


def base_tree(sha: str) -> Path:
    """The detached worktree of [sha], made once and kept; the oldest beyond
    KEEP_BASES are removed."""
    tree = BASES / sha
    if not (tree / ".git").exists():
        BASES.mkdir(parents=True, exist_ok=True)
        print(f"board · checking out the base {sha[:10]}", file=sys.stderr)
        git("worktree", "add", "--detach", str(tree), sha)
        done = subprocess.run(
            ["flutter", "pub", "get"], cwd=tree, capture_output=True, text=True
        )
        if done.returncode != 0:
            raise BoardError(f"flutter pub get on the base: {done.stderr.strip()}")
    tree.touch()
    others = sorted(
        (p for p in BASES.iterdir() if p.is_dir() and p != tree),
        key=lambda p: p.stat().st_mtime, reverse=True,
    )
    for old in others[KEEP_BASES - 1:]:
        print(f"board · removing the old base {old.name[:10]}", file=sys.stderr)
        git("worktree", "remove", "--force", str(old))
    return tree


def _has_manifest(tree: Path) -> bool:
    return "scenes.json" in (tree / HARNESS).read_text()


def render_base(tree: Path, chosen: list[Card], again: bool = False) -> list[str]:
    """Renders the base's sheets of [chosen] not yet rendered for it, or all
    of them [again]; returns what the board should say about how."""
    notes: list[str] = []
    stamp = tree / SHEETS / ".board-rendered.json"
    done = set(json.loads(stamp.read_text())) if stamp.exists() else set()
    todo = [c for c in chosen if again or c.name not in done]
    if not todo:
        print("board · the base's sheets are already drawn", file=sys.stderr)
        return notes
    harness = tree / HARNESS
    original = harness.read_text()
    lent = not _has_manifest(tree)
    if lent:
        notes.append(
            "base drawn with the tree's catalog harness (it predates the scene "
            "manifest)"
        )
        shutil.copyfile(ROOT / HARNESS, harness)
    try:
        _flutter_test(tree, [c.test for c in todo if (tree / c.test).exists()], "the base")
    except BoardError:
        if not lent:
            raise
        harness.write_text(original)
        lent = False
        notes[-1] = "base drawn without a scene manifest: whole sheets stand in for its scenes"
        _flutter_test(tree, [c.test for c in todo if (tree / c.test).exists()], "the base")
    finally:
        if lent:
            harness.write_text(original)
    stamp.parent.mkdir(parents=True, exist_ok=True)
    stamp.write_text(json.dumps(sorted(done | {c.name for c in todo})))
    return notes


# --- Scenes ------------------------------------------------------------------

@dataclass
class Scene:
    id: str
    caption: str
    image: Image.Image  # what the board shows: the scene and the glow around it
    exact: Image.Image  # what is compared: the scene's box alone


def scenes_of(sheets: Path, card: str, platform: str, theme: str) -> list[Scene] | None:
    """The scenes of one sheet, cropped by its manifest; the whole sheet as
    one scene when it has none; None when the sheet is not there."""
    png = sheets / card / f"{platform}.{theme}.png"
    if not png.exists():
        return None
    sheet = Image.open(png).convert("RGB")
    manifest = sheets / card / f"{platform}.{theme}.scenes.json"
    if not manifest.exists():
        return [Scene("sheet", "the whole sheet (no scene manifest)", sheet, sheet)]
    out = []
    for entry in json.loads(manifest.read_text()):
        x, y, w, h = entry["rect"]
        box = (max(0, x - PAD), max(0, y - PAD),
               min(sheet.width, x + w + PAD), min(sheet.height, y + h + PAD))
        out.append(Scene(entry["id"], entry["caption"], sheet.crop(box),
                         sheet.crop((x, y, x + w, y + h))))
    return out


def pair(before: list[Scene], after: list[Scene]):
    """(before, after) pairs: by id, then by caption likeness at 0.8, then
    the rest alone (new or removed)."""
    pairs: list[tuple[Scene | None, Scene | None]] = []
    left = {s.id: s for s in before}
    rest_after = []
    for scene in after:
        if scene.id in left:
            pairs.append((left.pop(scene.id), scene))
        else:
            rest_after.append(scene)
    for scene in rest_after:
        best, score = None, 0.0
        for old in left.values():
            ratio = difflib.SequenceMatcher(None, old.caption, scene.caption).ratio()
            if ratio > score:
                best, score = old, ratio
        if best is not None and score >= 0.8:
            pairs.append((left.pop(best.id), scene))
        else:
            pairs.append((None, scene))
    pairs.extend((old, None) for old in left.values())
    return pairs


def same(a: Image.Image, b: Image.Image) -> bool:
    return a.size == b.size and a.tobytes() == b.tobytes()


# --- Composition ---------------------------------------------------------------

def _font(size: int) -> ImageFont.FreeTypeFont:
    return ImageFont.truetype(str(FONT), size)


def _wrap(draw: ImageDraw.ImageDraw, text: str, font, width: int) -> list[str]:
    lines, line = [], ""
    for word in text.split():
        trial = f"{line} {word}".strip()
        if draw.textlength(trial, font=font) <= width or not line:
            line = trial
        else:
            lines.append(line)
            line = word
    return lines + ([line] if line else [])


def compose(sections, column: int, out: Path) -> None:
    """[sections]: (title, [(caption, before image or label, after image or
    label)]). Each row is two columns of [column] px at most, both crops
    scaled by the same factor."""
    title_font, caption_font, label_font = _font(40), _font(26), _font(30)
    probe = ImageDraw.Draw(Image.new("RGB", (1, 1)))
    blocks = []
    for title, rows in sections:
        laid = []
        for caption, before, after in rows:
            images = [i for i in (before, after) if isinstance(i, Image.Image)]
            scale = min(1.0, column / max(i.width for i in images))
            scaled = [
                i.resize((round(i.width * scale), round(i.height * scale)), Image.LANCZOS)
                if isinstance(i, Image.Image) and scale < 1 else i
                for i in (before, after)
            ]
            height = max(i.height for i in scaled if isinstance(i, Image.Image))
            lines = _wrap(probe, caption, caption_font, column * 2 + GAP)
            laid.append((scaled, height, lines))
        blocks.append((title, laid))

    width = MARGIN * 2 + column * 2 + GAP
    height = MARGIN
    for _, laid in blocks:
        height += 60 + 44
        for _, h, lines in laid:
            height += h + 14 + 34 * len(lines) + GAP
        height += GAP
    board = Image.new("RGB", (width, height), GROUND)
    draw = ImageDraw.Draw(board)
    y = MARGIN
    for title, laid in blocks:
        draw.text((MARGIN, y), title, font=title_font, fill=INK)
        y += 60
        for i, label in enumerate(("before", "after")):
            draw.text((MARGIN + i * (column + GAP), y), label, font=caption_font, fill=DIM)
        y += 44
        for scaled, h, lines in laid:
            for i, part in enumerate(scaled):
                x = MARGIN + i * (column + GAP)
                if isinstance(part, Image.Image):
                    board.paste(part, (x, y))
                else:
                    draw.rounded_rectangle((x, y, x + column, y + h), 24, fill=RAISED)
                    draw.text((x + 32, y + 32), part, font=label_font, fill=DIM)
            y += h + 14
            for line in lines:
                draw.text((MARGIN, y), line, font=caption_font, fill=INK)
                y += 34
            y += GAP
        y += GAP
    out.parent.mkdir(parents=True, exist_ok=True)
    board.save(out, optimize=True)


# --- Main ----------------------------------------------------------------------

def main(argv: list[str]) -> int:
    parser = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    parser.add_argument("--base", required=True, help="the revision before the change")
    parser.add_argument("--card", action="append", default=[], help="a card by name (repeatable)")
    parser.add_argument("--auto", action="store_true", help="the cards the diff touches")
    parser.add_argument("--scene", action="append", default=[],
                        help="keep scenes whose id or caption contains this (repeatable)")
    parser.add_argument("--theme", choices=("dark", "light", "both"), default="both")
    parser.add_argument("--platform", choices=("phone", "desktop"), action="append")
    parser.add_argument("--all-scenes", action="store_true", help="unchanged scenes too")
    parser.add_argument("--column", type=int, default=900, help="widest a side is drawn, in px")
    parser.add_argument("--out", type=Path,
                        default=ROOT / ".ai" / "scratch" / "boards" / "board.png")
    args = parser.parse_args(argv)

    known = cards()
    chosen: list[Card] = []
    for name in args.card:
        if name not in known:
            raise BoardError(f"no card {name} naming its catalog test under {COMPONENTS}")
        chosen.append(known[name])
    if args.auto:
        chosen += [c for c in auto_cards(args.base, known) if c not in chosen]
    if not chosen:
        raise BoardError("no cards: pass --card, or --auto with a change a card README names")

    sha = git("rev-parse", "--verify", f"{args.base}^{{commit}}")
    tree = base_tree(sha)
    notes = render_base(tree, chosen)
    _flutter_test(ROOT, [c.test for c in chosen], "the tree")

    themes = ("dark", "light") if args.theme == "both" else (args.theme,)
    platforms = args.platform or ["phone", "desktop"]
    sheets = [(c, p, t) for c in chosen for p in platforms for t in themes]

    def pairs_of(card, platform, theme):
        before = scenes_of(tree / SHEETS, card.name, platform, theme)
        after = scenes_of(ROOT / SHEETS, card.name, platform, theme)
        if before is None and after is None:
            return []
        return pair(before or [], after or [])

    def changed(old, new):
        return not (old and new and same(old.exact, new.exact))

    paired = {sheet: pairs_of(*sheet) for sheet in sheets}
    # A changed scene may be the clock's doing: draw its card's base again,
    # and hold as unstable what the two base renders disagree on.
    suspects = sorted(
        {card.name for (card, _, _), pairs in paired.items()
         if any(old and new and changed(old, new) for old, new in pairs)}
    )
    unstable: set[tuple[str, str, str, str]] = set()
    if suspects:
        first = {sheet: {old.id: old for old, _ in pairs if old}
                 for sheet, pairs in paired.items() if sheet[0].name in suspects}
        print(f"board · drawing the base again for {', '.join(suspects)}: "
              "a changed scene may be the clock's", file=sys.stderr)
        render_base(tree, [c for c in chosen if c.name in suspects], again=True)
        for sheet in first:
            paired[sheet] = pairs_of(*sheet)
            for old, _ in paired[sheet]:
                earlier = first[sheet].get(old.id) if old else None
                if earlier and not same(earlier.exact, old.exact):
                    unstable.add((sheet[0].name, sheet[1], sheet[2], old.id))

    sections, included = [], []
    for (card, platform, theme), pairs in paired.items():
        rows = []
        for old, new in pairs:
            scene = new or old
            if args.scene and not any(
                s.lower() in scene.id or s.lower() in scene.caption.lower()
                for s in args.scene
            ):
                continue
            shaky = (card.name, platform, theme, scene.id) in unstable
            if not changed(old, new) and not args.all_scenes:
                continue
            state = ("new" if not old else "removed" if not new
                     else "unstable" if shaky else "changed")
            caption = scene.caption
            if shaky:
                caption += " (unstable: two renders of the base differ, so compare by eye)"
            rows.append((
                caption,
                old.image if old else "new",
                new.image if new else "removed",
            ))
            included.append(f"{card.name} · {platform}.{theme} · {state} · {scene.id}")
        if rows:
            sections.append((f"{card.name} · {platform} · {theme}", rows))

    for note in notes:
        print(f"board · {note}")
    if not sections:
        print(f"board · nothing changed in {', '.join(c.name for c in chosen)} against {args.base}")
        return 3
    compose(sections, args.column, args.out)
    print(args.out)
    for line in included:
        print(f"  {line}")
    return 0


if __name__ == "__main__":
    try:
        sys.exit(main(sys.argv[1:]))
    except BoardError as error:
        print(f"board · {error}", file=sys.stderr)
        sys.exit(1)

"""Two small static SVG charts for docs/evaluation.md, standard library only.

GitHub shows SVGs in markdown as images, so there is no hover layer: the
markdown tables next to each chart are the table view. Colors are the first
four categorical slots of the dataviz reference palette (validated for light
mode); the charts draw their own light surface so they read the same in
GitHub's light and dark themes. Identity never rests on color alone: rows are
labelled, and lines carry direct labels plus a legend.
"""
from __future__ import annotations

import math
from dataclasses import dataclass
from pathlib import Path
from xml.sax.saxutils import escape

SURFACE = "#fcfcfb"
TEXT = "#0b0b0b"
TEXT_2 = "#52514e"
GRID = "#e4e3df"
SERIES = ["#2a78d6", "#eb6834", "#1baf7a", "#eda100"]  # blue, orange, aqua, yellow (fixed order)
FONT = "font-family=\"system-ui, -apple-system, 'Segoe UI', sans-serif\""
W = 760


@dataclass
class StripRow:
    label: str
    values: list[float]
    kind: str  # "owner" or "imitator"


@dataclass
class Mark:
    x: float
    label: str
    dashed: bool = False


@dataclass
class Series:
    label: str
    ys: list[float]  # NaN breaks the line


def _text(x, y, s, size=12, color=TEXT, anchor="start", weight="normal") -> str:
    return (f'<text x="{x:.1f}" y="{y:.1f}" {FONT} font-size="{size}" fill="{color}" '
            f'text-anchor="{anchor}" font-weight="{weight}">{escape(s)}</text>')


def _open(h: int, title: str) -> list[str]:
    return [f'<svg xmlns="http://www.w3.org/2000/svg" width="{W}" height="{h}" viewBox="0 0 {W} {h}" role="img" '
            f'aria-label="{escape(title)}">',
            f'<rect width="{W}" height="{h}" rx="8" fill="{SURFACE}"/>',
            _text(20, 28, title, 15, TEXT, weight="600")]


def _nice_ticks(hi: float) -> list[float]:
    step = 0.25 if hi <= 2 else 0.5 if hi <= 4 else 1.0
    return [round(i * step, 2) for i in range(int(hi / step + 1e-9) + 1)]


def strip_plot(path: Path, title: str, rows: list[StripRow], marks: list[Mark]) -> None:
    left, right, top, bottom, row_h = 150, 70, 64 + 14 * len(marks), 46, 54
    h = top + row_h * len(rows) + bottom
    finite = sorted(v for r in rows for v in r.values if math.isfinite(v))
    hi = finite[int(0.95 * (len(finite) - 1))] * 1.1 if finite else 2.5
    hi = min(8.0, max(2.5, hi, *(m.x * 1.2 for m in marks)))
    ticks = _nice_ticks(hi)
    hi = ticks[-1]
    x0, x1 = left, W - right

    def sx(v: float) -> float:
        return x0 + (x1 - x0) * v / hi

    out = _open(h, title)
    colors = {"owner": SERIES[0], "imitator": SERIES[1]}
    lx = W - right - 190
    for i, (kind, name) in enumerate((("owner", "Owner"), ("imitator", "Imitator"))):
        cx = lx + i * 100
        out.append(f'<circle cx="{cx}" cy="48" r="5" fill="{colors[kind]}" stroke="{SURFACE}" stroke-width="2"/>')
        out.append(_text(cx + 10, 52, name, 12, TEXT_2))
    for t in ticks:
        out.append(f'<line x1="{sx(t):.1f}" y1="{top - 6}" x2="{sx(t):.1f}" y2="{h - bottom}" stroke="{GRID}" stroke-width="1"/>')
        out.append(_text(sx(t), h - bottom + 18, f"{t:g}", 11, TEXT_2, "middle"))
    out.append(_text((x0 + x1) / 2, h - 8, "score ÷ worst template pair (accepted when left of the threshold)", 11,
                     TEXT_2, "middle"))
    for ri, row in enumerate(rows):
        cy = top + row_h * ri + row_h / 2
        out.append(_text(20, cy - 2, row.label, 13, TEXT))
        over = sum(1 for v in row.values if not math.isfinite(v) or v > hi)
        out.append(_text(20, cy + 14, f"n = {len(row.values)}", 11, TEXT_2))
        for k, v in enumerate(row.values):
            if not math.isfinite(v) or v > hi:
                continue
            jitter = ((k * 0.6180339887) % 1 - 0.5) * (row_h - 22)
            out.append(f'<circle cx="{sx(v):.1f}" cy="{cy + jitter:.1f}" r="4" fill="{colors[row.kind]}" '
                       f'fill-opacity="0.8" stroke="{SURFACE}" stroke-width="1.5"/>')
        if over:
            out.append(_text(x1 + 6, cy + 4, f"+{over} past {hi:g}", 11, TEXT_2))
    for i, m in enumerate(marks):  # one label row per mark so close thresholds never collide
        dash = ' stroke-dasharray="5 4"' if m.dashed else ""
        color = TEXT_2 if m.dashed else TEXT
        ly = top - 12 - 14 * (len(marks) - 1 - i)
        out.append(f'<line x1="{sx(m.x):.1f}" y1="{ly + 4}" x2="{sx(m.x):.1f}" y2="{h - bottom}" stroke="{color}" '
                   f'stroke-width="1.5"{dash}/>')
        out.append(_text(sx(m.x) + 4, ly, m.label, 11, color))
    out.append("</svg>")
    Path(path).write_text("\n".join(out), encoding="utf-8")


def line_chart(path: Path, title: str, xs: list[float], series: list[Series],
               hline: tuple[float, str] | None = None, vline: tuple[float, str] | None = None) -> None:
    left, right, top, bottom = 60, 170, 70, 50
    h = 440
    x0, x1, y0, y1 = left, W - right, h - bottom, top
    lo, hi = min(xs), max(xs)

    def sx(v: float) -> float:
        return x0 + (x1 - x0) * (v - lo) / (hi - lo or 1)

    def sy(v: float) -> float:
        return y0 - (y0 - y1) * v

    out = _open(h, title)
    for i, s in enumerate(series):  # legend row
        lx = 20 + i * 175
        out.append(f'<line x1="{lx}" y1="48" x2="{lx + 18}" y2="48" stroke="{SERIES[i]}" stroke-width="2.5" '
                   f'stroke-linecap="round"/>')
        out.append(_text(lx + 24, 52, s.label, 12, TEXT_2))
    for p in (0, 0.25, 0.5, 0.75, 1.0):
        out.append(f'<line x1="{x0}" y1="{sy(p):.1f}" x2="{x1}" y2="{sy(p):.1f}" stroke="{GRID}" stroke-width="1"/>')
        out.append(_text(x0 - 8, sy(p) + 4, f"{p:.0%}", 11, TEXT_2, "end"))
    for t in xs[::2]:
        out.append(_text(sx(t), y0 + 18, f"{t:g}", 11, TEXT_2, "middle"))
    out.append(_text((x0 + x1) / 2, h - 10, "thresholdFactor (threshold = factor × worst template pair)", 11, TEXT_2, "middle"))
    if hline:
        out.append(f'<line x1="{x0}" y1="{sy(hline[0]):.1f}" x2="{x1}" y2="{sy(hline[0]):.1f}" stroke="{TEXT_2}" '
                   f'stroke-width="1" stroke-dasharray="5 4"/>')
        out.append(_text(x1 - 6, sy(hline[0]) + 14, hline[1], 11, TEXT_2, "end"))
    if vline:
        out.append(f'<line x1="{sx(vline[0]):.1f}" y1="{y1 - 6}" x2="{sx(vline[0]):.1f}" y2="{y0}" stroke="{TEXT}" '
                   f'stroke-width="1.5"/>')
        out.append(_text(sx(vline[0]) + 4, y1 - 8, vline[1], 11, TEXT))
    ends = []
    for i, s in enumerate(series):
        segs, cur = [], []
        for x, y in zip(xs, s.ys):
            if y is None or (isinstance(y, float) and math.isnan(y)):
                if cur:
                    segs.append(cur)
                cur = []
            else:
                cur.append(f"{sx(x):.1f},{sy(y):.1f}")
        if cur:
            segs.append(cur)
        for seg in segs:
            out.append(f'<polyline points="{" ".join(seg)}" fill="none" stroke="{SERIES[i]}" stroke-width="2" '
                       f'stroke-linejoin="round" stroke-linecap="round"/>')
        last = next((y for y in reversed(s.ys) if not (isinstance(y, float) and math.isnan(y))), None)
        if last is not None:
            ends.append([sy(last), i, s.label, last])
    ends.sort()
    for k in range(1, len(ends)):  # keep direct labels 14px apart
        ends[k][0] = max(ends[k][0], ends[k - 1][0] + 14)
    for ly, i, label, val in ends:
        out.append(f'<line x1="{x1 + 6}" y1="{ly:.1f}" x2="{x1 + 18}" y2="{ly:.1f}" stroke="{SERIES[i]}" '
                   f'stroke-width="2.5" stroke-linecap="round"/>')
        out.append(_text(x1 + 22, ly + 4, f"{label} {val:.0%}", 11, TEXT))
    out.append("</svg>")
    Path(path).write_text("\n".join(out), encoding="utf-8")

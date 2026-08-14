#!/usr/bin/env python3
"""Create clean Decision Console background and atomic reference crops."""

from __future__ import annotations

import argparse
import json
from pathlib import Path

from PIL import Image, ImageDraw, ImageFilter


def read_box(value: list[int]) -> tuple[int, int, int, int]:
    if len(value) != 4:
        raise ValueError(f"expected [x1, y1, x2, y2], got {value!r}")
    box = tuple(int(item) for item in value)
    if box[2] <= box[0] or box[3] <= box[1]:
        raise ValueError(f"box must have positive area, got {value!r}")
    return box


def soften_edge(image: Image.Image, bounds: tuple[int, int, int, int]) -> None:
    edge = Image.new("RGBA", image.size, (0, 0, 0, 0))
    draw = ImageDraw.Draw(edge, "RGBA")
    draw.rectangle(bounds, outline=(0, 0, 0, 70), width=2)
    image.alpha_composite(edge.filter(ImageFilter.GaussianBlur(0.45)))


def resolve_output(base: Path, path: str) -> Path:
    output = base / path
    output.parent.mkdir(parents=True, exist_ok=True)
    return output


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--plan", default="output/research-control-center-demo/asset-plan.json")
    parser.add_argument("--source", help="Override the source path recorded in the plan")
    args = parser.parse_args()

    root = Path(__file__).resolve().parents[1]
    plan_path = root / args.plan
    output_base = plan_path.parent
    plan = json.loads(plan_path.read_text(encoding="utf-8"))
    source_path = Path(args.source or plan["source"])
    if not source_path.is_absolute():
        source_path = root / source_path
    if not source_path.is_file():
        raise FileNotFoundError(f"missing reference image: {source_path}")

    with Image.open(source_path) as source_file:
        source = source_file.convert("RGBA")
    expected_size = (int(plan["canvas"]["width"]), int(plan["canvas"]["height"]))
    if source.size != expected_size:
        raise ValueError(f"reference is {source.size}, expected {expected_size}")

    background = source.copy()
    draw = ImageDraw.Draw(background, "RGBA")
    for item in plan["background"]["clear"]:
        bounds = read_box(item["box"])
        color = tuple(int(channel) for channel in item.get("color", [31, 33, 33, 244]))
        if len(color) != 4:
            raise ValueError(f"clear color must be RGBA, got {color!r}")
        draw.rectangle(bounds, fill=color)
        if item.get("edge", True):
            soften_edge(background, bounds)

    for item in plan["background"].get("restore", []):
        bounds = read_box(item["box"])
        background.alpha_composite(source.crop(bounds), dest=(bounds[0], bounds[1]))

    for item in plan["background"].get("lines", []):
        start = tuple(int(value) for value in item["from"])
        end = tuple(int(value) for value in item["to"])
        color = tuple(int(channel) for channel in item.get("color", [8, 9, 9, 110]))
        width = int(item.get("width", 1))
        repeat_y = item.get("repeat_y")
        if repeat_y:
            step = int(repeat_y["step"])
            until = int(repeat_y["until"])
            y = start[1]
            while y <= until:
                delta = y - start[1]
                draw.line((start[0], start[1] + delta, end[0], end[1] + delta), fill=color, width=width)
                y += step
        else:
            draw.line((*start, *end), fill=color, width=width)

    background_path = resolve_output(output_base, plan["background"]["output"])
    background.save(background_path, format="PNG")

    for item in plan["crops"]:
        bounds = read_box(item["box"])
        crop = source.crop(bounds)
        output_path = resolve_output(output_base, item["output"])
        crop.save(output_path, format="PNG")
        print(f"{item['name']}: {crop.width}x{crop.height} -> {output_path}")

    print(f"background: {background.width}x{background.height} -> {background_path}")


if __name__ == "__main__":
    main()

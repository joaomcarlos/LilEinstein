#!/usr/bin/env python3
"""Prepare deterministic background and sprite crops for the throughput demo."""

from __future__ import annotations

import argparse
import json
from pathlib import Path
from typing import Any

from PIL import Image, ImageDraw


def read_box(value: list[int]) -> tuple[int, int, int, int]:
    if len(value) != 4:
        raise ValueError(f"expected four crop coordinates, got {value!r}")
    box = tuple(int(item) for item in value)
    if box[2] <= box[0] or box[3] <= box[1]:
        raise ValueError(f"crop must have positive area, got {value!r}")
    return box


def resolve_path(root: Path, value: str) -> Path:
    path = Path(value)
    return path if path.is_absolute() else root / path


def resolve_output(root: Path, output_base: Path, value: str) -> Path:
    path = output_base / value
    path.parent.mkdir(parents=True, exist_ok=True)
    return path


def open_rgba(path: Path) -> Image.Image:
    if not path.is_file():
        raise FileNotFoundError(f"missing sprite source: {path}")
    with Image.open(path) as image:
        return image.convert("RGBA")


def crop_source(path: Path, crop: list[int]) -> Image.Image:
    source = open_rgba(path)
    bounds = read_box(crop)
    if bounds[2] > source.width or bounds[3] > source.height:
        raise ValueError(f"crop {bounds} is outside {path} ({source.width}x{source.height})")
    return source.crop(bounds)


def expected_crop_size(sprite: dict[str, Any]) -> tuple[int, int]:
    crop = read_box(sprite["crop"])
    return crop[2] - crop[0], crop[3] - crop[1]


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--plan",
        default="output/science-throughput-demo/asset-plan.json",
        help="path to the prototype asset plan relative to the repository root",
    )
    args = parser.parse_args()

    root = Path(__file__).resolve().parents[1]
    plan_path = root / args.plan
    plan = json.loads(plan_path.read_text(encoding="utf-8"))
    output_base = plan_path.parent

    reference = plan["reference"]
    reference_path = resolve_path(root, reference["path"])
    background_source_path = resolve_path(output_base, plan["background"]["source"])
    source = open_rgba(background_source_path)
    expected_reference_size = (int(reference["width"]), int(reference["height"]))
    if source.size != expected_reference_size:
        raise ValueError(f"background source is {source.size}, expected {expected_reference_size}")

    if not reference_path.is_file():
        raise FileNotFoundError(f"missing selected reference: {reference_path}")

    background = source.copy()
    draw = ImageDraw.Draw(background, "RGBA")
    for item in plan["background"].get("clear", []):
        bounds = read_box(item["box"])
        color = tuple(int(channel) for channel in item.get("color", [25, 28, 28, 255]))
        if len(color) != 4:
            raise ValueError(f"background clear color must be RGBA, got {color!r}")
        draw.rectangle(bounds, fill=color)

    background_path = resolve_output(root, output_base, plan["background"]["output"])
    background.save(background_path, format="PNG")
    if Image.open(background_path).size != source.size:
        raise ValueError(f"background output has an unexpected size: {background_path}")

    source_roots = {
        "factorio_base": resolve_path(output_base, plan["sources"]["factorio_icon_root"]),
        "factorio_space_age": resolve_path(
            output_base, plan["sources"]["factorio_space_age_icon_root"]
        ),
        "factorio_core": resolve_path(output_base, plan["sources"]["factorio_core_root"]),
        "mod": resolve_path(output_base, plan["sources"]["mod_icon_root"]),
    }
    science_cell_width, science_cell_height = plan["sprite_contract"]["science_atlas_cell_size"]
    science_columns = int(plan["sprite_contract"]["science_atlas_columns"])
    science_rows = int(plan["sprite_contract"]["science_atlas_rows"])
    science_atlas = Image.new(
        "RGBA",
        (science_cell_width * science_columns, science_cell_height * science_rows),
        (0, 0, 0, 0),
    )
    status_cell_width, status_cell_height = plan["sprite_contract"]["status_atlas_cell_size"]
    status_columns = int(plan["sprite_contract"]["status_atlas_columns"])
    status_rows = int(plan["sprite_contract"]["status_atlas_rows"])
    status_atlas = Image.new(
        "RGBA",
        (status_cell_width * status_columns, status_cell_height * status_rows),
        (0, 0, 0, 0),
    )
    manifest: list[dict[str, Any]] = []

    for sprite in plan["sprites"]:
        group = sprite.get("group", "mod")
        source_root = source_roots[group]
        source_path = source_root / sprite["source"]
        source = open_rgba(source_path)
        if group in {"factorio_base", "factorio_space_age"}:
            expected_source_size = tuple(plan["sprite_contract"]["pack_source_size"])
        elif group == "factorio_core":
            expected_source_size = tuple(plan["sprite_contract"]["status_source_size"])
        else:
            expected_source_size = None
        if expected_source_size and source.size != expected_source_size:
            raise ValueError(
                f"unexpected source size for {sprite['id']}: {source.size} != {expected_source_size}"
            )
        crop = crop_source(source_path, sprite["crop"])
        expected_size = expected_crop_size(sprite)
        if crop.size != expected_size:
            raise ValueError(f"crop size mismatch for {sprite['id']}: {crop.size} != {expected_size}")

        output_path = resolve_output(root, output_base, sprite["output"])
        crop.save(output_path, format="PNG")
        if Image.open(output_path).size != expected_size:
            raise ValueError(f"output size mismatch for {sprite['id']}: {output_path}")

        cell_x, cell_y = (int(value) for value in sprite["atlas_cell"])
        if group in {"factorio_base", "factorio_space_age"}:
            atlas = science_atlas
            cell_width, cell_height = science_cell_width, science_cell_height
            atlas_columns, atlas_rows = science_columns, science_rows
            atlas_name = "science"
        else:
            atlas = status_atlas
            cell_width, cell_height = status_cell_width, status_cell_height
            atlas_columns, atlas_rows = status_columns, status_rows
            atlas_name = "status"
        if not 0 <= cell_x < atlas_columns:
            raise ValueError(f"atlas x cell out of range for {sprite['id']}")
        if not 0 <= cell_y < atlas_rows:
            raise ValueError(f"atlas y cell out of range for {sprite['id']}")
        paste_x = cell_x * cell_width + (cell_width - crop.width) // 2
        paste_y = cell_y * cell_height + (cell_height - crop.height) // 2
        atlas.alpha_composite(crop, dest=(paste_x, paste_y))
        manifest.append(
            {
                "id": sprite["id"],
                "group": group,
                "source": str(source_path),
                "crop": sprite["crop"],
                "output": sprite["output"],
                "output_size": list(crop.size),
                "atlas_cell": sprite["atlas_cell"],
                "atlas_pixel_bounds": [paste_x, paste_y, paste_x + crop.width, paste_y + crop.height],
                "display_size": plan["sprite_contract"][
                    "pack_display_size" if group in {"factorio_base", "factorio_space_age"} else "status_display_size"
                ],
                "atlas_name": atlas_name,
                "factorio_name": sprite["factorio_name"],
            }
        )

    atlas_path = output_base / "assets" / "sprite-atlas-preview.png"
    status_atlas_path = output_base / "assets" / "status-atlas-preview.png"
    science_atlas.save(atlas_path, format="PNG")
    status_atlas.save(status_atlas_path, format="PNG")
    manifest_path = output_base / "assets" / "sprite-manifest.json"
    manifest_path.write_text(
        json.dumps(
            {
                "science_atlas": {
                    "path": "sprite-atlas-preview.png",
                    "cell_size": [science_cell_width, science_cell_height],
                    "columns": science_columns,
                    "rows": science_rows,
                    "source_reference": str(reference_path),
                },
                "status_atlas": {
                    "path": "status-atlas-preview.png",
                    "cell_size": [status_cell_width, status_cell_height],
                    "columns": status_columns,
                    "rows": status_rows,
                    "source_reference": str(reference_path),
                },
                "sprites": manifest,
            },
            indent=2,
        )
        + "\n",
        encoding="utf-8",
    )
    print(f"background: {background_path} ({background.width}x{background.height})")
    for item in manifest:
        print(f"{item['id']}: {item['output_size'][0]}x{item['output_size'][1]} -> {item['output']}")
    print(f"science atlas: {atlas_path} ({science_atlas.width}x{science_atlas.height})")
    print(f"status atlas: {status_atlas_path} ({status_atlas.width}x{status_atlas.height})")
    print(f"manifest: {manifest_path}")


if __name__ == "__main__":
    main()

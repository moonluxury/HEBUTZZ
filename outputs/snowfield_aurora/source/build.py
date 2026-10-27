"""A small, optional command-line front end to the central design controls."""
import argparse
import subprocess
import sys
from common import *


def main():
    p = argparse.ArgumentParser(description="Build the same masked logo with adjustable winter materials.")
    p.add_argument("--prepare", action="store_true", help="Rebuild masks from original source labels.")
    p.add_argument("--body-color")
    p.add_argument("--orbit-green")
    p.add_argument("--orbit-violet")
    p.add_argument("--frost", type=float)
    p.add_argument("--snow", type=float)
    p.add_argument("--reflection", type=float)
    p.add_argument("--background-aurora", type=float)
    p.add_argument("--snow-points", type=int)
    args = p.parse_args()
    cfg = read_config()
    mapping = {
        "body_color": ("palette", "body"), "orbit_green": ("palette", "aurora_green"),
        "orbit_violet": ("palette", "aurora_violet"), "frost": ("material", "frost_strength"),
        "snow": ("material", "thin_snow_strength"), "reflection": ("material", "aurora_reflection_strength"),
        "background_aurora": ("background", "aurora_strength"),
        "snow_points": ("background", "snow_points")
    }
    changed = False
    for arg, (group, key) in mapping.items():
        value = getattr(args, arg)
        if value is not None:
            if group == "palette":
                if len(value) != 7 or not value.startswith("#"):
                    p.error(f"{arg}: use #RRGGBB")
                try:
                    rgb(value)
                except ValueError:
                    p.error(f"{arg}: invalid hex color")
            elif key == "snow_points":
                if not 0 <= value <= 100:
                    p.error("snow-points must be 0..100")
            elif not 0 <= value <= 1:
                p.error(f"{arg}: strength must be 0..1")
            cfg[group][key] = value
            changed = True
    if changed:
        save_json(SOURCE / "config.json", cfg)
    if args.prepare or not (MASKS / "silhouette.png").exists():
        subprocess.run([sys.executable, str(SOURCE / "prepare.py")], check=True)
    subprocess.run([sys.executable, str(SOURCE / "render.py")], check=True)
    subprocess.run([sys.executable, str(SOURCE / "validate.py")], check=True)


if __name__ == "__main__":
    main()

"""Verify that the supplied CLI and fixed seeds reproduce both final files."""
import hashlib
import subprocess
import sys
from common import *


def fingerprint():
    return {
        name: hashlib.sha256((FINAL / name).read_bytes()).hexdigest()
        for name in ["logo_snowfield_aurora_transparent.png", "logo_snowfield_aurora_presentation.png"]
    }


def main():
    cfg = read_config()
    before = fingerprint()
    command = [
        sys.executable, str(SOURCE / "build.py"),
        "--body-color", cfg["palette"]["body"],
        "--orbit-green", cfg["palette"]["aurora_green"],
        "--orbit-violet", cfg["palette"]["aurora_violet"],
        "--frost", str(cfg["material"]["frost_strength"]),
        "--snow", str(cfg["material"]["thin_snow_strength"]),
        "--reflection", str(cfg["material"]["aurora_reflection_strength"]),
        "--background-aurora", str(cfg["background"]["aurora_strength"]),
        "--snow-points", str(cfg["background"]["snow_points"])
    ]
    result = subprocess.run(command, capture_output=True, text=True, encoding="utf-8", errors="replace")
    if result.returncode:
        raise RuntimeError(result.stdout + result.stderr)
    after = fingerprint()
    report = {
        "same_final_png_bytes_after_rerender": before == after,
        "configuration_values_preserved": cfg == read_config(),
        "sha256": after,
        "cli_options_exercised": command[2:],
        "method": "Run the provided build command again with all eight public controls at the saved settings."
    }
    assert report["same_final_png_bytes_after_rerender"]
    assert report["configuration_values_preserved"]
    save_json(SOURCE / "reproducibility.json", report)
    progress("阶段九：可编辑文件与复现验证完成",
             "通过公开命令行选项按交付参数重新生成，两份正式 PNG 的 SHA256 均完全一致。"
             "README、配置、五类蒙版、材质控制蒙版、背景分层、构建和验收脚本已保留。",
             "打包并交付正式展示图、透明版与源文件；不改动原图或现有站点。")
    print(json.dumps(report, ensure_ascii=False, indent=2))


if __name__ == "__main__":
    main()

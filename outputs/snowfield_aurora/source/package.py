"""Package deliverables and source, excluding interpreter caches."""
from pathlib import Path
from zipfile import ZipFile, ZIP_DEFLATED
import shutil
from common import ROOT, FINAL

for kind in ("transparent", "presentation"):
    source = FINAL / f"logo_snowfield_aurora_{kind}.png"
    versioned = FINAL / f"logo_snowfield_aurora_{kind}_v3.png"
    shutil.copy2(source, versioned)
    assert source.read_bytes() == versioned.read_bytes()
archive = ROOT.with_name("snowfield_aurora_20261020_v3.zip")
with ZipFile(archive, "w", compression=ZIP_DEFLATED, compresslevel=6) as target:
    for item in sorted(ROOT.rglob("*")):
        if not item.is_file() or "__pycache__" in item.parts or item.suffix in {".pyc", ".import"}:
            continue
        target.write(item, Path(ROOT.name) / item.relative_to(ROOT))
with ZipFile(archive) as target:
    assert target.testzip() is None
    for expected in [
        "final/logo_snowfield_aurora_transparent.png",
        "final/logo_snowfield_aurora_presentation.png",
        "previews/structure_comparison.png",
        "source/config.json", "source/validation.json",
        "README.md", "progress.md"
    ]:
        assert f"{ROOT.name}/{expected}" in target.namelist()
    print(f"{archive}\n{archive.stat().st_size} bytes; {len(target.namelist())} files; ZIP validation passed.")

from pathlib import Path
import importlib.util
import os
import sys

WORK = Path(__file__).resolve().parent
RUNTIME = Path(r'C:\Users\Legion\.cache\codex-runtimes\codex-primary-runtime\dependencies')
RENDERER = Path(r'C:\Users\Legion\.codex\plugins\cache\openai-primary-runtime\documents\26.1013.11914\skills\documents\render_docx.py')
os.environ['PATH'] = str(RUNTIME / 'native/poppler/Library/bin') + os.pathsep + os.environ['PATH']
spec = importlib.util.spec_from_file_location('docx_renderer', RENDERER)
renderer = importlib.util.module_from_spec(spec)
spec.loader.exec_module(renderer)

# The packaged runtime has no LibreOffice on Windows. Word exported this exact
# DOCX to PDF; retain the packaged renderer's rasterization and page naming.
def use_word_export(*args, **kwargs):
    pdf = WORK / 'word-preview.pdf'
    if not pdf.is_file() or pdf.stat().st_size == 0:
        raise FileNotFoundError(pdf)
    return str(pdf), 'PDF exported by installed Word automation'

renderer.convert_to_pdf = use_word_export
sys.argv = [str(RENDERER), str(WORK.parent / '河工开物投稿模板.docx'), '--output_dir', str(WORK / 'render'), '--dpi', '144']
renderer.main()

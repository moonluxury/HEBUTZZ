from pathlib import Path
import hashlib,shutil,json

work=Path(__file__).resolve().parent
stage=(work/'HEBUT先进空天').resolve()
destination=Path('C:/Users/Legion/Desktop/版本1/HEBUT先进空天').resolve()
files=sorted(p for p in stage.rglob('*') if p.is_file())
assert len(files)==27
plan=[]
for source in files:
    relative=source.relative_to(stage)
    target=(destination/relative).resolve()
    assert target.is_relative_to(destination)
    digest=hashlib.sha256(source.read_bytes()).hexdigest()
    if target.exists() and (not target.is_file() or hashlib.sha256(target.read_bytes()).hexdigest()!=digest):
        raise RuntimeError('Existing different file, left untouched: '+str(target))
    plan.append((source,target,digest))
destination.mkdir(parents=True,exist_ok=True)
copied=0
for source,target,digest in plan:
    target.parent.mkdir(parents=True,exist_ok=True)
    if not target.exists():
        shutil.copy2(source,target)
        copied+=1
    assert hashlib.sha256(target.read_bytes()).hexdigest()==digest
report={'destination':str(destination),'logo_png_count':24,'overview_png_count':1,'support_files':2,'copied_files':copied,'verified_files':len(plan),'all_hashes_match':True}
(work/'copy_report.json').write_text(json.dumps(report,ensure_ascii=False,indent=2),encoding='utf-8')
print(json.dumps(report,ensure_ascii=False,indent=2))

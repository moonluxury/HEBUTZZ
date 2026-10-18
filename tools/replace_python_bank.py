"""Build the Python bank exclusively from 编程2.docx and 编程大题1.docx.

Document reference programs are inspected with ast.parse, never executed.
Repeated source versions are retained with distinct, stable source IDs.
"""
import argparse
import ast
from collections import Counter
import hashlib
import itertools
import json
from pathlib import Path
import re
from zipfile import ZipFile
from lxml import etree
from python_text_exercises import OUTPUTS, OUTPUT_NOTES, FILLS, verify_outputs

ROOT=Path(__file__).resolve().parents[1]
NS={'w':'http://schemas.openxmlformats.org/wordprocessingml/2006/main','a':'http://schemas.openxmlformats.org/drawingml/2006/main','r':'http://schemas.openxmlformats.org/officeDocument/2006/relationships'}
QUESTIONS=[]
AUDIT=[]


def read_docx(path):
    with ZipFile(path) as archive:
        root=etree.fromstring(archive.read('word/document.xml'))
        rels=etree.fromstring(archive.read('word/_rels/document.xml.rels'))
        targets={r.get('Id'):r.get('Target') for r in rels}
        paragraphs=[]
        for i,p in enumerate(root.findall('.//w:body//w:p',NS)):
            text=''.join(n.text or '' if n.tag.endswith('}t') else '\t' if n.tag.endswith('}tab') else '\n'
                         for n in p.iter() if n.tag in [f'{{{NS["w"]}}}t',f'{{{NS["w"]}}}tab',f'{{{NS["w"]}}}br'])
            images=[targets[n.get(f'{{{NS["r"]}}}embed')] for n in p.findall('.//a:blip',NS)]
            paragraphs.append({'index':i,'text':text,'images':images})
        media={n.removeprefix('word/'):archive.read(n) for n in archive.namelist() if n.startswith('word/media/') and not n.endswith('/')}
    return paragraphs,media


def clean(text):
    return text.replace('\u00a0',' ').replace('\u200b','').replace('\r','')


def add(kind,stem,source_id,source,locator,**extra):
    q={'id':len(QUESTIONS)+1,'source_id':source_id,'type':kind,
       'type_label':{'single':'单选题','output':'读程序写结果','fill':'程序填空题','program':'编程题'}[kind],
       'stem':stem,'source':source,'source_locator':locator,'language':'python','options':[],**extra}
    QUESTIONS.append(q)
    return q


def image_choices(media):
    reviewed=json.loads((ROOT/'tools/python_choice_transcriptions.json').read_text(encoding='utf-8'))['images']
    assert len(reviewed)==372
    for entry in reviewed:
        number=entry['number']
        assert f'media/image{number}.png' in media
        assert len(entry['options'])==4 and all(t.strip() for t in entry['options'])
        add('single',entry['stem'],f'py-v2-image-{number}','编程2.docx',f'图片 {number}（已转写为文字）',
            preserve_option_order=True,
            options=[{'key':letter,'text':text,'correct':letter==entry['answer']} for letter,text in zip('ABCD',entry['options'])],
            answer_raw=entry['answer'],answer_title='参考答案（原资料）',
            explanation=entry.get('note',''),
            source_note=entry.get('note','题干、代码及选项已转为文字，参考答案沿用原资料。'))


def text_choices(paragraphs):
    blocks=[]
    for p in paragraphs:
        if not 228<=p['index']<=476:continue
        for part in re.split(r'(?m)^\s*(?=\d{3}(?:[.．、]|[\u4e00-\u9fff]))',p['text']):
            if not part.strip():continue
            if re.search(r'[（(][A-D][）)]',part):
                blocks.append({'paragraph':p['index'],'text':part.strip()})
            elif blocks:
                blocks[-1]['text']+='\n'+part.strip()
    for n,b in enumerate(blocks,1):
        raw=clean(b['text'])
        match=re.search(r'[（(]([A-D])[）)]',raw)
        answer=match[1]
        stem=raw[:match.start()]+raw[match.end():]
        stem=re.sub(r'^\d{3}[.．、]?\s*','',stem)
        markers=list(re.finditer(r'(?m)^\s*([ABCD])(?:[.:：、]|(?=[\s\u4e00-\u9fff\[\(<\'\"])).*',stem))
        sequence=[]
        for marker in markers:
            if marker[1]=='ABCD'[len(sequence)]:
                sequence.append(marker)
                if len(sequence)==4:break
        common={'source_raw':raw,'source_paragraph':b['paragraph'],'answer_raw':answer,
                'source_note':'原资料文字版；与截图版重复的题目保留各自版本。题干及代码按原文收录，参考答案未逐题重新审定。'}
        if len(sequence)==4:
            options=[]
            for k,m in enumerate(sequence):
                end=sequence[k+1].start() if k<3 else len(stem)
                text=re.sub(r'^\s*[ABCD][.:：、]?\s*','',stem[m.start():end]).strip()
                options.append({'key':m[1],'text':text,'correct':m[1]==answer})
            add('single',stem[:sequence[0].start()].strip(),f'py-v2-text-{n}','编程2.docx',f'文字选择题第 {n} 条（段落 {b["paragraph"]}）',options=options,**common)
        else:
            add('single',stem,f'py-v2-text-{n}','编程2.docx',f'文字选择题第 {n} 条（段落 {b["paragraph"]}）',
                preserve_option_order=True, options=[{'key':letter,'text':'见题干选项','correct':letter==answer} for letter in 'ABCD'],**common)
            AUDIT.append({'source_id':f'py-v2-text-{n}','issue':'原文选项排版不规则，保留全文及原选项顺序，使用 A—D 按钮作答。'})


def outputs_and_fills(paragraphs):
    verify_outputs()
    for number,code,answer,mode in OUTPUTS:
        index=476+number if number<=9 else 477+number
        raw=paragraphs[index]['text']
        if number==9:raw+='\n'+paragraphs[486]['text']
        answers=[answer]
        if number==29:
            answers=['{'+', '.join(map(str,p))+'}' for p in itertools.permutations([1,3,4,6])]
        note=OUTPUT_NOTES.get(number,'仅整理原文引号、标识符拼写与缩进；表达式题通过 print 显示所求值。')
        add('output','阅读下列 Python 程序，写出输出结果；如运行报错，填写异常类型。\n\n'+code,
            f'py-v2-output-{number}','编程2.docx',f'二 读程序写结果 第 {number} 题',
            answers=answers,answer_raw=answer,answer_mode=mode,answer_title='参考输出（已校验）',
            explanation=note,source_raw=raw,source_note=note)
    for number,(start,end,prompt,code,answers,note) in enumerate(FILLS,1):
        raw='\n'.join(p['text'] for p in paragraphs[start:end+1])
        add('fill',prompt+'\n\n'+code+('\n\n资料说明：'+note if note else ''),
            f'py-v2-fill-{number}','编程2.docx',f'三 程序填空 第 {number} 题',
            blanks=[{'label':f'第 {i} 空','answers':values} for i,values in enumerate(answers,1)],
            answer_raw='；'.join(f'（{i}）{v[0]}' for i,v in enumerate(answers,1)),
            explanation=note or '按原题参考答案核对，允许列出的等价写法。',source_raw=raw)
        if note:AUDIT.append({'source_id':f'py-v2-fill-{number}','issue':note})


CODE_START=re.compile(r'^(?:#|import\s|from\s|def\s|class\s|for\s|while\s|if\s|with\s|try:|[A-Za-z_]\w*(?:\s*,\s*\w+)*\s*(?:\[[^\n]*?\])?\s*=)')
REFERENCE_START={1:1,2:15,3:33,4:44,9:101,11:117,12:120,13:133,14:143,15:174,16:183,26:344,32:443,50:711,60:872}


def programs(paragraphs,media):
    starts=[]
    expected=1
    for p in paragraphs:
        if re.match(rf'^\s*{expected}(?:[.．、#]|(?=[\u4e00-\u9fff]))',p['text']):
            starts.append(p['index']);expected+=1
    assert expected==108,('Missing program heading',expected)
    for number,start in enumerate(starts,1):
        end=starts[number] if number<len(starts) else len(paragraphs)
        if number==56:end=844
        chunk=paragraphs[start:end]
        split=REFERENCE_START.get(number)
        if split is None:
            split=next((p['index'] for p in chunk[1:] if CODE_START.match(clean(p['text']).lstrip())),end)
        question='\n'.join(clean(p['text']) for p in chunk if p['index']<split and p['text'].strip())
        question=re.sub(rf'^\s*{number}[.．、#]*\s*#?','',question)
        code='\n'.join(clean(p['text']) for p in chunk if p['index']>=split).strip()
        notes=['参考内容来自原资料，请对照题意自行检查解法。']
        if number in [36,37]:
            question='\n'.join(clean(p['text']) for p in paragraphs[536:544])
            question=re.sub(r'(?m)^(36|37)\.','',question)
            code='\n'.join(clean(p['text']) for p in paragraphs[544:550]).strip()
            notes.append('原资料第 36、37 条连续描述同一道库存题，合并上下文展示，两处题号均保留。')
        if number==31:
            notes.append('原题要求判断数字是否互不相同，但所附参考程序是成绩分级，两者不对应，请勿据此判定解答。')
            AUDIT.append({'source_id':'py-v2-program-31','issue':notes[-1]})
        if number in [2,49,58,60,69,81,84,85,86,103,104,107]:
            data_lines=[]
            for line in code.splitlines():
                if line.lstrip().startswith('#'):continue
                try:
                    node=ast.parse(line).body[0]
                    value=ast.literal_eval(node.value) if isinstance(node,ast.Assign) else None
                    if not isinstance(value,(list,dict,tuple,str)) or not value:break
                    data_lines.append(line)
                except (ValueError,SyntaxError,IndexError):break
            if data_lines:
                question+='\n\n原资料参考程序所给数据：\n'+'\n'.join(data_lines)
        if not code:code='原资料未提供参考代码。';notes.append('本题原资料只有题目描述。')
        elif number in [11,12]:notes.append('原资料只提供结果，没有参考程序。'+('题干缺少四名嫌疑人的陈述，无法据此推导。' if number==11 else ''))
        else:
            try:ast.parse(code)
            except SyntaxError as error:
                notes.append(f'原参考代码第 {error.lineno} 行存在语法或缩进问题，保留原文供核对。')
                AUDIT.append({'source_id':f'py-v2-program-{number}','issue':notes[-1]})
        q=add('program',question,f'py-v2-program-{number}','编程大题1.docx',f'第 {number} 题',
              reference_code=code,source_note='\n'.join(notes),
              source_raw='\n'.join(p['text'] for p in chunk),source_number=number,source_paragraph=start,reference_start=split)
        if number==9:
            q['stem']='假设已有字典变量 dic_score 存储了学生的成绩信息，姓名为字典的键。试编写程序，统计每名学生的平均成绩，添加至字典，最后将字典内容输出。\n\n姓名        语文  数学  英语  计算机\nXuLi        88    90    98    95\nZhangXing   85    92    95    98\nLiuNing     89    89    90    92\nZhangXu     82    86    89    90'
        elif number==53:
            q['stem']='编写一个递归函数，计算下面的级数：\n\nm(i) = 1 + 1/2 + 1/3 + 1/4 + 1/5 + … + 1/i'
        if number==11:AUDIT.append({'source_id':q['source_id'],'issue':'题干缺少嫌疑人的陈述；保留残题并标注。'})
    add('program','编写程序输出如下图形（各行星号之间没有空格）：\n\n*******\n *****\n  ***\n   *','py-v2-program-unnumbered-stars','编程大题1.docx','第 56 题之后的无编号图形题',
        reference_code='\n'.join(clean(p['text']) for p in paragraphs[846:852]),
        source_note='原资料无题号，单独收录。参考程序最后的 print() 缩进缺失，按图形要求应在外层循环内换行。')


def extra_programs(paragraphs):
    starts=[609,626,628,652,662,670,674,686]
    splits=[610,628,629,653,663,671,677,687]
    for number,(start,split) in enumerate(zip(starts,splits),1):
        end=starts[number] if number<len(starts) else len(paragraphs)
        question='\n'.join(clean(p['text']) for p in paragraphs[start:split] if p['text'].strip())
        code='\n'.join(clean(p['text']) for p in paragraphs[split:end] if p['text'].strip())
        if not code:code='原资料未提供参考程序。'
        note='参考内容按原资料保留；与另一份文档的重复题保留各自版本。请对照题意自行核对。'
        add('program',question,f'py-v2-extra-program-{number}','编程2.docx',f'编程部分第 {number} 题',reference_code=code,source_note=note)


def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--source',type=Path,default=Path('C:/Users/Legion/Desktop/编程2.docx'))
    parser.add_argument('--programs',type=Path,default=Path('C:/Users/Legion/Desktop/编程大题1.docx'))
    args=parser.parse_args()
    QUESTIONS.clear();AUDIT.clear()
    p,media=read_docx(args.source)
    pp,pm=read_docx(args.programs)
    image_choices(media)
    text_choices(p)
    outputs_and_fills(p)
    programs(pp,pm)
    extra_programs(p)
    transcriptions=json.loads((ROOT/'tools/python_choice_transcriptions.json').read_text(encoding='utf-8'))
    for q in QUESTIONS:
        if q['source_id'] in transcriptions.get('text_versions',{}):
            entry=transcriptions['text_versions'][q['source_id']]
            q['stem']=entry['stem']
            q['options']=[{'key':letter,'text':text,'correct':letter==q['answer_raw']} for letter,text in zip('ABCD',entry['options'])]
            q['preserve_option_order']=True
            q['source_note']='文字版排版已整理；参考答案沿用该版本原资料。'
            q['explanation']=entry.get('note','')
            AUDIT[:]=[issue for issue in AUDIT if issue['source_id'] != q['source_id']]
    assert all(not q.get('images') and not q.get('reference_images') for q in QUESTIONS)
    assert len({q['source_id'] for q in QUESTIONS})==len(QUESTIONS)
    assert all(q['stem'].strip() for q in QUESTIONS)
    assert all(option['text'] != '见题干选项' for q in QUESTIONS for option in q['options'])
    (ROOT/'data/questions_python.json').write_text(json.dumps(QUESTIONS,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
    report={'version':'python-v2-two-documents','sources':[{'path':str(f),'sha256':hashlib.sha256(f.read_bytes()).hexdigest()} for f in [args.source,args.programs]],
            'total':len(QUESTIONS),'types':dict(Counter(q['type'] for q in QUESTIONS)),
            'coverage':{'screenshot_choices':372,'text_choice_versions':sum(q['source_id'].startswith('py-v2-text-') for q in QUESTIONS),'output':35,'fill':len(FILLS),'programs_document_numbered':107,'programs_document_unnumbered':1,'extra_programs':8},
            'excluded_non_questions':[{'source':'编程2.docx','image':70,'reason':'Python 保留字知识表，不是题目。'}],
            'duplicate_policy':'保留原文中的重复版本，未用相似度合并或丢弃题目。',
            'answer_policy':'选择题按原资料参考答案；35道输出题按展示代码校验；编程题可主动运行自己的代码并查看参考代码，运行成功不代表自动判题通过。',
            'presentation':'所有890题均为文字；372道图片选择题、成绩表、级数和星号图形均已转写，不再展示题目截图。',
            'old_bank':'旧100题全部替换；旧Python错题文件保留但新题库使用独立v2错题文件。',
            'issues':AUDIT}
    (ROOT/'data/python_source_notes.json').write_text(json.dumps(report,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
    print(json.dumps({k:report[k] for k in ['total','types','coverage']},ensure_ascii=False,indent=2))
    print('All 35 reviewed output programs verified.')


if __name__=='__main__':main()

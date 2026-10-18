"""Extract C++ choice, text-fill and program-output questions with a source audit.

Reads PDF text as data. No source or learner code is executed.
"""
import argparse
import json
import re
import textwrap
from collections import Counter
from pathlib import Path

import pdfplumber

ROOT = Path(__file__).resolve().parents[1]
HEADER = re.compile(r'\[第\s*(\d+)\s*题\s*ID=(\d+)\]')
SECTION = re.compile(r'\[(单项选择|程序填空|读程序写结果|编程)\]\s*共\s*(\d+)\s*题')
BLANK = re.compile(r'^空\s*(\d+)\s*[:：]\s*(.*)$')
OPTION = re.compile(r'^([A-F])(?:\s*[.．、:：)）]\s*|$)(.*)$')


def read_records(pages):
    records, current, kind = [], None, None
    for p in pages:
        for raw in p['text'].splitlines():
            line = raw.strip()
            section = SECTION.match(line)
            if section:
                kind, current = section[1], None
                continue
            header = HEADER.match(line)
            if header:
                current = {'source_number': int(header[1]), 'source_id': int(header[2]),
                           'kind': kind, 'pages': [p['page']], 'lines': []}
                records.append(current)
                continue
            if re.match(r'^(?:={4,}|--- .*\(\d+\s*题\) ---)$', line):
                current = None
                continue
            if current is not None:
                if p['page'] not in current['pages']:
                    current['pages'].append(p['page'])
                current['lines'].append(raw.rstrip())
    return records


def clean_text(lines):
    parts, block, in_code = [], [], False
    for raw in lines:
        if raw.strip().startswith('```'):
            if in_code:
                parts.append(format_code(textwrap.dedent('\n'.join(block))))
                block = []
            in_code = not in_code
            parts.append('')
        elif in_code:
            block.append(raw)
        else:
            line = raw.strip().replace('`', '')
            line = re.sub(r'\\frac\{([^{}]+)\}\{([^{}]+)\}', r'(\1)/(\2)', line)
            line = re.sub(r'\${1,2}([^$]+)\${1,2}', r'\1', line)
            parts.append(line)
    parts.extend(block)
    text = '\n'.join(parts).strip()
    text = re.sub(r'\n{3,}', '\n\n', text)
    return text.strip()


def format_code(block):
    lines = [line.strip() for line in block.splitlines()]
    if lines == ['*', '***', '*****', '*******']:
        return '\n'.join(' ' * (3 - i) + line for i, line in enumerate(lines))
    if not any(';' in line or '{' in line or line.startswith('#include') for line in lines):
        return block
    formatted, depth, pending = [], 0, 0
    for line in lines:
        # Braces inside literals/comments do not control indentation.
        syntax = re.sub(r'"(?:\\.|[^"\\])*"|\'(?:\\.|[^\'\\])*\'|//.*', '', line)
        closes = len(re.match(r'^\}*', syntax)[0])
        indent = max(0, depth - closes)
        if not line.startswith(('{', '}')):
            indent += pending
        if line in ['public:', 'protected:', 'private:']:
            indent = max(0, depth - 1)
        if line.startswith('#'):
            indent = 0
        formatted.append('    ' * indent + line if line else '')
        depth = max(0, depth + syntax.count('{') - syntax.count('}'))
        if re.match(r'^(?:for|while|if|else if)\s*\(.*\)$|^else$', syntax):
            pending += 1
        else:
            pending = 0
    return '\n'.join(formatted)


def label_blanks(stem, count):
    # The same unnumbered blank can be mentioned in prose and repeated in code.
    # A single source answer is reused for all those occurrences.
    seen = set()
    number_pattern = r'(?:\(([1-9])\)|（([1-9])）|([①②③④⑤⑥⑦⑧⑨⑴⑵⑶⑷⑸⑹⑺⑻⑼]))'
    pattern = re.compile(r'_{3,}(?:\s*' + number_pattern + r'\s*_{3,})?')
    def replace(match):
        ordinary = match[1] or match[2]
        circled = match[3]
        if ordinary:
            number = int(ordinary)
        elif circled:
            digits = '①②③④⑤⑥⑦⑧⑨' if circled in '①②③④⑤⑥⑦⑧⑨' else '⑴⑵⑶⑷⑸⑹⑺⑻⑼'
            number = digits.index(circled) + 1
        else:
            number = 1
        if not ordinary and not circled and count != 1:
            raise ValueError('多空题含未编号的横线，需人工核对')
        seen.add(number)
        return f'____({number})____'
    stem = pattern.sub(replace, stem)
    if seen != set(range(1, count + 1)):
        raise ValueError(f'题干填空编号与答案不匹配：{seen}')
    return stem


FILL_REPAIRS = {
    20004: [('include <iostream>\n', 'include <iostream>\nusing namespace std;\n')],
    20005: [('double mul=1;', 'double mul=1;\nint j;'), ('for (int j=2;j<i;j++)', 'for (j=2;j<i;j++)')],
    20008: [('for(j=1;', 'for(int j=1;')],
    20012: [('void main()\n', '')],
    20021: [('char *p="program"', 'const char *p="program"')],
    20025: [('for (int i=0,j=0;', 'int j=0;\nfor (int i=0;')],
    40629: [('const int N = 5\n', 'const int N = 5;\n')],
    40630: [('char *days[]', 'const char *days[]')],
    40622: [('char name[255]\n', 'char name[255];\n')],
    40623: [('}\nTIME*', '};\nTIME*')],
    40624: [('cout << "pls input the number of students:"\n', 'cout << "pls input the number of students:";\n')],
}


OUTPUT_REPAIRS = {
    30014: [('for (int i=1,count=0;i<=10;i++)', 'int count=0;\nfor (int i=1;i<=10;i++)')],
    30019: [('for(i=0;i<4;i++)', 'for(int i=0;i<4;i++)')],
    30025: [('for (i=0;i<2;i++)', 'for (int i=0;i<2;i++)')],
    40625: [('char name[255]\n', 'char name[255];\n')],
}


def convert_output(record, question, answer_pos):
    if record['source_id'] == 30010:
        raise ValueError('第 160 页空白，原程序仅剩函数头，并混入后续题目的代码')
    lines = record['lines']
    answer = [lines[answer_pos].strip().removeprefix('答案:').strip()]
    body_start = answer_pos + 1
    while body_start < len(lines):
        line = lines[body_start].strip()
        if line.startswith('```') or re.match(r'^(阅读|下列|下面|请|程序|写出)', line):
            break
        answer.append(line)
        body_start += 1
    body = lines[body_start:]
    repairs = []
    if record['source_id'] == 40625:
        # Page 193 contains this complete snippet; page 194 is blank and the
        # following text belongs to other questions whose headers are missing.
        last = next(i for i, line in enumerate(body) if line.strip() == 'cout << (p++)->name;')
        body = body[:last + 1] + ['```']
        question['pages'] = [193]
        repairs.append({'note': '从第 193 页恢复完整题干与答案，剔除空白页之后混入的其他题目片段。'})
    if sum(line.strip().startswith('```') for line in body) % 2:
        raise ValueError('程序或输入示例的边界不完整，需对照原页补全')
    if not any(line.strip().startswith('```') for line in body):
        raise ValueError('缺少程序代码')
    stem = clean_text(body)
    for old, new in OUTPUT_REPAIRS.get(record['source_id'], []):
        if old in stem:
            stem = stem.replace(old, new)
            repairs.append({'before': old, 'after': new})
    if repairs:
        stem = '\n\n'.join(format_code(part) for part in stem.split('\n\n'))
        question['source_repairs'] = repairs
    if stem.startswith('#') or stem.startswith(('enum ', 'class ', 'struct ', 'int ', 'void ')):
        stem = '阅读下面程序，写出输出结果。\n\n' + stem
    answer_text = '\n'.join(answer).strip()
    if not answer_text or not stem or '答案:' in stem:
        raise ValueError('输出答案或题干缺失、混入其他题目')
    question.update({'type': 'output', 'type_label': '读程序写结果', 'stem': stem,
                     'answers': [answer_text], 'answer_raw': answer_text,
                     'explanation': '按原资料参考输出核对。忽略行首尾空白及连续空格、制表符的差别；保留字符、大小写、输出顺序与换行。'})
    return question


def convert(record):
    if record['source_id'] == 40448:
        raise ValueError('第 81 页空白，该题仅剩 A、B 选项，后续选项缺失')
    if record['source_id'] == 40401:
        raise ValueError('第 41～42 页题目截断，并混入下一题的答案和内容')
    lines = record['lines']
    answer_pos = next((i for i, line in enumerate(lines) if line.strip().startswith('答案:')), None)
    if answer_pos is None:
        raise ValueError('缺少参考答案，题目受空白页影响')
    question = {key: record[key] for key in ['source_number', 'source_id', 'pages']}
    question.update({'source': 'C++题库（400页）.pdf', 'language': 'cpp',
                     'answer_basis': '源 PDF 参考答案', 'options': []})
    if record['kind'] == '读程序写结果':
        return convert_output(record, question, answer_pos)
    if record['kind'] == '单项选择':
        answer = lines[answer_pos].strip().removeprefix('答案:').strip()
        if not re.fullmatch('[A-F]', answer):
            raise ValueError(f'单选答案不明确：{answer}')
        stem, options, active = [], [], None
        for line in lines[answer_pos + 1:]:
            option = OPTION.match(line.strip())
            if option:
                active = {'key': option[1], 'lines': [option[2]]}
                options.append(active)
            elif active is not None:
                active['lines'].append(line)
            else:
                stem.append(line)
        keys = [o['key'] for o in options]
        if len(keys) < 3 or keys != list('ABCDEF'[:len(keys)]) or answer not in keys:
            raise ValueError(f'选项不完整或标记不规范：{keys}')
        if not clean_text(stem):
            raise ValueError('缺少题干')
        question.update({'type': 'single', 'type_label': '单选题', 'stem': clean_text(stem), 'answer_raw': answer,
                         'options': [{'key': o['key'], 'text': clean_text(o['lines']), 'correct': o['key'] == answer} for o in options]})
        return question

    answer_lines, rest = [], lines[answer_pos + 1:]
    last_blank = None
    while rest:
        line = rest[0].strip()
        match = BLANK.match(line)
        if match:
            last_blank = {'number': int(match[1]), 'text': match[2]}
            answer_lines.append(last_blank)
        elif last_blank is not None and (last_blank['text'].count('(') > last_blank['text'].count(')') or last_blank['text'].endswith('或 void')):
            last_blank['text'] += ' ' + line
        else:
            break
        rest = rest[1:]
    if [a['number'] for a in answer_lines] != list(range(1, len(answer_lines) + 1)) or not answer_lines:
        raise ValueError('填空答案编号不连续或缺失')
    question.update({'type': 'fill', 'type_label': '填空题', 'stem': clean_text(rest),
                     'blanks': [{'label': f'第 {a["number"]} 空', 'answers': re.split(r'\s+或\s+', a['text'])} for a in answer_lines],
                     'answer_raw': '；'.join(f'（{a["number"]}）{a["text"]}' for a in answer_lines)})
    if not re.search(r'_{3,}', question['stem']):
        raise ValueError('题干中没有可定位的填空横线')
    # Mechanical source repairs only; answer expressions remain source-based.
    repairs = []
    for old, new in FILL_REPAIRS.get(record['source_id'], []):
        if old in question['stem']:
            question['stem'] = question['stem'].replace(old, new)
            repairs.append({'before': old, 'after': new})
    if repairs:
        question['source_repairs'] = repairs
        question['stem'] = '\n\n'.join(format_code(part) for part in question['stem'].split('\n\n'))
    question['stem'] = label_blanks(question['stem'], len(question['blanks']))
    question['explanation'] = '按原资料参考答案核对，支持列出的等价写法；未列出的等价写法可对照参考答案复核。'
    return question


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('pdf', nargs='?', type=Path, default=Path('F:/C++题库（400页）.pdf'))
    parser.add_argument('--pages-json', type=Path, help='Read a previously extracted page cache')
    parser.add_argument('--output', type=Path, default=ROOT / 'data/questions_cpp.json')
    parser.add_argument('--report', type=Path, default=ROOT / 'data/cpp_source_notes.json')
    args = parser.parse_args()
    if args.pages_json:
        pages = json.loads(args.pages_json.read_text(encoding='utf-8'))
    else:
        with pdfplumber.open(args.pdf) as pdf:
            pages = [{'page': i, 'text': '\n'.join(' ' * max(0, round((line['x0'] - 72) / 4)) + line['text']
                      for line in page.extract_text_lines(return_chars=False))} for i, page in enumerate(pdf.pages, 1)]
    records = read_records(pages)
    questions, excluded = [], []
    for record in records:
        if record['kind'] not in ['单项选择', '程序填空', '读程序写结果']:
            continue
        try:
            question = convert(record)
        except ValueError as error:
            excluded.append({k: record[k] for k in ['source_number', 'source_id', 'kind', 'pages']} | {'reason': str(error)})
            continue
        question['id'] = len(questions) + 1
        questions.append(question)
    args.output.write_text(json.dumps(questions, ensure_ascii=False, indent=2) + '\n', encoding='utf-8')
    report = {'source': str(args.pdf), 'page_count': len(pages),
              'blank_pages': [p['page'] for p in pages if not p['text'].strip()],
              'identified_records': dict(Counter(r['kind'] for r in records)),
              'included': dict(Counter(q['type'] for q in questions)), 'total': len(questions),
              'excluded_incomplete': excluded,
              'directory_counts': {'单项选择': 269, '程序填空': 71, '读程序写结果': 78, '编程': 390},
              'unavailable_in_scope': {'count': 418 - len(questions), 'missing_source_numbers': [108, 132, 133, 134, 576, 623, 624, 625, 626, 800, 801, 802],
                                       'incomplete_source_numbers': [r['source_number'] for r in excluded]},
              'output_questions': {'directory_count': 78, 'included': sum(q['type'] == 'output' for q in questions),
                                   'missing_source_numbers': [132, 133, 134, 800, 801, 802],
                                   'incomplete_source_numbers': [131], 'recovered_source_numbers': [799]},
              'missing_source_numbers': sorted(set(range(1, 809)) - {r['source_number'] for r in records}),
              'source_repairs': [{'source_id': q['source_id'], 'changes': q['source_repairs']} for q in questions if 'source_repairs' in q],
              'scope': '不分章节；选择题、文字填空题及读程序写结果题；输出题支持多行文字作答，不执行代码。整段编程题暂未导入。',
              'answer_policy': '以 PDF 参考答案为基础，未逐题编译或重新审定全部答案。'}
    args.report.write_text(json.dumps(report, ensure_ascii=False, indent=2) + '\n', encoding='utf-8')
    print(json.dumps({key: report[key] for key in ['page_count', 'blank_pages', 'identified_records', 'included', 'total', 'excluded_incomplete', 'missing_source_numbers']}, ensure_ascii=False, indent=2))


if __name__ == '__main__':
    main()

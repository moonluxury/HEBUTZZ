"""Immutable answer keys and pure grading; learner code is never executed."""
from functools import lru_cache
import hashlib
import json
import os
from pathlib import Path
import re

from psycopg.types.json import Jsonb

FILES = {'xi': 'questions.json', **{name: 'questions_' + name + '.json' for name in ['marxism', 'mao', 'matlab', 'python', 'cpp']}}
TYPES = ['single', 'multiple', 'judge', 'fill', 'output']
TOKEN = re.compile(r'''"(?:\\.|[^"\\])*"|'(?:\\.|[^'\\])*'|[A-Za-z_][A-Za-z_0-9]*|[0-9]+(?:\.[0-9]+)?|->\*|<<=|>>=|::|->|\.\*|\+\+|--|&&|\|\||<<|>>|==|!=|<=|>=|\*\*|//|\+=|-=|\*=|/=|%=|&=|\|=|\^=|\S''')


@lru_cache(maxsize=1)
def banks():
    location = Path(os.environ.get('QUIZ_BANK_PATH', Path(__file__).with_name('question_banks')))
    if not location.exists(): location = Path(__file__).resolve().parents[1] / 'data'
    result = {}
    for subject, filename in FILES.items():
        text = (location / filename).read_text(encoding='utf-8-sig').replace('\r\n', '\n')
        version = hashlib.sha256(text.encode()).hexdigest()
        content = json.loads(text)
        questions = content if isinstance(content, list) else content['questions']
        grading = {}
        for question in questions:
            if question.get('type', 'single') not in TYPES: continue
            qid = str(question['id'])
            if qid in grading: raise ValueError('Duplicate question ID in ' + subject)
            grading[qid] = {key: question[key] for key in ['type', 'blanks', 'answers', 'answer_mode', 'language'] if key in question}
            grading[qid]['keys'] = sorted(str(item['key']) for item in question.get('options', []) if item.get('correct'))
        result[subject] = {'version': version, 'grading': grading}
    return result


def install(conn):
    for subject, value in banks().items():
        conn.execute('INSERT INTO quiz_bank_versions(subject_id,version,grading) VALUES (%s,%s,%s) ON CONFLICT DO NOTHING', (subject, value['version'], Jsonb(value['grading'])))


def tokens(value, language='python'):
    result = TOKEN.findall(value.strip())
    if language == 'python':
        result = ['string:' + token[1:-1] if len(token) >= 2 and token[0] in "\"'" and token[-1] == token[0] else token for token in result]
    return '\x1f'.join(result)


def output(value):
    return '\n'.join(re.sub(r'[ \t]+', ' ', line.strip()) for line in value.replace('\r\n', '\n').replace('\r', '\n').split('\n')).strip()


def correct(question, answer):
    kind = question.get('type', 'single')
    entered = answer['entered_answers']
    if kind == 'fill':
        blanks = question['blanks']
        return len(entered) == len(blanks) and all(value.strip() and any(tokens(value, question.get('language', 'python')) == tokens(accepted, question.get('language', 'python')) for accepted in blank['answers']) for value, blank in zip(entered, blanks))
    if kind == 'output':
        normalize = tokens if question.get('answer_mode') == 'python_value' else output
        return len(entered) == 1 and bool(entered[0].strip()) and any(normalize(entered[0]) == normalize(accepted) for accepted in question['answers'])
    return kind in TYPES and bool(question['keys']) and sorted(answer['selected_keys']) == question['keys']

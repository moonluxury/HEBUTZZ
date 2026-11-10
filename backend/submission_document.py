"""Strict, versioned rich-text document protocol shared by publication and DOCX.

HTML is never a source of truth. Only these nodes and attributes may reach a
published article; links and media references are validated independently.
"""
import copy
import re
from urllib.parse import urlsplit

VERSION = 1
MAX_TEXT = 50000
MAX_NODES = 2500
MAX_DEPTH = 16
MAX_IMAGES = 9
ASSET_ID = re.compile(r'^[a-f0-9]{32}$')
MARKS = {'bold', 'italic', 'underline', 'strike', 'code', 'link'}
CONTAINERS = {
    'doc': {'paragraph', 'heading', 'bulletList', 'orderedList', 'taskList', 'blockquote', 'codeBlock', 'horizontalRule', 'image', 'table', 'mathBlock'},
    'paragraph': {'text', 'hardBreak', 'mathInline'},
    'heading': {'text', 'hardBreak', 'mathInline'},
    'bulletList': {'listItem'}, 'orderedList': {'listItem'}, 'taskList': {'taskItem'},
    'listItem': {'paragraph', 'bulletList', 'orderedList', 'taskList'},
    'taskItem': {'paragraph', 'bulletList', 'orderedList', 'taskList'},
    'blockquote': {'paragraph', 'heading', 'bulletList', 'orderedList'},
    'codeBlock': {'text'}, 'table': {'tableRow'}, 'tableRow': {'tableCell', 'tableHeader'},
    'tableCell': {'paragraph', 'bulletList', 'orderedList'},
    'tableHeader': {'paragraph', 'bulletList', 'orderedList'},
}
LEAVES = {'text', 'hardBreak', 'horizontalRule', 'image', 'mathInline', 'mathBlock'}
# Tiptap's list items, quotes and cells accept the same safe block types as the
# document. This includes formulas inserted while the caret is inside a table.
for _container in ['listItem', 'taskItem', 'blockquote', 'tableCell', 'tableHeader']:
    CONTAINERS[_container] = set(CONTAINERS['doc'])


class InvalidDocument(ValueError): pass


def safe_link(value):
    if not isinstance(value, str) or len(value) > 2048 or any(ord(c) < 32 for c in value):
        raise InvalidDocument('链接格式不正确')
    parsed = urlsplit(value)
    if parsed.scheme.lower() not in {'https', 'http', 'mailto'}:
        raise InvalidDocument('只支持 HTTP(S) 或电子邮件链接')
    if parsed.scheme.lower() != 'mailto' and (not parsed.hostname or parsed.username or parsed.password):
        raise InvalidDocument('链接地址不正确')
    return value


def short_text(value, maximum, label):
    if not isinstance(value, str) or len(value) > maximum or '\x00' in value:
        raise InvalidDocument(label + '格式或长度不正确')
    return value


def normalize_document(document):
    if not isinstance(document, dict) or document.get('type') != 'doc':
        raise InvalidDocument('正文必须为结构化文档')
    count = 0
    text_length = 0
    images = set()

    def walk(node, parent=None, depth=0):
        nonlocal count, text_length
        count += 1
        if count > MAX_NODES or depth > MAX_DEPTH or not isinstance(node, dict):
            raise InvalidDocument('文档结构过大或嵌套过深')
        kind = node.get('type')
        if kind not in CONTAINERS and kind not in LEAVES:
            raise InvalidDocument('不支持的正文元素')
        if parent is not None and kind not in CONTAINERS.get(parent, set()):
            raise InvalidDocument('正文元素层级不正确')
        result = {'type': kind}
        attrs = node.get('attrs') or {}
        if not isinstance(attrs, dict): raise InvalidDocument('元素属性不正确')
        if kind == 'text':
            value = short_text(node.get('text', ''), MAX_TEXT, '正文')
            text_length += len(value)
            if text_length > MAX_TEXT: raise InvalidDocument('正文超过允许长度')
            result['text'] = value
            marks = node.get('marks', [])
            if not isinstance(marks, list) or len(marks) > 6: raise InvalidDocument('文字格式不正确')
            safe_marks, seen = [], set()
            for mark in marks:
                if not isinstance(mark, dict) or mark.get('type') not in MARKS: raise InvalidDocument('不支持的文字格式')
                mark_type = mark['type']
                if mark_type in seen: continue
                seen.add(mark_type)
                item = {'type': mark_type}
                if mark_type == 'link': item['attrs'] = {'href': safe_link((mark.get('attrs') or {}).get('href', ''))}
                safe_marks.append(item)
            if safe_marks: result['marks'] = safe_marks
        elif kind == 'heading':
            level = attrs.get('level', 1)
            if type(level) is not int or level not in [1, 2, 3]: raise InvalidDocument('标题级别不正确')
            result['attrs'] = {'level': level}
        elif kind == 'orderedList':
            start = attrs.get('start', 1)
            if type(start) is not int or not 1 <= start <= 9999: raise InvalidDocument('列表编号不正确')
            result['attrs'] = {'start': start}
        elif kind == 'taskItem':
            if type(attrs.get('checked', False)) is not bool: raise InvalidDocument('任务状态不正确')
            result['attrs'] = {'checked': attrs.get('checked', False)}
        elif kind == 'codeBlock':
            language = short_text(attrs.get('language') or '', 32, '代码语言')
            if language and not re.fullmatch(r'[a-zA-Z0-9_+.#-]+', language): raise InvalidDocument('代码语言不正确')
            result['attrs'] = {'language': language}
        elif kind in {'tableCell', 'tableHeader'}:
            span = {key: attrs.get(key, 1) for key in ['colspan', 'rowspan']}
            if any(type(value) is not int or not 1 <= value <= 12 for value in span.values()): raise InvalidDocument('表格跨度过大')
            result['attrs'] = span
        elif kind == 'image':
            asset = attrs.get('asset_id', '')
            if not isinstance(asset, str) or not ASSET_ID.fullmatch(asset): raise InvalidDocument('图片必须引用本稿件已上传资源')
            images.add(asset)
            if len(images) > MAX_IMAGES: raise InvalidDocument('图片数量超过限制')
            width = attrs.get('width', 720)
            if type(width) not in [int, float] or not 80 <= width <= 1600: raise InvalidDocument('图片宽度不正确')
            result['attrs'] = {'asset_id': asset, 'width': int(width), 'alt': short_text(attrs.get('alt', ''), 300, '图片说明')}
        elif kind in {'mathInline', 'mathBlock'}:
            latex = short_text(attrs.get('latex', ''), 4000, '公式')
            if re.search(r'\\(?:includegraphics|html\w*|href|url|input|include|write\w*|def|newcommand)\b', latex):
                raise InvalidDocument('公式包含不允许的指令')
            result['attrs'] = {'latex': latex}
        if kind in CONTAINERS:
            content = node.get('content', [])
            if not isinstance(content, list): raise InvalidDocument('正文内容不正确')
            if kind == 'table' and len(content) > 30: raise InvalidDocument('表格行数超过限制')
            if kind == 'tableRow' and len(content) > 12: raise InvalidDocument('表格列数超过限制')
            result['content'] = [walk(child, kind, depth + 1) for child in content]
            if kind in {'listItem','taskItem'} and (not result['content'] or result['content'][0]['type']!='paragraph'):
                raise InvalidDocument('列表项目必须以段落开始')
            if kind in {'tableCell','tableHeader'} and not result['content']:
                result['content']=[{'type':'paragraph','content':[]}]
        return result

    clean = walk(copy.deepcopy(document))
    if not clean['content']: clean['content'] = [{'type': 'paragraph', 'content': []}]
    return clean


def asset_ids(document):
    result = set()
    def walk(node):
        if node.get('type') == 'image': result.add(node['attrs']['asset_id'])
        for child in node.get('content', []): walk(child)
    walk(document)
    return result


def plain_text(document):
    parts = []
    def walk(node):
        if node.get('type') == 'text': parts.append(node.get('text', ''))
        elif node.get('type') in {'mathInline', 'mathBlock'}:
            parts.append(re.sub(r'\\[A-Za-z]+|[{}_^]', '', node.get('attrs', {}).get('latex', '')))
        for child in node.get('content', []): walk(child)
        if node.get('type') in {'paragraph', 'heading', 'codeBlock', 'mathBlock'}: parts.append('\n')
    walk(document)
    return ''.join(parts)


def word_count(document): return len(re.sub(r'\s+', '', plain_text(document)))

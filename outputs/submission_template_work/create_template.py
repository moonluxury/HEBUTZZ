from pathlib import Path
from docx import Document
from docx.shared import Mm, Pt, RGBColor
from docx.enum.text import WD_ALIGN_PARAGRAPH
from docx.enum.style import WD_STYLE_TYPE
from docx.oxml import OxmlElement
from docx.oxml.ns import qn


ROOT = Path(__file__).resolve().parents[1]
OUTPUT = ROOT / '河工开物投稿模板.docx'
doc = Document()
section = doc.sections[0]
section.page_width = Mm(210)
section.page_height = Mm(297)
section.top_margin = Mm(21)
section.bottom_margin = Mm(21)
section.left_margin = Mm(24)
section.right_margin = Mm(24)


def font(style, family='微软雅黑', size=10.5, bold=False, color='000000'):
    style.font.name = family
    style.font.size = Pt(size)
    style.font.bold = bold
    style.font.color.rgb = RGBColor.from_string(color)
    rpr = style.element.get_or_add_rPr()
    fonts = rpr.find(qn('w:rFonts'))
    if fonts is None:
        fonts = OxmlElement('w:rFonts')
        rpr.insert(0, fonts)
    for attr in ('ascii', 'hAnsi', 'eastAsia', 'cs'):
        fonts.set(qn(f'w:{attr}'), family)
    for attr in ('asciiTheme', 'hAnsiTheme', 'eastAsiaTheme', 'cstheme'):
        fonts.attrib.pop(qn(f'w:{attr}'), None)
    lang = OxmlElement('w:lang')
    lang.set(qn('w:val'), 'zh-CN')
    lang.set(qn('w:eastAsia'), 'zh-CN')
    rpr.append(lang)


def style(name, family='微软雅黑', size=10.5, bold=False, color='000000',
          before=0, after=5, line=1.25):
    s = doc.styles[name] if name in doc.styles else doc.styles.add_style(name, WD_STYLE_TYPE.PARAGRAPH)
    s.base_style = doc.styles['Normal'] if name != 'Normal' else None
    font(s, family, size, bold, color)
    pf = s.paragraph_format
    pf.space_before = Pt(before)
    pf.space_after = Pt(after)
    pf.line_spacing = line
    pf.widow_control = True
    pf.keep_with_next = False
    pf.first_line_indent = Pt(0)
    ppr = s.element.get_or_add_pPr()
    snap = OxmlElement('w:snapToGrid')
    snap.set(qn('w:val'), '0')
    ppr.append(snap)
    return s


style('Normal')
title = style('Title', size=25, bold=True, after=10)
title.paragraph_format.keep_with_next = True
style('Subtitle', size=10, after=0)
for h in ('Heading 1', 'Heading 2', 'Heading 3'):
    s = style(h, size=11.5, bold=True, before=17, after=8)
    s.paragraph_format.keep_with_next = True
style('填写提示', size=9.5, color='595959', after=0, line=1.4)
style('信息字段', size=10.5, after=7, line=1.25)
mt = style('稿件标题', size=17, bold=True, before=4, after=12, line=1.35)
mt.paragraph_format.alignment = WD_ALIGN_PARAGRAPH.CENTER
mt.paragraph_format.keep_with_next = True
body = style('稿件正文', family='宋体', size=12, after=6, line=1.5)
body.paragraph_format.first_line_indent = Pt(24)
body.next_paragraph_style = body
style('投稿说明', size=10, after=5, line=1.35)
style('稿费说明', size=9, color='595959', before=9, after=0, line=1.4)

# Keep the document entirely editable and use standard Word paragraph styles.
hyphenation = OxmlElement('w:autoHyphenation')
hyphenation.set(qn('w:val'), '0')
doc.settings.element.append(hyphenation)
for root in (doc.styles.element, doc.element):
    for border in list(root.iter(qn('w:pBdr'))):
        border.getparent().remove(border)
default = doc.styles.element.find(qn('w:docDefaults'))
if default is not None:
    for node in default.iter(qn('w:lang')):
        node.set(qn('w:val'), 'zh-CN')
        node.set(qn('w:eastAsia'), 'zh-CN')

doc.add_paragraph('河工开物投稿模板', 'Title')
doc.add_paragraph('请填写作者信息，将方括号内的提示替换为实际内容。正文可续页，选填项目可按需删除。', '填写提示')


def field(label, placeholder, paragraph_style='信息字段'):
    p = doc.add_paragraph(style=paragraph_style)
    p.add_run(label + '  ').bold = True
    r = p.add_run(placeholder)
    r.font.color.rgb = RGBColor.from_string('595959')
    return p


doc.add_paragraph('作者与稿件信息', 'Heading 1')
p = field('作者姓名', '[姓名]')
p.paragraph_format.tab_stops.add_tab_stop(Mm(75))
p.add_run('\t发表署名  ').bold = True
p.add_run('[选填，可填笔名]').font.color.rgb = RGBColor.from_string('595959')
field('联系方式', '[手机、微信或QQ，至少填写一项]')
field('学院或单位', '[选填]')
field('稿件类型', '[校园故事／青春感悟／学习经验／精彩创意／其他，填写一项]')

doc.add_paragraph('稿件正文', 'Heading 1')
doc.add_paragraph('[在此填写稿件标题]', '稿件标题')
doc.add_paragraph('[请在此输入正文，可按内容增加段落，篇幅较长时自动续页。]', '稿件正文')
doc.add_paragraph('[正文已设为宋体小四号、1.5倍行距、首行缩进2字符。粘贴已有稿件时，请选择“只保留文本”。完成后请删除所有方括号提示。]', '稿件正文')
field('配图与来源', '[选填。配图请插入对应位置并注明图注与来源；引用内容请注明出处。]', '投稿说明')

doc.add_paragraph('投稿方式', 'Heading 1')
for label, value in (
    ('投稿邮箱', 'hebutxjkt@163.com'),
    ('邮件主题', '投稿名称—稿件类型'),
    ('附件命名', '投稿名称—作者姓名.docx'),
):
    p = doc.add_paragraph(style='投稿说明')
    p.add_run(label + '  ').bold = True
    p.add_run(value)

doc.add_paragraph('发送前请核对联系方式，并以可编辑的Word文件作为附件；如有配图，可一并附上原图。', '投稿说明')
doc.add_paragraph('稿件一经采用，可获得39—69元稿费。\n同一作者累计中稿超过3次后，此后每次中稿另获30元“优质作者赏金”。', '稿费说明')

props = doc.core_properties
props.title = '河工开物投稿模板'
props.subject = '作者信息、稿件正文及投稿方式'
props.author = '河工开物'
props.last_modified_by = '河工开物'
props.keywords = '投稿模板,河工开物'
props.comments = ''
doc.save(OUTPUT)
print(OUTPUT)

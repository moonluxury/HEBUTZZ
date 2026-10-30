"""Bounded, offline DOCX conversion. Runs in the bundled Python standard library.

No macros, external images, HTML execution, network fetches or archive extraction.
Unsupported Word objects are explicitly reported, never silently treated as text.
"""
import base64
import copy
import hashlib
import json
import os
from pathlib import Path, PurePosixPath
import re
import sys
import uuid
import zipfile
import xml.etree.ElementTree as ET

NS={'w':'http://schemas.openxmlformats.org/wordprocessingml/2006/main','r':'http://schemas.openxmlformats.org/officeDocument/2006/relationships','a':'http://schemas.openxmlformats.org/drawingml/2006/main','wp':'http://schemas.openxmlformats.org/drawingml/2006/wordprocessingDrawing','pic':'http://schemas.openxmlformats.org/drawingml/2006/picture','m':'http://schemas.openxmlformats.org/officeDocument/2006/math'}
for key,value in NS.items(): ET.register_namespace(key,value)
REL='http://schemas.openxmlformats.org/package/2006/relationships'
CT='http://schemas.openxmlformats.org/package/2006/content-types'
def q(name): prefix,local=name.split(':');return '{'+NS[prefix]+'}'+local
def el(name,attrs=None,text=None):
    node=ET.Element(q(name),{q(k) if ':' in k else k:str(v) for k,v in (attrs or {}).items()})
    if text is not None: node.text=text
    return node
def xml(data):
    if len(data)>8*1024*1024 or re.search(br'<!\s*(DOCTYPE|ENTITY)',data,re.I): raise ValueError('Word XML 含不支持的实体或超过大小限制')
    return ET.fromstring(data)
def safe_url(url):
    from urllib.parse import urlsplit
    parsed=urlsplit(url)
    return parsed.scheme.lower() in {'https','http','mailto'} and not parsed.username and not parsed.password and not any(ord(c)<32 for c in url)
def text_node(text,marks=None): return {'type':'text','text':text,**({'marks':marks} if marks else {})}
def para(text=''):return {'type':'paragraph','content':[text_node(text)] if text else []}

def image_size(raw):
    if raw.startswith(b'\x89PNG\r\n\x1a\n') and len(raw)>=24:
        return int.from_bytes(raw[16:20],'big'),int.from_bytes(raw[20:24],'big')
    if raw.startswith(b'\xff\xd8'):
        offset=2
        while offset+8<len(raw):
            if raw[offset]!=255:break
            while offset<len(raw) and raw[offset]==255:offset+=1
            marker=raw[offset];offset+=1
            if marker in {217,218}:break
            size=int.from_bytes(raw[offset:offset+2],'big')
            if size<2 or offset+size>len(raw):break
            if marker in {192,193,194,195,197,198,199,201,202,203,205,206,207}:
                return int.from_bytes(raw[offset+5:offset+7],'big'),int.from_bytes(raw[offset+3:offset+5],'big')
            offset+=size
    raise ValueError('无法读取图片尺寸，请重新插入图片')


def read_docx(path,work):
    if path.suffix.lower()!='.docx': raise ValueError('第一阶段只支持 .docx，不支持旧版 .doc')
    if path.stat().st_size>64*1024*1024: raise ValueError('Word 文档不能超过 64 MB')
    report=[];assets=[]
    with zipfile.ZipFile(path) as archive:
        entries=archive.infolist()
        if len(entries)>1500 or sum(x.file_size for x in entries)>64*1024*1024: raise ValueError('Word 压缩内容超过允许大小')
        for item in entries:
            name=PurePosixPath(item.filename)
            if name.is_absolute() or '..' in name.parts or '\\' in item.filename or item.file_size>8*1024*1024 or item.file_size>max(1,item.compress_size)*300: raise ValueError('Word 压缩包结构不安全')
            if 'vbaproject' in item.filename.lower(): raise ValueError('不支持包含宏的文档')
        if len({item.filename for item in entries})!=len(entries): raise ValueError('Word 压缩包包含重复文件名')
        if 'word/document.xml' not in archive.namelist(): raise ValueError('文件不是有效的 Word 文档')
        root=xml(archive.read('word/document.xml'))
        rels={}
        if 'word/_rels/document.xml.rels' in archive.namelist():
            for entry in xml(archive.read('word/_rels/document.xml.rels')): rels[entry.get('Id')]=entry.attrib
        media={}
        def image_for(rid):
            rel=rels.get(rid,{})
            target=rel.get('Target','')
            if rel.get('TargetMode')=='External' or not target.startswith('media/') or '..' in PurePosixPath(target).parts:
                report.append('外部或不安全的图片引用未导入。');return None
            name='word/'+target
            if name in media:return media[name]
            if name not in archive.namelist():report.append('Word 中有缺失的图片。');return None
            raw=archive.read(name)
            extension='.png' if raw.startswith(b'\x89PNG\r\n\x1a\n') else '.jpg' if raw.startswith(b'\xff\xd8') else '.webp' if raw[:4]==b'RIFF' and raw[8:12]==b'WEBP' else ''
            if not extension:report.append('不支持的 Word 图片格式已标记待补充。');return None
            asset_id=uuid.uuid4().hex;file=work/(asset_id+extension);file.write_bytes(raw)
            assets.append({'id':asset_id,'path':str(file)});media[name]=asset_id
            return asset_id
        def math_source(node):
            if node is None:return ''
            kind=node.tag.split('}')[-1]
            children=list(node)
            if kind=='t':return node.text or ''
            if kind=='f':return '\\frac{'+math_source(node.find(q('m:num')))+'}{'+math_source(node.find(q('m:den')))+'}'
            if kind in {'sSup','sSub','sSubSup'}:
                base=math_source(node.find(q('m:e')))
                sub=node.find(q('m:sub'));sup=node.find(q('m:sup'))
                return base+('_{'+math_source(sub)+'}' if sub is not None else '')+('^{'+math_source(sup)+'}' if sup is not None else '')
            if kind=='rad':return '\\sqrt{'+math_source(node.find(q('m:e')))+'}'
            if kind.endswith('Pr'):return ''
            return ''.join(math_source(c) for c in children)
        numbering={};abstract={}
        styles={}
        if 'word/styles.xml' in archive.namelist():
            for style in xml(archive.read('word/styles.xml')).findall(q('w:style')):styles[style.get(q('w:styleId'))]=style
        def style_properties(style_id,depth=0):
            if depth>12 or style_id not in styles:return None
            style=styles[style_id];properties=style.find(q('w:pPr'))
            if properties is not None and properties.find(q('w:numPr')) is not None:return properties
            base=style.find(q('w:basedOn'))
            return style_properties(base.get(q('w:val')),depth+1) if base is not None else properties
        if 'word/numbering.xml' in archive.namelist():
            n=xml(archive.read('word/numbering.xml'))
            for a in n.findall(q('w:abstractNum')):
                for level in a.findall(q('w:lvl')):
                    fmt=level.find(q('w:numFmt'));abstract[(a.get(q('w:abstractNumId')),level.get(q('w:ilvl'),'0'))]='bulletList' if fmt is not None and fmt.get(q('w:val'))=='bullet' else 'orderedList'
            for num in n.findall(q('w:num')):
                a=num.find(q('w:abstractNumId'))
                if a is not None:numbering[num.get(q('w:numId'))]=a.get(q('w:val'))
        def paragraph(node):
            props=node.find(q('w:pPr'));kind='paragraph';attrs={}
            inherited=None
            if props is not None:
                style=props.find(q('w:pStyle'))
                if style is not None:
                    name=style.get(q('w:val'),'')
                    inherited=style_properties(name)
                    named=styles.get(name)
                    display_name=named.find(q('w:name')) if named is not None else None
                    heading_name=display_name.get(q('w:val'),name) if display_name is not None else name
                    match=re.search(r'(?:heading|标题)\s*([123])',heading_name,re.I)
                    if match:kind='heading';attrs={'level':int(match.group(1))}
                    elif name.lower()=='code':kind='codeBlock';attrs={'language':''}
                    elif name=='HegongMath':kind='mathBlock'
            content=[];images=[]
            def inline(item,link=None):
                local=item.tag.split('}')[-1]
                if local in {'oMath','oMathPara'}:
                    latex=math_source(item)
                    if not latex:latex='\\text{Word公式待补充}'
                    content.append({'type':'mathInline','attrs':{'latex':latex}})
                    report.append('Word 公式已转换为可编辑数学源；复杂矩阵、对齐和样式需检查。')
                    return
                if local=='hyperlink':
                    rel=rels.get(item.get(q('r:id')),{})
                    url=rel.get('Target','')
                    for child in item:inline(child,url if safe_url(url) else None)
                    if url and not safe_url(url):report.append('危险链接已移除。')
                    return
                if local=='r':
                    marks=[];rp=item.find(q('w:rPr'))
                    inline_style=rp.find(q('w:rStyle')) if rp is not None else None
                    if inline_style is not None and inline_style.get(q('w:val'))=='HegongInlineMath':
                        content.append({'type':'mathInline','attrs':{'latex':''.join(t.text or '' for t in item.iter(q('w:t')))}})
                        return
                    for source,target in [('b','bold'),('i','italic'),('u','underline'),('strike','strike')]:
                        value=rp.find(q('w:'+source)) if rp is not None else None
                        if value is not None and value.get(q('w:val'),'1') not in {'0','false','none'}:marks.append({'type':target})
                    if link:marks.append({'type':'link','attrs':{'href':link}})
                    for child in item:
                        if child.tag==q('w:t') and child.text:content.append(text_node(child.text,marks))
                        elif child.tag==q('w:br'):content.append({'type':'hardBreak'})
                        elif child.tag==q('w:tab'):content.append(text_node('\t',marks))
                        for blip in child.iter(q('a:blip')):
                            asset_id=image_for(blip.get(q('r:embed')))
                            if asset_id:images.append({'type':'image','attrs':{'asset_id':asset_id,'width':720,'alt':''}})
                            else:content.append(text_node('【图片未能转换，请手动补充】'))
                    return
                for child in item:inline(child,link)
            for child in node:
                if child.tag!=q('w:pPr'):inline(child)
            value={'type':kind,'content':content}
            if kind=='mathBlock': value={'type':'mathBlock','attrs':{'latex':''.join(c.get('text',c.get('attrs',{}).get('latex','')) for c in content)}}
            if attrs:value['attrs']=attrs
            list_info=None
            if props is not None or inherited is not None:
                num=props.find(q('w:numPr')) if props is not None else None
                if num is None and inherited is not None:num=inherited.find(q('w:numPr'))
                if num is not None:
                    nid=num.find(q('w:numId'));level=num.find(q('w:ilvl'));depth=level.get(q('w:val'),'0') if level is not None else '0'
                    if nid is not None:list_info=(abstract.get((numbering.get(nid.get(q('w:val'))),depth),'bulletList'),min(8,int(depth)))
            return value,images,list_info
        blocks=[];list_stack=[]
        for item in root.find(q('w:body')):
            if item.tag==q('w:p'):
                value,images,li=paragraph(item)
                if li:
                    kind,depth=li
                    while list_stack and (len(list_stack)>depth+1 or list_stack[-1]['type']!=kind):list_stack.pop()
                    while len(list_stack)<depth+1:
                        container={'type':kind,'content':[]}
                        if kind=='orderedList':container['attrs']={'start':1}
                        if list_stack and list_stack[-1]['content']:list_stack[-1]['content'][-1]['content'].append(container)
                        else:blocks.append(container)
                        list_stack.append(container)
                    list_stack[-1]['content'].append({'type':'listItem','content':[{'type':'paragraph','content':value['content']}]})
                else:list_stack=[];blocks.append(value)
                blocks.extend(images)
            elif item.tag==q('w:tbl'):
                list_stack=[];table={'type':'table','content':[]}
                if len(item.findall(q('w:tr')))>30:raise ValueError('Word 表格超过 30 行，请拆分后导入')
                for row in item.findall(q('w:tr'))[:30]:
                    if len(row.findall(q('w:tc')))>12:raise ValueError('Word 表格超过 12 列，请拆分后导入')
                    cells=[]
                    for cell in row.findall(q('w:tc'))[:12]:
                        content=[]
                        for p in cell.findall(q('w:p')):
                            value,images,_=paragraph(p)
                            content.append(value);content.extend(images)
                        if cell.find(q('w:tbl')) is not None:
                            content.append(para('【嵌套表格待补充】'))
                            report.append('嵌套表格未能完整转换，已在对应单元格标记待补充。')
                        if cell.find('.//'+q('w:gridSpan')) is not None or cell.find('.//'+q('w:vMerge')) is not None:
                            report.append('合并单元格已转为普通单元格，文字和图片保留，请检查表格布局。')
                        cells.append({'type':'tableCell','attrs':{'colspan':1,'rowspan':1},'content':content or [para()]})
                    table['content'].append({'type':'tableRow','content':cells})
                blocks.append(table)
        for n in ['header','footer','footnotes','endnotes']:
            if any(name.startswith('word/'+n) for name in archive.namelist()):report.append('页眉页脚、脚注/尾注不参与正文转换，请检查原文。');break
        if any(item.tag in {q('w:object'),q('w:pict')} for item in root.iter()):report.append('文档含旧式绘图或嵌入对象，请在正文中手动补充。')
        document={'type':'doc','content':blocks or [para()]}
        # Our export retains normalized source to preserve editable formulas exactly.
        if 'customXml/hegong.json' in archive.namelist():
            saved=json.loads(archive.read('customXml/hegong.json'))
            if saved.get('version')==1 and saved.get('document_hash')==hashlib.sha256(archive.read('word/document.xml')).hexdigest() and isinstance(saved.get('document'),dict):
                candidate=saved['document'];mapping={}
                for old,name in saved.get('images',{}).items():
                    matches=[rid for rid,rel in rels.items() if 'word/'+rel.get('Target','')==name and rel.get('TargetMode')!='External']
                    if matches:mapping[old]=image_for(matches[0])
                def remap(node,depth=0):
                    if depth>16 or not isinstance(node,dict):raise ValueError('文档结构不正确')
                    if node.get('type')=='image':
                        old=node.get('attrs',{}).get('asset_id');new=mapping.get(old)
                        if not new:raise ValueError('Word 内嵌图片引用不完整')
                        node['attrs']['asset_id']=new
                    for child in node.get('content',[]):remap(child,depth+1)
                remap(candidate);document=candidate
            else: report.append('Word 正文已修改，已按实际 Word 内容重新导入，不使用旧的附加快照。')
        if len(json.dumps(document,ensure_ascii=False))>1000000:raise ValueError('正文超过允许大小')
        return {'ok':True,'document':document,'assets':assets,'report':list(dict.fromkeys(report))}


def write_docx(path,document,title,assets):
    report=[];relationships=[];image_files={};body=el('w:body');image_number=0;list_sequences=[]
    def relation(kind,target,external=False):
        rid='rId'+str(len(relationships)+1);relationships.append({'Id':rid,'Type':'http://schemas.openxmlformats.org/officeDocument/2006/relationships/'+kind,'Target':target,**({'TargetMode':'External'} if external else {})});return rid
    def run(text,marks=None):
        r=el('w:r');pr=el('w:rPr')
        for mark in marks or []:
            name={'bold':'b','italic':'i','underline':'u','strike':'strike','code':'rStyle'}.get(mark['type'])
            if name:pr.append(el('w:'+name,{'w:val':'single' if name=='u' else 'Code' if name=='rStyle' else '1'}))
        if len(pr):r.append(pr)
        t=el('w:t',text=text);t.set('{http://www.w3.org/XML/1998/namespace}space','preserve');r.append(t);return r
    def inline(p,node):
        if node['type']=='text':
            marks=node.get('marks',[]);link=next((m.get('attrs',{}).get('href') for m in marks if m['type']=='link'),None)
            if link and safe_url(link):h=el('w:hyperlink',{'r:id':relation('hyperlink',link,True)});h.append(run(node['text'],marks));p.append(h)
            else:p.append(run(node['text'],marks))
        elif node['type']=='hardBreak':r=el('w:r');r.append(el('w:br'));p.append(r)
        elif node['type'].startswith('math'):
            # LaTeX is retained as editable text plus exact structured metadata.
            math_run=run(node.get('attrs',{}).get('latex',''))
            props=el('w:rPr');props.append(el('w:rStyle',{'w:val':'HegongInlineMath'}));math_run.insert(0,props);p.append(math_run)
            report.append('公式在 Word 中保留为可编辑 LaTeX 文本；重新导入本应用可恢复数学节点。')
    def block(node,parent,depth=0,list_kind=None):
        nonlocal image_number
        if depth>16:raise ValueError('文档嵌套过深')
        kind=node['type']
        if kind in {'paragraph','heading','codeBlock','mathBlock'}:
            p=el('w:p');pr=el('w:pPr')
            if kind=='heading':pr.append(el('w:pStyle',{'w:val':'Heading'+str(node.get('attrs',{}).get('level',1))}))
            if kind=='codeBlock':pr.append(el('w:pStyle',{'w:val':'Code'}))
            if kind=='mathBlock':pr.append(el('w:pStyle',{'w:val':'HegongMath'}))
            if list_kind:
                np=el('w:numPr');np.append(el('w:ilvl',{'w:val':min(max(0,depth-1),8)}));np.append(el('w:numId',{'w:val':list_kind}));pr.append(np)
            if len(pr):p.append(pr)
            if kind=='mathBlock':inline(p,node)
            else:
                for child in node.get('content',[]):inline(p,child)
            parent.append(p)
        elif kind in {'bulletList','orderedList','taskList'}:
            list_id=len(list_sequences)+1
            list_sequences.append((1 if kind in {'bulletList','taskList'} else 2,int(node.get('attrs',{}).get('start',1))))
            for item in node.get('content',[]):
                for child in item.get('content',[]):block(child,parent,depth+1,list_id)
        elif kind=='blockquote':
            for child in node.get('content',[]):block(child,parent,depth+1)
        elif kind=='horizontalRule':parent.append(el('w:p'))
        elif kind=='table':
            table=el('w:tbl');props=el('w:tblPr');borders=el('w:tblBorders')
            for side in ['top','left','bottom','right','insideH','insideV']:borders.append(el('w:'+side,{'w:val':'single','w:sz':4,'w:color':'D8DFEA'}))
            props.append(borders);table.append(props)
            columns=max((sum(int(cell.get('attrs',{}).get('colspan',1)) for cell in row.get('content',[])) for row in node.get('content',[])),default=1)
            grid=el('w:tblGrid')
            for _ in range(columns):grid.append(el('w:gridCol',{'w:w':9000//max(1,columns)}))
            table.append(grid)
            for row in node.get('content',[]):
                tr=el('w:tr')
                for cell in row.get('content',[]):
                    tc=el('w:tc')
                    cell_properties=el('w:tcPr');span=int(cell.get('attrs',{}).get('colspan',1))
                    cell_properties.append(el('w:tcW',{'w:w':9000*span//max(1,columns),'w:type':'dxa'}))
                    if span>1:cell_properties.append(el('w:gridSpan',{'w:val':span}))
                    tc.append(cell_properties)
                    for child in cell.get('content',[]):block(child,tc,depth+1)
                    if not len(tc):tc.append(el('w:p'))
                    tr.append(tc)
                table.append(tr)
            parent.append(table)
        elif kind=='image':
            asset_id=node['attrs']['asset_id'];source=Path(assets[asset_id]);raw=source.read_bytes()
            if len(raw)>8*1024*1024:raise ValueError('图片超过导出限制')
            ext='.png' if raw.startswith(b'\x89PNG') else '.jpg' if raw.startswith(b'\xff\xd8') else None
            if not ext:raise ValueError('导出前需要将图片转换为 PNG 或 JPG')
            image_number+=1;name='media/'+asset_id+ext;image_files[asset_id]=('word/'+name,raw)
            rid=relation('image',name);width=min(600,max(80,int(node['attrs'].get('width',600))));cx=width*9525
            w,h=image_size(raw);cy=int(cx*h/max(1,w))
            p=el('w:p');r=el('w:r');drawing=el('w:drawing');container=el('wp:inline',{'distT':0,'distB':0,'distL':0,'distR':0});container.append(el('wp:extent',{'cx':cx,'cy':cy}));container.append(el('wp:docPr',{'id':image_number,'name':'Image '+str(image_number),'descr':node['attrs'].get('alt','')}));graphic=el('a:graphic');gd=el('a:graphicData',{'uri':NS['pic']});pic=el('pic:pic');nv=el('pic:nvPicPr');nv.append(el('pic:cNvPr',{'id':0,'name':asset_id+ext}));nv.append(el('pic:cNvPicPr'));pic.append(nv);fill=el('pic:blipFill');fill.append(el('a:blip',{'r:embed':rid}));stretch=el('a:stretch');stretch.append(el('a:fillRect'));fill.append(stretch);pic.append(fill);shape=el('pic:spPr');transform=el('a:xfrm');transform.append(el('a:off',{'x':0,'y':0}));transform.append(el('a:ext',{'cx':cx,'cy':cy}));shape.append(transform);geometry=el('a:prstGeom',{'prst':'rect'});geometry.append(el('a:avLst'));shape.append(geometry);pic.append(shape);gd.append(pic);graphic.append(gd);container.append(graphic);drawing.append(container);r.append(drawing);p.append(r);parent.append(p)
    if title:block({'type':'heading','attrs':{'level':1},'content':[text_node(title)]},body)
    for node in document.get('content',[]):block(node,body)
    section=el('w:sectPr');section.append(el('w:pgSz',{'w:w':11906,'w:h':16838}));section.append(el('w:pgMar',{'w:top':1134,'w:right':1134,'w:bottom':1134,'w:left':1134}));body.append(section)
    root=el('w:document');root.append(body)
    styles=el('w:styles')
    for name,size in [('Normal',22),('Heading1',36),('Heading2',30),('Heading3',26),('Code',20),('HegongMath',22)]:
        st=el('w:style',{'w:type':'paragraph','w:styleId':name});st.append(el('w:name',{'w:val':name}));pr=el('w:rPr');pr.append(el('w:rFonts',{'w:ascii':'Consolas' if name=='Code' else 'Arial','w:eastAsia':'Microsoft YaHei'}));pr.append(el('w:sz',{'w:val':size}));st.append(pr);styles.append(st)
        if name.startswith('Heading'):
            pp=el('w:pPr');pp.append(el('w:outlineLvl',{'w:val':int(name[-1])-1}));st.insert(1,pp);pr.append(el('w:b'))
    inline_style=el('w:style',{'w:type':'character','w:styleId':'HegongInlineMath'});inline_style.append(el('w:name',{'w:val':'HegongInlineMath'}));styles.append(inline_style)
    numbering=el('w:numbering')
    for index,fmt in [(1,'bullet'),(2,'decimal')]:
        abstract=el('w:abstractNum',{'w:abstractNumId':index})
        for depth in range(9):
            level=el('w:lvl',{'w:ilvl':depth});level.append(el('w:start',{'w:val':1}));level.append(el('w:numFmt',{'w:val':fmt}));level.append(el('w:lvlText',{'w:val':'•' if fmt=='bullet' else '%'+str(depth+1)+'.'}));abstract.append(level)
        numbering.append(abstract)
    # OOXML requires all abstract definitions before numbering instances.
    for index,(abstract_id,start) in enumerate(list_sequences,1):
        num=el('w:num',{'w:numId':index});num.append(el('w:abstractNumId',{'w:val':abstract_id}))
        for depth in range(9):
            override=el('w:lvlOverride',{'w:ilvl':depth});override.append(el('w:startOverride',{'w:val':start}));num.append(override)
        numbering.append(num)
    relation('styles','styles.xml');relation('numbering','numbering.xml')
    relations=ET.Element('{'+REL+'}Relationships')
    for item in relationships:ET.SubElement(relations,'{'+REL+'}Relationship',item)
    types=ET.Element('{'+CT+'}Types')
    for ext,mime in [('rels','application/vnd.openxmlformats-package.relationships+xml'),('xml','application/xml'),('json','application/json'),('png','image/png'),('jpg','image/jpeg')]:ET.SubElement(types,'{'+CT+'}Default',{'Extension':ext,'ContentType':mime})
    for name,mime in [('document','document.main'),('styles','styles'),('numbering','numbering')]:ET.SubElement(types,'{'+CT+'}Override',{'PartName':'/word/'+name+'.xml','ContentType':'application/vnd.openxmlformats-officedocument.wordprocessingml.'+mime+'+xml'})
    relroot=ET.Element('{'+REL+'}Relationships');ET.SubElement(relroot,'{'+REL+'}Relationship',{'Id':'rId1','Type':'http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument','Target':'word/document.xml'})
    temporary=path.with_name(path.name+'.tmp')
    try:
        with zipfile.ZipFile(temporary,'w',zipfile.ZIP_DEFLATED) as archive:
            for name,node in [('[Content_Types].xml',types),('_rels/.rels',relroot),('word/document.xml',root),('word/styles.xml',styles),('word/numbering.xml',numbering),('word/_rels/document.xml.rels',relations)]:archive.writestr(name,ET.tostring(node,encoding='utf-8',xml_declaration=True))
            for name,raw in image_files.values():archive.writestr(name,raw)
            archive.writestr('customXml/hegong.json',json.dumps({'version':1,'document_hash':hashlib.sha256(ET.tostring(root,encoding='utf-8',xml_declaration=True)).hexdigest(),'document':document,'images':{key:value[0] for key,value in image_files.items()}},ensure_ascii=False))
        with zipfile.ZipFile(temporary) as archive:
            if archive.testzip():raise ValueError('Word 文件校验失败')
        os.replace(temporary,path)
    finally:
        if temporary.exists():temporary.unlink()
    return {'ok':True,'report':list(dict.fromkeys(report))}


def main(request_path):
    request=json.loads(Path(request_path).read_text(encoding='utf-8-sig'));work=Path(request['work']);work.mkdir(parents=True,exist_ok=True)
    try:
        if request['action']=='import':result=read_docx(Path(request['path']),work)
        elif request['action']=='export':result=write_docx(Path(request['path']),request['document'],request.get('title',''),request.get('assets',{}))
        else:raise ValueError('不支持的 Word 操作')
    except Exception as error:result={'ok':False,'message':'Word 转换失败：'+str(error)[:180]}
    (work/'result.json').write_text(json.dumps(result,ensure_ascii=False),encoding='utf-8')

if __name__=='__main__':main(sys.argv[1])

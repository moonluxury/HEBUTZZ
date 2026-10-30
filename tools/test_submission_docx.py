"""Independent OOXML-reader checks for the offline DOCX conversion worker."""
from pathlib import Path
import importlib.util
import json
import tempfile
import unittest
import zipfile

from docx import Document
from docx.oxml import OxmlElement
from docx.shared import Inches
from PIL import Image

ROOT=Path(__file__).resolve().parents[1]
spec=importlib.util.spec_from_file_location('codec',ROOT/'scripts/submission_docx.py')
codec=importlib.util.module_from_spec(spec);spec.loader.exec_module(codec)

def walk(node):
    yield node
    for child in node.get('content',[]):yield from walk(child)


class WordConversion(unittest.TestCase):
    def setUp(self):
        self.folder=Path(tempfile.mkdtemp(prefix='docx-check-',dir=ROOT/'.godot_appdata'))
        self.image=self.folder/'sample.png';Image.new('RGB',(80,60),'#092c87').save(self.image)

    def test_independent_reader_opens_export_with_all_objects(self):
        doc={'type':'doc','content':[{'type':'heading','attrs':{'level':1},'content':[codec.text_node('中文标题')]}, {'type':'paragraph','content':[codec.text_node('粗体文本',[{'type':'bold'}]),codec.text_node('安全链接',[{'type':'link','attrs':{'href':'https://example.org/lesson'}}])]}, {'type':'orderedList','attrs':{'start':1},'content':[{'type':'listItem','content':[codec.para('第一项'),{'type':'bulletList','content':[{'type':'listItem','content':[codec.para('嵌套项目')]}]}]}]}, {'type':'image','attrs':{'asset_id':'a'*32,'width':400,'alt':'图片说明'}}, {'type':'table','content':[{'type':'tableRow','content':[{'type':'tableCell','content':[codec.para('中文表格')]},{'type':'tableCell','content':[codec.para('数值')]}]}]}, {'type':'mathBlock','attrs':{'latex':r'\frac{a}{b}+x^2'}}]}
        path=self.folder/'complete.docx';result=codec.write_docx(path,doc,'文章标题',{'a'*32:str(self.image)})
        self.assertTrue(result['report'])
        external=Document(path)
        self.assertIn('中文标题','\n'.join(p.text for p in external.paragraphs))
        self.assertEqual(len(external.inline_shapes),1)
        self.assertEqual(external.tables[0].cell(0,0).text,'中文表格')
        imported=codec.read_docx(path,self.folder)
        self.assertIn('粗体文本',json.dumps(imported['document'],ensure_ascii=False))
        self.assertEqual(sum(n['type']=='mathBlock' for n in walk(imported['document'])),1)
        self.assertEqual(len(imported['assets']),1)

    def test_import_external_word_lists_tables_and_math(self):
        doc=Document();doc.add_heading('外部 Word 标题',1)
        p=doc.add_paragraph();p.add_run('加粗中文').bold=True;p.add_run('斜体').italic=True
        doc.add_paragraph('列表项目',style='List Bullet')
        doc.add_table(rows=1,cols=2).cell(0,0).text='单元格'
        doc.add_picture(str(self.image),width=Inches(2))
        p=doc.add_paragraph();math=OxmlElement('m:oMath');frac=OxmlElement('m:f')
        for name,value in [('m:num','a'),('m:den','b')]:
            branch=OxmlElement(name);run=OxmlElement('m:r');text=OxmlElement('m:t');text.text=value;run.append(text);branch.append(run);frac.append(branch)
        math.append(frac);p._p.append(math)
        path=self.folder/'external.docx';doc.save(path)
        result=codec.read_docx(path,self.folder);nodes=list(walk(result['document']))
        self.assertTrue(any(n['type']=='heading' for n in nodes))
        self.assertTrue(any(n['type']=='bulletList' for n in nodes))
        self.assertTrue(any(n['type']=='table' for n in nodes))
        self.assertTrue(any(n['type']=='image' for n in nodes))
        self.assertTrue(any(n['type']=='mathInline' and n['attrs']['latex']==r'\frac{a}{b}' for n in nodes))

    def test_word_edits_override_old_embedded_snapshot(self):
        path=self.folder/'changed.docx';codec.write_docx(path,{'type':'doc','content':[codec.para('原始正文')]},'',{})
        with zipfile.ZipFile(path) as archive:parts={n:archive.read(n) for n in archive.namelist()}
        parts['word/document.xml']=parts['word/document.xml'].replace('原始正文'.encode(),'Word 修改后的正文'.encode())
        with zipfile.ZipFile(path,'w') as archive:
            for name,data in parts.items():archive.writestr(name,data)
        result=codec.read_docx(path,self.folder)
        self.assertIn('Word 修改后的正文',json.dumps(result['document'],ensure_ascii=False))
        self.assertNotIn('原始正文',json.dumps(result['document'],ensure_ascii=False))

    def test_images_inside_word_table_are_not_lost(self):
        doc=Document();cell=doc.add_table(rows=1,cols=1).cell(0,0)
        cell.paragraphs[0].add_run('表格里的图片').add_picture(str(self.image),width=Inches(1))
        path=self.folder/'table-picture.docx';doc.save(path)
        imported=codec.read_docx(path,self.folder)
        table=next(n for n in walk(imported['document']) if n['type']=='table')
        self.assertEqual(sum(n['type']=='image' for n in walk(table)),1)
        self.assertEqual(len(imported['assets']),1)

    def test_oversized_word_table_is_not_silently_truncated(self):
        doc=Document();table=doc.add_table(rows=31,cols=1);table.cell(30,0).text='必须保留的最后一行'
        path=self.folder/'large-table.docx';doc.save(path)
        with self.assertRaisesRegex(ValueError,'30 行'):codec.read_docx(path,self.folder)

    def test_jpeg_export_preserves_aspect_ratio(self):
        picture=self.folder/'portrait.jpg';Image.new('RGB',(100,200),'blue').save(picture)
        output=self.folder/'portrait.docx'
        codec.write_docx(output,{'type':'doc','content':[{'type':'image','attrs':{'asset_id':'a'*32,'width':400}}]},'',{'a'*32:str(picture)})
        external=Document(output)
        self.assertAlmostEqual(external.inline_shapes[0].height/external.inline_shapes[0].width,2)

    def test_malicious_archive_and_unsupported_type_leave_input_intact(self):
        for name,parts in [('unsafe.docx',{'../outside.txt':b'bad','word/document.xml':b'<x/>'}),('entity.docx',{'word/document.xml':b'<!DOCTYPE x [<!ENTITY bad "bad">]><x>&bad;</x>'})]:
            path=self.folder/name
            with zipfile.ZipFile(path,'w') as archive:
                for part,value in parts.items():archive.writestr(part,value)
            before=path.read_bytes()
            with self.assertRaises(ValueError):codec.read_docx(path,self.folder)
            self.assertEqual(before,path.read_bytes())
        path=self.folder/'legacy.doc';path.write_bytes(b'not a docx')
        with self.assertRaises(ValueError):codec.read_docx(path,self.folder)


if __name__=='__main__':unittest.main()

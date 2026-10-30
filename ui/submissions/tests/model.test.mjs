import test from 'node:test';
import assert from 'node:assert/strict';
import {normalizeDocument,countText,headings,imageIds,safeLink,canDeleteDraft} from '../src/model.js';

test('persistence removes transient image URLs while preserving editable source',()=>{
  const source={type:'doc',content:[{type:'image',attrs:{asset_id:'abc',src:'blob:temporary',width:400.2,alt:'图'}},{type:'mathBlock',attrs:{latex:'\\frac{a}{b}'}}]};
  const saved=normalizeDocument(source);
  assert.equal(saved.content[0].attrs.src,undefined);
  assert.equal(saved.content[0].attrs.asset_id,'abc');
  assert.equal(saved.content[0].attrs.width,400);
  assert.equal(saved.content[1].attrs.latex,'\\frac{a}{b}');
  assert.equal(source.content[0].attrs.src,'blob:temporary');
});
test('outline derives nested headings and image references are unique',()=>{
  const doc={type:'doc',content:[{type:'heading',attrs:{level:2},content:[{type:'text',text:'中文章节'}]},{type:'blockquote',content:[{type:'heading',attrs:{level:3},content:[{type:'text',text:'子章节'}]}]},...['a','b','a'].map(id=>({type:'image',attrs:{asset_id:id}}))]};
  assert.deepEqual(headings(doc).map(h=>[h.title,h.level]),[['中文章节',2],['子章节',3]]);
  assert.deepEqual(imageIds(doc),['a','b']);
});
test('character count excludes formula commands and whitespace',()=>{
  assert.equal(countText({type:'doc',content:[{type:'paragraph',content:[{type:'text',text:'中文 😀 '}]},{type:'mathBlock',attrs:{latex:'\\frac{a}{b}'}}]}),5);
});
test('untrusted links cannot open script, local files or credential-bearing URLs',()=>{
  for(const url of ['javascript:alert(1)','file:///C:/secret','data:text/html,test','https://user:secret@example.com'])assert.equal(safeLink(url),null);
  assert.equal(safeLink('https://example.org/lesson'),'https://example.org/lesson');
});
test('delete is offered only for unpublished editable or rejected drafts',()=>{
  for(const state of ['draft','returned','rejected'])assert.equal(canDeleteDraft({state,article_id:null}),true);
  for(const state of ['pending','approved','published','archived'])assert.equal(canDeleteDraft({state}),false);
  assert.equal(canDeleteDraft({state:'draft',article_id:'existing-public-article'}),false);
});

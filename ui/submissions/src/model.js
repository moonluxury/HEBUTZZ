import {formatBeijingDateTime} from './date_time.js';
export const emptyDocument=()=>({type:'doc',content:[{type:'paragraph',content:[]}]});
export const states={draft:'草稿',pending:'待审核',approved:'待发表',returned:'被退回',rejected:'不予采用',published:'已发表',archived:'已下架'};
export const canDeleteDraft=item=>['draft','returned','rejected'].includes(item?.state)&&!item?.article_id;
export function normalizeDocument(node){
  const out={type:node.type};
  if(node.text!==undefined)out.text=node.text;
  if(node.marks)out.marks=node.marks.map(m=>({type:m.type,...(m.type==='link'?{attrs:{href:m.attrs.href}}:{})}));
  if(node.attrs){out.attrs={...node.attrs};if(node.type==='image'){delete out.attrs.src;delete out.attrs.title;out.attrs.width=Math.round(Number(out.attrs.width)||720);}delete out.attrs.id;}
  if(node.content)out.content=node.content.map(normalizeDocument);
  return out;
}
export function textOf(node){return (node.type==='text'?node.text||'':node.type?.startsWith('math')?(node.attrs?.latex||'').replace(/\\[A-Za-z]+|[{}_^]/g,''):'')+(node.content||[]).map(textOf).join('');}
export function countText(doc){return [...textOf(doc).replace(/\s/g,'')].length;}
export function headings(doc){const result=[];const walk=(n)=>{if(n.type==='heading')result.push({title:textOf(n),level:n.attrs?.level||1,index:result.length});(n.content||[]).forEach(walk);};walk(doc);return result;}
export function imageIds(doc){const ids=new Set();const walk=n=>{if(n.type==='image'&&n.attrs?.asset_id)ids.add(n.attrs.asset_id);(n.content||[]).forEach(walk);};walk(doc);return [...ids];}
export function safeLink(value){try{const u=new URL(value);return ['https:','http:','mailto:'].includes(u.protocol)&&!u.username&&!u.password?u.href:null;}catch{return null;}}
export function fmtDate(value){return value?formatBeijingDateTime(value):'尚未同步';}

import test from 'node:test';
import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import {formatBeijingDateTime} from '../src/date_time.js';
import {fmtDate} from '../src/model.js';

const cases=JSON.parse(readFileSync(new URL('../../../tools/fixtures/time_display_cases.json',import.meta.url),'utf8'));
for(const example of cases){
  test(`Readable Beijing time: ${example.input||'(empty)'}`,()=>assert.equal(formatBeijingDateTime(example.input),example.expected));
}
test('WebView output stays in Beijing time on a device using another timezone',()=>{
  const original=process.env.TZ;
  try{
    for(const zone of ['UTC','America/New_York','Asia/Shanghai']){
      process.env.TZ=zone;
      assert.equal(fmtDate('2026-10-31T13:44:04.064609+00:00'),'2026-10-31 21:44');
      assert.equal(fmtDate('2026-10-31 21:44'),'2026-10-31 21:44');
    }
    assert.equal(fmtDate(null),'尚未同步');
    assert.equal(fmtDate('bad timestamp'),'');
  }finally{if(original===undefined)delete process.env.TZ;else process.env.TZ=original;}
});

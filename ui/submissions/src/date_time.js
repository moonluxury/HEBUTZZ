// Display only. Match the native TimeDisplay's Beijing time and legacy-label policy.
const offsetMinutes=8*60;
const pad=value=>String(value).padStart(2,'0');
const dateLabel=parts=>`${String(parts.year).padStart(4,'0')}-${pad(parts.month)}-${pad(parts.day)}`;
const clockLabel=parts=>`${pad(parts.hour)}:${pad(parts.minute)}`;

export function formatBeijingDateTime(value){
  if(typeof value!=='string')return '';
  const source=value.trim();
  const clock=/^(\d{2}):(\d{2})(?::(\d{2}))?$/.exec(source);
  if(clock)return +clock[1]<24&&+clock[2]<60&&+(clock[3]||0)<60?`${clock[1]}:${clock[2]}`:'';
  const match=/^(\d{4})-(\d{2})-(\d{2})(?:[Tt ](\d{2}):(\d{2})(?::(\d{2})(?:[.,]\d+)?)?([Zz]|[+-]\d{2}:?\d{2})?)?$/.exec(source);
  if(!match)return '';
  const [,y,m,d,h,mi,s,zone]=match;
  const parts={year:+y,month:+m,day:+d,hour:+(h||0),minute:+(mi||0),second:+(s||0)};
  if(parts.year<1||parts.month<1||parts.month>12||parts.day<1||parts.hour>23||parts.minute>59||parts.second>59)return '';
  const instant=new Date(0);
  instant.setUTCFullYear(parts.year,parts.month-1,parts.day);
  instant.setUTCHours(parts.hour,parts.minute,parts.second,0);
  if(instant.getUTCFullYear()!==parts.year||instant.getUTCMonth()+1!==parts.month||instant.getUTCDate()!==parts.day)return '';
  if(h===undefined)return dateLabel(parts);
  let sourceOffset=offsetMinutes;
  if(zone?.toUpperCase()==='Z')sourceOffset=0;
  else if(zone){
    const compact=zone.replace(':',''),hours=+compact.slice(1,3),minutes=+compact.slice(3,5);
    if(hours>23||minutes>59)return '';
    sourceOffset=(hours*60+minutes)*(compact[0]==='-'?-1:1);
  }
  const local=new Date(+instant+(offsetMinutes-sourceOffset)*60000);
  const result={year:local.getUTCFullYear(),month:local.getUTCMonth()+1,day:local.getUTCDate(),hour:local.getUTCHours(),minute:local.getUTCMinutes()};
  return `${dateLabel(result)} ${clockLabel(result)}`;
}

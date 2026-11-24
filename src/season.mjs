import {dayKey,weekStart,ranking} from './stats.mjs';
export const start='2026-11-24',end='2026-12-25',finish='2026-12-26T00:00:00+01:00',zone='Europe/Berlin';
const add=(d,n)=>{const x=new Date(d+'T00:00:00Z');x.setUTCDate(x.getUTCDate()+n);return x.toISOString().slice(0,10)};
const max=(a,b)=>a>b?a:b;
const min=(a,b)=>a<b?a:b;
const between=(r,a,b)=>{const d=dayKey(r.created_at,zone);return d>=a&&d<=b};
const winners=rows=>rows[0]?.count>0?rows.filter(x=>x.count===rows[0].count):[];
export function seasonStats(members,records,me,now=new Date()){
 const today=dayKey(now,zone),last=min(today,end),done=today>end;
 const active=members.filter(m=>m.active);
 const valid=records.filter(r=>active.some(m=>m.id===r.member_id)&&Date.parse(r.created_at)<=+now&&between(r,start,last));
 const overall=ranking(active,valid),own=overall.find(m=>m.id===me)?.count??0;
 const weeks=[];
 for(let d=weekStart(new Date(start+'T12:00:00Z'),zone);d<=end;d=add(d,7)){
  const first=max(d,start),final=min(add(d,6),end);
  if(first>today)break;
  const entries=valid.filter(r=>between(r,first,final)),rows=ranking(active,entries);
  weeks.push({first,final,closed:today>final,rows,winners:winners(rows),total:entries.length,participating:rows.filter(r=>r.count>0).length});
 }
 const current=weeks[weeks.length-1],closed=weeks.filter(w=>w.closed),past=closed[closed.length-1];
 const finalWinners=done?winners(overall):[];
 const activeWeeks=weeks.filter(w=>w.rows.some(r=>r.id===me&&r.count>0)).length;
 const teamPerfect=weeks.some(w=>active.length>1&&w.participating===active.length);
 const awards=[
  {emoji:'🎯',title:'Primer paso',description:'Primera contribución de la temporada',earned:own>=1,progress:own,target:1},
  {emoji:'🥉',title:'Colaborador',description:'3 contribuciones',earned:own>=3,progress:own,target:3},
  {emoji:'🥈',title:'Pilar de la casa',description:'5 contribuciones',earned:own>=5,progress:own,target:5},
  {emoji:'🦸',title:'Héroe del apartamento',description:'8 contribuciones',earned:own>=8,progress:own,target:8},
  {emoji:'🏆',title:'MVP semanal',description:'Gana una semana cerrada',earned:closed.some(w=>w.winners.some(r=>r.id===me))},
  {emoji:'🔥',title:'Constancia',description:'Participa en 3 semanas distintas',earned:activeWeeks>=3,progress:activeWeeks,target:3},
  {emoji:'🤝',title:'Equipo perfecto',description:'Todos participan en una misma semana',earned:teamPerfect},
  {emoji:'🎄',title:'Campeón de Navidad',description:'Primer lugar al cierre del 25 de diciembre',earned:finalWinners.some(r=>r.id===me)}
 ];
 return {overall,own,weeks,current,past,done,finalWinners,awards,total:valid.length,activeCount:active.length};
}

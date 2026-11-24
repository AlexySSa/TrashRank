import {createClient} from 'npm:@supabase/supabase-js@2.49.4';
import webpush from 'npm:web-push@3.6.7';
const url=Deno.env.get('SUPABASE_URL')!,secret=Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!;
const db=createClient(url,secret,{auth:{persistSession:false,autoRefreshToken:false}});
const cors={'Access-Control-Allow-Origin':'*','Access-Control-Allow-Headers':'authorization, apikey, content-type, x-client-info','Access-Control-Allow-Methods':'POST, OPTIONS','Content-Type':'application/json'};
const reply=(body:object,status=200)=>new Response(JSON.stringify(body),{status,headers:cors});
function endpointOK(value:unknown):value is string{if(typeof value!=='string'||value.length>2048)return false;try{const u=new URL(value),h=u.hostname.toLowerCase();return u.protocol==='https:'&&!u.username&&!u.password&&!u.port&&!u.hash&&!!u.pathname&&(['fcm.googleapis.com','updates.push.services.mozilla.com','web.push.apple.com','wns.windows.com'].includes(h)||h.endsWith('.push.services.mozilla.com')||h.endsWith('.push.apple.com')||h.endsWith('.notify.windows.com'))}catch{return false}}
const tokenOK=(x:unknown,min:number,max:number)=>typeof x==='string'&&x.length>=min&&x.length<=max&&/^[A-Za-z0-9_-]+$/.test(x);
async function keys(){const old=await db.from('trash_push_keys').select('public_key,private_key').eq('id',1).maybeSingle();if(old.error)throw old.error;if(old.data)return old.data;const generated=webpush.generateVAPIDKeys();const result=await db.from('trash_push_keys').upsert({id:1,public_key:generated.publicKey,private_key:generated.privateKey},{onConflict:'id',ignoreDuplicates:true});if(result.error)throw result.error;const saved=await db.from('trash_push_keys').select('public_key,private_key').eq('id',1).single();if(saved.error)throw saved.error;return saved.data}
async function deliver(rows:any[],make:(id:string)=>object){if(!rows.length)return {sent:0,failed:0};const k=await keys();const results=await Promise.all(rows.map(async r=>{if(!endpointOK(r.endpoint))return false;try{await webpush.sendNotification({endpoint:r.endpoint,keys:{p256dh:r.p256dh,auth:r.auth}},JSON.stringify(make(r.member_id)),{TTL:3600,urgency:'high',timeout:8000,vapidDetails:{subject:'https://trashrank.vercel.app',publicKey:k.public_key,privateKey:k.private_key}});return true}catch(e:any){if(e?.statusCode===404||e?.statusCode===410)await db.from('trash_push_subscriptions').delete().eq('endpoint',r.endpoint);return false}}));return {sent:results.filter(Boolean).length,failed:results.filter(v=>!v).length}}
// Database dispatch uses an unguessable, one-use per-event nonce. It cannot create events.
async function dispatchWall(body:any){
 if(typeof body.eventId!=='string'||typeof body.nonce!=='string'||!/^[-0-9a-f]{36}$/i.test(body.eventId)||!/^[-0-9a-f]{36}$/i.test(body.nonce))return reply({error:'Aviso inválido'},400);
 const claimed=await db.from('wall_notification_events').update({claimed_at:new Date().toISOString()}).eq('id',body.eventId).eq('nonce',body.nonce).is('claimed_at',null).gte('created_at',new Date(Date.now()-3600000).toISOString()).select('id,house_id,actor_id,owner_id,kind').maybeSingle();
 if(claimed.error)return reply({error:'No se pudo preparar el aviso'},500);
 if(!claimed.data)return reply({ok:true,sent:0});
 const e=claimed.data;
 const [notifications,members]=await Promise.all([db.from('wall_notifications').select('recipient_id,actor_name,is_own').eq('event_id',e.id),db.from('members').select('id').eq('house_id',e.house_id).eq('active',true)]);
 if(notifications.error||members.error)return reply({error:'No se pudieron verificar destinatarios'},500);
 const active=new Set(members.data.map(x=>x.id));
 const targets=notifications.data.filter(n=>active.has(n.recipient_id)&&n.recipient_id!==e.actor_id);
 if(!targets.length)return reply({ok:true,sent:0});
 const preferences=await db.from('wall_notification_preferences').select('member_id,mode').in('member_id',targets.map(n=>n.recipient_id));
 if(preferences.error)return reply({error:'No se pudieron verificar preferencias'},500);
 const modes=new Map(preferences.data.map(x=>[x.member_id,x.mode]));
 const allowed=targets.filter(n=>modes.get(n.recipient_id)==='all'||(modes.get(n.recipient_id)==='own'&&n.is_own));
 if(!allowed.length)return reply({ok:true,sent:0});
 const subscriptions=await db.from('trash_push_subscriptions').select('*').in('member_id',allowed.map(n=>n.recipient_id));
 if(subscriptions.error)return reply({error:'No se pudieron leer dispositivos'},500);
 const result=await deliver(subscriptions.data??[],uid=>{
  const n=allowed.find(x=>x.recipient_id===uid)!;let title='Actividad del muro',message='';
  if(e.kind==='post'){title='Nueva publicación';message=n.actor_name+' publicó algo en el muro.'}
  if(e.kind==='comment'){title=n.is_own?'Comentaron tu publicación':'Nuevo comentario';message=n.actor_name+(n.is_own?' comentó tu publicación.':' dejó un comentario en el muro.')}
  if(e.kind==='reaction'){title=n.is_own?'Reaccionaron a tu contenido':'Nueva reacción';message=n.actor_name+(n.is_own?' reaccionó a tu contenido.':' reaccionó en el muro.')}
  if(e.kind==='contribution'){title='Nueva contribución';message=n.actor_name+' registró que sacó la basura.'}
  return {title:'Muro · '+title,body:message,tag:'wall-'+e.id,destination:'wall'};
 });
 return reply({ok:true,...result});
}
Deno.serve(async req=>{if(req.method==='OPTIONS')return new Response(null,{status:204,headers:cors});if(req.method!=='POST')return reply({error:'Método inválido'},405);try{const body=await req.json();if(body?.action==='wall-dispatch')return await dispatchWall(body);const token=req.headers.get('authorization')?.match(/^Bearer (.+)$/i)?.[1];if(!token)return reply({error:'Inicia sesión'},401);const auth=await db.auth.getUser(token);if(auth.error||!auth.data.user)return reply({error:'Sesión inválida'},401);const id=auth.data.user.id;const member=await db.from('members').select('id,house_id,role,active').eq('id',id).eq('active',true).maybeSingle();if(member.error||!member.data)return reply({error:'No perteneces a una casa activa'},403);const m=member.data;
if(body.action==='key'){const k=await keys();return reply({publicKey:k.public_key})}
if(body.action==='subscribe'){const s=body.subscription;if(!endpointOK(s?.endpoint)||!tokenOK(s?.keys?.p256dh,80,128)||!tokenOK(s?.keys?.auth,16,64))return reply({error:'Suscripción no compatible'},400);const count=await db.from('trash_push_subscriptions').select('endpoint',{count:'exact',head:true}).eq('member_id',id).neq('endpoint',s.endpoint);if(count.error)throw count.error;if((count.count??0)>=5)return reply({error:'Máximo 5 dispositivos por cuenta. Desactiva uno antes de añadir otro.'},400);const result=await db.from('trash_push_subscriptions').upsert({endpoint:s.endpoint,member_id:id,p256dh:s.keys.p256dh,auth:s.keys.auth,updated_at:new Date().toISOString()},{onConflict:'endpoint'});if(result.error)throw result.error;return reply({ok:true})}
if(body.action==='unsubscribe'){if(!endpointOK(body.endpoint))return reply({error:'Dispositivo inválido'},400);const r=await db.from('trash_push_subscriptions').delete().eq('endpoint',body.endpoint).eq('member_id',id);if(r.error)throw r.error;return reply({ok:true})}
if(body.action==='test'){if(!endpointOK(body.endpoint))return reply({error:'Dispositivo inválido'},400);const s=await db.from('trash_push_subscriptions').select('*').eq('member_id',id).eq('endpoint',body.endpoint);if(s.error)throw s.error;const delivered=await deliver(s.data??[],()=>({title:'TrashRank · Prueba',body:'¡Las notificaciones de este dispositivo están activadas!',tag:'trashrank-test'}));return reply(delivered)}
if(body.action==='alert'){if(m.role!=='admin')return reply({error:'Solo el administrador puede enviar avisos'},403);if(typeof body.assignee!=='string'||!/^[0-9a-f-]{36}$/i.test(body.assignee))return reply({error:'Responsable inválido'},400);const a=await db.rpc('create_trash_alert',{p_admin:id,p_assignee:body.assignee});if(a.error)return reply({error:a.error.message},409);const alert=Array.isArray(a.data)?a.data[0]:a.data;if(!alert?.id)return reply({ok:true,sent:0,failed:-1});let sent=0,failed=0;try{const people=await db.from('members').select('id').eq('house_id',m.house_id).eq('active',true);if(people.error)throw people.error;const ids=people.data.map(x=>x.id);const subs=await db.from('trash_push_subscriptions').select('*').in('member_id',ids);if(subs.error)throw subs.error;const result=await deliver(subs.data??[],uid=>({title:uid===alert.assignee_id?'¡Te toca sacar la basura!':'La basura está llena',body:uid===alert.assignee_id?'El administrador avisó que es hora de sacar la basura.':'Le toca sacar la basura a '+alert.assignee_name+'.',tag:'trash-'+alert.id}));sent=result.sent;failed=result.failed}catch{failed=-1}return reply({ok:true,alertId:alert.id,sent,failed})}
return reply({error:'Acción inválida'},400)}catch{return reply({error:'No se pudo completar la operación'},500)}});

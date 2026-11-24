import {createClient} from 'npm:@supabase/supabase-js@2.49.4';
const cors={'Access-Control-Allow-Origin':'*','Access-Control-Allow-Headers':'authorization, apikey, content-type, x-client-info','Access-Control-Allow-Methods':'POST, OPTIONS','Cache-Control':'no-store'};
const reply=(status:number,data:object)=>new Response(JSON.stringify(data),{status,headers:{...cors,'Content-Type':'application/json'}});
Deno.serve(async(req:Request)=>{
 if(req.method==='OPTIONS')return new Response(null,{status:204,headers:cors});
 if(req.method!=='POST')return reply(405,{error:'Método inválido'});
 try {
 const url=Deno.env.get('SUPABASE_URL')!,secret=Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')||JSON.parse(Deno.env.get('SUPABASE_SECRET_KEYS')||'{}').default;
 if(!url||!secret)return reply(503,{error:'Servidor sin configurar'});
 const client=createClient(url,secret,{auth:{persistSession:false,autoRefreshToken:false}});
 const raw=await req.text();if(raw.length>4096)return reply(413,{error:'Solicitud demasiado grande'});
 const body=JSON.parse(raw),{action,password}=body??{};
 if(typeof password!=='string'||password.length<8||new TextEncoder().encode(password).length>72)return reply(400,{error:'Contraseña de 8 a 72 bytes'});
 const username=typeof body.username==='string'?body.username.trim().toLowerCase():'';
 if(action==='signup'){
   if(!/^[a-z0-9_]{3,24}$/.test(username))return reply(400,{error:'Usuario inválido'});
   const {data:allowed,error:quotaError}=await client.rpc('reserve_signup',{p_bucket:'global',p_max:60});if(quotaError||!allowed)return reply(429,{error:'Demasiados registros. Intenta más tarde.'});
   const {data:allowedUser,error:userError}=await client.rpc('reserve_signup',{p_bucket:'user:'+username,p_max:4});if(userError||!allowedUser)return reply(429,{error:'Demasiados intentos. Intenta más tarde.'});
   const {error}=await client.auth.admin.createUser({email:username+'@trashrank.invalid',password,email_confirm:true});
   return error?reply(400,{error:'No se pudo crear la cuenta; prueba con otro usuario'}):reply(200,{ok:true});
 }
 const token=req.headers.get('authorization')?.match(/^Bearer (.+)$/i)?.[1];if(!token)return reply(401,{error:'Inicia sesión'});
 const {data:{user},error}=await client.auth.getUser(token);if(error||!user)return reply(401,{error:'Sesión inválida'});
 const {data:admin}=await client.from('members').select('house_id,role,active').eq('id',user.id).maybeSingle();if(!admin?.active||admin.role!=='admin')return reply(403,{error:'Sin permiso'});
 if(action==='create'){
   const name=typeof body.name==='string'?body.name.trim():'';
   if(!/^[a-z0-9_]{3,24}$/.test(username)||!name||name.length>80)return reply(400,{error:'Nombre o usuario inválido'});
   const {data,error}=await client.auth.admin.createUser({email:username+'@trashrank.invalid',password,email_confirm:true});if(error||!data.user)return reply(400,{error:'No se pudo crear el usuario; prueba con otro nombre'});
   const {error:link}=await client.rpc('server_add_member',{p_admin:user.id,p_id:data.user.id,p_username:username,p_name:name});if(link){await client.auth.admin.deleteUser(data.user.id);return reply(400,{error:'No se pudo añadir el miembro'});}
   return reply(200,{ok:true});
 }
 if(action==='reset'){
   const {data:target}=await client.from('members').select('id,role').eq('id',String(body.id)).eq('house_id',admin.house_id).eq('active',true).maybeSingle();if(!target||target.role==='admin')return reply(403,{error:'Miembro no disponible'});
   const {error}=await client.auth.admin.updateUserById(target.id,{password});return error?reply(400,{error:'No se pudo restablecer la contraseña'}):reply(200,{ok:true});
 }
 return reply(400,{error:'Acción inválida'});
 }catch{return reply(500,{error:'Error del servidor'});}
});

import {createClient} from '@supabase/supabase-js';
import type {IncomingMessage,ServerResponse} from 'node:http';
export default async function handler(req:IncomingMessage & {body?:any},res:ServerResponse){
 const send=(status:number,data:object)=>{res.statusCode=status;res.setHeader('Content-Type','application/json');res.setHeader('Cache-Control','no-store');res.end(JSON.stringify(data))};
 if(req.method!=='POST') return send(405,{error:'Método inválido'});
 try{
  const url=process.env.VITE_SUPABASE_URL,key=process.env.SUPABASE_SERVICE_ROLE_KEY;if(!url||!key)return send(503,{error:'Servidor sin configurar'});
  const token=req.headers.authorization?.match(/^Bearer (.+)$/)?.[1];if(!token)return send(401,{error:'Inicia sesión'});
  const client=createClient(url,key,{auth:{persistSession:false,autoRefreshToken:false}});
  const {data:{user},error}=await client.auth.getUser(token);if(error||!user)return send(401,{error:'Sesión inválida'});
  const {data:admin}=await client.from('members').select('house_id,role,active').eq('id',user.id).maybeSingle();if(!admin?.active||admin.role!=='admin')return send(403,{error:'Sin permiso'});
  const body=typeof req.body==='string'?JSON.parse(req.body):req.body;const {action,password}=body??{};
  if(typeof password!=='string'||password.length<8||password.length>72)return send(400,{error:'Contraseña de 8 a 72 caracteres'});
  if(action==='create'){
   const username=String(body.username??'').trim().toLowerCase(),name=String(body.name??'').trim();if(!/^[a-z0-9_]{3,24}$/.test(username)||!name||name.length>80)return send(400,{error:'Nombre o usuario inválido'});
   const {data,error}=await client.auth.admin.createUser({email:username+'@trashrank.invalid',password,email_confirm:true});if(error||!data.user)return send(400,{error:'No se pudo crear el usuario; prueba con otro nombre'});
   const {error:link}=await client.rpc('server_add_member',{p_admin:user.id,p_id:data.user.id,p_username:username,p_name:name});if(link){await client.auth.admin.deleteUser(data.user.id);return send(400,{error:'No se pudo añadir el miembro'});}
   return send(200,{ok:true});
  }
  if(action==='reset'){
   const {data:target}=await client.from('members').select('id,role').eq('id',String(body.id)).eq('house_id',admin.house_id).eq('active',true).maybeSingle();if(!target||target.role==='admin')return send(403,{error:'Miembro no disponible'});
   const {error}=await client.auth.admin.updateUserById(target.id,{password});if(error)return send(400,{error:'No se pudo restablecer la contraseña'});return send(200,{ok:true});
  }
  return send(400,{error:'Acción inválida'});
 }catch{return send(500,{error:'Error del servidor'});}
}

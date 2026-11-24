# TrashRank

Aplicación web para hogares compartidos. React, TypeScript, Tailwind, Supabase/PostgreSQL, Vercel y PWA.

## Instalación y publicación
1. Crea un proyecto Free en Supabase. Ejecuta supabase/schema.sql una sola vez en SQL Editor.
2. En Authentication, habilita Email y el registro, desactiva Confirm email y exige al menos 8 caracteres. Se usa usuario@trashrank.invalid como identificador sintético; no hay recuperación por correo.
3. Importa este repositorio en Vercel Hobby, framework Vite. Build: npm run build; salida: dist.
4. Configura VITE_SUPABASE_URL, VITE_SUPABASE_ANON_KEY y SUPABASE_SERVICE_ROLE_KEY (exclusivamente en el servidor). No publiques las claves privadas. Ajusta Site URL en Supabase al dominio de Vercel.
5. Ejecuta npm install, npm test y npm run build. Prueba el aislamiento entre casas, autenticación, permisos de administrador, registros duplicados y sincronización antes de compartir el enlace.

La aplicación requiere conexión. El despliegue y pruebas de integración están pendientes.

# Pruebas de integración pendientes
En un proyecto de prueba real:
- Registrar dos administradores y casas distintas. Verificar RLS intentando leer o escribir datos de la otra casa con cada token.
- Probar invitación, rotación del código, registro de miembros y restablecimiento de contraseña; verificar que un miembro normal recibe 403 en /api/members.
- Registrar una contribución en dos dispositivos, verificar sincronización y bloqueo de repetición de UUID o menos de 60 segundos.
- Comprobar ranking con ceros, filtros por fechas locales, porcentajes, logros, cambio de zona horaria y reinicio sin pérdida de historial. Corregir y eliminar registros como admin.
- Subir imágenes válidas, rechazar tipo o tamaño inválido, comprobar privacidad de fotos y pérdida de acceso de miembros retirados.
- Verificar que dist/ no contiene claves privadas; probar PWA en Chrome Android y Safari iOS, desconexión y reconexión.

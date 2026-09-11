-- Script para documentar las políticas de seguridad actualizadas
-- Este script es solo para documentación y no realiza cambios en la base de datos

/*
DOCUMENTACIÓN DE POLÍTICAS DE SEGURIDAD

Las políticas de seguridad en Supabase se han actualizado para permitir que todos los usuarios 
con rol de administrador de un tenant puedan ver y modificar los recursos de ese tenant, 
no solo el usuario que los creó.

FUNCIONES DE SEGURIDAD:

1. is_tenant_admin(tenant_id uuid): 
   Verifica si el usuario actual es administrador del tenant especificado.

2. is_tenant_member(tenant_id uuid): 
   Verifica si el usuario actual es miembro del tenant especificado.

3. is_tenant_owner(tenant_id uuid): 
   Verifica si el usuario actual es propietario del tenant especificado.

POLÍTICAS POR TABLA:

1. tenant_users:
   - tenant_user_read: Permite a los usuarios ver todas las relaciones tenant_user de los tenants a los que pertenecen.
   - tenant_user_insert: Permite a los usuarios insertarse a sí mismos o a los administradores insertar otros usuarios.
   - tenant_user_update: Permite a los administradores actualizar usuarios en sus tenants.
   - tenant_user_delete: Permite a los usuarios eliminarse a sí mismos o a los administradores eliminar otros usuarios.

2. tenants:
   - tenant_read: Permite a los usuarios ver los tenants a los que pertenecen.
   - tenant_insert: Permite a cualquier usuario autenticado crear un tenant donde es propietario.
   - tenant_update: Permite al propietario o administradores actualizar un tenant.
   - tenant_delete: Permite solo al propietario eliminar un tenant.

3. roles:
   - role_read: Permite a los usuarios ver los roles de los tenants a los que pertenecen.
   - role_insert: Permite solo a los administradores crear roles.
   - role_update: Permite solo a los administradores actualizar roles.
   - role_delete: Permite solo a los administradores eliminar roles (excepto el rol Admin).

4. Otras tablas:
   Todas las demás tablas con tenant_id tienen políticas similares que permiten:
   - Lectura: A todos los miembros del tenant.
   - Inserción/Actualización/Eliminación: Solo a usuarios con los permisos correspondientes.

NOTA: Estas políticas garantizan que los administradores de un tenant puedan gestionar todos los recursos
de ese tenant, independientemente de quién los haya creado, mientras que los usuarios regulares
solo pueden ver los recursos pero no modificarlos a menos que tengan permisos específicos.
*/

-- Este script no ejecuta ninguna operación, es solo para documentación
SELECT 'Documentación de políticas de seguridad actualizada';

-- Script para verificar y corregir las políticas de seguridad
BEGIN;

-- Verificar las políticas existentes
SELECT 
    schemaname, 
    tablename, 
    policyname, 
    permissive, 
    roles, 
    cmd, 
    qual, 
    with_check
FROM 
    pg_policies
WHERE 
    schemaname = 'public'
ORDER BY 
    tablename, policyname;

-- Eliminar todas las políticas existentes para tenant_users
DROP POLICY IF EXISTS tenant_user_tenant_access ON tenant_users;
DROP POLICY IF EXISTS tenant_user_self_access ON tenant_users;
DROP POLICY IF EXISTS tenant_user_admin_access ON tenant_users;
DROP POLICY IF EXISTS tenant_user_insert ON tenant_users;
DROP POLICY IF EXISTS tenant_user_update ON tenant_users;
DROP POLICY IF EXISTS tenant_user_delete ON tenant_users;

-- Crear políticas simplificadas para tenant_users
-- Esta política permite a todos los usuarios autenticados ver todas las relaciones tenant_user
CREATE POLICY tenant_user_read ON tenant_users
    FOR SELECT
    USING (auth.uid() IS NOT NULL);

-- Esta política permite a los usuarios insertar sus propias relaciones
CREATE POLICY tenant_user_insert ON tenant_users
    FOR INSERT
    WITH CHECK (user_id = auth.uid());

-- Esta política permite a los usuarios actualizar sus propias relaciones
CREATE POLICY tenant_user_update ON tenant_users
    FOR UPDATE
    USING (user_id = auth.uid());

-- Esta política permite a los usuarios eliminar sus propias relaciones
CREATE POLICY tenant_user_delete ON tenant_users
    FOR DELETE
    USING (user_id = auth.uid());

-- Verificar las políticas después de los cambios
SELECT 
    schemaname, 
    tablename, 
    policyname, 
    permissive, 
    roles, 
    cmd, 
    qual, 
    with_check
FROM 
    pg_policies
WHERE 
    schemaname = 'public' AND
    tablename = 'tenant_users'
ORDER BY 
    policyname;

-- Crear un tenant de prueba si no existe ninguno
INSERT INTO tenants (name, owner_user_id)
SELECT 'Mi Negocio', auth.uid()
WHERE NOT EXISTS (
    SELECT 1 FROM tenants WHERE owner_user_id = auth.uid()
);

-- Asegurarse de que el usuario actual tenga acceso al tenant
INSERT INTO tenant_users (tenant_id, user_id, role_id)
SELECT t.id, auth.uid(), r.id
FROM tenants t
JOIN roles r ON r.tenant_id = t.id AND r.name = 'Admin'
WHERE t.owner_user_id = auth.uid()
AND NOT EXISTS (
    SELECT 1 FROM tenant_users WHERE tenant_id = t.id AND user_id = auth.uid()
);

-- Confirmar la transacción
COMMIT;

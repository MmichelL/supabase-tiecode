-- Script para corregir todas las políticas de seguridad
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

-- Verificar las tablas existentes
SELECT 
    tablename 
FROM 
    pg_tables 
WHERE 
    schemaname = 'public';

-- Eliminar todas las políticas existentes para las tablas principales
DROP POLICY IF EXISTS tenant_user_tenant_access ON tenant_users;
DROP POLICY IF EXISTS tenant_user_self_access ON tenant_users;
DROP POLICY IF EXISTS tenant_user_admin_access ON tenant_users;
DROP POLICY IF EXISTS tenant_user_read ON tenant_users;
DROP POLICY IF EXISTS tenant_user_insert ON tenant_users;
DROP POLICY IF EXISTS tenant_user_update ON tenant_users;
DROP POLICY IF EXISTS tenant_user_delete ON tenant_users;

DROP POLICY IF EXISTS tenant_user_access ON tenants;
DROP POLICY IF EXISTS tenant_owner_access ON tenants;
DROP POLICY IF EXISTS tenant_member_access ON tenants;
DROP POLICY IF EXISTS tenant_insert ON tenants;
DROP POLICY IF EXISTS tenant_update ON tenants;
DROP POLICY IF EXISTS tenant_delete ON tenants;

DROP POLICY IF EXISTS role_tenant_access ON roles;
DROP POLICY IF EXISTS role_admin_access ON roles;
DROP POLICY IF EXISTS role_self_access ON roles;
DROP POLICY IF EXISTS role_insert ON roles;
DROP POLICY IF EXISTS role_update ON roles;
DROP POLICY IF EXISTS role_delete ON roles;

-- Función para verificar si un usuario es administrador de un tenant
CREATE OR REPLACE FUNCTION is_tenant_admin(tenant_id uuid)
RETURNS boolean AS $$
BEGIN
  RETURN EXISTS (
    SELECT 1
    FROM tenant_users tu
    JOIN roles r ON tu.role_id = r.id
    WHERE tu.tenant_id = tenant_id
    AND tu.user_id = auth.uid()
    AND r.name = 'Admin'
  );
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Función para verificar si un usuario es miembro de un tenant
CREATE OR REPLACE FUNCTION is_tenant_member(tenant_id uuid)
RETURNS boolean AS $$
BEGIN
  RETURN EXISTS (
    SELECT 1
    FROM tenant_users
    WHERE tenant_id = tenant_id
    AND user_id = auth.uid()
  );
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Función para verificar si un usuario es propietario de un tenant
CREATE OR REPLACE FUNCTION is_tenant_owner(tenant_id uuid)
RETURNS boolean AS $$
BEGIN
  RETURN EXISTS (
    SELECT 1
    FROM tenants
    WHERE id = tenant_id
    AND owner_user_id = auth.uid()
  );
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Políticas para tenant_users
-- Los usuarios pueden ver todas las relaciones tenant_user de los tenants a los que pertenecen
CREATE POLICY tenant_user_read ON tenant_users
    FOR SELECT
    USING (
        -- El usuario es miembro del tenant
        tenant_id IN (
            SELECT tenant_id FROM tenant_users WHERE user_id = auth.uid()
        )
    );

-- Los administradores pueden insertar nuevos usuarios en sus tenants
CREATE POLICY tenant_user_insert ON tenant_users
    FOR INSERT
    WITH CHECK (
        -- El usuario es el propio usuario
        user_id = auth.uid()
        OR
        -- El usuario es administrador del tenant
        is_tenant_admin(tenant_id)
    );

-- Los administradores pueden actualizar usuarios en sus tenants
CREATE POLICY tenant_user_update ON tenant_users
    FOR UPDATE
    USING (
        -- El usuario es el propio usuario
        user_id = auth.uid()
        OR
        -- El usuario es administrador del tenant
        is_tenant_admin(tenant_id)
    );

-- Los administradores pueden eliminar usuarios de sus tenants
CREATE POLICY tenant_user_delete ON tenant_users
    FOR DELETE
    USING (
        -- El usuario es el propio usuario
        user_id = auth.uid()
        OR
        -- El usuario es administrador del tenant
        is_tenant_admin(tenant_id)
    );

-- Políticas para tenants
-- Los usuarios pueden ver los tenants a los que pertenecen
CREATE POLICY tenant_read ON tenants
    FOR SELECT
    USING (
        -- El usuario es propietario del tenant
        owner_user_id = auth.uid()
        OR
        -- El usuario es miembro del tenant
        id IN (
            SELECT tenant_id FROM tenant_users WHERE user_id = auth.uid()
        )
    );

-- Cualquier usuario autenticado puede crear un tenant
CREATE POLICY tenant_insert ON tenants
    FOR INSERT
    WITH CHECK (
        -- El usuario es el propietario
        owner_user_id = auth.uid()
    );

-- Solo el propietario o los administradores pueden actualizar un tenant
CREATE POLICY tenant_update ON tenants
    FOR UPDATE
    USING (
        -- El usuario es propietario del tenant
        owner_user_id = auth.uid()
        OR
        -- El usuario es administrador del tenant
        is_tenant_admin(id)
    );

-- Solo el propietario puede eliminar un tenant
CREATE POLICY tenant_delete ON tenants
    FOR DELETE
    USING (
        -- El usuario es propietario del tenant
        owner_user_id = auth.uid()
    );

-- Políticas para roles
-- Los usuarios pueden ver los roles de los tenants a los que pertenecen
CREATE POLICY role_read ON roles
    FOR SELECT
    USING (
        -- El rol pertenece a un tenant del que el usuario es miembro
        tenant_id IN (
            SELECT tenant_id FROM tenant_users WHERE user_id = auth.uid()
        )
    );

-- Solo los administradores pueden crear roles
CREATE POLICY role_insert ON roles
    FOR INSERT
    WITH CHECK (
        -- El usuario es administrador del tenant
        is_tenant_admin(tenant_id)
    );

-- Solo los administradores pueden actualizar roles
CREATE POLICY role_update ON roles
    FOR UPDATE
    USING (
        -- El usuario es administrador del tenant
        is_tenant_admin(tenant_id)
    );

-- Solo los administradores pueden eliminar roles (excepto el rol Admin)
CREATE POLICY role_delete ON roles
    FOR DELETE
    USING (
        -- El usuario es administrador del tenant
        is_tenant_admin(tenant_id)
        AND
        -- No se puede eliminar el rol Admin
        name != 'Admin'
    );

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
    schemaname = 'public'
ORDER BY 
    tablename, policyname;

-- Confirmar la transacción
COMMIT;

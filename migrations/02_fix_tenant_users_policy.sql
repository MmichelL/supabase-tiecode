-- Script para corregir la política de tenant_users que causa recursión infinita
BEGIN;

-- Eliminar la política actual que causa recursión infinita
DROP POLICY IF EXISTS tenant_user_tenant_access ON tenant_users;

-- Crear una nueva política para tenant_users que no cause recursión
-- Esta política permite a los usuarios ver sus propias relaciones tenant_user
CREATE POLICY tenant_user_self_access ON tenant_users
    USING (user_id = auth.uid());

-- Esta política permite a los administradores ver todas las relaciones tenant_user de sus tenants
CREATE POLICY tenant_user_admin_access ON tenant_users
    USING (
        EXISTS (
            SELECT 1
            FROM tenant_users tu
            JOIN roles r ON tu.role_id = r.id
            WHERE tu.tenant_id = tenant_users.tenant_id
            AND tu.user_id = auth.uid()
            AND r.name = 'Admin'
        )
    );

-- Crear políticas para inserción, actualización y eliminación
CREATE POLICY tenant_user_insert ON tenant_users
    FOR INSERT WITH CHECK (
        -- Los usuarios pueden insertarse a sí mismos
        user_id = auth.uid()
        OR
        -- Los administradores pueden insertar a otros usuarios en sus tenants
        EXISTS (
            SELECT 1
            FROM tenant_users tu
            JOIN roles r ON tu.role_id = r.id
            WHERE tu.tenant_id = tenant_users.tenant_id
            AND tu.user_id = auth.uid()
            AND r.name = 'Admin'
        )
    );

CREATE POLICY tenant_user_update ON tenant_users
    FOR UPDATE USING (
        -- Los administradores pueden actualizar usuarios en sus tenants
        EXISTS (
            SELECT 1
            FROM tenant_users tu
            JOIN roles r ON tu.role_id = r.id
            WHERE tu.tenant_id = tenant_users.tenant_id
            AND tu.user_id = auth.uid()
            AND r.name = 'Admin'
        )
    );

CREATE POLICY tenant_user_delete ON tenant_users
    FOR DELETE USING (
        -- Los usuarios pueden eliminarse a sí mismos
        user_id = auth.uid()
        OR
        -- Los administradores pueden eliminar a otros usuarios en sus tenants
        EXISTS (
            SELECT 1
            FROM tenant_users tu
            JOIN roles r ON tu.role_id = r.id
            WHERE tu.tenant_id = tenant_users.tenant_id
            AND tu.user_id = auth.uid()
            AND r.name = 'Admin'
        )
    );

-- Confirmar la transacción
COMMIT;

-- Script para corregir la política de roles para evitar problemas de recursión
BEGIN;

-- Eliminar la política actual que podría causar problemas
DROP POLICY IF EXISTS role_tenant_access ON roles;

-- Crear una nueva política para roles
-- Esta política permite a los administradores ver los roles de sus tenants
CREATE POLICY role_admin_access ON roles
    USING (
        EXISTS (
            SELECT 1
            FROM tenant_users tu
            WHERE tu.tenant_id = roles.tenant_id
            AND tu.user_id = auth.uid()
            AND EXISTS (
                SELECT 1
                FROM roles r
                WHERE r.id = tu.role_id
                AND r.name = 'Admin'
            )
        )
    );

-- Esta política permite a los usuarios ver su propio rol
CREATE POLICY role_self_access ON roles
    USING (
        id IN (
            SELECT role_id
            FROM tenant_users
            WHERE user_id = auth.uid()
        )
    );

-- Crear políticas para inserción, actualización y eliminación
CREATE POLICY role_insert ON roles
    FOR INSERT WITH CHECK (
        -- Solo los administradores pueden crear roles
        EXISTS (
            SELECT 1
            FROM tenant_users tu
            JOIN roles r ON tu.role_id = r.id
            WHERE tu.tenant_id = roles.tenant_id
            AND tu.user_id = auth.uid()
            AND r.name = 'Admin'
        )
    );

CREATE POLICY role_update ON roles
    FOR UPDATE USING (
        -- Solo los administradores pueden actualizar roles
        EXISTS (
            SELECT 1
            FROM tenant_users tu
            JOIN roles r ON tu.role_id = r.id
            WHERE tu.tenant_id = roles.tenant_id
            AND tu.user_id = auth.uid()
            AND r.name = 'Admin'
        )
    );

CREATE POLICY role_delete ON roles
    FOR DELETE USING (
        -- Solo los administradores pueden eliminar roles
        EXISTS (
            SELECT 1
            FROM tenant_users tu
            JOIN roles r ON tu.role_id = r.id
            WHERE tu.tenant_id = roles.tenant_id
            AND tu.user_id = auth.uid()
            AND r.name = 'Admin'
        )
        -- No permitir eliminar el rol Admin
        AND name != 'Admin'
    );

-- Confirmar la transacción
COMMIT;

-- Script para corregir la política de tenants para evitar problemas de recursión
BEGIN;

-- Eliminar la política actual que podría causar problemas
DROP POLICY IF EXISTS tenant_user_access ON tenants;

-- Crear una nueva política para tenants
-- Esta política permite a los usuarios ver los tenants donde son propietarios
CREATE POLICY tenant_owner_access ON tenants
    USING (owner_user_id = auth.uid());

-- Esta política permite a los usuarios ver los tenants donde son miembros
CREATE POLICY tenant_member_access ON tenants
    USING (
        id IN (
            SELECT tenant_id 
            FROM tenant_users 
            WHERE user_id = auth.uid()
        )
    );

-- Crear políticas para inserción, actualización y eliminación
CREATE POLICY tenant_insert ON tenants
    FOR INSERT WITH CHECK (
        -- Los usuarios solo pueden crear tenants donde son propietarios
        owner_user_id = auth.uid()
    );

CREATE POLICY tenant_update ON tenants
    FOR UPDATE USING (
        -- Solo el propietario puede actualizar el tenant
        owner_user_id = auth.uid()
        OR
        -- O un administrador del tenant
        EXISTS (
            SELECT 1
            FROM tenant_users tu
            JOIN roles r ON tu.role_id = r.id
            WHERE tu.tenant_id = tenants.id
            AND tu.user_id = auth.uid()
            AND r.name = 'Admin'
        )
    );

CREATE POLICY tenant_delete ON tenants
    FOR DELETE USING (
        -- Solo el propietario puede eliminar el tenant
        owner_user_id = auth.uid()
    );

-- Confirmar la transacción
COMMIT;

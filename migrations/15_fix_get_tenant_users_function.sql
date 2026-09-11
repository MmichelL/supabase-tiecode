-- Script para corregir la función get_tenant_users
BEGIN;

-- Eliminar la función existente antes de recrearla
DROP FUNCTION IF EXISTS get_tenant_users(UUID);

-- Crear la función corregida para obtener usuarios por tenant
CREATE OR REPLACE FUNCTION get_tenant_users(p_tenant_id UUID)
RETURNS TABLE (
    user_id UUID,
    email TEXT,
    role_id UUID,
    role_name TEXT,
    joined_at TIMESTAMPTZ
) SECURITY DEFINER
AS $$
BEGIN
    -- Solo permitir a usuarios autenticados
    IF auth.uid() IS NULL THEN
        RAISE EXCEPTION 'No autenticado';
    END IF;

    -- Verificar que el usuario pertenece al tenant
    -- Usar alias para evitar ambigüedad con la columna user_id
    IF NOT EXISTS (
        SELECT 1 FROM tenant_users tu
        WHERE tu.tenant_id = p_tenant_id AND tu.user_id = auth.uid()
    ) THEN
        RAISE EXCEPTION 'No tienes acceso a este tenant';
    END IF;

    -- Devolver los usuarios del tenant con sus roles
    RETURN QUERY
    SELECT 
        tu.user_id,
        au.email::TEXT,
        tu.role_id,
        r.name AS role_name,
        tu.joined_at
    FROM tenant_users tu
    JOIN roles r ON tu.role_id = r.id
    JOIN auth.users au ON tu.user_id = au.id
    WHERE tu.tenant_id = p_tenant_id;
END;
$$ LANGUAGE plpgsql;

-- Otorgar permisos para ejecutar la función
GRANT EXECUTE ON FUNCTION get_tenant_users(UUID) TO authenticated;

-- Verificar que la función se ha creado correctamente
DO $$
BEGIN
    RAISE NOTICE 'Función get_tenant_users corregida correctamente';
END $$;

COMMIT;

-- Script para mejorar el acceso a la información de usuarios
BEGIN;

-- Eliminar la función existente antes de recrearla con un tipo de retorno diferente
DROP FUNCTION IF EXISTS get_users_by_ids(UUID[]);

-- Crear la función mejorada para obtener más información de usuarios
CREATE OR REPLACE FUNCTION get_users_by_ids(user_ids UUID[])
RETURNS TABLE (
    id UUID,
    email TEXT,
    created_at TIMESTAMPTZ,
    last_sign_in_at TIMESTAMPTZ
) SECURITY DEFINER
AS $$
BEGIN
    -- Solo permitir a usuarios autenticados
    IF auth.uid() IS NULL THEN
        RAISE EXCEPTION 'No autenticado';
    END IF;

    -- Devolver los usuarios solicitados con más información
    RETURN QUERY
    SELECT 
        au.id, 
        au.email::TEXT,
        au.created_at,
        au.last_sign_in_at
    FROM auth.users au
    WHERE au.id = ANY(user_ids);
END;
$$ LANGUAGE plpgsql;

-- Crear una nueva función para obtener usuarios por tenant
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
    IF NOT EXISTS (
        SELECT 1 FROM tenant_users 
        WHERE tenant_id = p_tenant_id AND user_id = auth.uid()
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

-- Otorgar permisos para ejecutar las funciones
GRANT EXECUTE ON FUNCTION get_users_by_ids(UUID[]) TO authenticated;
GRANT EXECUTE ON FUNCTION get_tenant_users(UUID) TO authenticated;

COMMIT;

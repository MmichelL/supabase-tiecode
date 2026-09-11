-- Script para crear una función que permita obtener usuarios de auth.users
BEGIN;

-- Crear función para obtener usuarios por IDs
CREATE OR REPLACE FUNCTION get_users_by_ids(user_ids UUID[])
RETURNS TABLE (
    id UUID,
    email TEXT
) SECURITY DEFINER
AS $$
BEGIN
    -- Solo permitir a usuarios autenticados
    IF auth.uid() IS NULL THEN
        RAISE EXCEPTION 'No autenticado';
    END IF;

    -- Devolver los usuarios solicitados
    RETURN QUERY
    SELECT au.id, au.email::TEXT
    FROM auth.users au
    WHERE au.id = ANY(user_ids);
END;
$$ LANGUAGE plpgsql;

-- Otorgar permisos para ejecutar la función
GRANT EXECUTE ON FUNCTION get_users_by_ids(UUID[]) TO authenticated;

COMMIT;

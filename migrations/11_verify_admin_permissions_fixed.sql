-- Script para verificar y corregir los permisos de administrador
BEGIN;

-- Verificar si existen roles de Admin sin todos los permisos necesarios
DO $$
DECLARE
    v_role_id UUID;
    v_tenant_id UUID;
    v_permissions JSONB;
    v_all_permissions JSONB := '["manage_tenant_users", "manage_roles", "create_ingredient", "read_ingredient", "update_ingredient", "delete_ingredient", "manage_ingredient_equivalencies", "create_recipe", "read_recipe", "update_recipe", "delete_recipe", "create_recipe_version", "view_scaled_recipe", "log_preparation", "view_preparation_logs"]'::jsonb;
BEGIN
    -- Recorrer todos los roles Admin
    FOR v_role_id, v_tenant_id, v_permissions IN
        SELECT id, tenant_id, permissions
        FROM roles
        WHERE name = 'Admin'
    LOOP
        -- Verificar si el rol Admin tiene todos los permisos necesarios
        IF NOT (v_permissions @> v_all_permissions) THEN
            RAISE NOTICE 'Corrigiendo permisos para rol Admin en tenant %', v_tenant_id;
            
            -- Actualizar los permisos del rol Admin
            UPDATE roles
            SET permissions = v_all_permissions
            WHERE id = v_role_id;
        END IF;
    END LOOP;
END $$;

-- Verificar si hay tenants sin rol Admin
DO $$
DECLARE
    v_tenant_id UUID;
    v_has_admin BOOLEAN;
    v_all_permissions JSONB := '["manage_tenant_users", "manage_roles", "create_ingredient", "read_ingredient", "update_ingredient", "delete_ingredient", "manage_ingredient_equivalencies", "create_recipe", "read_recipe", "update_recipe", "delete_recipe", "create_recipe_version", "view_scaled_recipe", "log_preparation", "view_preparation_logs"]'::jsonb;
    v_role_id UUID;
BEGIN
    -- Recorrer todos los tenants
    FOR v_tenant_id IN
        SELECT id
        FROM tenants
    LOOP
        -- Verificar si el tenant tiene un rol Admin
        SELECT EXISTS (
            SELECT 1
            FROM roles
            WHERE tenant_id = v_tenant_id
            AND name = 'Admin'
        ) INTO v_has_admin;
        
        IF NOT v_has_admin THEN
            RAISE NOTICE 'Creando rol Admin para tenant %', v_tenant_id;
            
            -- Crear rol Admin para el tenant
            INSERT INTO roles (tenant_id, name, permissions)
            VALUES (v_tenant_id, 'Admin', v_all_permissions)
            RETURNING id INTO v_role_id;
            
            -- Asignar el rol Admin al propietario del tenant
            INSERT INTO tenant_users (tenant_id, user_id, role_id)
            SELECT v_tenant_id, owner_user_id, v_role_id
            FROM tenants
            WHERE id = v_tenant_id
            AND owner_user_id IS NOT NULL
            AND NOT EXISTS (
                SELECT 1
                FROM tenant_users
                WHERE tenant_id = v_tenant_id
                AND user_id = tenants.owner_user_id
            );
        END IF;
    END LOOP;
END $$;

-- Verificar si las funciones de seguridad existen y son correctas
DO $$
BEGIN
    -- Verificar si la función is_tenant_admin existe
    IF NOT EXISTS (
        SELECT 1
        FROM pg_proc
        WHERE proname = 'is_tenant_admin'
    ) THEN
        RAISE NOTICE 'Creando función is_tenant_admin';
        
        -- Crear función is_tenant_admin fuera del bloque DO
        EXECUTE $func$
        CREATE OR REPLACE FUNCTION is_tenant_admin(tenant_id uuid)
        RETURNS boolean AS $inner$
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
        $inner$ LANGUAGE plpgsql SECURITY DEFINER;
        $func$;
    END IF;
    
    -- Verificar si la función is_tenant_member existe
    IF NOT EXISTS (
        SELECT 1
        FROM pg_proc
        WHERE proname = 'is_tenant_member'
    ) THEN
        RAISE NOTICE 'Creando función is_tenant_member';
        
        -- Crear función is_tenant_member fuera del bloque DO
        EXECUTE $func$
        CREATE OR REPLACE FUNCTION is_tenant_member(tenant_id uuid)
        RETURNS boolean AS $inner$
        BEGIN
          RETURN EXISTS (
            SELECT 1
            FROM tenant_users
            WHERE tenant_id = tenant_id
            AND user_id = auth.uid()
          );
        END;
        $inner$ LANGUAGE plpgsql SECURITY DEFINER;
        $func$;
    END IF;
    
    -- Verificar si la función is_tenant_owner existe
    IF NOT EXISTS (
        SELECT 1
        FROM pg_proc
        WHERE proname = 'is_tenant_owner'
    ) THEN
        RAISE NOTICE 'Creando función is_tenant_owner';
        
        -- Crear función is_tenant_owner fuera del bloque DO
        EXECUTE $func$
        CREATE OR REPLACE FUNCTION is_tenant_owner(tenant_id uuid)
        RETURNS boolean AS $inner$
        BEGIN
          RETURN EXISTS (
            SELECT 1
            FROM tenants
            WHERE id = tenant_id
            AND owner_user_id = auth.uid()
          );
        END;
        $inner$ LANGUAGE plpgsql SECURITY DEFINER;
        $func$;
    END IF;
    
    -- Verificar si la función check_user_permission existe
    IF NOT EXISTS (
        SELECT 1
        FROM pg_proc
        WHERE proname = 'check_user_permission'
    ) THEN
        RAISE NOTICE 'Creando función check_user_permission';
        
        -- Crear función check_user_permission fuera del bloque DO
        EXECUTE $func$
        CREATE OR REPLACE FUNCTION check_user_permission(
            p_tenant_id UUID,
            p_permission TEXT
        ) RETURNS BOOLEAN AS $inner$
        DECLARE
            v_has_permission BOOLEAN;
        BEGIN
            SELECT EXISTS (
                SELECT 1
                FROM tenant_users tu
                JOIN roles r ON tu.role_id = r.id
                WHERE tu.tenant_id = p_tenant_id
                AND tu.user_id = auth.uid()
                AND r.permissions ? p_permission
            ) INTO v_has_permission;
            
            RETURN v_has_permission;
        END;
        $inner$ LANGUAGE plpgsql SECURITY DEFINER;
        $func$;
    END IF;
END $$;

COMMIT;

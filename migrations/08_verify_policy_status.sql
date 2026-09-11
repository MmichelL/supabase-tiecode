-- Script para verificar el estado de las políticas
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

-- Verificar las funciones existentes
SELECT 
    proname, 
    prosrc
FROM 
    pg_proc
WHERE 
    proname IN ('is_tenant_admin', 'is_tenant_member', 'is_tenant_owner')
    AND pronamespace = (SELECT oid FROM pg_namespace WHERE nspname = 'public');

-- Verificar los tenants existentes
SELECT 
    id, 
    name, 
    owner_user_id
FROM 
    tenants;

-- Verificar los usuarios de tenants existentes
SELECT  
    tu.tenant_id, 
    t.name AS tenant_name, 
    tu.user_id, 
    tu.role_id, 
    r.name AS role_name
FROM 
    tenant_users tu
JOIN 
    tenants t ON tu.tenant_id = t.id
JOIN 
    roles r ON tu.role_id = r.id;

-- Verificar los roles existentes
SELECT 
    id, 
    tenant_id, 
    name
FROM 
    roles;

-- Confirmar la transacción
COMMIT;

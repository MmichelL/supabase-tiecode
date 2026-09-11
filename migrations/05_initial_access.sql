-- Script para permitir el acceso inicial a los tenants y roles
BEGIN;

-- Crear un tenant de prueba si no existe ninguno
INSERT INTO tenants (name, owner_user_id)
SELECT 'Mi Negocio', auth.uid()
WHERE NOT EXISTS (
    SELECT 1 FROM tenants WHERE owner_user_id = auth.uid()
);

-- Asegurarse de que el usuario actual tenga acceso al tenant
-- (esto debería ocurrir automáticamente por el trigger, pero lo hacemos por si acaso)
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

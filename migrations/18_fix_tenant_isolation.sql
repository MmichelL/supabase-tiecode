-- =============================================================================
-- 18 - Cierre del aislamiento multi-tenant y del RBAC en base de datos
-- =============================================================================
--
-- Corrige cinco defectos que permitían acceso cruzado entre negocios:
--
--   C-1  tenant_user_insert exigía solo `user_id = auth.uid()`, así que
--        cualquier usuario autenticado podía insertarse a sí mismo en el
--        tenant de otro y quedar habilitado por las políticas de lectura.
--   C-2  tenant_user_update permitía al usuario editar su propia fila y
--        cambiar su role_id al rol Admin del tenant. Sin WITH CHECK.
--   C-3  get_users_by_ids es SECURITY DEFINER sobre auth.users y solo
--        comprobaba que hubiera sesión: cualquiera podía leer el email y el
--        last_sign_in_at de cualquier UUID de la plataforma.
--   C-4  Las políticas `*_tenant_access` se crearon sin cláusula FOR, así que
--        aplicaban a ALL. Al combinarse por OR con las políticas de escritura
--        basadas en permisos, anulaban la comprobación de permisos. Además
--        siete tablas nunca tuvieron políticas de escritura.
--   C-5  is_tenant_admin / is_tenant_member declaraban el parámetro con el
--        mismo nombre que la columna (`tenant_id = tenant_id`), lo que en
--        PL/pgSQL es referencia ambigua. Ninguna de las dos era fiable.
--
-- Además, todas las funciones SECURITY DEFINER fijan search_path, que es el
-- aviso `function_search_path_mutable` del linter de Supabase.
--
-- Idempotente: puede aplicarse más de una vez sin efectos adicionales.
-- =============================================================================

BEGIN;

-- CREATE OR REPLACE no permite renombrar parámetros: estas funciones se crearon
-- con el parámetro `tenant_id` y ahora se llaman `p_tenant_id`. Hay que dropear
-- primero (las políticas que las usan se recrean más abajo).
DROP FUNCTION IF EXISTS is_tenant_admin(uuid) CASCADE;
DROP FUNCTION IF EXISTS is_tenant_member(uuid) CASCADE;
DROP FUNCTION IF EXISTS is_tenant_owner(uuid) CASCADE;
DROP FUNCTION IF EXISTS check_user_permission(uuid, text) CASCADE;
DROP FUNCTION IF EXISTS can_write(uuid, text) CASCADE;
DROP FUNCTION IF EXISTS get_users_by_ids(uuid[]) CASCADE;
DROP FUNCTION IF EXISTS get_tenant_users(uuid) CASCADE;

-- -----------------------------------------------------------------------------
-- 0. Verificación previa: coherencia de rol y tenant
-- -----------------------------------------------------------------------------
-- La FK compuesta del paso 3 falla si ya existen filas donde el rol asignado
-- pertenece a otro tenant. Se aborta con un mensaje explícito en vez de dejar
-- que el ALTER falle con un error opaco.
DO $$
DECLARE
    v_offending INTEGER;
BEGIN
    SELECT COUNT(*) INTO v_offending
    FROM tenant_users tu
    JOIN roles r ON r.id = tu.role_id
    WHERE r.tenant_id <> tu.tenant_id;

    IF v_offending > 0 THEN
        RAISE EXCEPTION
            'Hay % fila(s) en tenant_users cuyo role_id pertenece a otro tenant. '
            'Corrígelas antes de aplicar esta migración: '
            'SELECT tu.* FROM tenant_users tu JOIN roles r ON r.id = tu.role_id '
            'WHERE r.tenant_id <> tu.tenant_id;', v_offending;
    END IF;
END $$;

-- -----------------------------------------------------------------------------
-- 1. Funciones auxiliares de seguridad (C-5 y search_path)
-- -----------------------------------------------------------------------------
-- Los parámetros se prefijan con p_ para que no puedan confundirse con una
-- columna. Se marcan STABLE porque solo leen.

CREATE OR REPLACE FUNCTION is_tenant_admin(p_tenant_id uuid)
RETURNS boolean
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
BEGIN
  RETURN EXISTS (
    SELECT 1
    FROM tenant_users tu
    JOIN roles r ON r.id = tu.role_id
    WHERE tu.tenant_id = p_tenant_id
      AND tu.user_id = auth.uid()
      AND r.name = 'Admin'
  );
END;
$$;

CREATE OR REPLACE FUNCTION is_tenant_member(p_tenant_id uuid)
RETURNS boolean
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
BEGIN
  RETURN EXISTS (
    SELECT 1
    FROM tenant_users tu
    WHERE tu.tenant_id = p_tenant_id
      AND tu.user_id = auth.uid()
  );
END;
$$;

CREATE OR REPLACE FUNCTION is_tenant_owner(p_tenant_id uuid)
RETURNS boolean
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
BEGIN
  RETURN EXISTS (
    SELECT 1
    FROM tenants t
    WHERE t.id = p_tenant_id
      AND t.owner_user_id = auth.uid()
  );
END;
$$;

CREATE OR REPLACE FUNCTION check_user_permission(p_tenant_id uuid, p_permission text)
RETURNS boolean
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
BEGIN
  RETURN EXISTS (
    SELECT 1
    FROM tenant_users tu
    JOIN roles r ON r.id = tu.role_id
    WHERE tu.tenant_id = p_tenant_id
      AND tu.user_id = auth.uid()
      AND r.permissions ? p_permission
  );
END;
$$;

-- Atajo usado por todas las políticas de escritura: el permiso explícito o el
-- rol Admin. Refleja la regla que ya aplica el cliente en usePermissions.
CREATE OR REPLACE FUNCTION can_write(p_tenant_id uuid, p_permission text)
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
  SELECT check_user_permission(p_tenant_id, p_permission)
      OR is_tenant_admin(p_tenant_id);
$$;

-- -----------------------------------------------------------------------------
-- 2. Funciones que exponen datos de auth.users (C-3)
-- -----------------------------------------------------------------------------
-- get_users_by_ids solo devuelve usuarios que comparten al menos un tenant con
-- quien llama. Antes devolvía cualquier UUID de la plataforma.

CREATE OR REPLACE FUNCTION get_users_by_ids(user_ids uuid[])
RETURNS TABLE (
    id uuid,
    email text,
    created_at timestamptz,
    last_sign_in_at timestamptz
)
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
BEGIN
    IF auth.uid() IS NULL THEN
        RAISE EXCEPTION 'No autenticado';
    END IF;

    RETURN QUERY
    SELECT
        au.id,
        au.email::text,
        au.created_at,
        au.last_sign_in_at
    FROM auth.users au
    WHERE au.id = ANY(user_ids)
      -- Solo usuarios que comparten tenant con quien llama.
      AND EXISTS (
        SELECT 1
        FROM tenant_users tu_target
        JOIN tenant_users tu_caller
          ON tu_caller.tenant_id = tu_target.tenant_id
        WHERE tu_target.user_id = au.id
          AND tu_caller.user_id = auth.uid()
      );
END;
$$;

CREATE OR REPLACE FUNCTION get_tenant_users(p_tenant_id uuid)
RETURNS TABLE (
    user_id uuid,
    email text,
    role_id uuid,
    role_name text,
    joined_at timestamptz
)
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
BEGIN
    IF auth.uid() IS NULL THEN
        RAISE EXCEPTION 'No autenticado';
    END IF;

    IF NOT is_tenant_member(p_tenant_id) THEN
        RAISE EXCEPTION 'No tienes acceso a este tenant';
    END IF;

    RETURN QUERY
    SELECT
        tu.user_id,
        au.email::text,
        tu.role_id,
        r.name AS role_name,
        tu.joined_at
    FROM tenant_users tu
    JOIN roles r ON r.id = tu.role_id
    JOIN auth.users au ON au.id = tu.user_id
    WHERE tu.tenant_id = p_tenant_id;
END;
$$;

GRANT EXECUTE ON FUNCTION get_users_by_ids(uuid[]) TO authenticated;
GRANT EXECUTE ON FUNCTION get_tenant_users(uuid) TO authenticated;

-- -----------------------------------------------------------------------------
-- 3. Integridad: el rol asignado debe pertenecer al mismo tenant
-- -----------------------------------------------------------------------------
-- Sin esto, un usuario podía referenciar el rol 'Admin' de su propio tenant
-- desde una fila apuntando al tenant de otro, y is_tenant_admin daba verdadero.

DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_constraint WHERE conname = 'roles_id_tenant_unique'
    ) THEN
        ALTER TABLE roles ADD CONSTRAINT roles_id_tenant_unique UNIQUE (id, tenant_id);
    END IF;

    IF NOT EXISTS (
        SELECT 1 FROM pg_constraint WHERE conname = 'tenant_users_role_same_tenant'
    ) THEN
        ALTER TABLE tenant_users
            ADD CONSTRAINT tenant_users_role_same_tenant
            FOREIGN KEY (role_id, tenant_id) REFERENCES roles (id, tenant_id);
    END IF;
END $$;

-- -----------------------------------------------------------------------------
-- 4. Políticas de tenant_users (C-1 y C-2)
-- -----------------------------------------------------------------------------

DROP POLICY IF EXISTS tenant_user_tenant_access ON tenant_users;
DROP POLICY IF EXISTS tenant_user_self_access   ON tenant_users;
DROP POLICY IF EXISTS tenant_user_admin_access  ON tenant_users;
DROP POLICY IF EXISTS tenant_user_read          ON tenant_users;
DROP POLICY IF EXISTS tenant_user_insert        ON tenant_users;
DROP POLICY IF EXISTS tenant_user_update        ON tenant_users;
DROP POLICY IF EXISTS tenant_user_delete        ON tenant_users;

-- Lectura: miembros del mismo tenant.
CREATE POLICY tenant_user_read ON tenant_users
    FOR SELECT
    USING (is_tenant_member(tenant_id));

-- Alta: SOLO un administrador del tenant destino. El alta propia se elimina;
-- entrar a un negocio pasa por invitación, no por INSERT desde el navegador.
CREATE POLICY tenant_user_insert ON tenant_users
    FOR INSERT
    WITH CHECK (is_tenant_admin(tenant_id));

-- Cambio de rol: solo administradores, y el resultado tiene que seguir siendo
-- del mismo tenant (WITH CHECK, que antes no existía).
CREATE POLICY tenant_user_update ON tenant_users
    FOR UPDATE
    USING (is_tenant_admin(tenant_id))
    WITH CHECK (is_tenant_admin(tenant_id));

-- Baja: un administrador, o el propio usuario abandonando el negocio.
CREATE POLICY tenant_user_delete ON tenant_users
    FOR DELETE
    USING (is_tenant_admin(tenant_id) OR user_id = auth.uid());

-- -----------------------------------------------------------------------------
-- 5. Políticas de tenants y roles
-- -----------------------------------------------------------------------------

DROP POLICY IF EXISTS tenant_user_access   ON tenants;
DROP POLICY IF EXISTS tenant_owner_access  ON tenants;
DROP POLICY IF EXISTS tenant_member_access ON tenants;
DROP POLICY IF EXISTS tenant_read          ON tenants;
DROP POLICY IF EXISTS tenant_insert        ON tenants;
DROP POLICY IF EXISTS tenant_update        ON tenants;
DROP POLICY IF EXISTS tenant_delete        ON tenants;

CREATE POLICY tenant_read ON tenants
    FOR SELECT
    USING (owner_user_id = auth.uid() OR is_tenant_member(id));

CREATE POLICY tenant_insert ON tenants
    FOR INSERT
    WITH CHECK (owner_user_id = auth.uid());

CREATE POLICY tenant_update ON tenants
    FOR UPDATE
    USING (owner_user_id = auth.uid() OR is_tenant_admin(id))
    WITH CHECK (owner_user_id = auth.uid() OR is_tenant_admin(id));

CREATE POLICY tenant_delete ON tenants
    FOR DELETE
    USING (owner_user_id = auth.uid());

DROP POLICY IF EXISTS role_tenant_access ON roles;
DROP POLICY IF EXISTS role_admin_access  ON roles;
DROP POLICY IF EXISTS role_self_access   ON roles;
DROP POLICY IF EXISTS role_read          ON roles;
DROP POLICY IF EXISTS role_insert        ON roles;
DROP POLICY IF EXISTS role_update        ON roles;
DROP POLICY IF EXISTS role_delete        ON roles;

CREATE POLICY role_read ON roles
    FOR SELECT
    USING (is_tenant_member(tenant_id));

CREATE POLICY role_insert ON roles
    FOR INSERT
    WITH CHECK (can_write(tenant_id, 'manage_roles'));

CREATE POLICY role_update ON roles
    FOR UPDATE
    USING (can_write(tenant_id, 'manage_roles'))
    WITH CHECK (can_write(tenant_id, 'manage_roles'));

-- El rol Admin no se puede borrar: es el que sostiene is_tenant_admin.
CREATE POLICY role_delete ON roles
    FOR DELETE
    USING (can_write(tenant_id, 'manage_roles') AND name <> 'Admin');

-- -----------------------------------------------------------------------------
-- 6. Tablas de datos: lectura por pertenencia, escritura por permiso (C-4)
-- -----------------------------------------------------------------------------
-- Las políticas antiguas se crearon sin FOR, así que cubrían ALL y, al ser
-- permisivas, se combinaban por OR con las de escritura y las anulaban.

DROP POLICY IF EXISTS ingredient_tenant_access ON ingredients;
DROP POLICY IF EXISTS ingredient_read          ON ingredients;
DROP POLICY IF EXISTS ingredient_insert        ON ingredients;
DROP POLICY IF EXISTS ingredient_update        ON ingredients;
DROP POLICY IF EXISTS ingredient_delete        ON ingredients;

CREATE POLICY ingredient_read ON ingredients
    FOR SELECT USING (is_tenant_member(tenant_id));
CREATE POLICY ingredient_insert ON ingredients
    FOR INSERT WITH CHECK (can_write(tenant_id, 'create_ingredient'));
CREATE POLICY ingredient_update ON ingredients
    FOR UPDATE USING (can_write(tenant_id, 'update_ingredient'))
               WITH CHECK (can_write(tenant_id, 'update_ingredient'));
CREATE POLICY ingredient_delete ON ingredients
    FOR DELETE USING (can_write(tenant_id, 'delete_ingredient'));

DROP POLICY IF EXISTS ingredient_equivalency_tenant_access ON ingredient_equivalencies;
DROP POLICY IF EXISTS ingredient_equivalency_read          ON ingredient_equivalencies;
DROP POLICY IF EXISTS ingredient_equivalency_insert        ON ingredient_equivalencies;
DROP POLICY IF EXISTS ingredient_equivalency_update        ON ingredient_equivalencies;
DROP POLICY IF EXISTS ingredient_equivalency_delete        ON ingredient_equivalencies;

CREATE POLICY ingredient_equivalency_read ON ingredient_equivalencies
    FOR SELECT USING (is_tenant_member(tenant_id));
CREATE POLICY ingredient_equivalency_insert ON ingredient_equivalencies
    FOR INSERT WITH CHECK (can_write(tenant_id, 'manage_ingredient_equivalencies'));
CREATE POLICY ingredient_equivalency_update ON ingredient_equivalencies
    FOR UPDATE USING (can_write(tenant_id, 'manage_ingredient_equivalencies'))
               WITH CHECK (can_write(tenant_id, 'manage_ingredient_equivalencies'));
CREATE POLICY ingredient_equivalency_delete ON ingredient_equivalencies
    FOR DELETE USING (can_write(tenant_id, 'manage_ingredient_equivalencies'));

DROP POLICY IF EXISTS recipe_tenant_access ON recipes;
DROP POLICY IF EXISTS recipe_read          ON recipes;
DROP POLICY IF EXISTS recipe_insert        ON recipes;
DROP POLICY IF EXISTS recipe_update        ON recipes;
DROP POLICY IF EXISTS recipe_delete        ON recipes;

CREATE POLICY recipe_read ON recipes
    FOR SELECT USING (is_tenant_member(tenant_id));
CREATE POLICY recipe_insert ON recipes
    FOR INSERT WITH CHECK (can_write(tenant_id, 'create_recipe'));
CREATE POLICY recipe_update ON recipes
    FOR UPDATE USING (can_write(tenant_id, 'update_recipe'))
               WITH CHECK (can_write(tenant_id, 'update_recipe'));
CREATE POLICY recipe_delete ON recipes
    FOR DELETE USING (can_write(tenant_id, 'delete_recipe'));

DROP POLICY IF EXISTS recipe_version_tenant_access ON recipe_versions;
DROP POLICY IF EXISTS recipe_version_read          ON recipe_versions;
DROP POLICY IF EXISTS recipe_version_insert        ON recipe_versions;
DROP POLICY IF EXISTS recipe_version_update        ON recipe_versions;
DROP POLICY IF EXISTS recipe_version_delete        ON recipe_versions;

CREATE POLICY recipe_version_read ON recipe_versions
    FOR SELECT USING (is_tenant_member(tenant_id));
CREATE POLICY recipe_version_insert ON recipe_versions
    FOR INSERT WITH CHECK (can_write(tenant_id, 'create_recipe_version'));
CREATE POLICY recipe_version_update ON recipe_versions
    FOR UPDATE USING (can_write(tenant_id, 'update_recipe'))
               WITH CHECK (can_write(tenant_id, 'update_recipe'));
CREATE POLICY recipe_version_delete ON recipe_versions
    FOR DELETE USING (can_write(tenant_id, 'delete_recipe'));

DROP POLICY IF EXISTS recipe_version_ingredient_tenant_access ON recipe_version_ingredients;
DROP POLICY IF EXISTS recipe_version_ingredient_read          ON recipe_version_ingredients;
DROP POLICY IF EXISTS recipe_version_ingredient_insert        ON recipe_version_ingredients;
DROP POLICY IF EXISTS recipe_version_ingredient_update        ON recipe_version_ingredients;
DROP POLICY IF EXISTS recipe_version_ingredient_delete        ON recipe_version_ingredients;

CREATE POLICY recipe_version_ingredient_read ON recipe_version_ingredients
    FOR SELECT USING (is_tenant_member(tenant_id));
CREATE POLICY recipe_version_ingredient_insert ON recipe_version_ingredients
    FOR INSERT WITH CHECK (can_write(tenant_id, 'create_recipe_version'));
CREATE POLICY recipe_version_ingredient_update ON recipe_version_ingredients
    FOR UPDATE USING (can_write(tenant_id, 'update_recipe'))
               WITH CHECK (can_write(tenant_id, 'update_recipe'));
CREATE POLICY recipe_version_ingredient_delete ON recipe_version_ingredients
    FOR DELETE USING (can_write(tenant_id, 'delete_recipe'));

DROP POLICY IF EXISTS recipe_version_step_tenant_access ON recipe_version_steps;
DROP POLICY IF EXISTS recipe_version_step_read          ON recipe_version_steps;
DROP POLICY IF EXISTS recipe_version_step_insert        ON recipe_version_steps;
DROP POLICY IF EXISTS recipe_version_step_update        ON recipe_version_steps;
DROP POLICY IF EXISTS recipe_version_step_delete        ON recipe_version_steps;

CREATE POLICY recipe_version_step_read ON recipe_version_steps
    FOR SELECT USING (is_tenant_member(tenant_id));
CREATE POLICY recipe_version_step_insert ON recipe_version_steps
    FOR INSERT WITH CHECK (can_write(tenant_id, 'create_recipe_version'));
CREATE POLICY recipe_version_step_update ON recipe_version_steps
    FOR UPDATE USING (can_write(tenant_id, 'update_recipe'))
               WITH CHECK (can_write(tenant_id, 'update_recipe'));
CREATE POLICY recipe_version_step_delete ON recipe_version_steps
    FOR DELETE USING (can_write(tenant_id, 'delete_recipe'));

DROP POLICY IF EXISTS preprocessing_ingredient_tenant_access ON preprocessing_ingredients;
DROP POLICY IF EXISTS preprocessing_ingredient_read          ON preprocessing_ingredients;
DROP POLICY IF EXISTS preprocessing_ingredient_insert        ON preprocessing_ingredients;
DROP POLICY IF EXISTS preprocessing_ingredient_update        ON preprocessing_ingredients;
DROP POLICY IF EXISTS preprocessing_ingredient_delete        ON preprocessing_ingredients;

CREATE POLICY preprocessing_ingredient_read ON preprocessing_ingredients
    FOR SELECT USING (is_tenant_member(tenant_id));
CREATE POLICY preprocessing_ingredient_insert ON preprocessing_ingredients
    FOR INSERT WITH CHECK (can_write(tenant_id, 'create_recipe_version'));
CREATE POLICY preprocessing_ingredient_update ON preprocessing_ingredients
    FOR UPDATE USING (can_write(tenant_id, 'update_recipe'))
               WITH CHECK (can_write(tenant_id, 'update_recipe'));
CREATE POLICY preprocessing_ingredient_delete ON preprocessing_ingredients
    FOR DELETE USING (can_write(tenant_id, 'delete_recipe'));

DROP POLICY IF EXISTS preparation_log_tenant_access ON preparation_logs;
DROP POLICY IF EXISTS preparation_log_read          ON preparation_logs;
DROP POLICY IF EXISTS preparation_log_insert        ON preparation_logs;
DROP POLICY IF EXISTS preparation_log_update        ON preparation_logs;
DROP POLICY IF EXISTS preparation_log_delete        ON preparation_logs;

CREATE POLICY preparation_log_read ON preparation_logs
    FOR SELECT USING (can_write(tenant_id, 'view_preparation_logs')
                      OR is_tenant_member(tenant_id));
CREATE POLICY preparation_log_insert ON preparation_logs
    FOR INSERT WITH CHECK (can_write(tenant_id, 'log_preparation')
                           AND user_id = auth.uid());
CREATE POLICY preparation_log_update ON preparation_logs
    FOR UPDATE USING (can_write(tenant_id, 'log_preparation'))
               WITH CHECK (can_write(tenant_id, 'log_preparation'));
CREATE POLICY preparation_log_delete ON preparation_logs
    FOR DELETE USING (can_write(tenant_id, 'log_preparation'));

-- preparation_log_adjustments no tiene tenant_id: se resuelve por su log.
DROP POLICY IF EXISTS preparation_log_adjustment_access ON preparation_log_adjustments;
DROP POLICY IF EXISTS preparation_log_adjustment_read   ON preparation_log_adjustments;
DROP POLICY IF EXISTS preparation_log_adjustment_write  ON preparation_log_adjustments;

CREATE POLICY preparation_log_adjustment_read ON preparation_log_adjustments
    FOR SELECT
    USING (EXISTS (
        SELECT 1 FROM preparation_logs pl
        WHERE pl.id = preparation_log_adjustments.preparation_log_id
          AND is_tenant_member(pl.tenant_id)
    ));

CREATE POLICY preparation_log_adjustment_insert ON preparation_log_adjustments
    FOR INSERT
    WITH CHECK (EXISTS (
        SELECT 1 FROM preparation_logs pl
        WHERE pl.id = preparation_log_adjustments.preparation_log_id
          AND can_write(pl.tenant_id, 'log_preparation')
    ));

CREATE POLICY preparation_log_adjustment_update ON preparation_log_adjustments
    FOR UPDATE
    USING (EXISTS (
        SELECT 1 FROM preparation_logs pl
        WHERE pl.id = preparation_log_adjustments.preparation_log_id
          AND can_write(pl.tenant_id, 'log_preparation')
    ));

CREATE POLICY preparation_log_adjustment_delete ON preparation_log_adjustments
    FOR DELETE
    USING (EXISTS (
        SELECT 1 FROM preparation_logs pl
        WHERE pl.id = preparation_log_adjustments.preparation_log_id
          AND can_write(pl.tenant_id, 'log_preparation')
    ));

-- -----------------------------------------------------------------------------
-- 7. Índices que sostienen las políticas
-- -----------------------------------------------------------------------------
-- is_tenant_member / is_tenant_admin se evalúan por fila en cada política.

CREATE INDEX IF NOT EXISTS idx_tenant_users_user_id   ON tenant_users (user_id);
CREATE INDEX IF NOT EXISTS idx_tenant_users_tenant_id ON tenant_users (tenant_id);
CREATE INDEX IF NOT EXISTS idx_roles_tenant_id        ON roles (tenant_id);
CREATE INDEX IF NOT EXISTS idx_recipes_tenant_id      ON recipes (tenant_id);
CREATE INDEX IF NOT EXISTS idx_ingredients_tenant_id  ON ingredients (tenant_id);
CREATE INDEX IF NOT EXISTS idx_recipe_versions_recipe_id ON recipe_versions (recipe_id);
CREATE INDEX IF NOT EXISTS idx_preparation_logs_tenant_id ON preparation_logs (tenant_id);

COMMIT;

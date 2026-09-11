-- Iniciar transacción
BEGIN;

-- Habilitar la extensión UUID
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";

-- Tabla de tenants (inquilinos)
CREATE TABLE IF NOT EXISTS tenants (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    name TEXT NOT NULL,
    created_at TIMESTAMPTZ DEFAULT now(),
    owner_user_id UUID REFERENCES auth.users(id) ON DELETE SET NULL
);

-- Tabla de roles (específicos por tenant)
CREATE TABLE IF NOT EXISTS roles (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    tenant_id UUID NOT NULL REFERENCES tenants(id) ON DELETE CASCADE,
    name TEXT NOT NULL,
    permissions JSONB NOT NULL,
    UNIQUE (tenant_id, name)
);

-- Tabla de relación entre tenants y usuarios
CREATE TABLE IF NOT EXISTS tenant_users (
    tenant_id UUID REFERENCES tenants(id) ON DELETE CASCADE,
    user_id UUID REFERENCES auth.users(id) ON DELETE CASCADE,
    role_id UUID NOT NULL REFERENCES roles(id) ON DELETE RESTRICT,
    joined_at TIMESTAMPTZ DEFAULT now(),
    PRIMARY KEY (tenant_id, user_id)
);

-- Tabla de ingredientes
CREATE TABLE IF NOT EXISTS ingredients (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    tenant_id UUID NOT NULL REFERENCES tenants(id) ON DELETE CASCADE,
    name TEXT NOT NULL,
    description TEXT,
    category TEXT,
    created_at TIMESTAMPTZ DEFAULT now(),
    created_by_user_id UUID REFERENCES auth.users(id) ON DELETE SET NULL,
    UNIQUE (tenant_id, name)
);

-- Tabla de equivalencias de ingredientes
CREATE TABLE IF NOT EXISTS ingredient_equivalencies (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    ingredient_id UUID NOT NULL REFERENCES ingredients(id) ON DELETE CASCADE,
    tenant_id UUID NOT NULL REFERENCES tenants(id) ON DELETE CASCADE,
    volume_unit TEXT NOT NULL CHECK (volume_unit IN ('cup', 'tbsp', 'tsp')),
    volume_amount NUMERIC DEFAULT 1,
    weight_unit TEXT NOT NULL CHECK (weight_unit IN ('g', 'oz')),
    weight_amount NUMERIC NOT NULL,
    created_at TIMESTAMPTZ DEFAULT now(),
    UNIQUE (ingredient_id, volume_unit, volume_amount)
);

-- Tabla de recetas
CREATE TABLE IF NOT EXISTS recipes (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    tenant_id UUID NOT NULL REFERENCES tenants(id) ON DELETE CASCADE,
    name TEXT NOT NULL,
    description TEXT,
    category TEXT,
    base_yield_amount NUMERIC NOT NULL,
    base_yield_unit TEXT NOT NULL,
    created_at TIMESTAMPTZ DEFAULT now(),
    created_by_user_id UUID REFERENCES auth.users(id) ON DELETE SET NULL,
    current_version_id UUID,
    UNIQUE (tenant_id, name)
);

-- Tabla de versiones de recetas
CREATE TABLE IF NOT EXISTS recipe_versions (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    recipe_id UUID NOT NULL REFERENCES recipes(id) ON DELETE CASCADE,
    tenant_id UUID NOT NULL REFERENCES tenants(id) ON DELETE CASCADE,
    version_number INTEGER NOT NULL,
    notes TEXT,
    created_at TIMESTAMPTZ DEFAULT now(),
    created_by_user_id UUID REFERENCES auth.users(id) ON DELETE SET NULL,
    UNIQUE (recipe_id, version_number)
);

-- Actualizar la referencia en la tabla de recetas
ALTER TABLE recipes ADD CONSTRAINT fk_current_version
    FOREIGN KEY (current_version_id) REFERENCES recipe_versions(id) ON DELETE SET NULL;

-- Tabla de ingredientes de versiones de recetas
CREATE TABLE IF NOT EXISTS recipe_version_ingredients (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    recipe_version_id UUID NOT NULL REFERENCES recipe_versions(id) ON DELETE CASCADE,
    tenant_id UUID NOT NULL REFERENCES tenants(id) ON DELETE CASCADE,
    ingredient_id UUID REFERENCES ingredients(id) ON DELETE SET NULL,
    ingredient_name_snapshot TEXT NOT NULL,
    quantity NUMERIC NOT NULL,
    unit TEXT NOT NULL,
    preprocessing_description TEXT,
    preprocessing_output TEXT,
    order_index INTEGER NOT NULL,
    UNIQUE (recipe_version_id, order_index)
);

-- Tabla de pasos de versiones de recetas
CREATE TABLE IF NOT EXISTS recipe_version_steps (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    recipe_version_id UUID NOT NULL REFERENCES recipe_versions(id) ON DELETE CASCADE,
    tenant_id UUID NOT NULL REFERENCES tenants(id) ON DELETE CASCADE,
    description TEXT NOT NULL,
    order_index INTEGER NOT NULL,
    time_minutes INTEGER,
    temperature_celsius INTEGER,
    UNIQUE (recipe_version_id, order_index)
);

-- Tabla de ingredientes de preprocesamiento
CREATE TABLE IF NOT EXISTS preprocessing_ingredients (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    recipe_version_ingredient_id UUID NOT NULL REFERENCES recipe_version_ingredients(id) ON DELETE CASCADE,
    tenant_id UUID NOT NULL REFERENCES tenants(id) ON DELETE CASCADE,
    ingredient_id UUID REFERENCES ingredients(id) ON DELETE SET NULL,
    ingredient_name_snapshot TEXT NOT NULL,
    quantity NUMERIC NOT NULL,
    unit TEXT NOT NULL,
    order_index INTEGER NOT NULL,
    UNIQUE (recipe_version_ingredient_id, order_index)
);

-- Tabla de logs de preparación
CREATE TABLE IF NOT EXISTS preparation_logs (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    tenant_id UUID NOT NULL REFERENCES tenants(id) ON DELETE CASCADE,
    recipe_version_id UUID NOT NULL REFERENCES recipe_versions(id) ON DELETE CASCADE,
    user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    preparation_date TIMESTAMPTZ DEFAULT now(),
    target_yield_amount NUMERIC NOT NULL,
    target_yield_unit TEXT NOT NULL,
    actual_yield_amount NUMERIC,
    feedback_notes TEXT,
    rating INTEGER CHECK (rating BETWEEN 1 AND 5),
    photo_url TEXT,
    cooking_time_minutes INTEGER,
    oven_temperature_celsius INTEGER
);

-- Tabla de ajustes de logs de preparación
CREATE TABLE IF NOT EXISTS preparation_log_adjustments (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    preparation_log_id UUID NOT NULL REFERENCES preparation_logs(id) ON DELETE CASCADE,
    recipe_ingredient_link_id UUID REFERENCES recipe_version_ingredients(id) ON DELETE SET NULL,
    ingredient_name_snapshot TEXT NOT NULL,
    original_scaled_quantity NUMERIC NOT NULL,
    original_scaled_unit TEXT NOT NULL,
    adjusted_quantity NUMERIC NOT NULL,
    adjusted_unit TEXT NOT NULL,
    reason TEXT
);

-- Configurar políticas de seguridad (RLS)
-- Habilitar RLS en todas las tablas
ALTER TABLE tenants ENABLE ROW LEVEL SECURITY;
ALTER TABLE roles ENABLE ROW LEVEL SECURITY;
ALTER TABLE tenant_users ENABLE ROW LEVEL SECURITY;
ALTER TABLE ingredients ENABLE ROW LEVEL SECURITY;
ALTER TABLE ingredient_equivalencies ENABLE ROW LEVEL SECURITY;
ALTER TABLE recipes ENABLE ROW LEVEL SECURITY;
ALTER TABLE recipe_versions ENABLE ROW LEVEL SECURITY;
ALTER TABLE recipe_version_ingredients ENABLE ROW LEVEL SECURITY;
ALTER TABLE recipe_version_steps ENABLE ROW LEVEL SECURITY;
ALTER TABLE preprocessing_ingredients ENABLE ROW LEVEL SECURITY;
ALTER TABLE preparation_logs ENABLE ROW LEVEL SECURITY;
ALTER TABLE preparation_log_adjustments ENABLE ROW LEVEL SECURITY;

-- Crear políticas para cada tabla
-- Política para tenants: los usuarios solo pueden ver los tenants a los que pertenecen
CREATE POLICY tenant_user_access ON tenants
    USING (id IN (
        SELECT tenant_id FROM tenant_users WHERE user_id = auth.uid()
    ));

-- Política para roles: los usuarios solo pueden ver los roles de los tenants a los que pertenecen
CREATE POLICY role_tenant_access ON roles
    USING (tenant_id IN (
        SELECT tenant_id FROM tenant_users WHERE user_id = auth.uid()
    ));

-- Política para tenant_users: los usuarios solo pueden ver las relaciones de los tenants a los que pertenecen
CREATE POLICY tenant_user_tenant_access ON tenant_users
    USING (tenant_id IN (
        SELECT tenant_id FROM tenant_users WHERE user_id = auth.uid()
    ));

-- Política para ingredients: los usuarios solo pueden ver los ingredientes de los tenants a los que pertenecen
CREATE POLICY ingredient_tenant_access ON ingredients
    USING (tenant_id IN (
        SELECT tenant_id FROM tenant_users WHERE user_id = auth.uid()
    ));

-- Política para ingredient_equivalencies: los usuarios solo pueden ver las equivalencias de los tenants a los que pertenecen
CREATE POLICY ingredient_equivalency_tenant_access ON ingredient_equivalencies
    USING (tenant_id IN (
        SELECT tenant_id FROM tenant_users WHERE user_id = auth.uid()
    ));

-- Política para recipes: los usuarios solo pueden ver las recetas de los tenants a los que pertenecen
CREATE POLICY recipe_tenant_access ON recipes
    USING (tenant_id IN (
        SELECT tenant_id FROM tenant_users WHERE user_id = auth.uid()
    ));

-- Política para recipe_versions: los usuarios solo pueden ver las versiones de recetas de los tenants a los que pertenecen
CREATE POLICY recipe_version_tenant_access ON recipe_versions
    USING (tenant_id IN (
        SELECT tenant_id FROM tenant_users WHERE user_id = auth.uid()
    ));

-- Política para recipe_version_ingredients: los usuarios solo pueden ver los ingredientes de versiones de recetas de los tenants a los que pertenecen
CREATE POLICY recipe_version_ingredient_tenant_access ON recipe_version_ingredients
    USING (tenant_id IN (
        SELECT tenant_id FROM tenant_users WHERE user_id = auth.uid()
    ));

-- Política para recipe_version_steps: los usuarios solo pueden ver los pasos de versiones de recetas de los tenants a los que pertenecen
CREATE POLICY recipe_version_step_tenant_access ON recipe_version_steps
    USING (tenant_id IN (
        SELECT tenant_id FROM tenant_users WHERE user_id = auth.uid()
    ));

-- Política para preprocessing_ingredients: los usuarios solo pueden ver los ingredientes de preprocesamiento de los tenants a los que pertenecen
CREATE POLICY preprocessing_ingredient_tenant_access ON preprocessing_ingredients
    USING (tenant_id IN (
        SELECT tenant_id FROM tenant_users WHERE user_id = auth.uid()
    ));

-- Política para preparation_logs: los usuarios solo pueden ver los logs de preparación de los tenants a los que pertenecen
CREATE POLICY preparation_log_tenant_access ON preparation_logs
    USING (tenant_id IN (
        SELECT tenant_id FROM tenant_users WHERE user_id = auth.uid()
    ));

-- Política para preparation_log_adjustments: los usuarios solo pueden ver los ajustes de logs de preparación de los logs a los que tienen acceso
CREATE POLICY preparation_log_adjustment_access ON preparation_log_adjustments
    USING (preparation_log_id IN (
        SELECT id FROM preparation_logs WHERE tenant_id IN (
            SELECT tenant_id FROM tenant_users WHERE user_id = auth.uid()
        )
    ));

-- Crear función para verificar permisos de usuario en un tenant
CREATE OR REPLACE FUNCTION check_user_permission(
    p_tenant_id UUID,
    p_permission TEXT
) RETURNS BOOLEAN AS $$
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
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Crear políticas de inserción, actualización y eliminación basadas en permisos
-- Ejemplo para ingredients
CREATE POLICY ingredient_insert ON ingredients
    FOR INSERT WITH CHECK (
        check_user_permission(tenant_id, 'create_ingredient')
    );

CREATE POLICY ingredient_update ON ingredients
    FOR UPDATE USING (
        check_user_permission(tenant_id, 'update_ingredient')
    );

CREATE POLICY ingredient_delete ON ingredients
    FOR DELETE USING (
        check_user_permission(tenant_id, 'delete_ingredient')
    );

-- Ejemplo para recipes
CREATE POLICY recipe_insert ON recipes
    FOR INSERT WITH CHECK (
        check_user_permission(tenant_id, 'create_recipe')
    );

CREATE POLICY recipe_update ON recipes
    FOR UPDATE USING (
        check_user_permission(tenant_id, 'update_recipe')
    );

CREATE POLICY recipe_delete ON recipes
    FOR DELETE USING (
        check_user_permission(tenant_id, 'delete_recipe')
    );

-- Crear un rol predeterminado de administrador para nuevos tenants
CREATE OR REPLACE FUNCTION create_default_admin_role()
RETURNS TRIGGER AS $$
BEGIN
    INSERT INTO roles (tenant_id, name, permissions)
    VALUES (
        NEW.id,
        'Admin',
        '["manage_tenant_users", "manage_roles", "create_ingredient", "read_ingredient", "update_ingredient", "delete_ingredient", "manage_ingredient_equivalencies", "create_recipe", "read_recipe", "update_recipe", "delete_recipe", "create_recipe_version", "view_scaled_recipe", "log_preparation", "view_preparation_logs"]'::jsonb
    );
    RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

CREATE TRIGGER create_default_admin_role_trigger
AFTER INSERT ON tenants
FOR EACH ROW
EXECUTE FUNCTION create_default_admin_role();

-- Asignar automáticamente el rol de administrador al creador del tenant
CREATE OR REPLACE FUNCTION assign_admin_role_to_owner()
RETURNS TRIGGER AS $$
DECLARE
    v_role_id UUID;
BEGIN
    -- Solo si hay un owner_user_id
    IF NEW.owner_user_id IS NOT NULL THEN
        -- Obtener el ID del rol Admin
        SELECT id INTO v_role_id
        FROM roles
        WHERE tenant_id = NEW.id AND name = 'Admin'
        LIMIT 1;

        -- Insertar la relación tenant_user
        IF v_role_id IS NOT NULL THEN
            INSERT INTO tenant_users (tenant_id, user_id, role_id)
            VALUES (NEW.id, NEW.owner_user_id, v_role_id);
        END IF;
    END IF;

    RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

CREATE TRIGGER assign_admin_role_to_owner_trigger
AFTER INSERT ON tenants
FOR EACH ROW
EXECUTE FUNCTION assign_admin_role_to_owner();

-- Confirmar la transacción si todo ha ido bien
COMMIT;

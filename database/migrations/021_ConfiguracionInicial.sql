/*
    021_ConfiguracionInicial.sql — Configuración esencial de ShopCart.
    Ejecutar COMPLETO como un único lote, sin GO, en ShopCart con Auto-commit.
    No iniciar con transacciones abiertas o implícitas. No ejecutar parcialmente
    ni en paralelo con cambios administrativos que ignoren los bloqueos comunes.

    SHA-256: calcular los bytes del archivo FINAL aprobado mediante Get-FileHash.
    Suministrar 32 bytes binary/varbinary en la MISMA conexión de DataGrip,
    SESSION_CONTEXT(N'ShopCart.Migracion021.SHA256'); limpiar al terminar.
    No incrustar la huella: SQL valida su formato, el ejecutor verifica archivo/huella.
    Este archivo solo se prepara para revisión; no implica ejecución.

    Roles: IDs preferidos 1=Cliente, 2=Operador, 3=Administrador.
    Backend y SP resuelven por Nombre, no por un número fijo. Si un rol ya existe
    con nombre EXACTO compatible con backend, se conserva su ID y descripción.
    Si falta y el ID preferido está ocupado por otro rol, se aborta sin reasignar.
    Se rechazan variantes de mayúsculas, acentos o espacios de los tres nombres:
    SQL compara CI/AI, pero el backend valida literalmente Cliente/Operador/Administrador.

    Envíos de demostración: ESTANDAR Q25.0000, EXPRES Q45.0000,
    RETIRO_TIENDA Q0.0000; tarifa fija GTQ por pedido, con IVA incluido según 017.
    No representan cotizaciones de transportistas. Categorías: Electrónica, Ropa,
    Hogar y Accesorios. Nuevos registros activos; IDs IDENTITY asignados por SQL.

    Solo se insertan faltantes por código de envío o nombre de categoría/rol.
    Se conservan costos, descripciones, orden, fechas e IDs de registros existentes.
    Un código de envío con nombre distinto, el mismo nombre con otro código, o un
    registro inicial inactivo exige revisión manual y provoca rollback; no se reactiva.
    Categorías homónimas bajo la intercalación CI/AI se reutilizan si están activas
    y sin espacios exteriores; no se cambia su presentación.

    Dependencias administrativas y de auditoría:
    - SP_Catalogo_GuardarCategoria exige usuario Administrador con sesión vigente
      y controla su propia transacción; no sirve para el arranque sin usuarios.
      Este script es una migración administrativa autorizada con CONTROL, distinta
      del acceso de la API. No invoca SP de negocio ni crea sesiones/usuarios.
    - Registra SOLO las filas nuevas en EventosAuditoria con IdUsuarioActor NULL,
      JSON válido, fecha UTC y correlación común. No audita preservados como creados.
    - 020 agrupa Roles y MetodosEnvio como OTROS; sus eventos pueden consultarse
      por Entidad sin filtro de módulo. No se modifica ese contrato.
    - La cuenta SQL de servicio de privilegios mínimos y el primer administrador
      siguen siendo una configuración separada; no se crean ni conceden permisos aquí.
    - No se requieren exactamente 19 registros técnicos o 52 SP: se valida 020
      y se rechaza >=021. No se impone vacío a ninguna tabla de configuración.
    Datos, auditoría y registro de versión se confirman o revierten juntos.
    Las columnas IDENTITY pueden consumir números aun si una transacción revierte.
*/
IF DB_NAME() <> N'ShopCart'
    THROW 64000, N'021 solo puede ejecutarse en la base ShopCart.', 1;

IF @@TRANCOUNT <> 0 OR (2 & @@OPTIONS) = 2
    THROW 64001, N'Inicie con Auto-commit y sin transacciones abiertas o implícitas.', 1;

SET NOCOUNT ON;
SET XACT_ABORT ON;
-- Opciones de sesión consistentes con las migraciones anteriores.
SET ANSI_NULLS ON;
SET ANSI_PADDING ON;
SET ANSI_WARNINGS ON;
SET ARITHABORT ON;
SET CONCAT_NULL_YIELDS_NULL ON;
SET QUOTED_IDENTIFIER ON;
SET NUMERIC_ROUNDABORT OFF;

IF COALESCE(HAS_PERMS_BY_NAME(DB_NAME(), N'DATABASE', N'CONTROL'), 0) <> 1
    THROW 64002, N'Se requiere CONTROL sobre ShopCart para inspeccionar y crear el esquema.', 1;

IF NOT EXISTS (
    SELECT 1 FROM sys.databases
    WHERE database_id = DB_ID()
      AND collation_name = N'Latin1_General_100_CI_AI_SC'
      AND recovery_model_desc = N'SIMPLE'
      AND state_desc = N'ONLINE' AND user_access_desc = N'MULTI_USER'
      AND is_read_only = 0 AND source_database_id IS NULL
)
    THROW 64003, N'Las propiedades de ShopCart no coinciden con el arranque 001.', 1;

DECLARE @HuellaRecibida sql_variant = SESSION_CONTEXT(N'ShopCart.Migracion021.SHA256');
IF @HuellaRecibida IS NULL
   OR CONVERT(nvarchar(128), SQL_VARIANT_PROPERTY(@HuellaRecibida, 'BaseType')) NOT IN (N'binary', N'varbinary')
    THROW 64004, N'Suministre el SHA-256 real como valor binario en SESSION_CONTEXT antes de ejecutar 021.', 1;

DECLARE @SHA256 varbinary(max) = CONVERT(varbinary(max), @HuellaRecibida);
IF DATALENGTH(@SHA256) <> 32
    THROW 64005, N'La huella SHA-256 debe contener exactamente 32 bytes.', 1;

BEGIN TRY
    BEGIN TRANSACTION;

    -- Serializa ejecuciones que respeten este mismo recurso administrativo.
    DECLARE @ResultadoBloqueo int;
    EXEC @ResultadoBloqueo = sys.sp_getapplock
        @Resource = N'ShopCart.Migraciones',
        @LockMode = N'Exclusive',
        @LockOwner = N'Transaction',
        @LockTimeout = 0;
    IF @ResultadoBloqueo < 0
        THROW 64006, N'No se pudo obtener el bloqueo exclusivo de migraciones.', 1;

    DECLARE @IDVersiones int = OBJECT_ID(N'dbo.VersionesMigracion', N'U');
    IF @IDVersiones IS NULL
        THROW 64007, N'Falta la tabla técnica creada por 001. No se aplicará 021.', 1;

    -- Verifica el contrato utilizado para registrar la migración, no solo el nombre.
    IF EXISTS (
        SELECT 1
        FROM (VALUES
            (N'Version', N'int', 4, 10, 0),
            (N'NombreArchivo', N'nvarchar', 520, 0, 0),
            (N'SHA256', N'binary', 32, 0, 0),
            (N'FechaAplicacionUTC', N'datetime2', 8, 27, 7),
            (N'Ejecutor', N'nvarchar', 256, 0, 0)
        ) AS e(Nombre, Tipo, Longitud, PrecisionTipo, Escala)
        FULL JOIN (
            SELECT c.*, t.name AS Tipo
            FROM sys.columns AS c
            JOIN sys.types AS t ON t.user_type_id = c.user_type_id
            WHERE c.object_id = @IDVersiones
        ) AS a ON a.name = e.Nombre
        WHERE e.Nombre IS NULL OR a.name IS NULL OR a.Tipo <> e.Tipo
           OR a.user_type_id <> a.system_type_id OR a.max_length <> e.Longitud
           OR a.precision <> e.PrecisionTipo OR a.scale <> e.Escala
           OR a.is_nullable <> 0 OR a.is_identity <> 0 OR a.is_computed <> 0
           OR a.is_sparse <> 0 OR a.is_hidden <> 0 OR a.generated_always_type <> 0
    )
        THROW 64008, N'Las columnas de VersionesMigracion no cumplen el contrato de 001.', 1;

    IF NOT EXISTS (
        SELECT 1 FROM sys.indexes AS i
        JOIN sys.index_columns AS ic
          ON ic.object_id = i.object_id AND ic.index_id = i.index_id
        JOIN sys.columns AS c
          ON c.object_id = ic.object_id AND c.column_id = ic.column_id
        WHERE i.object_id = @IDVersiones AND i.is_primary_key = 1
          AND i.type = 1 AND i.is_disabled = 0
          AND c.name = N'Version' AND ic.key_ordinal = 1
          AND ic.is_descending_key = 0
          AND (SELECT COUNT(*) FROM sys.index_columns AS k
               WHERE k.object_id = i.object_id AND k.index_id = i.index_id
                 AND k.key_ordinal > 0) = 1
    )
        THROW 64009, N'VersionesMigracion requiere la PK clustered de 001 sobre Version.', 1;

    IF EXISTS (SELECT 1 FROM sys.triggers WHERE parent_id = @IDVersiones)
       OR EXISTS (SELECT 1 FROM sys.tables WHERE object_id = @IDVersiones
                  AND (temporal_type <> 0 OR is_memory_optimized = 1))
        THROW 64010, N'VersionesMigracion tiene características inesperadas; revisar manualmente.', 1;

    -- Lote inferior: errores de compilación/resolución quedan dentro del TRY externo.
    EXEC sys.sp_executesql N'
        IF NOT EXISTS (
            SELECT 1 FROM dbo.VersionesMigracion WITH (UPDLOCK, HOLDLOCK)
            WHERE [Version] = 20 AND NombreArchivo = N''020_ProcedimientosReportesAuditoria.sql''
        )
            THROW 64013, N''Debe estar registrada la migración 020_ProcedimientosReportesAuditoria.sql antes de aplicar 021.'', 1;
        IF EXISTS (SELECT 1 FROM dbo.VersionesMigracion WITH (UPDLOCK, HOLDLOCK)
                   WHERE [Version] >= 21)
            THROW 64011, N''021 o una migración posterior ya está registrada. No se reaplica ni se certifica el esquema existente.'', 1;
    ';



    -- Coordina también con las escrituras de los SP 012-020.
    DECLARE @ResultadoNegocio int;
    EXEC @ResultadoNegocio = sys.sp_getapplock
        @Resource = N'ShopCart.Negocio',
        @LockMode = N'Exclusive',
        @LockOwner = N'Transaction',
        @LockTimeout = 10000;
    IF @ResultadoNegocio < 0
        THROW 64014, N'No se pudo obtener el bloqueo de negocio para configurar datos.', 1;

    IF OBJECT_ID(N'dbo.Roles', N'U') IS NULL
       OR OBJECT_ID(N'dbo.Categorias', N'U') IS NULL
       OR OBJECT_ID(N'dbo.MetodosEnvio', N'U') IS NULL
       OR OBJECT_ID(N'dbo.EventosAuditoria', N'U') IS NULL
        THROW 64015, N'Faltan tablas requeridas por las migraciones anteriores.', 1;

    -- Contrato de columnas: tipos nativos, longitudes, escala, nulabilidad e identidad.
    IF EXISTS (
        SELECT 1
        FROM (VALUES
            (N'Roles', N'IdRol', N'tinyint', 1, 3, 0, 0, 0),
            (N'Roles', N'Nombre', N'nvarchar', 60, 0, 0, 0, 0),
            (N'Roles', N'Descripcion', N'nvarchar', 300, 0, 0, 1, 0),
            (N'Categorias', N'IdCategoria', N'int', 4, 10, 0, 0, 1),
            (N'Categorias', N'Nombre', N'nvarchar', 200, 0, 0, 0, 0),
            (N'Categorias', N'Descripcion', N'nvarchar', 1000, 0, 0, 1, 0),
            (N'Categorias', N'EstaActiva', N'bit', 1, 1, 0, 0, 0),
            (N'Categorias', N'FechaCreacionUTC', N'datetime2', 8, 27, 7, 0, 0),
            (N'Categorias', N'FechaActualizacionUTC', N'datetime2', 8, 27, 7, 0, 0),
            (N'MetodosEnvio', N'IdMetodoEnvio', N'int', 4, 10, 0, 0, 1),
            (N'MetodosEnvio', N'Codigo', N'varchar', 30, 0, 0, 0, 0),
            (N'MetodosEnvio', N'Nombre', N'nvarchar', 200, 0, 0, 0, 0),
            (N'MetodosEnvio', N'Descripcion', N'nvarchar', 1000, 0, 0, 1, 0),
            (N'MetodosEnvio', N'Costo', N'decimal', 9, 19, 4, 0, 0),
            (N'MetodosEnvio', N'EstaActivo', N'bit', 1, 1, 0, 0, 0),
            (N'MetodosEnvio', N'OrdenVisualizacion', N'int', 4, 10, 0, 0, 0),
            (N'MetodosEnvio', N'FechaCreacionUTC', N'datetime2', 8, 27, 7, 0, 0),
            (N'MetodosEnvio', N'FechaActualizacionUTC', N'datetime2', 8, 27, 7, 0, 0),
            (N'EventosAuditoria', N'IdEventoAuditoria', N'bigint', 8, 19, 0, 0, 1),
            (N'EventosAuditoria', N'IdUsuarioActor', N'bigint', 8, 19, 0, 1, 0),
            (N'EventosAuditoria', N'Accion', N'varchar', 100, 0, 0, 0, 0),
            (N'EventosAuditoria', N'Entidad', N'varchar', 100, 0, 0, 0, 0),
            (N'EventosAuditoria', N'IdEntidad', N'bigint', 8, 19, 0, 1, 0),
            (N'EventosAuditoria', N'DatosAnteriores', N'nvarchar', -1, 0, 0, 1, 0),
            (N'EventosAuditoria', N'DatosNuevos', N'nvarchar', -1, 0, 0, 1, 0),
            (N'EventosAuditoria', N'IdCorrelacion', N'uniqueidentifier', 16, 0, 0, 1, 0),
            (N'EventosAuditoria', N'FechaEventoUTC', N'datetime2', 8, 27, 7, 0, 0)
        ) AS e(Tabla, Columna, Tipo, Longitud, PrecisionTipo, Escala, AdmiteNull, Identidad)
        FULL JOIN (
            SELECT s.name AS Esquema, t.name AS Tabla, c.*, ty.name AS Tipo
            FROM sys.tables AS t
            JOIN sys.schemas AS s ON s.schema_id = t.schema_id
            JOIN sys.columns AS c ON c.object_id = t.object_id
            JOIN sys.types AS ty ON ty.user_type_id = c.user_type_id
            WHERE s.name = N'dbo'
              AND t.name IN (N'Roles', N'Categorias', N'MetodosEnvio', N'EventosAuditoria')
        ) AS a ON a.Tabla = e.Tabla AND a.name = e.Columna
        WHERE e.Columna IS NULL OR a.name IS NULL OR a.Tipo <> e.Tipo
           OR a.user_type_id <> a.system_type_id OR a.max_length <> e.Longitud
           OR a.precision <> e.PrecisionTipo OR a.scale <> e.Escala
           OR a.is_nullable <> e.AdmiteNull OR a.is_identity <> e.Identidad
           OR a.is_computed <> 0 OR a.is_sparse <> 0 OR a.is_hidden <> 0
           OR a.generated_always_type <> 0
           OR (a.collation_name IS NOT NULL AND a.collation_name <> N'Latin1_General_100_CI_AI_SC')
    )
        THROW 64016, N'El esquema de configuración o auditoría difiere del contrato aprobado.', 1;

    IF EXISTS (
        SELECT 1 FROM sys.triggers
        WHERE parent_id IN (OBJECT_ID(N'dbo.Roles'), OBJECT_ID(N'dbo.Categorias'),
                            OBJECT_ID(N'dbo.MetodosEnvio'), OBJECT_ID(N'dbo.EventosAuditoria'))
    ) OR EXISTS (
        SELECT 1 FROM sys.tables
        WHERE object_id IN (OBJECT_ID(N'dbo.Roles'), OBJECT_ID(N'dbo.Categorias'),
                            OBJECT_ID(N'dbo.MetodosEnvio'), OBJECT_ID(N'dbo.EventosAuditoria'))
          AND (temporal_type <> 0 OR is_memory_optimized = 1)
    )
        THROW 64017, N'Hay características adicionales en las tablas; revisar antes del arranque.', 1;


    -- Exige las claves únicas que sostienen la identidad de cada dato inicial.
    IF EXISTS (
        SELECT 1 FROM (VALUES
            (N'Roles', N'IdRol', 1),
            (N'Roles', N'Nombre', 0),
            (N'Categorias', N'IdCategoria', 1),
            (N'Categorias', N'Nombre', 0),
            (N'MetodosEnvio', N'IdMetodoEnvio', 1),
            (N'MetodosEnvio', N'Codigo', 0),
            (N'EventosAuditoria', N'IdEventoAuditoria', 1)
        ) AS e(Tabla, Columna, EsPK)
        WHERE NOT EXISTS (
            SELECT 1 FROM sys.indexes AS i
            JOIN sys.index_columns AS ic
              ON ic.object_id = i.object_id AND ic.index_id = i.index_id
            JOIN sys.columns AS c
              ON c.object_id = ic.object_id AND c.column_id = ic.column_id
            WHERE i.object_id = OBJECT_ID(N'dbo.' + e.Tabla, N'U')
              AND i.is_unique = 1 AND i.has_filter = 0 AND i.is_disabled = 0
              AND i.is_hypothetical = 0
              AND ((e.EsPK = 1 AND i.is_primary_key = 1)
                   OR (e.EsPK = 0 AND i.is_unique_constraint = 1))
              AND c.name = e.Columna AND ic.key_ordinal = 1
              AND (SELECT COUNT(*) FROM sys.index_columns AS k
                   WHERE k.object_id = i.object_id AND k.index_id = i.index_id
                     AND k.key_ordinal > 0) = 1
        )
    )
        THROW 64018, N'Faltan claves primarias o restricciones únicas requeridas.', 1;

    -- DML constante en ámbito inferior para capturar errores de compilación/resolución.
    EXEC sys.sp_executesql N'
-- Lote inferior: errores de resolución o compilación se capturan en el CATCH externo.
DECLARE @Ahora datetime2(7) = SYSUTCDATETIME();
DECLARE @Correlacion uniqueidentifier = NEWID();
DECLARE @RolesPlan TABLE (
    IdPreferido tinyint NOT NULL PRIMARY KEY,
    Nombre nvarchar(30) NOT NULL UNIQUE,
    Descripcion nvarchar(150) NOT NULL
);
DECLARE @EnviosPlan TABLE (
    Codigo varchar(30) NOT NULL PRIMARY KEY,
    Nombre nvarchar(100) NOT NULL UNIQUE,
    Descripcion nvarchar(500) NOT NULL,
    Costo decimal(19,4) NOT NULL,
    OrdenVisualizacion int NOT NULL
);
DECLARE @CategoriasPlan TABLE (
    Nombre nvarchar(100) NOT NULL PRIMARY KEY,
    Descripcion nvarchar(500) NOT NULL
);
DECLARE @RolesInsertados TABLE (IdRol tinyint NOT NULL PRIMARY KEY);
DECLARE @EnviosInsertados TABLE (IdMetodoEnvio int NOT NULL PRIMARY KEY);
DECLARE @CategoriasInsertadas TABLE (IdCategoria int NOT NULL PRIMARY KEY);

INSERT @RolesPlan (IdPreferido, Nombre, Descripcion) VALUES
    (1, N''Cliente'', N''Cliente de la tienda; opera únicamente con recursos propios.''),
    (2, N''Operador'', N''Operación de pedidos, devoluciones e inventario según autorización.''),
    (3, N''Administrador'', N''Administración del comercio según permisos de la aplicación.'');

INSERT @EnviosPlan (Codigo, Nombre, Descripcion, Costo, OrdenVisualizacion) VALUES
    (''ESTANDAR'', N''Envío estándar'', N''Tarifa fija de demostración para entrega estándar en Guatemala.'',
     CONVERT(decimal(19,4),25.0000), 10),
    (''EXPRES'', N''Envío exprés'', N''Tarifa fija de demostración para entrega prioritaria en Guatemala.'',
     CONVERT(decimal(19,4),45.0000), 20),
    (''RETIRO_TIENDA'', N''Retiro en tienda'', N''Retiro sin costo de envío en el punto de atención de la tienda.'',
     CONVERT(decimal(19,4),0.0000), 30);

INSERT @CategoriasPlan (Nombre, Descripcion) VALUES
    (N''Electrónica'', N''Dispositivos y artículos electrónicos.''),
    (N''Ropa'', N''Prendas de vestir.''),
    (N''Hogar'', N''Artículos para el hogar.''),
    (N''Accesorios'', N''Complementos y accesorios de uso general.'');

-- Mantiene bloqueadas filas y rangos leídos hasta confirmar toda la migración.
-- BIN2 más DATALENGTH evita aceptar nombres que el backend no reconocerá literalmente.
IF EXISTS (
    SELECT 1 FROM dbo.Roles AS r WITH (UPDLOCK, HOLDLOCK)
    JOIN @RolesPlan AS p ON LTRIM(RTRIM(r.Nombre)) = p.Nombre
    WHERE r.Nombre COLLATE Latin1_General_100_BIN2 <> p.Nombre COLLATE Latin1_General_100_BIN2
       OR DATALENGTH(r.Nombre) <> DATALENGTH(p.Nombre)
)
    THROW 64020, N''Hay un rol equivalente con nombre no canónico; no se renombrará automáticamente.'', 1;

IF EXISTS (
    SELECT 1 FROM @RolesPlan AS p
    WHERE NOT EXISTS (
        SELECT 1 FROM dbo.Roles AS r WITH (UPDLOCK, HOLDLOCK)
        WHERE r.Nombre = p.Nombre
    ) AND EXISTS (
        SELECT 1 FROM dbo.Roles AS r WITH (UPDLOCK, HOLDLOCK)
        WHERE r.IdRol = p.IdPreferido
    )
)
    THROW 64021, N''Un ID preferido está ocupado por otro rol. No se reasignarán IDs ni referencias.'', 1;

IF EXISTS (
    SELECT 1 FROM dbo.MetodosEnvio AS m WITH (UPDLOCK, HOLDLOCK)
    JOIN @EnviosPlan AS p ON LTRIM(RTRIM(m.Codigo)) = p.Codigo
    WHERE m.Nombre <> p.Nombre
       OR DATALENGTH(m.Codigo) <> DATALENGTH(LTRIM(RTRIM(m.Codigo)))
       OR DATALENGTH(m.Nombre) <> DATALENGTH(LTRIM(RTRIM(m.Nombre)))
       OR m.EstaActivo <> 1 OR m.Costo < 0 OR m.OrdenVisualizacion < 0
)
    THROW 64022, N''Un código de envío existente tiene nombre o propiedades incompatibles; revisar manualmente.'', 1;

-- Nombres repetidos son válidos en el modelo general, pero aquí serían una identidad
-- ambigua de la configuración propuesta. No se inventa una equivalencia entre códigos.
IF EXISTS (
    SELECT 1 FROM dbo.MetodosEnvio AS m WITH (UPDLOCK, HOLDLOCK)
    JOIN @EnviosPlan AS p ON LTRIM(RTRIM(m.Nombre)) = p.Nombre
    WHERE m.Codigo <> p.Codigo
)
    THROW 64023, N''Un método inicial ya tiene el mismo nombre bajo otro código; no se duplicará.'', 1;

IF EXISTS (
    SELECT 1 FROM dbo.Categorias AS c WITH (UPDLOCK, HOLDLOCK)
    JOIN @CategoriasPlan AS p ON LTRIM(RTRIM(c.Nombre)) = p.Nombre
    WHERE c.EstaActiva <> 1
       OR DATALENGTH(c.Nombre) <> DATALENGTH(LTRIM(RTRIM(c.Nombre)))
)
    THROW 64024, N''Una categoría inicial está inactiva o tiene espacios exteriores; no se modificará.'', 1;

INSERT dbo.Roles (IdRol, Nombre, Descripcion)
    OUTPUT inserted.IdRol INTO @RolesInsertados (IdRol)
SELECT p.IdPreferido, p.Nombre, p.Descripcion
FROM @RolesPlan AS p
WHERE NOT EXISTS (
    SELECT 1 FROM dbo.Roles AS r WITH (UPDLOCK, HOLDLOCK)
    WHERE r.Nombre = p.Nombre
);

-- Identidades y fechas se generan según el esquema; no se utiliza IDENTITY_INSERT.
-- Fechas explícitas permiten registrar el mismo instante UTC de configuración.
INSERT dbo.MetodosEnvio
    (Codigo, Nombre, Descripcion, Costo, EstaActivo, OrdenVisualizacion,
     FechaCreacionUTC, FechaActualizacionUTC)
    OUTPUT inserted.IdMetodoEnvio INTO @EnviosInsertados (IdMetodoEnvio)
SELECT p.Codigo, p.Nombre, p.Descripcion, p.Costo, 1, p.OrdenVisualizacion, @Ahora, @Ahora
FROM @EnviosPlan AS p
WHERE NOT EXISTS (
    SELECT 1 FROM dbo.MetodosEnvio AS m WITH (UPDLOCK, HOLDLOCK)
    WHERE m.Codigo = p.Codigo
);

INSERT dbo.Categorias
    (Nombre, Descripcion, EstaActiva, FechaCreacionUTC, FechaActualizacionUTC)
    OUTPUT inserted.IdCategoria INTO @CategoriasInsertadas (IdCategoria)
SELECT p.Nombre, p.Descripcion, 1, @Ahora, @Ahora
FROM @CategoriasPlan AS p
WHERE NOT EXISTS (
    SELECT 1 FROM dbo.Categorias AS c WITH (UPDLOCK, HOLDLOCK)
    WHERE c.Nombre = p.Nombre
);

INSERT dbo.EventosAuditoria
    (IdUsuarioActor, Accion, Entidad, IdEntidad, DatosAnteriores, DatosNuevos,
     IdCorrelacion, FechaEventoUTC)
SELECT NULL, ''CONFIGURACION_INICIAL'', ''Roles'', r.IdRol, NULL,
       (SELECT r.IdRol, r.Nombre, r.Descripcion FOR JSON PATH, WITHOUT_ARRAY_WRAPPER),
       @Correlacion, @Ahora
FROM @RolesInsertados AS n JOIN dbo.Roles AS r ON r.IdRol = n.IdRol;

INSERT dbo.EventosAuditoria
    (IdUsuarioActor, Accion, Entidad, IdEntidad, DatosAnteriores, DatosNuevos,
     IdCorrelacion, FechaEventoUTC)
SELECT NULL, ''CONFIGURACION_INICIAL'', ''MetodosEnvio'', m.IdMetodoEnvio, NULL,
       (SELECT m.IdMetodoEnvio, m.Codigo, m.Nombre, m.Descripcion, m.Costo,
               m.EstaActivo, m.OrdenVisualizacion
        FOR JSON PATH, WITHOUT_ARRAY_WRAPPER),
       @Correlacion, @Ahora
FROM @EnviosInsertados AS n JOIN dbo.MetodosEnvio AS m ON m.IdMetodoEnvio = n.IdMetodoEnvio;

INSERT dbo.EventosAuditoria
    (IdUsuarioActor, Accion, Entidad, IdEntidad, DatosAnteriores, DatosNuevos,
     IdCorrelacion, FechaEventoUTC)
SELECT NULL, ''CONFIGURACION_INICIAL'', ''Categorias'', c.IdCategoria, NULL,
       (SELECT c.IdCategoria, c.Nombre, c.Descripcion, c.EstaActiva
        FOR JSON PATH, WITHOUT_ARRAY_WRAPPER),
       @Correlacion, @Ahora
FROM @CategoriasInsertadas AS n JOIN dbo.Categorias AS c ON c.IdCategoria = n.IdCategoria;

-- No se exige que las tablas estuvieran vacías ni que todos los datos sean nuevos.
IF (SELECT COUNT(*) FROM dbo.Roles AS r JOIN @RolesPlan AS p ON r.Nombre = p.Nombre) <> 3
   OR (SELECT COUNT(*) FROM dbo.MetodosEnvio AS m JOIN @EnviosPlan AS p ON m.Codigo = p.Codigo) <> 3
   OR (SELECT COUNT(*) FROM dbo.Categorias AS c JOIN @CategoriasPlan AS p ON c.Nombre = p.Nombre) <> 4
    THROW 64025, N''No se pudo verificar toda la configuración esencial.'', 1;

INSERT dbo.VersionesMigracion ([Version], NombreArchivo, SHA256, FechaAplicacionUTC, Ejecutor)
VALUES (21, N''021_ConfiguracionInicial.sql'', @Huella, @Ahora, ORIGINAL_LOGIN());
',
        N'@Huella varbinary(32)', @Huella = @SHA256;

    COMMIT TRANSACTION;
    PRINT N'Migración 021 completada: configuración esencial, auditoría y registro técnico confirmados.';
END TRY
BEGIN CATCH
    IF XACT_STATE() <> 0
        ROLLBACK TRANSACTION;
    THROW;
END CATCH;

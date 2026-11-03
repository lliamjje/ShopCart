/*
    002_Seguridad.sql — Tablas de seguridad, sin datos semilla ni SP de negocio.
    Ejecutar COMPLETO como un único lote, sin GO, conectado a ShopCart.
    Requiere Auto-commit al inicio; la transacción pertenece a este script.
    No ejecutar selecciones parciales ni cambios administrativos concurrentes.

    PROPUESTA PENDIENTE DE APROBACIÓN ANTES DE EJECUTAR:
    finalizar este archivo, calcular SHA-256 de sus bytes con Get-FileHash y,
    sin editarlo después, suministrar los 32 bytes mediante sp_set_session_context
    con clave ShopCart.Migracion002.SHA256 en la MISMA conexión de DataGrip.
    El valor debe ser binary/varbinary, no texto hexadecimal. Limpiarlo al terminar.
    No se incluye una huella literal: incluirla cambiaría el archivo que se mide.
    SQL Server valida el formato recibido, pero no verifica los bytes del archivo;
    corresponde al ejecutor comprobar que aplica exactamente el archivo medido.

    IdTokenAnterior representa el antecesor, según el diseño de esta tarea.
    La rotación atómica, reutilización y una sola cadena activa por sesión se
    implementarán en SP posteriores; estas tablas no sustituyen esos procesos.
    HashContrasena y HashToken nunca deben contener contraseñas ni tokens originales.
    FechaActualizacionUTC debe actualizarse desde los futuros SP: DEFAULT solo inserta.
*/
IF DB_NAME() <> N'ShopCart'
    THROW 52000, N'002 solo puede ejecutarse en la base ShopCart.', 1;

IF @@TRANCOUNT <> 0 OR (2 & @@OPTIONS) = 2
    THROW 52001, N'Inicie con Auto-commit y sin transacciones abiertas o implícitas.', 1;

SET NOCOUNT ON;
SET XACT_ABORT ON;
-- Opciones requeridas por los índices filtrados.
SET ANSI_NULLS ON;
SET ANSI_PADDING ON;
SET ANSI_WARNINGS ON;
SET ARITHABORT ON;
SET CONCAT_NULL_YIELDS_NULL ON;
SET QUOTED_IDENTIFIER ON;
SET NUMERIC_ROUNDABORT OFF;

IF COALESCE(HAS_PERMS_BY_NAME(DB_NAME(), N'DATABASE', N'CONTROL'), 0) <> 1
    THROW 52002, N'Se requiere CONTROL sobre ShopCart para inspeccionar y crear el esquema.', 1;

IF NOT EXISTS (
    SELECT 1 FROM sys.databases
    WHERE database_id = DB_ID()
      AND collation_name = N'Latin1_General_100_CI_AI_SC'
      AND recovery_model_desc = N'SIMPLE'
      AND state_desc = N'ONLINE' AND user_access_desc = N'MULTI_USER'
      AND is_read_only = 0 AND source_database_id IS NULL
)
    THROW 52003, N'Las propiedades de ShopCart no coinciden con el arranque 001.', 1;

DECLARE @HuellaRecibida sql_variant = SESSION_CONTEXT(N'ShopCart.Migracion002.SHA256');
IF @HuellaRecibida IS NULL
   OR CONVERT(nvarchar(128), SQL_VARIANT_PROPERTY(@HuellaRecibida, 'BaseType')) NOT IN (N'binary', N'varbinary')
    THROW 52004, N'Suministre el SHA-256 real como valor binario en SESSION_CONTEXT antes de ejecutar 002.', 1;

DECLARE @SHA256 varbinary(max) = CONVERT(varbinary(max), @HuellaRecibida);
IF DATALENGTH(@SHA256) <> 32
    THROW 52005, N'La huella SHA-256 debe contener exactamente 32 bytes.', 1;

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
        THROW 52006, N'No se pudo obtener el bloqueo exclusivo de migraciones.', 1;

    DECLARE @IDVersiones int = OBJECT_ID(N'dbo.VersionesMigracion', N'U');
    IF @IDVersiones IS NULL
        THROW 52007, N'Falta la tabla técnica creada por 001. No se aplicará 002.', 1;

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
        THROW 52008, N'Las columnas de VersionesMigracion no cumplen el contrato de 001.', 1;

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
        THROW 52009, N'VersionesMigracion requiere la PK clustered de 001 sobre Version.', 1;

    IF EXISTS (SELECT 1 FROM sys.triggers WHERE parent_id = @IDVersiones)
       OR EXISTS (SELECT 1 FROM sys.tables WHERE object_id = @IDVersiones
                  AND (temporal_type <> 0 OR is_memory_optimized = 1))
        THROW 52010, N'VersionesMigracion tiene características inesperadas; revisar manualmente.', 1;

    -- Lote inferior: errores de compilación/resolución quedan dentro del TRY externo.
    EXEC sys.sp_executesql N'
        IF EXISTS (SELECT 1 FROM dbo.VersionesMigracion WITH (UPDLOCK, HOLDLOCK)
                   WHERE [Version] >= 2)
            THROW 52011, N''002 o una migración posterior ya está registrada. No se reaplica ni se certifica el esquema existente.'', 1;
    ';

    IF EXISTS (
        SELECT 1 FROM sys.objects AS o
        JOIN sys.schemas AS s ON s.schema_id = o.schema_id
        WHERE s.name = N'dbo'
          AND o.name IN (N'Roles', N'Usuarios', N'Direcciones',
                         N'SesionesUsuario', N'TokensRenovacion')
    )
        THROW 52012, N'Ya existe parte o todo el esquema de seguridad sin registro compatible. Revisar manualmente; no se reparará.', 1;

    -- SQL constante, sin concatenación ni entradas externas.
    -- El lote inferior permite capturar también errores de compilación del DDL.
    EXEC sys.sp_executesql N'
        CREATE TABLE dbo.Roles
        (
            IdRol tinyint NOT NULL,
            Nombre nvarchar(30) NOT NULL,
            Descripcion nvarchar(150) NULL,
            CONSTRAINT PK_Roles PRIMARY KEY CLUSTERED (IdRol),
            CONSTRAINT UQ_Roles_Nombre UNIQUE NONCLUSTERED (Nombre)
        );

        CREATE TABLE dbo.Usuarios
        (
            IdUsuario bigint IDENTITY(1,1) NOT NULL,
            IdRol tinyint NOT NULL,
            Nombre nvarchar(100) NOT NULL,
            Apellido nvarchar(100) NOT NULL,
            CorreoElectronico nvarchar(254) NOT NULL,
            HashContrasena nvarchar(255) NOT NULL,
            EstaActivo bit NOT NULL CONSTRAINT DF_Usuarios_EstaActivo DEFAULT (1),
            FechaCreacionUTC datetime2(7) NOT NULL
                CONSTRAINT DF_Usuarios_FechaCreacionUTC DEFAULT (SYSUTCDATETIME()),
            FechaActualizacionUTC datetime2(7) NOT NULL
                CONSTRAINT DF_Usuarios_FechaActualizacionUTC DEFAULT (SYSUTCDATETIME()),
            CONSTRAINT PK_Usuarios PRIMARY KEY CLUSTERED (IdUsuario),
            CONSTRAINT UQ_Usuarios_CorreoElectronico UNIQUE NONCLUSTERED (CorreoElectronico),
            CONSTRAINT FK_Usuarios_Roles FOREIGN KEY (IdRol)
                REFERENCES dbo.Roles (IdRol) ON DELETE NO ACTION ON UPDATE NO ACTION
        );
        CREATE NONCLUSTERED INDEX IX_Usuarios_IdRol ON dbo.Usuarios (IdRol);

        CREATE TABLE dbo.Direcciones
        (
            IdDireccion bigint IDENTITY(1,1) NOT NULL,
            IdUsuario bigint NOT NULL,
            NombreDestinatario nvarchar(150) NOT NULL,
            TelefonoContacto nvarchar(25) NOT NULL,
            Departamento nvarchar(100) NOT NULL,
            Municipio nvarchar(100) NOT NULL,
            DireccionLinea1 nvarchar(250) NOT NULL,
            DireccionLinea2 nvarchar(250) NULL,
            Referencias nvarchar(500) NULL,
            CodigoPostal nvarchar(15) NULL,
            EsPredeterminada bit NOT NULL
                CONSTRAINT DF_Direcciones_EsPredeterminada DEFAULT (0),
            EstaActiva bit NOT NULL CONSTRAINT DF_Direcciones_EstaActiva DEFAULT (1),
            FechaCreacionUTC datetime2(7) NOT NULL
                CONSTRAINT DF_Direcciones_FechaCreacionUTC DEFAULT (SYSUTCDATETIME()),
            FechaActualizacionUTC datetime2(7) NOT NULL
                CONSTRAINT DF_Direcciones_FechaActualizacionUTC DEFAULT (SYSUTCDATETIME()),
            CONSTRAINT PK_Direcciones PRIMARY KEY CLUSTERED (IdDireccion),
            CONSTRAINT FK_Direcciones_Usuarios FOREIGN KEY (IdUsuario)
                REFERENCES dbo.Usuarios (IdUsuario) ON DELETE NO ACTION ON UPDATE NO ACTION
        );
        -- El índice filtrado no cubre la consulta de todas las direcciones del usuario.
        CREATE NONCLUSTERED INDEX IX_Direcciones_IdUsuario ON dbo.Direcciones (IdUsuario);
        CREATE UNIQUE NONCLUSTERED INDEX UX_Direcciones_Usuario_PredeterminadaActiva
            ON dbo.Direcciones (IdUsuario)
            WHERE EsPredeterminada = 1 AND EstaActiva = 1;

        CREATE TABLE dbo.SesionesUsuario
        (
            IdSesion uniqueidentifier NOT NULL
                CONSTRAINT DF_SesionesUsuario_IdSesion DEFAULT (NEWID()),
            IdUsuario bigint NOT NULL,
            FechaCreacionUTC datetime2(7) NOT NULL
                CONSTRAINT DF_SesionesUsuario_FechaCreacionUTC DEFAULT (SYSUTCDATETIME()),
            FechaUltimaActividadUTC datetime2(7) NOT NULL
                CONSTRAINT DF_SesionesUsuario_FechaUltimaActividadUTC DEFAULT (SYSUTCDATETIME()),
            FechaExpiracionUTC datetime2(7) NOT NULL,
            FechaRevocacionUTC datetime2(7) NULL,
            MotivoRevocacion nvarchar(100) NULL,
            DireccionIP varchar(45) NULL,
            AgenteUsuario nvarchar(500) NULL,
            CONSTRAINT PK_SesionesUsuario PRIMARY KEY CLUSTERED (IdSesion),
            CONSTRAINT FK_SesionesUsuario_Usuarios FOREIGN KEY (IdUsuario)
                REFERENCES dbo.Usuarios (IdUsuario) ON DELETE NO ACTION ON UPDATE NO ACTION,
            CONSTRAINT CK_SesionesUsuario_ExpiracionPosterior
                CHECK (FechaExpiracionUTC > FechaCreacionUTC)
        );
        CREATE NONCLUSTERED INDEX IX_SesionesUsuario_Usuario_Expiracion
            ON dbo.SesionesUsuario (IdUsuario, FechaExpiracionUTC);

        CREATE TABLE dbo.TokensRenovacion
        (
            IdTokenRenovacion bigint IDENTITY(1,1) NOT NULL,
            IdSesion uniqueidentifier NOT NULL,
            HashToken binary(32) NOT NULL,
            IdTokenAnterior bigint NULL,
            FechaCreacionUTC datetime2(7) NOT NULL
                CONSTRAINT DF_TokensRenovacion_FechaCreacionUTC DEFAULT (SYSUTCDATETIME()),
            FechaExpiracionUTC datetime2(7) NOT NULL,
            FechaUsoUTC datetime2(7) NULL,
            FechaRevocacionUTC datetime2(7) NULL,
            MotivoRevocacion nvarchar(100) NULL,
            CONSTRAINT PK_TokensRenovacion PRIMARY KEY CLUSTERED (IdTokenRenovacion),
            CONSTRAINT UQ_TokensRenovacion_HashToken UNIQUE NONCLUSTERED (HashToken),
            -- Clave candidata requerida como destino exacto de la FK compuesta.
            CONSTRAINT UQ_TokensRenovacion_Sesion_Token
                UNIQUE NONCLUSTERED (IdSesion, IdTokenRenovacion),
            CONSTRAINT FK_TokensRenovacion_SesionesUsuario FOREIGN KEY (IdSesion)
                REFERENCES dbo.SesionesUsuario (IdSesion)
                ON DELETE NO ACTION ON UPDATE NO ACTION,
            CONSTRAINT FK_TokensRenovacion_AnteriorMismaSesion
                FOREIGN KEY (IdSesion, IdTokenAnterior)
                REFERENCES dbo.TokensRenovacion (IdSesion, IdTokenRenovacion)
                ON DELETE NO ACTION ON UPDATE NO ACTION,
            CONSTRAINT CK_TokensRenovacion_NoAutorreferencia
                CHECK (IdTokenAnterior IS NULL OR IdTokenAnterior <> IdTokenRenovacion),
            CONSTRAINT CK_TokensRenovacion_ExpiracionPosterior
                CHECK (FechaExpiracionUTC > FechaCreacionUTC)
        );
        -- Un antecesor puede tener como máximo un sucesor; admite múltiples raíces NULL.
        CREATE UNIQUE NONCLUSTERED INDEX UX_TokensRenovacion_IdTokenAnterior
            ON dbo.TokensRenovacion (IdTokenAnterior)
            WHERE IdTokenAnterior IS NOT NULL;
        -- Consulta por sesión y rango de vencimiento; no requiere otro índice de IdSesion.
        CREATE NONCLUSTERED INDEX IX_TokensRenovacion_Sesion_Expiracion
            ON dbo.TokensRenovacion (IdSesion, FechaExpiracionUTC);
    ';

    -- El registro participa en la MISMA transacción que las cinco tablas.
    EXEC sys.sp_executesql N'
        INSERT INTO dbo.VersionesMigracion
            ([Version], NombreArchivo, SHA256, FechaAplicacionUTC, Ejecutor)
        VALUES
            (2, N''002_Seguridad.sql'', @Huella, SYSUTCDATETIME(), ORIGINAL_LOGIN());
    ', N'@Huella varbinary(32)', @Huella = @SHA256;

    COMMIT TRANSACTION;
    PRINT N'Migración 002 completada: cinco tablas y registro técnico confirmados.';
END TRY
BEGIN CATCH
    IF XACT_STATE() <> 0
        ROLLBACK TRANSACTION;
    THROW;
END CATCH;

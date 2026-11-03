/*
    004_InventarioBase.sql — Existencias y kardex, sin semillas ni SP de negocio.
    Ejecutar COMPLETO como un único lote, sin GO, conectado a ShopCart.
    Iniciar con Auto-commit, sin transacciones abiertas ni implícitas.
    No ejecutar selecciones parciales ni cambios administrativos concurrentes.

    Calcular SHA-256 del archivo FINAL con Get-FileHash y no editarlo después.
    Suministrar sus 32 bytes mediante sp_set_session_context en la MISMA conexión
    de DataGrip, clave ShopCart.Migracion004.SHA256, como binary/varbinary.
    Limpiar el contexto al terminar. No incrustar una huella literal en el archivo.
    SQL valida tipo y longitud; el ejecutor comprueba la correspondencia con el archivo.

    No se crean filas de existencias: el futuro SP de alta de variante creará saldo 0.
    Reservar no reduce CantidadFisica ni genera movimientos físicos.
    Disponible será CantidadFisica menos reservas efectivamente vigentes.
    Los futuros SP actualizarán saldo y kardex en la misma transacción, con bloqueos
    comunes, motivo obligatorio para ajustes y referencias de origen validadas.
    No editar ni borrar movimientos desde SP de negocio; corregir con compensaciones.
    La protección mediante permisos corresponde a migraciones posteriores.
    Esta migración no concilia el kardex ni impide sobreventa por sí sola.
    DEFAULT de FechaActualizacionUTC solo inicializa; los SP actualizarán la fecha.

    Las referencias son polimórficas y aún no tienen FK a ventas/devoluciones.
    El índice único impide repetir (tipo de origen, identificador, variante),
    incluso con otro TipoMovimiento. Los futuros SP deberán definir cada origen
    con granularidad suficiente para distinguir venta, cancelación y devolución.
*/
IF DB_NAME() <> N'ShopCart'
    THROW 54000, N'004 solo puede ejecutarse en la base ShopCart.', 1;

IF @@TRANCOUNT <> 0 OR (2 & @@OPTIONS) = 2
    THROW 54001, N'Inicie con Auto-commit y sin transacciones abiertas o implícitas.', 1;

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
    THROW 54002, N'Se requiere CONTROL sobre ShopCart para inspeccionar y crear el esquema.', 1;

IF NOT EXISTS (
    SELECT 1 FROM sys.databases
    WHERE database_id = DB_ID()
      AND collation_name = N'Latin1_General_100_CI_AI_SC'
      AND recovery_model_desc = N'SIMPLE'
      AND state_desc = N'ONLINE' AND user_access_desc = N'MULTI_USER'
      AND is_read_only = 0 AND source_database_id IS NULL
)
    THROW 54003, N'Las propiedades de ShopCart no coinciden con el arranque 001.', 1;

DECLARE @HuellaRecibida sql_variant = SESSION_CONTEXT(N'ShopCart.Migracion004.SHA256');
IF @HuellaRecibida IS NULL
   OR CONVERT(nvarchar(128), SQL_VARIANT_PROPERTY(@HuellaRecibida, 'BaseType')) NOT IN (N'binary', N'varbinary')
    THROW 54004, N'Suministre el SHA-256 real como valor binario en SESSION_CONTEXT antes de ejecutar 004.', 1;

DECLARE @SHA256 varbinary(max) = CONVERT(varbinary(max), @HuellaRecibida);
IF DATALENGTH(@SHA256) <> 32
    THROW 54005, N'La huella SHA-256 debe contener exactamente 32 bytes.', 1;

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
        THROW 54006, N'No se pudo obtener el bloqueo exclusivo de migraciones.', 1;

    DECLARE @IDVersiones int = OBJECT_ID(N'dbo.VersionesMigracion', N'U');
    IF @IDVersiones IS NULL
        THROW 54007, N'Falta la tabla técnica creada por 001. No se aplicará 004.', 1;

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
        THROW 54008, N'Las columnas de VersionesMigracion no cumplen el contrato de 001.', 1;

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
        THROW 54009, N'VersionesMigracion requiere la PK clustered de 001 sobre Version.', 1;

    IF EXISTS (SELECT 1 FROM sys.triggers WHERE parent_id = @IDVersiones)
       OR EXISTS (SELECT 1 FROM sys.tables WHERE object_id = @IDVersiones
                  AND (temporal_type <> 0 OR is_memory_optimized = 1))
        THROW 54010, N'VersionesMigracion tiene características inesperadas; revisar manualmente.', 1;

    -- Lote inferior: errores de compilación/resolución quedan dentro del TRY externo.
    EXEC sys.sp_executesql N'
        IF NOT EXISTS (
            SELECT 1 FROM dbo.VersionesMigracion WITH (UPDLOCK, HOLDLOCK)
            WHERE [Version] = 3 AND NombreArchivo = N''003_Catalogo.sql''
        )
            THROW 54013, N''Debe estar registrada la migración 003_Catalogo.sql antes de aplicar 004.'', 1;
        IF EXISTS (SELECT 1 FROM dbo.VersionesMigracion WITH (UPDLOCK, HOLDLOCK)
                   WHERE [Version] >= 4)
            THROW 54011, N''004 o una migración posterior ya está registrada. No se reaplica ni se certifica el esquema existente.'', 1;
    ';

    IF EXISTS (
        SELECT 1 FROM sys.objects AS o
        JOIN sys.schemas AS s ON s.schema_id = o.schema_id
        WHERE s.name = N'dbo'
          AND o.name IN (N'Existencias', N'MovimientosInventario')
    )
        THROW 54012, N'Ya existe parte o todo el esquema de inventario sin registro compatible. Revisar manualmente; no se reparará.', 1;

    IF OBJECT_ID(N'dbo.VariantesProducto', N'U') IS NULL
       OR OBJECT_ID(N'dbo.Usuarios', N'U') IS NULL
        THROW 54014, N'Faltan las tablas VariantesProducto o Usuarios de las migraciones previas.', 1;

    -- Verifica los tipos de las columnas que serán destinos de FK.
    IF NOT EXISTS (
        SELECT 1 FROM sys.columns
        WHERE object_id = OBJECT_ID(N'dbo.VariantesProducto', N'U')
          AND name = N'IdVariante' AND system_type_id = TYPE_ID(N'bigint')
          AND user_type_id = system_type_id AND is_nullable = 0 AND is_computed = 0
    ) OR NOT EXISTS (
        SELECT 1 FROM sys.columns
        WHERE object_id = OBJECT_ID(N'dbo.Usuarios', N'U')
          AND name = N'IdUsuario' AND system_type_id = TYPE_ID(N'bigint')
          AND user_type_id = system_type_id AND is_nullable = 0 AND is_computed = 0
    )
        THROW 54015, N'Las columnas referenciadas deben ser bigint NOT NULL nativas.', 1;

    -- DDL constante en un lote inferior: sus errores alcanzan el CATCH externo.
    -- Al crear las FK, SQL Server verifica también las claves candidatas de destino.
    EXEC sys.sp_executesql N'
        CREATE TABLE dbo.Existencias
        (
            IdVariante bigint NOT NULL,
            CantidadFisica int NOT NULL
                CONSTRAINT DF_Existencias_CantidadFisica DEFAULT (0),
            FechaActualizacionUTC datetime2(7) NOT NULL
                CONSTRAINT DF_Existencias_FechaActualizacionUTC DEFAULT (SYSUTCDATETIME()),
            CONSTRAINT PK_Existencias PRIMARY KEY CLUSTERED (IdVariante),
            CONSTRAINT FK_Existencias_VariantesProducto FOREIGN KEY (IdVariante)
                REFERENCES dbo.VariantesProducto (IdVariante)
                ON DELETE NO ACTION ON UPDATE NO ACTION,
            CONSTRAINT CK_Existencias_CantidadFisicaNoNegativa CHECK (CantidadFisica >= 0)
        );

        CREATE TABLE dbo.MovimientosInventario
        (
            IdMovimiento bigint IDENTITY(1,1) NOT NULL,
            IdVariante bigint NOT NULL,
            TipoMovimiento varchar(30) NOT NULL,
            Cantidad int NOT NULL,
            SaldoAnterior int NOT NULL,
            SaldoPosterior int NOT NULL,
            Motivo nvarchar(500) NULL,
            IdUsuarioResponsable bigint NULL,
            TipoReferencia varchar(30) NULL,
            IdReferencia bigint NULL,
            FechaMovimientoUTC datetime2(7) NOT NULL
                CONSTRAINT DF_MovimientosInventario_FechaMovimientoUTC
                DEFAULT (SYSUTCDATETIME()),
            CONSTRAINT PK_MovimientosInventario PRIMARY KEY CLUSTERED (IdMovimiento),
            CONSTRAINT FK_MovimientosInventario_Existencias FOREIGN KEY (IdVariante)
                REFERENCES dbo.Existencias (IdVariante)
                ON DELETE NO ACTION ON UPDATE NO ACTION,
            CONSTRAINT FK_MovimientosInventario_Usuarios FOREIGN KEY (IdUsuarioResponsable)
                REFERENCES dbo.Usuarios (IdUsuario)
                ON DELETE NO ACTION ON UPDATE NO ACTION,
            CONSTRAINT CK_MovimientosInventario_TipoPermitido CHECK (
                TipoMovimiento IN (
                    ''ENTRADA'', ''SALIDA'', ''AJUSTE_POSITIVO'',
                    ''AJUSTE_NEGATIVO'', ''DEVOLUCION''
                )
            ),
            CONSTRAINT CK_MovimientosInventario_CantidadPositiva CHECK (Cantidad > 0),
            CONSTRAINT CK_MovimientosInventario_SaldosNoNegativos CHECK (
                SaldoAnterior >= 0 AND SaldoPosterior >= 0
            ),
            -- Convertir ANTES de operar evita overflow de int durante el CHECK.
            CONSTRAINT CK_MovimientosInventario_ConsistenciaSaldo CHECK (
                (
                    TipoMovimiento IN (''ENTRADA'', ''AJUSTE_POSITIVO'', ''DEVOLUCION'')
                    AND CONVERT(bigint, SaldoPosterior) =
                        CONVERT(bigint, SaldoAnterior) + CONVERT(bigint, Cantidad)
                )
                OR
                (
                    TipoMovimiento IN (''SALIDA'', ''AJUSTE_NEGATIVO'')
                    AND CONVERT(bigint, SaldoPosterior) =
                        CONVERT(bigint, SaldoAnterior) - CONVERT(bigint, Cantidad)
                )
            ),
            CONSTRAINT CK_MovimientosInventario_ReferenciaCompleta CHECK (
                (TipoReferencia IS NULL AND IdReferencia IS NULL)
                OR (TipoReferencia IS NOT NULL AND IdReferencia IS NOT NULL)
            )
        );

        -- El prefijo IdVariante cubre la FK y la consulta de kardex por fecha.
        -- IdMovimiento da orden estable cuando coinciden las fechas.
        CREATE NONCLUSTERED INDEX IX_MovimientosInventario_Variante_Fecha
            ON dbo.MovimientosInventario (IdVariante, FechaMovimientoUTC, IdMovimiento);
        CREATE NONCLUSTERED INDEX IX_MovimientosInventario_IdUsuarioResponsable
            ON dbo.MovimientosInventario (IdUsuarioResponsable);
        CREATE UNIQUE NONCLUSTERED INDEX UX_MovimientosInventario_Origen_Variante
            ON dbo.MovimientosInventario (TipoReferencia, IdReferencia, IdVariante)
            WHERE TipoReferencia IS NOT NULL AND IdReferencia IS NOT NULL;
    ';

    -- Registro técnico y DDL se confirman o revierten juntos.
    EXEC sys.sp_executesql N'
        INSERT INTO dbo.VersionesMigracion
            ([Version], NombreArchivo, SHA256, FechaAplicacionUTC, Ejecutor)
        VALUES
            (4, N''004_InventarioBase.sql'', @Huella, SYSUTCDATETIME(), ORIGINAL_LOGIN());
    ', N'@Huella varbinary(32)', @Huella = @SHA256;

    COMMIT TRANSACTION;
    PRINT N'Migración 004 completada: dos tablas y registro técnico confirmados.';
END TRY
BEGIN CATCH
    IF XACT_STATE() <> 0
        ROLLBACK TRANSACTION;
    THROW;
END CATCH;

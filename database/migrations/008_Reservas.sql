/*
    008_Reservas.sql — Reservas de inventario y cupón, sin semillas ni SP de negocio.
    Ejecutar COMPLETO como un único lote, sin GO, conectado a ShopCart.
    Iniciar con Auto-commit, sin transacciones abiertas ni implícitas.
    No ejecutar selecciones parciales ni cambios administrativos concurrentes.

    Calcular SHA-256 del archivo FINAL con Get-FileHash y no editarlo después.
    Suministrar los 32 bytes con sp_set_session_context en la MISMA conexión de
    DataGrip, clave ShopCart.Migracion008.SHA256, como binary/varbinary.
    Limpiar el contexto al terminar. No incrustar la huella en este archivo.
    SQL valida formato; el ejecutor comprueba la correspondencia archivo/huella.

    Modelo confirmado: una fila por reserva de checkout/variante, sin DetallesReserva.
    Estados: ACTIVA, CONFIRMADA, LIBERADA y EXPIRADA. Se conserva historial mediante
    múltiples filas terminales; los índices únicos limitan solo las filas ACTIVA.
    FechaResolucionUTC es NULL en ACTIVA y obligatoria en los tres estados terminales.

    Disponibilidad efectiva: CantidadFisica menos SUM(Cantidad) de reservas con
    Estado = ACTIVA y FechaExpiracionUTC > hora UTC actual de SQL Server.
    Una ACTIVA vencida deja de descontarse inmediatamente, sin depender de limpieza.
    El tiempo NO cambia por sí solo el estado persistido: una ACTIVA vencida sigue
    ocupando el índice único hasta que un SP la pase a EXPIRADA transaccionalmente.
    El mismo criterio temporal se aplicará a capacidad reservada de cupones.
    No se usa la hora actual en filtros de índice ni se fija expiración por DEFAULT.

    Futuros SP: reservar sin reducir saldo físico ni crear kardex; bloquear las filas
    de Existencias con disciplina común para comprobar disponibilidad y reservar
    atómicamente. Vigencia de 15 minutos coordinada con Checkouts; validar artículos,
    cantidades, cupón y propietario, incluso invitados. Resolver expiración frente
    a confirmación sin consumos dobles y rechazar confirmaciones fuera de vigencia.
    Liberar/expirar/confirmar mediante transacciones con transiciones válidas,
    actualización de fechas y conservación de historial; no borrar reservas históricas.
    DEFAULT de FechaActualizacionUTC solo inicializa: los SP actualizarán la fecha.

    Cupones: bloquear la fila de Cupones al comprobar y reservar capacidad global
    y por usuario. Contar usos confirmados más reservas ACTIVA no vencidas, sin
    duplicar un uso al confirmar el pedido. Exigir autenticación si existe
    LimiteUsosPorUsuario y comprobar IdUsuario contra el propietario del checkout.
    Las FK simples no prueban esa pertenencia ni la elegibilidad del cupón.
    Coordinar consumo, pedido, kardex y pago simulado en una única transacción futura.
    Estas tablas e índices por sí solos no evitan sobreventa ni excesos de uso.
*/
IF DB_NAME() <> N'ShopCart'
    THROW 58000, N'008 solo puede ejecutarse en la base ShopCart.', 1;

IF @@TRANCOUNT <> 0 OR (2 & @@OPTIONS) = 2
    THROW 58001, N'Inicie con Auto-commit y sin transacciones abiertas o implícitas.', 1;

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
    THROW 58002, N'Se requiere CONTROL sobre ShopCart para inspeccionar y crear el esquema.', 1;

IF NOT EXISTS (
    SELECT 1 FROM sys.databases
    WHERE database_id = DB_ID()
      AND collation_name = N'Latin1_General_100_CI_AI_SC'
      AND recovery_model_desc = N'SIMPLE'
      AND state_desc = N'ONLINE' AND user_access_desc = N'MULTI_USER'
      AND is_read_only = 0 AND source_database_id IS NULL
)
    THROW 58003, N'Las propiedades de ShopCart no coinciden con el arranque 001.', 1;

DECLARE @HuellaRecibida sql_variant = SESSION_CONTEXT(N'ShopCart.Migracion008.SHA256');
IF @HuellaRecibida IS NULL
   OR CONVERT(nvarchar(128), SQL_VARIANT_PROPERTY(@HuellaRecibida, 'BaseType')) NOT IN (N'binary', N'varbinary')
    THROW 58004, N'Suministre el SHA-256 real como valor binario en SESSION_CONTEXT antes de ejecutar 008.', 1;

DECLARE @SHA256 varbinary(max) = CONVERT(varbinary(max), @HuellaRecibida);
IF DATALENGTH(@SHA256) <> 32
    THROW 58005, N'La huella SHA-256 debe contener exactamente 32 bytes.', 1;

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
        THROW 58006, N'No se pudo obtener el bloqueo exclusivo de migraciones.', 1;

    DECLARE @IDVersiones int = OBJECT_ID(N'dbo.VersionesMigracion', N'U');
    IF @IDVersiones IS NULL
        THROW 58007, N'Falta la tabla técnica creada por 001. No se aplicará 008.', 1;

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
        THROW 58008, N'Las columnas de VersionesMigracion no cumplen el contrato de 001.', 1;

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
        THROW 58009, N'VersionesMigracion requiere la PK clustered de 001 sobre Version.', 1;

    IF EXISTS (SELECT 1 FROM sys.triggers WHERE parent_id = @IDVersiones)
       OR EXISTS (SELECT 1 FROM sys.tables WHERE object_id = @IDVersiones
                  AND (temporal_type <> 0 OR is_memory_optimized = 1))
        THROW 58010, N'VersionesMigracion tiene características inesperadas; revisar manualmente.', 1;

    -- Lote inferior: errores de compilación/resolución quedan dentro del TRY externo.
    EXEC sys.sp_executesql N'
        IF NOT EXISTS (
            SELECT 1 FROM dbo.VersionesMigracion WITH (UPDLOCK, HOLDLOCK)
            WHERE [Version] = 7 AND NombreArchivo = N''007_Checkout.sql''
        )
            THROW 58013, N''Debe estar registrada la migración 007_Checkout.sql antes de aplicar 008.'', 1;
        IF EXISTS (SELECT 1 FROM dbo.VersionesMigracion WITH (UPDLOCK, HOLDLOCK)
                   WHERE [Version] >= 8)
            THROW 58011, N''008 o una migración posterior ya está registrada. No se reaplica ni se certifica el esquema existente.'', 1;
    ';

    IF EXISTS (
        SELECT 1 FROM sys.objects AS o
        JOIN sys.schemas AS s ON s.schema_id = o.schema_id
        WHERE s.name = N'dbo'
          AND o.name IN (N'ReservasInventario', N'ReservasCupon')
    )
        THROW 58012, N'Ya existe parte o todo el esquema de reservas sin registro compatible. Revisar manualmente; no se reparará.', 1;

    -- Verifica tablas y tipos nativos de las claves que serán destinos de FK.
    IF EXISTS (
        SELECT 1
        FROM (VALUES
            (N'dbo.Checkouts', N'IdCheckout', N'bigint'),
            (N'dbo.VariantesProducto', N'IdVariante', N'bigint'),
            (N'dbo.Cupones', N'IdCupon', N'bigint'),
            (N'dbo.Usuarios', N'IdUsuario', N'bigint')
        ) AS e(Tabla, Columna, Tipo)
        WHERE NOT EXISTS (
            SELECT 1 FROM sys.columns AS c
            WHERE c.object_id = OBJECT_ID(e.Tabla, N'U')
              AND c.name = e.Columna AND c.system_type_id = TYPE_ID(e.Tipo)
              AND c.user_type_id = c.system_type_id
              AND c.is_nullable = 0 AND c.is_computed = 0
        )
    )
        THROW 58014, N'Faltan tablas previas o sus claves no tienen los tipos requeridos.', 1;

    -- DDL constante en un lote inferior: sus errores alcanzan el CATCH externo.
    EXEC sys.sp_executesql N'
        CREATE TABLE dbo.ReservasInventario
        (
            IdReservaInventario bigint IDENTITY(1,1) NOT NULL,
            IdCheckout bigint NOT NULL,
            IdVariante bigint NOT NULL,
            Cantidad int NOT NULL,
            Estado varchar(20) NOT NULL
                CONSTRAINT DF_ReservasInventario_Estado DEFAULT (''ACTIVA''),
            FechaExpiracionUTC datetime2(7) NOT NULL,
            FechaCreacionUTC datetime2(7) NOT NULL
                CONSTRAINT DF_ReservasInventario_FechaCreacionUTC DEFAULT (SYSUTCDATETIME()),
            FechaActualizacionUTC datetime2(7) NOT NULL
                CONSTRAINT DF_ReservasInventario_FechaActualizacionUTC DEFAULT (SYSUTCDATETIME()),
            FechaResolucionUTC datetime2(7) NULL,
            CONSTRAINT PK_ReservasInventario PRIMARY KEY CLUSTERED (IdReservaInventario),
            CONSTRAINT FK_ReservasInventario_Checkouts FOREIGN KEY (IdCheckout)
                REFERENCES dbo.Checkouts (IdCheckout)
                ON DELETE NO ACTION ON UPDATE NO ACTION,
            CONSTRAINT FK_ReservasInventario_VariantesProducto FOREIGN KEY (IdVariante)
                REFERENCES dbo.VariantesProducto (IdVariante)
                ON DELETE NO ACTION ON UPDATE NO ACTION,
            CONSTRAINT CK_ReservasInventario_CantidadPositiva CHECK (Cantidad > 0),
            CONSTRAINT CK_ReservasInventario_EstadoPermitido CHECK (
                Estado IN (''ACTIVA'', ''CONFIRMADA'', ''LIBERADA'', ''EXPIRADA'')
            ),
            CONSTRAINT CK_ReservasInventario_ResolucionCoherente CHECK (
                (Estado = ''ACTIVA'' AND FechaResolucionUTC IS NULL)
                OR (Estado IN (''CONFIRMADA'', ''LIBERADA'', ''EXPIRADA'')
                    AND FechaResolucionUTC IS NOT NULL)
            )
        );
        CREATE UNIQUE NONCLUSTERED INDEX UX_ReservasInventario_Checkout_Variante_Activa
            ON dbo.ReservasInventario (IdCheckout, IdVariante)
            WHERE Estado = ''ACTIVA'';
        -- Historial completo y FK por checkout; el índice filtrado no lo cubre.
        CREATE NONCLUSTERED INDEX IX_ReservasInventario_Checkout_Variante
            ON dbo.ReservasInventario (IdCheckout, IdVariante);
        -- FK por variante y cálculo de reservas efectivamente vigentes.
        CREATE NONCLUSTERED INDEX IX_ReservasInventario_Variante_Estado_Expiracion
            ON dbo.ReservasInventario (IdVariante, Estado, FechaExpiracionUTC)
            INCLUDE (Cantidad);
        -- Localiza filas ACTIVA vencidas para persistir la transición a EXPIRADA.
        CREATE NONCLUSTERED INDEX IX_ReservasInventario_Activas_Expiracion
            ON dbo.ReservasInventario (FechaExpiracionUTC)
            WHERE Estado = ''ACTIVA'';

        CREATE TABLE dbo.ReservasCupon
        (
            IdReservaCupon bigint IDENTITY(1,1) NOT NULL,
            IdCheckout bigint NOT NULL,
            IdCupon bigint NOT NULL,
            IdUsuario bigint NULL,
            Estado varchar(20) NOT NULL
                CONSTRAINT DF_ReservasCupon_Estado DEFAULT (''ACTIVA''),
            FechaExpiracionUTC datetime2(7) NOT NULL,
            FechaCreacionUTC datetime2(7) NOT NULL
                CONSTRAINT DF_ReservasCupon_FechaCreacionUTC DEFAULT (SYSUTCDATETIME()),
            FechaActualizacionUTC datetime2(7) NOT NULL
                CONSTRAINT DF_ReservasCupon_FechaActualizacionUTC DEFAULT (SYSUTCDATETIME()),
            FechaResolucionUTC datetime2(7) NULL,
            CONSTRAINT PK_ReservasCupon PRIMARY KEY CLUSTERED (IdReservaCupon),
            CONSTRAINT FK_ReservasCupon_Checkouts FOREIGN KEY (IdCheckout)
                REFERENCES dbo.Checkouts (IdCheckout)
                ON DELETE NO ACTION ON UPDATE NO ACTION,
            CONSTRAINT FK_ReservasCupon_Cupones FOREIGN KEY (IdCupon)
                REFERENCES dbo.Cupones (IdCupon)
                ON DELETE NO ACTION ON UPDATE NO ACTION,
            CONSTRAINT FK_ReservasCupon_Usuarios FOREIGN KEY (IdUsuario)
                REFERENCES dbo.Usuarios (IdUsuario)
                ON DELETE NO ACTION ON UPDATE NO ACTION,
            CONSTRAINT CK_ReservasCupon_EstadoPermitido CHECK (
                Estado IN (''ACTIVA'', ''CONFIRMADA'', ''LIBERADA'', ''EXPIRADA'')
            ),
            CONSTRAINT CK_ReservasCupon_ResolucionCoherente CHECK (
                (Estado = ''ACTIVA'' AND FechaResolucionUTC IS NULL)
                OR (Estado IN (''CONFIRMADA'', ''LIBERADA'', ''EXPIRADA'')
                    AND FechaResolucionUTC IS NOT NULL)
            )
        );
        CREATE UNIQUE NONCLUSTERED INDEX UX_ReservasCupon_Checkout_Activa
            ON dbo.ReservasCupon (IdCheckout)
            WHERE Estado = ''ACTIVA'';
        -- Historial completo y FK por checkout.
        CREATE NONCLUSTERED INDEX IX_ReservasCupon_IdCheckout
            ON dbo.ReservasCupon (IdCheckout);
        -- Capacidad global del cupón y reservas por usuario dentro del conjunto vigente.
        CREATE NONCLUSTERED INDEX IX_ReservasCupon_Cupon_Estado_Expiracion
            ON dbo.ReservasCupon (IdCupon, Estado, FechaExpiracionUTC)
            INCLUDE (IdUsuario);
        -- Consultas y FK por usuario; el índice anterior no tiene ese prefijo.
        CREATE NONCLUSTERED INDEX IX_ReservasCupon_Usuario_Cupon_Estado_Expiracion
            ON dbo.ReservasCupon (IdUsuario, IdCupon, Estado, FechaExpiracionUTC);
        CREATE NONCLUSTERED INDEX IX_ReservasCupon_Activas_Expiracion
            ON dbo.ReservasCupon (FechaExpiracionUTC)
            WHERE Estado = ''ACTIVA'';
    ';

    -- Registro técnico y DDL se confirman o revierten juntos.
    EXEC sys.sp_executesql N'
        INSERT INTO dbo.VersionesMigracion
            ([Version], NombreArchivo, SHA256, FechaAplicacionUTC, Ejecutor)
        VALUES
            (8, N''008_Reservas.sql'', @Huella, SYSUTCDATETIME(), ORIGINAL_LOGIN());
    ', N'@Huella varbinary(32)', @Huella = @SHA256;

    COMMIT TRANSACTION;
    PRINT N'Migración 008 completada: dos tablas de reservas y registro técnico confirmados.';
END TRY
BEGIN CATCH
    IF XACT_STATE() <> 0
        ROLLBACK TRANSACTION;
    THROW;
END CATCH;

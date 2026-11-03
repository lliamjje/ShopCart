/*
    010_DevolucionesAuditoria.sql — Devoluciones, reembolsos y auditoría.
    Ejecutar COMPLETO como un único lote, sin GO, conectado a ShopCart.
    Iniciar con Auto-commit, sin transacciones abiertas ni implícitas.
    No ejecutar selecciones parciales ni cambios administrativos concurrentes.

    Tras aprobar el archivo FINAL, calcular SHA-256 mediante Get-FileHash.
    No editar después; suministrar 32 bytes binary/varbinary mediante
    sp_set_session_context en la MISMA conexión de DataGrip, clave
    ShopCart.Migracion010.SHA256. Limpiar el contexto al terminar.
    SQL valida formato; el ejecutor verifica la correspondencia archivo/huella.

    Diseño confirmado: Reembolsos es independiente de Pagos y solo representa
    operaciones monetarias positivas por devolución, no cancelaciones de pedidos.
    Una devolución de importe reembolsable cero no crea una fila en Reembolsos.
    No se agregan procesador ni importes autorizados por solicitud/línea.
    Su estructura complementaria, los reembolsos por cancelación, el historial de
    estados de pedido y el filtro de auditoría por módulo se evaluarán en otra
    migración antes de implementar los SP que los necesiten.

    Futuros SP transaccionales:
    - Autorizar solicitante y validar pedido ENTREGADO; permitir devoluciones
      parciales sin superar cantidades compradas. Contar SOLICITADA, APROBADA,
      RECIBIDA y COMPLETADA; excluir RECHAZADA y CANCELADA de capacidad ocupada.
      Bloquear con disciplina común al comprobar y registrar, incluso concurrentes.
    - Comprobar que cada IdDetallePedido pertenece al pedido de la devolución
      y que IdPago corresponde al mismo pedido y a un pago APROBADO.
      Las FK simples no garantizan estas relaciones ni autorización.
    - Definir transiciones y momentos de reintegro y reembolso. Un cambio de
      estado por sí solo NO reintegra existencias ni ejecuta un reembolso.
      Coordinar existencias, kardex, reembolso y auditoría atómicamente,
      identificando cada evento físico para evitar movimientos duplicados.
    - Controlar importes autorizados e importes acumulados por devolución y pago,
      sin superar el cobro aprobado; usar GTQ decimal(19,4) y precisión ampliada
      para acumulaciones. No reembolsar automáticamente el envío en devoluciones.
    - Comparar contenido al reutilizar claves idempotentes y devolver el resultado
      registrado. Claves diferentes no autorizan duplicar un mismo reembolso.
      Mantener historial de solicitudes y operaciones, incluidas las rechazadas.
    - Actualizar FechaActualizacionUTC y fechas de resolución explícitamente:
      los DEFAULT solo inicializan; los CHECK no restringen transiciones.
    - Insertar auditoría dentro de cada transacción de negocio, sin contraseñas,
      hashes de contraseñas, tokens, credenciales ni secretos. DatosAnteriores y
      DatosNuevos admiten NULL u objetos/arreglos JSON válidos; no texto libre.

    Permisos pendientes: las migraciones 001-009 no definen un rol SQL inequívoco
    para la aplicación. No se crea rol ni se aplica DENY a public. En la etapa
    de seguridad, utilizar cuenta de privilegios mínimos, acceso mediante SP y
    sin permisos directos de modificación/eliminación de EventosAuditoria.
    Esta migración NO impone todavía su carácter de solo inserción por permisos.
    Las cuentas administrativas privilegiadas quedan fuera de esa protección.
*/
IF DB_NAME() <> N'ShopCart'
    THROW 60000, N'010 solo puede ejecutarse en la base ShopCart.', 1;

IF @@TRANCOUNT <> 0 OR (2 & @@OPTIONS) = 2
    THROW 60001, N'Inicie con Auto-commit y sin transacciones abiertas o implícitas.', 1;

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
    THROW 60002, N'Se requiere CONTROL sobre ShopCart para inspeccionar y crear el esquema.', 1;

IF NOT EXISTS (
    SELECT 1 FROM sys.databases
    WHERE database_id = DB_ID()
      AND collation_name = N'Latin1_General_100_CI_AI_SC'
      AND recovery_model_desc = N'SIMPLE'
      AND state_desc = N'ONLINE' AND user_access_desc = N'MULTI_USER'
      AND is_read_only = 0 AND source_database_id IS NULL
)
    THROW 60003, N'Las propiedades de ShopCart no coinciden con el arranque 001.', 1;

DECLARE @HuellaRecibida sql_variant = SESSION_CONTEXT(N'ShopCart.Migracion010.SHA256');
IF @HuellaRecibida IS NULL
   OR CONVERT(nvarchar(128), SQL_VARIANT_PROPERTY(@HuellaRecibida, 'BaseType')) NOT IN (N'binary', N'varbinary')
    THROW 60004, N'Suministre el SHA-256 real como valor binario en SESSION_CONTEXT antes de ejecutar 010.', 1;

DECLARE @SHA256 varbinary(max) = CONVERT(varbinary(max), @HuellaRecibida);
IF DATALENGTH(@SHA256) <> 32
    THROW 60005, N'La huella SHA-256 debe contener exactamente 32 bytes.', 1;

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
        THROW 60006, N'No se pudo obtener el bloqueo exclusivo de migraciones.', 1;

    DECLARE @IDVersiones int = OBJECT_ID(N'dbo.VersionesMigracion', N'U');
    IF @IDVersiones IS NULL
        THROW 60007, N'Falta la tabla técnica creada por 001. No se aplicará 010.', 1;

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
        THROW 60008, N'Las columnas de VersionesMigracion no cumplen el contrato de 001.', 1;

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
        THROW 60009, N'VersionesMigracion requiere la PK clustered de 001 sobre Version.', 1;

    IF EXISTS (SELECT 1 FROM sys.triggers WHERE parent_id = @IDVersiones)
       OR EXISTS (SELECT 1 FROM sys.tables WHERE object_id = @IDVersiones
                  AND (temporal_type <> 0 OR is_memory_optimized = 1))
        THROW 60010, N'VersionesMigracion tiene características inesperadas; revisar manualmente.', 1;

    -- Lote inferior: errores de compilación/resolución quedan dentro del TRY externo.
    EXEC sys.sp_executesql N'
        IF NOT EXISTS (
            SELECT 1 FROM dbo.VersionesMigracion WITH (UPDLOCK, HOLDLOCK)
            WHERE [Version] = 9 AND NombreArchivo = N''009_PedidosPagos.sql''
        )
            THROW 60013, N''Debe estar registrada la migración 009_PedidosPagos.sql antes de aplicar 010.'', 1;
        IF EXISTS (SELECT 1 FROM dbo.VersionesMigracion WITH (UPDLOCK, HOLDLOCK)
                   WHERE [Version] >= 10)
            THROW 60011, N''010 o una migración posterior ya está registrada. No se reaplica ni se certifica el esquema existente.'', 1;
    ';

    IF EXISTS (
        SELECT 1 FROM sys.objects AS o
        JOIN sys.schemas AS s ON s.schema_id = o.schema_id
        WHERE s.name = N'dbo'
          AND o.name IN (N'Devoluciones', N'DetallesDevolucion', N'Reembolsos', N'EventosAuditoria')
    )
        THROW 60012, N'Ya existe parte o todo el esquema de devoluciones y auditoría sin registro compatible. Revisar manualmente; no se reparará.', 1;

    -- Verifica tablas y tipos nativos de las claves que serán destinos de FK.
    -- Al crear las FK se comprueban también las claves candidatas de destino.
    IF EXISTS (
        SELECT 1
        FROM (VALUES
            (N'dbo.Pedidos', N'IdPedido', N'bigint'),
            (N'dbo.DetallesPedido', N'IdDetallePedido', N'bigint'),
            (N'dbo.Pagos', N'IdPago', N'bigint'),
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
        THROW 60014, N'Faltan tablas previas o sus claves no tienen los tipos requeridos.', 1;

    -- DDL constante en un lote inferior: sus errores alcanzan el CATCH externo.
    EXEC sys.sp_executesql N'
        CREATE TABLE dbo.Devoluciones
        (
            IdDevolucion bigint IDENTITY(1,1) NOT NULL,
            IdPedido bigint NOT NULL,
            IdUsuarioSolicitante bigint NULL,
            Estado varchar(25) NOT NULL
                CONSTRAINT DF_Devoluciones_Estado DEFAULT (''SOLICITADA''),
            Motivo nvarchar(500) NOT NULL,
            Observaciones nvarchar(1000) NULL,
            FechaSolicitudUTC datetime2(7) NOT NULL
                CONSTRAINT DF_Devoluciones_FechaSolicitudUTC DEFAULT (SYSUTCDATETIME()),
            FechaActualizacionUTC datetime2(7) NOT NULL
                CONSTRAINT DF_Devoluciones_FechaActualizacionUTC DEFAULT (SYSUTCDATETIME()),
            FechaResolucionUTC datetime2(7) NULL,
            CONSTRAINT PK_Devoluciones PRIMARY KEY CLUSTERED (IdDevolucion),
            CONSTRAINT FK_Devoluciones_Pedidos FOREIGN KEY (IdPedido)
                REFERENCES dbo.Pedidos (IdPedido) ON DELETE NO ACTION ON UPDATE NO ACTION,
            CONSTRAINT FK_Devoluciones_UsuariosSolicitantes FOREIGN KEY (IdUsuarioSolicitante)
                REFERENCES dbo.Usuarios (IdUsuario) ON DELETE NO ACTION ON UPDATE NO ACTION,
            CONSTRAINT CK_Devoluciones_EstadoPermitido CHECK (
                Estado IN (''SOLICITADA'', ''APROBADA'', ''RECHAZADA'', ''RECIBIDA'', ''COMPLETADA'', ''CANCELADA'')
            ),
            -- Recorta espacios normales U+0020; DATALENGTH detecta los exteriores.
            CONSTRAINT CK_Devoluciones_MotivoValido CHECK (
                LEN(LTRIM(RTRIM(Motivo))) > 0
                AND DATALENGTH(Motivo) = DATALENGTH(LTRIM(RTRIM(Motivo)))
            ),
            CONSTRAINT CK_Devoluciones_ResolucionCoherente CHECK (
                (Estado IN (''SOLICITADA'', ''APROBADA'', ''RECIBIDA'') AND FechaResolucionUTC IS NULL)
                OR (Estado IN (''RECHAZADA'', ''COMPLETADA'', ''CANCELADA'') AND FechaResolucionUTC IS NOT NULL)
            )
        );
        -- Historial por pedido y fecha; no UNIQUE: admite solicitudes parciales múltiples.
        CREATE NONCLUSTERED INDEX IX_Devoluciones_Pedido_Fecha
            ON dbo.Devoluciones (IdPedido, FechaSolicitudUTC);
        -- Cola operativa por estado y rango de fecha.
        CREATE NONCLUSTERED INDEX IX_Devoluciones_Estado_Fecha
            ON dbo.Devoluciones (Estado, FechaSolicitudUTC);
        -- FK y consultas del solicitante, incluidas solicitudes históricas.
        CREATE NONCLUSTERED INDEX IX_Devoluciones_IdUsuarioSolicitante
            ON dbo.Devoluciones (IdUsuarioSolicitante);

        CREATE TABLE dbo.DetallesDevolucion
        (
            IdDetalleDevolucion bigint IDENTITY(1,1) NOT NULL,
            IdDevolucion bigint NOT NULL,
            IdDetallePedido bigint NOT NULL,
            Cantidad int NOT NULL,
            Motivo nvarchar(500) NULL,
            FechaCreacionUTC datetime2(7) NOT NULL
                CONSTRAINT DF_DetallesDevolucion_FechaCreacionUTC DEFAULT (SYSUTCDATETIME()),
            CONSTRAINT PK_DetallesDevolucion PRIMARY KEY CLUSTERED (IdDetalleDevolucion),
            CONSTRAINT FK_DetallesDevolucion_Devoluciones FOREIGN KEY (IdDevolucion)
                REFERENCES dbo.Devoluciones (IdDevolucion) ON DELETE NO ACTION ON UPDATE NO ACTION,
            CONSTRAINT FK_DetallesDevolucion_DetallesPedido FOREIGN KEY (IdDetallePedido)
                REFERENCES dbo.DetallesPedido (IdDetallePedido) ON DELETE NO ACTION ON UPDATE NO ACTION,
            CONSTRAINT UQ_DetallesDevolucion_Devolucion_DetallePedido
                UNIQUE NONCLUSTERED (IdDevolucion, IdDetallePedido),
            CONSTRAINT CK_DetallesDevolucion_CantidadPositiva CHECK (Cantidad > 0)
        );
        -- Consulta acumulada por línea y FK; la UNIQUE cubre el prefijo IdDevolucion.
        CREATE NONCLUSTERED INDEX IX_DetallesDevolucion_IdDetallePedido
            ON dbo.DetallesDevolucion (IdDetallePedido) INCLUDE (Cantidad);

        CREATE TABLE dbo.Reembolsos
        (
            IdReembolso bigint IDENTITY(1,1) NOT NULL,
            IdDevolucion bigint NOT NULL,
            IdPago bigint NOT NULL,
            ClaveIdempotenciaHash binary(32) NOT NULL,
            ReferenciaReembolso varchar(80) NOT NULL,
            Estado varchar(20) NOT NULL
                CONSTRAINT DF_Reembolsos_Estado DEFAULT (''PENDIENTE''),
            Monto decimal(19,4) NOT NULL,
            Moneda char(3) NOT NULL CONSTRAINT DF_Reembolsos_Moneda DEFAULT (''GTQ''),
            CodigoResultado varchar(40) NULL,
            MensajeResultado nvarchar(250) NULL,
            FechaCreacionUTC datetime2(7) NOT NULL
                CONSTRAINT DF_Reembolsos_FechaCreacionUTC DEFAULT (SYSUTCDATETIME()),
            FechaActualizacionUTC datetime2(7) NOT NULL
                CONSTRAINT DF_Reembolsos_FechaActualizacionUTC DEFAULT (SYSUTCDATETIME()),
            FechaResolucionUTC datetime2(7) NULL,
            CONSTRAINT PK_Reembolsos PRIMARY KEY CLUSTERED (IdReembolso),
            CONSTRAINT FK_Reembolsos_Devoluciones FOREIGN KEY (IdDevolucion)
                REFERENCES dbo.Devoluciones (IdDevolucion) ON DELETE NO ACTION ON UPDATE NO ACTION,
            CONSTRAINT FK_Reembolsos_Pagos FOREIGN KEY (IdPago)
                REFERENCES dbo.Pagos (IdPago) ON DELETE NO ACTION ON UPDATE NO ACTION,
            CONSTRAINT UQ_Reembolsos_ClaveIdempotenciaHash
                UNIQUE NONCLUSTERED (ClaveIdempotenciaHash),
            CONSTRAINT UQ_Reembolsos_ReferenciaReembolso
                UNIQUE NONCLUSTERED (ReferenciaReembolso),
            CONSTRAINT CK_Reembolsos_EstadoPermitido CHECK (
                Estado IN (''PENDIENTE'', ''APROBADO'', ''RECHAZADO'', ''CANCELADO'')
            ),
            CONSTRAINT CK_Reembolsos_MontoPositivo CHECK (Monto > 0),
            CONSTRAINT CK_Reembolsos_MonedaGTQ CHECK (Moneda = ''GTQ''),
            CONSTRAINT CK_Reembolsos_ResolucionCoherente CHECK (
                (Estado = ''PENDIENTE'' AND FechaResolucionUTC IS NULL)
                OR (Estado IN (''APROBADO'', ''RECHAZADO'', ''CANCELADO'') AND FechaResolucionUTC IS NOT NULL)
            )
        );
        -- No son únicos: conservan múltiples operaciones e intentos por devolución/pago.
        CREATE NONCLUSTERED INDEX IX_Reembolsos_Devolucion_Fecha
            ON dbo.Reembolsos (IdDevolucion, FechaCreacionUTC);
        -- Localiza operaciones del pago para comprobar acumulaciones bajo bloqueo.
        CREATE NONCLUSTERED INDEX IX_Reembolsos_Pago_Estado
            ON dbo.Reembolsos (IdPago, Estado) INCLUDE (Monto);

        CREATE TABLE dbo.EventosAuditoria
        (
            IdEventoAuditoria bigint IDENTITY(1,1) NOT NULL,
            IdUsuarioActor bigint NULL,
            Accion varchar(100) NOT NULL,
            Entidad varchar(100) NOT NULL,
            IdEntidad bigint NULL,
            DatosAnteriores nvarchar(max) NULL,
            DatosNuevos nvarchar(max) NULL,
            IdCorrelacion uniqueidentifier NULL,
            FechaEventoUTC datetime2(7) NOT NULL
                CONSTRAINT DF_EventosAuditoria_FechaEventoUTC DEFAULT (SYSUTCDATETIME()),
            CONSTRAINT PK_EventosAuditoria PRIMARY KEY CLUSTERED (IdEventoAuditoria),
            CONSTRAINT FK_EventosAuditoria_UsuariosActores FOREIGN KEY (IdUsuarioActor)
                REFERENCES dbo.Usuarios (IdUsuario) ON DELETE NO ACTION ON UPDATE NO ACTION,
            CONSTRAINT CK_EventosAuditoria_AccionValida CHECK (
                LEN(LTRIM(RTRIM(Accion))) > 0
                AND DATALENGTH(Accion) = DATALENGTH(LTRIM(RTRIM(Accion)))
            ),
            CONSTRAINT CK_EventosAuditoria_EntidadValida CHECK (
                LEN(LTRIM(RTRIM(Entidad))) > 0
                AND DATALENGTH(Entidad) = DATALENGTH(LTRIM(RTRIM(Entidad)))
            ),
            CONSTRAINT CK_EventosAuditoria_DatosAnterioresJSON CHECK (
                DatosAnteriores IS NULL OR ISJSON(DatosAnteriores) = 1
            ),
            CONSTRAINT CK_EventosAuditoria_DatosNuevosJSON CHECK (
                DatosNuevos IS NULL OR ISJSON(DatosNuevos) = 1
            )
        );
        -- Actor y rango temporal; también cubre la FK opcional.
        CREATE NONCLUSTERED INDEX IX_EventosAuditoria_Actor_Fecha
            ON dbo.EventosAuditoria (IdUsuarioActor, FechaEventoUTC);
        -- Historial de entidad/registro; IdEntidad es polimórfico y no tiene FK.
        CREATE NONCLUSTERED INDEX IX_EventosAuditoria_Entidad_Registro_Fecha
            ON dbo.EventosAuditoria (Entidad, IdEntidad, FechaEventoUTC);
        -- Consulta cronológica global, sin exigir un actor o entidad.
        CREATE NONCLUSTERED INDEX IX_EventosAuditoria_Fecha
            ON dbo.EventosAuditoria (FechaEventoUTC, IdEventoAuditoria);
        -- Correlación de una operación; no indexa eventos sin correlación.
        CREATE NONCLUSTERED INDEX IX_EventosAuditoria_Correlacion_Fecha
            ON dbo.EventosAuditoria (IdCorrelacion, FechaEventoUTC)
            WHERE IdCorrelacion IS NOT NULL;
    ';

    -- Registro técnico y DDL se confirman o revierten juntos.
    EXEC sys.sp_executesql N'
        INSERT INTO dbo.VersionesMigracion
            ([Version], NombreArchivo, SHA256, FechaAplicacionUTC, Ejecutor)
        VALUES
            (10, N''010_DevolucionesAuditoria.sql'', @Huella, SYSUTCDATETIME(), ORIGINAL_LOGIN());
    ', N'@Huella varbinary(32)', @Huella = @SHA256;

    COMMIT TRANSACTION;
    PRINT N'Migración 010 completada: cuatro tablas y registro técnico confirmados; permisos de auditoría pendientes.';
END TRY
BEGIN CATCH
    IF XACT_STATE() <> 0
        ROLLBACK TRANSACTION;
    THROW;
END CATCH;


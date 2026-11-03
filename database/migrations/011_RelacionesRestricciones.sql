/*
    011_RelacionesRestricciones.sql — Estructuras y relaciones complementarias.
    Ejecutar COMPLETO como un único lote, sin GO, conectado a ShopCart.
    Iniciar con Auto-commit, sin transacciones abiertas ni implícitas.
    No ejecutar selecciones parciales ni cambios administrativos concurrentes.

    Calcular SHA-256 del archivo FINAL aprobado mediante Get-FileHash.
    No editar después; suministrar sus 32 bytes binary/varbinary mediante
    sp_set_session_context en la MISMA conexión de DataGrip, clave
    ShopCart.Migracion011.SHA256. Limpiar el contexto al terminar.
    SQL valida formato; el ejecutor verifica la correspondencia archivo/huella.

    UsosCupon conserva solo las cinco columnas confirmadas. UNIQUE(IdPedido)
    hace redundante UNIQUE(IdCupon, IdPedido); no se crea esta última.
    La clave candidata adicional en Pedidos sí es necesaria como destino EXACTO
    de la FK compuesta que comprueba el cupón. No identifica la reserva original.
    Descuento histórico: Pedidos.Descuento y detalles; reserva mediante IdCheckout.

    ReservasInventario debe referenciar una variante presente en DetallesCheckout.
    Se reutiliza su UNIQUE existente y el índice completo de reservas de 008.
    Se conservan los índices y FK anteriores; no se modifican archivos aplicados.
    Las nuevas restricciones validan datos existentes: ante incompatibilidades
    se revierte todo, sin WITH NOCHECK, correcciones ni borrados automáticos.

    ReembolsosCancelacion permite historial de operaciones monetarias positivas
    por cancelación sin devolución física. La FK compuesta garantiza que IdPago
    pertenece a IdPedido; la clave candidata en Pagos es su destino exacto.
    No se limita a una fila por pedido/pago: admite intentos históricos legítimos.
    Cancelar un pedido gratuito no crea una operación monetaria de importe cero.
    Las claves y referencias son únicas DENTRO de cada tabla de reembolsos;
    los SP deberán distinguir el tipo de operación al resolver idempotencia.

    Pendientes para SP transaccionales:
    - Autorizar rol y propiedad de carrito, dirección, checkout y pedido,
      también para invitados. Las FK no sustituyen la autorización ni prueban
      igualdad de propietarios cuando hay IdUsuario NULL.
    - Reservar con bloqueos de Existencias y Cupones, sin sobreventa ni excesos
      de usos. Vigencia efectiva: estado ACTIVA y vencimiento UTC futuro.
    - Al confirmar cupón, comprobar reserva original del checkout del pedido,
      vigencia, cupón y comprador autenticado cuando aplique. Registrar un uso
      y resolver la reserva en la misma transacción, sin contar ambos dos veces.
      Serializar límites globales y por usuario; no restituir usos por devolución.
    - Idempotencia de checkout, pedido, pago y reembolso: comparar contenido y
      devolver resultado registrado. Claves distintas no justifican duplicados.
    - Validar pago APROBADO, estado cancelable y transición del pedido; sumar
      reembolsos aprobados de AMBAS tablas y considerar operaciones pendientes
      que comprometan capacidad. Bloquear el pago original con disciplina común.
      No superar lo pagado ni lo autorizado; respetar política de envío.
    - Devoluciones: validar pertenencia del detalle y del pago al mismo pedido.
      Cantidades SOLICITADA/APROBADA/RECIBIDA/COMPLETADA ocupan capacidad;
      RECHAZADA/CANCELADA no. Comprobar acumulaciones bajo bloqueos.
      No se agregan columnas redundantes a las tablas de 010 para estas relaciones.
    - Coordinar inventario, kardex, cupón, pago/reembolso e historial sin duplicar
      eventos físicos. Usar referencias de origen del kardex con significado único.
    - Conciliar importes y líneas con precisión ampliada, GTQ e IVA 12 % incluido;
      no sumarlo otra vez. Mantener instantáneas e importes confirmados inmutables.
    - Registrar estado inicial con EstadoAnterior NULL y cada transición posterior
      junto con pedido y auditoría en la misma transacción. CHECK limita valores,
      no la secuencia de cambios; actor NULL representa sistema/invitado autorizado.
    - Actualizar fechas explícitamente; DEFAULT solo inicializa.
    - Auditoría sin secretos, mediante SP. El filtro por módulo requiere un mapeo
      de entidades definido antes de los SP; no se altera EventosAuditoria aquí.
    Seguridad pendiente: cuenta de privilegios mínimos y SP; proteger auditoría
    e historial frente a UPDATE/DELETE ordinarios al configurar el rol de aplicación.
    No hay rol SQL inequívoco en 001-010: no se crean roles ni se aplica DENY a public.
    No se implementan SP, semillas ni el flujo transaccional de negocio en este archivo.
*/
IF DB_NAME() <> N'ShopCart'
    THROW 61000, N'011 solo puede ejecutarse en la base ShopCart.', 1;

IF @@TRANCOUNT <> 0 OR (2 & @@OPTIONS) = 2
    THROW 61001, N'Inicie con Auto-commit y sin transacciones abiertas o implícitas.', 1;

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
    THROW 61002, N'Se requiere CONTROL sobre ShopCart para inspeccionar y crear el esquema.', 1;

IF NOT EXISTS (
    SELECT 1 FROM sys.databases
    WHERE database_id = DB_ID()
      AND collation_name = N'Latin1_General_100_CI_AI_SC'
      AND recovery_model_desc = N'SIMPLE'
      AND state_desc = N'ONLINE' AND user_access_desc = N'MULTI_USER'
      AND is_read_only = 0 AND source_database_id IS NULL
)
    THROW 61003, N'Las propiedades de ShopCart no coinciden con el arranque 001.', 1;

DECLARE @HuellaRecibida sql_variant = SESSION_CONTEXT(N'ShopCart.Migracion011.SHA256');
IF @HuellaRecibida IS NULL
   OR CONVERT(nvarchar(128), SQL_VARIANT_PROPERTY(@HuellaRecibida, 'BaseType')) NOT IN (N'binary', N'varbinary')
    THROW 61004, N'Suministre el SHA-256 real como valor binario en SESSION_CONTEXT antes de ejecutar 011.', 1;

DECLARE @SHA256 varbinary(max) = CONVERT(varbinary(max), @HuellaRecibida);
IF DATALENGTH(@SHA256) <> 32
    THROW 61005, N'La huella SHA-256 debe contener exactamente 32 bytes.', 1;

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
        THROW 61006, N'No se pudo obtener el bloqueo exclusivo de migraciones.', 1;

    DECLARE @IDVersiones int = OBJECT_ID(N'dbo.VersionesMigracion', N'U');
    IF @IDVersiones IS NULL
        THROW 61007, N'Falta la tabla técnica creada por 001. No se aplicará 011.', 1;

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
        THROW 61008, N'Las columnas de VersionesMigracion no cumplen el contrato de 001.', 1;

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
        THROW 61009, N'VersionesMigracion requiere la PK clustered de 001 sobre Version.', 1;

    IF EXISTS (SELECT 1 FROM sys.triggers WHERE parent_id = @IDVersiones)
       OR EXISTS (SELECT 1 FROM sys.tables WHERE object_id = @IDVersiones
                  AND (temporal_type <> 0 OR is_memory_optimized = 1))
        THROW 61010, N'VersionesMigracion tiene características inesperadas; revisar manualmente.', 1;

    -- Lote inferior: errores de compilación/resolución quedan dentro del TRY externo.
    EXEC sys.sp_executesql N'
        IF NOT EXISTS (
            SELECT 1 FROM dbo.VersionesMigracion WITH (UPDLOCK, HOLDLOCK)
            WHERE [Version] = 10 AND NombreArchivo = N''010_DevolucionesAuditoria.sql''
        )
            THROW 61013, N''Debe estar registrada la migración 010_DevolucionesAuditoria.sql antes de aplicar 011.'', 1;
        IF EXISTS (SELECT 1 FROM dbo.VersionesMigracion WITH (UPDLOCK, HOLDLOCK)
                   WHERE [Version] >= 11)
            THROW 61011, N''011 o una migración posterior ya está registrada. No se reaplica ni se certifica el esquema existente.'', 1;
    ';

    IF EXISTS (
        SELECT 1 FROM sys.objects AS o
        JOIN sys.schemas AS s ON s.schema_id = o.schema_id
        WHERE s.name = N'dbo'
          AND o.name IN (N'UsosCupon', N'HistorialEstadosPedido', N'ReembolsosCancelacion',
                         N'UQ_Pedidos_Pedido_Cupon', N'UQ_Pagos_Pedido_Pago',
                         N'FK_ReservasInventario_DetallesCheckout')
    )
        THROW 61012, N'Ya existe parte o todo el esquema complementario sin registro compatible. Revisar manualmente; no se reparará.', 1;

    -- Verifica columnas utilizadas por las nuevas FK y claves candidatas.
    IF EXISTS (
        SELECT 1
        FROM (VALUES
            (N'dbo.Usuarios', N'IdUsuario', 0),
            (N'dbo.Cupones', N'IdCupon', 0),
            (N'dbo.Pedidos', N'IdPedido', 0),
            (N'dbo.Pedidos', N'IdCupon', 1),
            (N'dbo.Pagos', N'IdPago', 0),
            (N'dbo.Pagos', N'IdPedido', 0),
            (N'dbo.DetallesCheckout', N'IdCheckout', 0),
            (N'dbo.DetallesCheckout', N'IdVariante', 0),
            (N'dbo.ReservasInventario', N'IdCheckout', 0),
            (N'dbo.ReservasInventario', N'IdVariante', 0)
        ) AS e(Tabla, Columna, AdmiteNull)
        WHERE NOT EXISTS (
            SELECT 1 FROM sys.columns AS c
            WHERE c.object_id = OBJECT_ID(e.Tabla, N'U')
              AND c.name = e.Columna AND c.system_type_id = TYPE_ID(N'bigint')
              AND c.user_type_id = c.system_type_id
              AND c.is_nullable = e.AdmiteNull AND c.is_computed = 0
        )
    )
        THROW 61014, N'Faltan tablas previas o sus columnas no cumplen el contrato requerido.', 1;

    -- DDL constante en un lote inferior: sus errores alcanzan el CATCH externo.
    EXEC sys.sp_executesql N'
        -- Claves candidatas necesarias para las nuevas FK compuestas.
        ALTER TABLE dbo.Pedidos
            ADD CONSTRAINT UQ_Pedidos_Pedido_Cupon UNIQUE NONCLUSTERED (IdPedido, IdCupon);
        ALTER TABLE dbo.Pagos
            ADD CONSTRAINT UQ_Pagos_Pedido_Pago UNIQUE NONCLUSTERED (IdPedido, IdPago);

        -- Valida todas las reservas existentes; no descarta datos incompatibles.
        ALTER TABLE dbo.ReservasInventario WITH CHECK
            ADD CONSTRAINT FK_ReservasInventario_DetallesCheckout
            FOREIGN KEY (IdCheckout, IdVariante)
            REFERENCES dbo.DetallesCheckout (IdCheckout, IdVariante)
            ON DELETE NO ACTION ON UPDATE NO ACTION;

        CREATE TABLE dbo.UsosCupon
        (
            IdUsoCupon bigint IDENTITY(1,1) NOT NULL,
            IdCupon bigint NOT NULL,
            IdPedido bigint NOT NULL,
            IdUsuario bigint NULL,
            FechaUsoUTC datetime2(7) NOT NULL
                CONSTRAINT DF_UsosCupon_FechaUsoUTC DEFAULT (SYSUTCDATETIME()),
            CONSTRAINT PK_UsosCupon PRIMARY KEY CLUSTERED (IdUsoCupon),
            CONSTRAINT UQ_UsosCupon_IdPedido UNIQUE NONCLUSTERED (IdPedido),
            CONSTRAINT FK_UsosCupon_Cupones FOREIGN KEY (IdCupon)
                REFERENCES dbo.Cupones (IdCupon) ON DELETE NO ACTION ON UPDATE NO ACTION,
            -- Comprueba existencia del pedido Y coincidencia del cupón, sin FK simple duplicada.
            CONSTRAINT FK_UsosCupon_Pedido_Cupon FOREIGN KEY (IdPedido, IdCupon)
                REFERENCES dbo.Pedidos (IdPedido, IdCupon) ON DELETE NO ACTION ON UPDATE NO ACTION,
            CONSTRAINT FK_UsosCupon_Usuarios FOREIGN KEY (IdUsuario)
                REFERENCES dbo.Usuarios (IdUsuario) ON DELETE NO ACTION ON UPDATE NO ACTION
        );
        -- Conteo global por cupón y por comprador dentro del mismo cupón.
        CREATE NONCLUSTERED INDEX IX_UsosCupon_Cupon_Usuario
            ON dbo.UsosCupon (IdCupon, IdUsuario);
        -- Consultas/FK por usuario; el índice anterior tiene otro prefijo.
        CREATE NONCLUSTERED INDEX IX_UsosCupon_Usuario_Cupon
            ON dbo.UsosCupon (IdUsuario, IdCupon);

        CREATE TABLE dbo.HistorialEstadosPedido
        (
            IdHistorialEstadoPedido bigint IDENTITY(1,1) NOT NULL,
            IdPedido bigint NOT NULL,
            EstadoAnterior varchar(25) NULL,
            EstadoNuevo varchar(25) NOT NULL,
            IdUsuarioActor bigint NULL,
            Observacion nvarchar(500) NULL,
            FechaCambioUTC datetime2(7) NOT NULL
                CONSTRAINT DF_HistorialEstadosPedido_FechaCambioUTC DEFAULT (SYSUTCDATETIME()),
            CONSTRAINT PK_HistorialEstadosPedido PRIMARY KEY CLUSTERED (IdHistorialEstadoPedido),
            CONSTRAINT FK_HistorialEstadosPedido_Pedidos FOREIGN KEY (IdPedido)
                REFERENCES dbo.Pedidos (IdPedido) ON DELETE NO ACTION ON UPDATE NO ACTION,
            CONSTRAINT FK_HistorialEstadosPedido_UsuariosActores FOREIGN KEY (IdUsuarioActor)
                REFERENCES dbo.Usuarios (IdUsuario) ON DELETE NO ACTION ON UPDATE NO ACTION,
            CONSTRAINT CK_HistorialEstadosPedido_EstadoAnteriorPermitido CHECK (
                EstadoAnterior IS NULL OR EstadoAnterior IN (''PENDIENTE_PAGO'', ''PAGADO'', ''EN_PREPARACION'', ''ENVIADO'', ''ENTREGADO'', ''CANCELADO'')
            ),
            CONSTRAINT CK_HistorialEstadosPedido_EstadoNuevoPermitido CHECK (
                EstadoNuevo IN (''PENDIENTE_PAGO'', ''PAGADO'', ''EN_PREPARACION'', ''ENVIADO'', ''ENTREGADO'', ''CANCELADO'')
            ),
            CONSTRAINT CK_HistorialEstadosPedido_EstadosDistintos CHECK (
                EstadoAnterior IS NULL OR EstadoAnterior <> EstadoNuevo
            )
        );
        -- Orden estable si coinciden fechas; también cubre la FK de pedido.
        CREATE NONCLUSTERED INDEX IX_HistorialEstadosPedido_Pedido_Fecha
            ON dbo.HistorialEstadosPedido (IdPedido, FechaCambioUTC, IdHistorialEstadoPedido);
        CREATE NONCLUSTERED INDEX IX_HistorialEstadosPedido_IdUsuarioActor
            ON dbo.HistorialEstadosPedido (IdUsuarioActor);

        CREATE TABLE dbo.ReembolsosCancelacion
        (
            IdReembolsoCancelacion bigint IDENTITY(1,1) NOT NULL,
            IdPedido bigint NOT NULL,
            IdPago bigint NOT NULL,
            ClaveIdempotenciaHash binary(32) NOT NULL,
            ReferenciaReembolso varchar(80) NOT NULL,
            Estado varchar(20) NOT NULL
                CONSTRAINT DF_ReembolsosCancelacion_Estado DEFAULT (''PENDIENTE''),
            Monto decimal(19,4) NOT NULL,
            Moneda char(3) NOT NULL
                CONSTRAINT DF_ReembolsosCancelacion_Moneda DEFAULT (''GTQ''),
            CodigoResultado varchar(40) NULL,
            MensajeResultado nvarchar(250) NULL,
            FechaCreacionUTC datetime2(7) NOT NULL
                CONSTRAINT DF_ReembolsosCancelacion_FechaCreacionUTC DEFAULT (SYSUTCDATETIME()),
            FechaActualizacionUTC datetime2(7) NOT NULL
                CONSTRAINT DF_ReembolsosCancelacion_FechaActualizacionUTC DEFAULT (SYSUTCDATETIME()),
            FechaResolucionUTC datetime2(7) NULL,
            CONSTRAINT PK_ReembolsosCancelacion PRIMARY KEY CLUSTERED (IdReembolsoCancelacion),
            CONSTRAINT FK_ReembolsosCancelacion_Pedidos FOREIGN KEY (IdPedido)
                REFERENCES dbo.Pedidos (IdPedido) ON DELETE NO ACTION ON UPDATE NO ACTION,
            CONSTRAINT FK_ReembolsosCancelacion_Pedido_Pago FOREIGN KEY (IdPedido, IdPago)
                REFERENCES dbo.Pagos (IdPedido, IdPago) ON DELETE NO ACTION ON UPDATE NO ACTION,
            CONSTRAINT UQ_ReembolsosCancelacion_ClaveIdempotenciaHash
                UNIQUE NONCLUSTERED (ClaveIdempotenciaHash),
            CONSTRAINT UQ_ReembolsosCancelacion_ReferenciaReembolso
                UNIQUE NONCLUSTERED (ReferenciaReembolso),
            CONSTRAINT CK_ReembolsosCancelacion_MontoPositivo CHECK (Monto > 0),
            CONSTRAINT CK_ReembolsosCancelacion_MonedaGTQ CHECK (Moneda = ''GTQ''),
            CONSTRAINT CK_ReembolsosCancelacion_EstadoPermitido CHECK (
                Estado IN (''PENDIENTE'', ''APROBADO'', ''RECHAZADO'', ''CANCELADO'')
            ),
            CONSTRAINT CK_ReembolsosCancelacion_ResolucionCoherente CHECK (
                (Estado = ''PENDIENTE'' AND FechaResolucionUTC IS NULL)
                OR (Estado IN (''APROBADO'', ''RECHAZADO'', ''CANCELADO'') AND FechaResolucionUTC IS NOT NULL)
            ),
            CONSTRAINT CK_ReembolsosCancelacion_ReferenciaValida CHECK (
                LEN(LTRIM(RTRIM(ReferenciaReembolso))) > 0
                AND DATALENGTH(ReferenciaReembolso) = DATALENGTH(LTRIM(RTRIM(ReferenciaReembolso)))
            )
        );
        -- Historial por pedido y soporte de la FK compuesta.
        CREATE NONCLUSTERED INDEX IX_ReembolsosCancelacion_Pedido_Pago
            ON dbo.ReembolsosCancelacion (IdPedido, IdPago);
        -- Acumulaciones y bloqueos por pago, incluidos todos los intentos históricos.
        CREATE NONCLUSTERED INDEX IX_ReembolsosCancelacion_Pago_Estado
            ON dbo.ReembolsosCancelacion (IdPago, Estado) INCLUDE (Monto);
    ';

    -- DDL y registro técnico se confirman o revierten juntos.
    EXEC sys.sp_executesql N'
        INSERT INTO dbo.VersionesMigracion
            ([Version], NombreArchivo, SHA256, FechaAplicacionUTC, Ejecutor)
        VALUES
            (11, N''011_RelacionesRestricciones.sql'', @Huella, SYSUTCDATETIME(), ORIGINAL_LOGIN());
    ', N'@Huella varbinary(32)', @Huella = @SHA256;

    COMMIT TRANSACTION;
    PRINT N'Migración 011 completada: tres tablas complementarias, relaciones y registro técnico confirmados.';
END TRY
BEGIN CATCH
    IF XACT_STATE() <> 0
        ROLLBACK TRANSACTION;
    THROW;
END CATCH;


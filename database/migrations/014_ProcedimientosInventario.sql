/*
    014_ProcedimientosInventario.sql. Ejecutar completo, sin GO, con Auto-commit en ShopCart.
    SHA-256 final: suministrar 32 bytes mediante SESSION_CONTEXT,
    clave ShopCart.Migracion014.SHA256, misma conexión DataGrip.
    No incluye huella literal. El ejecutor verifica archivo/huella y limpia contexto.
    SQL preparado para revisión; no ejecutado contra el motor.

    Frontera de confianza: solo conexión de servicio controlada por el backend.
    El backend verifica contraseña/JWT y nunca toma IdActor/IdSesion del body HTTP.
    SQL verifica sesión vigente, usuario activo, rol y propiedad; no autentica JWT.
    No usar SESSION_CONTEXT como identidad. No se conceden permisos aquí.
    Configurar después EXECUTE por procedimiento para la cuenta de privilegios mínimos;
    no conceder EXECUTE a esquema/public ni acceso a helpers, autenticación o tablas.
    La identidad del servicio y su política de permisos siguen pendientes de despliegue.

    Escrituras: operación superior dueña de la transacción, sin transacciones externas.
    Bloqueo exclusivo ShopCart.Negocio común a TODAS las escrituras de estas migraciones:
    serializa decisiones de sesión, catálogo, carrito, cupón, stock y compra.
    No delegar COMMIT a helpers ni llamar operaciones superiores desde otras.
    Favorece corrección en la demostración local; evaluar contención antes de escalar.
    Parámetros de texto amplios para validar longitud antes de convertir al esquema.
    RegistrarMovimiento admite ENTRADA, SALIDA y ambos ajustes; IdOperacion es una referencia administrativa estable emitida por backend. Umbral es parámetro, no una columna inexistente.
*/
IF DB_NAME() <> N'ShopCart'
    THROW 62200, N'014 solo puede ejecutarse en la base ShopCart.', 1;

IF @@TRANCOUNT <> 0 OR (2 & @@OPTIONS) = 2
    THROW 62201, N'Inicie con Auto-commit y sin transacciones abiertas o implícitas.', 1;

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
    THROW 62202, N'Se requiere CONTROL sobre ShopCart para inspeccionar y crear el esquema.', 1;

IF NOT EXISTS (
    SELECT 1 FROM sys.databases
    WHERE database_id = DB_ID()
      AND collation_name = N'Latin1_General_100_CI_AI_SC'
      AND recovery_model_desc = N'SIMPLE'
      AND state_desc = N'ONLINE' AND user_access_desc = N'MULTI_USER'
      AND is_read_only = 0 AND source_database_id IS NULL
)
    THROW 62203, N'Las propiedades de ShopCart no coinciden con el arranque 001.', 1;

DECLARE @HuellaRecibida sql_variant = SESSION_CONTEXT(N'ShopCart.Migracion014.SHA256');
IF @HuellaRecibida IS NULL
   OR CONVERT(nvarchar(128), SQL_VARIANT_PROPERTY(@HuellaRecibida, 'BaseType')) NOT IN (N'binary', N'varbinary')
    THROW 62204, N'Suministre el SHA-256 real como valor binario en SESSION_CONTEXT antes de ejecutar 014.', 1;

DECLARE @SHA256 varbinary(max) = CONVERT(varbinary(max), @HuellaRecibida);
IF DATALENGTH(@SHA256) <> 32
    THROW 62205, N'La huella SHA-256 debe contener exactamente 32 bytes.', 1;

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
        THROW 62206, N'No se pudo obtener el bloqueo exclusivo de migraciones.', 1;

    DECLARE @IDVersiones int = OBJECT_ID(N'dbo.VersionesMigracion', N'U');
    IF @IDVersiones IS NULL
        THROW 62207, N'Falta la tabla técnica creada por 001. No se aplicará 014.', 1;

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
        THROW 62208, N'Las columnas de VersionesMigracion no cumplen el contrato de 001.', 1;

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
        THROW 62209, N'VersionesMigracion requiere la PK clustered de 001 sobre Version.', 1;

    IF EXISTS (SELECT 1 FROM sys.triggers WHERE parent_id = @IDVersiones)
       OR EXISTS (SELECT 1 FROM sys.tables WHERE object_id = @IDVersiones
                  AND (temporal_type <> 0 OR is_memory_optimized = 1))
        THROW 62210, N'VersionesMigracion tiene características inesperadas; revisar manualmente.', 1;

    -- Lote inferior: errores de compilación/resolución quedan dentro del TRY externo.
    EXEC sys.sp_executesql N'
        IF NOT EXISTS (
            SELECT 1 FROM dbo.VersionesMigracion WITH (UPDLOCK, HOLDLOCK)
            WHERE [Version] = 13 AND NombreArchivo = N''013_ProcedimientosSeguridad.sql''
        )
            THROW 62213, N''Debe estar registrada la migración 013_ProcedimientosSeguridad.sql antes de aplicar 014.'', 1;
        IF EXISTS (SELECT 1 FROM dbo.VersionesMigracion WITH (UPDLOCK, HOLDLOCK)
                   WHERE [Version] >= 14)
            THROW 62211, N''014 o una migración posterior ya está registrada. No se reaplica ni se certifica el esquema existente.'', 1;
    ';


    -- Rechaza nombres conflictivos antes de crear el primer procedimiento.
    IF OBJECT_ID(N'dbo.SP_Inventario_Consultar') IS NOT NULL THROW 62250, N'Ya existe un objeto de procedimiento; no se sobrescribe.',1;
    IF OBJECT_ID(N'dbo.SP_Inventario_RegistrarMovimiento') IS NOT NULL THROW 62250, N'Ya existe un objeto de procedimiento; no se sobrescribe.',1;
    IF OBJECT_ID(N'dbo.SP_Inventario_ListarMovimientos') IS NOT NULL THROW 62250, N'Ya existe un objeto de procedimiento; no se sobrescribe.',1;

    EXEC sys.sp_executesql N'CREATE PROCEDURE dbo.SP_Inventario_Consultar
@IdActor bigint,@IdSesion uniqueidentifier,@IdVariante bigint=NULL,@Umbral int=NULL,@Pagina int=1,@TamanoPagina int=50
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;
EXEC dbo.SP_Interno_Autorizar @IdActor, @IdSesion, N''OPERADOR'';

IF @Pagina IS NULL OR @Pagina<1 OR @TamanoPagina IS NULL OR @TamanoPagina NOT BETWEEN 1 AND 100 OR @Umbral<0
THROW 62400,N''Filtros inválidos.'',1;
SELECT e.IdVariante,v.SKU,e.CantidadFisica,COALESCE(r.Reservada,0) CantidadReservada,
CONVERT(bigint,e.CantidadFisica)-COALESCE(r.Reservada,0) Disponible,COUNT_BIG(*) OVER() TotalFilas
FROM dbo.Existencias e JOIN dbo.VariantesProducto v ON v.IdVariante=e.IdVariante
OUTER APPLY(SELECT SUM(CONVERT(bigint,Cantidad)) Reservada FROM dbo.ReservasInventario
WHERE IdVariante=e.IdVariante AND Estado=''ACTIVA'' AND FechaExpiracionUTC>SYSUTCDATETIME()) r
WHERE (@IdVariante IS NULL OR e.IdVariante=@IdVariante)
AND (@Umbral IS NULL OR CONVERT(bigint,e.CantidadFisica)-COALESCE(r.Reservada,0)<=@Umbral)
ORDER BY e.IdVariante OFFSET ((CONVERT(bigint,@Pagina)-1)*@TamanoPagina) ROWS FETCH NEXT @TamanoPagina ROWS ONLY;
END;';

    EXEC sys.sp_executesql N'CREATE PROCEDURE dbo.SP_Inventario_RegistrarMovimiento
@IdActor bigint,@IdSesion uniqueidentifier,@IdVariante bigint,@Tipo varchar(30),@Cantidad int,@Motivo nvarchar(max),@IdOperacion bigint
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;
    IF @@TRANCOUNT <> 0 OR (2 & @@OPTIONS) = 2 THROW 62001, N''La operación requiere Auto-commit sin transacción externa.'', 1;
    BEGIN TRY
        BEGIN TRANSACTION;
        DECLARE @Bloqueo int;
        EXEC @Bloqueo = sys.sp_getapplock @Resource=N''ShopCart.Negocio'', @LockMode=N''Exclusive'',
             @LockOwner=N''Transaction'', @LockTimeout=10000;
        IF @Bloqueo < 0 THROW 62002, N''No se pudo serializar la operación; reintente la solicitud completa.'', 1;
EXEC dbo.SP_Interno_Autorizar @IdActor, @IdSesion, N''OPERADOR'';
IF @Motivo IS NULL OR LEN(LTRIM(RTRIM(@Motivo)))=0 OR DATALENGTH(@Motivo)>1000
THROW 62003,N''Texto obligatorio vacío o longitud no válida.'',1;

IF @Tipo IS NULL OR @Tipo NOT IN (''ENTRADA'',''SALIDA'',''AJUSTE_POSITIVO'',''AJUSTE_NEGATIVO'')
OR @Cantidad IS NULL OR @Cantidad<=0 OR @IdOperacion IS NULL OR @IdOperacion<=0 THROW 62401,N''Movimiento inválido.'',1;
DECLARE @Previo bigint=(SELECT IdMovimiento FROM dbo.MovimientosInventario WHERE TipoReferencia=''ADMIN'' AND IdReferencia=@IdOperacion AND IdVariante=@IdVariante);
IF @Previo IS NOT NULL BEGIN
 IF NOT EXISTS(SELECT 1 FROM dbo.MovimientosInventario WHERE IdMovimiento=@Previo AND TipoMovimiento=@Tipo AND Cantidad=@Cantidad
 AND IdUsuarioResponsable=@IdActor AND Motivo COLLATE Latin1_General_100_BIN2=@Motivo COLLATE Latin1_General_100_BIN2
 AND DATALENGTH(Motivo)=DATALENGTH(@Motivo)) THROW 62402,N''Clave de movimiento reutilizada con contenido distinto.'',1;
 SELECT @Previo IdMovimiento; COMMIT TRANSACTION; RETURN;
END;
DECLARE @Antes int,@Reservada bigint,@Despues bigint;
SELECT @Antes=CantidadFisica FROM dbo.Existencias WITH(UPDLOCK,HOLDLOCK) WHERE IdVariante=@IdVariante;
IF @Antes IS NULL THROW 62403,N''Existencia inexistente.'',1;
SELECT @Reservada=COALESCE(SUM(CONVERT(bigint,Cantidad)),0) FROM dbo.ReservasInventario
WHERE IdVariante=@IdVariante AND Estado=''ACTIVA'' AND FechaExpiracionUTC>SYSUTCDATETIME();
SET @Despues=CONVERT(bigint,@Antes)+CASE WHEN @Tipo IN (''ENTRADA'',''AJUSTE_POSITIVO'') THEN CONVERT(bigint,@Cantidad) ELSE -CONVERT(bigint,@Cantidad) END;
IF @Despues<@Reservada OR @Despues>2147483647 THROW 62404,N''El movimiento compromete reservas o excede la capacidad del saldo.'',1;
UPDATE dbo.Existencias SET CantidadFisica=CONVERT(int,@Despues),FechaActualizacionUTC=SYSUTCDATETIME() WHERE IdVariante=@IdVariante AND CantidadFisica=@Antes;
IF @@ROWCOUNT<>1 THROW 62405,N''Conflicto de inventario.'',1;
INSERT dbo.MovimientosInventario(IdVariante,TipoMovimiento,Cantidad,SaldoAnterior,SaldoPosterior,Motivo,IdUsuarioResponsable,TipoReferencia,IdReferencia)
VALUES(@IdVariante,@Tipo,@Cantidad,@Antes,CONVERT(int,@Despues),@Motivo,@IdActor,''ADMIN'',@IdOperacion);
DECLARE @Id bigint=CONVERT(bigint,SCOPE_IDENTITY());
DECLARE @AnteriorJSON nvarchar(max)=(SELECT @Antes CantidadFisica FOR JSON PATH,WITHOUT_ARRAY_WRAPPER);
DECLARE @NuevoJSON nvarchar(max)=(SELECT @Despues CantidadFisica,@Id IdMovimiento FOR JSON PATH,WITHOUT_ARRAY_WRAPPER);
INSERT dbo.EventosAuditoria (IdUsuarioActor,Accion,Entidad,IdEntidad,DatosAnteriores,DatosNuevos)
VALUES (@IdActor,N''MOVIMIENTO'',N''Existencias'',@IdVariante,@AnteriorJSON,@NuevoJSON);
SELECT @Id IdMovimiento;
        COMMIT TRANSACTION;
    END TRY
    BEGIN CATCH
        IF XACT_STATE() <> 0 ROLLBACK TRANSACTION;
        THROW;
    END CATCH;
END;';

    EXEC sys.sp_executesql N'CREATE PROCEDURE dbo.SP_Inventario_ListarMovimientos
@IdActor bigint,@IdSesion uniqueidentifier,@Desde datetime2(7),@Hasta datetime2(7),@IdVariante bigint=NULL,@Pagina int=1,@TamanoPagina int=50
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;
EXEC dbo.SP_Interno_Autorizar @IdActor, @IdSesion, N''OPERADOR'';

IF @Desde IS NULL OR @Hasta IS NULL OR @Desde>=@Hasta OR @Pagina IS NULL OR @Pagina<1 OR @TamanoPagina IS NULL OR @TamanoPagina NOT BETWEEN 1 AND 100
THROW 62406,N''Intervalo o paginación inválidos.'',1;
SELECT IdMovimiento,IdVariante,TipoMovimiento,Cantidad,SaldoAnterior,SaldoPosterior,Motivo,IdUsuarioResponsable,TipoReferencia,IdReferencia,FechaMovimientoUTC,
COUNT_BIG(*) OVER() TotalFilas FROM dbo.MovimientosInventario
WHERE FechaMovimientoUTC>=@Desde AND FechaMovimientoUTC<@Hasta AND (@IdVariante IS NULL OR IdVariante=@IdVariante)
ORDER BY FechaMovimientoUTC,IdMovimiento OFFSET ((CONVERT(bigint,@Pagina)-1)*@TamanoPagina) ROWS FETCH NEXT @TamanoPagina ROWS ONLY;
END;';

    EXEC sys.sp_executesql N'
        INSERT dbo.VersionesMigracion ([Version],NombreArchivo,SHA256,FechaAplicacionUTC,Ejecutor)
        VALUES (14,N''014_ProcedimientosInventario.sql'',@Huella,SYSUTCDATETIME(),ORIGINAL_LOGIN());
    ',N'@Huella varbinary(32)',@Huella=@SHA256;
    COMMIT TRANSACTION;
    PRINT N'Migración 14 completada.';
END TRY
BEGIN CATCH
    IF XACT_STATE() <> 0 ROLLBACK TRANSACTION;
    THROW;
END CATCH;

/*
    016_ProcedimientosCupones.sql. Ejecutar completo, sin GO, con Auto-commit en ShopCart.
    SHA-256 final: suministrar 32 bytes mediante SESSION_CONTEXT,
    clave ShopCart.Migracion016.SHA256, misma conexión DataGrip.
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
    ValidarCarrito no reserva capacidad. CambiarEstado permite desactivar respetando reservas vigentes; Guardar rechaza cambios de condiciones con reservas vigentes.
*/
IF DB_NAME() <> N'ShopCart'
    THROW 62400, N'016 solo puede ejecutarse en la base ShopCart.', 1;

IF @@TRANCOUNT <> 0 OR (2 & @@OPTIONS) = 2
    THROW 62401, N'Inicie con Auto-commit y sin transacciones abiertas o implícitas.', 1;

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
    THROW 62402, N'Se requiere CONTROL sobre ShopCart para inspeccionar y crear el esquema.', 1;

IF NOT EXISTS (
    SELECT 1 FROM sys.databases
    WHERE database_id = DB_ID()
      AND collation_name = N'Latin1_General_100_CI_AI_SC'
      AND recovery_model_desc = N'SIMPLE'
      AND state_desc = N'ONLINE' AND user_access_desc = N'MULTI_USER'
      AND is_read_only = 0 AND source_database_id IS NULL
)
    THROW 62403, N'Las propiedades de ShopCart no coinciden con el arranque 001.', 1;

DECLARE @HuellaRecibida sql_variant = SESSION_CONTEXT(N'ShopCart.Migracion016.SHA256');
IF @HuellaRecibida IS NULL
   OR CONVERT(nvarchar(128), SQL_VARIANT_PROPERTY(@HuellaRecibida, 'BaseType')) NOT IN (N'binary', N'varbinary')
    THROW 62404, N'Suministre el SHA-256 real como valor binario en SESSION_CONTEXT antes de ejecutar 016.', 1;

DECLARE @SHA256 varbinary(max) = CONVERT(varbinary(max), @HuellaRecibida);
IF DATALENGTH(@SHA256) <> 32
    THROW 62405, N'La huella SHA-256 debe contener exactamente 32 bytes.', 1;

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
        THROW 62406, N'No se pudo obtener el bloqueo exclusivo de migraciones.', 1;

    DECLARE @IDVersiones int = OBJECT_ID(N'dbo.VersionesMigracion', N'U');
    IF @IDVersiones IS NULL
        THROW 62407, N'Falta la tabla técnica creada por 001. No se aplicará 016.', 1;

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
        THROW 62408, N'Las columnas de VersionesMigracion no cumplen el contrato de 001.', 1;

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
        THROW 62409, N'VersionesMigracion requiere la PK clustered de 001 sobre Version.', 1;

    IF EXISTS (SELECT 1 FROM sys.triggers WHERE parent_id = @IDVersiones)
       OR EXISTS (SELECT 1 FROM sys.tables WHERE object_id = @IDVersiones
                  AND (temporal_type <> 0 OR is_memory_optimized = 1))
        THROW 62410, N'VersionesMigracion tiene características inesperadas; revisar manualmente.', 1;

    -- Lote inferior: errores de compilación/resolución quedan dentro del TRY externo.
    EXEC sys.sp_executesql N'
        IF NOT EXISTS (
            SELECT 1 FROM dbo.VersionesMigracion WITH (UPDLOCK, HOLDLOCK)
            WHERE [Version] = 15 AND NombreArchivo = N''015_ProcedimientosCarritos.sql''
        )
            THROW 62413, N''Debe estar registrada la migración 015_ProcedimientosCarritos.sql antes de aplicar 016.'', 1;
        IF EXISTS (SELECT 1 FROM dbo.VersionesMigracion WITH (UPDLOCK, HOLDLOCK)
                   WHERE [Version] >= 16)
            THROW 62411, N''016 o una migración posterior ya está registrada. No se reaplica ni se certifica el esquema existente.'', 1;
    ';


    -- Rechaza nombres conflictivos antes de crear el primer procedimiento.
    IF OBJECT_ID(N'dbo.SP_Cupones_Guardar') IS NOT NULL THROW 62450, N'Ya existe un objeto de procedimiento; no se sobrescribe.',1;
    IF OBJECT_ID(N'dbo.SP_Interno_EvaluarCupon') IS NOT NULL THROW 62450, N'Ya existe un objeto de procedimiento; no se sobrescribe.',1;
    IF OBJECT_ID(N'dbo.SP_Cupones_ValidarCarrito') IS NOT NULL THROW 62450, N'Ya existe un objeto de procedimiento; no se sobrescribe.',1;
    IF OBJECT_ID(N'dbo.SP_Cupones_ConsultarUsos') IS NOT NULL THROW 62450, N'Ya existe un objeto de procedimiento; no se sobrescribe.',1;
    IF OBJECT_ID(N'dbo.SP_Cupones_CambiarEstado') IS NOT NULL THROW 62450, N'Ya existe un objeto de procedimiento; no se sobrescribe.',1;

    EXEC sys.sp_executesql N'CREATE PROCEDURE dbo.SP_Cupones_Guardar
@IdActor bigint,@IdSesion uniqueidentifier,@Codigo nvarchar(max),@Tipo varchar(15),@Valor decimal(19,4),
@Minimo decimal(19,4),@Inicio datetime2(7),@Fin datetime2(7),@IdCategoria int=NULL,
@LimiteTotal int=NULL,@LimiteUsuario int=NULL,@Activo bit=1,@Descripcion nvarchar(max)=NULL,@IdCupon bigint=NULL
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
EXEC dbo.SP_Interno_Autorizar @IdActor, @IdSesion, N''ADMINISTRADOR'';
IF @Codigo IS NULL OR LEN(LTRIM(RTRIM(@Codigo)))=0 OR DATALENGTH(@Codigo)>100
THROW 62003,N''Texto obligatorio vacío o longitud no válida.'',1;

IF @Tipo IS NULL OR @Tipo NOT IN (''PORCENTAJE'',''MONTO_FIJO'') OR @Valor IS NULL OR @Valor<=0
OR (@Tipo=''PORCENTAJE'' AND @Valor>100) OR @Minimo IS NULL OR @Minimo<0 OR @Inicio IS NULL OR @Fin IS NULL OR @Inicio>=@Fin
OR @LimiteTotal<=0 OR @LimiteUsuario<=0 OR @Activo IS NULL OR DATALENGTH(@Descripcion)>500
OR (@IdCategoria IS NOT NULL AND NOT EXISTS(SELECT 1 FROM dbo.Categorias WHERE IdCategoria=@IdCategoria))
THROW 62600,N''Cupón inválido.'',1;
IF @IdCupon IS NOT NULL AND EXISTS(SELECT 1 FROM dbo.ReservasCupon WHERE IdCupon=@IdCupon AND Estado=''ACTIVA'' AND FechaExpiracionUTC>SYSUTCDATETIME())
THROW 62601,N''Hay reservas vigentes; no se modifican sus condiciones.'',1;
DECLARE @Antes nvarchar(max),@Despues nvarchar(max);
IF @IdCupon IS NULL BEGIN
 INSERT dbo.Cupones(Codigo,Descripcion,TipoDescuento,ValorDescuento,MontoMinimoCompra,IdCategoria,LimiteUsosTotal,LimiteUsosPorUsuario,FechaInicioUTC,FechaFinUTC,EstaActivo)
 VALUES(UPPER(LTRIM(RTRIM(@Codigo))),@Descripcion,@Tipo,@Valor,@Minimo,@IdCategoria,@LimiteTotal,@LimiteUsuario,@Inicio,@Fin,@Activo);
 SET @IdCupon=CONVERT(bigint,SCOPE_IDENTITY());
END ELSE BEGIN
 SELECT @Antes=(SELECT * FROM dbo.Cupones WHERE IdCupon=@IdCupon FOR JSON PATH,WITHOUT_ARRAY_WRAPPER);
 IF @Antes IS NULL THROW 62602,N''Cupón inexistente.'',1;
 UPDATE dbo.Cupones SET Codigo=UPPER(LTRIM(RTRIM(@Codigo))),Descripcion=@Descripcion,TipoDescuento=@Tipo,ValorDescuento=@Valor,
 MontoMinimoCompra=@Minimo,IdCategoria=@IdCategoria,LimiteUsosTotal=@LimiteTotal,LimiteUsosPorUsuario=@LimiteUsuario,
 FechaInicioUTC=@Inicio,FechaFinUTC=@Fin,EstaActivo=@Activo,FechaActualizacionUTC=SYSUTCDATETIME() WHERE IdCupon=@IdCupon;
END;
SELECT @Despues=(SELECT * FROM dbo.Cupones WHERE IdCupon=@IdCupon FOR JSON PATH,WITHOUT_ARRAY_WRAPPER);
INSERT dbo.EventosAuditoria (IdUsuarioActor,Accion,Entidad,IdEntidad,DatosAnteriores,DatosNuevos)
VALUES (@IdActor,N''GUARDAR'',N''Cupones'',@IdCupon,@Antes,@Despues);
SELECT @IdCupon IdCupon;
        COMMIT TRANSACTION;
    END TRY
    BEGIN CATCH
        IF XACT_STATE() <> 0 ROLLBACK TRANSACTION;
        THROW;
    END CATCH;
END;';

    EXEC sys.sp_executesql N'CREATE PROCEDURE dbo.SP_Interno_EvaluarCupon
@IdCupon bigint,@IdUsuario bigint,@Subtotal decimal(19,4),@Elegible decimal(19,4),
@IdCheckout bigint,@Descuento decimal(19,4) OUTPUT
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

-- Helper interno: el llamador debe poseer ShopCart.Negocio dentro de su transacción.
IF @@TRANCOUNT=0 OR APPLOCK_MODE(N''public'',N''ShopCart.Negocio'',N''Transaction'')<>N''Exclusive''
THROW 62603,N''El cálculo requiere la transacción de negocio.'',1;
DECLARE @Tipo varchar(15),@Valor decimal(19,4),@Minimo decimal(19,4),@Inicio datetime2(7),@Fin datetime2(7),
@Activo bit,@Limite int,@PorUsuario int,@Usados bigint,@Reservados bigint,@UsadosUsuario bigint,@ReservadosUsuario bigint;
SELECT @Tipo=TipoDescuento,@Valor=ValorDescuento,@Minimo=MontoMinimoCompra,@Inicio=FechaInicioUTC,@Fin=FechaFinUTC,
@Activo=EstaActivo,@Limite=LimiteUsosTotal,@PorUsuario=LimiteUsosPorUsuario FROM dbo.Cupones WITH(UPDLOCK,HOLDLOCK) WHERE IdCupon=@IdCupon;
IF @Tipo IS NULL OR @Activo<>1 THROW 62604,N''Cupón inexistente o inactivo.'',1;
IF SYSUTCDATETIME()<@Inicio OR SYSUTCDATETIME()>=@Fin THROW 62605,N''Cupón fuera de vigencia.'',1;
IF @Subtotal<@Minimo THROW 62606,N''Compra mínima no alcanzada.'',1;
IF @Subtotal IS NULL OR @Elegible IS NULL OR @Elegible<=0 THROW 62607,N''No hay líneas elegibles.'',1;
IF @PorUsuario IS NOT NULL AND @IdUsuario IS NULL THROW 62608,N''El cupón requiere autenticación.'',1;
SELECT @Usados=COUNT_BIG(*),@UsadosUsuario=COALESCE(SUM(CONVERT(bigint,CASE WHEN IdUsuario=@IdUsuario THEN 1 ELSE 0 END)),0)
FROM dbo.UsosCupon WHERE IdCupon=@IdCupon;
SELECT @Reservados=COUNT_BIG(*),@ReservadosUsuario=COALESCE(SUM(CONVERT(bigint,CASE WHEN IdUsuario=@IdUsuario THEN 1 ELSE 0 END)),0)
FROM dbo.ReservasCupon r WHERE r.IdCupon=@IdCupon AND r.Estado=''ACTIVA'' AND r.FechaExpiracionUTC>SYSUTCDATETIME()
AND (@IdCheckout IS NULL OR r.IdCheckout<>@IdCheckout)
AND NOT EXISTS(SELECT 1 FROM dbo.Pedidos p JOIN dbo.UsosCupon u ON u.IdPedido=p.IdPedido WHERE p.IdCheckout=r.IdCheckout);
IF (@Limite IS NOT NULL AND @Usados+@Reservados>=@Limite)
OR (@PorUsuario IS NOT NULL AND @UsadosUsuario+@ReservadosUsuario>=@PorUsuario) THROW 62609,N''Límite de usos agotado.'',1;
SET @Descuento=CASE WHEN @Tipo=''MONTO_FIJO'' THEN CASE WHEN @Valor>@Elegible THEN @Elegible ELSE @Valor END
ELSE CONVERT(decimal(19,4),ROUND((CONVERT(decimal(25,4),@Elegible)*@Valor)/100,4)) END;
IF @Descuento>@Elegible SET @Descuento=@Elegible;
END;';

    EXEC sys.sp_executesql N'CREATE PROCEDURE dbo.SP_Cupones_ValidarCarrito
@IdCarrito bigint,@Codigo nvarchar(max),@IdActor bigint=NULL,@IdSesion uniqueidentifier=NULL,@TokenInvitado varbinary(max)=NULL
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
IF @IdActor IS NOT NULL BEGIN
 EXEC dbo.SP_Interno_Autorizar @IdActor,@IdSesion,N''USUARIO'';
 IF @TokenInvitado IS NOT NULL THROW 62500,N''Identidad de carrito ambigua.'',1;
 IF NOT EXISTS(SELECT 1 FROM dbo.Carritos WHERE IdCarrito=@IdCarrito AND IdUsuario=@IdActor)
 THROW 62501,N''Carrito no autorizado.'',1;
END ELSE BEGIN
 IF @TokenInvitado IS NULL OR DATALENGTH(@TokenInvitado)<>32 OR @IdSesion IS NOT NULL
 OR NOT EXISTS(SELECT 1 FROM dbo.Carritos WHERE IdCarrito=@IdCarrito AND IdUsuario IS NULL AND TokenInvitadoHash=@TokenInvitado)
 THROW 62501,N''Carrito no autorizado.'',1;
END;IF @Codigo IS NULL OR LEN(LTRIM(RTRIM(@Codigo)))=0 OR DATALENGTH(@Codigo)>100
THROW 62003,N''Texto obligatorio vacío o longitud no válida.'',1;

DECLARE @IdCupon bigint,@Categoria int,@Subtotal decimal(19,4),@Elegible decimal(19,4),@Descuento decimal(19,4);
SELECT @IdCupon=IdCupon,@Categoria=IdCategoria FROM dbo.Cupones WHERE Codigo=UPPER(LTRIM(RTRIM(@Codigo)));
IF @IdCupon IS NULL THROW 62604,N''Cupón inexistente.'',1;
SELECT @Subtotal=SUM(CONVERT(decimal(30,4),d.Cantidad)*v.Precio),
@Elegible=SUM(CASE WHEN @Categoria IS NULL OR p.IdCategoria=@Categoria THEN CONVERT(decimal(30,4),d.Cantidad)*v.Precio ELSE 0 END)
FROM dbo.DetallesCarrito d JOIN dbo.VariantesProducto v ON v.IdVariante=d.IdVariante JOIN dbo.Productos p ON p.IdProducto=v.IdProducto WHERE d.IdCarrito=@IdCarrito;
IF @Subtotal IS NULL THROW 62607,N''Carrito vacío.'',1;
EXEC dbo.SP_Interno_EvaluarCupon @IdCupon,@IdActor,@Subtotal,@Elegible,NULL,@Descuento OUTPUT;
SELECT @IdCupon IdCupon,@Subtotal Subtotal,@Elegible ImporteElegible,@Descuento Descuento;

        COMMIT TRANSACTION;
    END TRY
    BEGIN CATCH
        IF XACT_STATE() <> 0 ROLLBACK TRANSACTION;
        THROW;
    END CATCH;
END;';

    EXEC sys.sp_executesql N'CREATE PROCEDURE dbo.SP_Cupones_ConsultarUsos
@IdActor bigint,@IdSesion uniqueidentifier,@IdCupon bigint,@Pagina int=1,@TamanoPagina int=50
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;
EXEC dbo.SP_Interno_Autorizar @IdActor, @IdSesion, N''ADMINISTRADOR'';

IF @Pagina IS NULL OR @Pagina<1 OR @TamanoPagina IS NULL OR @TamanoPagina NOT BETWEEN 1 AND 100 THROW 62610,N''Paginación inválida.'',1;
SELECT u.IdUsoCupon,u.IdPedido,u.IdUsuario,u.FechaUsoUTC,p.Descuento,COUNT_BIG(*) OVER() TotalFilas FROM dbo.UsosCupon u
JOIN dbo.Pedidos p ON p.IdPedido=u.IdPedido WHERE u.IdCupon=@IdCupon
ORDER BY u.FechaUsoUTC,u.IdUsoCupon OFFSET ((CONVERT(bigint,@Pagina)-1)*@TamanoPagina) ROWS FETCH NEXT @TamanoPagina ROWS ONLY;
END;';

    EXEC sys.sp_executesql N'CREATE PROCEDURE dbo.SP_Cupones_CambiarEstado
@IdActor bigint,@IdSesion uniqueidentifier,@IdCupon bigint,@Activo bit
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
EXEC dbo.SP_Interno_Autorizar @IdActor, @IdSesion, N''ADMINISTRADOR'';

IF @Activo IS NULL THROW 62611,N''Estado inválido.'',1;
DECLARE @Anterior bit=(SELECT EstaActivo FROM dbo.Cupones WITH(UPDLOCK,HOLDLOCK) WHERE IdCupon=@IdCupon);
IF @Anterior IS NULL THROW 62602,N''Cupón inexistente.'',1;
UPDATE dbo.Cupones SET EstaActivo=@Activo,FechaActualizacionUTC=SYSUTCDATETIME() WHERE IdCupon=@IdCupon;
DECLARE @AntesJSON nvarchar(max)=(SELECT @Anterior EstaActivo FOR JSON PATH,WITHOUT_ARRAY_WRAPPER),
@NuevoJSON nvarchar(max)=(SELECT @Activo EstaActivo FOR JSON PATH,WITHOUT_ARRAY_WRAPPER);
INSERT dbo.EventosAuditoria (IdUsuarioActor,Accion,Entidad,IdEntidad,DatosAnteriores,DatosNuevos)
VALUES (@IdActor,N''ESTADO'',N''Cupones'',@IdCupon,@AntesJSON,@NuevoJSON);

        COMMIT TRANSACTION;
    END TRY
    BEGIN CATCH
        IF XACT_STATE() <> 0 ROLLBACK TRANSACTION;
        THROW;
    END CATCH;
END;';

    EXEC sys.sp_executesql N'
        INSERT dbo.VersionesMigracion ([Version],NombreArchivo,SHA256,FechaAplicacionUTC,Ejecutor)
        VALUES (16,N''016_ProcedimientosCupones.sql'',@Huella,SYSUTCDATETIME(),ORIGINAL_LOGIN());
    ',N'@Huella varbinary(32)',@Huella=@SHA256;
    COMMIT TRANSACTION;
    PRINT N'Migración 16 completada.';
END TRY
BEGIN CATCH
    IF XACT_STATE() <> 0 ROLLBACK TRANSACTION;
    THROW;
END CATCH;

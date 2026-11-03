/*
    012_ProcedimientosCatalogo.sql. Ejecutar completo, sin GO, con Auto-commit en ShopCart.
    SHA-256 final: suministrar 32 bytes mediante SESSION_CONTEXT,
    clave ShopCart.Migracion012.SHA256, misma conexión DataGrip.
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
    Guardar crea con ID NULL y actualiza/activa/desactiva con ID existente. No hay borrado físico. La restricción de rutas de 003 valida las imágenes.
*/
IF DB_NAME() <> N'ShopCart'
    THROW 62000, N'012 solo puede ejecutarse en la base ShopCart.', 1;

IF @@TRANCOUNT <> 0 OR (2 & @@OPTIONS) = 2
    THROW 62001, N'Inicie con Auto-commit y sin transacciones abiertas o implícitas.', 1;

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
    THROW 62002, N'Se requiere CONTROL sobre ShopCart para inspeccionar y crear el esquema.', 1;

IF NOT EXISTS (
    SELECT 1 FROM sys.databases
    WHERE database_id = DB_ID()
      AND collation_name = N'Latin1_General_100_CI_AI_SC'
      AND recovery_model_desc = N'SIMPLE'
      AND state_desc = N'ONLINE' AND user_access_desc = N'MULTI_USER'
      AND is_read_only = 0 AND source_database_id IS NULL
)
    THROW 62003, N'Las propiedades de ShopCart no coinciden con el arranque 001.', 1;

DECLARE @HuellaRecibida sql_variant = SESSION_CONTEXT(N'ShopCart.Migracion012.SHA256');
IF @HuellaRecibida IS NULL
   OR CONVERT(nvarchar(128), SQL_VARIANT_PROPERTY(@HuellaRecibida, 'BaseType')) NOT IN (N'binary', N'varbinary')
    THROW 62004, N'Suministre el SHA-256 real como valor binario en SESSION_CONTEXT antes de ejecutar 012.', 1;

DECLARE @SHA256 varbinary(max) = CONVERT(varbinary(max), @HuellaRecibida);
IF DATALENGTH(@SHA256) <> 32
    THROW 62005, N'La huella SHA-256 debe contener exactamente 32 bytes.', 1;

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
        THROW 62006, N'No se pudo obtener el bloqueo exclusivo de migraciones.', 1;

    DECLARE @IDVersiones int = OBJECT_ID(N'dbo.VersionesMigracion', N'U');
    IF @IDVersiones IS NULL
        THROW 62007, N'Falta la tabla técnica creada por 001. No se aplicará 012.', 1;

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
        THROW 62008, N'Las columnas de VersionesMigracion no cumplen el contrato de 001.', 1;

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
        THROW 62009, N'VersionesMigracion requiere la PK clustered de 001 sobre Version.', 1;

    IF EXISTS (SELECT 1 FROM sys.triggers WHERE parent_id = @IDVersiones)
       OR EXISTS (SELECT 1 FROM sys.tables WHERE object_id = @IDVersiones
                  AND (temporal_type <> 0 OR is_memory_optimized = 1))
        THROW 62010, N'VersionesMigracion tiene características inesperadas; revisar manualmente.', 1;

    -- Lote inferior: errores de compilación/resolución quedan dentro del TRY externo.
    EXEC sys.sp_executesql N'
        IF NOT EXISTS (
            SELECT 1 FROM dbo.VersionesMigracion WITH (UPDLOCK, HOLDLOCK)
            WHERE [Version] = 11 AND NombreArchivo = N''011_RelacionesRestricciones.sql''
        )
            THROW 62013, N''Debe estar registrada la migración 011_RelacionesRestricciones.sql antes de aplicar 012.'', 1;
        IF EXISTS (SELECT 1 FROM dbo.VersionesMigracion WITH (UPDLOCK, HOLDLOCK)
                   WHERE [Version] >= 12)
            THROW 62012, N''012 o una migración posterior ya está registrada. No se reaplica ni se certifica el esquema existente.'', 1;
    ';


    -- Rechaza nombres conflictivos antes de crear el primer procedimiento.
    IF OBJECT_ID(N'dbo.SP_Interno_Autorizar') IS NOT NULL THROW 62050, N'Ya existe un objeto de procedimiento; no se sobrescribe.',1;
    IF OBJECT_ID(N'dbo.SP_Catalogo_ListarCategorias') IS NOT NULL THROW 62050, N'Ya existe un objeto de procedimiento; no se sobrescribe.',1;
    IF OBJECT_ID(N'dbo.SP_Catalogo_ListarProductos') IS NOT NULL THROW 62050, N'Ya existe un objeto de procedimiento; no se sobrescribe.',1;
    IF OBJECT_ID(N'dbo.SP_Catalogo_ObtenerProducto') IS NOT NULL THROW 62050, N'Ya existe un objeto de procedimiento; no se sobrescribe.',1;
    IF OBJECT_ID(N'dbo.SP_Catalogo_GuardarCategoria') IS NOT NULL THROW 62050, N'Ya existe un objeto de procedimiento; no se sobrescribe.',1;
    IF OBJECT_ID(N'dbo.SP_Catalogo_GuardarProducto') IS NOT NULL THROW 62050, N'Ya existe un objeto de procedimiento; no se sobrescribe.',1;
    IF OBJECT_ID(N'dbo.SP_Catalogo_GuardarVariante') IS NOT NULL THROW 62050, N'Ya existe un objeto de procedimiento; no se sobrescribe.',1;
    IF OBJECT_ID(N'dbo.SP_Catalogo_GuardarImagen') IS NOT NULL THROW 62050, N'Ya existe un objeto de procedimiento; no se sobrescribe.',1;

    EXEC sys.sp_executesql N'CREATE PROCEDURE dbo.SP_Interno_Autorizar
@IdActor bigint,@IdSesion uniqueidentifier,@Ambito nvarchar(30)
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

DECLARE @Rol nvarchar(30);
SELECT @Rol=r.Nombre FROM dbo.Usuarios u JOIN dbo.Roles r ON r.IdRol=u.IdRol
JOIN dbo.SesionesUsuario s ON s.IdUsuario=u.IdUsuario
WHERE u.IdUsuario=@IdActor AND u.EstaActivo=1 AND s.IdSesion=@IdSesion
AND s.FechaRevocacionUTC IS NULL AND s.FechaExpiracionUTC>SYSUTCDATETIME();
IF @Rol IS NULL THROW 62100,N''Sesión inválida o expirada.'',1;
IF @Ambito IS NULL OR @Ambito NOT IN (N''USUARIO'',N''OPERADOR'',N''ADMINISTRADOR'') THROW 62101,N''Ámbito inválido.'',1;
IF (@Ambito=N''ADMINISTRADOR'' AND @Rol<>N''Administrador'')
OR (@Ambito=N''OPERADOR'' AND @Rol NOT IN (N''Operador'',N''Administrador''))
THROW 62103,N''Operación no autorizada.'',1;
END;';

    EXEC sys.sp_executesql N'CREATE PROCEDURE dbo.SP_Catalogo_ListarCategorias

AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;
SELECT IdCategoria,Nombre,Descripcion FROM dbo.Categorias WHERE EstaActiva=1 ORDER BY Nombre,IdCategoria;
END;';

    EXEC sys.sp_executesql N'CREATE PROCEDURE dbo.SP_Catalogo_ListarProductos
@Texto nvarchar(max)=NULL,@IdCategoria int=NULL,@PrecioMin decimal(19,4)=NULL,
@PrecioMax decimal(19,4)=NULL,@SoloDisponibles bit=0,@Orden varchar(20)=''NOMBRE'',@Pagina int=1,@TamanoPagina int=20
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

IF @Pagina IS NULL OR @Pagina<1 OR @TamanoPagina IS NULL OR @TamanoPagina NOT BETWEEN 1 AND 100
OR @Orden IS NULL OR @Orden NOT IN (''NOMBRE'',''PRECIO_ASC'',''PRECIO_DESC'')
OR DATALENGTH(@Texto)>400 OR @PrecioMin<0 OR @PrecioMax<0 OR @PrecioMax<@PrecioMin OR @SoloDisponibles IS NULL
THROW 62104,N''Filtros o paginación inválidos.'',1;
;WITH Catalogo AS (
 SELECT p.IdProducto,p.IdCategoria,p.Nombre,p.Descripcion,MIN(v.Precio) PrecioDesde,
 MAX(CASE WHEN CONVERT(bigint,e.CantidadFisica)-COALESCE(rv.Reservada,0)>0 THEN 1 ELSE 0 END) Disponible
 FROM dbo.Productos p JOIN dbo.Categorias c ON c.IdCategoria=p.IdCategoria AND c.EstaActiva=1
 JOIN dbo.VariantesProducto v ON v.IdProducto=p.IdProducto AND v.EstaActiva=1
 LEFT JOIN dbo.Existencias e ON e.IdVariante=v.IdVariante
 OUTER APPLY(SELECT SUM(CONVERT(bigint,r.Cantidad)) Reservada FROM dbo.ReservasInventario r
 WHERE r.IdVariante=v.IdVariante AND r.Estado=''ACTIVA'' AND r.FechaExpiracionUTC>SYSUTCDATETIME()) rv
 WHERE p.EstaActivo=1 AND (@IdCategoria IS NULL OR p.IdCategoria=@IdCategoria)
 AND (@Texto IS NULL OR CHARINDEX(@Texto,p.Nombre)>0 OR CHARINDEX(@Texto,p.Descripcion)>0)
 AND (@PrecioMin IS NULL OR v.Precio>=@PrecioMin) AND (@PrecioMax IS NULL OR v.Precio<=@PrecioMax)
 GROUP BY p.IdProducto,p.IdCategoria,p.Nombre,p.Descripcion
)
SELECT *,COUNT_BIG(*) OVER() TotalFilas FROM Catalogo WHERE @SoloDisponibles=0 OR Disponible=1
ORDER BY CASE WHEN @Orden=''PRECIO_ASC'' THEN PrecioDesde END,
CASE WHEN @Orden=''PRECIO_DESC'' THEN PrecioDesde END DESC,Nombre,IdProducto
OFFSET ((CONVERT(bigint,@Pagina)-1)*@TamanoPagina) ROWS FETCH NEXT @TamanoPagina ROWS ONLY;
END;';

    EXEC sys.sp_executesql N'CREATE PROCEDURE dbo.SP_Catalogo_ObtenerProducto
@IdProducto bigint
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

IF NOT EXISTS(SELECT 1 FROM dbo.Productos p JOIN dbo.Categorias c ON c.IdCategoria=p.IdCategoria
WHERE p.IdProducto=@IdProducto AND p.EstaActivo=1 AND c.EstaActiva=1) THROW 62105,N''Producto no disponible.'',1;
SELECT p.IdProducto,p.Nombre,p.Descripcion,p.IdCategoria,c.Nombre Categoria
FROM dbo.Productos p JOIN dbo.Categorias c ON c.IdCategoria=p.IdCategoria WHERE p.IdProducto=@IdProducto;
SELECT v.IdVariante,v.SKU,v.Talla,v.Color,v.Precio,CONVERT(bigint,e.CantidadFisica)-COALESCE(r.Cantidad,0) Disponible
FROM dbo.VariantesProducto v LEFT JOIN dbo.Existencias e ON e.IdVariante=v.IdVariante
OUTER APPLY(SELECT SUM(CONVERT(bigint,Cantidad)) Cantidad FROM dbo.ReservasInventario
WHERE IdVariante=v.IdVariante AND Estado=''ACTIVA'' AND FechaExpiracionUTC>SYSUTCDATETIME()) r
WHERE v.IdProducto=@IdProducto AND v.EstaActiva=1 ORDER BY v.IdVariante;
SELECT IdImagen,RutaImagen,TextoAlternativo,OrdenVisualizacion,EsPrincipal FROM dbo.ImagenesProducto
WHERE IdProducto=@IdProducto AND EstaActiva=1 ORDER BY OrdenVisualizacion,IdImagen;
END;';

    EXEC sys.sp_executesql N'CREATE PROCEDURE dbo.SP_Catalogo_GuardarCategoria
@IdActor bigint,@IdSesion uniqueidentifier,@Nombre nvarchar(max),@Descripcion nvarchar(max)=NULL,@EstaActiva bit=1,@IdCategoria int=NULL
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
IF @Nombre IS NULL OR LEN(LTRIM(RTRIM(@Nombre)))=0 OR DATALENGTH(@Nombre)>200
THROW 62003,N''Texto obligatorio vacío o longitud no válida.'',1;

IF DATALENGTH(@Descripcion)>1000 OR @EstaActiva IS NULL THROW 62106,N''Categoría inválida.'',1;
DECLARE @Antes nvarchar(max),@Despues nvarchar(max);
IF @IdCategoria IS NOT NULL BEGIN
 SELECT @Antes=(SELECT IdCategoria,Nombre,Descripcion,EstaActiva FROM dbo.Categorias WHERE IdCategoria=@IdCategoria FOR JSON PATH,WITHOUT_ARRAY_WRAPPER);
 IF @Antes IS NULL THROW 62107,N''Categoría inexistente.'',1;
 UPDATE dbo.Categorias SET Nombre=LTRIM(RTRIM(@Nombre)),Descripcion=@Descripcion,EstaActiva=@EstaActiva,FechaActualizacionUTC=SYSUTCDATETIME() WHERE IdCategoria=@IdCategoria;
END ELSE BEGIN
 INSERT dbo.Categorias(Nombre,Descripcion,EstaActiva) VALUES(LTRIM(RTRIM(@Nombre)),@Descripcion,@EstaActiva);
 SET @IdCategoria=CONVERT(int,SCOPE_IDENTITY());
END;
SELECT @Despues=(SELECT IdCategoria,Nombre,Descripcion,EstaActiva FROM dbo.Categorias WHERE IdCategoria=@IdCategoria FOR JSON PATH,WITHOUT_ARRAY_WRAPPER);
INSERT dbo.EventosAuditoria (IdUsuarioActor,Accion,Entidad,IdEntidad,DatosAnteriores,DatosNuevos)
VALUES (@IdActor,N''GUARDAR'',N''Categorias'',@IdCategoria,@Antes,@Despues);
SELECT @IdCategoria IdCategoria;
        COMMIT TRANSACTION;
    END TRY
    BEGIN CATCH
        IF XACT_STATE() <> 0 ROLLBACK TRANSACTION;
        THROW;
    END CATCH;
END;';

    EXEC sys.sp_executesql N'CREATE PROCEDURE dbo.SP_Catalogo_GuardarProducto
@IdActor bigint,@IdSesion uniqueidentifier,@IdCategoria int,@Nombre nvarchar(max),@Descripcion nvarchar(max)=NULL,@EstaActivo bit=0,@IdProducto bigint=NULL
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
IF @Nombre IS NULL OR LEN(LTRIM(RTRIM(@Nombre)))=0 OR DATALENGTH(@Nombre)>400
THROW 62003,N''Texto obligatorio vacío o longitud no válida.'',1;

IF @EstaActivo IS NULL OR NOT EXISTS(SELECT 1 FROM dbo.Categorias WHERE IdCategoria=@IdCategoria) THROW 62108,N''Categoría o estado inválido.'',1;
IF @EstaActivo=1 AND NOT EXISTS(SELECT 1 FROM dbo.VariantesProducto WHERE IdProducto=@IdProducto AND EstaActiva=1 AND Precio>0)
THROW 62109,N''Active una variante antes de activar el producto.'',1;
DECLARE @Antes nvarchar(max),@Despues nvarchar(max);
IF @IdProducto IS NULL BEGIN
 INSERT dbo.Productos(IdCategoria,Nombre,Descripcion,EstaActivo) VALUES(@IdCategoria,LTRIM(RTRIM(@Nombre)),@Descripcion,0);
 SET @IdProducto=CONVERT(bigint,SCOPE_IDENTITY());
END ELSE BEGIN
 SELECT @Antes=(SELECT IdProducto,IdCategoria,Nombre,Descripcion,EstaActivo FROM dbo.Productos WHERE IdProducto=@IdProducto FOR JSON PATH,WITHOUT_ARRAY_WRAPPER);
 IF @Antes IS NULL THROW 62110,N''Producto inexistente.'',1;
 UPDATE dbo.Productos SET IdCategoria=@IdCategoria,Nombre=LTRIM(RTRIM(@Nombre)),Descripcion=@Descripcion,EstaActivo=@EstaActivo,FechaActualizacionUTC=SYSUTCDATETIME() WHERE IdProducto=@IdProducto;
END;
SELECT @Despues=(SELECT IdProducto,IdCategoria,Nombre,Descripcion,EstaActivo FROM dbo.Productos WHERE IdProducto=@IdProducto FOR JSON PATH,WITHOUT_ARRAY_WRAPPER);
INSERT dbo.EventosAuditoria (IdUsuarioActor,Accion,Entidad,IdEntidad,DatosAnteriores,DatosNuevos)
VALUES (@IdActor,N''GUARDAR'',N''Productos'',@IdProducto,@Antes,@Despues);
SELECT @IdProducto IdProducto;
        COMMIT TRANSACTION;
    END TRY
    BEGIN CATCH
        IF XACT_STATE() <> 0 ROLLBACK TRANSACTION;
        THROW;
    END CATCH;
END;';

    EXEC sys.sp_executesql N'CREATE PROCEDURE dbo.SP_Catalogo_GuardarVariante
@IdActor bigint,@IdSesion uniqueidentifier,@IdProducto bigint,@SKU nvarchar(max),@Precio decimal(19,4),@Talla nvarchar(max)=NULL,@Color nvarchar(max)=NULL,@EstaActiva bit=1,@IdVariante bigint=NULL
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
IF @SKU IS NULL OR LEN(LTRIM(RTRIM(@SKU)))=0 OR DATALENGTH(@SKU)>128
THROW 62003,N''Texto obligatorio vacío o longitud no válida.'',1;

IF @Precio IS NULL OR @Precio<=0 OR @EstaActiva IS NULL OR DATALENGTH(@Talla)>100 OR DATALENGTH(@Color)>100
OR NOT EXISTS(SELECT 1 FROM dbo.Productos WHERE IdProducto=@IdProducto) THROW 62111,N''Variante inválida.'',1;
SET @SKU=UPPER(LTRIM(RTRIM(@SKU)));
SET @Talla=NULLIF(LTRIM(RTRIM(@Talla)),N''''); SET @Color=NULLIF(LTRIM(RTRIM(@Color)),N'''');
DECLARE @Antes nvarchar(max),@Despues nvarchar(max);
IF @IdVariante IS NULL BEGIN
 INSERT dbo.VariantesProducto(IdProducto,SKU,Talla,Color,Precio,EstaActiva) VALUES(@IdProducto,@SKU,@Talla,@Color,@Precio,@EstaActiva);
 SET @IdVariante=CONVERT(bigint,SCOPE_IDENTITY());
 INSERT dbo.Existencias(IdVariante,CantidadFisica) VALUES(@IdVariante,0);
END ELSE BEGIN
 SELECT @Antes=(SELECT IdVariante,IdProducto,SKU,Talla,Color,Precio,EstaActiva FROM dbo.VariantesProducto WHERE IdVariante=@IdVariante AND IdProducto=@IdProducto FOR JSON PATH,WITHOUT_ARRAY_WRAPPER);
 IF @Antes IS NULL THROW 62112,N''Variante inexistente o producto incorrecto.'',1;
 UPDATE dbo.VariantesProducto SET SKU=@SKU,Talla=@Talla,Color=@Color,Precio=@Precio,EstaActiva=@EstaActiva,FechaActualizacionUTC=SYSUTCDATETIME() WHERE IdVariante=@IdVariante;
END;
IF @EstaActiva=0 AND NOT EXISTS(SELECT 1 FROM dbo.VariantesProducto WHERE IdProducto=@IdProducto AND EstaActiva=1)
BEGIN
 DECLARE @ProductoAntes nvarchar(max)=(SELECT IdProducto,EstaActivo FROM dbo.Productos WHERE IdProducto=@IdProducto FOR JSON PATH,WITHOUT_ARRAY_WRAPPER);
 UPDATE dbo.Productos SET EstaActivo=0,FechaActualizacionUTC=SYSUTCDATETIME() WHERE IdProducto=@IdProducto;
 DECLARE @ProductoDespues nvarchar(max)=(SELECT IdProducto,EstaActivo FROM dbo.Productos WHERE IdProducto=@IdProducto FOR JSON PATH,WITHOUT_ARRAY_WRAPPER);
 INSERT dbo.EventosAuditoria (IdUsuarioActor,Accion,Entidad,IdEntidad,DatosAnteriores,DatosNuevos)
VALUES (@IdActor,N''DESACTIVAR_SIN_VARIANTES'',N''Productos'',@IdProducto,@ProductoAntes,@ProductoDespues);

END;
SELECT @Despues=(SELECT IdVariante,IdProducto,SKU,Talla,Color,Precio,EstaActiva FROM dbo.VariantesProducto WHERE IdVariante=@IdVariante FOR JSON PATH,WITHOUT_ARRAY_WRAPPER);
INSERT dbo.EventosAuditoria (IdUsuarioActor,Accion,Entidad,IdEntidad,DatosAnteriores,DatosNuevos)
VALUES (@IdActor,N''GUARDAR'',N''VariantesProducto'',@IdVariante,@Antes,@Despues);
SELECT @IdVariante IdVariante;
        COMMIT TRANSACTION;
    END TRY
    BEGIN CATCH
        IF XACT_STATE() <> 0 ROLLBACK TRANSACTION;
        THROW;
    END CATCH;
END;';

    EXEC sys.sp_executesql N'CREATE PROCEDURE dbo.SP_Catalogo_GuardarImagen
@IdActor bigint,@IdSesion uniqueidentifier,@IdProducto bigint,@Ruta nvarchar(max),@TextoAlternativo nvarchar(max)=NULL,@Orden int=0,@EsPrincipal bit=0,@EstaActiva bit=1,@IdImagen bigint=NULL
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
IF @Ruta IS NULL OR LEN(LTRIM(RTRIM(@Ruta)))=0 OR DATALENGTH(@Ruta)>1000
THROW 62003,N''Texto obligatorio vacío o longitud no válida.'',1;

IF DATALENGTH(@TextoAlternativo)>500 OR @Orden IS NULL OR @Orden<0 OR @EsPrincipal IS NULL OR @EstaActiva IS NULL
OR NOT EXISTS(SELECT 1 FROM dbo.Productos WHERE IdProducto=@IdProducto) THROW 62113,N''Imagen inválida.'',1;
DECLARE @Antes nvarchar(max),@Despues nvarchar(max);
IF @IdImagen IS NOT NULL BEGIN
 SELECT @Antes=(SELECT IdImagen,RutaImagen,TextoAlternativo,OrdenVisualizacion,EsPrincipal,EstaActiva FROM dbo.ImagenesProducto WHERE IdImagen=@IdImagen AND IdProducto=@IdProducto FOR JSON PATH,WITHOUT_ARRAY_WRAPPER);
 IF @Antes IS NULL THROW 62114,N''Imagen inexistente o producto incorrecto.'',1;
END;
IF @IdImagen IS NULL BEGIN
 INSERT dbo.ImagenesProducto(IdProducto,RutaImagen,TextoAlternativo,OrdenVisualizacion,EsPrincipal,EstaActiva)
 VALUES(@IdProducto,@Ruta,@TextoAlternativo,@Orden,@EsPrincipal,@EstaActiva);
 SET @IdImagen=CONVERT(bigint,SCOPE_IDENTITY());
END ELSE
 UPDATE dbo.ImagenesProducto SET RutaImagen=@Ruta,TextoAlternativo=@TextoAlternativo,OrdenVisualizacion=@Orden,EsPrincipal=@EsPrincipal,EstaActiva=@EstaActiva,FechaActualizacionUTC=SYSUTCDATETIME() WHERE IdImagen=@IdImagen;
SELECT @Despues=(SELECT IdImagen,RutaImagen,TextoAlternativo,OrdenVisualizacion,EsPrincipal,EstaActiva FROM dbo.ImagenesProducto WHERE IdImagen=@IdImagen FOR JSON PATH,WITHOUT_ARRAY_WRAPPER);
INSERT dbo.EventosAuditoria (IdUsuarioActor,Accion,Entidad,IdEntidad,DatosAnteriores,DatosNuevos)
VALUES (@IdActor,N''GUARDAR'',N''ImagenesProducto'',@IdImagen,@Antes,@Despues);
SELECT @IdImagen IdImagen;
        COMMIT TRANSACTION;
    END TRY
    BEGIN CATCH
        IF XACT_STATE() <> 0 ROLLBACK TRANSACTION;
        THROW;
    END CATCH;
END;';

    EXEC sys.sp_executesql N'
        INSERT dbo.VersionesMigracion ([Version],NombreArchivo,SHA256,FechaAplicacionUTC,Ejecutor)
        VALUES (12,N''012_ProcedimientosCatalogo.sql'',@Huella,SYSUTCDATETIME(),ORIGINAL_LOGIN());
    ',N'@Huella varbinary(32)',@Huella=@SHA256;
    COMMIT TRANSACTION;
    PRINT N'Migración 12 completada.';
END TRY
BEGIN CATCH
    IF XACT_STATE() <> 0 ROLLBACK TRANSACTION;
    THROW;
END CATCH;

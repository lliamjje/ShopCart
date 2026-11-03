/*
    020_ProcedimientosReportesAuditoria.sql. Ejecutar completo, sin GO, con Auto-commit en ShopCart.
    SHA-256 final: suministrar 32 bytes mediante SESSION_CONTEXT,
    clave ShopCart.Migracion020.SHA256, misma conexión DataGrip.
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
    Ventas: ENTREGADO, fecha de pago, devoluciones APROBADA/RECIBIDA/COMPLETADA y prorrateo monetario entero exacto. Finanzas es flujo monetario por fecha de resolución. No se ha medido rendimiento.
*/
IF DB_NAME() <> N'ShopCart'
    THROW 62800, N'020 solo puede ejecutarse en la base ShopCart.', 1;

IF @@TRANCOUNT <> 0 OR (2 & @@OPTIONS) = 2
    THROW 62801, N'Inicie con Auto-commit y sin transacciones abiertas o implícitas.', 1;

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
    THROW 62802, N'Se requiere CONTROL sobre ShopCart para inspeccionar y crear el esquema.', 1;

IF NOT EXISTS (
    SELECT 1 FROM sys.databases
    WHERE database_id = DB_ID()
      AND collation_name = N'Latin1_General_100_CI_AI_SC'
      AND recovery_model_desc = N'SIMPLE'
      AND state_desc = N'ONLINE' AND user_access_desc = N'MULTI_USER'
      AND is_read_only = 0 AND source_database_id IS NULL
)
    THROW 62803, N'Las propiedades de ShopCart no coinciden con el arranque 001.', 1;

DECLARE @HuellaRecibida sql_variant = SESSION_CONTEXT(N'ShopCart.Migracion020.SHA256');
IF @HuellaRecibida IS NULL
   OR CONVERT(nvarchar(128), SQL_VARIANT_PROPERTY(@HuellaRecibida, 'BaseType')) NOT IN (N'binary', N'varbinary')
    THROW 62804, N'Suministre el SHA-256 real como valor binario en SESSION_CONTEXT antes de ejecutar 020.', 1;

DECLARE @SHA256 varbinary(max) = CONVERT(varbinary(max), @HuellaRecibida);
IF DATALENGTH(@SHA256) <> 32
    THROW 62805, N'La huella SHA-256 debe contener exactamente 32 bytes.', 1;

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
        THROW 62806, N'No se pudo obtener el bloqueo exclusivo de migraciones.', 1;

    DECLARE @IDVersiones int = OBJECT_ID(N'dbo.VersionesMigracion', N'U');
    IF @IDVersiones IS NULL
        THROW 62807, N'Falta la tabla técnica creada por 001. No se aplicará 020.', 1;

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
        THROW 62808, N'Las columnas de VersionesMigracion no cumplen el contrato de 001.', 1;

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
        THROW 62809, N'VersionesMigracion requiere la PK clustered de 001 sobre Version.', 1;

    IF EXISTS (SELECT 1 FROM sys.triggers WHERE parent_id = @IDVersiones)
       OR EXISTS (SELECT 1 FROM sys.tables WHERE object_id = @IDVersiones
                  AND (temporal_type <> 0 OR is_memory_optimized = 1))
        THROW 62810, N'VersionesMigracion tiene características inesperadas; revisar manualmente.', 1;

    -- Lote inferior: errores de compilación/resolución quedan dentro del TRY externo.
    EXEC sys.sp_executesql N'
        IF NOT EXISTS (
            SELECT 1 FROM dbo.VersionesMigracion WITH (UPDLOCK, HOLDLOCK)
            WHERE [Version] = 19 AND NombreArchivo = N''019_ProcedimientosDevoluciones.sql''
        )
            THROW 62813, N''Debe estar registrada la migración 019_ProcedimientosDevoluciones.sql antes de aplicar 020.'', 1;
        IF EXISTS (SELECT 1 FROM dbo.VersionesMigracion WITH (UPDLOCK, HOLDLOCK)
                   WHERE [Version] >= 20)
            THROW 62811, N''020 o una migración posterior ya está registrada. No se reaplica ni se certifica el esquema existente.'', 1;
    ';


    -- Rechaza nombres conflictivos antes de crear el primer procedimiento.
    IF OBJECT_ID(N'dbo.SP_Reportes_Ventas') IS NOT NULL THROW 62850, N'Ya existe un objeto de procedimiento; no se sobrescribe.',1;
    IF OBJECT_ID(N'dbo.SP_Reportes_Finanzas') IS NOT NULL THROW 62850, N'Ya existe un objeto de procedimiento; no se sobrescribe.',1;
    IF OBJECT_ID(N'dbo.SP_Reportes_Operacion') IS NOT NULL THROW 62850, N'Ya existe un objeto de procedimiento; no se sobrescribe.',1;
    IF OBJECT_ID(N'dbo.SP_Auditoria_Consultar') IS NOT NULL THROW 62850, N'Ya existe un objeto de procedimiento; no se sobrescribe.',1;

    EXEC sys.sp_executesql N'CREATE PROCEDURE dbo.SP_Reportes_Ventas
@IdActor bigint,@IdSesion uniqueidentifier,@Desde datetime2(7),@Hasta datetime2(7),
@Dimension varchar(15)=''DIA'',@Pagina int=1,@TamanoPagina int=50,@Top int=10
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;
EXEC dbo.SP_Interno_Autorizar @IdActor, @IdSesion, N''ADMINISTRADOR'';

IF @Desde IS NULL OR @Hasta IS NULL OR @Desde>=@Hasta OR @Dimension IS NULL
OR @Dimension NOT IN(''DIA'',''SEMANA'',''MES'',''PRODUCTO'',''CATEGORIA'',''TOP'')
OR @Pagina IS NULL OR @Pagina<1 OR @TamanoPagina IS NULL OR @TamanoPagina NOT BETWEEN 1 AND 100 OR @Top IS NULL OR @Top NOT BETWEEN 1 AND 100
THROW 63000,N''Filtros de ventas inválidos.'',1;
;WITH Lineas AS(
 SELECT p.IdPedido,d.IdDetallePedido,pr.IdProducto,d.IdCategoria,d.NombreCategoria,
 d.NombreProducto,pa.FechaResolucionUTC,
 CONVERT(bigint,d.Cantidad)-COALESCE(dev.Cantidad,0) UnidadesNetas,
 CONVERT(decimal(19,4),d.TotalLinea-
 CONVERT(decimal(19,0),
 (n.Unidades-n.Unidades%d.Cantidad)/d.Cantidad+
 CASE WHEN (n.Unidades%d.Cantidad)*2>=d.Cantidad THEN 1 ELSE 0 END)/10000.0) Neto,
 d.SubtotalLinea,d.DescuentoLinea
 FROM dbo.Pedidos p JOIN dbo.Pagos pa ON pa.IdPedido=p.IdPedido AND pa.Estado=''APROBADO''
 JOIN dbo.DetallesPedido d ON d.IdPedido=p.IdPedido
 JOIN dbo.VariantesProducto v ON v.IdVariante=d.IdVariante JOIN dbo.Productos pr ON pr.IdProducto=v.IdProducto
 OUTER APPLY(SELECT SUM(CONVERT(bigint,dd.Cantidad)) Cantidad FROM dbo.DetallesDevolucion dd
 JOIN dbo.Devoluciones de ON de.IdDevolucion=dd.IdDevolucion WHERE dd.IdDetallePedido=d.IdDetallePedido
 AND de.Estado IN(''APROBADA'',''RECIBIDA'',''COMPLETADA'')) dev
 CROSS APPLY(SELECT CONVERT(decimal(19,0),d.TotalLinea*10000)*CONVERT(decimal(10,0),COALESCE(dev.Cantidad,0)) Unidades) n
 WHERE p.Estado=''ENTREGADO'' AND pa.FechaResolucionUTC>=@Desde AND pa.FechaResolucionUTC<@Hasta
), Agrupada AS(
 SELECT CASE
 WHEN @Dimension=''DIA'' THEN CONVERT(nvarchar(10),CONVERT(date,FechaResolucionUTC),23)
 WHEN @Dimension=''MES'' THEN CONVERT(nvarchar(7),FechaResolucionUTC,126)
 WHEN @Dimension=''SEMANA'' THEN CONVERT(nvarchar(10),DATEADD(day,-((DATEDIFF(day,CONVERT(date,''19000101'',112),CONVERT(date,FechaResolucionUTC))%7+7)%7),CONVERT(date,FechaResolucionUTC)),23)
 WHEN @Dimension=''CATEGORIA'' THEN COALESCE(CONVERT(nvarchar(20),IdCategoria),N''SIN_CATEGORIA'')
 ELSE CONVERT(nvarchar(20),IdProducto) END Clave,
 MIN(CASE WHEN @Dimension=''CATEGORIA'' THEN NombreCategoria WHEN @Dimension IN(''PRODUCTO'',''TOP'') THEN NombreProducto END) Nombre,
 SUM(UnidadesNetas) UnidadesNetas,SUM(CONVERT(decimal(30,4),Neto)) VentasNetasProductos,
 SUM(CONVERT(decimal(30,4),SubtotalLinea)) SubtotalHistorico,
 SUM(CONVERT(decimal(30,4),DescuentoLinea)) DescuentoHistorico,
 COUNT(DISTINCT IdPedido) Pedidos
 FROM Lineas
 GROUP BY CASE
 WHEN @Dimension=''DIA'' THEN CONVERT(nvarchar(10),CONVERT(date,FechaResolucionUTC),23)
 WHEN @Dimension=''MES'' THEN CONVERT(nvarchar(7),FechaResolucionUTC,126)
 WHEN @Dimension=''SEMANA'' THEN CONVERT(nvarchar(10),DATEADD(day,-((DATEDIFF(day,CONVERT(date,''19000101'',112),CONVERT(date,FechaResolucionUTC))%7+7)%7),CONVERT(date,FechaResolucionUTC)),23)
 WHEN @Dimension=''CATEGORIA'' THEN COALESCE(CONVERT(nvarchar(20),IdCategoria),N''SIN_CATEGORIA'')
 ELSE CONVERT(nvarchar(20),IdProducto) END
), Ordenada AS(
 SELECT *,COUNT_BIG(*) OVER() TotalFilas,ROW_NUMBER() OVER(
 ORDER BY CASE WHEN @Dimension=''TOP'' THEN UnidadesNetas END DESC,Clave) Fila FROM Agrupada
)
SELECT Clave,Nombre,UnidadesNetas,VentasNetasProductos,SubtotalHistorico,DescuentoHistorico,Pedidos,TotalFilas
FROM Ordenada WHERE (@Dimension<>''TOP'' OR Fila<=@Top)
AND Fila>((CONVERT(bigint,@Pagina)-1)*@TamanoPagina) AND Fila<=CONVERT(bigint,@Pagina)*@TamanoPagina ORDER BY Fila;
-- Envío separado: no se distribuye arbitrariamente entre categorías.
SELECT COUNT_BIG(*) PedidosEntregados,COALESCE(SUM(CONVERT(decimal(30,4),p.CostoEnvio)),0) Envio
FROM dbo.Pedidos p JOIN dbo.Pagos pa ON pa.IdPedido=p.IdPedido AND pa.Estado=''APROBADO''
WHERE p.Estado=''ENTREGADO'' AND pa.FechaResolucionUTC>=@Desde AND pa.FechaResolucionUTC<@Hasta;
END;';

    EXEC sys.sp_executesql N'CREATE PROCEDURE dbo.SP_Reportes_Finanzas
@IdActor bigint,@IdSesion uniqueidentifier,@Desde datetime2(7),@Hasta datetime2(7)
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;
EXEC dbo.SP_Interno_Autorizar @IdActor, @IdSesion, N''ADMINISTRADOR'';

IF @Desde IS NULL OR @Hasta IS NULL OR @Desde>=@Hasta THROW 63001,N''Intervalo inválido.'',1;
DECLARE @Cobros decimal(35,4),@Dev decimal(35,4),@Can decimal(35,4);
SELECT @Cobros=COALESCE(SUM(CONVERT(decimal(30,4),Monto)),0) FROM dbo.Pagos WHERE Estado=''APROBADO'' AND FechaResolucionUTC>=@Desde AND FechaResolucionUTC<@Hasta;
SELECT @Dev=COALESCE(SUM(CONVERT(decimal(30,4),Monto)),0) FROM dbo.Reembolsos WHERE Estado=''APROBADO'' AND FechaResolucionUTC>=@Desde AND FechaResolucionUTC<@Hasta;
SELECT @Can=COALESCE(SUM(CONVERT(decimal(30,4),Monto)),0) FROM dbo.ReembolsosCancelacion WHERE Estado=''APROBADO'' AND FechaResolucionUTC>=@Desde AND FechaResolucionUTC<@Hasta;
SELECT @Cobros CobrosAprobados,@Dev ReembolsosDevoluciones,@Can ReembolsosCancelaciones,
@Cobros-@Dev-@Can FlujoMonetarioNeto;
SELECT p.Estado,COUNT_BIG(*) Pedidos,SUM(CONVERT(decimal(30,4),p.Total)) TotalPedidos,
SUM(CONVERT(decimal(30,4),p.Descuento)) Descuentos FROM dbo.Pedidos p
WHERE p.FechaPedidoUTC>=@Desde AND p.FechaPedidoUTC<@Hasta GROUP BY p.Estado ORDER BY p.Estado;
SELECT COUNT_BIG(*) PedidosPagadosNoCancelados,
COALESCE(SUM(CONVERT(decimal(30,4),p.Subtotal)-p.Descuento),0) NetoProductos,
COALESCE(AVG(CONVERT(decimal(30,4),p.Subtotal)-p.Descuento),0) TicketPromedio
FROM dbo.Pedidos p JOIN dbo.Pagos pa ON pa.IdPedido=p.IdPedido AND pa.Estado=''APROBADO''
WHERE p.Estado<>''CANCELADO'' AND pa.FechaResolucionUTC>=@Desde AND pa.FechaResolucionUTC<@Hasta;
SELECT Estado,COUNT_BIG(*) Operaciones FROM dbo.Devoluciones WHERE FechaSolicitudUTC>=@Desde AND FechaSolicitudUTC<@Hasta GROUP BY Estado ORDER BY Estado;
END;';

    EXEC sys.sp_executesql N'CREATE PROCEDURE dbo.SP_Reportes_Operacion
@IdActor bigint,@IdSesion uniqueidentifier,@Modulo varchar(20),@Desde datetime2(7),@Hasta datetime2(7),
@Pagina int=1,@TamanoPagina int=50
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;
EXEC dbo.SP_Interno_Autorizar @IdActor, @IdSesion, N''OPERADOR'';

IF @Desde IS NULL OR @Hasta IS NULL OR @Desde>=@Hasta OR @Pagina IS NULL OR @Pagina<1
OR @TamanoPagina IS NULL OR @TamanoPagina NOT BETWEEN 1 AND 100 OR @Modulo IS NULL
OR @Modulo NOT IN(''INVENTARIO'',''MOVIMIENTOS'',''RESERVAS'',''DEVOLUCIONES'',''REEMBOLSOS'',''CUPONES'')
THROW 63002,N''Filtros inválidos.'',1;
IF @Modulo IN(''REEMBOLSOS'',''CUPONES'') EXEC dbo.SP_Interno_Autorizar @IdActor,@IdSesion,N''ADMINISTRADOR'';
DECLARE @Offset bigint=(CONVERT(bigint,@Pagina)-1)*@TamanoPagina;
IF @Modulo=''INVENTARIO''
 SELECT e.IdVariante,v.SKU,e.CantidadFisica,COALESCE(r.Cantidad,0) Reservada,
 CONVERT(bigint,e.CantidadFisica)-COALESCE(r.Cantidad,0) Disponible,COUNT_BIG(*) OVER() TotalFilas
 FROM dbo.Existencias e JOIN dbo.VariantesProducto v ON v.IdVariante=e.IdVariante
 OUTER APPLY(SELECT SUM(CONVERT(bigint,Cantidad)) Cantidad FROM dbo.ReservasInventario WHERE IdVariante=e.IdVariante AND Estado=''ACTIVA'' AND FechaExpiracionUTC>SYSUTCDATETIME()) r
 ORDER BY e.IdVariante OFFSET @Offset ROWS FETCH NEXT @TamanoPagina ROWS ONLY;
ELSE IF @Modulo=''MOVIMIENTOS''
 SELECT IdMovimiento,IdVariante,TipoMovimiento,Cantidad,SaldoAnterior,SaldoPosterior,Motivo,FechaMovimientoUTC,COUNT_BIG(*) OVER() TotalFilas
 FROM dbo.MovimientosInventario WHERE FechaMovimientoUTC>=@Desde AND FechaMovimientoUTC<@Hasta
 ORDER BY FechaMovimientoUTC,IdMovimiento OFFSET @Offset ROWS FETCH NEXT @TamanoPagina ROWS ONLY;
ELSE IF @Modulo=''RESERVAS''
 SELECT IdReservaInventario,IdCheckout,IdVariante,Cantidad,Estado,FechaExpiracionUTC,
 CONVERT(bit,CASE WHEN Estado=''ACTIVA'' AND FechaExpiracionUTC>SYSUTCDATETIME() THEN 1 ELSE 0 END) EfectivamenteVigente,
 COUNT_BIG(*) OVER() TotalFilas FROM dbo.ReservasInventario
 WHERE FechaCreacionUTC>=@Desde AND FechaCreacionUTC<@Hasta ORDER BY IdReservaInventario OFFSET @Offset ROWS FETCH NEXT @TamanoPagina ROWS ONLY;
ELSE IF @Modulo=''DEVOLUCIONES''
 SELECT IdDevolucion,IdPedido,Estado,FechaSolicitudUTC,FechaResolucionUTC,COUNT_BIG(*) OVER() TotalFilas FROM dbo.Devoluciones
 WHERE FechaSolicitudUTC>=@Desde AND FechaSolicitudUTC<@Hasta ORDER BY FechaSolicitudUTC,IdDevolucion OFFSET @Offset ROWS FETCH NEXT @TamanoPagina ROWS ONLY;
ELSE IF @Modulo=''CUPONES''
 SELECT u.IdUsoCupon,u.IdCupon,c.Codigo,u.IdPedido,u.IdUsuario,u.FechaUsoUTC,p.Descuento,COUNT_BIG(*) OVER() TotalFilas
 FROM dbo.UsosCupon u JOIN dbo.Cupones c ON c.IdCupon=u.IdCupon JOIN dbo.Pedidos p ON p.IdPedido=u.IdPedido
 WHERE u.FechaUsoUTC>=@Desde AND u.FechaUsoUTC<@Hasta ORDER BY u.FechaUsoUTC,u.IdUsoCupon OFFSET @Offset ROWS FETCH NEXT @TamanoPagina ROWS ONLY;
ELSE BEGIN
 ;WITH R AS(
 SELECT ''DEVOLUCION'' Origen,IdReembolso Id,IdPago,Estado,Monto,FechaCreacionUTC,FechaResolucionUTC FROM dbo.Reembolsos
 UNION ALL SELECT ''CANCELACION'',IdReembolsoCancelacion,IdPago,Estado,Monto,FechaCreacionUTC,FechaResolucionUTC FROM dbo.ReembolsosCancelacion)
 SELECT *,COUNT_BIG(*) OVER() TotalFilas FROM R WHERE FechaCreacionUTC>=@Desde AND FechaCreacionUTC<@Hasta
 ORDER BY FechaCreacionUTC,Origen,Id OFFSET @Offset ROWS FETCH NEXT @TamanoPagina ROWS ONLY;
END;
END;';

    EXEC sys.sp_executesql N'CREATE PROCEDURE dbo.SP_Auditoria_Consultar
@IdActor bigint,@IdSesion uniqueidentifier,@Desde datetime2(7),@Hasta datetime2(7),
@IdUsuario bigint=NULL,@Entidad varchar(max)=NULL,@IdCorrelacion uniqueidentifier=NULL,@Modulo varchar(20)=NULL,
@Pagina int=1,@TamanoPagina int=50
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;
EXEC dbo.SP_Interno_Autorizar @IdActor, @IdSesion, N''ADMINISTRADOR'';

IF @Desde IS NULL OR @Hasta IS NULL OR @Desde>=@Hasta OR @Pagina IS NULL OR @Pagina<1
OR @TamanoPagina IS NULL OR @TamanoPagina NOT BETWEEN 1 AND 100 OR DATALENGTH(@Entidad)>100
OR (@Modulo IS NOT NULL AND @Modulo NOT IN(''CATALOGO'',''SEGURIDAD'',''INVENTARIO'',''VENTAS'',''DEVOLUCIONES'',''CUPONES''))
THROW 63003,N''Filtros de auditoría inválidos.'',1;
;WITH E AS(
 SELECT *,CASE
 WHEN Entidad IN(''Categorias'',''Productos'',''VariantesProducto'',''ImagenesProducto'') THEN ''CATALOGO''
 WHEN Entidad IN(''Usuarios'',''SesionesUsuario'',''TokensRenovacion'',''Direcciones'') THEN ''SEGURIDAD''
 WHEN Entidad IN(''Existencias'',''MovimientosInventario'') THEN ''INVENTARIO''
 WHEN Entidad IN(''Pedidos'',''Pagos'',''Checkouts'',''HistorialEstadosPedido'') THEN ''VENTAS''
 WHEN Entidad IN(''Devoluciones'',''Reembolsos'',''ReembolsosCancelacion'') THEN ''DEVOLUCIONES''
 WHEN Entidad IN(''Cupones'',''UsosCupon'') THEN ''CUPONES'' ELSE ''OTROS'' END Modulo
 FROM dbo.EventosAuditoria)
SELECT IdEventoAuditoria,IdUsuarioActor,Accion,Entidad,IdEntidad,DatosAnteriores,DatosNuevos,IdCorrelacion,FechaEventoUTC,Modulo,COUNT_BIG(*) OVER() TotalFilas
FROM E WHERE FechaEventoUTC>=@Desde AND FechaEventoUTC<@Hasta AND (@IdUsuario IS NULL OR IdUsuarioActor=@IdUsuario)
AND (@Entidad IS NULL OR Entidad=@Entidad) AND (@IdCorrelacion IS NULL OR IdCorrelacion=@IdCorrelacion)
AND (@Modulo IS NULL OR Modulo=@Modulo)
ORDER BY FechaEventoUTC,IdEventoAuditoria OFFSET ((CONVERT(bigint,@Pagina)-1)*@TamanoPagina) ROWS FETCH NEXT @TamanoPagina ROWS ONLY;
END;';

    EXEC sys.sp_executesql N'
        INSERT dbo.VersionesMigracion ([Version],NombreArchivo,SHA256,FechaAplicacionUTC,Ejecutor)
        VALUES (20,N''020_ProcedimientosReportesAuditoria.sql'',@Huella,SYSUTCDATETIME(),ORIGINAL_LOGIN());
    ',N'@Huella varbinary(32)',@Huella=@SHA256;
    COMMIT TRANSACTION;
    PRINT N'Migración 20 completada.';
END TRY
BEGIN CATCH
    IF XACT_STATE() <> 0 ROLLBACK TRANSACTION;
    THROW;
END CATCH;

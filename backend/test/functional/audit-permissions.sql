/* Verificación administrativa opcional, SOLO lectura.
   Ejecutar con la identidad real shopcart_service en ShopCart; NO como administrador,
   NO mediante EXECUTE AS. No se prueban UPDATE/DELETE, ni siquiera sobre cero filas.
   0 significa ausencia de permiso efectivo, no prueba un DENY explícito.
   NULL significa NO VERIFICABLE y nunca se convierte en 0.
   Los nombres de columnas conocidos proceden de 010; se consultan por nombre
   sin necesitar OBJECT_ID. Si los metadatos están ocultos no se certifica
   que esa lista sea exhaustiva en la base actual: cobertura global parcial.
   Este archivo no lo invoca la API ni el ejecutor funcional.
*/
IF DB_NAME() <> N'ShopCart' OR ORIGINAL_LOGIN() <> N'shopcart_service'
 OR SUSER_SNAME() <> N'shopcart_service' OR USER_NAME() <> N'shopcart_service'
    THROW 65000, N'Use ShopCart y la conexión real de shopcart_service.', 1;

DECLARE @ObjetoId int = OBJECT_ID(N'dbo.EventosAuditoria', N'U');
SELECT ORIGINAL_LOGIN() AS LoginOriginal, SUSER_SNAME() AS LoginActual,
       USER_NAME() AS UsuarioBase, DB_NAME() AS BaseDatos,
       CASE WHEN @ObjetoId IS NULL THEN N'NO_VISIBLE_O_NO_EXISTENTE'
            ELSE N'VISIBLE' END AS VisibilidadObjeto,
       CASE WHEN @ObjetoId IS NULL THEN N'PARCIAL: no se pueden enumerar todas las columnas actuales'
            ELSE N'Columnas enumeradas; revisar individualmente los resultados' END AS Cobertura;

WITH Columnas AS (
    SELECT Nombre FROM (VALUES
        (N'IdEventoAuditoria'), (N'IdUsuarioActor'), (N'Accion'), (N'Entidad'),
        (N'IdEntidad'), (N'DatosAnteriores'), (N'DatosNuevos'),
        (N'IdCorrelacion'), (N'FechaEventoUTC')
    ) AS conocidas(Nombre)
    UNION
    SELECT name FROM sys.columns WHERE object_id = @ObjetoId
), Comprobaciones AS (
    SELECT N'OBJETO' AS Ambito, CAST(NULL AS nvarchar(128)) AS Columna,
           p.Permiso,
           HAS_PERMS_BY_NAME(N'dbo.EventosAuditoria', N'OBJECT', p.Permiso) AS Valor
    FROM (VALUES (N'UPDATE'), (N'DELETE'), (N'ALTER')) AS p(Permiso)
    UNION ALL
    SELECT N'COLUMNA', Nombre, N'UPDATE',
           HAS_PERMS_BY_NAME(N'dbo.EventosAuditoria', N'OBJECT', N'UPDATE', Nombre, N'COLUMN')
    FROM Columnas
)
SELECT Ambito, Columna, Permiso, Valor,
       CASE Valor WHEN 0 THEN N'SIN_PERMISO_EFECTIVO'
                  WHEN 1 THEN N'PERMISO_PRESENTE'
                  ELSE N'NO_VERIFICABLE' END AS Resultado
FROM Comprobaciones ORDER BY Ambito, Columna, Permiso;
-- No se emite APROBADA global: el consumidor debe comprobar todos los valores
-- y distinguir los permisos consultados de la cobertura de metadatos.

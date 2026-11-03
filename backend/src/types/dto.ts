/** DTOs tras normalizar los tipos del driver; importes e IDs bigint son strings. */
export type Money=string;
export type BigintId=string;
export interface CartDto {
 IdCarrito:BigintId;Estado:'ACTIVO'|'CONVERTIDO'|'FUSIONADO';
 FechaUltimaActividadUTC:string;RevisionCarrito:string;
}
export interface CartItemDto {
 IdDetalleCarrito:BigintId;IdVariante:BigintId;SKU:string;Nombre:string;
 Precio:Money;Cantidad:number;SubtotalLinea:Money;Disponible:BigintId;EstaDisponible:boolean;
}
export interface CartResponse {cart:CartDto|null;items:CartItemDto[];totals:{Subtotal:Money;Descuento:Money}|null}
export interface StartedCheckoutDto {IdCheckout:BigintId;IdPedido:BigintId;Total:Money;FechaExpiracionUTC:string}
export interface PaymentDto {
 IdPago:BigintId;IdPedido:BigintId;Estado:'PENDIENTE'|'APROBADO'|'RECHAZADO'|'CANCELADO';
 Monto:Money;ReferenciaPago:string;FechaResolucionUTC:string|null;
}
export interface OrderDto {
 IdPedido:BigintId;NumeroPedido:string;IdCheckout:BigintId;IdUsuario:BigintId|null;
 Estado:'PENDIENTE_PAGO'|'PAGADO'|'EN_PREPARACION'|'ENVIADO'|'ENTREGADO'|'CANCELADO';
 Subtotal:Money;Descuento:Money;CostoEnvio:Money;Total:Money;BaseImponible:Money;MontoIVA:Money;
 NombreDestinatario:string;TelefonoDestinatario:string;DireccionLinea1:string;DireccionLinea2:string|null;
 Ciudad:string;Departamento:string;CodigoPostal:string|null;Pais:'GT';Moneda:'GTQ';
 CodigoMetodoEnvio:string;NombreMetodoEnvio:string;FechaPedidoUTC:string;FechaActualizacionUTC:string;
}
export interface ReturnDto {
 IdDevolucion:BigintId;IdPedido:BigintId;IdUsuarioSolicitante:BigintId|null;
 Estado:'SOLICITADA'|'APROBADA'|'RECHAZADA'|'RECIBIDA'|'COMPLETADA'|'CANCELADA';
 Motivo:string;Observaciones:string|null;FechaSolicitudUTC:string;FechaActualizacionUTC:string;FechaResolucionUTC:string|null;
}
export interface Success<T> {success:true;data:T}
export interface Failure {success:false;error:{code:string;message:string}}

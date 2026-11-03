export const sqlErrors:Record<number,{status:number;message:string}>={
  "62001": {
    "status": 409,
    "message": "La operación requiere Auto-commit sin transacción externa."
  },
  "62002": {
    "status": 409,
    "message": "No se pudo serializar la operación; reintente la solicitud completa."
  },
  "62003": {
    "status": 400,
    "message": "Texto obligatorio vacío o longitud no válida."
  },
  "62100": {
    "status": 401,
    "message": "Sesión inválida o expirada."
  },
  "62101": {
    "status": 400,
    "message": "Ámbito inválido."
  },
  "62103": {
    "status": 403,
    "message": "Operación no autorizada."
  },
  "62104": {
    "status": 400,
    "message": "Filtros o paginación inválidos."
  },
  "62105": {
    "status": 404,
    "message": "Producto no disponible."
  },
  "62300": {
    "status": 409,
    "message": "El backend debe aportar un hash Argon2id válido."
  },
  "62301": {
    "status": 400,
    "message": "Correo inválido."
  },
  "62302": {
    "status": 409,
    "message": "Falta el rol Cliente; aplique las semillas aprobadas."
  },
  "62303": {
    "status": 401,
    "message": "Sesión inválida."
  },
  "62304": {
    "status": 400,
    "message": "Parámetros de rotación inválidos."
  },
  "62305": {
    "status": 401,
    "message": "Token inválido."
  },
  "62306": {
    "status": 401,
    "message": "Reutilización detectada; sesión revocada."
  },
  "62307": {
    "status": 401,
    "message": "Sesión o token expirado."
  },
  "62308": {
    "status": 409,
    "message": "Conflicto de rotación."
  },
  "62603": {
    "status": 409,
    "message": "El cálculo requiere la transacción de negocio."
  },
  "62604": {
    "status": 404,
    "message": "Cupón inexistente o inactivo."
  },
  "62605": {
    "status": 409,
    "message": "Cupón fuera de vigencia."
  },
  "62606": {
    "status": 409,
    "message": "Compra mínima no alcanzada."
  },
  "62607": {
    "status": 409,
    "message": "No hay líneas elegibles."
  },
  "62608": {
    "status": 401,
    "message": "El cupón requiere autenticación."
  },
  "62609": {
    "status": 409,
    "message": "Límite de usos agotado."
  },
  "62700": {
    "status": 404,
    "message": "Checkout inexistente."
  },
  "62823": {
    "status": 400,
    "message": "Número de pedido inválido."
  },
  "62824": {
    "status": 409,
    "message": "Identificador y número no corresponden."
  },
  "62900": {
    "status": 404,
    "message": "Pedido inexistente."
  }
};

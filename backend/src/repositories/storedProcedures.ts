// Contratos extraídos de las migraciones inmutables 012–020; no son SQL ejecutable.
export interface ParameterDefinition {readonly name:string;readonly type:string;readonly size:string|null;readonly scale:string|null;readonly optional:boolean;readonly output:boolean}
export const procedures = {
  "SP_Interno_Autorizar": {
    "params": [
      {
        "name": "IdActor",
        "type": "bigint",
        "size": null,
        "scale": null,
        "optional": false,
        "output": false
      },
      {
        "name": "IdSesion",
        "type": "uniqueidentifier",
        "size": null,
        "scale": null,
        "optional": false,
        "output": false
      },
      {
        "name": "Ambito",
        "type": "nvarchar",
        "size": "30",
        "scale": null,
        "optional": false,
        "output": false
      }
    ]
  },
  "SP_Catalogo_ListarCategorias": {
    "params": []
  },
  "SP_Catalogo_ListarProductos": {
    "params": [
      {
        "name": "Texto",
        "type": "nvarchar",
        "size": "max",
        "scale": null,
        "optional": true,
        "output": false
      },
      {
        "name": "IdCategoria",
        "type": "int",
        "size": null,
        "scale": null,
        "optional": true,
        "output": false
      },
      {
        "name": "PrecioMin",
        "type": "decimal",
        "size": "19",
        "scale": "4",
        "optional": true,
        "output": false
      },
      {
        "name": "PrecioMax",
        "type": "decimal",
        "size": "19",
        "scale": "4",
        "optional": true,
        "output": false
      },
      {
        "name": "SoloDisponibles",
        "type": "bit",
        "size": null,
        "scale": null,
        "optional": true,
        "output": false
      },
      {
        "name": "Orden",
        "type": "varchar",
        "size": "20",
        "scale": null,
        "optional": true,
        "output": false
      },
      {
        "name": "Pagina",
        "type": "int",
        "size": null,
        "scale": null,
        "optional": true,
        "output": false
      },
      {
        "name": "TamanoPagina",
        "type": "int",
        "size": null,
        "scale": null,
        "optional": true,
        "output": false
      }
    ]
  },
  "SP_Catalogo_ObtenerProducto": {
    "params": [
      {
        "name": "IdProducto",
        "type": "bigint",
        "size": null,
        "scale": null,
        "optional": false,
        "output": false
      }
    ]
  },
  "SP_Catalogo_GuardarCategoria": {
    "params": [
      {
        "name": "IdActor",
        "type": "bigint",
        "size": null,
        "scale": null,
        "optional": false,
        "output": false
      },
      {
        "name": "IdSesion",
        "type": "uniqueidentifier",
        "size": null,
        "scale": null,
        "optional": false,
        "output": false
      },
      {
        "name": "Nombre",
        "type": "nvarchar",
        "size": "max",
        "scale": null,
        "optional": false,
        "output": false
      },
      {
        "name": "Descripcion",
        "type": "nvarchar",
        "size": "max",
        "scale": null,
        "optional": true,
        "output": false
      },
      {
        "name": "EstaActiva",
        "type": "bit",
        "size": null,
        "scale": null,
        "optional": true,
        "output": false
      },
      {
        "name": "IdCategoria",
        "type": "int",
        "size": null,
        "scale": null,
        "optional": true,
        "output": false
      }
    ]
  },
  "SP_Catalogo_GuardarProducto": {
    "params": [
      {
        "name": "IdActor",
        "type": "bigint",
        "size": null,
        "scale": null,
        "optional": false,
        "output": false
      },
      {
        "name": "IdSesion",
        "type": "uniqueidentifier",
        "size": null,
        "scale": null,
        "optional": false,
        "output": false
      },
      {
        "name": "IdCategoria",
        "type": "int",
        "size": null,
        "scale": null,
        "optional": false,
        "output": false
      },
      {
        "name": "Nombre",
        "type": "nvarchar",
        "size": "max",
        "scale": null,
        "optional": false,
        "output": false
      },
      {
        "name": "Descripcion",
        "type": "nvarchar",
        "size": "max",
        "scale": null,
        "optional": true,
        "output": false
      },
      {
        "name": "EstaActivo",
        "type": "bit",
        "size": null,
        "scale": null,
        "optional": true,
        "output": false
      },
      {
        "name": "IdProducto",
        "type": "bigint",
        "size": null,
        "scale": null,
        "optional": true,
        "output": false
      }
    ]
  },
  "SP_Catalogo_GuardarVariante": {
    "params": [
      {
        "name": "IdActor",
        "type": "bigint",
        "size": null,
        "scale": null,
        "optional": false,
        "output": false
      },
      {
        "name": "IdSesion",
        "type": "uniqueidentifier",
        "size": null,
        "scale": null,
        "optional": false,
        "output": false
      },
      {
        "name": "IdProducto",
        "type": "bigint",
        "size": null,
        "scale": null,
        "optional": false,
        "output": false
      },
      {
        "name": "SKU",
        "type": "nvarchar",
        "size": "max",
        "scale": null,
        "optional": false,
        "output": false
      },
      {
        "name": "Precio",
        "type": "decimal",
        "size": "19",
        "scale": "4",
        "optional": false,
        "output": false
      },
      {
        "name": "Talla",
        "type": "nvarchar",
        "size": "max",
        "scale": null,
        "optional": true,
        "output": false
      },
      {
        "name": "Color",
        "type": "nvarchar",
        "size": "max",
        "scale": null,
        "optional": true,
        "output": false
      },
      {
        "name": "EstaActiva",
        "type": "bit",
        "size": null,
        "scale": null,
        "optional": true,
        "output": false
      },
      {
        "name": "IdVariante",
        "type": "bigint",
        "size": null,
        "scale": null,
        "optional": true,
        "output": false
      }
    ]
  },
  "SP_Catalogo_GuardarImagen": {
    "params": [
      {
        "name": "IdActor",
        "type": "bigint",
        "size": null,
        "scale": null,
        "optional": false,
        "output": false
      },
      {
        "name": "IdSesion",
        "type": "uniqueidentifier",
        "size": null,
        "scale": null,
        "optional": false,
        "output": false
      },
      {
        "name": "IdProducto",
        "type": "bigint",
        "size": null,
        "scale": null,
        "optional": false,
        "output": false
      },
      {
        "name": "Ruta",
        "type": "nvarchar",
        "size": "max",
        "scale": null,
        "optional": false,
        "output": false
      },
      {
        "name": "TextoAlternativo",
        "type": "nvarchar",
        "size": "max",
        "scale": null,
        "optional": true,
        "output": false
      },
      {
        "name": "Orden",
        "type": "int",
        "size": null,
        "scale": null,
        "optional": true,
        "output": false
      },
      {
        "name": "EsPrincipal",
        "type": "bit",
        "size": null,
        "scale": null,
        "optional": true,
        "output": false
      },
      {
        "name": "EstaActiva",
        "type": "bit",
        "size": null,
        "scale": null,
        "optional": true,
        "output": false
      },
      {
        "name": "IdImagen",
        "type": "bigint",
        "size": null,
        "scale": null,
        "optional": true,
        "output": false
      }
    ]
  },
  "SP_Seguridad_RegistrarUsuario": {
    "params": [
      {
        "name": "Nombre",
        "type": "nvarchar",
        "size": "max",
        "scale": null,
        "optional": false,
        "output": false
      },
      {
        "name": "Apellido",
        "type": "nvarchar",
        "size": "max",
        "scale": null,
        "optional": false,
        "output": false
      },
      {
        "name": "Correo",
        "type": "nvarchar",
        "size": "max",
        "scale": null,
        "optional": false,
        "output": false
      },
      {
        "name": "HashContrasena",
        "type": "nvarchar",
        "size": "max",
        "scale": null,
        "optional": false,
        "output": false
      }
    ]
  },
  "SP_Seguridad_ObtenerAutenticacion": {
    "params": [
      {
        "name": "Correo",
        "type": "nvarchar",
        "size": "max",
        "scale": null,
        "optional": false,
        "output": false
      }
    ]
  },
  "SP_Seguridad_ConsultarPerfil": {
    "params": [
      {
        "name": "IdActor",
        "type": "bigint",
        "size": null,
        "scale": null,
        "optional": false,
        "output": false
      },
      {
        "name": "IdSesion",
        "type": "uniqueidentifier",
        "size": null,
        "scale": null,
        "optional": false,
        "output": false
      }
    ]
  },
  "SP_Seguridad_ActualizarPerfil": {
    "params": [
      {
        "name": "IdActor",
        "type": "bigint",
        "size": null,
        "scale": null,
        "optional": false,
        "output": false
      },
      {
        "name": "IdSesion",
        "type": "uniqueidentifier",
        "size": null,
        "scale": null,
        "optional": false,
        "output": false
      },
      {
        "name": "Nombre",
        "type": "nvarchar",
        "size": "max",
        "scale": null,
        "optional": false,
        "output": false
      },
      {
        "name": "Apellido",
        "type": "nvarchar",
        "size": "max",
        "scale": null,
        "optional": false,
        "output": false
      }
    ]
  },
  "SP_Seguridad_CrearSesion": {
    "params": [
      {
        "name": "IdUsuario",
        "type": "bigint",
        "size": null,
        "scale": null,
        "optional": false,
        "output": false
      },
      {
        "name": "HashToken",
        "type": "varbinary",
        "size": "max",
        "scale": null,
        "optional": false,
        "output": false
      },
      {
        "name": "FechaExpiracionUTC",
        "type": "datetime2",
        "size": "7",
        "scale": null,
        "optional": false,
        "output": false
      },
      {
        "name": "DireccionIP",
        "type": "varchar",
        "size": "max",
        "scale": null,
        "optional": true,
        "output": false
      },
      {
        "name": "Agente",
        "type": "nvarchar",
        "size": "max",
        "scale": null,
        "optional": true,
        "output": false
      }
    ]
  },
  "SP_Seguridad_ConsultarSesion": {
    "params": [
      {
        "name": "IdActor",
        "type": "bigint",
        "size": null,
        "scale": null,
        "optional": false,
        "output": false
      },
      {
        "name": "IdSesion",
        "type": "uniqueidentifier",
        "size": null,
        "scale": null,
        "optional": false,
        "output": false
      }
    ]
  },
  "SP_Seguridad_RotarToken": {
    "params": [
      {
        "name": "HashAnterior",
        "type": "varbinary",
        "size": "max",
        "scale": null,
        "optional": false,
        "output": false
      },
      {
        "name": "HashNuevo",
        "type": "varbinary",
        "size": "max",
        "scale": null,
        "optional": false,
        "output": false
      },
      {
        "name": "NuevaExpiracionUTC",
        "type": "datetime2",
        "size": "7",
        "scale": null,
        "optional": false,
        "output": false
      }
    ]
  },
  "SP_Seguridad_RevocarSesiones": {
    "params": [
      {
        "name": "IdActor",
        "type": "bigint",
        "size": null,
        "scale": null,
        "optional": false,
        "output": false
      },
      {
        "name": "IdSesion",
        "type": "uniqueidentifier",
        "size": null,
        "scale": null,
        "optional": false,
        "output": false
      },
      {
        "name": "Todas",
        "type": "bit",
        "size": null,
        "scale": null,
        "optional": true,
        "output": false
      }
    ]
  },
  "SP_Seguridad_RevocarToken": {
    "params": [
      {
        "name": "IdActor",
        "type": "bigint",
        "size": null,
        "scale": null,
        "optional": false,
        "output": false
      },
      {
        "name": "IdSesion",
        "type": "uniqueidentifier",
        "size": null,
        "scale": null,
        "optional": false,
        "output": false
      },
      {
        "name": "IdToken",
        "type": "bigint",
        "size": null,
        "scale": null,
        "optional": false,
        "output": false
      }
    ]
  },
  "SP_Seguridad_AdministrarUsuario": {
    "params": [
      {
        "name": "IdActor",
        "type": "bigint",
        "size": null,
        "scale": null,
        "optional": false,
        "output": false
      },
      {
        "name": "IdSesion",
        "type": "uniqueidentifier",
        "size": null,
        "scale": null,
        "optional": false,
        "output": false
      },
      {
        "name": "IdUsuario",
        "type": "bigint",
        "size": null,
        "scale": null,
        "optional": false,
        "output": false
      },
      {
        "name": "Rol",
        "type": "nvarchar",
        "size": "max",
        "scale": null,
        "optional": false,
        "output": false
      },
      {
        "name": "EstaActivo",
        "type": "bit",
        "size": null,
        "scale": null,
        "optional": false,
        "output": false
      }
    ]
  },
  "SP_Seguridad_ListarDirecciones": {
    "params": [
      {
        "name": "IdActor",
        "type": "bigint",
        "size": null,
        "scale": null,
        "optional": false,
        "output": false
      },
      {
        "name": "IdSesion",
        "type": "uniqueidentifier",
        "size": null,
        "scale": null,
        "optional": false,
        "output": false
      }
    ]
  },
  "SP_Seguridad_GuardarDireccion": {
    "params": [
      {
        "name": "IdActor",
        "type": "bigint",
        "size": null,
        "scale": null,
        "optional": false,
        "output": false
      },
      {
        "name": "IdSesion",
        "type": "uniqueidentifier",
        "size": null,
        "scale": null,
        "optional": false,
        "output": false
      },
      {
        "name": "Nombre",
        "type": "nvarchar",
        "size": "max",
        "scale": null,
        "optional": false,
        "output": false
      },
      {
        "name": "Telefono",
        "type": "nvarchar",
        "size": "max",
        "scale": null,
        "optional": false,
        "output": false
      },
      {
        "name": "Departamento",
        "type": "nvarchar",
        "size": "max",
        "scale": null,
        "optional": false,
        "output": false
      },
      {
        "name": "Municipio",
        "type": "nvarchar",
        "size": "max",
        "scale": null,
        "optional": false,
        "output": false
      },
      {
        "name": "Linea1",
        "type": "nvarchar",
        "size": "max",
        "scale": null,
        "optional": false,
        "output": false
      },
      {
        "name": "Linea2",
        "type": "nvarchar",
        "size": "max",
        "scale": null,
        "optional": true,
        "output": false
      },
      {
        "name": "Referencias",
        "type": "nvarchar",
        "size": "max",
        "scale": null,
        "optional": true,
        "output": false
      },
      {
        "name": "CodigoPostal",
        "type": "nvarchar",
        "size": "max",
        "scale": null,
        "optional": true,
        "output": false
      },
      {
        "name": "Predeterminada",
        "type": "bit",
        "size": null,
        "scale": null,
        "optional": true,
        "output": false
      },
      {
        "name": "Activa",
        "type": "bit",
        "size": null,
        "scale": null,
        "optional": true,
        "output": false
      },
      {
        "name": "IdDireccion",
        "type": "bigint",
        "size": null,
        "scale": null,
        "optional": true,
        "output": false
      }
    ]
  },
  "SP_Inventario_Consultar": {
    "params": [
      {
        "name": "IdActor",
        "type": "bigint",
        "size": null,
        "scale": null,
        "optional": false,
        "output": false
      },
      {
        "name": "IdSesion",
        "type": "uniqueidentifier",
        "size": null,
        "scale": null,
        "optional": false,
        "output": false
      },
      {
        "name": "IdVariante",
        "type": "bigint",
        "size": null,
        "scale": null,
        "optional": true,
        "output": false
      },
      {
        "name": "Umbral",
        "type": "int",
        "size": null,
        "scale": null,
        "optional": true,
        "output": false
      },
      {
        "name": "Pagina",
        "type": "int",
        "size": null,
        "scale": null,
        "optional": true,
        "output": false
      },
      {
        "name": "TamanoPagina",
        "type": "int",
        "size": null,
        "scale": null,
        "optional": true,
        "output": false
      }
    ]
  },
  "SP_Inventario_RegistrarMovimiento": {
    "params": [
      {
        "name": "IdActor",
        "type": "bigint",
        "size": null,
        "scale": null,
        "optional": false,
        "output": false
      },
      {
        "name": "IdSesion",
        "type": "uniqueidentifier",
        "size": null,
        "scale": null,
        "optional": false,
        "output": false
      },
      {
        "name": "IdVariante",
        "type": "bigint",
        "size": null,
        "scale": null,
        "optional": false,
        "output": false
      },
      {
        "name": "Tipo",
        "type": "varchar",
        "size": "30",
        "scale": null,
        "optional": false,
        "output": false
      },
      {
        "name": "Cantidad",
        "type": "int",
        "size": null,
        "scale": null,
        "optional": false,
        "output": false
      },
      {
        "name": "Motivo",
        "type": "nvarchar",
        "size": "max",
        "scale": null,
        "optional": false,
        "output": false
      },
      {
        "name": "IdOperacion",
        "type": "bigint",
        "size": null,
        "scale": null,
        "optional": false,
        "output": false
      }
    ]
  },
  "SP_Inventario_ListarMovimientos": {
    "params": [
      {
        "name": "IdActor",
        "type": "bigint",
        "size": null,
        "scale": null,
        "optional": false,
        "output": false
      },
      {
        "name": "IdSesion",
        "type": "uniqueidentifier",
        "size": null,
        "scale": null,
        "optional": false,
        "output": false
      },
      {
        "name": "Desde",
        "type": "datetime2",
        "size": "7",
        "scale": null,
        "optional": false,
        "output": false
      },
      {
        "name": "Hasta",
        "type": "datetime2",
        "size": "7",
        "scale": null,
        "optional": false,
        "output": false
      },
      {
        "name": "IdVariante",
        "type": "bigint",
        "size": null,
        "scale": null,
        "optional": true,
        "output": false
      },
      {
        "name": "Pagina",
        "type": "int",
        "size": null,
        "scale": null,
        "optional": true,
        "output": false
      },
      {
        "name": "TamanoPagina",
        "type": "int",
        "size": null,
        "scale": null,
        "optional": true,
        "output": false
      }
    ]
  },
  "SP_Carritos_ObtenerActivo": {
    "params": [
      {
        "name": "IdActor",
        "type": "bigint",
        "size": null,
        "scale": null,
        "optional": true,
        "output": false
      },
      {
        "name": "IdSesion",
        "type": "uniqueidentifier",
        "size": null,
        "scale": null,
        "optional": true,
        "output": false
      },
      {
        "name": "TokenInvitado",
        "type": "varbinary",
        "size": "max",
        "scale": null,
        "optional": true,
        "output": false
      }
    ]
  },
  "SP_Carritos_Consultar": {
    "params": [
      {
        "name": "IdCarrito",
        "type": "bigint",
        "size": null,
        "scale": null,
        "optional": false,
        "output": false
      },
      {
        "name": "IdActor",
        "type": "bigint",
        "size": null,
        "scale": null,
        "optional": true,
        "output": false
      },
      {
        "name": "IdSesion",
        "type": "uniqueidentifier",
        "size": null,
        "scale": null,
        "optional": true,
        "output": false
      },
      {
        "name": "TokenInvitado",
        "type": "varbinary",
        "size": "max",
        "scale": null,
        "optional": true,
        "output": false
      }
    ]
  },
  "SP_Carritos_Modificar": {
    "params": [
      {
        "name": "IdCarrito",
        "type": "bigint",
        "size": null,
        "scale": null,
        "optional": false,
        "output": false
      },
      {
        "name": "Accion",
        "type": "varchar",
        "size": "15",
        "scale": null,
        "optional": false,
        "output": false
      },
      {
        "name": "IdVariante",
        "type": "bigint",
        "size": null,
        "scale": null,
        "optional": true,
        "output": false
      },
      {
        "name": "Cantidad",
        "type": "int",
        "size": null,
        "scale": null,
        "optional": true,
        "output": false
      },
      {
        "name": "IdActor",
        "type": "bigint",
        "size": null,
        "scale": null,
        "optional": true,
        "output": false
      },
      {
        "name": "IdSesion",
        "type": "uniqueidentifier",
        "size": null,
        "scale": null,
        "optional": true,
        "output": false
      },
      {
        "name": "TokenInvitado",
        "type": "varbinary",
        "size": "max",
        "scale": null,
        "optional": true,
        "output": false
      }
    ]
  },
  "SP_Carritos_Fusionar": {
    "params": [
      {
        "name": "IdActor",
        "type": "bigint",
        "size": null,
        "scale": null,
        "optional": false,
        "output": false
      },
      {
        "name": "IdSesion",
        "type": "uniqueidentifier",
        "size": null,
        "scale": null,
        "optional": false,
        "output": false
      },
      {
        "name": "IdCarritoInvitado",
        "type": "bigint",
        "size": null,
        "scale": null,
        "optional": false,
        "output": false
      },
      {
        "name": "TokenInvitado",
        "type": "varbinary",
        "size": "max",
        "scale": null,
        "optional": false,
        "output": false
      }
    ]
  },
  "SP_Cupones_Guardar": {
    "params": [
      {
        "name": "IdActor",
        "type": "bigint",
        "size": null,
        "scale": null,
        "optional": false,
        "output": false
      },
      {
        "name": "IdSesion",
        "type": "uniqueidentifier",
        "size": null,
        "scale": null,
        "optional": false,
        "output": false
      },
      {
        "name": "Codigo",
        "type": "nvarchar",
        "size": "max",
        "scale": null,
        "optional": false,
        "output": false
      },
      {
        "name": "Tipo",
        "type": "varchar",
        "size": "15",
        "scale": null,
        "optional": false,
        "output": false
      },
      {
        "name": "Valor",
        "type": "decimal",
        "size": "19",
        "scale": "4",
        "optional": false,
        "output": false
      },
      {
        "name": "Minimo",
        "type": "decimal",
        "size": "19",
        "scale": "4",
        "optional": false,
        "output": false
      },
      {
        "name": "Inicio",
        "type": "datetime2",
        "size": "7",
        "scale": null,
        "optional": false,
        "output": false
      },
      {
        "name": "Fin",
        "type": "datetime2",
        "size": "7",
        "scale": null,
        "optional": false,
        "output": false
      },
      {
        "name": "IdCategoria",
        "type": "int",
        "size": null,
        "scale": null,
        "optional": true,
        "output": false
      },
      {
        "name": "LimiteTotal",
        "type": "int",
        "size": null,
        "scale": null,
        "optional": true,
        "output": false
      },
      {
        "name": "LimiteUsuario",
        "type": "int",
        "size": null,
        "scale": null,
        "optional": true,
        "output": false
      },
      {
        "name": "Activo",
        "type": "bit",
        "size": null,
        "scale": null,
        "optional": true,
        "output": false
      },
      {
        "name": "Descripcion",
        "type": "nvarchar",
        "size": "max",
        "scale": null,
        "optional": true,
        "output": false
      },
      {
        "name": "IdCupon",
        "type": "bigint",
        "size": null,
        "scale": null,
        "optional": true,
        "output": false
      }
    ]
  },
  "SP_Interno_EvaluarCupon": {
    "params": [
      {
        "name": "IdCupon",
        "type": "bigint",
        "size": null,
        "scale": null,
        "optional": false,
        "output": false
      },
      {
        "name": "IdUsuario",
        "type": "bigint",
        "size": null,
        "scale": null,
        "optional": false,
        "output": false
      },
      {
        "name": "Subtotal",
        "type": "decimal",
        "size": "19",
        "scale": "4",
        "optional": false,
        "output": false
      },
      {
        "name": "Elegible",
        "type": "decimal",
        "size": "19",
        "scale": "4",
        "optional": false,
        "output": false
      },
      {
        "name": "IdCheckout",
        "type": "bigint",
        "size": null,
        "scale": null,
        "optional": false,
        "output": false
      },
      {
        "name": "Descuento",
        "type": "decimal",
        "size": "19",
        "scale": "4",
        "optional": false,
        "output": true
      }
    ]
  },
  "SP_Cupones_ValidarCarrito": {
    "params": [
      {
        "name": "IdCarrito",
        "type": "bigint",
        "size": null,
        "scale": null,
        "optional": false,
        "output": false
      },
      {
        "name": "Codigo",
        "type": "nvarchar",
        "size": "max",
        "scale": null,
        "optional": false,
        "output": false
      },
      {
        "name": "IdActor",
        "type": "bigint",
        "size": null,
        "scale": null,
        "optional": true,
        "output": false
      },
      {
        "name": "IdSesion",
        "type": "uniqueidentifier",
        "size": null,
        "scale": null,
        "optional": true,
        "output": false
      },
      {
        "name": "TokenInvitado",
        "type": "varbinary",
        "size": "max",
        "scale": null,
        "optional": true,
        "output": false
      }
    ]
  },
  "SP_Cupones_ConsultarUsos": {
    "params": [
      {
        "name": "IdActor",
        "type": "bigint",
        "size": null,
        "scale": null,
        "optional": false,
        "output": false
      },
      {
        "name": "IdSesion",
        "type": "uniqueidentifier",
        "size": null,
        "scale": null,
        "optional": false,
        "output": false
      },
      {
        "name": "IdCupon",
        "type": "bigint",
        "size": null,
        "scale": null,
        "optional": false,
        "output": false
      },
      {
        "name": "Pagina",
        "type": "int",
        "size": null,
        "scale": null,
        "optional": true,
        "output": false
      },
      {
        "name": "TamanoPagina",
        "type": "int",
        "size": null,
        "scale": null,
        "optional": true,
        "output": false
      }
    ]
  },
  "SP_Cupones_CambiarEstado": {
    "params": [
      {
        "name": "IdActor",
        "type": "bigint",
        "size": null,
        "scale": null,
        "optional": false,
        "output": false
      },
      {
        "name": "IdSesion",
        "type": "uniqueidentifier",
        "size": null,
        "scale": null,
        "optional": false,
        "output": false
      },
      {
        "name": "IdCupon",
        "type": "bigint",
        "size": null,
        "scale": null,
        "optional": false,
        "output": false
      },
      {
        "name": "Activo",
        "type": "bit",
        "size": null,
        "scale": null,
        "optional": false,
        "output": false
      }
    ]
  },
  "SP_Checkout_Iniciar": {
    "params": [
      {
        "name": "IdCarrito",
        "type": "bigint",
        "size": null,
        "scale": null,
        "optional": false,
        "output": false
      },
      {
        "name": "RevisionCarrito",
        "type": "nvarchar",
        "size": "max",
        "scale": null,
        "optional": false,
        "output": false
      },
      {
        "name": "ClaveIdempotencia",
        "type": "varbinary",
        "size": "max",
        "scale": null,
        "optional": false,
        "output": false
      },
      {
        "name": "IdMetodoEnvio",
        "type": "int",
        "size": null,
        "scale": null,
        "optional": false,
        "output": false
      },
      {
        "name": "NombreDestinatario",
        "type": "nvarchar",
        "size": "max",
        "scale": null,
        "optional": false,
        "output": false
      },
      {
        "name": "Telefono",
        "type": "nvarchar",
        "size": "max",
        "scale": null,
        "optional": false,
        "output": false
      },
      {
        "name": "Departamento",
        "type": "nvarchar",
        "size": "max",
        "scale": null,
        "optional": false,
        "output": false
      },
      {
        "name": "Ciudad",
        "type": "nvarchar",
        "size": "max",
        "scale": null,
        "optional": false,
        "output": false
      },
      {
        "name": "Direccion1",
        "type": "nvarchar",
        "size": "max",
        "scale": null,
        "optional": false,
        "output": false
      },
      {
        "name": "Direccion2",
        "type": "nvarchar",
        "size": "max",
        "scale": null,
        "optional": true,
        "output": false
      },
      {
        "name": "CodigoPostal",
        "type": "nvarchar",
        "size": "max",
        "scale": null,
        "optional": true,
        "output": false
      },
      {
        "name": "IdDireccion",
        "type": "bigint",
        "size": null,
        "scale": null,
        "optional": true,
        "output": false
      },
      {
        "name": "CodigoCupon",
        "type": "nvarchar",
        "size": "max",
        "scale": null,
        "optional": true,
        "output": false
      },
      {
        "name": "IdActor",
        "type": "bigint",
        "size": null,
        "scale": null,
        "optional": true,
        "output": false
      },
      {
        "name": "IdSesion",
        "type": "uniqueidentifier",
        "size": null,
        "scale": null,
        "optional": true,
        "output": false
      },
      {
        "name": "TokenInvitado",
        "type": "varbinary",
        "size": "max",
        "scale": null,
        "optional": true,
        "output": false
      }
    ]
  },
  "SP_Checkout_Consultar": {
    "params": [
      {
        "name": "IdCheckout",
        "type": "bigint",
        "size": null,
        "scale": null,
        "optional": false,
        "output": false
      },
      {
        "name": "IdActor",
        "type": "bigint",
        "size": null,
        "scale": null,
        "optional": true,
        "output": false
      },
      {
        "name": "IdSesion",
        "type": "uniqueidentifier",
        "size": null,
        "scale": null,
        "optional": true,
        "output": false
      },
      {
        "name": "TokenInvitado",
        "type": "varbinary",
        "size": "max",
        "scale": null,
        "optional": true,
        "output": false
      }
    ]
  },
  "SP_Checkout_Cancelar": {
    "params": [
      {
        "name": "IdCheckout",
        "type": "bigint",
        "size": null,
        "scale": null,
        "optional": false,
        "output": false
      },
      {
        "name": "IdActor",
        "type": "bigint",
        "size": null,
        "scale": null,
        "optional": true,
        "output": false
      },
      {
        "name": "IdSesion",
        "type": "uniqueidentifier",
        "size": null,
        "scale": null,
        "optional": true,
        "output": false
      },
      {
        "name": "TokenInvitado",
        "type": "varbinary",
        "size": "max",
        "scale": null,
        "optional": true,
        "output": false
      }
    ]
  },
  "SP_Checkout_Expirar": {
    "params": [
      {
        "name": "IdActor",
        "type": "bigint",
        "size": null,
        "scale": null,
        "optional": false,
        "output": false
      },
      {
        "name": "IdSesion",
        "type": "uniqueidentifier",
        "size": null,
        "scale": null,
        "optional": false,
        "output": false
      },
      {
        "name": "Limite",
        "type": "int",
        "size": null,
        "scale": null,
        "optional": true,
        "output": false
      }
    ]
  },
  "SP_Checkout_ListarMetodosEnvio": {
    "params": []
  },
  "SP_Pedidos_ProcesarPago": {
    "params": [
      {
        "name": "IdPedido",
        "type": "bigint",
        "size": null,
        "scale": null,
        "optional": false,
        "output": false
      },
      {
        "name": "ClaveOperacion",
        "type": "varbinary",
        "size": "max",
        "scale": null,
        "optional": false,
        "output": false
      },
      {
        "name": "Referencia",
        "type": "varchar",
        "size": "max",
        "scale": null,
        "optional": false,
        "output": false
      },
      {
        "name": "Monto",
        "type": "decimal",
        "size": "19",
        "scale": "4",
        "optional": false,
        "output": false
      },
      {
        "name": "Accion",
        "type": "varchar",
        "size": "10",
        "scale": null,
        "optional": false,
        "output": false
      },
      {
        "name": "IdActor",
        "type": "bigint",
        "size": null,
        "scale": null,
        "optional": true,
        "output": false
      },
      {
        "name": "IdSesion",
        "type": "uniqueidentifier",
        "size": null,
        "scale": null,
        "optional": true,
        "output": false
      },
      {
        "name": "TokenInvitado",
        "type": "varbinary",
        "size": "max",
        "scale": null,
        "optional": true,
        "output": false
      }
    ]
  },
  "SP_Pedidos_Consultar": {
    "params": [
      {
        "name": "IdPedido",
        "type": "bigint",
        "size": null,
        "scale": null,
        "optional": true,
        "output": false
      },
      {
        "name": "IdActor",
        "type": "bigint",
        "size": null,
        "scale": null,
        "optional": true,
        "output": false
      },
      {
        "name": "IdSesion",
        "type": "uniqueidentifier",
        "size": null,
        "scale": null,
        "optional": true,
        "output": false
      },
      {
        "name": "TokenInvitado",
        "type": "varbinary",
        "size": "max",
        "scale": null,
        "optional": true,
        "output": false
      },
      {
        "name": "NumeroPedido",
        "type": "varchar",
        "size": "max",
        "scale": null,
        "optional": true,
        "output": false
      }
    ]
  },
  "SP_Pedidos_Listar": {
    "params": [
      {
        "name": "IdActor",
        "type": "bigint",
        "size": null,
        "scale": null,
        "optional": false,
        "output": false
      },
      {
        "name": "IdSesion",
        "type": "uniqueidentifier",
        "size": null,
        "scale": null,
        "optional": false,
        "output": false
      },
      {
        "name": "Administrativo",
        "type": "bit",
        "size": null,
        "scale": null,
        "optional": true,
        "output": false
      },
      {
        "name": "IdUsuario",
        "type": "bigint",
        "size": null,
        "scale": null,
        "optional": true,
        "output": false
      },
      {
        "name": "Estado",
        "type": "varchar",
        "size": "25",
        "scale": null,
        "optional": true,
        "output": false
      },
      {
        "name": "Desde",
        "type": "datetime2",
        "size": "7",
        "scale": null,
        "optional": true,
        "output": false
      },
      {
        "name": "Hasta",
        "type": "datetime2",
        "size": "7",
        "scale": null,
        "optional": true,
        "output": false
      },
      {
        "name": "Pagina",
        "type": "int",
        "size": null,
        "scale": null,
        "optional": true,
        "output": false
      },
      {
        "name": "TamanoPagina",
        "type": "int",
        "size": null,
        "scale": null,
        "optional": true,
        "output": false
      }
    ]
  },
  "SP_Pedidos_CambiarEstado": {
    "params": [
      {
        "name": "IdActor",
        "type": "bigint",
        "size": null,
        "scale": null,
        "optional": false,
        "output": false
      },
      {
        "name": "IdSesion",
        "type": "uniqueidentifier",
        "size": null,
        "scale": null,
        "optional": false,
        "output": false
      },
      {
        "name": "IdPedido",
        "type": "bigint",
        "size": null,
        "scale": null,
        "optional": false,
        "output": false
      },
      {
        "name": "EstadoNuevo",
        "type": "varchar",
        "size": "25",
        "scale": null,
        "optional": false,
        "output": false
      },
      {
        "name": "Observacion",
        "type": "nvarchar",
        "size": "max",
        "scale": null,
        "optional": true,
        "output": false
      }
    ]
  },
  "SP_Devoluciones_Solicitar": {
    "params": [
      {
        "name": "IdPedido",
        "type": "bigint",
        "size": null,
        "scale": null,
        "optional": false,
        "output": false
      },
      {
        "name": "Lineas",
        "type": "nvarchar",
        "size": "max",
        "scale": null,
        "optional": false,
        "output": false
      },
      {
        "name": "Motivo",
        "type": "nvarchar",
        "size": "max",
        "scale": null,
        "optional": false,
        "output": false
      },
      {
        "name": "IdOperacion",
        "type": "uniqueidentifier",
        "size": null,
        "scale": null,
        "optional": false,
        "output": false
      },
      {
        "name": "IdDevolucion",
        "type": "bigint",
        "size": null,
        "scale": null,
        "optional": true,
        "output": false
      },
      {
        "name": "IdActor",
        "type": "bigint",
        "size": null,
        "scale": null,
        "optional": true,
        "output": false
      },
      {
        "name": "IdSesion",
        "type": "uniqueidentifier",
        "size": null,
        "scale": null,
        "optional": true,
        "output": false
      },
      {
        "name": "TokenInvitado",
        "type": "varbinary",
        "size": "max",
        "scale": null,
        "optional": true,
        "output": false
      }
    ]
  },
  "SP_Devoluciones_CambiarEstado": {
    "params": [
      {
        "name": "IdDevolucion",
        "type": "bigint",
        "size": null,
        "scale": null,
        "optional": false,
        "output": false
      },
      {
        "name": "EstadoNuevo",
        "type": "varchar",
        "size": "25",
        "scale": null,
        "optional": false,
        "output": false
      },
      {
        "name": "Observacion",
        "type": "nvarchar",
        "size": "max",
        "scale": null,
        "optional": true,
        "output": false
      },
      {
        "name": "IdActor",
        "type": "bigint",
        "size": null,
        "scale": null,
        "optional": true,
        "output": false
      },
      {
        "name": "IdSesion",
        "type": "uniqueidentifier",
        "size": null,
        "scale": null,
        "optional": true,
        "output": false
      },
      {
        "name": "TokenInvitado",
        "type": "varbinary",
        "size": "max",
        "scale": null,
        "optional": true,
        "output": false
      }
    ]
  },
  "SP_Devoluciones_Completar": {
    "params": [
      {
        "name": "IdActor",
        "type": "bigint",
        "size": null,
        "scale": null,
        "optional": false,
        "output": false
      },
      {
        "name": "IdSesion",
        "type": "uniqueidentifier",
        "size": null,
        "scale": null,
        "optional": false,
        "output": false
      },
      {
        "name": "IdDevolucion",
        "type": "bigint",
        "size": null,
        "scale": null,
        "optional": false,
        "output": false
      },
      {
        "name": "ClaveReembolso",
        "type": "varbinary",
        "size": "max",
        "scale": null,
        "optional": true,
        "output": false
      },
      {
        "name": "Referencia",
        "type": "varchar",
        "size": "max",
        "scale": null,
        "optional": true,
        "output": false
      }
    ]
  },
  "SP_Devoluciones_ProcesarReembolso": {
    "params": [
      {
        "name": "IdActor",
        "type": "bigint",
        "size": null,
        "scale": null,
        "optional": false,
        "output": false
      },
      {
        "name": "IdSesion",
        "type": "uniqueidentifier",
        "size": null,
        "scale": null,
        "optional": false,
        "output": false
      },
      {
        "name": "IdDevolucion",
        "type": "bigint",
        "size": null,
        "scale": null,
        "optional": false,
        "output": false
      },
      {
        "name": "ClaveOperacion",
        "type": "varbinary",
        "size": "max",
        "scale": null,
        "optional": false,
        "output": false
      },
      {
        "name": "Referencia",
        "type": "varchar",
        "size": "max",
        "scale": null,
        "optional": false,
        "output": false
      },
      {
        "name": "Accion",
        "type": "varchar",
        "size": "10",
        "scale": null,
        "optional": false,
        "output": false
      }
    ]
  },
  "SP_Pedidos_Cancelar": {
    "params": [
      {
        "name": "IdPedido",
        "type": "bigint",
        "size": null,
        "scale": null,
        "optional": false,
        "output": false
      },
      {
        "name": "ClaveReembolso",
        "type": "varbinary",
        "size": "max",
        "scale": null,
        "optional": true,
        "output": false
      },
      {
        "name": "Referencia",
        "type": "varchar",
        "size": "max",
        "scale": null,
        "optional": true,
        "output": false
      },
      {
        "name": "IdActor",
        "type": "bigint",
        "size": null,
        "scale": null,
        "optional": true,
        "output": false
      },
      {
        "name": "IdSesion",
        "type": "uniqueidentifier",
        "size": null,
        "scale": null,
        "optional": true,
        "output": false
      },
      {
        "name": "TokenInvitado",
        "type": "varbinary",
        "size": "max",
        "scale": null,
        "optional": true,
        "output": false
      }
    ]
  },
  "SP_Devoluciones_Consultar": {
    "params": [
      {
        "name": "IdPedido",
        "type": "bigint",
        "size": null,
        "scale": null,
        "optional": false,
        "output": false
      },
      {
        "name": "IdActor",
        "type": "bigint",
        "size": null,
        "scale": null,
        "optional": true,
        "output": false
      },
      {
        "name": "IdSesion",
        "type": "uniqueidentifier",
        "size": null,
        "scale": null,
        "optional": true,
        "output": false
      },
      {
        "name": "TokenInvitado",
        "type": "varbinary",
        "size": "max",
        "scale": null,
        "optional": true,
        "output": false
      }
    ]
  },
  "SP_Devoluciones_Listar": {
    "params": [
      {
        "name": "IdActor",
        "type": "bigint",
        "size": null,
        "scale": null,
        "optional": false,
        "output": false
      },
      {
        "name": "IdSesion",
        "type": "uniqueidentifier",
        "size": null,
        "scale": null,
        "optional": false,
        "output": false
      },
      {
        "name": "Estado",
        "type": "varchar",
        "size": "25",
        "scale": null,
        "optional": true,
        "output": false
      },
      {
        "name": "Pagina",
        "type": "int",
        "size": null,
        "scale": null,
        "optional": true,
        "output": false
      },
      {
        "name": "TamanoPagina",
        "type": "int",
        "size": null,
        "scale": null,
        "optional": true,
        "output": false
      }
    ]
  },
  "SP_Reportes_Ventas": {
    "params": [
      {
        "name": "IdActor",
        "type": "bigint",
        "size": null,
        "scale": null,
        "optional": false,
        "output": false
      },
      {
        "name": "IdSesion",
        "type": "uniqueidentifier",
        "size": null,
        "scale": null,
        "optional": false,
        "output": false
      },
      {
        "name": "Desde",
        "type": "datetime2",
        "size": "7",
        "scale": null,
        "optional": false,
        "output": false
      },
      {
        "name": "Hasta",
        "type": "datetime2",
        "size": "7",
        "scale": null,
        "optional": false,
        "output": false
      },
      {
        "name": "Dimension",
        "type": "varchar",
        "size": "15",
        "scale": null,
        "optional": true,
        "output": false
      },
      {
        "name": "Pagina",
        "type": "int",
        "size": null,
        "scale": null,
        "optional": true,
        "output": false
      },
      {
        "name": "TamanoPagina",
        "type": "int",
        "size": null,
        "scale": null,
        "optional": true,
        "output": false
      },
      {
        "name": "Top",
        "type": "int",
        "size": null,
        "scale": null,
        "optional": true,
        "output": false
      }
    ]
  },
  "SP_Reportes_Finanzas": {
    "params": [
      {
        "name": "IdActor",
        "type": "bigint",
        "size": null,
        "scale": null,
        "optional": false,
        "output": false
      },
      {
        "name": "IdSesion",
        "type": "uniqueidentifier",
        "size": null,
        "scale": null,
        "optional": false,
        "output": false
      },
      {
        "name": "Desde",
        "type": "datetime2",
        "size": "7",
        "scale": null,
        "optional": false,
        "output": false
      },
      {
        "name": "Hasta",
        "type": "datetime2",
        "size": "7",
        "scale": null,
        "optional": false,
        "output": false
      }
    ]
  },
  "SP_Reportes_Operacion": {
    "params": [
      {
        "name": "IdActor",
        "type": "bigint",
        "size": null,
        "scale": null,
        "optional": false,
        "output": false
      },
      {
        "name": "IdSesion",
        "type": "uniqueidentifier",
        "size": null,
        "scale": null,
        "optional": false,
        "output": false
      },
      {
        "name": "Modulo",
        "type": "varchar",
        "size": "20",
        "scale": null,
        "optional": false,
        "output": false
      },
      {
        "name": "Desde",
        "type": "datetime2",
        "size": "7",
        "scale": null,
        "optional": false,
        "output": false
      },
      {
        "name": "Hasta",
        "type": "datetime2",
        "size": "7",
        "scale": null,
        "optional": false,
        "output": false
      },
      {
        "name": "Pagina",
        "type": "int",
        "size": null,
        "scale": null,
        "optional": true,
        "output": false
      },
      {
        "name": "TamanoPagina",
        "type": "int",
        "size": null,
        "scale": null,
        "optional": true,
        "output": false
      }
    ]
  },
  "SP_Auditoria_Consultar": {
    "params": [
      {
        "name": "IdActor",
        "type": "bigint",
        "size": null,
        "scale": null,
        "optional": false,
        "output": false
      },
      {
        "name": "IdSesion",
        "type": "uniqueidentifier",
        "size": null,
        "scale": null,
        "optional": false,
        "output": false
      },
      {
        "name": "Desde",
        "type": "datetime2",
        "size": "7",
        "scale": null,
        "optional": false,
        "output": false
      },
      {
        "name": "Hasta",
        "type": "datetime2",
        "size": "7",
        "scale": null,
        "optional": false,
        "output": false
      },
      {
        "name": "IdUsuario",
        "type": "bigint",
        "size": null,
        "scale": null,
        "optional": true,
        "output": false
      },
      {
        "name": "Entidad",
        "type": "varchar",
        "size": "max",
        "scale": null,
        "optional": true,
        "output": false
      },
      {
        "name": "IdCorrelacion",
        "type": "uniqueidentifier",
        "size": null,
        "scale": null,
        "optional": true,
        "output": false
      },
      {
        "name": "Modulo",
        "type": "varchar",
        "size": "20",
        "scale": null,
        "optional": true,
        "output": false
      },
      {
        "name": "Pagina",
        "type": "int",
        "size": null,
        "scale": null,
        "optional": true,
        "output": false
      },
      {
        "name": "TamanoPagina",
        "type": "int",
        "size": null,
        "scale": null,
        "optional": true,
        "output": false
      }
    ]
  }
} as const;
export type ProcedureName=keyof typeof procedures;
export type SqlInput=string|number|boolean|Buffer|Date|null;
export interface ProcedureParameters {
 'SP_Interno_Autorizar': {
  IdActor: string|null;
  IdSesion: string|null;
  Ambito: string|null;
 };
 'SP_Catalogo_ListarCategorias': {
 };
 'SP_Catalogo_ListarProductos': {
  Texto?: string|null;
  IdCategoria?: number|null;
  PrecioMin?: string|null;
  PrecioMax?: string|null;
  SoloDisponibles?: boolean|null;
  Orden?: string|null;
  Pagina?: number|null;
  TamanoPagina?: number|null;
 };
 'SP_Catalogo_ObtenerProducto': {
  IdProducto: string|null;
 };
 'SP_Catalogo_GuardarCategoria': {
  IdActor: string|null;
  IdSesion: string|null;
  Nombre: string|null;
  Descripcion?: string|null;
  EstaActiva?: boolean|null;
  IdCategoria?: number|null;
 };
 'SP_Catalogo_GuardarProducto': {
  IdActor: string|null;
  IdSesion: string|null;
  IdCategoria: number|null;
  Nombre: string|null;
  Descripcion?: string|null;
  EstaActivo?: boolean|null;
  IdProducto?: string|null;
 };
 'SP_Catalogo_GuardarVariante': {
  IdActor: string|null;
  IdSesion: string|null;
  IdProducto: string|null;
  SKU: string|null;
  Precio: string|null;
  Talla?: string|null;
  Color?: string|null;
  EstaActiva?: boolean|null;
  IdVariante?: string|null;
 };
 'SP_Catalogo_GuardarImagen': {
  IdActor: string|null;
  IdSesion: string|null;
  IdProducto: string|null;
  Ruta: string|null;
  TextoAlternativo?: string|null;
  Orden?: number|null;
  EsPrincipal?: boolean|null;
  EstaActiva?: boolean|null;
  IdImagen?: string|null;
 };
 'SP_Seguridad_RegistrarUsuario': {
  Nombre: string|null;
  Apellido: string|null;
  Correo: string|null;
  HashContrasena: string|null;
 };
 'SP_Seguridad_ObtenerAutenticacion': {
  Correo: string|null;
 };
 'SP_Seguridad_ConsultarPerfil': {
  IdActor: string|null;
  IdSesion: string|null;
 };
 'SP_Seguridad_ActualizarPerfil': {
  IdActor: string|null;
  IdSesion: string|null;
  Nombre: string|null;
  Apellido: string|null;
 };
 'SP_Seguridad_CrearSesion': {
  IdUsuario: string|null;
  HashToken: Buffer|null;
  FechaExpiracionUTC: Date|null;
  DireccionIP?: string|null;
  Agente?: string|null;
 };
 'SP_Seguridad_ConsultarSesion': {
  IdActor: string|null;
  IdSesion: string|null;
 };
 'SP_Seguridad_RotarToken': {
  HashAnterior: Buffer|null;
  HashNuevo: Buffer|null;
  NuevaExpiracionUTC: Date|null;
 };
 'SP_Seguridad_RevocarSesiones': {
  IdActor: string|null;
  IdSesion: string|null;
  Todas?: boolean|null;
 };
 'SP_Seguridad_RevocarToken': {
  IdActor: string|null;
  IdSesion: string|null;
  IdToken: string|null;
 };
 'SP_Seguridad_AdministrarUsuario': {
  IdActor: string|null;
  IdSesion: string|null;
  IdUsuario: string|null;
  Rol: string|null;
  EstaActivo: boolean|null;
 };
 'SP_Seguridad_ListarDirecciones': {
  IdActor: string|null;
  IdSesion: string|null;
 };
 'SP_Seguridad_GuardarDireccion': {
  IdActor: string|null;
  IdSesion: string|null;
  Nombre: string|null;
  Telefono: string|null;
  Departamento: string|null;
  Municipio: string|null;
  Linea1: string|null;
  Linea2?: string|null;
  Referencias?: string|null;
  CodigoPostal?: string|null;
  Predeterminada?: boolean|null;
  Activa?: boolean|null;
  IdDireccion?: string|null;
 };
 'SP_Inventario_Consultar': {
  IdActor: string|null;
  IdSesion: string|null;
  IdVariante?: string|null;
  Umbral?: number|null;
  Pagina?: number|null;
  TamanoPagina?: number|null;
 };
 'SP_Inventario_RegistrarMovimiento': {
  IdActor: string|null;
  IdSesion: string|null;
  IdVariante: string|null;
  Tipo: string|null;
  Cantidad: number|null;
  Motivo: string|null;
  IdOperacion: string|null;
 };
 'SP_Inventario_ListarMovimientos': {
  IdActor: string|null;
  IdSesion: string|null;
  Desde: Date|null;
  Hasta: Date|null;
  IdVariante?: string|null;
  Pagina?: number|null;
  TamanoPagina?: number|null;
 };
 'SP_Carritos_ObtenerActivo': {
  IdActor?: string|null;
  IdSesion?: string|null;
  TokenInvitado?: Buffer|null;
 };
 'SP_Carritos_Consultar': {
  IdCarrito: string|null;
  IdActor?: string|null;
  IdSesion?: string|null;
  TokenInvitado?: Buffer|null;
 };
 'SP_Carritos_Modificar': {
  IdCarrito: string|null;
  Accion: string|null;
  IdVariante?: string|null;
  Cantidad?: number|null;
  IdActor?: string|null;
  IdSesion?: string|null;
  TokenInvitado?: Buffer|null;
 };
 'SP_Carritos_Fusionar': {
  IdActor: string|null;
  IdSesion: string|null;
  IdCarritoInvitado: string|null;
  TokenInvitado: Buffer|null;
 };
 'SP_Cupones_Guardar': {
  IdActor: string|null;
  IdSesion: string|null;
  Codigo: string|null;
  Tipo: string|null;
  Valor: string|null;
  Minimo: string|null;
  Inicio: Date|null;
  Fin: Date|null;
  IdCategoria?: number|null;
  LimiteTotal?: number|null;
  LimiteUsuario?: number|null;
  Activo?: boolean|null;
  Descripcion?: string|null;
  IdCupon?: string|null;
 };
 'SP_Interno_EvaluarCupon': {
  IdCupon: string|null;
  IdUsuario: string|null;
  Subtotal: string|null;
  Elegible: string|null;
  IdCheckout: string|null;
 };
 'SP_Cupones_ValidarCarrito': {
  IdCarrito: string|null;
  Codigo: string|null;
  IdActor?: string|null;
  IdSesion?: string|null;
  TokenInvitado?: Buffer|null;
 };
 'SP_Cupones_ConsultarUsos': {
  IdActor: string|null;
  IdSesion: string|null;
  IdCupon: string|null;
  Pagina?: number|null;
  TamanoPagina?: number|null;
 };
 'SP_Cupones_CambiarEstado': {
  IdActor: string|null;
  IdSesion: string|null;
  IdCupon: string|null;
  Activo: boolean|null;
 };
 'SP_Checkout_Iniciar': {
  IdCarrito: string|null;
  RevisionCarrito: string|null;
  ClaveIdempotencia: Buffer|null;
  IdMetodoEnvio: number|null;
  NombreDestinatario: string|null;
  Telefono: string|null;
  Departamento: string|null;
  Ciudad: string|null;
  Direccion1: string|null;
  Direccion2?: string|null;
  CodigoPostal?: string|null;
  IdDireccion?: string|null;
  CodigoCupon?: string|null;
  IdActor?: string|null;
  IdSesion?: string|null;
  TokenInvitado?: Buffer|null;
 };
 'SP_Checkout_Consultar': {
  IdCheckout: string|null;
  IdActor?: string|null;
  IdSesion?: string|null;
  TokenInvitado?: Buffer|null;
 };
 'SP_Checkout_Cancelar': {
  IdCheckout: string|null;
  IdActor?: string|null;
  IdSesion?: string|null;
  TokenInvitado?: Buffer|null;
 };
 'SP_Checkout_Expirar': {
  IdActor: string|null;
  IdSesion: string|null;
  Limite?: number|null;
 };
 'SP_Checkout_ListarMetodosEnvio': {
 };
 'SP_Pedidos_ProcesarPago': {
  IdPedido: string|null;
  ClaveOperacion: Buffer|null;
  Referencia: string|null;
  Monto: string|null;
  Accion: string|null;
  IdActor?: string|null;
  IdSesion?: string|null;
  TokenInvitado?: Buffer|null;
 };
 'SP_Pedidos_Consultar': {
  IdPedido?: string|null;
  IdActor?: string|null;
  IdSesion?: string|null;
  TokenInvitado?: Buffer|null;
  NumeroPedido?: string|null;
 };
 'SP_Pedidos_Listar': {
  IdActor: string|null;
  IdSesion: string|null;
  Administrativo?: boolean|null;
  IdUsuario?: string|null;
  Estado?: string|null;
  Desde?: Date|null;
  Hasta?: Date|null;
  Pagina?: number|null;
  TamanoPagina?: number|null;
 };
 'SP_Pedidos_CambiarEstado': {
  IdActor: string|null;
  IdSesion: string|null;
  IdPedido: string|null;
  EstadoNuevo: string|null;
  Observacion?: string|null;
 };
 'SP_Devoluciones_Solicitar': {
  IdPedido: string|null;
  Lineas: string|null;
  Motivo: string|null;
  IdOperacion: string|null;
  IdDevolucion?: string|null;
  IdActor?: string|null;
  IdSesion?: string|null;
  TokenInvitado?: Buffer|null;
 };
 'SP_Devoluciones_CambiarEstado': {
  IdDevolucion: string|null;
  EstadoNuevo: string|null;
  Observacion?: string|null;
  IdActor?: string|null;
  IdSesion?: string|null;
  TokenInvitado?: Buffer|null;
 };
 'SP_Devoluciones_Completar': {
  IdActor: string|null;
  IdSesion: string|null;
  IdDevolucion: string|null;
  ClaveReembolso?: Buffer|null;
  Referencia?: string|null;
 };
 'SP_Devoluciones_ProcesarReembolso': {
  IdActor: string|null;
  IdSesion: string|null;
  IdDevolucion: string|null;
  ClaveOperacion: Buffer|null;
  Referencia: string|null;
  Accion: string|null;
 };
 'SP_Pedidos_Cancelar': {
  IdPedido: string|null;
  ClaveReembolso?: Buffer|null;
  Referencia?: string|null;
  IdActor?: string|null;
  IdSesion?: string|null;
  TokenInvitado?: Buffer|null;
 };
 'SP_Devoluciones_Consultar': {
  IdPedido: string|null;
  IdActor?: string|null;
  IdSesion?: string|null;
  TokenInvitado?: Buffer|null;
 };
 'SP_Devoluciones_Listar': {
  IdActor: string|null;
  IdSesion: string|null;
  Estado?: string|null;
  Pagina?: number|null;
  TamanoPagina?: number|null;
 };
 'SP_Reportes_Ventas': {
  IdActor: string|null;
  IdSesion: string|null;
  Desde: Date|null;
  Hasta: Date|null;
  Dimension?: string|null;
  Pagina?: number|null;
  TamanoPagina?: number|null;
  Top?: number|null;
 };
 'SP_Reportes_Finanzas': {
  IdActor: string|null;
  IdSesion: string|null;
  Desde: Date|null;
  Hasta: Date|null;
 };
 'SP_Reportes_Operacion': {
  IdActor: string|null;
  IdSesion: string|null;
  Modulo: string|null;
  Desde: Date|null;
  Hasta: Date|null;
  Pagina?: number|null;
  TamanoPagina?: number|null;
 };
 'SP_Auditoria_Consultar': {
  IdActor: string|null;
  IdSesion: string|null;
  Desde: Date|null;
  Hasta: Date|null;
  IdUsuario?: string|null;
  Entidad?: string|null;
  IdCorrelacion?: string|null;
  Modulo?: string|null;
  Pagina?: number|null;
  TamanoPagina?: number|null;
 };
}

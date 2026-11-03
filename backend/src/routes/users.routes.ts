import { z } from 'zod';
import { operationRouter,bind,constant } from './operationRouter.js';
import * as s from '../schemas/common.js';
import type { Operation } from '../types/operation.js';

export const usersOperations = [
{method:"get",path:"/me",procedure:"SP_Seguridad_ConsultarPerfil",access:"user",sets:["profile","roles"],single:["profile"],bindings:{}},
{method:"patch",path:"/me",procedure:"SP_Seguridad_ActualizarPerfil",access:"user",sets:[],single:[],bindings:{Nombre:bind("firstName",s.text(100)),Apellido:bind("lastName",s.text(100))}},
{method:"get",path:"/me/session",procedure:"SP_Seguridad_ConsultarSesion",access:"user",sets:["session"],single:["session"],bindings:{}},
{method:"post",path:"/me/tokens/:id/revoke",procedure:"SP_Seguridad_RevocarToken",access:"user",sets:[],single:[],bindings:{IdToken:bind("id",s.id)}},
{method:"get",path:"/me/addresses",procedure:"SP_Seguridad_ListarDirecciones",access:"user",sets:["addresses"],single:[],bindings:{}},
{method:"post",path:"/me/addresses",procedure:"SP_Seguridad_GuardarDireccion",access:"user",sets:["address"],single:["address"],status:201,bindings:{IdDireccion:constant(null),Nombre:bind("recipientName",s.text(150)),Telefono:bind("phone",s.text(25)),Departamento:bind("department",s.text(100)),Municipio:bind("city",s.text(100)),Linea1:bind("address1",s.text(250)),Linea2:bind("address2",s.optionalText(250)),Referencias:bind("references",s.optionalText(500)),CodigoPostal:bind("postalCode",s.optionalText(15)),Predeterminada:bind("primary",s.bool.default(false)),Activa:bind("active",s.bool.default(true))}},
{method:"patch",path:"/me/addresses/:id",procedure:"SP_Seguridad_GuardarDireccion",access:"user",sets:["address"],single:["address"],status:200,bindings:{IdDireccion:bind("id",s.id),Nombre:bind("recipientName",s.text(150)),Telefono:bind("phone",s.text(25)),Departamento:bind("department",s.text(100)),Municipio:bind("city",s.text(100)),Linea1:bind("address1",s.text(250)),Linea2:bind("address2",s.optionalText(250)),Referencias:bind("references",s.optionalText(500)),CodigoPostal:bind("postalCode",s.optionalText(15)),Predeterminada:bind("primary",s.bool.default(false)),Activa:bind("active",s.bool.default(true))}},
{method:"patch",path:"/:id/access",procedure:"SP_Seguridad_AdministrarUsuario",access:"admin",sets:[],single:[],bindings:{IdUsuario:bind("id",s.id),Rol:bind("role",z.enum(['Cliente','Operador','Administrador'])),EstaActivo:bind("active",s.bool)}}
] satisfies readonly Operation[];
export const usersRoutes=operationRouter(usersOperations);

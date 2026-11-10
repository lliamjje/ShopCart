import {Context} from './context.js';
import {check} from './client.js';
import {expectedAdminId} from './config.js';
import {object} from '../support/values.js';

// Sin escenarios, registro, refresh, logout ni operaciones comerciales.
export async function preflight(c:Context,email:string,password:string):Promise<void>{
  await c.admin.init();
  await c.admin.login(email,password,'Administrador');
  const profile=object((await c.admin.call('GET','/users/me')).profile);
  check(String(profile.IdUsuario)===expectedAdminId&&profile.Rol==='Administrador'&&profile.CorreoElectronico===email,
    'El perfil no corresponde al Administrador ID 3 autenticado.');
}

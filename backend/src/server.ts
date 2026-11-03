import { createApp } from './app.js';
import { env } from './config/env.js';
import { closePool } from './config/database.js';
const server=createApp().listen(env.PORT,env.HOST,()=>{console.info('ShopCart HTTP iniciado en el puerto '+env.PORT);});
server.on('error',()=>{console.error('No se pudo iniciar el servidor HTTP.');process.exitCode=1;});
let closing=false;
function stop(){if(closing)return;closing=true;
 const timeout=setTimeout(()=>{process.exitCode=1;server.closeAllConnections();void closePool();},10000);timeout.unref();
 server.close(()=>{void closePool().catch(()=>{process.exitCode=1;}).finally(()=>clearTimeout(timeout));});
}
process.on('SIGINT',stop);process.on('SIGTERM',stop);

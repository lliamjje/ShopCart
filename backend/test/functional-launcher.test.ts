import {test} from 'node:test';
import assert from 'node:assert/strict';
import {spawnSync} from 'node:child_process';
import {fileURLToPath} from 'node:url';
import {parseConfig,ConfigFailure} from './functional/config.js';
import {Context} from './functional/context.js';
import {preflight} from './functional/preflight.js';
import {auth,sessions} from './functional/modules/auth.js';

const backend=fileURLToPath(new URL('../',import.meta.url));
const launcher=fileURLToPath(new URL('./functional/run.ps1',import.meta.url));
const windows=process.platform==='win32';

test('preflight: solo CSRF, login y perfil; no continúa tras un fallo',async()=>{
  const original=globalThis.fetch;
  const calls:string[]=[];
  const csrf='a'.repeat(43);
  let fail=false;
  globalThis.fetch=async(url,options)=>{
    const path=String(url).replace('http://127.0.0.1:3000/api/v1','');
    calls.push(`${options?.method} ${path}`);
    const profile={IdUsuario:'3',Rol:'Administrador',CorreoElectronico:'admin@example.invalid'};
    if(path==='/auth/csrf')return Response.json({success:true,data:{csrfToken:csrf}},{headers:{'Set-Cookie':`sc_csrf=${csrf}; Path=/`}});
    if(path==='/auth/login'){
      if(fail)return Response.json({success:false,error:{code:'INVALID_CREDENTIALS'}},{status:401});
      return Response.json({success:true,data:{profile,accessToken:'fake.jwt.value',cartMerge:null}},{headers:{'Set-Cookie':'sc_refresh=fake; Path=/'}});
    }
    assert.equal(options?.headers&& (options.headers as Record<string,string>).Authorization,'Bearer fake.jwt.value');
    assert.equal(path,'/users/me');return Response.json({success:true,data:{profile}});
  };
  const c=new Context(()=>{});
  try{
    await preflight(c,'admin@example.invalid','FAKE_SECRET');
    assert.deepEqual(calls,['GET /auth/csrf','POST /auth/login','GET /users/me']);
    const token=c.admin.token;
    await auth[0]!.run(c);
    assert.equal(c.admin.token,token);
    assert.deepEqual(calls,['GET /auth/csrf','POST /auth/login','GET /users/me','GET /users/me']);
    assert.equal(c.authBudget.used,1);
    calls.length=0;fail=true;c.clear();
    await assert.rejects(preflight(c,'admin@example.invalid','FAKE_SECRET'),/401/);
    assert.deepEqual(calls,['GET /auth/csrf','POST /auth/login']);
  }finally{globalThis.fetch=original;c.clear();}
});

test('logout de Clientes y Operador no cierra la sesión administrativa',async()=>{
  const c=new Context(()=>{});
  const calls:string[]=[];
  for(const label of ['b','operator']){
    const client=c.client(true);c.users[label]=client;
    client.call=async(method,path,body,expected)=>{
      calls.push(`${label}:${method}:${path}`);
      if(path==='/auth/logout')assert.deepEqual(body,{all:false});
      else assert.equal(expected,401);
      return {};
    };
  }
  c.admin.token='fake-admin-token';
  c.admin.call=async(method,path)=>{
    calls.push(`admin:${method}:${path}`);
    assert.equal(method,'GET');assert.equal(path,'/users/me');
    return {profile:{IdUsuario:'3',Rol:'Administrador'}};
  };
  await sessions[1]!.run(c);
  assert.equal(c.admin.token,'fake-admin-token');
  assert.deepEqual(calls,['b:POST:/auth/logout','b:GET:/users/me','operator:POST:/auth/logout','admin:GET:/users/me']);
  c.clear();
});
test('entrada: errores JSON, estructura y credenciales tienen códigos seguros',()=>{
  for(const [raw,code] of [
    ['{FAKE_SECRET','INPUT_JSON'],
    ['{}','INPUT_SHAPE'],
    [JSON.stringify({email:'',password:'FAKE_SECRET',confirm:'DATOS_FICTICIOS_EN_SHOPCART',modules:['all']}),'INPUT_CREDENTIALS']
  ] as const){
    assert.throws(()=>parseConfig(raw),error=>error instanceof ConfigFailure&&error.code===code&&!error.message.includes('FAKE_SECRET'));
  }
});
test('Node: stdin inválido produce diagnóstico de inicialización sin HTTP ni secretos',()=>{
  const child=spawnSync(process.execPath,['--import','tsx','test/functional/run.ts','--check-transport'],{cwd:backend,input:'{FAKE_SECRET',encoding:'utf8',timeout:15000});
  assert.equal(child.status,1);
  assert.match(child.stdout,/INPUT_JSON/);assert.match(child.stdout,/CONFIGURACION/);
  assert.match(child.stdout,/"scenariosStarted":false/);
  assert.doesNotMatch(child.stdout+child.stderr,/FAKE_SECRET|"operation"/);
});
test('PowerShell 5.1: SecureString, BSTR, JSON UTF-8, comillas y barra viajan por stdin offline',{skip:!windows},()=>{
  const child=spawnSync('powershell.exe',['-NoProfile','-ExecutionPolicy','Bypass','-File',launcher,'-CheckTransport'],{cwd:backend,encoding:'utf8',timeout:15000});
  assert.equal(child.status,0);assert.match(child.stdout,/UTF-8: OK/);
  assert.match(child.stdout,/codigo 0/);assert.doesNotMatch(child.stdout,/prueba-sin-secretos|"operation"/);
});
test('PowerShell: reproduce entrada inválida tras contraseña y muestra etapa sin iniciar Node',{skip:!windows},()=>{
  const quote=(s:string)=>"'"+s.replaceAll("'","''")+"'";
  // Sin archivos ni API. Si fallara la validación, el ejecutable inexistente
  // impediría arrancar Node; el test nunca podría alcanzar el flujo HTTP.
  const command=`function global:Read-Host { param([string]$Prompt,[switch]$AsSecureString) if($AsSecureString){return (ConvertTo-SecureString 'FAKE_SECRET' -AsPlainText -Force)} if($Prompt -like 'Escriba*'){return 'PRUEBAS'} return '' }
function global:Get-Command { param([string]$Name) return [pscustomobject]@{Source=(Join-Path ([IO.Path]::GetTempPath()) ([Guid]::NewGuid().ToString()+'.exe'))} }
& ${quote(launcher)}`;
  const child=spawnSync('powershell.exe',['-NoProfile','-ExecutionPolicy','Bypass','-Command',command],{cwd:backend,encoding:'utf8',timeout:15000});
  assert.equal(child.status,1);
  assert.match(child.stdout,/validar-credenciales/);assert.match(child.stdout,/INPUT_CREDENTIALS/);
  assert.match(child.stdout,/NodeIniciado=False/);assert.doesNotMatch(child.stdout+child.stderr,/FAKE_SECRET|"operation"/);
});

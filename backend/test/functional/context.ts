import { randomBytes, randomUUID } from 'node:crypto';
import { Client, check, type Logger } from './client.js';
import { Owned } from './safety.js';
import {AuthBudget} from './rate-policy.js';
import { object, rows, id, type Row } from '../support/values.js';
export interface Scenario { module:string; name:string; requires?:string[]; pending?:string; run:(c:Context)=>Promise<void> }
export interface Checkout { id:string; orderId:string; body:Row; key:string }
export class Context {
  readonly batch=randomUUID().replaceAll('-','').toUpperCase();
  readonly owned=new Owned(this.batch);
  readonly clients:Client[]=[];
  readonly authBudget=new AuthBudget();
  readonly admin:Client;
  readonly guest:Client;
  readonly from=new Date(Date.now()-60000).toISOString();
  readonly to=new Date(Date.now()+86400000).toISOString();
  readonly users:Record<string,Client>={};
  readonly ids:Record<string,string>={};
  readonly values:Record<string,Row>={};
  readonly checkouts:Record<string,Checkout>={};
  private sequence=0;
  constructor(readonly log:Logger){this.admin=this.client();this.guest=this.client(true);}
  client(testIdentity=false):Client {const c=new Client(this.owned,this.log,testIdentity,this.authBudget);this.clients.push(c);return c;}
  user(label:string):Client {const c=this.users[label];check(c,'Falta una cuenta Cliente requerida.');return c;}
  key(label:string):string {return `${this.batch}_${label}_${++this.sequence}`;}
  interval():string{return `from=${encodeURIComponent(this.from)}&to=${encodeURIComponent(this.to)}`;}
  async register(label:string):Promise<Client>{
    const c=this.client(true);await c.init();
    c.email=`qa-${this.batch.toLowerCase()}-${label}@example.invalid`;
    c.password=randomBytes(32).toString('base64url')+'aA1!';
    const registered=await c.call('POST','/auth/register',{firstName:'QA',lastName:label,email:c.email,password:c.password},201);
    c.userId=this.owned.add('user',id(registered.IdUsuario));
    await c.login(c.email,c.password,'Cliente');this.users[label]=c;return c;
  }
  async cart(c:Client):Promise<Row>{
    if(c.userId)this.owned.require('user',c.userId);
    const result=await c.call('GET','/carts/current');
    const cart=object(result.cart);check(cart.Estado==='ACTIVO','El carrito no está activo.');
    for(const line of rows(result.items))this.owned.require('variant',id(line.IdVariante));
    this.owned.add('cart',id(cart.IdCarrito));return result;
  }
  async balance(variant=this.ids.m!):Promise<Row>{
    const result=rows((await this.admin.call('GET',`/inventory?variantId=${variant}`)).inventory);
    check(result.length===1&&result[0]!.IdVariante===variant,'Inventario de variante inesperado.');return result[0]!;
  }
  async checkout(label:string,c:Client,coupon=true,variant=this.ids.m!,quantity=2,shipping=this.ids.shipping!):Promise<Checkout>{
    this.owned.require('variant',variant);
    await this.cart(c);await c.call('DELETE','/carts/current/items');
    await c.call('POST','/carts/current/items',{variantId:variant,quantity});
    const cart=object((await this.cart(c)).cart);
    const body:Row={cartId:id(cart.IdCarrito),cartRevision:cart.RevisionCarrito,shippingMethodId:Number(shipping),recipientName:'QA',phone:'55550000',department:'Guatemala',city:'Guatemala',address1:'Prueba QA',...(coupon?{couponCode:this.ids.couponCode}: {})};
    const key=this.key('checkout');
    const result=object((await c.call('POST','/checkouts',body,201,key)).checkout);
    const checkout={id:this.owned.add('checkout',id(result.IdCheckout)),orderId:this.owned.add('order',id(result.IdPedido)),body,key};
    this.checkouts[label]=checkout;return checkout;
  }
  async order(c:Client,orderId:string):Promise<Row>{
    this.owned.require('order',orderId);const result=await c.call('GET',`/orders/${orderId}`);
    const header=object(result.order);check(header.IdPedido===orderId,'La consulta devolvió otro pedido.');
    this.owned.require('checkout',id(header.IdCheckout));
    const lines=rows(result.items);
    // Validar TODAS las líneas antes de habilitar cualquiera para devoluciones.
    for(const line of lines){
      id(line.IdDetallePedido);
      check(line.IdPedido===orderId,'Detalle asociado a otro pedido.');
      this.owned.require('variant',id(line.IdVariante));this.owned.require('category',line.IdCategoria);
    }
    for(const line of lines)this.owned.add('line',id(line.IdDetallePedido));return result;
  }
  async findPage(client:Client,path:string,set:string,predicate:(row:Row)=>boolean):Promise<Row|undefined>{
    for(let page=1;page<=1000;page++){
      const values=rows((await client.call('GET',`${path}${path.includes('?')?'&':'?'}page=${page}&pageSize=100`))[set]);
      const found=values.find(predicate);if(found)return found;if(values.length<100)return undefined;
    }
    throw Error('Paginación excedida; no se completa la comprobación.');
  }
  clear():void{for(const c of this.clients)c.clear();}
}

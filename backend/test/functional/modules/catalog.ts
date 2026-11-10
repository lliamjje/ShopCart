import type { Scenario } from '../context.js';
import { check } from '../client.js';
import { id,intId,object,rows,money } from '../../support/values.js';
export const catalog:Scenario[]=[
 {module:'catalog',name:'Categoría propia y dos productos inicialmente inactivos',requires:['users'],run:async c=>{
   const search=rows((await c.guest.call('GET',`/catalog/products?search=${c.batch}`)).products);
   check(search.length===0,'El lote ya está presente.');
   const category=intId(object((await c.admin.call('POST','/catalog/categories',{name:'QA '+c.batch,description:'Lote funcional',active:true},201)).category).IdCategoria);
   c.ids.category=c.owned.add('category',category);
   await c.admin.call('PATCH',`/catalog/categories/${category}`,{name:'QA '+c.batch,description:'Categoría actualizada del lote',active:true});
   for(const [label,name] of [['shirt','Camiseta QA'],['organizer','Organizador QA']] as const){
     const body={categoryId:category,name,description:c.batch,active:false};c.values[label]=body;
     c.ids[label]=c.owned.add('product',id(object((await c.admin.call('POST','/catalog/products',body,201)).product).IdProducto));
     await c.guest.call('GET',`/catalog/products/${c.ids[label]}`,{},404);
   }
 }},
 {module:'catalog',name:'Tres variantes, dinero decimal y restricciones de SKU',run:async c=>{
   for(const [label,product,price,size,color] of [['m','shirt','112.0000','M','azul'],['l','shirt','123.2000','L','azul'],['org','organizer','56.0000',null,null]] as const){
     const body={productId:c.ids[product],sku:`QA-${c.batch}-${label.toUpperCase()}`,price,size,color,active:true};
     c.values[label]=body;c.ids[label]=c.owned.add('variant',id(object((await c.admin.call('POST','/catalog/variants',body,201)).variant).IdVariante));
     check(Number((await c.balance(c.ids[label])).CantidadFisica)===0,'La existencia inicial no es cero.');
   }
   await c.admin.call('POST','/catalog/variants',{...c.values.m,size:'DUPLICADO'},409);
   await c.admin.call('POST','/catalog/variants',{...c.values.m,sku:`QA-${c.batch}-INVALID`,price:'0'},400);
 }}
];
export const publication:Scenario[]=[
 {module:'publication',name:'Activación, catálogo paginado y variante agotada',requires:['inventory'],run:async c=>{
   for(const label of ['shirt','organizer'])await c.admin.call('PATCH',`/catalog/products/${c.ids[label]}`,{...c.values[label],active:true});
   const listed=rows((await c.guest.call('GET',`/catalog/products?search=${c.batch}&pageSize=1`)).products);
   check(listed.length===1,'La paginación no limitó resultados.');
   for(const label of ['shirt','organizer']){
     const detail=await c.guest.call('GET',`/catalog/products/${c.ids[label]}`);
     check(object(detail.product).IdProducto===c.ids[label],'Identidad del producto incorrecta.');
     const variants=rows(detail.variants);
     for(const name of label==='shirt'?['m','l']:['org']){
       const variant=variants.find(v=>v.IdVariante===c.ids[name]);check(variant,'Falta variante activa.');
       check(money(variant.Precio)===money(c.values[name]!.price),'Precio decimal incorrecto.');
       check(Number(variant.Disponible)===(name==='m'?10:name==='l'?0:5),'Disponibilidad inicial incorrecta.');
     }
   }
 }}
];

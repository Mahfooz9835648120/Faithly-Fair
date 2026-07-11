import { createClient } from 'https://esm.sh/@supabase/supabase-js@2';

const cors={ 'Content-Type':'application/json' };
Deno.serve(async(req)=>{
 try{
  const hookSecret=Deno.env.get('WEBHOOK_SECRET');
  if(!hookSecret||req.headers.get('x-webhook-secret')!==hookSecret)return new Response(JSON.stringify({error:'Unauthorized'}),{status:401,headers:cors});
  const body=await req.json();
  const orderId=body.record?.id||body.order_id;
  const supabase=createClient(Deno.env.get('SUPABASE_URL')!,Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!);
  const {data:order,error}=await supabase.from('orders').select('*,order_items(*)').eq('id',orderId).single();
  if(error)throw error;
  const rows=order.order_items.map((x:any)=>`<tr><td style="padding:8px">${escapeHtml(x.product_name)}</td><td>${x.quantity}</td><td>₹${Number(x.line_total).toFixed(2)}</td></tr>`).join('');
  const html=`<div style="font-family:Arial;color:#3f292b;max-width:650px"><h1 style="color:#94464d">New Faithly Fair order</h1><p><b>${order.order_number}</b> · ${order.payment_method.toUpperCase()} · ${order.payment_status}</p><table style="width:100%;border-collapse:collapse">${rows}</table><h2>Total: ₹${Number(order.total).toFixed(2)}</h2><hr/><p><b>${escapeHtml(order.customer_name)}</b><br/>${escapeHtml(order.mobile)} ${order.email?`· ${escapeHtml(order.email)}`:''}<br/>${escapeHtml([order.address_line1,order.address_line2,order.landmark,order.city,order.state,order.pincode].filter(Boolean).join(', '))}</p><p>Review this order in the private admin studio.</p></div>`;
  const response=await fetch('https://api.resend.com/emails',{method:'POST',headers:{Authorization:`Bearer ${Deno.env.get('RESEND_API_KEY')}`,'Content-Type':'application/json'},body:JSON.stringify({from:Deno.env.get('ORDER_FROM_EMAIL')||'Faithly Fair <orders@yourdomain.com>',to:[Deno.env.get('ORDER_TO_EMAIL')||'Fairyfaithly@gmail.com'],subject:`New order ${order.order_number} · ₹${Number(order.total).toFixed(0)}`,html})});
  if(!response.ok)throw new Error(await response.text());
  return new Response(JSON.stringify({ok:true}),{headers:cors});
 }catch(error){console.error(error);return new Response(JSON.stringify({error:error instanceof Error?error.message:'Unknown error'}),{status:500,headers:cors})}
});
function escapeHtml(value:unknown){return String(value??'').replace(/[&<>'"]/g,c=>({'&':'&amp;','<':'&lt;','>':'&gt;',"'":'&#39;','"':'&quot;'}[c]!))}

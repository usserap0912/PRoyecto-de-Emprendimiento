// ============================================
// SafeZone - Stripe Premium Subscription
// Edge Function para Supabase
// ============================================
// Endpoints:
//   POST /checkout  - Crea una sesión de pago Stripe
//   POST /webhook   - Recibe eventos de Stripe
// ============================================

import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2.39.0";
import Stripe from "stripe";

// ============================================
// CONFIGURACIÓN
// ============================================
// Variables de entorno requeridas (configurar via Supabase CLI):
//   supabase secrets set STRIPE_SECRET_KEY=sk_test_...
//   supabase secrets set STRIPE_WEBHOOK_SECRET=whsec_...
//   supabase secrets set STRIPE_PRICE_ID=price_... (ID del precio en Stripe Dashboard)
//   supabase secrets set PREMIUM_REDIRECT_URL=https://tudominio.com (opcional)
// ============================================

const stripe = new Stripe(Deno.env.get("STRIPE_SECRET_KEY")!, {
  apiVersion: "2023-10-16",
});

const supabaseUrl = Deno.env.get("SUPABASE_URL")!;
const supabaseKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
const supabase = createClient(supabaseUrl, supabaseKey);

const STRIPE_PRICE_ID = Deno.env.get("STRIPE_PRICE_ID") || "price_placeholder";
const WEBHOOK_SECRET = Deno.env.get("STRIPE_WEBHOOK_SECRET")!;

// CORS headers para la app Flutter
const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
  "Access-Control-Allow-Headers": "Content-Type, stripe-signature",
};

serve(async (req) => {
  // Manejar preflight CORS
  if (req.method === "OPTIONS") {
    return new Response(null, { headers: corsHeaders });
  }

  const url = new URL(req.url);
  const path = url.pathname.split("/").pop();

  try {
    // ============================================
    // POST /checkout - Crear sesión de pago
    // ============================================
    if (path === "checkout" && req.method === "POST") {
      const { userCode, zone } = await req.json();

      if (!userCode) {
        return new Response(
          JSON.stringify({ error: "userCode es requerido" }),
          { status: 400, headers: { ...corsHeaders, "Content-Type": "application/json" } }
        );
      }

      // Determinar URL de redirección
      const redirectUrl = Deno.env.get("PREMIUM_REDIRECT_URL") ||
        req.headers.get("origin") ||
        "http://localhost:8000";

      // Crear sesión de checkout en Stripe
      const session = await stripe.checkout.sessions.create({
        payment_method_types: ["card"],
        line_items: [
          {
            price: STRIPE_PRICE_ID,
            quantity: 1,
          },
        ],
        mode: "subscription",
        success_url: `${redirectUrl}/premium?success=true&user_code=${userCode}`,
        cancel_url: `${redirectUrl}/premium?canceled=true`,
        metadata: {
          user_code: userCode,
          zone: String(zone || ""),
        },
      });

      return new Response(
        JSON.stringify({
          url: session.url,
          sessionId: session.id,
        }),
        { headers: { ...corsHeaders, "Content-Type": "application/json" } }
      );
    }

    // ============================================
    // POST /webhook - Recibir eventos de Stripe
    // ============================================
    if (path === "webhook" && req.method === "POST") {
      const signature = req.headers.get("stripe-signature");
      if (!signature) {
        return new Response(
          JSON.stringify({ error: "Firma de webhook requerida" }),
          { status: 400, headers: { ...corsHeaders, "Content-Type": "application/json" } }
        );
      }

      const body = await req.text();
      let event: Stripe.Event;

      try {
        event = stripe.webhooks.constructEvent(body, signature, WEBHOOK_SECRET);
      } catch (err) {
        console.error("Error verificando webhook:", err);
        return new Response(
          JSON.stringify({ error: "Firma de webhook inválida" }),
          { status: 400, headers: { ...corsHeaders, "Content-Type": "application/json" } }
        );
      }

      console.log(`Evento Stripe recibido: ${event.type}`);

      // Procesar checkout completado
      if (event.type === "checkout.session.completed") {
        const session = event.data.object as Stripe.Checkout.Session;
        const userCode = session.metadata?.user_code;

        if (userCode) {
          // Actualizar perfil del usuario como premium
          const { error } = await supabase
            .from("profiles")
            .update({
              is_premium: true,
              stripe_customer_id: session.customer,
              premium_activated_at: new Date().toISOString(),
            })
            .eq("user_code", userCode);

          if (error) {
            console.error("Error actualizando perfil premium:", error);
          } else {
            console.log(`✅ Premium activado para usuario: ${userCode}`);
          }
        }
      }

      // Procesar cancelación de suscripción
      if (event.type === "customer.subscription.deleted") {
        const subscription = event.data.object as Stripe.Subscription;
        const customerId = subscription.customer as string;

        // Buscar usuario por stripe_customer_id y desactivar premium
        const { data: profiles } = await supabase
          .from("profiles")
          .select("user_code")
          .eq("stripe_customer_id", customerId);

        if (profiles && profiles.length > 0) {
          for (const profile of profiles) {
            await supabase
              .from("profiles")
              .update({
                is_premium: false,
                premium_activated_at: null,
              })
              .eq("user_code", profile.user_code);
            console.log(`❌ Premium desactivado para usuario: ${profile.user_code}`);
          }
        }
      }

      return new Response(
        JSON.stringify({ received: true }),
        { headers: { ...corsHeaders, "Content-Type": "application/json" } }
      );
    }

    // ============================================
    // GET /status?user_code=xxx - Verificar estado premium
    // ============================================
    if (path === "status" && req.method === "GET") {
      const userCode = url.searchParams.get("user_code");

      if (!userCode) {
        return new Response(
          JSON.stringify({ error: "user_code es requerido" }),
          { status: 400, headers: { ...corsHeaders, "Content-Type": "application/json" } }
        );
      }

      const { data, error } = await supabase
        .from("profiles")
        .select("is_premium, premium_activated_at")
        .eq("user_code", userCode)
        .single();

      if (error) {
        return new Response(
          JSON.stringify({ error: "Usuario no encontrado" }),
          { status: 404, headers: { ...corsHeaders, "Content-Type": "application/json" } }
        );
      }

      return new Response(
        JSON.stringify({
          is_premium: data?.is_premium || false,
          premium_activated_at: data?.premium_activated_at || null,
        }),
        { headers: { ...corsHeaders, "Content-Type": "application/json" } }
      );
    }

    // Ruta no encontrada
    return new Response(
      JSON.stringify({ error: "Ruta no encontrada. Usa /checkout, /webhook o /status" }),
      { status: 404, headers: { ...corsHeaders, "Content-Type": "application/json" } }
    );
  } catch (error) {
    console.error("Error en Edge Function:", error);
    return new Response(
      JSON.stringify({ error: "Error interno del servidor" }),
      { status: 500, headers: { ...corsHeaders, "Content-Type": "application/json" } }
    );
  }
});

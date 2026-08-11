// ============================================
// SafeZone — Mercado Pago Premium (Suscripción mensual)
// Edge Function para Supabase
// ============================================
// Endpoints:
//   POST /checkout  → crea una suscripción (preapproval) y devuelve la URL de pago
//   POST /webhook   → recibe notificaciones de Mercado Pago
//   GET  /status    → consulta el estado premium de un usuario
//   GET  /return    → página simple de confirmación tras pagar
//
// VARIABLES DE ENTORNO (Supabase → Edge Functions → Secrets):
//   MERCADOPAGO_ACCESS_TOKEN = Token del vendedor (Dashboard MP → Desarrolladores → Credenciales)
//   MP_PRICE_PER_MONTH       = Precio mensual en soles (ej: 9.9) [opcional, default 9.9]
//   MP_REDIRECT_URL          = URL de la app a la que volver tras pagar [opcional]
// ============================================

import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2.39.0";

const MP_API = "https://api.mercadopago.com";
const ACCESS_TOKEN = Deno.env.get("MERCADOPAGO_ACCESS_TOKEN") || "";
const PRICE = Number(Deno.env.get("MP_PRICE_PER_MONTH") || "9.9") || 9.9;
const REDIRECT_URL = Deno.env.get("MP_REDIRECT_URL") || "";

const supabase = createClient(
  Deno.env.get("SUPABASE_URL")!,
  Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!
);

// CORS headers para la app Flutter
const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Methods": "POST, GET, OPTIONS",
  "Access-Control-Allow-Headers": "Content-Type",
};

function json(data: unknown, status = 200): Response {
  return new Response(JSON.stringify(data), {
    status,
    headers: { ...corsHeaders, "Content-Type": "application/json" },
  });
}

// ============================================
// Helpers
// ============================================

/** external_reference guarda el código de usuario de forma segura (JSON) */
function refFor(userCode: string, zone: string): string {
  return JSON.stringify({ u: userCode, z: zone || "" });
}

/** Recupera el user_code desde el external_reference */
function userFromRef(ref: string | null | undefined): string | null {
  if (!ref) return null;
  try {
    const parsed = JSON.parse(ref);
    return typeof parsed?.u === "string" ? parsed.u : null;
  } catch {
    return null;
  }
}

/** Llama a la API de Mercado Pago con el token del vendedor */
async function mpFetch(path: string, init?: RequestInit): Promise<{ ok: boolean; data: any }> {
  const resp = await fetch(`${MP_API}${path}`, {
    ...init,
    headers: {
      Authorization: `Bearer ${ACCESS_TOKEN}`,
      "Content-Type": "application/json",
      ...(init?.headers || {}),
    },
  });
  let data: any = null;
  try {
    data = await resp.json();
  } catch {
    /* sin cuerpo */
  }
  return { ok: resp.ok, data };
}

/** Activa o desactiva premium en Supabase */
async function setPremium(userCode: string, preapprovalId: string | null, active: boolean) {
  const patch: Record<string, unknown> = { is_premium: active };
  if (preapprovalId) patch.mercadopago_subscription_id = preapprovalId;
  if (active) patch.premium_activated_at = new Date().toISOString();

  const { error } = await supabase.from("profiles").update(patch).eq("user_code", userCode);
  if (error) {
    console.error("Error actualizando premium:", error);
  } else {
    console.log(`${active ? "✅" : "❌"} Premium ${active ? "activado" : "desactivado"} para ${userCode}`);
  }
}

// ============================================
// Handler principal
// ============================================

serve(async (req) => {
  // Preflight CORS
  if (req.method === "OPTIONS") {
    return new Response(null, { headers: corsHeaders });
  }

  const url = new URL(req.url);
  const path = url.pathname.split("/").pop();

  try {
    // ============================================
    // POST /checkout — Crear suscripción (preapproval)
    // ============================================
    if (path === "checkout" && req.method === "POST") {
      if (!ACCESS_TOKEN) {
        return json(
          { error: "Mercado Pago no configurado (falta MERCADOPAGO_ACCESS_TOKEN)" },
          500
        );
      }

      const { userCode, zone, email } = await req.json();
      if (!userCode) {
        return json({ error: "userCode es requerido" }, 400);
      }

      const notificationUrl = `${url.origin}/functions/v1/mercadopago-premium/webhook`;
      const backUrl = REDIRECT_URL || `${url.origin}/functions/v1/mercadopago-premium/return`;

      const { ok, data } = await mpFetch("/preapproval", {
        method: "POST",
        body: JSON.stringify({
          reason: "SafeZone Premium — suscripción mensual",
          external_reference: refFor(userCode, String(zone || "")),
          payer_email: email || undefined,
          auto_recurring: {
            frequency: 1,
            frequency_type: "months",
            transaction_amount: PRICE,
            currency_id: "PEN",
          },
          back_url: backUrl,
          notification_url: notificationUrl,
        }),
      });

      if (!ok) {
        console.error("MP error creando preapproval:", data);
        return json({ error: data?.message || "Error creando la suscripción en Mercado Pago" }, 502);
      }

      return json({ url: data.init_point, preapprovalId: data.id });
    }

    // ============================================
    // POST /webhook — Notificaciones de Mercado Pago
    // ============================================
    if (path === "webhook" && req.method === "POST") {
      const body = await req.json();
      const type = body?.type || body?.topic;
      const dataId = body?.data?.id;
      console.log("Webhook MP:", JSON.stringify(body));

      if (!dataId) return json({ received: true });

      // Suscripción (preapproval): autorizada / cancelada
      if (type === "preapproval" || type === "subscription_preapproval") {
        const { ok, data } = await mpFetch(`/preapproval/${dataId}`);
        if (ok && data) {
          const userCode = userFromRef(data.external_reference);
          if (userCode) {
            const active = data.status === "authorized";
            await setPremium(userCode, String(data.id), active);
          }
        }
      }

      // Pago (inicial o recurrente)
      if (type === "payment") {
        const { ok, data } = await mpFetch(`/payments/${dataId}`);
        if (ok && data && data.status === "approved") {
          let userCode = userFromRef(data.external_reference);
          const preapprovalId = data.preapproval_id ? String(data.preapproval_id) : null;

          // Si el pago no trae la referencia, la buscamos en la suscripción
          if (!userCode && preapprovalId) {
            const { ok: ok2, data: pre } = await mpFetch(`/preapproval/${preapprovalId}`);
            if (ok2 && pre) userCode = userFromRef(pre.external_reference);
          }

          if (userCode) await setPremium(userCode, preapprovalId, true);
        }
      }

      return json({ received: true });
    }

    // ============================================
    // POST /cancel — Cancelar la suscripción del usuario
    // ============================================
    if (path === "cancel" && req.method === "POST") {
      const { userCode } = await req.json();
      if (!userCode) return json({ error: "userCode es requerido" }, 400);

      const { data, error } = await supabase
        .from("profiles")
        .select("mercadopago_subscription_id")
        .eq("user_code", userCode)
        .single();

      if (error || !data?.mercadopago_subscription_id) {
        return json({ error: "No hay suscripción activa para este usuario" }, 404);
      }

      const subId = String(data.mercadopago_subscription_id);

      // Cancelar la suscripción en Mercado Pago
      const { ok, data: res } = await mpFetch(`/preapproval/${subId}`, {
        method: "PUT",
        body: JSON.stringify({ status: "cancelled" }),
      });

      if (!ok) {
        console.error("MP error cancelando preapproval:", res);
        return json({ error: res?.message || "Error cancelando la suscripción en Mercado Pago" }, 502);
      }

      await setPremium(userCode, subId, false);
      return json({ success: true, message: "Suscripción cancelada correctamente" });
    }

    // ============================================
    // GET /status?user_code=xxx — Estado premium
    // ============================================
    if (path === "status" && req.method === "GET") {
      const userCode = url.searchParams.get("user_code");
      if (!userCode) {
        return json({ error: "user_code es requerido" }, 400);
      }

      const { data, error } = await supabase
        .from("profiles")
        .select("is_premium, premium_activated_at, mercadopago_subscription_id")
        .eq("user_code", userCode)
        .single();

      if (error) return json({ is_premium: false });

      // Verificación extra contra Mercado Pago (si hay suscripción registrada)
      let isPremium = data?.is_premium || false;
      const subId = data?.mercadopago_subscription_id;
      if (subId) {
        const { ok, data: pre } = await mpFetch(`/preapproval/${subId}`);
        if (ok && pre) {
          const active = pre.status === "authorized";
          if (active !== isPremium) {
            isPremium = active;
            await setPremium(userCode, String(subId), active);
          }
        }
      }

      return json({
        is_premium: isPremium,
        premium_activated_at: data?.premium_activated_at || null,
      });
    }

    // ============================================
    // GET /return — Página de confirmación tras pagar
    // ============================================
    if (path === "return" && req.method === "GET") {
      return new Response(
        "<html><body style='font-family:sans-serif;text-align:center;padding:48px 16px'>" +
          "<h2 style='color:#2e7d32'>✅ Pago procesado</h2>" +
          "<p>Puedes cerrar esta ventana y volver a SafeZone.</p>" +
          "<p>Si tu Premium no se activó al instante, toca «Restaurar compras» en la app.</p>" +
          "</body></html>",
        { headers: { ...corsHeaders, "Content-Type": "text/html; charset=utf-8" } }
      );
    }

    // Ruta no encontrada
    return json(
      { error: "Ruta no encontrada. Usa /checkout, /webhook, /status o /return" },
      404
    );
  } catch (error) {
    console.error("Error en Edge Function:", error);
    return json({ error: "Error interno del servidor" }, 500);
  }
});

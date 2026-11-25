// ============================================
// SafeZone — Push de alertas (Firebase Cloud Messaging)
// Edge Function para Supabase
// ============================================
// La app la llama después de publicar un S.O.S. o un reporte.
// Envía el aviso a los tokens de device_tokens para que llegue
// al celular aunque SafeZone esté cerrada.
//
// Endpoint:
//   POST /  → body { type: 'sos' | 'report', alertId, userCode, zone, category }
//
// VARIABLES DE ENTORNO (Supabase → Edge Functions → Secrets):
//   FIREBASE_SERVICE_ACCOUNT = contenido del JSON de la cuenta de servicio
//                              (Firebase → Configuración → Cuentas de servicio)
// ============================================

import { createClient } from "https://esm.sh/@supabase/supabase-js@2.39.0";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
};

const SUPABASE_URL = Deno.env.get("SUPABASE_URL")!;

// Los proyectos nuevos ya no exponen SUPABASE_SERVICE_ROLE_KEY como secreto
// propio: la clave de servicio vive dentro de SUPABASE_SECRET_KEYS (JSON).
function serviceKey(): string {
  const legacy = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
  if (legacy) return legacy;

  const dict = Deno.env.get("SUPABASE_SECRET_KEYS");
  if (dict) {
    const parsed = JSON.parse(dict) as Record<string, string>;
    const first = Object.values(parsed)[0];
    if (first) return first;
  }

  throw new Error(
    "Falta la clave de servicio (SUPABASE_SERVICE_ROLE_KEY o SUPABASE_SECRET_KEYS)",
  );
}

let cachedClient: ReturnType<typeof createClient> | null = null;

function db() {
  if (!cachedClient) cachedClient = createClient(SUPABASE_URL, serviceKey());
  return cachedClient;
}

const SOS_CHANNEL = "safezone_sos_v2";
const ALERTS_CHANNEL = "safezone_alerts";

interface ServiceAccount {
  project_id: string;
  client_email: string;
  private_key: string;
  token_uri?: string;
}

function serviceAccount(): ServiceAccount {
  const raw = Deno.env.get("FIREBASE_SERVICE_ACCOUNT");
  if (!raw) throw new Error("Falta FIREBASE_SERVICE_ACCOUNT en los secrets");
  return JSON.parse(raw) as ServiceAccount;
}

function base64Url(input: Uint8Array | string): string {
  const bytes = typeof input === "string" ? new TextEncoder().encode(input) : input;
  let binary = "";
  for (const byte of bytes) binary += String.fromCharCode(byte);
  return btoa(binary).replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/, "");
}

function pemToDer(pem: string): Uint8Array {
  const body = pem
    .replace(/-----BEGIN PRIVATE KEY-----/, "")
    .replace(/-----END PRIVATE KEY-----/, "")
    .replace(/\s+/g, "");
  const binary = atob(body);
  const der = new Uint8Array(binary.length);
  for (let i = 0; i < binary.length; i++) der[i] = binary.charCodeAt(i);
  return der;
}

let cachedToken: { value: string; expiresAt: number } | null = null;

/** Token OAuth de Google (scope firebase.messaging) firmado con la clave RS256. */
async function googleAccessToken(): Promise<string> {
  const now = Math.floor(Date.now() / 1000);
  if (cachedToken && cachedToken.expiresAt - 60 > now) return cachedToken.value;

  const account = serviceAccount();
  const header = base64Url(JSON.stringify({ alg: "RS256", typ: "JWT" }));
  const claims = base64Url(
    JSON.stringify({
      iss: account.client_email,
      scope: "https://www.googleapis.com/auth/firebase.messaging",
      aud: account.token_uri || "https://oauth2.googleapis.com/token",
      iat: now,
      exp: now + 3600,
    }),
  );

  const key = await crypto.subtle.importKey(
    "pkcs8",
    pemToDer(account.private_key),
    { name: "RS256", hash: "SHA-256" },
    false,
    ["sign"],
  );
  const signature = await crypto.subtle.sign(
    "RS256",
    key,
    new TextEncoder().encode(`${header}.${claims}`),
  );
  const assertion = `${header}.${claims}.${base64Url(new Uint8Array(signature))}`;

  const response = await fetch(account.token_uri || "https://oauth2.googleapis.com/token", {
    method: "POST",
    headers: { "Content-Type": "application/x-www-form-urlencoded" },
    body: new URLSearchParams({
      grant_type: "urn:ietf:params:oauth:grant-type:jwt-bearer",
      assertion,
    }),
  });

  const data = await response.json();
  if (!response.ok) {
    throw new Error(`Google token ${response.status}: ${JSON.stringify(data)}`);
  }

  cachedToken = {
    value: data.access_token,
    expiresAt: now + (Number(data.expires_in) || 3600),
  };
  return cachedToken.value;
}

const CATEGORY_LABELS: Record<string, string> = {
  robo: "Robo",
  sospechoso: "Persona sospechosa",
  extorsion: "Extorsión",
  alumbrado: "Alumbrado",
  otros: "Otro incidente",
  sos: "S.O.S.",
};

function buildMessage(token: string, body: Record<string, unknown>) {
  const type = body.type === "sos" ? "sos" : "report";
  const isSos = type === "sos";
  const category = typeof body.category === "string" ? body.category : "otros";
  const zone = typeof body.zone === "number" ? body.zone : null;

  const title = isSos
    ? "🚨 ¡Alerta S.O.S. activa!"
    : `🚨 ${CATEGORY_LABELS[category] ?? "Nuevo reporte"}${zone ? ` en Zona ${zone}` : ""}`;

  const text = isSos
    ? "Un vecino necesita ayuda. Abre SafeZone para ver la ubicación aproximada."
    : "Hay un nuevo reporte cerca de ti. Abre SafeZone para verlo.";

  return {
    message: {
      token,
      notification: { title, body: text },
      data: {
        type,
        alertId: String(body.alertId ?? ""),
        userCode: String(body.userCode ?? ""),
      },
      android: {
        priority: isSos ? "HIGH" : "NORMAL",
        notification: {
          channel_id: isSos ? SOS_CHANNEL : ALERTS_CHANNEL,
          sound: isSos ? "alarma_recepcion" : "default",
          color: isSos ? "#D32F2F" : "#E65100",
          default_vibrate_timings: isSos,
          notification_priority: isSos ? "PRIORITY_MAX" : "PRIORITY_HIGH",
        },
      },
    },
  };
}

async function sendToToken(token: string, body: Record<string, unknown>) {
  const account = serviceAccount();
  const accessToken = await googleAccessToken();
  const response = await fetch(
    `https://fcm.googleapis.com/v1/projects/${account.project_id}/messages:send`,
    {
      method: "POST",
      headers: {
        Authorization: `Bearer ${accessToken}`,
        "Content-Type": "application/json",
      },
      body: JSON.stringify(buildMessage(token, body)),
    },
  );
  if (response.ok) return { token, ok: true as const };

  const error = await response.text();
  return { token, ok: false as const, error };
}

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }

  try {
    const body = await req.json();
    const actor = typeof body.userCode === "string" ? body.userCode : "";
    const type = body.type === "sos" ? "sos" : "report";

    let query = db()
      .from("device_tokens")
      .select("token, user_code, zone")
      .neq("user_code", actor);
    // Los reportes se avisan solo a la zona del incidente; el S.O.S. a todos.
    if (type === "report" && typeof body.zone === "number") {
      query = query.eq("zone", body.zone);
    }

    const { data: tokens, error } = await query.limit(2000);
    if (error) throw error;
    if (!tokens || tokens.length === 0) {
      return new Response(JSON.stringify({ sent: 0, failed: 0 }), {
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      });
    }

    const results = await Promise.allSettled(
      tokens.map((row: { token: string }) => sendToToken(row.token, body)),
    );

    const invalid: string[] = [];
    let sent = 0;
    let failed = 0;

    for (const result of results) {
      if (result.status === "rejected") {
        failed++;
        continue;
      }
      if (result.value.ok) {
        sent++;
      } else {
        failed++;
        if (result.value.error?.includes("UNREGISTERED") ||
            result.value.error?.includes("NOT_FOUND")) {
          invalid.push(result.value.token);
        }
      }
    }

    // Limpiar tokens de apps desinstaladas.
    if (invalid.length > 0) {
      await db().from("device_tokens").delete().in("token", invalid);
    }

    return new Response(JSON.stringify({ sent, failed, cleaned: invalid.length }), {
      headers: { ...corsHeaders, "Content-Type": "application/json" },
    });
  } catch (error) {
    console.error("[send-push]", error);
    return new Response(JSON.stringify({ error: String(error) }), {
      status: 500,
      headers: { ...corsHeaders, "Content-Type": "application/json" },
    });
  }
});

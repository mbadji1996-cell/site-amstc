// supabase/functions/notify-members-whatsapp/index.ts
//
// Diffuse un message WhatsApp à une audience de membres (tous, carte
// expirée, carte à renouveler bientôt, ou cotisation du mois impayée -
// voir supabase/phase31-whatsapp-rappels-cibles.sql pour le détail du
// ciblage), via la Meta Cloud API. Contrairement à "notify-admin", cette
// fonction est appelée DIRECTEMENT depuis le navigateur
// (membres/whatsapp-admin.html), avec le
// jeton de session de l'admin connecté (Authorization: Bearer <JWT>,
// envoyé automatiquement par supabaseClient.functions.invoke()). Elle
// vérifie donc elle-même que l'appelant a le rôle admin/super_admin avant
// d'envoyer quoi que ce soit — le bouton "Verify JWT" du Dashboard doit
// rester ACTIVÉ pour cette fonction (contrairement à notify-admin).
//
// Un message WhatsApp envoyé par une entreprise en dehors d'une fenêtre
// de conversation de 24h DOIT utiliser un modèle ("template") pré-approuvé
// par WhatsApp — voir README-espace-membres.md, section "Diffusion
// WhatsApp aux membres", pour la création de ce modèle.
//
// Secrets requis (Dashboard > Project Settings > Edge Functions > Secrets) :
//   SUPABASE_URL              - déjà fourni automatiquement par Supabase
//   SUPABASE_SERVICE_ROLE_KEY - déjà fourni automatiquement par Supabase
//   META_WHATSAPP_TOKEN       - jeton d'accès permanent Meta Cloud API
//   META_PHONE_NUMBER_ID      - identifiant du numéro expéditeur WhatsApp Business
//   META_TEMPLATE_NAME        - optionnel, défaut "nouvelle_annonce"
//   META_TEMPLATE_LANG        - optionnel, défaut "fr"

import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const SUPABASE_URL = Deno.env.get("SUPABASE_URL")!;
const SERVICE_ROLE_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
const META_WHATSAPP_TOKEN = Deno.env.get("META_WHATSAPP_TOKEN");
const META_PHONE_NUMBER_ID = Deno.env.get("META_PHONE_NUMBER_ID");
const META_TEMPLATE_NAME = Deno.env.get("META_TEMPLATE_NAME") || "nouvelle_annonce";
const META_TEMPLATE_LANG = Deno.env.get("META_TEMPLATE_LANG") || "fr";

const CORS_HEADERS = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, content-type, apikey, x-client-info",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

function digitsOnly(phone: string): string {
  return String(phone || "").replace(/[^0-9]/g, "");
}

function json(body: Record<string, unknown>, status = 200) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...CORS_HEADERS, "Content-Type": "application/json" },
  });
}

Deno.serve(async (req: Request) => {
  if (req.method === "OPTIONS") return new Response(null, { headers: CORS_HEADERS });
  if (req.method !== "POST") return json({ error: "Méthode non autorisée" }, 405);

  if (!META_WHATSAPP_TOKEN || !META_PHONE_NUMBER_ID) {
    console.error("notify-members-whatsapp: secrets META_WHATSAPP_TOKEN / META_PHONE_NUMBER_ID manquants");
    return json({ error: "Configuration serveur incomplète" }, 500);
  }

  const jwt = (req.headers.get("authorization") || "").replace(/^Bearer /, "");
  if (!jwt) return json({ error: "Non authentifié" }, 401);

  const admin = createClient(SUPABASE_URL, SERVICE_ROLE_KEY);

  const { data: userData, error: userErr } = await admin.auth.getUser(jwt);
  if (userErr || !userData?.user) {
    return json({ error: "Session invalide" }, 401);
  }

  const { data: callerProfile } = await admin
    .from("profiles")
    .select("role, full_name")
    .eq("id", userData.user.id)
    .single();

  if (!callerProfile || !["admin", "super_admin"].includes(callerProfile.role)) {
    return json({ error: "Réservé aux administrateurs" }, 403);
  }

  let payload: { message?: string; audience?: string };
  try {
    payload = await req.json();
  } catch {
    return json({ error: "JSON invalide" }, 400);
  }

  const message = String(payload.message || "").trim();
  if (!message) return json({ error: "Message vide" }, 400);
  if (message.length > 800) return json({ error: "Message trop long (800 caractères maximum)" }, 400);

  const audience = String(payload.audience || "tous");
  const KNOWN_AUDIENCES = ["tous", "carte_expiree", "carte_expire_bientot", "cotisation_impayee"];
  if (!KNOWN_AUDIENCES.includes(audience)) {
    return json({ error: `Audience inconnue : ${audience}` }, 400);
  }

  const { data: recipients, error: recErr } = await admin
    .rpc("whatsapp_target_members", { p_audience: audience });

  if (recErr) {
    console.error("notify-members-whatsapp: échec chargement destinataires", recErr);
    return json({ error: "Impossible de charger les destinataires" }, 500);
  }

  const targets = (recipients || []).filter((r) => digitsOnly(r.phone || "").length >= 8);

  let successCount = 0;
  const failures: string[] = [];

  for (const r of targets) {
    const to = digitsOnly(r.phone || "");
    try {
      const res = await fetch(`https://graph.facebook.com/v20.0/${META_PHONE_NUMBER_ID}/messages`, {
        method: "POST",
        headers: {
          "Authorization": `Bearer ${META_WHATSAPP_TOKEN}`,
          "Content-Type": "application/json",
        },
        body: JSON.stringify({
          messaging_product: "whatsapp",
          to,
          type: "template",
          template: {
            name: META_TEMPLATE_NAME,
            language: { code: META_TEMPLATE_LANG },
            components: [
              { type: "body", parameters: [{ type: "text", text: message }] },
            ],
          },
        }),
      });
      if (res.ok) {
        successCount++;
      } else {
        const errText = await res.text();
        failures.push(`${r.full_name || to} : ${errText.slice(0, 150)}`);
      }
    } catch (e) {
      failures.push(`${r.full_name || to} : ${String(e).slice(0, 150)}`);
    }
  }

  const { error: logErr } = await admin.from("whatsapp_broadcasts").insert({
    message,
    audience,
    sent_by: userData.user.id,
    sent_by_name: callerProfile.full_name,
    recipients_count: targets.length,
    success_count: successCount,
  });
  if (logErr) console.error("notify-members-whatsapp: échec journalisation", logErr);

  return json({
    ok: true,
    recipients_count: targets.length,
    success_count: successCount,
    failures: failures.slice(0, 20),
  });
});

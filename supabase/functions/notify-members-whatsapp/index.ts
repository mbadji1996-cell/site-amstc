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
// d'envoyer quoi que ce soit - le bouton "Verify JWT" du Dashboard doit
// rester ACTIVÉ pour cette fonction (contrairement à notify-admin).
//
// Un message WhatsApp envoyé par une entreprise en dehors d'une fenêtre
// de conversation de 24h DOIT utiliser un modèle ("template") pré-approuvé
// par WhatsApp - voir README-espace-membres.md, section "Diffusion
// WhatsApp aux membres", pour la création de ces modèles. Deux modèles
// distincts sont utilisés selon l'audience, car leur contenu relève de
// deux catégories différentes chez Meta :
//   - "tous" (annonces générales, événements) -> modèle Marketing
//   - rappels ciblés (carte/cotisation)       -> modèle Utilitaire
// Les deux utilisent un paramètre NOMMÉ "message" dans leur corps (ex :
// "Bonjour, {{message}} ..."), pas l'ancienne syntaxe positionnelle {{1}}.
//
// Secrets requis (Dashboard > Project Settings > Edge Functions > Secrets) :
//   SUPABASE_URL              - déjà fourni automatiquement par Supabase
//   SUPABASE_SERVICE_ROLE_KEY - déjà fourni automatiquement par Supabase
//   META_WHATSAPP_TOKEN       - jeton d'accès permanent Meta Cloud API
//   META_PHONE_NUMBER_ID      - identifiant du numéro expéditeur WhatsApp Business
//   META_TEMPLATE_NAME          - optionnel, défaut "nouvelle_annonce" (Marketing, audience "tous")
//   META_TEMPLATE_NAME_RAPPEL   - optionnel, défaut "rappel_compte" (Utilitaire, audiences carte/cotisation)
//   META_TEMPLATE_LANG          - optionnel, défaut "fr"

import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const SUPABASE_URL = Deno.env.get("SUPABASE_URL")!;
const SERVICE_ROLE_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
const META_WHATSAPP_TOKEN = Deno.env.get("META_WHATSAPP_TOKEN");
const META_PHONE_NUMBER_ID = Deno.env.get("META_PHONE_NUMBER_ID");
const META_TEMPLATE_NAME = Deno.env.get("META_TEMPLATE_NAME") || "nouvelle_annonce";
const META_TEMPLATE_NAME_RAPPEL = Deno.env.get("META_TEMPLATE_NAME_RAPPEL") || "rappel_compte";
const META_TEMPLATE_LANG = Deno.env.get("META_TEMPLATE_LANG") || "fr";
// Facultatif, et seulement pour le mode « vérifier » : les modèles
// appartiennent au compte WhatsApp Business, pas au numéro. Sans lui, la
// diffusion fonctionne normalement - seul l'état des modèles reste
// invisible.
const META_WABA_ID = Deno.env.get("META_WABA_ID");

// Audiences servies par le modèle « rappel » plutôt que par le modèle
// d'alerte générale. « carte_jamais_reclamee » (phase 93) vise le
// REGISTRE et non les profils : des membres connus sur le papier qui
// n'ont jamais créé de compte. Son ciblage est fait en SQL, qui rend
// déjà le numéro au format international.
const REMINDER_AUDIENCES = [
  "carte_expiree", "carte_expire_bientot", "cotisation_impayee", "carte_jamais_reclamee",
];

function templateNameFor(audience: string): string {
  return REMINDER_AUDIENCES.includes(audience) ? META_TEMPLATE_NAME_RAPPEL : META_TEMPLATE_NAME;
}

const CORS_HEADERS = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, content-type, apikey, x-client-info",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

function digitsOnly(phone: string): string {
  return String(phone || "").replace(/[^0-9]/g, "");
}

// ============================================================
// MODE « VÉRIFIER » - lecture seule, aucun envoi
// ============================================================
async function meta(chemin: string): Promise<Record<string, unknown>> {
  const res = await fetch(`https://graph.facebook.com/v20.0/${chemin}`, {
    headers: { Authorization: `Bearer ${META_WHATSAPP_TOKEN}` },
  });
  const corps = await res.json().catch(() => ({}));
  if (!res.ok) {
    const e = (corps as { error?: { message?: string } })?.error || {};
    throw new Error(e.message || `HTTP ${res.status}`);
  }
  return corps as Record<string, unknown>;
}

async function verifierConfiguration(): Promise<Record<string, unknown>> {
  const rapport: Record<string, unknown> = {
    secrets: {
      META_WHATSAPP_TOKEN: !!META_WHATSAPP_TOKEN,
      META_PHONE_NUMBER_ID: !!META_PHONE_NUMBER_ID,
      META_WABA_ID: !!META_WABA_ID,
    },
    attendus: {
      annonce: META_TEMPLATE_NAME,
      rappel: META_TEMPLATE_NAME_RAPPEL,
      langue: META_TEMPLATE_LANG,
    },
  };

  if (!META_WHATSAPP_TOKEN || !META_PHONE_NUMBER_ID) {
    rapport.numero = { erreur: "Posez d'abord le jeton et l'identifiant du numéro." };
    rapport.modeles = { erreur: "Rien ne peut être lu chez Meta sans le jeton." };
    return rapport;
  }

  try {
    const n = await meta(
      `${META_PHONE_NUMBER_ID}?fields=display_phone_number,verified_name,quality_rating,platform_type`,
    );
    rapport.numero = {
      numero: n.display_phone_number,
      nom_verifie: n.verified_name,
      qualite: n.quality_rating,
      plateforme: n.platform_type,
    };
  } catch (e) {
    rapport.numero = { erreur: String((e as Error).message || e) };
  }

  if (!META_WABA_ID) {
    rapport.modeles = {
      erreur: "META_WABA_ID n'est pas défini. Les modèles appartiennent au compte "
        + "WhatsApp Business : sans son identifiant, leur état ne peut pas être lu.",
    };
    return rapport;
  }

  try {
    const rep = await meta(
      `${META_WABA_ID}/message_templates?fields=name,status,category,language&limit=200`,
    );
    const tous = ((rep.data as Array<Record<string, string>>) || []);
    const retenir = (nom: string) =>
      tous.filter((m) => m.name === nom)
          .map((m) => ({ nom: m.name, statut: m.status, categorie: m.category, langue: m.language }));
    rapport.modeles = {
      annonce: retenir(META_TEMPLATE_NAME),
      rappel: retenir(META_TEMPLATE_NAME_RAPPEL),
      total: tous.length,
    };
  } catch (e) {
    // « lire les modèles » exige whatsapp_business_management, que
    // « envoyer » n'exige pas : on le dit, plutôt que de laisser croire
    // que les modèles n'existent pas.
    rapport.modeles = {
      erreur: String((e as Error).message || e),
      indice: "Lire les modèles exige la permission whatsapp_business_management, "
        + "distincte de whatsapp_business_messaging utilisée pour envoyer.",
    };
  }

  return rapport;
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

  // L'identité est vérifiée AVANT l'état de la configuration : sans cela,
  // n'importe qui apprenait si les secrets Meta sont posés, et le message
  // détaillé ci-dessous serait lisible sans être administrateur.
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

  // Le mode « vérifier » passe AVANT le contrôle des secrets : ce
  // contrôle répond 500, alors qu'ici l'absence d'un secret est
  // précisément ce que l'on vient constater.
  let sonde: { verifier?: boolean } = {};
  try { sonde = await req.clone().json(); } catch { /* traité plus bas */ }
  if (sonde.verifier === true) {
    return json({ verification: await verifierConfiguration() });
  }

  // Le secret manquant est nommé : « Configuration serveur incomplète »
  // obligeait à chercher lequel des deux à l'aveugle, dans une interface
  // Coolify où ils ne sont pas côte à côte.
  const secretsManquants = [
    !META_WHATSAPP_TOKEN ? "META_WHATSAPP_TOKEN" : null,
    !META_PHONE_NUMBER_ID ? "META_PHONE_NUMBER_ID" : null,
  ].filter(Boolean);
  if (secretsManquants.length) {
    console.error("notify-members-whatsapp : secrets manquants -", secretsManquants.join(", "));
    return json({
      error: "Configuration WhatsApp incomplète : " + secretsManquants.join(" et ")
        + " " + (secretsManquants.length > 1 ? "ne sont pas définis" : "n'est pas défini")
        + " sur le service edge-functions.",
    }, 500);
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
  const KNOWN_AUDIENCES = ["tous", ...REMINDER_AUDIENCES];
  if (!KNOWN_AUDIENCES.includes(audience)) {
    return json({ error: `Audience inconnue : ${audience}` }, 400);
  }
  const templateName = templateNameFor(audience);

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
            name: templateName,
            language: { code: META_TEMPLATE_LANG },
            components: [
              { type: "body", parameters: [{ type: "text", parameter_name: "message", text: message }] },
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

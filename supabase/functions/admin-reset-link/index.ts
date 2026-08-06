// supabase/functions/admin-reset-link/index.ts
//
// Génère le lien de réinitialisation de mot de passe d'un membre, l'envoie
// par e-mail, et le renvoie à l'admin pour qu'il puisse aussi le
// transmettre par WhatsApp.
//
// Appelée directement depuis le navigateur (membres/validation.html) avec
// le jeton de session de l'admin connecté, comme
// provision-consultation-user : la fonction vérifie elle-même que
// l'appelant est admin/super_admin.
//
// POURQUOI UNE FONCTION PLUTÔT QUE resetPasswordForEmail :
// resetPasswordForEmail envoie le mail sans jamais exposer le lien, donc
// rien à transmettre par WhatsApp. Et surtout, GoTrue ne conserve QU'UN
// SEUL jeton de récupération par compte : appeler resetPasswordForEmail
// puis generateLink (ou l'inverse) invaliderait le premier des deux liens.
// Le membre aurait alors reçu deux liens dont un mort, sans moyen de
// savoir lequel. On génère donc le lien UNE FOIS, et on le diffuse sur les
// deux canaux - même jeton, les deux fonctionnent.
//
// Effet de bord utile : l'e-mail part par Resend, pas par le SMTP de
// l'instance. Il arrive donc même si le SMTP de GoTrue n'est pas
// configuré, ce qui était le cas des notifications admin avant phase25.
//
// Secrets requis (variables d'environnement du service edge-functions) :
//   SUPABASE_URL              - fourni automatiquement
//   SUPABASE_SERVICE_ROLE_KEY - fourni automatiquement
//   RESEND_API_KEY            - clé API Resend (déjà utilisée par notify-admin)
//   NOTIFY_FROM_EMAIL         - optionnel, adresse d'expédition

import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const SUPABASE_URL = Deno.env.get("SUPABASE_URL")!;
const SERVICE_ROLE_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
const RESEND_API_KEY = Deno.env.get("RESEND_API_KEY");
const FROM_EMAIL = Deno.env.get("NOTIFY_FROM_EMAIL") || "AMSTC <onboarding@resend.dev>";

const CORS_HEADERS = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, content-type, apikey, x-client-info",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

function json(body: Record<string, unknown>, status = 200) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...CORS_HEADERS, "Content-Type": "application/json" },
  });
}

function esc(v: unknown): string {
  return String(v ?? "").replace(
    /[<>&]/g,
    (c) => ({ "<": "&lt;", ">": "&gt;", "&": "&amp;" } as Record<string, string>)[c],
  );
}

// L'admin choisit la page de retour, mais on ne relaie pas n'importe quelle
// URL : un lien de récupération pointant vers un domaine tiers y enverrait
// le jeton du membre.
const REDIRECT_ALLOWED = /^https?:\/\/[^\/]+\/(?:[^?#]*\/)?reinitialiser\.html$/;

Deno.serve(async (req: Request) => {
  if (req.method === "OPTIONS") return new Response(null, { headers: CORS_HEADERS });
  if (req.method !== "POST") return json({ error: "Méthode non autorisée" }, 405);

  // ===== 1. L'appelant est-il un admin de l'espace membres ? =====
  const jwt = (req.headers.get("authorization") || "").replace(/^Bearer /, "");
  if (!jwt) return json({ error: "Non authentifié" }, 401);

  const admin = createClient(SUPABASE_URL, SERVICE_ROLE_KEY);
  const { data: userData, error: userErr } = await admin.auth.getUser(jwt);
  if (userErr || !userData?.user) return json({ error: "Session invalide" }, 401);

  const { data: caller } = await admin
    .from("profiles")
    .select("role, is_active")
    .eq("id", userData.user.id)
    .single();
  if (!caller || !["admin", "super_admin"].includes(caller.role) || caller.is_active === false) {
    return json({ error: "Réservé aux administrateurs" }, 403);
  }

  // ===== 2. Membre visé =====
  let payload: { member_id?: string; redirect_to?: string };
  try {
    payload = await req.json();
  } catch {
    return json({ error: "JSON invalide" }, 400);
  }

  const memberId = String(payload.member_id || "").trim();
  if (!memberId) return json({ error: "member_id manquant" }, 400);

  const redirectTo = String(payload.redirect_to || "").trim();
  if (!REDIRECT_ALLOWED.test(redirectTo)) {
    return json({ error: "Page de retour non autorisée" }, 400);
  }

  const { data: member, error: memberErr } = await admin
    .from("profiles")
    .select("id, email, full_name, first_name, phone")
    .eq("id", memberId)
    .single();
  if (memberErr || !member) return json({ error: "Membre introuvable" }, 404);
  if (!member.email) return json({ error: "Ce membre n'a pas d'adresse e-mail" }, 400);

  // ===== 3. Un seul lien, deux canaux =====
  const { data: linkData, error: linkErr } = await admin.auth.admin.generateLink({
    type: "recovery",
    email: member.email,
    options: { redirectTo },
  });

  if (linkErr || !linkData?.properties?.action_link) {
    console.error("admin-reset-link: échec generateLink", linkErr?.message);
    return json({ error: "Impossible de générer le lien : " + (linkErr?.message || "réponse vide") }, 502);
  }

  const actionLink = linkData.properties.action_link;

  // ===== 4. Envoi de l'e-mail =====
  // Un échec d'envoi n'annule pas la génération : le lien reste valide et
  // l'admin peut le transmettre par WhatsApp. On le signale seulement.
  let emailSent = false;
  let emailError: string | null = null;

  if (!RESEND_API_KEY) {
    emailError = "RESEND_API_KEY manquant côté serveur";
  } else {
    const prenom = member.first_name || member.full_name || "";
    const res = await fetch("https://api.resend.com/emails", {
      method: "POST",
      headers: {
        "Authorization": `Bearer ${RESEND_API_KEY}`,
        "Content-Type": "application/json",
      },
      body: JSON.stringify({
        from: FROM_EMAIL,
        to: [member.email],
        subject: "Réinitialisation de votre mot de passe AMSTC",
        html: `
          <p>Bonjour ${esc(prenom)},</p>
          <p>Voici votre lien pour définir un nouveau mot de passe sur l'espace membres de l'AMSTC :</p>
          <p><a href="${esc(actionLink)}">Définir mon mot de passe</a></p>
          <p>Ce lien est personnel et expire rapidement : utilisez-le sans tarder.
             Si vous n'êtes pas à l'origine de cette demande, ignorez ce message.</p>
          <p>- L'AMSTC</p>
        `,
      }),
    });

    if (res.ok) {
      emailSent = true;
    } else {
      emailError = await res.text();
      console.error("admin-reset-link: échec envoi Resend", res.status, emailError);
    }
  }

  return json({
    ok: true,
    action_link: actionLink,
    email: member.email,
    phone: member.phone || null,
    first_name: member.first_name || null,
    full_name: member.full_name || null,
    email_sent: emailSent,
    email_error: emailError,
  });
});

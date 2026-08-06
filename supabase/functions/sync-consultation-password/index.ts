// supabase/functions/sync-consultation-password/index.ts
//
// Recopie le mot de passe amstc.org d'un membre vers son compte
// consultations-amstc.org, pour tenir la promesse « même e-mail, même mot
// de passe » APRÈS une réinitialisation.
//
// Contexte : à la création de l'accès consultations
// (provision-consultation-user), l'empreinte bcrypt du mot de passe amstc
// est copiée une fois. C'est une photocopie, pas un lien : un mot de passe
// réinitialisé ensuite sur amstc.org laissait consultations sur l'ancien.
// Cette fonction refait la copie au moment du changement.
//
// Appelée par membres/reinitialiser.html juste après la mise à jour du mot
// de passe, avec la session du membre lui-même (session de récupération) :
// chacun ne peut synchroniser QUE son propre compte, la cible est lue dans
// son profil (consultation_user_id), jamais dans la requête.
//
// Sens unique amstc -> consultations, par conception : la consigne donnée
// aux membres est de gérer leur mot de passe sur amstc.org.
//
// Deux stratégies, dans l'ordre :
//   1. copie de l'empreinte bcrypt (via consultation_password_hash, phase38,
//      réservée au service_role) : le mot de passe en clair n'est pas relu ;
//   2. si l'instance consultations refuse password_hash en mise à jour
//      (versions GoTrue plus anciennes), repli sur le nouveau mot de passe
//      en clair transmis par la page (new_password) - même exposition
//      qu'un formulaire de connexion, uniquement via HTTPS.
//
// Membre sans compte consultations lié : la fonction répond ok sans rien
// faire - la page peut appeler sans se poser de question.
//
// Secrets requis (variables d'environnement du service edge-functions) :
//   SUPABASE_URL              - fourni automatiquement (instance amstc)
//   SUPABASE_SERVICE_ROLE_KEY - fourni automatiquement (instance amstc)
//   CONSULT_SUPABASE_URL      - https://api.consultations-amstc.org
//   CONSULT_SERVICE_ROLE_KEY  - clé service_role de l'instance consultations
//   (les deux derniers sont déjà en place pour provision-consultation-user)

import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const SUPABASE_URL = Deno.env.get("SUPABASE_URL")!;
const SERVICE_ROLE_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
const CONSULT_URL = Deno.env.get("CONSULT_SUPABASE_URL");
const CONSULT_KEY = Deno.env.get("CONSULT_SERVICE_ROLE_KEY");

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

Deno.serve(async (req: Request) => {
  if (req.method === "OPTIONS") return new Response(null, { headers: CORS_HEADERS });
  if (req.method !== "POST") return json({ error: "Méthode non autorisée" }, 405);

  if (!CONSULT_URL || !CONSULT_KEY) {
    console.error("sync-consultation-password: secrets CONSULT_SUPABASE_URL / CONSULT_SERVICE_ROLE_KEY manquants");
    return json({ error: "Configuration serveur incomplète" }, 500);
  }

  // ===== 1. Identifier le membre par SA session =====
  const jwt = (req.headers.get("authorization") || "").replace(/^Bearer /, "");
  if (!jwt) return json({ error: "Non authentifié" }, 401);

  const amstc = createClient(SUPABASE_URL, SERVICE_ROLE_KEY);
  const { data: userData, error: userErr } = await amstc.auth.getUser(jwt);
  if (userErr || !userData?.user) return json({ error: "Session invalide" }, 401);
  const userId = userData.user.id;

  // ===== 2. A-t-il un compte consultations lié ? =====
  const { data: profile } = await amstc
    .from("profiles")
    .select("consultation_user_id")
    .eq("id", userId)
    .single();

  if (!profile?.consultation_user_id) {
    // Rien à synchroniser : réponse tranquille, la page appelle sans filtre.
    return json({ ok: true, synced: false });
  }

  // ===== 3. Nouveau mot de passe en clair (repli éventuel) =====
  let newPassword: string | null = null;
  try {
    const payload = await req.json();
    if (typeof payload?.new_password === "string" && payload.new_password.length >= 8) {
      newPassword = payload.new_password;
    }
  } catch (_) { /* corps vide accepté : la copie d'empreinte reste possible */ }

  // ===== 4. Stratégie 1 : copier l'empreinte bcrypt =====
  let passwordHash: string | null = null;
  {
    const { data: hashData, error: hashErr } = await amstc.rpc("consultation_password_hash", {
      target_user_id: userId,
    });
    if (hashErr) console.error("sync-consultation-password: échec lecture empreinte", hashErr.message);
    if (typeof hashData === "string" && hashData.startsWith("$2")) passwordHash = hashData;
  }

  const consult = createClient(CONSULT_URL, CONSULT_KEY);

  if (passwordHash) {
    const { error: hashUpdateErr } = await consult.auth.admin.updateUserById(
      profile.consultation_user_id,
      { password_hash: passwordHash } as Record<string, unknown>,
    );
    if (!hashUpdateErr) return json({ ok: true, synced: true, via: "hash" });
    console.error("sync-consultation-password: échec via empreinte, tentative en clair", hashUpdateErr.message);
  }

  // ===== 5. Stratégie 2 : repli sur le mot de passe en clair =====
  if (newPassword) {
    const { error: pwUpdateErr } = await consult.auth.admin.updateUserById(
      profile.consultation_user_id,
      { password: newPassword },
    );
    if (!pwUpdateErr) return json({ ok: true, synced: true, via: "password" });
    console.error("sync-consultation-password: échec mise à jour consultations", pwUpdateErr.message);
    return json({ error: "La synchronisation vers consultations a échoué" }, 502);
  }

  return json({ error: "Impossible de synchroniser (empreinte indisponible)" }, 502);
});

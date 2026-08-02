// supabase/functions/provision-consultation-user/index.ts
//
// Crée, pour un membre soignant validé de l'espace membres, un compte sur
// la plateforme de consultations (consultations-amstc.org, instance
// Supabase DISTINCTE), sans double saisie : prénom, nom, e-mail, téléphone
// et profession sont recopiés depuis son profil amstc.org.
//
// Appelée directement depuis le navigateur (membres/validation.html) avec
// le jeton de session de l'admin connecté, comme notify-members-whatsapp :
// la fonction vérifie elle-même que l'appelant est admin/super_admin.
//
// Garde-fous voulus par le bureau :
//   - le compte créé arrive INACTIF et SANS site : l'habilitation reste
//     une décision explicite du supra-admin des consultations, jamais un
//     effet de bord de l'adhésion (données de santé oblige) ;
//   - seuls les domaines de santé sont provisionnables ;
//   - la fonction renvoie un lien "définir mon mot de passe" que l'admin
//     transmet au membre (WhatsApp) : rien ne dépend d'un serveur SMTP.
//
// Secrets requis (variables d'environnement du service edge-functions) :
//   SUPABASE_URL              - fourni automatiquement (instance amstc)
//   SUPABASE_SERVICE_ROLE_KEY - fourni automatiquement (instance amstc)
//   CONSULT_SUPABASE_URL      - https://api.consultations-amstc.org
//   CONSULT_SERVICE_ROLE_KEY  - clé service_role de l'instance consultations
//                               (accès TOTAL à la base de santé : ne doit
//                               vivre QUE dans ces secrets serveur)

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

// ===== Correspondance domaine/spécialité (amstc) -> profession (consultations)
//
// Côté consultations, "specialite" est la profession (generaliste, dentiste,
// specialiste, sage_femme, infirmier, pharmacien) et "specialite_detail" ne
// sert qu'aux spécialistes. Décisions validées par le bureau :
//   - Médecine + "Médecine générale" -> generaliste
//   - Médecine + autre spécialité    -> specialiste (+ détail traduit)
//   - Soins obstétricaux             -> sage_femme
//   - "Santé publique" est passée telle quelle en détail de spécialiste.
const SPECIALTY_RENAMES: Record<string, string> = {
  "Gynécologie-Obstétrique": "Gynécologie-obstétrique",
  "Anesthésie-Réanimation": "Anesthésie-réanimation",
  "ORL": "ORL (oto-rhino-laryngologie)",
  "Radiologie": "Radiologie et imagerie médicale",
  "Endocrinologie": "Endocrinologie et diabétologie",
  "Gastro-entérologie": "Gastro-entérologie et hépatologie",
};

function mapToConsultation(domain: string, specialty: string | null): { specialite: string; specialite_detail: string | null } | null {
  switch (domain) {
    case "medecine": {
      const s = (specialty || "").trim();
      if (!s || s === "Médecine générale") return { specialite: "generaliste", specialite_detail: null };
      return { specialite: "specialiste", specialite_detail: SPECIALTY_RENAMES[s] || s };
    }
    case "pharmacie":
      return { specialite: "pharmacien", specialite_detail: null };
    case "odontologie":
      return { specialite: "dentiste", specialite_detail: null };
    case "soins_infirmiers":
      return { specialite: "infirmier", specialite_detail: null };
    case "soins_obstetricaux":
      return { specialite: "sage_femme", specialite_detail: null };
    default:
      return null; // domaine non médical : pas de provisionnement automatique
  }
}

function randomPassword(): string {
  // Mot de passe jetable jamais communiqué : le membre définit le sien via
  // le lien de récupération renvoyé à l'admin.
  const bytes = new Uint8Array(24);
  crypto.getRandomValues(bytes);
  return btoa(String.fromCharCode(...bytes));
}

Deno.serve(async (req: Request) => {
  if (req.method === "OPTIONS") return new Response(null, { headers: CORS_HEADERS });
  if (req.method !== "POST") return json({ error: "Méthode non autorisée" }, 405);

  // Fail-closed : sans la configuration de l'instance consultations, on
  // refuse tout plutôt que d'échouer à moitié.
  if (!CONSULT_URL || !CONSULT_KEY) {
    console.error("provision-consultation-user: secrets CONSULT_SUPABASE_URL / CONSULT_SERVICE_ROLE_KEY manquants");
    return json({ error: "Configuration serveur incomplète" }, 500);
  }

  // ===== 1. L'appelant est-il un admin de l'espace membres ? =====
  const jwt = (req.headers.get("authorization") || "").replace(/^Bearer /, "");
  if (!jwt) return json({ error: "Non authentifié" }, 401);

  const amstc = createClient(SUPABASE_URL, SERVICE_ROLE_KEY);
  const { data: userData, error: userErr } = await amstc.auth.getUser(jwt);
  if (userErr || !userData?.user) return json({ error: "Session invalide" }, 401);

  const { data: caller } = await amstc
    .from("profiles")
    .select("role, is_active")
    .eq("id", userData.user.id)
    .single();
  if (!caller || !["admin", "super_admin"].includes(caller.role) || caller.is_active === false) {
    return json({ error: "Réservé aux administrateurs" }, 403);
  }

  // ===== 2. Le membre visé est-il provisionnable ? =====
  let payload: { member_id?: string };
  try {
    payload = await req.json();
  } catch {
    return json({ error: "JSON invalide" }, 400);
  }
  const memberId = String(payload.member_id || "").trim();
  if (!memberId) return json({ error: "member_id manquant" }, 400);

  const { data: member, error: memberErr } = await amstc
    .from("profiles")
    .select("id, email, first_name, last_name, full_name, phone, domain, specialty, status, is_active, consultation_user_id")
    .eq("id", memberId)
    .single();
  if (memberErr || !member) return json({ error: "Membre introuvable" }, 404);
  if (member.status !== "approved") return json({ error: "Ce membre n'est pas encore approuvé" }, 400);
  if (member.is_active === false) return json({ error: "Ce compte membre est désactivé" }, 400);
  if (!member.email) return json({ error: "Ce membre n'a pas d'adresse e-mail" }, 400);
  if (member.consultation_user_id) return json({ error: "Un accès consultations existe déjà pour ce membre" }, 409);

  const mapping = mapToConsultation(member.domain || "", member.specialty);
  if (!mapping) {
    return json({ error: "Ce domaine n'ouvre pas droit à un accès consultations (réservé aux soignants)" }, 400);
  }

  const prenom = (member.first_name || "").trim() || (member.full_name || "").split(" ")[0] || "";
  const nom = (member.last_name || "").trim() || (member.full_name || "").split(" ").slice(1).join(" ") || "";

  // ===== 3. Création du compte sur l'instance consultations =====
  const consult = createClient(CONSULT_URL, CONSULT_KEY);
  const email = member.email.trim().toLowerCase();
  let consultUserId: string | null = null;
  let alreadyExisted = false;

  const { data: created, error: createErr } = await consult.auth.admin.createUser({
    email,
    password: randomPassword(),
    email_confirm: true,
    // Le déclencheur serveur de l'instance consultations construit la ligne
    // profiles depuis ces métadonnées, comme lors d'une inscription normale.
    user_metadata: {
      prenom,
      nom,
      telephone: member.phone || null,
      specialite: mapping.specialite,
      specialite_detail: mapping.specialite_detail,
    },
  });

  if (createErr) {
    const msg = String(createErr.message || "");
    if (/already|exist|registered|duplicate/i.test(msg)) {
      // Un compte existe déjà là-bas avec cet e-mail (créé à la main avant
      // cette liaison) : on le retrouve pour le rattacher au lieu d'échouer.
      alreadyExisted = true;
      const { data: page } = await consult.auth.admin.listUsers({ page: 1, perPage: 1000 });
      const existing = (page?.users || []).find((u) => (u.email || "").toLowerCase() === email);
      if (!existing) {
        console.error("provision-consultation-user: compte existant introuvable via listUsers", email);
        return json({ error: "Un compte existe déjà côté consultations mais n'a pas pu être retrouvé" }, 500);
      }
      consultUserId = existing.id;
    } else {
      console.error("provision-consultation-user: échec createUser", msg);
      return json({ error: "Échec de la création du compte consultations" }, 502);
    }
  } else {
    consultUserId = created!.user.id;
  }

  // ===== 4. Fiche praticien : compléter sans jamais habiliter =====
  // On renseigne l'identité si elle manque, mais on ne touche NI à actif,
  // NI à site_id, NI à role : l'activation reste au supra-admin.
  const { data: consultProfile } = await consult
    .from("profiles")
    .select("id")
    .eq("id", consultUserId)
    .maybeSingle();
  if (consultProfile) {
    await consult
      .from("profiles")
      .update({
        prenom,
        nom,
        telephone: member.phone || null,
        specialite: mapping.specialite,
        specialite_detail: mapping.specialite_detail,
      })
      .eq("id", consultUserId);
  } else if (!alreadyExisted) {
    // Filet si le déclencheur n'a pas créé la ligne : insertion minimale,
    // sans "actif" (le défaut de la table, inactif, s'applique).
    await consult.from("profiles").insert({
      id: consultUserId,
      prenom,
      nom,
      telephone: member.phone || null,
      specialite: mapping.specialite,
      specialite_detail: mapping.specialite_detail,
      role: "agent",
    });
  }

  // ===== 5. Lien "définir mon mot de passe" =====
  // Type recovery : ouvre l'écran de nouveau mot de passe de l'application
  // consultations (flux type=recovery déjà géré par son code). Transmis par
  // l'admin au membre, généralement via WhatsApp.
  let actionLink: string | null = null;
  if (!alreadyExisted) {
    const { data: linkData, error: linkErr } = await consult.auth.admin.generateLink({
      type: "recovery",
      email,
    });
    if (linkErr) console.error("provision-consultation-user: échec generateLink", linkErr.message);
    actionLink = linkData?.properties?.action_link || null;
  }

  // ===== 6. Traçabilité côté espace membres =====
  const { error: linkSaveErr } = await amstc
    .from("profiles")
    .update({ consultation_user_id: consultUserId, consultation_linked_at: new Date().toISOString() })
    .eq("id", member.id);
  if (linkSaveErr) console.error("provision-consultation-user: échec de la traçabilité", linkSaveErr.message);

  return json({
    ok: true,
    already_existed: alreadyExisted,
    consultation_user_id: consultUserId,
    action_link: actionLink,
  });
});

// ===== Configuration Supabase =====
// Remplacez ces deux valeurs par celles de votre projet Supabase
// (Dashboard > Project Settings > API). Voir README-espace-membres.md.
// La clé "anon" est conçue pour être visible côté client : la sécurité
// vient des règles RLS Postgres (voir supabase/schema.sql), pas du secret
// de cette clé.
const SUPABASE_URL = "https://qcdhtynqhpydtqnptvmo.supabase.co";
const SUPABASE_ANON_KEY = "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InFjZGh0eW5xaHB5ZHRxbnB0dm1vIiwicm9sZSI6ImFub24iLCJpYXQiOjE3ODQxMTYyMjUsImV4cCI6MjA5OTY5MjIyNX0.9PSZT4KmvKueqBxAW2ojpiB97PpZFCO_s1bLROWpTj4";

const supabaseClient = supabase.createClient(SUPABASE_URL, SUPABASE_ANON_KEY);

// ===== Aide partagée entre les pages membres/*.html =====

/**
 * Récupère le profil (role, status...) du compte actuellement connecté.
 * Retourne null si personne n'est connecté.
 */
async function getCurrentProfile() {
  const { data: { session } } = await supabaseClient.auth.getSession();
  if (!session) return null;
  const { data, error } = await supabaseClient
    .from("profiles")
    .select("*")
    .eq("id", session.user.id)
    .single();
  if (error) return null;
  return data;
}

/**
 * Protège une page membre : redirige vers la connexion si personne n'est
 * connecté ou si le compte n'est pas encore approuvé.
 */
async function requireApprovedMember(redirectTo = "connexion.html") {
  const profile = await getCurrentProfile();
  if (!profile || profile.status !== "approved" || profile.is_active === false) {
    window.location.href = redirectTo;
    return null;
  }
  return profile;
}

/**
 * Protège une page d'administration : redirige si le compte connecté n'a
 * pas le rôle admin/super_admin.
 */
async function requireAdmin(redirectTo = "connexion.html") {
  const profile = await getCurrentProfile();
  if (!profile || !["admin", "super_admin"].includes(profile.role) || profile.is_active === false) {
    window.location.href = redirectTo;
    return null;
  }
  return profile;
}

/**
 * Protège une page réservée au Super Administrateur uniquement.
 */
async function requireSuperAdmin(redirectTo = "connexion.html") {
  const profile = await getCurrentProfile();
  if (!profile || profile.role !== "super_admin" || profile.is_active === false) {
    window.location.href = redirectTo;
    return null;
  }
  return profile;
}

/**
 * Lit l'interrupteur global de restriction (table app_settings, une seule
 * ligne). Tant qu'il est désactivé, la coupure d'accès en cas de carte
 * expirée depuis 2 mois ne s'applique jamais (le rappel visuel reste
 * affiché). Retourne false si la table est vide/inaccessible.
 */
async function isCardRestrictionActive() {
  const { data } = await supabaseClient
    .from("app_settings")
    .select("restriction_cartes_active")
    .limit(1)
    .maybeSingle();
  return !!(data && data.restriction_cartes_active);
}

/**
 * Calcule l'état de validité de la carte d'un membre, en miroir de la
 * fonction SQL is_active_member() (voir supabase/phase10-restriction-cartes-expirees.sql).
 * card_valid_until est une année : la carte valable jusqu'en année N expire
 * le 1er janvier N+1, et le délai de grâce de 2 mois se termine le 1er mars N+1.
 * Retourne 'none' (jamais restreint, carte pas encore confirmée), 'valid',
 * 'grace' (expirée : bandeau de rappel, mais accès encore ouvert - soit
 * parce qu'on est dans les 2 mois de grâce, soit parce que l'interrupteur
 * global de restriction est désactivé) ou 'blocked' (coupure effective,
 * seulement possible si l'interrupteur est activé).
 */
function cardActiveState(profile, restrictionActive) {
  const cvu = profile && profile.card_valid_until;
  if (!cvu) return "none";
  const now = new Date();
  const expiresAt = new Date(cvu + 1, 0, 1); // 1er janvier N+1
  if (now < expiresAt) return "valid";
  if (!restrictionActive) return "grace";
  const graceEndsAt = new Date(cvu + 1, 2, 1); // 1er mars N+1
  return now < graceEndsAt ? "grace" : "blocked";
}

/**
 * Comme requireApprovedMember(), mais renvoie aussi l'état de validité de
 * la carte (cardActiveState) sans rediriger sur ce critère : le blocage
 * des contenus réservés se gère page par page (message explicite), pas par
 * une redirection globale.
 */
async function requireActiveMember(redirectTo = "connexion.html") {
  const profile = await requireApprovedMember(redirectTo);
  if (!profile) return null;
  const restrictionActive = await isCardRestrictionActive();
  return { profile, state: cardActiveState(profile, restrictionActive) };
}

async function signOut() {
  await supabaseClient.auth.signOut();
}

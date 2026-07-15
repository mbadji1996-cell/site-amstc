// ===== Configuration Supabase =====
// Remplacez ces deux valeurs par celles de votre projet Supabase
// (Dashboard > Project Settings > API). Voir README-espace-membres.md.
// La clé "anon" est conçue pour être visible côté client : la sécurité
// vient des règles RLS Postgres (voir supabase/schema.sql), pas du secret
// de cette clé.
const SUPABASE_URL = "https://VOTRE-PROJET.supabase.co";
const SUPABASE_ANON_KEY = "VOTRE_CLE_ANON";

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
  if (!profile || profile.status !== "approved") {
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
  if (!profile || !["admin", "super_admin"].includes(profile.role)) {
    window.location.href = redirectTo;
    return null;
  }
  return profile;
}

async function signOut() {
  await supabaseClient.auth.signOut();
}

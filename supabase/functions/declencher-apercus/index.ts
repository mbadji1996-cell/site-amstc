// supabase/functions/declencher-apercus/index.ts
//
// Déclenche la construction des pages d'aperçu de partage (/c/, /a/, /f/…)
// sans attendre le passage horaire.
//
// POURQUOI. Les cours du Daara et les leçons médicales vivent dans
// Supabase, pas dans le dépôt : aucun push ne signale leur publication.
// Un travail programmé passe donc toutes les heures fabriquer les pages
// manquantes, et jusqu'à son passage le bouton « Partager » refuse
// d'agir - un lien envoyé entre-temps s'afficherait sans titre ni image
// dans WhatsApp, ce que la page d'aperçu existe précisément pour éviter.
//
// Cette fonction demande à GitHub de lancer le travail tout de suite. Le
// délai passe d'une heure à environ une minute.
//
// POURQUOI UNE FONCTION PLUTÔT QU'UN APPEL DIRECT DEPUIS LA PAGE. Lancer
// un travail GitHub exige un jeton d'accès. Placé dans le code du site,
// il serait lisible par n'importe quel visiteur, et permettrait d'écrire
// dans le dépôt. Il reste donc ici, côté serveur, et la page n'envoie que
// la session de l'admin connecté.
//
// POURQUOI PAS UN DÉCLENCHEUR EN BASE, comme notify_admin. Il aurait
// fallu un second secret partagé entre la base et cette fonction, et
// l'écran n'aurait rien pu dire à l'admin - alors que c'est lui qui
// attend l'aperçu et veut savoir quand il sera prêt.
//
// Secrets requis (variables d'environnement du service edge-functions) :
//   SUPABASE_URL              - fourni automatiquement
//   SUPABASE_SERVICE_ROLE_KEY - fourni automatiquement
//   GITHUB_TOKEN              - jeton à portée « Actions: write » sur le dépôt
//   GITHUB_REPO               - optionnel, défaut mbadji1996-cell/site-amstc
//   GITHUB_WORKFLOW           - optionnel, défaut build-content-index.yml

import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const SUPABASE_URL = Deno.env.get("SUPABASE_URL")!;
const SERVICE_ROLE_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
const GITHUB_TOKEN = Deno.env.get("GITHUB_TOKEN");
const GITHUB_REPO = Deno.env.get("GITHUB_REPO") || "mbadji1996-cell/site-amstc";
const GITHUB_WORKFLOW = Deno.env.get("GITHUB_WORKFLOW") || "build-content-index.yml";
const BRANCHE = Deno.env.get("GITHUB_BRANCH") || "main";

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

  // ===== 2. Le jeton GitHub est-il configuré ? =====
  // Dit explicitement ce qui manque : sans cela, l'écran afficherait un
  // échec sans cause, et le passage horaire suffirait de toute façon.
  if (!GITHUB_TOKEN) {
    return json({
      error: "GITHUB_TOKEN n'est pas configuré sur l'instance.",
      repli: "L'aperçu sera fabriqué au prochain passage horaire.",
    }, 501);
  }

  // ===== 3. Demander à GitHub de lancer le travail =====
  const url = `https://api.github.com/repos/${GITHUB_REPO}/actions/workflows/${GITHUB_WORKFLOW}/dispatches`;

  let reponse: Response;
  try {
    reponse = await fetch(url, {
      method: "POST",
      headers: {
        "Authorization": `Bearer ${GITHUB_TOKEN}`,
        "Accept": "application/vnd.github+json",
        "X-GitHub-Api-Version": "2022-11-28",
        // GitHub refuse les requêtes sans User-Agent.
        "User-Agent": "amstc-declencher-apercus",
        "Content-Type": "application/json",
      },
      body: JSON.stringify({ ref: BRANCHE }),
    });
  } catch (e) {
    return json({ error: "GitHub injoignable : " + String(e) }, 502);
  }

  // 204 = accepté, sans corps. Tout le reste est un échec.
  if (reponse.status !== 204) {
    const detail = await reponse.text().catch(() => "");
    return json({
      error: `GitHub a refusé (${reponse.status})`,
      // Les causes utiles : 404 = dépôt ou fichier introuvable, ou jeton
      // sans le droit Actions ; 401 = jeton invalide ou expiré.
      detail: detail.slice(0, 300),
    }, 502);
  }

  return json({
    ok: true,
    message: "Construction lancée. L'aperçu sera prêt dans environ une minute.",
  });
});

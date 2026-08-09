// supabase/functions/sante/index.ts
//
// Sonde de santé pour la supervision externe (UptimeRobot ou équivalent).
//
// Contrairement à /auth/v1/health, qui répond 200 tant que le conteneur
// GoTrue tourne, cette fonction interroge RÉELLEMENT Postgres : elle
// détecte donc aussi une base arrêtée, saturée ou inaccessible, cas où le
// site paraît debout mais où plus aucune connexion de membre ne passe.
//
// Réponses :
//   200 {"etat":"ok", ...}       - base joignable
//   503 {"etat":"degrade", ...}  - base injoignable ou en erreur
//
// La supervision doit alerter sur tout code différent de 200.
//
// Appelable en GET avec la clé anon en paramètre d'URL
// (?apikey=...), ce que permettent les offres gratuites de supervision,
// qui ne savent pas envoyer d'en-tête personnalisé. Aucune donnée
// personnelle n'est exposée : la sonde ne renvoie que des compteurs.
//
// Secrets requis : SUPABASE_URL et SUPABASE_SERVICE_ROLE_KEY sont déjà
// fournis automatiquement à toutes les fonctions Edge.
//
// La table `profiles` existe sur les DEUX instances : le même fichier se
// déploie tel quel sur amstc et sur consultations.
//
// Déploiement : voir README-sauvegardes.md, section Supervision.

const SUPABASE_URL = Deno.env.get("SUPABASE_URL");
const SERVICE_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");

Deno.serve(async (req: Request) => {
  const debut = Date.now();

  // Le navigateur n'appelle pas cette fonction, mais un préflight coûte
  // moins cher à gérer qu'à diagnostiquer.
  if (req.method === "OPTIONS") {
    return new Response(null, {
      status: 204,
      headers: {
        "Access-Control-Allow-Origin": "*",
        "Access-Control-Allow-Headers": "authorization, apikey, content-type",
      },
    });
  }

  const entetes = {
    "Content-Type": "application/json",
    "Access-Control-Allow-Origin": "*",
    // La supervision doit voir l'état réel, jamais une réponse mise en cache.
    "Cache-Control": "no-store, max-age=0",
  };

  if (!SUPABASE_URL || !SERVICE_KEY) {
    return new Response(
      JSON.stringify({ etat: "degrade", motif: "configuration incomplete" }),
      { status: 503, headers: entetes },
    );
  }

  try {
    // Requête volontairement minimale : on ne lit aucune ligne, seulement
    // le compte exact, ce qui oblige quand même Postgres à répondre.
    const res = await fetch(
      `${SUPABASE_URL}/rest/v1/profiles?select=id&limit=1`,
      {
        headers: {
          apikey: SERVICE_KEY,
          Authorization: `Bearer ${SERVICE_KEY}`,
          Prefer: "count=exact",
          Range: "0-0",
        },
        signal: AbortSignal.timeout(8000),
      },
    );

    if (!res.ok) {
      return new Response(
        JSON.stringify({
          etat: "degrade",
          motif: "base injoignable",
          code_http: res.status,
          duree_ms: Date.now() - debut,
        }),
        { status: 503, headers: entetes },
      );
    }

    // "Content-Range: 0-0/1234" - on n'en garde que le total.
    const plage = res.headers.get("content-range") || "";
    const total = plage.includes("/") ? plage.split("/")[1] : null;

    return new Response(
      JSON.stringify({
        etat: "ok",
        base: "joignable",
        comptes: total ? Number(total) : null,
        duree_ms: Date.now() - debut,
      }),
      { status: 200, headers: entetes },
    );
  } catch (e) {
    return new Response(
      JSON.stringify({
        etat: "degrade",
        motif: String((e as Error).message || e),
        duree_ms: Date.now() - debut,
      }),
      { status: 503, headers: entetes },
    );
  }
});

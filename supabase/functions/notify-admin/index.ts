// supabase/functions/notify-admin/index.ts
//
// Fonction Edge partagée qui envoie un e-mail de notification à l'admin de
// l'AMSTC pour 5 événements : inscription, réclamation de carte, achat
// boutique, nouveau sujet de forum, demande de campagne/activité locale.
// Appelée UNIQUEMENT côté serveur par les triggers Postgres (voir
// supabase/phase25-notifications-admin.sql et phase33-demandes-campagnes.sql)
// via pg_net — jamais directement par le navigateur, donc aucune gestion
// CORS n'est nécessaire ici (pas de préflight OPTIONS à gérer).
//
// Secrets requis (Dashboard > Project Settings > Edge Functions > Secrets) :
//   RESEND_API_KEY      - clé API Resend (https://resend.com)
//   ADMIN_NOTIFY_EMAIL  - adresse qui reçoit les notifications
//   NOTIFY_ADMIN_SECRET - (optionnel mais recommandé) jeton partagé avec le
//                         trigger SQL, vérifié ci-dessous ; si absent, la
//                         vérification est simplement désactivée
//   NOTIFY_FROM_EMAIL   - optionnel, adresse d'expédition (voir note ci-dessous)
//
// IMPORTANT — Resend exige un domaine d'expédition vérifié pour envoyer
// depuis une adresse @amstc.org. Tant qu'amstc.org n'est pas vérifié dans
// Resend, seule l'adresse de test "onboarding@resend.dev" fonctionne, et
// UNIQUEMENT vers l'adresse e-mail du compte Resend lui-même (pas vers
// contact@amstc.org ni aucune autre adresse). Voir README-espace-membres.md.

const RESEND_API_KEY = Deno.env.get("RESEND_API_KEY");
const ADMIN_NOTIFY_EMAIL = Deno.env.get("ADMIN_NOTIFY_EMAIL");
const NOTIFY_ADMIN_SECRET = Deno.env.get("NOTIFY_ADMIN_SECRET");
const FROM_EMAIL = Deno.env.get("NOTIFY_FROM_EMAIL") || "AMSTC <onboarding@resend.dev>";

function esc(v: unknown): string {
  return String(v ?? "—").replace(
    /[<>&]/g,
    (c) => ({ "<": "&lt;", ">": "&gt;", "&": "&amp;" } as Record<string, string>)[c],
  );
}

function buildEmail(
  eventType: string,
  data: Record<string, any>,
): { subject: string; html: string } | null {
  switch (eventType) {
    case "inscription": {
      const kind = data.applicant_type === "nouvel_adherent" ? "Nouvel adhérent" : "Membre existant";
      return {
        subject: `Nouvelle inscription - ${esc(data.full_name)}`,
        html: `
          <h2>Nouvelle inscription sur l'espace membres AMSTC</h2>
          <p><strong>Type :</strong> ${esc(kind)}</p>
          <ul>
            <li><strong>Nom :</strong> ${esc(data.full_name)}</li>
            <li><strong>E-mail :</strong> ${esc(data.email)}</li>
            <li><strong>Téléphone :</strong> ${esc(data.phone)}</li>
            <li><strong>Domaine :</strong> ${esc(data.domain)}${data.domain_autre ? " (" + esc(data.domain_autre) + ")" : ""}</li>
            <li><strong>Spécialité :</strong> ${esc(data.specialty)}</li>
            <li><strong>Ville :</strong> ${esc(data.city)}</li>
          </ul>
          <p>À valider dans membres/validation.html.</p>
        `,
      };
    }
    case "reclamation_carte": {
      return {
        subject: `Réclamation de carte membre - ${esc(data.claimant_name)}`,
        html: `
          <h2>Réclamation de carte membre en attente</h2>
          <ul>
            <li><strong>Membre :</strong> ${esc(data.claimant_name)} (${esc(data.claimant_email)})</li>
            <li><strong>Carte réclamée :</strong> ${esc(data.card_full_name)} — n° ${esc(data.card_number)}</li>
            <li><strong>Ville / membre depuis :</strong> ${esc(data.card_city)} / ${esc(data.card_member_since)}</li>
          </ul>
          <p>À confirmer dans membres/cartes-admin.html.</p>
        `,
      };
    }
    case "achat_boutique": {
      const items = Array.isArray(data.items) ? data.items : [];
      const itemsHtml = items
        .map((it: any) => `<li>${esc(it.qty)} × ${esc(it.name)} — ${esc(it.price)} FCFA</li>`)
        .join("");
      return {
        subject: `Nouvelle commande boutique - ${esc(data.buyer_name)}`,
        html: `
          <h2>Nouvelle commande sur la Boutique AMSTC</h2>
          <ul>
            <li><strong>Acheteur :</strong> ${esc(data.buyer_name)} (${esc(data.buyer_email)})</li>
            <li><strong>Total :</strong> ${esc(data.total_fcfa)} FCFA</li>
            <li><strong>Paiement :</strong> ${esc(data.payment_method)} — réf. ${esc(data.payment_reference)}</li>
          </ul>
          <p><strong>Articles :</strong></p>
          <ul>${itemsHtml}</ul>
          <p>À traiter dans membres/boutique-admin.html.</p>
        `,
      };
    }
    case "demande_campagne": {
      return {
        subject: `Demande de campagne/activité - ${esc(data.locality)}`,
        html: `
          <h2>Nouvelle demande de campagne ou d'activité locale</h2>
          <ul>
            <li><strong>Nom :</strong> ${esc(data.full_name)}</li>
            <li><strong>Téléphone :</strong> ${esc(data.phone)}</li>
            <li><strong>E-mail :</strong> ${esc(data.email)}</li>
            <li><strong>Localité / daara :</strong> ${esc(data.locality)}</li>
          </ul>
          <p><strong>Description :</strong></p>
          <p>${esc(data.description)}</p>
          <p>À étudier dans membres/demandes-campagnes-admin.html.</p>
        `,
      };
    }
    case "nouveau_sujet_forum": {
      const bodyStr = String(data.body ?? "");
      const excerpt = bodyStr.slice(0, 200);
      return {
        subject: `Nouveau sujet forum - ${esc(data.title)}`,
        html: `
          <h2>Nouveau sujet sur le forum AMSTC</h2>
          <ul>
            <li><strong>Auteur :</strong> ${esc(data.author_name)} (${esc(data.author_email)})</li>
            <li><strong>Titre :</strong> ${esc(data.title)}</li>
          </ul>
          <p><strong>Extrait :</strong> ${esc(excerpt)}${bodyStr.length > 200 ? "…" : ""}</p>
          <p>Voir membres/forum.html.</p>
        `,
      };
    }
    default:
      return null;
  }
}

Deno.serve(async (req: Request) => {
  try {
    if (req.method !== "POST") {
      return new Response(JSON.stringify({ error: "Méthode non autorisée" }), { status: 405 });
    }

    // Vérification maison (indépendante du "Verify JWT" du dashboard, qui
    // doit être désactivé pour cette fonction — voir README-espace-membres.md).
    // Si NOTIFY_ADMIN_SECRET n'est pas défini, ce contrôle est simplement
    // ignoré (mode "sans jeton", plus simple mais moins strict).
    if (NOTIFY_ADMIN_SECRET) {
      const authHeader = req.headers.get("authorization") || "";
      if (authHeader !== `Bearer ${NOTIFY_ADMIN_SECRET}`) {
        return new Response(JSON.stringify({ error: "Non autorisé" }), { status: 401 });
      }
    }

    if (!RESEND_API_KEY || !ADMIN_NOTIFY_EMAIL) {
      console.error("notify-admin: secrets RESEND_API_KEY / ADMIN_NOTIFY_EMAIL manquants");
      return new Response(JSON.stringify({ error: "Configuration serveur incomplète" }), { status: 500 });
    }

    let payload: Record<string, any>;
    try {
      payload = await req.json();
    } catch {
      return new Response(JSON.stringify({ error: "JSON invalide" }), { status: 400 });
    }

    const { event_type, ...data } = payload;
    const email = buildEmail(event_type, data);
    if (!email) {
      return new Response(JSON.stringify({ error: `event_type inconnu: ${event_type}` }), { status: 400 });
    }

    const resendRes = await fetch("https://api.resend.com/emails", {
      method: "POST",
      headers: {
        "Authorization": `Bearer ${RESEND_API_KEY}`,
        "Content-Type": "application/json",
      },
      body: JSON.stringify({
        from: FROM_EMAIL,
        to: [ADMIN_NOTIFY_EMAIL],
        subject: email.subject,
        html: email.html,
      }),
    });

    if (!resendRes.ok) {
      const errText = await resendRes.text();
      console.error("notify-admin: échec envoi Resend", resendRes.status, errText);
      // On répond quand même avec un code d'erreur normal : pg_net ne relit
      // jamais ce corps de réponse, donc ceci ne bloque rien côté Postgres.
      return new Response(JSON.stringify({ error: "Échec de l'envoi", detail: errText }), { status: 502 });
    }

    return new Response(JSON.stringify({ ok: true }), {
      status: 200,
      headers: { "Content-Type": "application/json" },
    });
  } catch (err) {
    console.error("notify-admin: erreur inattendue", err);
    return new Response(JSON.stringify({ error: "Erreur interne" }), { status: 500 });
  }
});

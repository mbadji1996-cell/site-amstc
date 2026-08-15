// supabase/functions/notify-admin/index.ts
//
// Fonction Edge partagée qui notifie l'administration de l'AMSTC pour
// 8 événements : inscription, réclamation de carte, achat boutique,
// nouveau sujet de forum, demande de campagne/activité locale, et depuis
// la phase 79 les trois paiements - validité de carte, cotisations,
// participation à une collecte.
// Appelée UNIQUEMENT côté serveur par les triggers Postgres (voir
// supabase/phase25-notifications-admin.sql et phase33-demandes-campagnes.sql)
// via pg_net - jamais directement par le navigateur, donc aucune gestion
// CORS n'est nécessaire ici (pas de préflight OPTIONS à gérer).
//
// Secrets requis (Dashboard > Project Settings > Edge Functions > Secrets) :
//   RESEND_API_KEY      - clé API Resend (https://resend.com)
//   ADMIN_NOTIFY_EMAIL  - adresse qui reçoit les notifications
//   NOTIFY_ADMIN_SECRET - jeton partagé avec le trigger SQL, requis : sans
//                         lui, la fonction refuse toute requête (fail-closed)
//   NOTIFY_FROM_EMAIL   - optionnel, adresse d'expédition (voir note ci-dessous)
//
// Secrets OPTIONNELS - notification WhatsApp en plus de l'e-mail :
//   ADMIN_NOTIFY_WHATSAPP     - numéro à prévenir, chiffres seuls avec
//                               indicatif (ex. 221771234567). SANS LUI,
//                               aucun WhatsApp n'est envoyé.
//   META_WHATSAPP_TOKEN       - déjà configuré pour notify-members-whatsapp
//   META_PHONE_NUMBER_ID      - idem
//   META_TEMPLATE_NAME_ADMIN  - optionnel, défaut "rappel_compte" : le même
//                               modèle Utilitaire que les rappels aux
//                               membres, à paramètre nommé "message".
//   META_TEMPLATE_LANG        - optionnel, défaut "fr"
//
// Secrets OPTIONNELS - notification Telegram (GRATUITE, sans modèle à
// faire approuver ; à préférer si le coût compte) :
//   TELEGRAM_BOT_TOKEN        - jeton donné par @BotFather
//   TELEGRAM_CHAT_ID          - identifiant du salon à prévenir
//                               SANS LES DEUX, aucun Telegram n'est envoyé.
//
// IMPORTANT - Resend exige un domaine d'expédition vérifié pour envoyer
// depuis une adresse @amstc.org. Tant qu'amstc.org n'est pas vérifié dans
// Resend, seule l'adresse de test "onboarding@resend.dev" fonctionne, et
// UNIQUEMENT vers l'adresse e-mail du compte Resend lui-même (pas vers
// contact@amstc.org ni aucune autre adresse). Voir README-espace-membres.md.

const RESEND_API_KEY = Deno.env.get("RESEND_API_KEY");
const ADMIN_NOTIFY_EMAIL = Deno.env.get("ADMIN_NOTIFY_EMAIL");
const NOTIFY_ADMIN_SECRET = Deno.env.get("NOTIFY_ADMIN_SECRET");
const FROM_EMAIL = Deno.env.get("NOTIFY_FROM_EMAIL") || "AMSTC <onboarding@resend.dev>";
const ADMIN_NOTIFY_WHATSAPP = Deno.env.get("ADMIN_NOTIFY_WHATSAPP");
const META_WHATSAPP_TOKEN = Deno.env.get("META_WHATSAPP_TOKEN");
const META_PHONE_NUMBER_ID = Deno.env.get("META_PHONE_NUMBER_ID");
const META_TEMPLATE_NAME_ADMIN = Deno.env.get("META_TEMPLATE_NAME_ADMIN") || "rappel_compte";
const META_TEMPLATE_LANG = Deno.env.get("META_TEMPLATE_LANG") || "fr";
const TELEGRAM_BOT_TOKEN = Deno.env.get("TELEGRAM_BOT_TOKEN");
const TELEGRAM_CHAT_ID = Deno.env.get("TELEGRAM_CHAT_ID");

function esc(v: unknown): string {
  return String(v ?? "-").replace(
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
            <li><strong>Carte réclamée :</strong> ${esc(data.card_full_name)} - n° ${esc(data.card_number)}</li>
            <li><strong>Ville / membre depuis :</strong> ${esc(data.card_city)} / ${esc(data.card_member_since)}</li>
          </ul>
          <p>À confirmer dans membres/cartes-admin.html.</p>
        `,
      };
    }
    case "achat_boutique": {
      const items = Array.isArray(data.items) ? data.items : [];
      const itemsHtml = items
        .map((it: any) => `<li>${esc(it.qty)} × ${esc(it.name)} - ${esc(it.price)} FCFA</li>`)
        .join("");
      return {
        subject: `Nouvelle commande boutique - ${esc(data.buyer_name)}`,
        html: `
          <h2>Nouvelle commande sur la Boutique AMSTC</h2>
          <ul>
            <li><strong>Acheteur :</strong> ${esc(data.buyer_name)} (${esc(data.buyer_email)})</li>
            <li><strong>Total :</strong> ${esc(data.total_fcfa)} FCFA</li>
            <li><strong>Paiement :</strong> ${esc(data.payment_method)} - réf. ${esc(data.payment_reference)}</li>
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
    case "paiement_validite": {
      return {
        subject: `Paiement validité de carte - ${esc(data.member_name)} - ${esc(data.amount_fcfa)} F`,
        html: `
          <h2>Paiement de validité de carte déclaré</h2>
          <ul>
            <li><strong>Membre :</strong> ${esc(data.member_name)} (${esc(data.member_email)})</li>
            <li><strong>Années demandées :</strong> ${esc(data.years)}</li>
            <li><strong>Montant :</strong> ${esc(data.amount_fcfa)} FCFA</li>
            <li><strong>Paiement :</strong> ${esc(data.payment_method)} - réf. ${esc(data.payment_reference)}</li>
          </ul>
          <p>À vérifier puis confirmer dans membres/validation.html &rsaquo; Validité de carte.</p>
        `,
      };
    }
    case "paiement_cotisation": {
      return {
        subject: `Paiement cotisations - ${esc(data.member_name)} - ${esc(data.amount_fcfa)} F`,
        html: `
          <h2>Paiement de cotisations déclaré</h2>
          <ul>
            <li><strong>Membre :</strong> ${esc(data.member_name)} (${esc(data.member_email)})</li>
            <li><strong>Année :</strong> ${esc(data.year)}</li>
            <li><strong>Mois demandés :</strong> ${esc(data.months)}</li>
            <li><strong>Montant :</strong> ${esc(data.amount_fcfa)} FCFA</li>
            <li><strong>Paiement :</strong> ${esc(data.payment_method)} - réf. ${esc(data.payment_reference)}</li>
          </ul>
          <p>À vérifier puis confirmer dans membres/validation.html &rsaquo; Cotisations.</p>
        `,
      };
    }
    case "participation_collecte": {
      const enNature = data.mode === "nature";
      return {
        subject: enNature
          ? `Don en nature - ${esc(data.member_name)} - ${esc(data.item)}`
          : `Participation collecte - ${esc(data.member_name)} - ${esc(data.amount_fcfa)} F`,
        html: `
          <h2>${enNature ? "Promesse de don en nature" : "Participation à une collecte"}</h2>
          <ul>
            <li><strong>Membre :</strong> ${esc(data.member_name)} (${esc(data.member_email)})</li>
            <li><strong>Collecte :</strong> ${esc(data.collecte)}</li>
            <li><strong>Item :</strong> ${esc(data.item)}</li>
            ${enNature
              ? "<li><strong>Mode :</strong> don en nature (objet à remettre)</li>"
              : `<li><strong>Montant :</strong> ${esc(data.amount_fcfa)} FCFA</li>
                 <li><strong>Paiement :</strong> ${esc(data.payment_method)} - réf. ${esc(data.payment_reference)}</li>`}
          </ul>
          <p>À traiter dans membres/collectes-admin.html.</p>
        `,
      };
    }
    default:
      return null;
  }
}

/**
 * Résumé d'une ligne, partagé par WhatsApp et Telegram : le modèle Meta
 * n'accepte qu'un paramètre texte, sans mise en forme ni retour à la
 * ligne, et cette contrainte convient aussi bien à Telegram.
 */
function buildTexteCourt(eventType: string, data: Record<string, any>): string | null {
  switch (eventType) {
    case "inscription":
      return `Nouvelle inscription : ${data.full_name} (${data.phone || "sans téléphone"}). À valider dans l'espace administration.`;
    case "reclamation_carte":
      return `Réclamation de carte : ${data.claimant_name} demande la carte ${data.card_number}. À confirmer.`;
    case "achat_boutique":
      return `Commande boutique : ${data.buyer_name}, ${data.total_fcfa} FCFA (${data.payment_method}). À traiter.`;
    case "demande_campagne":
      return `Demande de campagne : ${data.full_name} pour ${data.locality}. À étudier.`;
    case "nouveau_sujet_forum":
      return `Nouveau sujet forum de ${data.author_name} : ${data.title}`;
    case "paiement_validite":
      return `Paiement validité : ${data.member_name}, ${data.amount_fcfa} FCFA pour ${data.years} an(s), réf. ${data.payment_reference}. À confirmer.`;
    case "paiement_cotisation":
      return `Paiement cotisations : ${data.member_name}, ${data.amount_fcfa} FCFA pour ${data.months} mois de ${data.year}, réf. ${data.payment_reference}. À confirmer.`;
    case "participation_collecte":
      return data.mode === "nature"
        ? `Don en nature : ${data.member_name} s'engage à remettre « ${data.item} » (${data.collecte}).`
        : `Participation collecte : ${data.member_name}, ${data.amount_fcfa} FCFA pour « ${data.item} » (${data.collecte}). À confirmer.`;
    default:
      return null;
  }
}

/**
 * Notification WhatsApp à l'administration - OPTIONNELLE.
 *
 * Elle n'est tentée que si les trois secrets sont présents :
 * ADMIN_NOTIFY_WHATSAPP (le numéro à prévenir, chiffres seuls avec
 * l'indicatif, ex. 221771234567), META_WHATSAPP_TOKEN et
 * META_PHONE_NUMBER_ID - les deux derniers étant DÉJÀ configurés pour
 * les rappels aux membres (notify-members-whatsapp).
 *
 * Elle utilise le même modèle « Utilitaire » à paramètre nommé
 * « message » que les rappels : rien de nouveau à faire approuver chez
 * Meta.
 *
 * Un échec n'est jamais fatal : l'e-mail reste la voie principale, et
 * pg_net ne relit pas notre réponse de toute façon.
 */
async function envoyerWhatsApp(texte: string): Promise<void> {
  if (!ADMIN_NOTIFY_WHATSAPP || !META_WHATSAPP_TOKEN || !META_PHONE_NUMBER_ID) return;
  try {
    const res = await fetch(`https://graph.facebook.com/v20.0/${META_PHONE_NUMBER_ID}/messages`, {
      method: "POST",
      headers: {
        "Authorization": `Bearer ${META_WHATSAPP_TOKEN}`,
        "Content-Type": "application/json",
      },
      body: JSON.stringify({
        messaging_product: "whatsapp",
        to: String(ADMIN_NOTIFY_WHATSAPP).replace(/[^0-9]/g, ""),
        type: "template",
        template: {
          name: META_TEMPLATE_NAME_ADMIN,
          language: { code: META_TEMPLATE_LANG },
          components: [
            { type: "body", parameters: [{ type: "text", parameter_name: "message", text: texte }] },
          ],
        },
      }),
    });
    if (!res.ok) {
      console.error("notify-admin: échec WhatsApp", res.status, (await res.text()).slice(0, 200));
    }
  } catch (e) {
    console.error("notify-admin: échec WhatsApp", String(e).slice(0, 200));
  }
}

/**
 * Notification Telegram à l'administration - OPTIONNELLE et GRATUITE.
 *
 * Contrairement à WhatsApp, Telegram ne facture rien et n'impose aucun
 * modèle à faire approuver : un bot créé en deux minutes auprès de
 * @BotFather suffit. C'est le canal à préférer quand le coût compte.
 *
 * Deux secrets, tous deux nécessaires : TELEGRAM_BOT_TOKEN (donné par
 * BotFather) et TELEGRAM_CHAT_ID (le salon à prévenir - votre
 * conversation privée avec le bot, ou un groupe). Sans eux, rien n'est
 * envoyé.
 *
 * parse_mode HTML : esc() échappe déjà &, < et >, exactement les trois
 * caractères que Telegram réclame dans ce mode.
 *
 * Un échec n'est jamais fatal : l'e-mail reste la voie principale.
 */
async function envoyerTelegram(titre: string, texte: string): Promise<void> {
  if (!TELEGRAM_BOT_TOKEN || !TELEGRAM_CHAT_ID) return;
  try {
    const res = await fetch(`https://api.telegram.org/bot${TELEGRAM_BOT_TOKEN}/sendMessage`, {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({
        chat_id: TELEGRAM_CHAT_ID,
        text: `<b>${esc(titre)}</b>

${esc(texte)}`,
        parse_mode: "HTML",
        disable_web_page_preview: true,
      }),
    });
    if (!res.ok) {
      console.error("notify-admin: échec Telegram", res.status, (await res.text()).slice(0, 200));
    }
  } catch (e) {
    console.error("notify-admin: échec Telegram", String(e).slice(0, 200));
  }
}

Deno.serve(async (req: Request) => {
  try {
    if (req.method !== "POST") {
      return new Response(JSON.stringify({ error: "Méthode non autorisée" }), { status: 405 });
    }

    // Vérification maison (indépendante du "Verify JWT" du dashboard, qui
    // doit être désactivé pour cette fonction - voir README-espace-membres.md).
    // Fail-closed : sans secret configuré côté serveur, aucune requête n'est
    // acceptée (plutôt que de désactiver silencieusement le contrôle).
    // Le nom du secret manquant figure dans la réponse : elle n'est lue que
    // par pg_net (table net._http_response), jamais par un visiteur, et sans
    // cela deux causes distinctes produisaient le même message opaque.
    if (!NOTIFY_ADMIN_SECRET) {
      console.error("notify-admin: secret NOTIFY_ADMIN_SECRET manquant côté serveur");
      return new Response(JSON.stringify({ error: "Configuration serveur incomplète : NOTIFY_ADMIN_SECRET manquant" }), { status: 500 });
    }
    const authHeader = req.headers.get("authorization") || "";
    if (authHeader !== `Bearer ${NOTIFY_ADMIN_SECRET}`) {
      return new Response(JSON.stringify({ error: "Non autorisé" }), { status: 401 });
    }

    const missing = [
      !RESEND_API_KEY ? "RESEND_API_KEY" : null,
      !ADMIN_NOTIFY_EMAIL ? "ADMIN_NOTIFY_EMAIL" : null,
    ].filter(Boolean);
    if (missing.length > 0) {
      console.error("notify-admin: secrets manquants :", missing.join(", "));
      return new Response(JSON.stringify({ error: `Configuration serveur incomplète : ${missing.join(" et ")} manquant(s)` }), { status: 500 });
    }

    let payload: Record<string, any>;
    try {
      payload = await req.json();
    } catch {
      return new Response(JSON.stringify({ error: "JSON invalide" }), { status: 400 });
    }

    const { event_type, ...data } = payload;

    // Type d'événement inconnu : on ne le REJETTE PAS. Auparavant la
    // fonction répondait 400 et l'alerte était perdue en silence - or un
    // type inconnu signifie presque toujours qu'un déclencheur SQL a été
    // ajouté sans mettre cette fonction à jour, c'est-à-dire justement un
    // événement dont l'administration voulait être prévenue. On envoie
    // donc un message générique portant les données brutes : sommaire,
    // mais jamais muet.
    const email = buildEmail(event_type, data) || {
      subject: `Événement AMSTC : ${event_type}`,
      html: `<p>Un événement de type <strong>${esc(event_type)}</strong> a été signalé, `
        + `mais cette fonction ne sait pas encore le mettre en forme.</p>`
        + `<p>Données reçues :</p><pre>${esc(JSON.stringify(data, null, 2))}</pre>`
        + `<p style="color:#8A6D1B">Ajoutez ce type dans supabase/functions/notify-admin/index.ts `
        + `pour un message lisible.</p>`,
    };

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

    // WhatsApp et Telegram en plus de l'e-mail, si configurés. Lancés
    // APRÈS l'e-mail et attendus : sur Deno Deploy, une promesse laissée
    // en suspens est abandonnée dès la réponse renvoyée.
    const texteCourt = buildTexteCourt(event_type, data);

    // WhatsApp : seulement pour les événements dont on sait rédiger une
    // phrase. Chaque message est facturé, on n'en envoie pas au hasard.
    if (texteCourt) await envoyerWhatsApp(texteCourt);

    // Telegram : TOUJOURS, quel que soit l'événement. C'est le canal
    // fourre-tout voulu par l'administration - « peu importe l'onglet ».
    // À défaut de phase courte (type d'événement ajouté plus tard et
    // oublié ici), le sujet de l'e-mail fait l'affaire : mieux vaut une
    // notification sommaire que pas de notification du tout. Gratuit,
    // donc rien ne justifie de s'en priver.
    await envoyerTelegram(email.subject, texteCourt || email.subject);

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

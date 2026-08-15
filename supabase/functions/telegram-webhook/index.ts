/**
 * Reçoit les clics sur les boutons des notifications Telegram.
 *
 * CE QU'ELLE FAIT. Vous touchez « Approuver » sous une notification :
 * Telegram appelle cette fonction, qui exécute l'action en base et
 * réécrit le message pour dire ce qui s'est passé - les boutons
 * disparaissent, remplacés par le résultat. Plus besoin d'ouvrir le
 * site pour valider une inscription ou confirmer un paiement.
 *
 * ELLE EST PUBLIQUEMENT ACCESSIBLE, contrairement aux autres fonctions
 * du projet : Telegram doit pouvoir l'appeler sans clé. Trois barrières
 * la protègent, et TOUTES sont nécessaires :
 *
 *   1. Le jeton secret que Telegram joint à chaque appel, dans l'en-tête
 *      X-Telegram-Bot-Api-Secret-Token. Il est fixé au moment du
 *      setWebhook et n'est connu que de Telegram et de nous. Sans lui,
 *      n'importe qui pourrait appeler cette adresse et approuver des
 *      inscriptions.
 *   2. L'identité du salon : seul TELEGRAM_CHAT_ID - votre conversation
 *      privée - peut agir. Un clic venant d'ailleurs est refusé, ce qui
 *      couvre le cas où le bot serait ajouté à un groupe.
 *   3. En base, action_telegram() n'est exécutable que par le rôle de
 *      service. Un membre connecté au site ne peut pas l'appeler.
 *
 * ATTENTION : le setWebhook doit autoriser « message » EN PLUS de
 * « callback_query », faute de quoi Telegram ne transmettra jamais les
 * messages des membres et le rattachement restera sans effet.
 *
 * Secrets requis :
 *   SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY  - fournis automatiquement
 *   TELEGRAM_BOT_TOKEN                       - le jeton du bot
 *   TELEGRAM_CHAT_ID                         - le seul salon autorisé
 *   TELEGRAM_WEBHOOK_SECRET                  - jeton partagé avec Telegram
 *
 * Sans TELEGRAM_WEBHOOK_SECRET, la fonction REFUSE tout : mieux vaut des
 * boutons inertes qu'une porte ouverte.
 */

const SUPABASE_URL = Deno.env.get("SUPABASE_URL")!;
const SERVICE_ROLE_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
const TELEGRAM_BOT_TOKEN = Deno.env.get("TELEGRAM_BOT_TOKEN");
const TELEGRAM_CHAT_ID = Deno.env.get("TELEGRAM_CHAT_ID");
const WEBHOOK_SECRET = Deno.env.get("TELEGRAM_WEBHOOK_SECRET");

function esc(v: unknown): string {
  return String(v ?? "")
    .replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;");
}

async function telegram(methode: string, corps: Record<string, unknown>): Promise<void> {
  if (!TELEGRAM_BOT_TOKEN) return;
  try {
    const r = await fetch(`https://api.telegram.org/bot${TELEGRAM_BOT_TOKEN}/${methode}`, {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify(corps),
    });
    if (!r.ok) console.error(`telegram-webhook: ${methode}`, r.status, (await r.text()).slice(0, 200));
  } catch (e) {
    console.error(`telegram-webhook: ${methode}`, String(e).slice(0, 200));
  }
}

async function rpc(fonction: string, corps: Record<string, unknown>): Promise<string> {
  try {
    const r = await fetch(`${SUPABASE_URL}/rest/v1/rpc/${fonction}`, {
      method: "POST",
      headers: {
        apikey: SERVICE_ROLE_KEY,
        Authorization: `Bearer ${SERVICE_ROLE_KEY}`,
        "Content-Type": "application/json",
      },
      body: JSON.stringify(corps),
    });
    const texte = await r.text();
    return r.ok ? String(JSON.parse(texte) ?? "") : `Échec (${r.status}).`;
  } catch (e) {
    return "Échec : " + String(e).slice(0, 120);
  }
}

/**
 * Répond à un membre qui écrit au bot.
 *
 * Le rattachement passe par « /start <jeton> » : le jeton vient du
 * profil du membre, déjà authentifié sur le site. Sans lui, on ne
 * saurait pas à quel compte relier la conversation.
 *
 * Les autres messages sont interprétés très largement - « ma carte »,
 * « CARTE », « cotisation » -, personne n'écrivant à un bot avec la
 * rigueur d'une ligne de commande.
 */
async function traiterMessage(msg: any): Promise<void> {
  const salon = msg.chat?.id;
  if (!salon) return;
  // Les groupes sont ignorés : ce bot répond à des questions
  // personnelles, qui n'ont rien à faire dans une conversation à
  // plusieurs.
  if (msg.chat?.type && msg.chat.type !== "private") return;

  const texte = String(msg.text ?? "").trim();
  let reponse: string;

  const start = texte.match(/^\/start\s+(\S+)/);
  if (start) {
    reponse = await rpc("lier_telegram", { p_jeton: start[1], p_chat_id: salon });
  } else if (/^\/start/.test(texte)) {
    reponse = "Bonjour ! Pour rattacher votre compte AMSTC, connectez-vous sur amstc.org, "
      + "onglet « Carte de membre et Cotisations », puis touchez "
      + "« Recevoir mes rappels sur Telegram ».";
  } else {
    const t = texte.toLowerCase();
    // Un numéro de carte tapé tel quel (« AMSTC-2016-001 ») vaut demande
    // de carte : c'est le premier réflexe observé au test réel. La
    // réponse porte toujours sur la conversation, jamais sur le numéro
    // saisi - on ne consulte pas la carte d'un autre en tapant son numéro.
    const quoi = /cotis/.test(t) ? "cotisations"
      : (/carte/.test(t) || /amstc-\d{4}-\d+/.test(t)) ? "carte" : "aide";
    reponse = await rpc("infos_membre_telegram", { p_chat_id: salon, p_quoi: quoi });
  }

  await telegram("sendMessage", { chat_id: salon, text: reponse });
}

Deno.serve(async (req: Request) => {
  // Telegram n'envoie que des POST. Tout le reste est refusé sans
  // détailler pourquoi : cette adresse est publique.
  if (req.method !== "POST") return new Response("non", { status: 405 });

  if (!WEBHOOK_SECRET) {
    console.error("telegram-webhook: TELEGRAM_WEBHOOK_SECRET absent, tout est refusé");
    return new Response("non configuré", { status: 503 });
  }
  if (req.headers.get("x-telegram-bot-api-secret-token") !== WEBHOOK_SECRET) {
    return new Response("non", { status: 401 });
  }

  let maj: any;
  try {
    maj = await req.json();
  } catch {
    return new Response("ok", { status: 200 });
  }

  // ===== Messages des MEMBRES =====
  // Contrairement aux clics, ils viennent de n'importe qui : c'est la
  // conversation elle-même qui identifie le membre, jamais un nom saisi.
  if (maj.message) {
    await traiterMessage(maj.message);
    return new Response("ok", { status: 200 });
  }

  const clic = maj.callback_query;
  // Tout autre type de mise à jour (ajout à un groupe, modification…)
  // est acquitté sans rien faire : répondre autre chose que 200 ferait
  // réessayer Telegram indéfiniment.
  if (!clic) return new Response("ok", { status: 200 });

  const salon = String(clic.message?.chat?.id ?? "");
  if (!TELEGRAM_CHAT_ID || salon !== String(TELEGRAM_CHAT_ID)) {
    await telegram("answerCallbackQuery", {
      callback_query_id: clic.id,
      text: "Action réservée à l'administration.",
      show_alert: true,
    });
    return new Response("ok", { status: 200 });
  }

  // « type:verdict:uuid », par exemple « ins:ok:6f2c… »
  const donnee = String(clic.data ?? "");
  const sep = donnee.lastIndexOf(":");
  const action = sep === -1 ? "" : donnee.slice(0, sep);
  const id = sep === -1 ? "" : donnee.slice(sep + 1);

  let resultat = "Action illisible.";
  if (action && id) {
    try {
      const r = await fetch(`${SUPABASE_URL}/rest/v1/rpc/action_telegram`, {
        method: "POST",
        headers: {
          apikey: SERVICE_ROLE_KEY,
          Authorization: `Bearer ${SERVICE_ROLE_KEY}`,
          "Content-Type": "application/json",
        },
        body: JSON.stringify({ p_action: action, p_id: id }),
      });
      const texte = await r.text();
      resultat = r.ok
        ? String(JSON.parse(texte) ?? "Fait.")
        : `Échec (${r.status}) : ${texte.slice(0, 120)}`;
    } catch (e) {
      resultat = "Échec : " + String(e).slice(0, 120);
    }
  }

  // La petite bulle de confirmation en haut de l'écran.
  await telegram("answerCallbackQuery", { callback_query_id: clic.id, text: resultat.slice(0, 190) });

  // Le message est réécrit avec le verdict, et SES BOUTONS RETIRÉS : sans
  // cela, on peut recliquer indéfiniment et se demander si l'action a
  // vraiment eu lieu.
  const avant = clic.message?.text ?? "";
  await telegram("editMessageText", {
    chat_id: salon,
    message_id: clic.message?.message_id,
    text: `${esc(avant)}\n\n➤ <b>${esc(resultat)}</b>`,
    parse_mode: "HTML",
    reply_markup: { inline_keyboard: [] },
  });

  return new Response("ok", { status: 200 });
});

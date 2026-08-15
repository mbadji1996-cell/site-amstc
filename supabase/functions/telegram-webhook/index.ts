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

  const clic = maj.callback_query;
  // Tout autre type de mise à jour (message ordinaire, ajout à un
  // groupe…) est acquitté sans rien faire : répondre autre chose que 200
  // ferait réessayer Telegram indéfiniment.
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

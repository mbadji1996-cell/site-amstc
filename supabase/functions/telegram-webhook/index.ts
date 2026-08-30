/**
 * Reçoit les clics sur les boutons des notifications Telegram, et les
 * messages écrits au bot.
 *
 * CE QU'ELLE FAIT. Vous touchez « Approuver » sous une notification :
 * Telegram appelle cette fonction, qui exécute l'action en base et
 * réécrit le message pour dire ce qui s'est passé - les boutons
 * disparaissent, remplacés par le résultat. Plus besoin d'ouvrir le
 * site pour valider une inscription ou confirmer un paiement.
 *
 * « Prévenir le membre » ouvre un MENU des six messages que propose
 * l'écran Validation du site (phase 89). Le message choisi revient sous
 * forme de LIEN WhatsApp pré-rempli : un serveur ne peut pas envoyer de
 * WhatsApp libre, seul le téléphone de l'administrateur le peut.
 * Telegram et l'e-mail ne servent qu'aux membres sans numéro.
 *
 * ELLE FAIT AUSSI, depuis les phases 90 à 92 :
 *   - dans le salon d'administration, sept commandes : /point, /attente,
 *     /justificatifs, /cotisations, /cartes, /membre <nom> et
 *     /diffusion <texte>. « /aide » les rappelle, et les quatre listes
 *     se joignent aussi par boutons depuis /point ;
 *   - « Publier sur la chaîne » sur les nouveautés du site public ;
 *   - la RÉCEPTION DES JUSTIFICATIFS : une capture de paiement envoyée
 *     au bot par un membre rattaché est archivée, puis reposée dans le
 *     salon avec sa fiche et les boutons de confirmation de sa
 *     déclaration en attente, s'il en a une.
 *
 * ATTENTION AUX MESSAGES-PHOTO : un justificatif se réécrit par
 * editMessageCaption, jamais par editMessageText. Tout passe donc par
 * reecrire().
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
 *   2. L'identité du salon : seul TELEGRAM_CHAT_ID peut agir - votre
 *      conversation privée, ou un GROUPE d'administrateurs si vous y
 *      mettez son identifiant. Un clic venant de tout autre salon est
 *      refusé. Dans un groupe, le nom Telegram de celui qui clique est
 *      transmis au journal d'administration (phase 86).
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
 * Secret OPTIONNEL :
 *   TELEGRAM_CHANNEL_ID                      - la chaîne publique, où
 *                                              part ce qu'on publie d'un
 *                                              clic. Sans lui, le bouton
 *                                              « Publier sur la chaîne »
 *                                              le dit au lieu d'échouer
 *                                              en silence.
 *
 * Sans TELEGRAM_WEBHOOK_SECRET, la fonction REFUSE tout : mieux vaut des
 * boutons inertes qu'une porte ouverte.
 */

const SUPABASE_URL = Deno.env.get("SUPABASE_URL")!;
const SERVICE_ROLE_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
const TELEGRAM_BOT_TOKEN = Deno.env.get("TELEGRAM_BOT_TOKEN");
const TELEGRAM_CHAT_ID = Deno.env.get("TELEGRAM_CHAT_ID");
const TELEGRAM_CHANNEL_ID = Deno.env.get("TELEGRAM_CHANNEL_ID");
const WEBHOOK_SECRET = Deno.env.get("TELEGRAM_WEBHOOK_SECRET");

const SITE = "https://amstc.org";

// La ligne qui sépare l'en-tête d'une proposition de publication du
// texte à publier. Écrite par scripts/publier-chaine.js : si elle change
// là-bas, elle doit changer ici. Le texte de la proposition EST la
// charge utile - rien n'est stocké entre la proposition et le clic.
const SEPARATEUR = "──────";
const FICHE_MEMBRE = { text: "🔎 Voir la fiche", url: SITE + "/membres/validation.html" };

function esc(v: unknown): string {
  return String(v ?? "")
    .replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;");
}

/**
 * Le texte d'origine d'une notification, sans les verdicts déjà ajoutés.
 *
 * Chaque action réécrit le message en ajoutant « ➤ … » à la fin. Sans
 * cette coupe, ouvrir le menu puis choisir un message empilerait trois
 * verdicts sous la notification, et l'on ne saurait plus lequel compte.
 */
function baseTexte(t: unknown): string {
  const s = String(t ?? "");
  const i = s.indexOf("\n\n➤ ");
  return i === -1 ? s : s.slice(0, i);
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

/**
 * Réécrit un message, qu'il soit texte ou photo.
 *
 * Telegram impose deux méthodes différentes : editMessageText échoue sur
 * un message-photo, dont il faut modifier la LÉGENDE. Un justificatif
 * arrivant en photo, tout ce qui réécrit un message doit passer par ici.
 *
 * La légende est plafonnée par Telegram à 1024 caractères : on tranche
 * avant lui, sans quoi la réécriture échouerait en silence et le bouton
 * resterait affiché comme si rien ne s'était passé.
 */
async function reecrire(
  salon: string | number, msgId: number | null | undefined, estPhoto: boolean,
  corps: string, clavier?: any[][] | null,
): Promise<void> {
  if (!msgId) return;
  await telegram(estPhoto ? "editMessageCaption" : "editMessageText", {
    chat_id: salon,
    message_id: msgId,
    ...(estPhoto
      ? { caption: corps.length > 1020 ? corps.slice(0, 1017) + "…" : corps }
      : { text: corps, disable_web_page_preview: true }),
    parse_mode: "HTML",
    ...(clavier ? { reply_markup: { inline_keyboard: clavier } } : {}),
  });
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
    if (!r.ok) return `Échec (${r.status}).`;
    const val = JSON.parse(texte);
    // Une fonction qui renvoie un OBJET (preparer_prevenir_membre) doit
    // arriver intact : String() en aurait fait « [object Object] ». Une
    // fonction qui renvoie du texte arrive tel quel.
    return typeof val === "string" ? val : (val == null ? "" : JSON.stringify(val));
  } catch (e) {
    return "Échec : " + String(e).slice(0, 120);
  }
}

/**
 * Les six messages du menu « Prévenir », dans l'ordre et sous les
 * intitulés de l'écran Validation du site : quelqu'un qui connaît l'un
 * retrouve l'autre sans réfléchir.
 *
 * Le code tient en cinq octets (« m:exp ») : Telegram plafonne
 * callback_data à 64 octets, et l'identifiant du membre en occupe 36.
 */
const MESSAGES: Record<string, { type: string; libelle: string; bouton: string }> = {
  "m:exp": { type: "carte_expiree",        libelle: "Carte expirée",              bouton: "📇 Carte expirée" },
  "m:ren": { type: "carte_expire_bientot", libelle: "Carte à renouveler",         bouton: "🔄 Carte à renouveler bientôt" },
  "m:cot": { type: "cotisation_retard",    libelle: "Cotisations en retard",      bouton: "💰 Cotisations en retard" },
  "m:act": { type: "compte_active",        libelle: "Compte activé",              bouton: "✅ Compte activé - se connecter" },
  "m:pay": { type: "rappel_paiement",      libelle: "Rappel de paiement",         bouton: "💳 Rappel de paiement" },
  "m:lib": { type: "libre",                libelle: "Message libre",              bouton: "✍️ Message libre" },
};

/**
 * Prépare le message et répond par un lien WhatsApp pré-rempli.
 *
 * Deux points d'entrée : un clic sur le menu, ou la réponse écrite de
 * l'administrateur pour un message libre. Le résultat est le même, seul
 * l'endroit où il s'affiche change - d'où « msgId » facultatif : avec,
 * on réécrit la notification ; sans, on envoie un nouveau message.
 */
async function proposerEnvoi(opts: {
  salon: string | number;
  id: string;
  code: string;
  message?: string | null;
  qui: string;
  msgId?: number | null;
  texteBase?: string;
  callbackId?: string;
  // Un justificatif arrive en photo : sa légende se modifie autrement
  // qu'un texte, et l'oublier ferait échouer la réécriture en silence.
  estPhoto?: boolean;
}): Promise<void> {
  const def = MESSAGES[opts.code];
  if (!def) return;

  const brut = await rpc("preparer_prevenir_membre", {
    p_user_id: opts.id, p_type: def.type, p_message: opts.message ?? null,
  });
  let prep: any = null;
  try { prep = JSON.parse(brut); } catch { prep = null; }

  const alerter = async (texte: string) => {
    if (opts.callbackId) {
      await telegram("answerCallbackQuery", {
        callback_query_id: opts.callbackId, text: texte.slice(0, 190), show_alert: true,
      });
    } else {
      await telegram("sendMessage", { chat_id: opts.salon, text: texte });
    }
  };

  if (!prep || !prep.ok) {
    await alerter((prep && prep.motif) || brut.slice(0, 190));
    return;
  }

  let verdict: string;
  let clavier: any[][];

  if (prep.whatsapp) {
    const lien = `https://wa.me/${prep.whatsapp}?text=${encodeURIComponent(prep.texte)}`;
    // Le journal enregistre l'intention, comme sur le site : le serveur
    // ne peut pas constater l'envoi lui-même.
    await rpc("tracer_whatsapp_telegram", {
      p_user_id: opts.id, p_type: def.type, p_qui: opts.qui || null,
    });
    if (opts.callbackId) {
      await telegram("answerCallbackQuery", {
        callback_query_id: opts.callbackId,
        text: "Touchez le bouton vert : WhatsApp s'ouvre avec le message prêt.",
      });
    }
    verdict = `${def.libelle} - prêt pour ${prep.nom}`;
    clavier = [
      [{ text: `💬 Envoyer sur WhatsApp à ${prep.nom}`.slice(0, 60), url: lien }],
      [FICHE_MEMBRE],
    ];
  } else {
    // Pas de numéro : repli Telegram puis e-mail, côté serveur.
    const res = await rpc("prevenir_membre_repli", {
      p_user_id: opts.id, p_type: def.type, p_message: opts.message ?? null,
    });
    if (opts.callbackId) {
      await telegram("answerCallbackQuery", {
        callback_query_id: opts.callbackId, text: res.slice(0, 190),
      });
    }
    verdict = res;
    clavier = [[FICHE_MEMBRE]];
  }

  const corps = `${esc(opts.texteBase ?? "")}${opts.texteBase ? "\n\n" : ""}➤ <b>${esc(verdict)}</b>`;
  if (opts.msgId) {
    await reecrire(opts.salon, opts.msgId, !!opts.estPhoto, corps, clavier);
  } else {
    await telegram("sendMessage", {
      chat_id: opts.salon, text: corps, parse_mode: "HTML",
      disable_web_page_preview: true, reply_markup: { inline_keyboard: clavier },
    });
  }
}

/**
 * Archive une image de Telegram dans le bucket privé « justificatifs ».
 *
 * Telegram ne conserve pas les fichiers indéfiniment et son file_id ne
 * vaut que pour ce bot : une capture de paiement doit vivre chez nous.
 * Le téléchargement passe par getFile puis l'adresse de fichier, et le
 * dépôt par l'API Storage avec la clé de service.
 *
 * Renvoie le chemin dans le bucket, ou null : un archivage raté ne doit
 * pas empêcher le justificatif d'arriver au salon d'administration.
 * Mieux vaut une capture vue et non conservée qu'une capture perdue.
 */
async function archiverJustificatif(fileId: string): Promise<string | null> {
  if (!TELEGRAM_BOT_TOKEN) return null;
  try {
    const info = await fetch(
      `https://api.telegram.org/bot${TELEGRAM_BOT_TOKEN}/getFile?file_id=${encodeURIComponent(fileId)}`);
    if (!info.ok) return null;
    const j = await info.json();
    const chemin = j?.result?.file_path;
    if (!chemin) return null;
    // Le bucket plafonne à 10 Mo : inutile de télécharger au-delà.
    if (Number(j.result.file_size) > 10 * 1024 * 1024) {
      console.error("telegram-webhook: justificatif trop volumineux", j.result.file_size);
      return null;
    }

    const bin = await fetch(`https://api.telegram.org/file/bot${TELEGRAM_BOT_TOKEN}/${chemin}`);
    if (!bin.ok) return null;
    const octets = new Uint8Array(await bin.arrayBuffer());

    const d = new Date();
    const ext = (/\.[A-Za-z0-9]{1,5}$/.exec(chemin) || [".jpg"])[0].toLowerCase();
    // Rangé par mois : au bout d'un an, un dossier unique deviendrait
    // impraticable à parcourir.
    const nom = `${d.getUTCFullYear()}-${String(d.getUTCMonth() + 1).padStart(2, "0")}/`
      + `${d.toISOString().replace(/[:.]/g, "-")}-${fileId.slice(-10)}${ext}`;

    const up = await fetch(`${SUPABASE_URL}/storage/v1/object/justificatifs/${nom}`, {
      method: "POST",
      headers: {
        apikey: SERVICE_ROLE_KEY,
        Authorization: `Bearer ${SERVICE_ROLE_KEY}`,
        "Content-Type": bin.headers.get("content-type") || "application/octet-stream",
      },
      body: octets,
    });
    if (!up.ok) {
      console.error("telegram-webhook: dépôt justificatif", up.status, (await up.text()).slice(0, 200));
      return null;
    }
    return nom;
  } catch (e) {
    console.error("telegram-webhook: archivage justificatif", String(e).slice(0, 200));
    return null;
  }
}

/**
 * Une capture de paiement envoyée par un membre.
 *
 * Elle est archivée, enregistrée, puis reposée dans le salon
 * d'administration - par son identifiant Telegram, sans retéléchargement
 * - avec la fiche du membre et, S'IL A DÉJÀ DÉCLARÉ SON PAIEMENT sur le
 * site, les boutons de confirmation de cette déclaration précise. C'est
 * ce rapprochement qui fait tout l'intérêt du dispositif : la capture
 * n'arrive plus détachée de ce à quoi elle se rapporte.
 *
 * Renvoie true si le message était bien une image.
 */
async function traiterJustificatif(msg: any): Promise<boolean> {
  // Telegram envoie plusieurs tailles ; la dernière est la plus grande,
  // et c'est la seule lisible quand la capture porte des chiffres.
  const photos = Array.isArray(msg.photo) ? msg.photo : null;
  const doc = msg.document;
  const estImageDoc = doc && (/^image\//.test(String(doc.mime_type ?? ""))
    || String(doc.mime_type ?? "") === "application/pdf");
  if (!photos?.length && !estImageDoc) return false;

  const salon = msg.chat?.id;
  const fileId = photos?.length ? photos[photos.length - 1].file_id : doc.file_id;

  const chemin = await archiverJustificatif(fileId);
  let r: any = null;
  try {
    r = JSON.parse(await rpc("enregistrer_justificatif", {
      p_chat_id: salon, p_file_id: fileId, p_chemin: chemin,
      p_legende: msg.caption ?? null,
    }));
  } catch { r = null; }

  if (!r || !r.ok) {
    await telegram("sendMessage", {
      chat_id: salon,
      text: (r && r.motif) || "Votre justificatif n'a pas pu être enregistré. Réessayez.",
    });
    return true;
  }

  // Accusé de réception au membre. Il doit savoir que ce n'est pas
  // encore validé : sans cela, il croira son paiement confirmé.
  await telegram("sendMessage", {
    chat_id: salon,
    text: `Merci ${r.prenom || ""} ! Votre justificatif est bien arrivé.\n`
        + `Il sera vérifié par la Commission finances, et votre paiement `
        + `apparaîtra sur votre espace membre une fois confirmé.`.trim(),
  });

  if (!TELEGRAM_CHAT_ID) return true;

  const attente: any[] = Array.isArray(r.attente) ? r.attente : [];
  const rangees: any[][] = attente.map((d) => [{
    text: `✅ Confirmer : ${d.libelle}`.slice(0, 60),
    callback_data: `${d.code}:ok:${d.id}`,
  }]);
  rangees.push([
    { text: "📁 Classer traité", callback_data: `jt:ok:${r.justificatif_id}` },
    { text: "✖️ Écarter", callback_data: `jt:no:${r.justificatif_id}` },
  ]);
  rangees.push([{ text: "🔎 Écran de vérification", url: SITE + "/membres/verification-admin.html" }]);

  const legende = `💳 <b>Justificatif reçu</b>\n${esc(r.fiche)}`
    + (r.legende ? `\n\nMot du membre : ${esc(r.legende)}` : "")
    + (attente.length ? "" : "\n\n⚠ Aucune déclaration en attente sur le site : "
        + "ce paiement n'a pas été déclaré, ou l'a déjà été et confirmé.")
    + (chemin ? "" : "\n\n⚠ Archivage impossible : enregistrez l'image à la main.");

  // Une photo se repose par sendPhoto, un PDF par sendDocument : croiser
  // les deux fait échouer l'envoi, et le justificatif n'arriverait
  // jamais au groupe.
  const enPhoto = !!photos?.length;
  await telegram(enPhoto ? "sendPhoto" : "sendDocument", {
    chat_id: TELEGRAM_CHAT_ID,
    ...(enPhoto ? { photo: fileId } : { document: fileId }),
    caption: legende.length > 1020 ? legende.slice(0, 1017) + "…" : legende,
    parse_mode: "HTML",
    reply_markup: { inline_keyboard: rangees },
  });
  return true;
}

/** Le nom de celui qui agit, tel que Telegram le transmet. */
function quiEst(from: any): string {
  return [from?.first_name, from?.last_name].filter(Boolean).join(" ")
    + (from?.username ? ` (@${from.username})` : "");
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
  // plusieurs. Mais leur identifiant est JOURNALISÉ : c'est le moyen le
  // plus simple de le connaître quand on veut faire d'un groupe le salon
  // d'administration - le webhook consomme les mises à jour, getUpdates
  // ne montre donc plus rien une fois posé.
  if (msg.chat?.type && msg.chat.type !== "private") {
    console.log(`telegram-webhook: message reçu du groupe ${salon} `
      + `« ${String(msg.chat.title ?? "").slice(0, 60)} » (${msg.chat.type})`);
    return;
  }

  // Une image ou un PDF vaut justificatif de paiement : c'est le geste
  // que les membres font déjà sur WhatsApp, et il n'a pas à s'apprendre.
  if (await traiterJustificatif(msg)) return;

  const texte = String(msg.text ?? "").trim();
  let reponse: string;
  let clavier: unknown = undefined;

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
    // Le geste qui suit la lecture : renouveler, ou déclarer un
    // paiement. Le bouton n'est proposé qu'au membre RATTACHÉ - à un
    // inconnu, la réponse explique déjà quoi faire, et un lien vers son
    // profil n'aurait pas de sens.
    if ((quoi === "carte" || quoi === "cotisations") && !/rattaché à aucun compte/.test(reponse)) {
      clavier = { inline_keyboard: [[{
        text: quoi === "carte" ? "📇 Ma carte sur amstc.org" : "💰 Déclarer un paiement",
        url: SITE + (quoi === "carte"
          ? "/membres/profil.html?open=validity"
          : "/membres/profil.html?open=cotis"),
      }]] };
    }
  }

  await telegram("sendMessage", {
    chat_id: salon, text: reponse, disable_web_page_preview: true,
    ...(clavier ? { reply_markup: clavier } : {}),
  });
}

/**
 * Les listes d'information, joignables par commande ET par bouton.
 *
 * « /point » sert de sommaire : ses boutons mènent aux quatre autres, ce
 * qui évite de retenir six commandes. Chaque liste renvoie les mêmes
 * boutons, de sorte qu'on circule dans les deux sens.
 */
const LISTES: Record<string, { commande: string; bouton: string }> = {
  "lst:dos": { commande: "attente",        bouton: "📋 Qui attend" },
  "lst:jus": { commande: "justificatifs",  bouton: "💳 Justificatifs" },
  "lst:car": { commande: "cartes",         bouton: "📇 Cartes non attribuées" },
  "lst:cot": { commande: "cotisations",    bouton: "💰 Cotisations" },
};

function boutonsListes(sauf?: string): any[][] {
  // La liste qu'on regarde déjà n'est pas reproposée : un bouton qui
  // renvoie là où l'on est fait douter d'avoir bien cliqué.
  const codes = Object.keys(LISTES).filter((c) => c !== sauf);
  const rangees: any[][] = [];
  for (let i = 0; i < codes.length; i += 2) {
    rangees.push(codes.slice(i, i + 2).map((c) => ({
      text: LISTES[c].bouton, callback_data: `${c}:x`,
    })));
  }
  if (sauf) rangees.push([{ text: "◂ Le point", callback_data: "lst:pnt:x" }]);
  return rangees;
}

const AIDE_ADMIN =
  "<b>Ce que je sais faire</b>\n\n"
  + "/point - ce qui attend, tous onglets confondus\n"
  + "/attente - qui attend, nommément\n"
  + "/justificatifs - les captures reçues et non classées\n"
  + "/cotisations - l'état des cotisations de l'année\n"
  + "/cartes - les cartes non attribuées\n"
  + "/membre &lt;nom&gt; - la fiche de quelqu'un (nom, e-mail, téléphone, n° de carte)\n"
  + "/diffusion &lt;texte&gt; - une annonce à tous les membres rattachés\n\n"
  + "Le reste se fait aux boutons, sous les notifications.";

/**
 * Affiche une des listes.
 *
 * Le même code sert à la commande et au bouton : dans un cas on envoie
 * un message, dans l'autre on réécrit celui qu'on vient de toucher.
 */
async function afficherListe(
  salon: string | number, quoi: string,
  opts: { msgId?: number | null; estPhoto?: boolean; callbackId?: string } = {},
): Promise<void> {
  let corps = "";
  let rangees: any[][] = [];
  let codeCourant: string | undefined;

  if (quoi === "point") {
    let p: any = null;
    try { p = JSON.parse(await rpc("point_telegram", {})); } catch { p = null; }
    corps = `📊 <b>Le point</b>\n\n${esc(p?.texte ?? "Indisponible.")}`;
    rangees = boutonsListes();

  } else if (quoi === "attente") {
    codeCourant = "lst:dos";
    let d: any = null;
    try { d = JSON.parse(await rpc("dossiers_en_attente_liste", {})); } catch { d = null; }
    const ins: any[] = Array.isArray(d?.inscriptions) ? d.inscriptions : [];
    corps = `📋 <b>Qui attend</b>\n\n`
      + `Inscriptions : ${esc(d?.nb_inscriptions ?? 0)}\n`
      + (ins.length ? "Touchez un nom pour ouvrir sa fiche.\n" : "")
      + `\nPaiements à confirmer : ${esc(d?.nb_paiements ?? 0)}\n`
      + (d?.paiements ? esc(d.paiements) : "Aucun.");
    // Une inscription par bouton : l'ouvrir est le geste qui suit. Les
    // paiements restent en texte - dans une longue liste, « Confirmer »
    // se touche par mégarde, et un paiement confirmé par erreur ne se
    // voit pas.
    rangees = ins.map((m) => [{ text: m.libelle.slice(0, 60), callback_data: `mf:${m.id}` }]);
    rangees.push(...boutonsListes(codeCourant));

  } else if (quoi === "cotisations") {
    codeCourant = "lst:cot";
    // Le texte vient de SQL en clair ; seule la première ligne, qui fait
    // titre, est mise en gras ici.
    const etat = (await rpc("etat_cotisations_telegram", {})).split("\n");
    corps = `<b>${esc(etat[0])}</b>` + (etat.length > 1 ? "\n" + esc(etat.slice(1).join("\n")) : "");
    rangees = boutonsListes(codeCourant);

  } else if (quoi === "cartes") {
    codeCourant = "lst:car";
    let c: any = null;
    try { c = JSON.parse(await rpc("cartes_non_attribuees", {})); } catch { c = null; }
    const sans: any[] = Array.isArray(c?.sans_numero) ? c.sans_numero : [];
    const nreg = Number(c?.nb_registre ?? 0);
    const nsans = Number(c?.nb_sans_numero ?? 0);
    const max = Number(c?.max ?? 10);
    // Deux choses distinctes, et les confondre fait chercher au mauvais
    // endroit : des cartes sans propriétaire, et des membres sans carte.
    corps = `📇 <b>Cartes non attribuées</b>\n\n`
      + `<b>Registre - ${esc(nreg)} carte(s) que personne n'a réclamée(s)</b>\n`
      + (nreg ? esc(c.registre) + (nreg > max ? `\n… et ${nreg - max} autre(s).` : "")
              : "Aucune.")
      + `\n\n<b>Membres inscrits sans numéro : ${esc(nsans)}</b>\n`
      + (nsans ? (sans.length ? "Touchez un nom pour ouvrir sa fiche."
                              : "") + (nsans > max ? `\n… et ${nsans - max} autre(s).` : "")
               : "Aucun.");
    rangees = sans.map((m) => [{ text: m.libelle.slice(0, 60), callback_data: `mf:${m.id}` }]);
    rangees.push([{ text: "📇 Écran des cartes", url: SITE + "/membres/cartes-admin.html" }]);
    rangees.push(...boutonsListes(codeCourant));
  }

  if (quoi === "justificatifs") {
    // Les justificatifs se REPOSENT en images : une capture décrite en
    // texte ne sert à rien, c'est le montant lisible dessus qui compte.
    let j: any = null;
    try { j = JSON.parse(await rpc("justificatifs_en_attente", {})); } catch { j = null; }
    const liste: any[] = Array.isArray(j?.liste) ? j.liste : [];
    if (opts.callbackId) await telegram("answerCallbackQuery", { callback_query_id: opts.callbackId });
    if (!liste.length) {
      await telegram("sendMessage", {
        chat_id: salon, text: "💳 <b>Justificatifs</b>\n\nAucun justificatif non classé.",
        parse_mode: "HTML",
        reply_markup: { inline_keyboard: boutonsListes("lst:jus") },
      });
      return;
    }
    for (const u of liste) {
      const att: any[] = Array.isArray(u.attente) ? u.attente : [];
      const clavier: any[][] = att.map((d) => [{
        text: `✅ Confirmer : ${d.libelle}`.slice(0, 60), callback_data: `${d.code}:ok:${d.id}`,
      }]);
      clavier.push([
        { text: "📁 Classer traité", callback_data: `jt:ok:${u.id}` },
        { text: "✖️ Écarter", callback_data: `jt:no:${u.id}` },
      ]);
      await telegram("sendPhoto", {
        chat_id: salon, photo: u.file_id,
        caption: `💳 <b>${esc(u.nom)}</b> - reçu le ${esc(u.recu)}`
          + (u.legende ? `\nMot du membre : ${esc(u.legende)}` : "")
          + (att.length ? "" : "\n⚠ Aucune déclaration en attente."),
        parse_mode: "HTML",
        reply_markup: { inline_keyboard: clavier },
      });
    }
    await telegram("sendMessage", {
      chat_id: salon,
      text: `💳 ${liste.length} justificatif(s) affiché(s) sur ${esc(j?.total ?? liste.length)}.`,
      reply_markup: { inline_keyboard: boutonsListes("lst:jus") },
    });
    return;
  }

  if (opts.callbackId) await telegram("answerCallbackQuery", { callback_query_id: opts.callbackId });
  if (opts.msgId) {
    await reecrire(salon, opts.msgId, !!opts.estPhoto, corps, rangees);
  } else {
    await telegram("sendMessage", {
      chat_id: salon, text: corps, parse_mode: "HTML",
      disable_web_page_preview: true, reply_markup: { inline_keyboard: rangees },
    });
  }
}

/** La fiche d'un membre, avec ce qu'on fait juste après l'avoir lue. */
async function envoyerFiche(salon: string | number, id: string): Promise<void> {
  const fiche = await rpc("fiche_membre_telegram", { p_user_id: id });
  await telegram("sendMessage", {
    chat_id: salon, text: fiche, disable_web_page_preview: true,
    reply_markup: { inline_keyboard: [
      [{ text: "✉️ Prévenir le membre", callback_data: `ins:msg:${id}` }],
      [FICHE_MEMBRE],
    ] },
  });
}

/**
 * Messages écrits dans le salon d'administration.
 *
 * Trois cas, et rien d'autre - tout le reste retombe sur le traitement
 * ordinaire, le salon pouvant être la conversation privée de
 * l'administrateur, qui reste un membre comme un autre :
 *
 *   - la RÉPONSE à la demande de message libre. Le bot a posé une
 *     question portant l'identifiant du membre entre crochets ;
 *     l'administrateur y répond, et son texte devient le message.
 *     Passer par une réponse plutôt que par un état gardé en mémoire
 *     évite de tenir quoi que ce soit entre deux appels - Telegram nous
 *     rend lui-même la question ;
 *   - « /membre <nom> », qui cherche et affiche une fiche ;
 *   - « /diffusion <texte> », qui PRÉPARE une annonce sans l'envoyer.
 *
 * Dans un groupe, Telegram accole le nom du bot aux commandes
 * (« /membre@amstc_notifs_bot ») : les motifs l'acceptent.
 *
 * Renvoie true si le message a été traité ici.
 */
async function traiterMessageAdmin(msg: any): Promise<boolean> {
  const salon = msg.chat?.id;
  const texte = String(msg.text ?? "").trim();

  // 1. Réponse à la demande de message libre.
  const repondA = msg.reply_to_message;
  const marque = repondA ? /\[#([0-9a-fA-F-]{36})\]/.exec(String(repondA.text ?? "")) : null;
  if (marque) {
    if (!texte) {
      await telegram("sendMessage", { chat_id: salon, text: "Message vide : rien n'a été préparé." });
      return true;
    }
    await proposerEnvoi({ salon, id: marque[1], code: "m:lib", message: texte, qui: quiEst(msg.from) });
    return true;
  }

  // 2. Les commandes d'information. Sans argument, elles répondent
  //    toutes de la même façon - d'où ce seul motif.
  const info = /^\/(point|attente|justificatifs?|cotisations?|cartes?|aide|start|help)(?:@\S+)?\s*$/i
    .exec(texte);
  if (info) {
    const mot = info[1].toLowerCase();
    if (mot === "aide" || mot === "help" || mot === "start") {
      await telegram("sendMessage", { chat_id: salon, text: AIDE_ADMIN, parse_mode: "HTML" });
      return true;
    }
    await afficherListe(salon,
      mot === "point" ? "point"
      : mot === "attente" ? "attente"
      : mot.startsWith("justificatif") ? "justificatifs"
      : mot.startsWith("cotisation") ? "cotisations"
      : "cartes");
    return true;
  }

  // 3. « /membre <recherche> »
  const cherche = /^\/membres?(?:@\S+)?(?:\s+([\s\S]+))?$/i.exec(texte);
  if (cherche) {
    const q = (cherche[1] ?? "").trim();
    if (!q) {
      await telegram("sendMessage", { chat_id: salon,
        text: "Écrivez ce que vous cherchez : /membre habib\n"
            + "Un nom, un e-mail, un téléphone ou un numéro de carte font l'affaire." });
      return true;
    }
    let r: any = null;
    try { r = JSON.parse(await rpc("chercher_membres_telegram", { p_recherche: q })); } catch { r = null; }
    if (!r || r.ok === false) {
      await telegram("sendMessage", { chat_id: salon, text: (r && r.motif) || "Recherche impossible." });
      return true;
    }
    const membres: any[] = Array.isArray(r.membres) ? r.membres : [];
    if (!membres.length) {
      await telegram("sendMessage", { chat_id: salon, text: `Aucun membre ne correspond à « ${q} ».` });
      return true;
    }
    // Un seul résultat : on va droit à la fiche, le choix serait une
    // question posée pour rien.
    if (membres.length === 1) {
      await envoyerFiche(salon, membres[0].id);
      return true;
    }
    await telegram("sendMessage", {
      chat_id: salon,
      text: `${r.nombre} membre(s) correspondent à « ${q} »`
          + (r.tronque ? `, voici les ${membres.length} premiers. Précisez pour en voir d'autres.` : " :"),
      reply_markup: { inline_keyboard: membres.map((m) => [{
        text: `${m.nom}${m.statut && m.statut !== "approved" ? ` (${m.statut})` : ""}`.slice(0, 60),
        callback_data: `mf:${m.id}`,
      }]) },
    });
    return true;
  }

  // 4. « /diffusion <texte> » - préparée, jamais envoyée d'emblée.
  const diff = /^\/diffusion(?:@\S+)?(?:\s+([\s\S]+))?$/i.exec(texte);
  if (diff) {
    const annonce = (diff[1] ?? "").trim();
    if (!annonce) {
      await telegram("sendMessage", { chat_id: salon,
        text: "Écrivez l'annonce après la commande :\n"
            + "/diffusion Assemblée générale samedi 10 h au siège.\n\n"
            + "Rien ne part avant votre confirmation." });
      return true;
    }
    let p: any = null;
    try {
      p = JSON.parse(await rpc("preparer_diffusion", { p_texte: annonce, p_qui: quiEst(msg.from) }));
    } catch { p = null; }
    if (!p || !p.ok) {
      await telegram("sendMessage", { chat_id: salon, text: (p && p.motif) || "Préparation impossible." });
      return true;
    }
    await telegram("sendMessage", {
      chat_id: salon,
      text: `📣 <b>Annonce à ${esc(p.nb)} membre(s) rattaché(s)</b>\n`
          + `Relisez-la : un message parti ne se rattrape pas.\n\n`
          + `<i>${esc(p.texte)}</i>`,
      parse_mode: "HTML",
      disable_web_page_preview: true,
      reply_markup: { inline_keyboard: [[
        { text: `📣 Envoyer à ${p.nb} membre(s)`.slice(0, 60), callback_data: `dif:ok:${p.id}` },
        { text: "✖️ Annuler", callback_data: `dif:no:${p.id}` },
      ]] },
    });
    return true;
  }

  return false;
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

  // ===== Messages =====
  // Ceux du salon d'administration passent d'abord par le traitement
  // administrateur ; s'il n'y reconnaît rien, le message suit la voie
  // ordinaire - le salon peut être la conversation privée de
  // l'administrateur, qui reste un membre comme un autre.
  if (maj.message) {
    const salon = String(maj.message.chat?.id ?? "");
    if (TELEGRAM_CHAT_ID && salon === String(TELEGRAM_CHAT_ID)
        && await traiterMessageAdmin(maj.message)) {
      return new Response("ok", { status: 200 });
    }
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

  // QUI a cliqué : les champs que Telegram joint à chaque clic. Ils
  // viennent de Telegram, pas d'une saisie, et servent au journal
  // d'administration (phase 86) - dans un groupe, chaque décision doit
  // avoir un auteur. Le nom d'affichage d'abord, l'identifiant @ ensuite
  // pour lever toute ambiguïté entre homonymes.
  const qui = quiEst(clic.from);

  // « type:verdict:uuid », par exemple « ins:ok:6f2c… »
  const donnee = String(clic.data ?? "");
  const sep = donnee.lastIndexOf(":");
  const action = sep === -1 ? "" : donnee.slice(0, sep);
  const id = sep === -1 ? "" : donnee.slice(sep + 1);
  // Un justificatif arrive en PHOTO : son texte est une légende, et se
  // réécrit par une autre méthode. Tout ce qui suit s'y adapte.
  const estPhoto = Array.isArray(clic.message?.photo) && clic.message.photo.length > 0;
  const avant = baseTexte(clic.message?.caption ?? clic.message?.text);
  const msgId = clic.message?.message_id;

  // ===== Publier - ou non - une nouveauté sur la chaîne publique =====
  //
  // Le message de proposition porte lui-même ce qu'il faut publier :
  // rien n'a été gardé en base entre les deux, et un bouton reste donc
  // valable aussi longtemps que son message existe.
  //
  // Telegram rend le texte SANS mise en forme : le gras du titre est
  // refait ici, la première ligne étant toujours le titre.
  if (action === "pub:go" || action === "pub:no") {
    // baseTexte, et non le texte brut : après un échec le message porte
    // déjà « ➤ Échec… », et le republier reviendrait à envoyer cette
    // ligne aux abonnés.
    const complet = avant;
    const coupe = complet.indexOf(SEPARATEUR);
    const annonce = coupe === -1 ? "" : complet.slice(coupe + SEPARATEUR.length).replace(/^\n+/, "");

    if (action === "pub:no") {
      await telegram("answerCallbackQuery", { callback_query_id: clic.id, text: "Non publié." });
      await reecrire(salon, msgId, estPhoto,
        `${esc(complet)}\n\n➤ <b>Non publié${qui ? " - décision de " + esc(qui) : ""}.</b>`);
      return new Response("ok", { status: 200 });
    }

    if (!annonce.trim() || !TELEGRAM_CHANNEL_ID) {
      await telegram("answerCallbackQuery", {
        callback_query_id: clic.id, show_alert: true,
        text: !TELEGRAM_CHANNEL_ID
          ? "TELEGRAM_CHANNEL_ID n'est pas configuré : impossible de publier."
          : "Ce message ne contient pas d'annonce à publier.",
      });
      return new Response("ok", { status: 200 });
    }

    const lignes = annonce.split("\n");
    // L'aperçu de lien est laissé ACTIF, contrairement aux
    // notifications : les pages de partage donnent une belle carte avec
    // titre et couverture, et c'est tout l'intérêt sur une chaîne.
    const corps = `<b>${esc(lignes[0])}</b>` + (lignes.length > 1 ? "\n" + esc(lignes.slice(1).join("\n")) : "");
    let publie = false;
    try {
      const r = await fetch(`https://api.telegram.org/bot${TELEGRAM_BOT_TOKEN}/sendMessage`, {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ chat_id: TELEGRAM_CHANNEL_ID, text: corps, parse_mode: "HTML" }),
      });
      publie = r.ok;
      if (!r.ok) console.error("telegram-webhook: publication chaîne", r.status, (await r.text()).slice(0, 200));
    } catch (e) {
      console.error("telegram-webhook: publication chaîne", String(e).slice(0, 200));
    }

    await telegram("answerCallbackQuery", {
      callback_query_id: clic.id,
      text: publie ? "Publié sur la chaîne." : "Échec de la publication.",
      ...(publie ? {} : { show_alert: true }),
    });
    // Les boutons ne sont retirés QUE si la publication a réussi : après
    // un échec, il faut pouvoir réessayer.
    await reecrire(salon, msgId, estPhoto,
      `${esc(complet)}\n\n➤ <b>${publie
        ? `Publié sur la chaîne${qui ? " par " + esc(qui) : ""}.`
        : "Échec de la publication - réessayez."}</b>`,
      publie ? null : [[
        { text: "📣 Publier sur la chaîne", callback_data: "pub:go:x" },
        { text: "✖️ Ne pas publier", callback_data: "pub:no:x" },
      ]]);
    return new Response("ok", { status: 200 });
  }

  // ===== Passer d'une liste d'information à une autre =====
  // Les justificatifs s'affichent en images, donc en NOUVEAUX messages ;
  // les autres réécrivent celui qu'on vient de toucher, pour ne pas
  // remplir le groupe à chaque coup d'œil.
  if (action === "lst:pnt" || LISTES[action]) {
    const quoi = action === "lst:pnt" ? "point" : LISTES[action].commande;
    await afficherListe(salon, quoi, quoi === "justificatifs"
      ? { callbackId: clic.id }
      : { msgId: msgId, estPhoto, callbackId: clic.id });
    return new Response("ok", { status: 200 });
  }

  // ===== Classer un justificatif reçu par le bot =====
  // Le classer n'est pas confirmer le paiement : ce sont deux gestes,
  // et les confondre ferait disparaître de la file un justificatif dont
  // le paiement n'a jamais été validé. Les boutons « Confirmer » posés
  // au-dessus s'en chargent, par la voie ordinaire.
  if ((action === "jt:ok" || action === "jt:no") && id) {
    const res = await rpc("statuer_justificatif", {
      p_id: id, p_statut: action === "jt:ok" ? "traite" : "ecarte", p_qui: qui || null,
    });
    await telegram("answerCallbackQuery", { callback_query_id: clic.id, text: res.slice(0, 190) });
    await reecrire(salon, msgId, estPhoto, `${esc(avant)}\n\n➤ <b>${esc(res)}</b>`,
      [[{ text: "🔎 Écran de vérification", url: SITE + "/membres/verification-admin.html" }]]);
    return new Response("ok", { status: 200 });
  }

  // ===== Une fiche choisie dans une liste de résultats =====
  // La liste reste affichée : on cherche souvent deux homonymes coup
  // sur coup, et la réécrire obligerait à relancer la recherche.
  if (action === "mf" && id) {
    await telegram("answerCallbackQuery", { callback_query_id: clic.id });
    await envoyerFiche(salon, id);
    return new Response("ok", { status: 200 });
  }

  // ===== Confirmation ou annulation d'une diffusion =====
  if ((action === "dif:ok" || action === "dif:no") && id) {
    const res = action === "dif:ok"
      ? await rpc("envoyer_diffusion", { p_id: id, p_qui: qui || null })
      : await rpc("annuler_diffusion", { p_id: id });
    await telegram("answerCallbackQuery", { callback_query_id: clic.id, text: res.slice(0, 190) });
    // Les boutons partent : recliquer « Envoyer » sur une annonce déjà
    // diffusée est le geste qu'on veut rendre impossible.
    await reecrire(salon, msgId, estPhoto, `${esc(avant)}\n\n➤ <b>${esc(res)}</b>`);
    return new Response("ok", { status: 200 });
  }

  // ===== « Prévenir le membre » : le menu des six messages =====
  if (action === "ins:msg" && id) {
    const nom = await rpc("nom_membre", { p_user_id: id });
    await telegram("answerCallbackQuery", { callback_query_id: clic.id });
    await reecrire(salon, msgId, estPhoto,
      `${esc(avant)}\n\n➤ <b>Quel message envoyer à ${esc(nom || "ce membre")} ?</b>`,
      [
        ...Object.entries(MESSAGES).map(([code, d]) => [{ text: d.bouton, callback_data: `${code}:${id}` }]),
        [FICHE_MEMBRE],
      ]);
    return new Response("ok", { status: 200 });
  }

  // ===== Un message choisi dans le menu =====
  // « ins:pay » reste accepté : les notifications déjà affichées dans le
  // groupe portent encore ce code, et un bouton qui ne répond plus est
  // pire qu'un bouton absent.
  const code = action === "ins:pay" ? "m:pay" : action;
  if (MESSAGES[code] && id) {
    // Le message libre demande d'abord son texte. Telegram ouvre le
    // clavier sur une réponse ; l'identifiant voyage dans la question.
    if (code === "m:lib") {
      const nom = await rpc("nom_membre", { p_user_id: id });
      await telegram("answerCallbackQuery", {
        callback_query_id: clic.id, text: "Répondez au message du bot avec votre texte.",
      });
      await telegram("sendMessage", {
        chat_id: salon,
        text: `✍️ Message libre pour ${nom || "ce membre"}.\n`
            + `Répondez à CE message avec le texte à lui envoyer.\n`
            + `[#${id}]`,
        reply_markup: {
          force_reply: true,
          input_field_placeholder: `Message pour ${nom || "le membre"}`.slice(0, 64),
        },
      });
      return new Response("ok", { status: 200 });
    }

    await proposerEnvoi({
      salon, id, code, qui, msgId, texteBase: avant, callbackId: clic.id, estPhoto,
    });
    return new Response("ok", { status: 200 });
  }

  // ===== Les actions en base (approuver, confirmer, refuser) =====
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
        body: JSON.stringify({ p_action: action, p_id: id, p_qui: qui || null }),
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

  // Le message est réécrit avec le verdict, et SES BOUTONS D'ACTION
  // RETIRÉS : sans cela, on peut recliquer indéfiniment et se demander si
  // l'action a vraiment eu lieu. « Voir la fiche » reste toujours.
  //
  // Une inscription qui vient d'être APPROUVÉE garde « Prévenir » - le
  // geste qui suit naturellement.
  const approuve = action === "ins:ok" && /approuvée/.test(resultat);
  const rangees: any[][] = [];
  if (approuve) rangees.push([{ text: "✉️ Prévenir le membre", callback_data: `ins:msg:${id}` }]);

  // Confirmer le paiement d'un justificatif ne classe pas le
  // justificatif lui-même : on garde ses boutons, sans quoi il resterait
  // « reçu » pour toujours et gonflerait le point du jour. Leur
  // identifiant ne tiendrait pas dans le callback_data de l'action ; il
  // est donc repris du clavier déjà affiché.
  const clavierActuel: any[][] = clic.message?.reply_markup?.inline_keyboard ?? [];
  const classement = clavierActuel
    .map((ligne) => ligne.filter((b: any) => String(b.callback_data ?? "").startsWith("jt:")))
    .filter((ligne) => ligne.length);
  rangees.push(...classement);

  // « Voir la fiche » doit mener là où l'on peut agir : un don ne se
  // traite pas dans l'écran de vérification des paiements.
  const ecranFiche = action.startsWith("ins") ? "/membres/validation.html"
    : action.startsWith("don") ? "/membres/dons-admin.html"
    : "/membres/verification-admin.html";
  rangees.push([{ text: "🔎 Voir la fiche", url: SITE + ecranFiche }]);

  await reecrire(salon, msgId, estPhoto, `${esc(avant)}\n\n➤ <b>${esc(resultat)}</b>`, rangees);

  return new Response("ok", { status: 200 });
});

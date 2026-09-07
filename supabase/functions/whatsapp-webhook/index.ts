// supabase/functions/whatsapp-webhook/index.ts
//
// Reçoit les messages que les membres écrivent au numéro WhatsApp de
// l'association, et les repose dans le salon Telegram d'administration.
// La réponse, elle, se tape directement dans Telegram : voir
// « traiterReponseWhatsApp » dans telegram-webhook.
//
// POURQUOI CETTE FONCTION EXISTE. Un numéro basculé sur l'API Cloud ne
// s'ouvre plus dans aucune application WhatsApp. Sans elle, un membre
// qui répond à une diffusion écrit dans le vide : personne ne voit son
// message, et lui croit avoir joint l'association.
//
// LES 24 HEURES, ET C'EST LA RÈGLE QUI COMMANDE TOUT. Meta n'autorise un
// message libre - hors modèle - que dans les 24 heures suivant le
// dernier message du correspondant. C'est donc précisément quand un
// membre écrit que la réponse libre s'ouvre. Passé ce délai, seul un
// modèle approuvé peut repartir. Le message reposé dans Telegram annonce
// l'heure limite pour que personne ne le découvre en essayant.
//
// LES MESSAGES SONT ENREGISTRÉS depuis la phase 104, dans
// whatsapp_messages : c'est ce qui permet la boîte de réception de
// l'espace membres (membres/whatsapp-boite.html), où l'on relit un
// échange et où l'on travaille à plusieurs. L'enregistrement ne peut
// PAS empêcher le dépôt Telegram : si la base refuse, le message doit
// tout de même parvenir à l'administrateur, qui reste le canal
// d'alerte. Meta réessayant un webhook resté sans réponse, l'insertion
// vise l'identifiant Meta du message et ignore les doublons.
//
// DEPUIS LA PHASE 105, une image ou un message vocal reçu est aussi
// TÉLÉCHARGÉ et déposé dans le bucket privé whatsapp-medias, pour
// être consultable dans la boîte. Échouer à le télécharger n'est jamais
// bloquant : le texte de repli (« [une image] ») suffit à savoir
// qu'il faut aller voir, seule la pièce jointe manquerait.
//
// LA RÉPONSE PAR TELEGRAM RESTE INCHANGÉE. Le numéro de l'expéditeur voyage dans
// une marque « [wa:221...] » écrite au bas du message Telegram. Quand
// l'administrateur répond à ce message, Telegram nous rend la marque :
// il n'y a donc rien à garder entre deux appels. C'est le mécanisme déjà
// employé pour « [#uuid] » dans telegram-webhook - une seule idée à
// comprendre plutôt que deux.
//
// ELLE EST PUBLIQUEMENT ACCESSIBLE, comme telegram-webhook : Meta doit
// pouvoir l'appeler sans session. DEUX barrières la protègent :
//
//   1. La SIGNATURE « X-Hub-Signature-256 », un HMAC-SHA256 du corps
//      brut avec la clé secrète de l'app. Sans elle, quiconque
//      connaîtrait l'adresse pourrait injecter de faux « messages de
//      membres » dans votre salon d'administration - et vous y
//      répondriez de bonne foi.
//   2. Le jeton de vérification, qui n'intervient qu'à l'enregistrement
//      du webhook chez Meta (la poignée de main en GET).
//
// LES ACCUSÉS DE LIVRAISON SONT IGNORÉS, délibérément. Meta envoie un
// événement « statuses » par message envoyé et par changement d'état.
// Sur une diffusion à deux cents membres, cela ferait six cents
// notifications Telegram pour zéro information utile. Seuls les
// « messages » entrants sont repris.
//
// Secrets requis (service edge-functions) :
//   META_APP_SECRET      - Paramètres de base de l'app > Clé secrète
//   META_VERIFY_TOKEN    - une chaîne au hasard, la même que chez Meta
//   META_WHATSAPP_TOKEN  - déjà posé pour la diffusion ; sert ICI à
//                          télécharger les médias reçus (phase 105)
//   META_PHONE_NUMBER_ID - déjà posé pour la diffusion
//   TELEGRAM_BOT_TOKEN   - déjà posé
//   TELEGRAM_CHAT_ID     - déjà posé : le salon d'administration
//   SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY - fournis automatiquement

const SUPABASE_URL = Deno.env.get("SUPABASE_URL");
const SERVICE_ROLE_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
const META_APP_SECRET = Deno.env.get("META_APP_SECRET");
const META_WHATSAPP_TOKEN = Deno.env.get("META_WHATSAPP_TOKEN");
const META_VERIFY_TOKEN = Deno.env.get("META_VERIFY_TOKEN");
const TELEGRAM_BOT_TOKEN = Deno.env.get("TELEGRAM_BOT_TOKEN");
const TELEGRAM_CHAT_ID = Deno.env.get("TELEGRAM_CHAT_ID");

// Le texte d'un membre est arbitraire : un « < » ou un « & » suffirait à
// faire échouer l'envoi en parse_mode HTML, et la réponse serait perdue
// sans que personne ne le sache.
function htm(s: unknown): string {
  return String(s ?? "")
    .replace(/&/g, "&amp;")
    .replace(/</g, "&lt;")
    .replace(/>/g, "&gt;");
}

// Le texte d'un membre ne doit jamais pouvoir RESSEMBLER à notre marque.
// Sans cela, « [wa:999999] » écrit dans son message ferait partir la
// réponse de l'administrateur vers un numéro qu'il aurait choisi. La
// lecture, côté Telegram, ancre déjà la marque en fin de message ; ceci
// est le second verrou, et il évite aussi d'afficher un leurre crédible
// dans le salon.
function sansMarque(s: string): string {
  return s.replace(/\[\s*wa\s*:/gi, "[wa - ");
}

// Enregistre un message entrant. « on_conflict » vise l'identifiant
// Meta : Meta réessaie un webhook resté sans réponse, et le même
// message apparaîtrait sinon deux fois dans le fil.
//
// Ne lève jamais : un échec d'enregistrement est ennuyeux, un message
// de membre perdu ne l'est pas au même titre. Le dépôt Telegram suit,
// quoi qu'il arrive ici.
async function enregistrer(ligne: Record<string, unknown>): Promise<void> {
  if (!SUPABASE_URL || !SERVICE_ROLE_KEY) return;
  try {
    const res = await fetch(
      `${SUPABASE_URL}/rest/v1/whatsapp_messages?on_conflict=wa_message_id`,
      {
        method: "POST",
        headers: {
          apikey: SERVICE_ROLE_KEY,
          Authorization: `Bearer ${SERVICE_ROLE_KEY}`,
          "Content-Type": "application/json",
          Prefer: "resolution=ignore-duplicates,return=minimal",
        },
        body: JSON.stringify(ligne),
      },
    );
    if (!res.ok) {
      console.error("whatsapp-webhook: enregistrement refusé",
        res.status, (await res.text()).slice(0, 300));
    }
  } catch (e) {
    console.error("whatsapp-webhook: base injoignable", e);
  }
}

// Types de message qui portent effectivement un fichier chez Meta.
// « text », « location », « contacts », « button », « interactive »
// n'ont rien à télécharger.
const TYPES_MEDIA = ["image", "audio", "video", "document", "sticker"];

// Deux appels chez Meta, dans cet ordre : le message entrant ne porte
// qu'un IDENTIFIANT de média, pas une adresse. Il faut d'abord demander
// l'adresse réelle du fichier, puis la télécharger avec le même jeton -
// cette seconde adresse n'est valable que quelques minutes.
async function telechargerMedia(
  mediaId: string,
): Promise<{ octets: ArrayBuffer; mime: string } | null> {
  if (!META_WHATSAPP_TOKEN) return null;
  try {
    const infoRes = await fetch(`https://graph.facebook.com/v20.0/${mediaId}`, {
      headers: { Authorization: `Bearer ${META_WHATSAPP_TOKEN}` },
    });
    if (!infoRes.ok) {
      console.error("whatsapp-webhook: adresse du média introuvable", infoRes.status);
      return null;
    }
    const info = await infoRes.json();
    if (!info.url) return null;

    const fichierRes = await fetch(String(info.url), {
      headers: { Authorization: `Bearer ${META_WHATSAPP_TOKEN}` },
    });
    if (!fichierRes.ok) {
      console.error("whatsapp-webhook: téléchargement du média refusé", fichierRes.status);
      return null;
    }
    return {
      octets: await fichierRes.arrayBuffer(),
      mime: String(info.mime_type || "application/octet-stream"),
    };
  } catch (e) {
    console.error("whatsapp-webhook: Meta injoignable pour le média", e);
    return null;
  }
}

// « x-upsert » couvre un cas précis : Meta réessaie un webhook resté
// sans réponse, et sans cette option le second essai échouerait sur un
// fichier déjà présent au même chemin - alors que l'enregistrement en
// base, lui, ignore déjà le doublon.
async function deposerMedia(
  chemin: string,
  octets: ArrayBuffer,
  mime: string,
): Promise<boolean> {
  if (!SUPABASE_URL || !SERVICE_ROLE_KEY) return false;
  try {
    const res = await fetch(
      `${SUPABASE_URL}/storage/v1/object/whatsapp-medias/${chemin}`,
      {
        method: "POST",
        headers: {
          apikey: SERVICE_ROLE_KEY,
          Authorization: `Bearer ${SERVICE_ROLE_KEY}`,
          "Content-Type": mime,
          "x-upsert": "true",
        },
        body: octets,
      },
    );
    if (!res.ok) {
      console.error("whatsapp-webhook: dépôt du média refusé",
        res.status, (await res.text()).slice(0, 300));
      return false;
    }
    return true;
  } catch (e) {
    console.error("whatsapp-webhook: stockage injoignable", e);
    return false;
  }
}

async function telegram(methode: string, corps: Record<string, unknown>): Promise<void> {
  if (!TELEGRAM_BOT_TOKEN) return;
  try {
    const res = await fetch(`https://api.telegram.org/bot${TELEGRAM_BOT_TOKEN}/${methode}`, {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify(corps),
    });
    if (!res.ok) {
      console.error("whatsapp-webhook: Telegram", res.status, (await res.text()).slice(0, 300));
    }
  } catch (e) {
    console.error("whatsapp-webhook: Telegram injoignable", e);
  }
}

// Comparaison À TEMPS CONSTANT. Une comparaison ordinaire s'arrête au
// premier caractère qui diffère : le temps de réponse renseigne alors,
// signature après signature, sur le préfixe correct.
function memeChaine(a: string, b: string): boolean {
  if (a.length !== b.length) return false;
  let diff = 0;
  for (let i = 0; i < a.length; i++) diff |= a.charCodeAt(i) ^ b.charCodeAt(i);
  return diff === 0;
}

async function signatureValide(brut: string, entete: string | null): Promise<boolean> {
  if (!META_APP_SECRET || !entete || !entete.startsWith("sha256=")) return false;
  const attendu = entete.slice(7).toLowerCase();
  const cle = await crypto.subtle.importKey(
    "raw",
    new TextEncoder().encode(META_APP_SECRET),
    { name: "HMAC", hash: "SHA-256" },
    false,
    ["sign"],
  );
  const sig = await crypto.subtle.sign("HMAC", cle, new TextEncoder().encode(brut));
  const calcule = [...new Uint8Array(sig)].map((b) => b.toString(16).padStart(2, "0")).join("");
  return memeChaine(calcule, attendu);
}

// Ce qu'on sait dire d'un message qui n'est pas du texte. On ne
// télécharge pas les médias : nommer le type suffit à savoir qu'il faut
// aller voir, et éviter d'archiver des pièces jointes non sollicitées
// est un choix, pas une paresse.
function resume(m: Record<string, any>): string {
  switch (m.type) {
    case "text":     return String(m.text?.body ?? "");
    case "image":    return "[une image]" + (m.image?.caption ? " " + m.image.caption : "");
    case "audio":    return "[un message vocal]";
    case "video":    return "[une vidéo]" + (m.video?.caption ? " " + m.video.caption : "");
    case "document": return "[un document" + (m.document?.filename ? " : " + m.document.filename : "") + "]";
    case "sticker":  return "[un autocollant]";
    case "location": return "[une position]";
    case "contacts": return "[une fiche contact]";
    // Un clic sur le bouton d'un modèle revient sous cette forme.
    case "button":   return String(m.button?.text ?? "[un bouton]");
    case "interactive":
      return String(m.interactive?.button_reply?.title
        ?? m.interactive?.list_reply?.title ?? "[une réponse]");
    default:         return "[message de type " + String(m.type ?? "inconnu") + "]";
  }
}

function heureLimite(horodatage: unknown): string {
  const sec = Number(horodatage);
  const base = Number.isFinite(sec) && sec > 0 ? sec * 1000 : Date.now();
  return new Date(base + 24 * 3600 * 1000).toLocaleString("fr-FR", {
    timeZone: "Africa/Dakar",
    day: "2-digit", month: "2-digit", hour: "2-digit", minute: "2-digit",
  });
}

async function reposerDansTelegram(charge: Record<string, any>): Promise<void> {
  for (const entree of charge.entry ?? []) {
    for (const chg of entree.changes ?? []) {
      const val = chg.value ?? {};

      // Les accusés de livraison ne sont pas repris : voir l'en-tête.
      const messages = val.messages ?? [];
      if (!messages.length) continue;

      // Meta joint le nom du profil WhatsApp à part, indexé par numéro.
      const noms: Record<string, string> = {};
      for (const c of val.contacts ?? []) {
        if (c.wa_id) noms[c.wa_id] = c.profile?.name ?? "";
      }

      for (const m of messages) {
        const numero = String(m.from ?? "").replace(/[^0-9]/g, "");
        if (!numero) continue;
        const nom = noms[numero] || "";
        const contenu = resume(m);

        // Téléchargement du fichier, s'il y en a un. Séquentiel plutôt
        // qu'en parallèle : un webhook porte presque toujours un seul
        // message, et l'appel entier tourne déjà en arrière-plan
        // (EdgeRuntime.waitUntil, plus bas) - Meta a déjà son 200.
        let mediaPath: string | null = null;
        let mediaMime: string | null = null;
        const mediaId = TYPES_MEDIA.includes(String(m.type)) ? m[m.type]?.id : null;
        if (mediaId) {
          const media = await telechargerMedia(String(mediaId));
          if (media) {
            const chemin = `${numero}/${m.id || crypto.randomUUID()}`;
            if (await deposerMedia(chemin, media.octets, media.mime)) {
              mediaPath = chemin;
              mediaMime = media.mime;
            }
          }
        }

        // La marque n'est PAS retirée ici : ce qui est archivé doit
        // être ce que le membre a écrit. Le détournement que « sansMarque »
        // empêche ne concerne que Telegram, où la marque commande.
        await enregistrer({
          telephone: numero,
          sens: "entrant",
          texte: contenu,
          type_message: String(m.type ?? "text"),
          wa_message_id: m.id ? String(m.id) : null,
          nom_affiche: nom || null,
          media_path: mediaPath,
          media_mime: mediaMime,
        });

        const texte =
          "💬 <b>Message WhatsApp</b>\n" +
          (nom ? htm(nom) + " " : "") + "<code>+" + htm(numero) + "</code>\n\n" +
          htm(sansMarque(contenu)) + "\n\n" +
          (mediaPath
            ? "<i>Consultable dans la boîte de réception de l'espace membres.</i>\n"
            : "") +
          "<i>Répondez à ce message pour lui écrire. " +
          "Réponse libre possible jusqu'au " + htm(heureLimite(m.timestamp)) + ".</i>\n" +
          "[wa:" + numero + "]";

        await telegram("sendMessage", {
          chat_id: TELEGRAM_CHAT_ID,
          text: texte,
          parse_mode: "HTML",
          disable_web_page_preview: true,
        });
      }
    }
  }
}

Deno.serve(async (req: Request) => {
  const url = new URL(req.url);

  // ---- La poignée de main, à l'enregistrement du webhook ----
  if (req.method === "GET") {
    const mode = url.searchParams.get("hub.mode");
    const jeton = url.searchParams.get("hub.verify_token");
    const defi = url.searchParams.get("hub.challenge");
    if (mode === "subscribe" && META_VERIFY_TOKEN && jeton === META_VERIFY_TOKEN && defi) {
      return new Response(defi, { status: 200, headers: { "Content-Type": "text/plain" } });
    }
    console.error("whatsapp-webhook: poignée de main refusée");
    return new Response("Forbidden", { status: 403 });
  }

  if (req.method !== "POST") return new Response("Method Not Allowed", { status: 405 });

  // Le corps est lu UNE fois, en brut : la signature porte sur les
  // octets reçus, pas sur un objet reconstruit puis re-sérialisé, qui
  // n'aurait pas le même texte.
  const brut = await req.text();

  if (!await signatureValide(brut, req.headers.get("x-hub-signature-256"))) {
    console.error("whatsapp-webhook: signature invalide - appel rejeté");
    return new Response("Forbidden", { status: 403 });
  }

  let charge: Record<string, any>;
  try {
    charge = JSON.parse(brut);
  } catch {
    return new Response("Bad Request", { status: 400 });
  }

  // Meta attend un 200 rapide et RÉESSAIE sinon - ce qui produirait des
  // doublons dans le salon. On accuse réception tout de suite et on
  // publie ensuite, hors du chemin de réponse.
  const fini = reposerDansTelegram(charge).catch((e) =>
    console.error("whatsapp-webhook: échec du dépôt Telegram", e)
  );
  // @ts-ignore - EdgeRuntime n'est pas typé dans Deno
  if (typeof EdgeRuntime !== "undefined") EdgeRuntime.waitUntil(fini);
  else await fini;

  return new Response("EVENT_RECEIVED", { status: 200 });
});

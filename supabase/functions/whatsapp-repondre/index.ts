// supabase/functions/whatsapp-repondre/index.ts
//
// Envoie une réponse WhatsApp en texte libre, depuis la boîte de
// réception de l'espace membres (membres/whatsapp-boite.html).
//
// POURQUOI UNE FONCTION SÉPARÉE de notify-members-whatsapp. Celle-là
// diffuse un MODÈLE approuvé à une audience ; celle-ci envoie un texte
// libre à une personne. Les deux règles de Meta n'ont rien de commun -
// l'une coûte un message facturé par destinataire et s'adresse à qui n'a
// rien demandé, l'autre est gratuite mais n'est permise que dans les 24
// heures suivant le message du correspondant. Les mélanger aurait donné
// une fonction où la moitié des contrôles ne s'applique jamais.
//
// LA FENÊTRE DE 24 HEURES COMMANDE TOUT. Meta refuse (erreur 131047) un
// message libre au-delà de 24 heures après le dernier message reçu de
// la personne. Ce n'est pas une panne, c'est la règle : elle est donc
// traduite en français, et la page l'affiche en compte à rebours pour
// qu'on ne l'apprenne pas en écrivant.
//
// ELLE EST APPELÉE DEPUIS LE NAVIGATEUR avec le jeton de session de
// l'administrateur, comme notify-members-whatsapp : « Verify JWT » doit
// rester ACTIVÉ, et la fonction contrôle elle-même le rôle.
//
// CE QUI EST ARCHIVÉ, ET QUAND. La ligne n'est écrite qu'après un envoi
// accepté par Meta. Archiver avant, ou malgré un refus, ferait croire à
// une réponse que le membre n'a jamais reçue - exactement le genre
// d'erreur qu'une boîte de réception ne doit pas commettre.
//
// Secrets requis (service edge-functions) :
//   SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY - fournis automatiquement
//   META_WHATSAPP_TOKEN  - déjà posé pour la diffusion
//   META_PHONE_NUMBER_ID - déjà posé pour la diffusion

import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const SUPABASE_URL = Deno.env.get("SUPABASE_URL")!;
const SERVICE_ROLE_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
const META_WHATSAPP_TOKEN = Deno.env.get("META_WHATSAPP_TOKEN");
const META_PHONE_NUMBER_ID = Deno.env.get("META_PHONE_NUMBER_ID");

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

// Un texte libre accepte les retours à la ligne, contrairement au
// paramètre d'un modèle : rien n'est aplati ici. Seules les fins de
// ligne Windows sont normalisées, pour que ce qui est archivé soit
// exactement ce qui a été envoyé.
function normaliser(texte: string): string {
  return String(texte || "").replace(/\r\n?/g, "\n").trim();
}

Deno.serve(async (req: Request) => {
  if (req.method === "OPTIONS") return new Response(null, { headers: CORS_HEADERS });
  if (req.method !== "POST") return json({ error: "Méthode non autorisée" }, 405);

  const jwt = (req.headers.get("authorization") || "").replace(/^Bearer /, "");
  if (!jwt) return json({ error: "Non authentifié" }, 401);

  const admin = createClient(SUPABASE_URL, SERVICE_ROLE_KEY);

  const { data: userData, error: userErr } = await admin.auth.getUser(jwt);
  if (userErr || !userData?.user) return json({ error: "Session invalide" }, 401);

  const { data: profil } = await admin
    .from("profiles")
    .select("role, full_name")
    .eq("id", userData.user.id)
    .single();

  if (!profil || !["admin", "super_admin"].includes(profil.role)) {
    return json({ error: "Réservé aux administrateurs" }, 403);
  }

  if (!META_WHATSAPP_TOKEN || !META_PHONE_NUMBER_ID) {
    return json({
      error: "WhatsApp n'est pas configuré sur ce serveur : META_WHATSAPP_TOKEN "
        + "ou META_PHONE_NUMBER_ID manque sur le service edge-functions.",
    }, 500);
  }

  let charge: { telephone?: string; message?: string };
  try {
    charge = await req.json();
  } catch {
    return json({ error: "JSON invalide" }, 400);
  }

  const telephone = String(charge.telephone || "").replace(/[^0-9]/g, "");
  const message = normaliser(charge.message || "");

  if (telephone.length < 8) return json({ error: "Numéro invalide" }, 400);
  if (!message) return json({ error: "Message vide" }, 400);
  if (message.length > 4000) {
    return json({ error: "Message trop long (4000 caractères maximum)" }, 400);
  }

  // La fenêtre est vérifiée ICI, avant d'appeler Meta. Meta la ferait
  // respecter de toute façon, mais son refus arrive sous forme de code
  // 131047 : autant répondre tout de suite, et dire depuis quand.
  const { data: dernierEntrant } = await admin
    .from("whatsapp_messages")
    .select("cree_le")
    .eq("telephone", telephone)
    .eq("sens", "entrant")
    .order("cree_le", { ascending: false })
    .limit(1)
    .maybeSingle();

  if (dernierEntrant?.cree_le) {
    const limite = new Date(dernierEntrant.cree_le).getTime() + 24 * 3600 * 1000;
    if (Date.now() > limite) {
      return json({
        error: "Plus de 24 heures se sont écoulées depuis son dernier message : "
          + "Meta n'autorise plus de réponse libre. Il faut attendre qu'il "
          + "réécrive, ou lui envoyer un modèle depuis l'écran Diffusion.",
        fenetre_fermee: true,
      }, 409);
    }
  }
  // Aucun message entrant connu : on tente quand même. La table ne
  // remonte qu'au déploiement de la phase 104, et refuser ici priverait
  // d'une réponse légitime à quelqu'un qui vient d'écrire.

  const res = await fetch(
    `https://graph.facebook.com/v20.0/${META_PHONE_NUMBER_ID}/messages`,
    {
      method: "POST",
      headers: {
        Authorization: `Bearer ${META_WHATSAPP_TOKEN}`,
        "Content-Type": "application/json",
      },
      body: JSON.stringify({
        messaging_product: "whatsapp",
        to: telephone,
        type: "text",
        text: { body: message, preview_url: false },
      }),
    },
  );

  if (!res.ok) {
    const corps = await res.json().catch(() => ({}));
    const err = (corps as { error?: { code?: number; message?: string } })?.error ?? {};
    const code = Number(err.code ?? 0);
    if (code === 131047 || /24 hours/i.test(String(err.message ?? ""))) {
      return json({
        error: "Meta refuse la réponse libre : plus de 24 heures se sont "
          + "écoulées depuis son message.",
        fenetre_fermee: true,
      }, 409);
    }
    console.error("whatsapp-repondre: refus Meta", res.status, JSON.stringify(err).slice(0, 300));
    return json({ error: "Échec de l'envoi : " + String(err.message ?? res.status) }, 502);
  }

  // Envoyé : on archive. Un échec d'archivage ne doit pas faire croire
  // que le message n'est pas parti - il l'est.
  const { error: archErr } = await admin.from("whatsapp_messages").insert({
    telephone,
    sens: "sortant",
    texte: message,
    type_message: "text",
    envoye_par: userData.user.id,
    envoye_par_nom: profil.full_name,
    via: "espace-membres",
  });
  if (archErr) console.error("whatsapp-repondre: archivage refusé", archErr);

  return json({ ok: true, archive: !archErr });
});

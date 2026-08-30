// supabase/functions/notify-membre/index.ts
//
// Envoie un e-mail AU MEMBRE (et non à l'administration, rôle tenu par
// notify-admin) pour les évènements qui le concernent directement :
//
//   compte_approuve      - son compte vient d'être validé
//   compte_refuse        - sa demande n'a pas été retenue
//   carte_expire_bientot - sa carte arrive à échéance
//
// Et un type COLLECTIF, appelé par le bouton de relance en masse
// (phase 96) :
//
//   rappel_masse         - un tableau « destinataires », chacun avec son
//                          propre titre et son propre corps, remis à
//                          Resend en UN SEUL appel (point d'entrée
//                          « batch »). Un appel par membre aurait fait
//                          exploser le plafond de débit de Resend, et
//                          les refus 429 seraient passés inaperçus :
//                          l'appelant SQL avale les erreurs réseau.
//
// Appelée UNIQUEMENT côté serveur, par les triggers Postgres via pg_net
// (voir supabase/phase50-notifications-membre.sql) : aucun préflight CORS
// à gérer.
//
// Secrets : les MÊMES que notify-admin, déjà configurés sur l'instance -
// aucun nouveau secret à créer.
//   RESEND_API_KEY      - clé API Resend
//   NOTIFY_ADMIN_SECRET - jeton partagé avec le trigger SQL (fail-closed)
//   NOTIFY_FROM_EMAIL   - optionnel, adresse d'expédition
//
// ATTENTION - contrairement à notify-admin, qui n'écrit qu'à une seule
// adresse, cette fonction écrit à des adresses quelconques. Resend ne
// l'autorise QUE depuis un domaine vérifié : tant qu'amstc.org n'est pas
// vérifié dans Resend, ces e-mails seront refusés. Voir
// README-espace-membres.md.

const RESEND_API_KEY = Deno.env.get("RESEND_API_KEY");
const NOTIFY_SECRET = Deno.env.get("NOTIFY_ADMIN_SECRET");
const FROM_EMAIL = Deno.env.get("NOTIFY_FROM_EMAIL") || "AMSTC <onboarding@resend.dev>";

const SITE = "https://amstc.org";

function esc(v: unknown): string {
  return String(v ?? "-").replace(
    /[<>&]/g,
    (c) => ({ "<": "&lt;", ">": "&gt;", "&": "&amp;" } as Record<string, string>)[c],
  );
}

// Enveloppe commune : le message doit rester lisible dans les clients qui
// n'affichent pas les styles, d'où la mise en forme en ligne et minimale.
function gabarit(titre: string, corps: string): string {
  return `
    <div style="font-family:Arial,Helvetica,sans-serif;color:#0B2E17;line-height:1.6;max-width:560px;">
      <div style="background:#06441C;padding:18px 24px;">
        <span style="color:#F8B718;font-size:20px;font-weight:bold;letter-spacing:1px;">AMSTC</span>
      </div>
      <div style="padding:24px;">
        <h2 style="color:#06441C;font-size:18px;margin:0 0 14px;">${titre}</h2>
        ${corps}
      </div>
      <div style="padding:16px 24px;border-top:1px solid #ddd;font-size:12px;color:#5B6E60;">
        Association Médico-Sociale des Talibés Cheikh -
        <a href="${SITE}" style="color:#17763B;">amstc.org</a>
        <br>&copy;AMSTC
      </div>
    </div>`;
}

function bouton(url: string, libelle: string): string {
  return `<p style="margin:22px 0;">
    <a href="${url}" style="background:#17763B;color:#fff;text-decoration:none;padding:12px 24px;border-radius:999px;display:inline-block;font-weight:bold;">${libelle}</a>
  </p>`;
}

// Chemin à suivre, sous le bouton. Certains clients de messagerie
// n'affichent pas les boutons, et un message lu sur téléphone est souvent
// rouvert plus tard sur un autre appareil : l'adresse doit donc figurer en
// toutes lettres, et le parcours dans le site être écrit.
function chemin(url: string, parcours: string): string {
  return `<p style="font-size:13px;color:#5B6E60;margin-top:18px;">
    <strong>Où aller :</strong> ${esc(parcours)}<br>
    <a href="${url}" style="color:#17763B;word-break:break-all;">${esc(url)}</a>
  </p>`;
}

function construireEmail(
  eventType: string,
  data: Record<string, any>,
): { subject: string; html: string } | null {
  const prenom = esc(data.first_name || data.full_name || "");
  const bonjour = prenom && prenom !== "-" ? `Bonjour ${prenom},` : "Bonjour,";

  switch (eventType) {
    case "compte_approuve":
      return {
        subject: "Votre compte AMSTC est actif",
        html: gabarit(
          "Votre compte est validé",
          `<p>${bonjour}</p>
           <p>Votre inscription à l'espace membres de l'AMSTC vient d'être validée
              par l'administration. Vous pouvez dès maintenant vous connecter avec
              l'adresse <strong>${esc(data.email)}</strong>.</p>
           ${bouton(SITE + "/membres/connexion.html", "Accéder à l'espace membres")}
           <p style="font-size:13px;color:#5B6E60;">Vous y trouverez votre carte de
              membre, l'annuaire, les formations, la médiathèque et le forum.</p>
           ${chemin(SITE + "/membres/connexion.html", "Espace membres > Connexion")}`,
        ),
      };

    case "compte_refuse":
      return {
        subject: "Votre demande d'inscription à l'AMSTC",
        html: gabarit(
          "Votre demande n'a pas été retenue",
          `<p>${bonjour}</p>
           <p>Votre demande d'inscription à l'espace membres de l'AMSTC n'a pas été
              retenue pour le moment.</p>
           <p>S'il s'agit d'une erreur ou si vous souhaitez des précisions, écrivez-nous
              à <a href="mailto:contact@amstc.org" style="color:#17763B;">contact@amstc.org</a>
              en rappelant l'adresse utilisée lors de votre inscription.</p>`,
        ),
      };

    case "carte_expire_bientot": {
      const annee = esc(data.card_valid_until);
      return {
        subject: `Votre carte de membre AMSTC expire fin ${annee}`,
        html: gabarit(
          "Votre carte arrive à échéance",
          `<p>${bonjour}</p>
           <p>Votre carte de membre est valable jusqu'à la fin de l'année
              <strong>${annee}</strong>. Pour continuer à bénéficier de l'accès aux
              contenus réservés, pensez à renouveler votre cotisation.</p>
           ${bouton(SITE + "/membres/profil.html?open=validity", "Renouveler ma carte")}
           <p style="font-size:13px;color:#5B6E60;">Si votre cotisation est déjà réglée,
              ce message ne demande aucune action de votre part.</p>
           ${chemin(SITE + "/membres/profil.html?open=validity",
                    "Espace membres > Carte de membre et Cotisations > Validité de la carte")}`,
        ),
      };
    }

    // Rappel envoyé à la demande par un administrateur, depuis la fiche du
    // membre. Le titre et le corps sont composés côté SQL
    // (envoyer_rappel_membre) : ajouter un nouveau type de rappel ne
    // demande donc jamais de redéployer cette fonction.
    case "rappel_admin": {
      const titre = esc(data.titre) || "Message de l'AMSTC";
      const corps = String(data.corps ?? "").trim();
      if (!corps) return null;
      // Le texte est saisi par l'administration : il est échappé, puis ses
      // sauts de ligne deviennent des paragraphes.
      //
      // Les adresses du site sont ensuite rendues cliquables : le corps se
      // termine par « Où aller : … » suivi d'un lien, et un lien non
      // cliquable dans un e-mail oblige à le recopier à la main. La
      // transformation intervient APRÈS l'échappement, sur un texte donc
      // déjà inoffensif.
      const paragraphes = esc(corps)
        .split(/\n{2,}/)
        .map((p) =>
          `<p>${
            p.replace(/\n/g, "<br>")
             .replace(/https:\/\/[^\s<]+/g,
               (u) => `<a href="${u}" style="color:#17763B;word-break:break-all;">${u}</a>`)
          }</p>`
        )
        .join("");
      // Le bouton mène à la section concernée (validité, cotisations…),
      // pas à la seule page de connexion.
      const cible = String(data.lien ?? "").startsWith(SITE)
        ? String(data.lien)
        : SITE + "/membres/connexion.html";
      return {
        subject: titre,
        html: gabarit(titre, `<p>${bonjour}</p>${paragraphes}
          ${bouton(cible, "Ouvrir mon espace membres")}`),
      };
    }

    default:
      return null;
  }
}

Deno.serve(async (req: Request) => {
  if (req.method !== "POST") {
    return new Response("Method not allowed", { status: 405 });
  }

  // Fail-closed : sans jeton configuré, la fonction refuse tout, plutôt
  // que de devenir un relais d'envoi ouvert.
  if (!NOTIFY_SECRET) {
    console.error("NOTIFY_ADMIN_SECRET absent : envoi refusé.");
    return new Response("Not configured", { status: 503 });
  }
  if (req.headers.get("Authorization") !== `Bearer ${NOTIFY_SECRET}`) {
    return new Response("Unauthorized", { status: 401 });
  }
  if (!RESEND_API_KEY) {
    console.error("RESEND_API_KEY absent : envoi impossible.");
    return new Response("Not configured", { status: 503 });
  }

  let body: Record<string, any>;
  try {
    body = await req.json();
  } catch {
    return new Response("Invalid JSON", { status: 400 });
  }

  // ===== Mode LOT (phase 96) =====
  // Le corps porte un tableau « destinataires » plutôt qu'une adresse.
  // Chaque entrée a la forme d'un rappel_admin : on réutilise donc le
  // même compositeur, et les courriels sont mot pour mot ceux qu'envoie
  // le bouton « Prévenir » d'une fiche.
  if (Array.isArray(body.destinataires)) {
    const liste = body.destinataires.filter(
      (d: any) => d && typeof d.email === "string" && d.email.includes("@"),
    );
    if (liste.length === 0) {
      return new Response("Missing recipients", { status: 400 });
    }

    const messages: Array<Record<string, unknown>> = [];
    for (const d of liste) {
      const m = construireEmail("rappel_admin", d);
      if (m) {
        messages.push({
          from: FROM_EMAIL,
          to: [String(d.email).trim()],
          subject: m.subject,
          html: m.html,
        });
      }
    }
    if (messages.length === 0) {
      return new Response("Nothing to send", { status: 400 });
    }

    // Resend n'accepte pas plus de 100 messages par appel. L'appelant SQL
    // découpe déjà par 50, mais on ne se fie pas à l'appelant : un lot
    // trop gros serait refusé en entier, donc silencieusement perdu.
    const envoyerLots = async () => {
      let envoyes = 0;
      let echecs = 0;
      for (let i = 0; i < messages.length; i += 100) {
        const paquet = messages.slice(i, i + 100);
        try {
          const r = await fetch("https://api.resend.com/emails/batch", {
            method: "POST",
            headers: {
              Authorization: `Bearer ${RESEND_API_KEY}`,
              "Content-Type": "application/json",
            },
            body: JSON.stringify(paquet),
          });
          if (r.ok) {
            envoyes += paquet.length;
          } else {
            echecs += paquet.length;
            console.error("Resend a refusé un lot :", r.status, await r.text());
          }
        } catch (e) {
          echecs += paquet.length;
          console.error("Appel à Resend impossible :", String(e));
        }
        // Souffler entre deux paquets : le plafond de Resend se compte à la
        // seconde, et rien ne presse une relance mensuelle.
        if (i + 100 < messages.length) {
          await new Promise((resolve) => setTimeout(resolve, 600));
        }
      }
      console.log(`rappel_masse : ${envoyes} envoyé(s), ${echecs} en échec.`);
    };

    // RÉPONDRE TOUT DE SUITE, ET ENVOYER APRÈS.
    //
    // pg_net coupe la communication au bout de 5 secondes. Un démarrage à
    // froid du conteneur, plus l'appel à Resend, dépasse ce délai : mesuré
    // sur la première mise en service, 5801 ms pour UN SEUL destinataire.
    // pg_net inscrivait alors « Timeout of 5000 ms reached » et l'écran
    // n'avait aucun moyen de savoir si les courriels étaient partis ou non.
    //
    // On rend donc la main immédiatement, et le travail se poursuit en
    // arrière-plan : waitUntil demande à l'hôte de ne pas arrêter la
    // fonction tant que l'envoi n'est pas terminé. Sans waitUntil (runtime
    // plus ancien), on attend comme avant - pg_net pourra expirer, mais
    // l'envoi, lui, ira au bout.
    //
    // Le compte rendu ne remonte donc plus à l'appelant : c'est assumé, et
    // c'est pourquoi l'écran annonce des courriels « mis en file ». La
    // preuve d'envoi est dans ces journaux et dans Resend.
    const travail = envoyerLots();
    const hote = (globalThis as unknown as {
      EdgeRuntime?: { waitUntil?: (p: Promise<unknown>) => void };
    }).EdgeRuntime;

    if (hote && typeof hote.waitUntil === "function") {
      hote.waitUntil(travail);
    } else {
      await travail;
    }

    return new Response(
      JSON.stringify({ accepte: messages.length }),
      { status: 202, headers: { "Content-Type": "application/json" } },
    );
  }

  const destinataire = String(body.email || "").trim();
  // Contrôle minimal : sans destinataire plausible, inutile d'appeler Resend.
  if (!destinataire || !destinataire.includes("@")) {
    return new Response("Missing recipient", { status: 400 });
  }

  const message = construireEmail(String(body.event_type || ""), body);
  if (!message) {
    return new Response("Unknown event_type", { status: 400 });
  }

  const res = await fetch("https://api.resend.com/emails", {
    method: "POST",
    headers: {
      Authorization: `Bearer ${RESEND_API_KEY}`,
      "Content-Type": "application/json",
    },
    body: JSON.stringify({
      from: FROM_EMAIL,
      to: [destinataire],
      subject: message.subject,
      html: message.html,
    }),
  });

  if (!res.ok) {
    const detail = await res.text();
    console.error("Resend a refusé l'envoi :", res.status, detail);
    return new Response("Send failed", { status: 502 });
  }

  return new Response(JSON.stringify({ envoye: true }), {
    status: 200,
    headers: { "Content-Type": "application/json" },
  });
});

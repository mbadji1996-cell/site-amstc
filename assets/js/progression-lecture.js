/**
 * Progression de lecture AUTOMATIQUE d'un cours ou d'une leçon.
 *
 * LE PRINCIPE. Le contenu est découpé en sections - ses titres h2 (ou
 * h3 s'il n'y a pas de h2, ou des tranches de hauteur s'il n'y a aucun
 * titre). Une section compte comme LUE quand elle a été visible à
 * l'écran un moment - pas seulement défilée : traverser un cours en
 * deux secondes ne le termine pas. Le pourcentage est le nombre de
 * sections lues sur le total ; la barre du haut le suit en direct.
 *
 * L'ENREGISTREMENT est régulier (toutes les 20 s si quelque chose a
 * changé) et à la fermeture de la page, par une fonction fournie par
 * l'appelant - c'est lui qui connaît sa table. On n'écrit que si la
 * progression a AVANCÉ : rouvrir un cours terminé et n'en lire que le
 * début ne le fait pas régresser.
 *
 * LA REPRISE. Au chargement, si une dernière section est connue et que
 * le cours n'est pas terminé, un bandeau propose d'y retourner. C'est
 * ce qui rend la progression utile sur un cours de dix-huit sections :
 * elle sert à revenir, pas seulement à s'afficher.
 *
 * Utilisation :
 *   const p = progressionLecture({
 *     conteneur: document.getElementById('courseContent'),
 *     barre: document.getElementById('topBar'),        // facultatif
 *     libelle: document.getElementById('progLabelTop'), // facultatif
 *     initial: { pct: 40, derniere_section: 'Titre', sections_lues: 3 },
 *     plafond: 100,           // 80 quand un quiz apporte les 20 derniers
 *     enregistrer: async ({ pct, derniere_section, sections_lues }) => {},
 *     bandeau: document.getElementById('reprise'),      // facultatif
 *   });
 *   p.terminer()   -> tout marquer lu, enregistrer 100
 *   p.etat()       -> { pct, sections_lues, total, derniere_section }
 */
(function () {
  "use strict";

  const DELAI_LU_MS = 2500;      // visible ce temps-là = lu
  const CADENCE_MS = 20000;      // enregistrement au plus toutes les 20 s

  function normaliser(t) {
    return String(t || "").replace(/\s+/g, " ").trim().slice(0, 160);
  }

  function decouper(conteneur) {
    let titres = [...conteneur.querySelectorAll("h2")];
    if (titres.length < 2) titres = [...conteneur.querySelectorAll("h2, h3")];
    // Aucun titre : on tranche le contenu en morceaux de ~1 écran, sur
    // ses enfants directs, pour avoir quand même une mesure.
    if (titres.length < 2) {
      const enfants = [...conteneur.children].filter((e) => e.offsetHeight > 0);
      const parTranche = Math.max(1, Math.ceil(enfants.length / 8));
      const sections = [];
      for (let i = 0; i < enfants.length; i += parTranche) {
        sections.push({ el: enfants[i], titre: "Partie " + (sections.length + 1) });
      }
      return sections.length ? sections : [{ el: conteneur, titre: "Le contenu" }];
    }
    return titres.map((h) => ({ el: h, titre: normaliser(h.textContent) || "Section" }));
  }

  function progressionLecture(opts) {
    const conteneur = opts.conteneur;
    if (!conteneur) return null;
    const plafond = Math.min(100, Math.max(1, opts.plafond || 100));
    const initial = opts.initial || {};

    let sections = decouper(conteneur);
    const lues = new Set();
    let derniere = initial.derniere_section || null;
    let pctEnregistre = Number(initial.pct) || 0;
    let sale = false;
    let termine = pctEnregistre >= 100;

    // Reprise de l'état connu : on marque comme lues les N premières
    // sections, dans l'ordre - c'est l'approximation la plus honnête
    // quand on ne stocke que le compte.
    const dejaLues = Math.min(Number(initial.sections_lues) || 0, sections.length);
    for (let i = 0; i < dejaLues; i++) lues.add(i);

    function pctLecture() {
      if (!sections.length) return 0;
      return Math.round((lues.size / sections.length) * plafond);
    }
    function afficher() {
      const pct = termine ? 100 : Math.max(pctEnregistre, pctLecture());
      if (opts.barre) opts.barre.style.width = pct + "%";
      if (opts.libelle) opts.libelle.textContent = pct + "%";
      if (typeof opts.surChangement === "function") opts.surChangement(pct, lues.size, sections.length);
      return pct;
    }

    // ---- Observation : une section est lue après DELAI_LU_MS visible ----
    const minuteries = new Map();
    const obs = new IntersectionObserver((entries) => {
      for (const e of entries) {
        const i = sections.findIndex((s) => s.el === e.target);
        if (i === -1) continue;
        if (e.isIntersecting) {
          if (lues.has(i) || minuteries.has(i)) continue;
          minuteries.set(i, setTimeout(() => {
            minuteries.delete(i);
            // L'onglet est passé en arrière-plan pendant le délai : la
            // section n'a pas été lue, elle a été laissée ouverte.
            if (document.hidden) return;
            lues.add(i);
            derniere = sections[i].titre;
            sale = true;
            afficher();
          }, DELAI_LU_MS));
        } else if (minuteries.has(i)) {
          clearTimeout(minuteries.get(i));
          minuteries.delete(i);
        }
      }
    }, { threshold: 0.15 });
    sections.forEach((s) => obs.observe(s.el));

    // ---- Enregistrement ----
    async function enregistrer(force) {
      if (!sale && !force) return;
      const pct = termine ? 100 : Math.max(pctEnregistre, pctLecture());
      // Jamais de régression : on n'écrit que si ça avance (ou en force).
      if (!force && pct <= pctEnregistre && lues.size <= dejaLues) { sale = false; return; }
      sale = false;
      try {
        await opts.enregistrer({
          pct,
          derniere_section: derniere,
          sections_lues: termine ? sections.length : lues.size,
        });
        pctEnregistre = pct;
      } catch (e) {
        sale = true;   // on réessaiera au prochain tour
      }
    }
    const tick = setInterval(() => enregistrer(false), CADENCE_MS);
    // À la fermeture, sendBeacon n'est pas possible avec Supabase JS :
    // on tente l'appel, le navigateur le laisse partir le plus souvent.
    const auDepart = () => { if (sale) enregistrer(false); };
    window.addEventListener("pagehide", auDepart);
    document.addEventListener("visibilitychange", () => { if (document.hidden) auDepart(); });

    // ---- Bandeau de reprise ----
    if (opts.bandeau && !termine && derniere && dejaLues > 0 && dejaLues < sections.length) {
      const cible = sections[Math.min(dejaLues, sections.length - 1)];
      opts.bandeau.innerHTML =
        '<span class="reprise-texte">Vous vous étiez arrêté à <strong>' + echapper(derniere) + "</strong>.</span>"
        + '<button type="button" class="reprise-btn">Reprendre <i class="ti ti-arrow-down"></i></button>';
      opts.bandeau.style.display = "";
      opts.bandeau.querySelector(".reprise-btn").addEventListener("click", () => {
        cible.el.scrollIntoView({ behavior: "smooth", block: "start" });
        opts.bandeau.style.display = "none";
      });
    }

    function echapper(s) {
      return String(s).replace(/[&<>"']/g, (c) => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;" }[c]));
    }

    afficher();

    return {
      etat: () => ({ pct: afficher(), sections_lues: lues.size, total: sections.length, derniere_section: derniere }),
      terminer: async () => {
        termine = true;
        sections.forEach((_, i) => lues.add(i));
        derniere = sections.length ? sections[sections.length - 1].titre : derniere;
        afficher();
        await enregistrer(true);
      },
      // Si le contenu est réinjecté (rare), redécouper.
      rafraichir: () => { obs.disconnect(); sections = decouper(conteneur); sections.forEach((s) => obs.observe(s.el)); afficher(); },
      arreter: () => { obs.disconnect(); clearInterval(tick); window.removeEventListener("pagehide", auDepart); },
    };
  }

  window.progressionLecture = progressionLecture;
})();

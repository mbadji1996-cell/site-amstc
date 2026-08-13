-- ============================================================
-- COURS DU DAARA - Gamou 1448H / 2026 « JikooY Sangue Bi »
-- Sixième volet : AR-RAHMA, la miséricorde.
--
-- Cours magistral de Demba Tahirou DIOP, converti depuis le PDF
-- « 06.AR RAHMA LA MISÉRICORDE » vers le Markdown restreint que sait
-- rendre membres/cours.html (## ### **gras** *italique* > citation
-- - liste). order_index = 6, à la suite de la patience (5).
--
-- PARTICULARITÉS DE CE DOCUMENT, à relire avant publication :
--
--   - Sur les huit vertus du thème (honnêteté, pudeur, patience,
--     justice, pardon, miséricorde, humilité, générosité), ce volet
--     couvre la miséricorde : il ne reste donc que la justice et la
--     générosité à recevoir.
--
--   - Un renvoi interne de l'auteur est LAISSÉ TEL QUEL bien qu'il
--     semble périmé : la partie II.3 (clémence de la conquête de La
--     Mecque) annonce « Cette dimension sera approfondie dans le
--     Chapitre VI », or le chapitre VI porte sur les animaux - le
--     renvoi visait sans doute le volet du pardon. À trancher avec
--     l'auteur.
--
--   - L'extraction du PDF a introduit des coupures de mots aux fins
--     de ligne (« ouest -africain », « spiritu elle », « l'insomni e »,
--     « s i chaque partie », « cité -État »). Toutes recollées.
--
--   - Deux coquilles de l'auteur corrigées : « la conscience de sa
--     propre besoin de rahma » devient « de son propre besoin », et
--     « par sa wird » devient « par son wird » (le wird est masculin
--     partout ailleurs dans la série).
--
--   - Les tirets cadratins du PDF sont remplacés par des tirets
--     simples, conformément à la règle typographique du site.
--
-- Inséré NON PUBLIÉ (is_published = false), comme les précédents :
-- relisez-le dans Gestion du Daara, puis publiez-le d'un clic.
--
-- Ré-exécutable sans danger : un cours du même titre est mis à jour
-- plutôt que dupliqué, sans toucher à is_published.
--
-- À exécuter : Studio (instance amstc) > SQL Editor > coller > Run.
-- ============================================================

do $$
declare
  v_titre   text := $t$Ar-Rahma : la miséricorde, essence de l'éthique prophétique$t$;
  v_desc    text := $d$Gamou 1448H / 2026 - JikooY Sangue Bi. La miséricorde comme essence de l'éthique prophétique : de la basmala et de la Sîra à la fayda de la miséricorde muhammadienne dans la voie tijaniyya.$d$;
  v_contenu text := $cours$## INTRODUCTION GÉNÉRALE

Le Gamou - commémoration de la naissance du Prophète Muhammad (SAWS) - constitue dans le soufisme ouest-africain un moment de ta'ammul (méditation profonde) et de tajdid (renouvellement spirituel). L'édition 1448H / 2026, portée par l'AMSTC (Association Médico-Sociale des Talibés Cheikh), a retenu pour thème central le Jiko (la miséricorde, la rahma en arabe). Ce choix interroge la communauté sur une vertu que les turbulences économiques, médiatiques et politiques contemporaines tendent à éroder, tout en rappelant qu'elle fut le socle même sur lequel s'est édifiée la mission prophétique.

Dans la tradition tijaniyye, cette vertu revêt une importance capitale : la rahma n'est pas seulement une qualité morale, c'est une condition d'ouverture (fath) et un vecteur de la fayda (dérivation spirituelle). Cheikh Ahmad Tijani (qu'Allah sanctifie son secret) a toujours enseigné que la réalisation spirituelle (tahqîq) ne peut advenir qu'à partir d'un cœur purifié de toute dureté (qaswa) et de toute indifférence. La voie tijaniyye, par sa rigueur liturgique et son exigence de murâqaba (vigilance spirituelle), fait de la miséricorde intérieure et extérieure le préalable incontournable à toute ascension vers le Prophète (SAWS).

### A. Problématique

Comment la miséricorde (rahma / al-ra'fa) du Prophète Muhammad (SAWS), antérieure même à la Révélation, constitue-t-elle non seulement une vertu morale individuelle, mais une architectonique anthropologique, sociale et spirituelle de l'Islam ? En d'autres termes, en quoi le titre de « Miséricorde pour les univers » (rahmatan li-l-'âlamîn) n'est-il pas qu'une métaphore poétique, mais une clé herméneutique pour comprendre la totalité du message prophétique, notamment dans son application tijaniyye ?

### B. Méthodologie

Nous adopterons une approche interdisciplinaire :

- **Approche historico-sociologique** : étude de la société jahiliyya mecquoise et du rôle de la compassion dans les rapports sociaux.
- **Approche scripturaire** : analyse coranique et hadithique de la rahma et de ses dérivés.
- **Approche anthropologique** : la miséricorde comme structure de la personne (akhlâq).
- **Approche politique** : la compassion comme fondement du pacte social.
- **Approche soufie/tariqienne** : la rahma comme tazkiyya (purification) et élévation dans la voie tijaniyye.

## PREMIÈRE PARTIE : CADRE HISTORIQUE ET FONDEMENTS SCRIPTURAIRES

*La miséricorde dans la société jahiliyya : une exception nommée Muhammad.*

### I.1. La société jahiliyya : absence de miséricorde structurante

La Mecque pré-islamique était une cité-État caravanière où le commerce (tijâra) structurait les rapports sociaux. Dans un contexte de rivalités tribales, de polythéismes concurrents et d'absence d'autorité judiciaire centralisée, la compassion (rahma) envers l'étranger, le faible ou l'opprimé était une denrée rare. Les stratagèmes commerciaux, l'exclusion des marginaux et la violence envers les sans-protection étaient des pratiques courantes, dénoncées même par les poètes de l'époque.

La société jahiliyya fonctionnait selon une logique de prédateur où la force physique et la puissance tribale déterminaient le sort des individus. Les faibles - orphelins, veuves, esclaves, étrangers - n'avaient aucune garantie de protection. L'infanticide des filles (wa'd al-banât), la réduction en esclavage des prisonniers de guerre et l'exploitation économique des démunis étaient des réalités acceptées. Ce n'était pas l'absence totale de morale, mais une morale tribale étroite qui ne s'étendait pas au-delà du clan.

### I.2. Al-Rahma dans le Coran : une ontologie de la compassion

Le terme rahma et ses dérivés apparaissent à de multiples reprises dans le Coran, articulant deux dimensions complémentaires qui structurent la pensée islamique.

**Rahma comme attribut divin.** Le Coran présente la miséricorde comme le premier et le plus grand attribut d'Allah. Chaque sourate (sauf une) commence par la basmala : « Au nom d'Allah, le Tout Miséricordieux, le Très Miséricordieux » (ar-Rahmân, ar-Rahîm). Ces deux noms dérivent de la racine R-H-M et désignent respectivement la miséricorde universelle (qui s'étend à toute la création) et la miséricorde spécifique (réservée aux croyants). Cette distinction théologique fondamentale établit que la compassion n'est pas une réaction occasionnelle de Dieu, mais Son essence même.

**Rahma comme mission prophétique.** Le Coran déclare à propos du Prophète (SAWS) : « Nous ne t'avons envoyé que comme une miséricorde pour les univers » (Sourate 21, v. 107). Ce verset ne qualifie pas seulement la mission du Prophète ; il la définit ontologiquement. Muhammad (SAWS) n'est pas seulement un messager qui apporte la miséricorde ; il est la miséricorde incarnée. Dans la perspective tijaniyye, cela évoque le concept de al-Haqîqa al-Muhammadiyya (la Réalité muhammadienne) qui est le réceptacle premier de la miséricorde divine.

> Et Mon châtiment est le châtiment douloureux. (Sourate 7, v. 167)

Ce verset, paradoxalement, révèle que même la justice divine est encadrée par la miséricorde. Le châtiment n'est jamais vengeur ; il est correcteur.

### I.3. Al-Rahma dans la Sunna : le Prophète comme « Miséricorde pour les univers »

Les hadiths rapportent de nombreux épisodes qui illustrent la compassion infinie du Prophète (SAWS). Anas ibn Mâlik, qui le servit pendant dix ans, rapporte : « J'ai servi le Messager d'Allah dix ans, et jamais il ne m'a dit : "Pourquoi as-tu fait cela ?" à propos de quelque chose que j'avais fait, ni : "Pourquoi n'as-tu pas fait cela ?" à propos de quelque chose que je n'avais pas fait. » (Rapporté par Al-Bukhârî et Muslim).

Cette patience et cette clémence ne sont pas des faiblesses ; elles sont la manifestation concrète de la rahma. Le Prophète (SAWS) ne punissait pas par colère, ne réprimandait pas par humiliation, ne rejetait pas par dédain. Chaque interaction était imprégnée d'une compassion qui reconnaissait la dignité de l'autre, qu'il soit musulman ou non, ami ou ennemi.

> Ceux qui sont miséricordieux envers les autres, le Miséricordieux leur accorde Sa miséricorde. Soyez miséricordieux envers ceux qui sont sur terre, Celui qui est au Ciel sera miséricordieux envers vous. - Hadith rapporté par Abû Dâwûd et At-Tirmidhî.

## DEUXIÈME PARTIE : LA MISÉRICORDE DANS LA SÎRA DU PROPHÈTE (SAWS)

### II.1. La compassion envers les faibles et les marginalisés

Dès son enfance, Muhammad (SAWS) démontre une sensibilité particulière envers les exclus de la société mecquoise. Orphelin de père avant sa naissance et de mère à l'âge de six ans, il connaît intimement la vulnérabilité. Cette expérience fondatrice forge en lui une compassion innée pour les faibles, les orphelins, les esclaves et les pauvres.

L'histoire de **Zayd ibn Haritha** est emblématique. Esclave offert à Khadija, il est libéré par le Prophète (SAWS) qui l'adopte comme fils. Quand le père biologique de Zayd vient le réclamer, le Prophète (SAWS) lui laisse le choix. Zayd choisit de rester auprès de Muhammad (SAWS), témoignant de l'amour et du respect qu'il lui porte. Ce geste révolutionnaire - traiter un esclave comme un fils, lui offrir la liberté et la dignité - est une manifestation concrète de la rahma prophétique.

**Bilal ibn Rabah**, l'esclave abyssin torturé pour sa foi, est un autre exemple. Le Prophète (SAWS) achète sa liberté et en fait le muezzin de l'Islam. Cette élévation d'un homme considéré comme inférieur par la société jahiliyya au rang de premier appelant à la prière est une subversion sociale fondée sur la compassion. La rahma prophétique ne connaît pas les barrières de race, de statut ou d'origine.

### II.2. La miséricorde envers les animaux et la création

La compassion du Prophète (SAWS) ne se limite pas aux humains ; elle s'étend à toute la création. Les hadiths rapportent de nombreux épisodes où il interdit la cruauté envers les animaux. Il condamne ceux qui chargent excessivement leurs montures, interdit de tuer les animaux sans nécessité, et enseigne que la bienfaisance envers les créatures est une forme de charité (sadaqa).

> Une femme fut punie à cause d'un chat qu'elle avait enfermé jusqu'à ce qu'il meure de faim. À cause de ce chat, elle entra en Enfer. Elle ne lui avait pas donné à manger ni laissé partir pour qu'il mange des bestioles de la terre. - Hadith rapporté par Al-Bukhârî et Muslim.

Ce hadith, souvent cité, révèle que la miséricorde envers les animaux est une mesure de la piété. La cruauté gratuite n'est pas seulement une faute morale ; elle est une rupture avec la rahma divine qui pénètre toute la création. Dans la perspective tijaniyye, ce respect de la création est une forme de tawhîd vécu : reconnaître la signature divine dans chaque être vivant.

### II.3. La clémence envers les ennemis : le modèle de la conquête de La Mecque

L'épisode de la conquête de La Mecque (8 H / 630) constitue l'apogée de la miséricorde prophétique. Après vingt ans de persécution, d'exil, de guerre et de trahison, le Prophète (SAWS) entre dans sa ville natale à la tête de dix mille hommes. Les Mecquois, terrorisés, attendent le châtiment. Pourtant, il déclare :

> Allez, vous êtes libres.

Cette amnistie générale n'est pas une faiblesse politique ; c'est l'accomplissement de sa mission de « miséricorde pour les univers ». Les Quraychites qui l'avaient lapidé, qui avaient tué ses compagnons, qui avaient persécuté les musulmans, sont pardonnés en bloc. Certains ennemis notoires - comme Hind bint 'Utba, qui avait mutilé le corps de Hamza - sont même accueillis avec clémence. Le Prophète (SAWS) ne demande qu'une chose : qu'ils reconnaissent l'unicité de Dieu.

Cette dimension sera approfondie dans le Chapitre VI. Il suffit de noter ici que la rahma prophétique transcende la logique de la vengeance. Elle ne nie pas l'injustice subie ; elle la surmonte par une compassion qui vient de Dieu. C'est ce que la tradition soufie appelle le pardon comme acte de transcendance (tajâwuz).

## TROISIÈME PARTIE : LA MISÉRICORDE COMME STRUCTURE ANTHROPOLOGIQUE

### III.1. Rahma al-nafs : la compassion envers soi-même

Dans la tradition spirituelle musulmane, la miséricorde ne commence pas par l'autre, mais par soi-même. Le hadith célèbre : « Celui qui n'a pas de miséricorde pour les autres, le Miséricordieux n'aura pas de miséricorde pour lui » (rapporté par Al-Bukhârî et Muslim) pose que la rahma est d'abord une qualité du cœur qui s'adresse à soi avant de s'adresser au monde.

La compassion envers soi-même (rahma al-nafs) ne signifie pas l'indulgence narcissique ou l'excuse de ses propres fautes. Elle signifie reconnaître sa propre vulnérabilité, accepter ses limites, et ne pas se détruire par la culpabilité excessive. Le Prophète (SAWS) enseignait que Dieu aime ceux qui se repentent sincèrement, et que le repentir (tawba) est lui-même un acte de miséricorde envers soi.

Dans la tijaniyye, cette dimension est essentielle. Le talibé qui se flagelle moralement, qui s'accable de ses imperfections sans jamais se relever, manque la rahma. Cheikh Ahmad Tijani enseignait que la confiance en Dieu (tawakkul) implique de se regarder avec les yeux de la compassion divine. On ne s'approche pas du Prophète (SAWS) en se haïssant, mais en se purifiant avec amour.

### III.2. Rahma al-â'il : la miséricorde familiale

Le Prophète (SAWS) a placé la bienfaisance envers les parents au rang des actes les plus agréés par Dieu. Le Coran répète à de multiples reprises l'ordre de « bienfaire aux parents » (bir al-wâlidayn), associant ce devoir à l'adoration de Dieu Lui-même. Cette association n'est pas rhétorique : elle révèle que la famille est le premier champ d'application de la rahma.

Le Prophète (SAWS) était un modèle de tendresse envers ses enfants et ses petits-enfants. Il embrassait Hassan et Hussein, jouait avec eux, et déclarait : « Celui qui n'est pas miséricordieux envers nos petits et qui ne respecte pas nos vieux n'est pas des nôtres. » (Rapporté par Abû Dâwûd). Cette miséricorde familiale n'est pas une affaire privée ; c'est une dimension publique de la foi. La manière dont on traite son épouse, ses enfants, ses parents est le miroir de sa rahma intérieure.

Dans la perspective tijaniyye, la famille est considérée comme la première zawiya (école spirituelle). C'est au sein de la cellule familiale que le talibé apprend la patience, le pardon, la bienfaisance et la compassion. Un homme qui est dur avec sa famille mais doux avec ses hôtes est un hypocrite (munâfiq) de la rahma. La sincérité de la voie se mesure d'abord dans l'intimité domestique.

### III.3. Rahma al-mujtama' : la miséricorde sociale comme devoir

La miséricorde ne se limite pas au cercle familial ; elle s'étend à la société tout entière. Le Coran ordonne : « Coopérez à la vertu et à la piété » (Sourate 5, v. 2). Cette coopération (ta'âwun) est fondée sur la reconnaissance mutuelle de la dignité de chaque être humain. Le Prophète (SAWS) a déclaré :

> Les croyants, dans leur affection, leur miséricorde et leur compassion les uns envers les autres, sont comme un seul corps : lorsqu'un membre souffre, tout le corps reste éveillé dans la fièvre et l'insomnie. - Rapporté par Al-Bukhârî et Muslim.

Cette métaphore du corps unique révolutionne la conception de la société. La souffrance de l'autre n'est pas une information distante ; elle est ma propre souffrance. La miséricorde sociale n'est donc pas une charité discrétionnaire ; elle est une obligation ontologique. Dans la tijaniyye, cette dimension sociale est incarnée par les pratiques de solidarité (tawâzu') qui lient les talibés entre eux, indépendamment de leur origine ethnique ou de leur statut social.

## QUATRIÈME PARTIE : DIMENSIONS POLITIQUES ET SOCIALES

### IV.1. La miséricorde dans le pacte social : la Constitution de Médine

La Sahîfat al-Madîna (Constitution de Médine) est le premier document politique de l'histoire islamique. Elle repose sur une mutualisation de la confiance et de la compassion entre Muhâjirûn, Ansâr et tribus juives. Ce texte, signé par le Prophète (SAWS) en l'an 1 de l'Hégire, établit que tous les signataires forment une seule communauté (umma) fondée sur le respect réciproque et la protection mutuelle.

Le Prophète (SAWS) tint scrupuleusement les clauses relatives aux droits des Juifs de Médine, bien que certains d'entre eux aient ultérieurement trahi leur parole. Cette asymétrie morale - être miséricordieux même face à la trahison - est le propre de la stature prophétique. La Constitution de Médine n'est pas seulement un traité politique ; c'est une charte de la compassion institutionnalisée. Elle établit que la justice politique doit être tempérée par la miséricorde, et que le pacte social ne tient que si chaque partie reconnaît la dignité de l'autre.

Dans la perspective tijaniyye, cette dimension est fondamentale. La tariqa ne promeut pas un retrait du monde social, mais un engagement éthique au sein de la société. Le talibé tijane est appelé à être un modèle de compassion dans ses relations civiques, professionnelles et politiques. La miséricorde n'est pas une vertu de retrait ; c'est une vertu d'engagement.

### IV.2. La miséricorde économique : zakat, sadaqa et solidarité

L'économie islamique est fondée sur la reconnaissance que la richesse est un dépôt divin (amâna) et non une propriété absolue. La zakat, pilier de l'Islam, institutionnalise la miséricorde économique en obligeant les nantis à redistribuer une portion de leurs biens aux pauvres. Ce n'est pas une aumône discrétionnaire mais un droit reconnu aux démunis sur la richesse des riches.

Le Prophète (SAWS) a multiplié les exhortations à la bienfaisance (sadaqa) et a lui-même vécu dans une extrême simplicité, redistribuant tout ce qui lui était offert. Il déclarait : « La main du donateur est meilleure que la main du receveur. » (Rapporté par Al-Bukhârî). Cette affirmation n'est pas une condescendance ; c'est la reconnaissance que donner purifie l'âme et renforce les liens sociaux. La miséricorde économique n'appauvrit pas le donateur ; elle l'élève.

Dans la tradition tijaniyye, la solidarité économique est un pilier de la vie communautaire. Les zawiyas ont historiquement organisé des systèmes de mutualité, de prêts sans intérêt (qard hasan) et d'entraide agricole. Cheikh Ibrahim Niasse, figure majeure de la diffusion de la fayda tijaniyye, a toujours enseigné que la richesse acquise sans miséricorde est un obstacle spirituel. Le commerce licite doit être empreint de rahma, et le profit doit servir la communauté.

### IV.3. La miséricorde dans la guérison et l'accompagnement des malades

Le Prophète (SAWS) était un modèle de compassion envers les malades. Il visitait les malades, priait pour leur guérison, et enseignait que visiter un malade est une forme de sadaqa. Il déclarait : « Allah ne fait descendre aucune maladie sans faire descendre son remède. » (Rapporté par Al-Bukhârî). Cette affirmation lie la maladie à la miséricorde divine : même la souffrance physique est un vecteur de rapprochement avec Dieu.

L'accompagnement des malades dans l'Islam ne se limite pas au soin physique. Il inclut la visite ('iyâda), la prière (du'â), le réconfort moral et l'aide matérielle. Le Prophète (SAWS) embrassait les lépreux, touchait les malades, et refusait de considérer la maladie comme une souillure ou une punition. Cette attitude révolutionnaire dans un contexte où les malades étaient souvent exclus témoigne de la profondeur de la rahma prophétique.

Dans la perspective tijaniyye, la guérison spirituelle (ruqya) et la médecine prophétique (tibb nabawî) sont des domaines où la miséricorde s'exprime concrètement. Le talibé est invité à visiter les malades, à réciter les invocations de guérison, et à offrir son soutien moral et matériel. La maladie de l'autre est une occasion de manifester la rahma, non une raison de s'éloigner.

## CINQUIÈME PARTIE : LA MISÉRICORDE COMME PURIFICATION SPIRITUELLE (TAZKIYYA)

### V.1. Al-Rahma comme lumière du cœur

L'enseignement spirituel souligne que la miséricorde est une lumière qui élève l'homme. Cette métaphore est profondément ancrée dans la tradition soufie. Al-Ghazâlî, dans son *Ihyâ' 'Ulûm al-Dîn*, traite de la rahma comme d'une nûr (lumière) qui dissipe les ténèbres de la dureté (qaswa), de l'orgueil (kibr) et de l'égoïsme (anâniyya).

La miséricorde purifie le cœur (qalb) parce qu'elle l'oblige à s'ouvrir : ouverture à l'autre, ouverture à la souffrance du monde, ouverture à la compassion divine. Le cœur fermé - qui se protège derrière des barrières de jugement, de mépris et d'indifférence - est le siège de l'angoisse spirituelle. Le cœur miséricordieux est en paix, car il sait qu'il participe à la miséricorde infinie de Dieu.

Dans la tijaniyye, cette paix est appelée itmi'nân : la sérénité du cœur qui a trouvé son centre dans l'amour prophétique. Cheikh Ahmad Tijani enseignait que la murâqaba (vigilance spirituelle) doit être empreinte de douceur (rifq). On ne se tient pas devant Dieu avec rigidité et crainte servile, mais avec amour et confiance. La rahma divine est le premier moteur de la création ; le cœur du talibé doit en être le réceptacle.

### V.2. La miséricorde et l'examen de conscience (muhâsaba)

Le maître soufi Al-Hârith al-Muhâsibî (m. 243 H) a fondé toute une science sur l'examen de conscience. Pour lui, la rahma est impossible sans un travail permanent d'introspection. Le croyant doit se demander chaque soir : Ai-je été dur envers quelqu'un aujourd'hui ? Ai-je refusé de pardonner ? Ai-je fermé mon cœur à la souffrance de l'autre ?

Ce travail est le jihâd al-akbar (le grand combat), celui contre son propre ego. Dans la tijaniyye, cette muhâsaba est le préalable à toute fayda : on ne reçoit que ce que l'on est capable de contenir, et un réceptacle durci par la rancune ne peut retenir la lumière. Cheikh Ahmad Tijani recommandait à ses disciples la revue quotidienne de leurs états d'âme avant le coucher, afin de ne pas emporter la dureté dans la nuit.

L'examen de conscience dans la perspective de la rahma n'est pas une auto-flagellation. C'est un regard bienveillant sur soi-même, qui reconnaît les imperfections sans s'y complaire, et qui s'appuie sur la miséricorde divine pour se relever. Le talibé ne se juge pas ; il se soigne. Et le premier remède est la conscience de son propre besoin de rahma.

### V.3. L'élévation de la condition humaine par la compassion

La miséricorde n'est pas seulement une vertu défensive (ne pas être dur). Elle est une vertu élévatrice : elle élève celui qui la pratique au-dessus de la médiocrité, au-dessus de la petitesse des calculs, au-dessus de la fragmentation du moi moderne. Le Prophète (SAWS) a élevé l'humanité non seulement par son message théologique, mais par la densité éthique de sa personne.

Dans la perspective tijaniyye, cette élévation est la fayda elle-même : la dérivation spirituelle n'est pas une récompense, mais une conséquence naturelle de l'alignement de l'être sur le Prophète (SAWS). Quand le cœur devient rahma pur, il devient transparent au Prophète (SAWS), et c'est par cette transparence que descend la grâce. Cheikh Ibrahim Niasse enseignait que la fayda al-tijaniyya est la fayda de la miséricorde muhammadienne. Or, le Prophète (SAWS) est rahmatan li-l-'âlamîn. Recevoir sa fayda sans être miséricordieux soi-même est une contradiction.

En définitive, la miséricorde est le couronnement de la spiritualité tijaniyye. Elle n'est pas un ornement moral mais l'essence même de la voie. On n'approche pas le Prophète (SAWS) par la dureté, mais par la douceur. On ne touche pas à la fayda par la force, mais par la compassion. La tariqa est une école de rahma où le disciple apprend à devenir un avec la miséricorde divine.

## CHAPITRE VI : LA MISÉRICORDE ENVERS LES ANIMAUX ET LA CRÉATION

### VI.1. Fondements coraniques et hadithiques

Le Coran présente la création entière comme soumise à Dieu et digne de respect. Les animaux sont décrits comme des communautés (umam) à part entière, avec leurs propres modes de vie et leurs droits. Le Coran déclare : « Il n'y a pas d'animal sur terre, ni d'oiseau qui vole de ses ailes, qui ne soit des communautés comme vous. » (Sourate 6, v. 38). Ce verset établit une fraternité cosmique entre tous les êtres vivants, fondée sur la soumission commune au Créateur.

Les hadiths rapportent de nombreux épisodes où le Prophète (SAWS) interdit la cruauté envers les animaux. Il condamne ceux qui chargent excessivement leurs montures, interdit de tuer les animaux sans nécessité, et enseigne que la bienfaisance envers les créatures est une forme de charité (sadaqa). Il déclare : « Quiconque est miséricordieux envers les créatures, Dieu est miséricordieux envers lui. » (Rapporté par Abû Dâwûd et At-Tirmidhî).

> Le Prophète (SAWS) racontait l'histoire d'un homme qui, ayant soif, descendit dans un puits pour boire. En remontant, il vit un chien haletant de soif et léchant la terre humide. L'homme dit : « Ce chien souffre de la soif comme je souffrais de la soif. » Il redescendit dans le puits, remplit sa chaussure d'eau et la donna au chien à boire. Dieu lui pardonna ses péchés. Les compagnons demandèrent : « Ô Messager d'Allah, y a-t-il une récompense pour les bêtes ? » Il répondit : « Il y a une récompense pour tout être vivant doué de chaleur. » - Rapporté par Al-Bukhârî et Muslim.

### VI.2. L'exemple prophétique : bienfaisance envers les animaux

Le Prophète (SAWS) était un modèle de compassion envers les animaux. Il interdisait de les tuer par le feu, de les mutiler vivants, et de les utiliser comme cibles. Il racontait l'histoire d'une prostituée qui fut pardonnée parce qu'elle avait donné à boire à un chien sur le point de mourir de soif. Ce hadith révolutionnaire établit que la miséricorde envers les animaux peut effacer les plus grands péchés. La rahma n'a pas de hiérarchie stricte : elle s'adresse à tout être vivant.

Le Prophète (SAWS) possédait un chiot nommé Qatmir qu'il aimait tendrement. Il interdisait de chasser les animaux pour le seul plaisir, et recommandait de tuer rapidement et sans cruauté les animaux destinés à la consommation. Ces enseignements établissent une éthique de la consommation animale fondée sur la nécessité et la compassion, loin de l'exploitation industrielle moderne.

### VI.3. Portée écologique dans la tradition musulmane

La miséricorde envers les animaux et la création a une portée écologique majeure. Dans un monde où l'exploitation des ressources naturelles menace l'équilibre planétaire, la tradition islamique offre une éthique environnementale fondée sur la rahma. Le Prophète (SAWS) déclarait : « Si le Jour du Jugement arrive et que quelqu'un ait en main un plant de dattier, qu'il le plante. » Cette exhortation, apparemment paradoxale, révèle que la responsabilité envers la création transcende l'urgence apocalyptique.

Dans la perspective tijaniyye, le respect de la création est une forme de tawhîd vécu. Reconnaître la signature divine dans chaque être vivant, dans chaque arbre, dans chaque rivière, c'est approfondir sa conscience de l'unicité divine. Cheikh Ahmad Tijani enseignait que le talibé doit être doux (rifq) envers toute la création, car la dureté envers la nature reflète une dureté intérieure envers Dieu. La zawiya tijane doit être un lieu de paix pour les humains comme pour les animaux.

## CHAPITRE VII : LA MISÉRICORDE DANS LA GUÉRISON ET LES ÉPREUVES

### VII.1. Le Prophète (SAWS) comme guérisseur de cœurs

Le Prophète Muhammad (SAWS) n'était pas seulement un guide spirituel et politique ; il était un guérisseur de cœurs. Le Coran le qualifie de rahmatan li-l-'âlamîn (miséricorde pour les univers), et cette miséricorde s'exerçait d'abord sur les blessures intérieures. Dans une société où la vengeance, l'orgueil tribal et la dureté étaient des vertus masculines valorisées, le Prophète (SAWS) introduisit une thérapeutique de la douceur.

Il consacrait des heures à écouter les souffrances des plus humbles. Il recevait les esclaves, les veuves et les pauvres avec la même attention qu'il réservait aux émissaires des tribus. Cette écoute compassionnelle n'était pas une simple courtoisie ; c'était un acte de guérison. Le qalb (cœur) brisé par l'injustice, l'abandon ou la pauvreté trouvait auprès de lui un refuge. Il déclarait : « Dieu ne regarde pas vos apparences ni vos biens, mais Il regarde vos cœurs et vos actes. » (Rapporté par Muslim).

Dans la perspective tijaniyye, cette guérison par la compassion est centrale. Le salât 'alâ an-nabî (prière sur le Prophète) n'est pas seulement une récitation liturgique ; c'est une invocation de la rahma muhammadienne sur le cœur blessé du disciple. Cheikh Ahmad Tijani enseignait que la fréquentation spirituelle du Prophète (SAWS) adoucit le cœur (qalb) et dissipe les ténèbres de la rancune.

### VII.2. La compassion face à la maladie et à la mort

Le Prophète (SAWS) visitait les malades, quel que soit leur statut social ou leur religion. Il touchait les lépreux, priait pour les mourants, et consolait les familles endeuillées. Il enseignait que la maladie est une épreuve (ibtilâ') qui purifie les péchés, mais il ne méprisait jamais la souffrance physique. Il recommandait le traitement médical tout en affirmant la confiance en Dieu.

À la mort de son fils Ibrahim, il pleura et déclara :

> Les yeux versent des larmes et le cœur est affligé, mais nous ne disons que ce qui plaît à notre Seigneur. Ô Ibrahim, nous sommes affligés par ton départ. (Rapporté par Al-Bukhârî)

Cette manifestation de chagrin, loin d'être une faiblesse, est la preuve d'une humanité profondément miséricordieuse. Le Prophète (SAWS) ne refoulait pas la souffrance ; il la traversait avec dignité et confiance.

Dans la tradition tijaniyye, l'accompagnement des mourants et la consolation des familles sont des devoirs communautaires. La zawiya est un lieu où la rahma s'exerce concrètement : prières pour les malades, visites, assistance matérielle et réconfort spirituel. La mort n'est pas une défaite de la compassion ; c'est son accomplissement ultime, car le croyant espère la miséricorde divine infinie.

### VII.3. La miséricorde comme remède contre la désespérance

La désespérance (ya's) est qualifiée dans le Coran d'état de mécréance : « Ne désespérez pas de la miséricorde de Dieu, car c'est les mécréants qui désespèrent de la miséricorde de Dieu. » (Sourate 12, v. 87). Le Prophète (SAWS) incarnait l'antithèse de cette désespérance. Face aux rejets, aux insultes et aux persécutions, il ne cessa jamais d'espérer et de pardonner.

Cette résilience miséricordieuse est un modèle pour le croyant. La rahma n'est pas seulement une vertu qu'on offre ; c'est une vertu qu'on cultive en soi pour ne pas sombrer dans la haine ou le ressentiment. Dans la tijaniyye, le sabr (patience) et la rahma sont les deux ailes qui portent le disciple au-dessus des épreuves. Cheikh Ibrahim Niasse enseignait que la fayda descend sur le cœur qui a appris à transformer la souffrance en compassion.

## CHAPITRE VIII : AL-RAHMA CHEZ CHEIKH AHMAD TIJANI ET DANS LA FAYDA

### VIII.1. La miséricorde divine comme fondement de la Tariqa Tijaniyya

Cheikh Ahmad Tijani (1737-1815), fondateur de la Tariqa Tijaniyya, a placé la rahma au centre de sa doctrine spirituelle. Pour lui, la tariqa n'est pas une voie d'ascèse morbide ou de retrait du monde ; c'est une voie d'ouverture à la miséricorde divine. Il enseignait que Dieu a créé la création par miséricorde, et que toute spiritualité authentique doit refléter cette origine.

Dans ses écrits, notamment dans *Jawâhir al-Ma'ânî*, Cheikh Tijani développe l'idée que le Prophète (SAWS) est le réceptacle premier de la rahma divine. Le talibé tijane, par son wird et sa murâqaba, cherche à devenir un canal de cette même miséricorde. Ce n'est pas une appropriation arrogante ; c'est une disponibilité humble. Le disciple se vide de sa dureté pour être rempli de la compassion muhammadienne.

### VIII.2. Le salât 'alâ an-nabî comme canal de rahma

Le salât 'alâ an-nabî (prière sur le Prophète) est le pilier central de la pratique tijaniyye. Cheikh Tijani enseignait que cette invocation n'est pas seulement une louange adressée au Prophète (SAWS) ; c'est un échange spirituel où la rahma descend sur l'invocateur. Chaque salât est une goutte de miséricorde qui adoucit le cœur, efface les péchés et rapproche du Prophète (SAWS).

Cette pratique exige une qualité de présence (hudûr) qui n'est possible qu'à partir d'un cœur purifié de la rancune et de l'envie. La rahma n'est pas un don qu'on reçoit passivement ; c'est une qualité qu'on active par la sincérité de l'invocation. Cheikh Tijani recommandait de commencer chaque wird par l'intention pure de recevoir la miséricorde pour la redistribuer, et non pour s'enorgueillir.

### VIII.3. Cheikh Ibrahim Niasse et la diffusion de la fayda al-rahma

Cheikh Ibrahim Niasse (qu'Allah sanctifie son secret), figure majeure de la diffusion de la fayda tijaniyye en Afrique de l'Ouest, a toujours mis en avant que la fayda est essentiellement une fayda al-rahma. Elle n'est pas une force magique ou un pouvoir occulte ; c'est un déversement de compassion divine qui transforme le cœur du disciple.

Cheikh Niasse enseignait que la fayda ne s'acquiert pas par la quantité de litanies, mais par la qualité de la miséricorde intérieure. Un cœur dur, un cœur qui juge, un cœur qui méprise les autres, ne peut recevoir la fayda. C'est pourquoi il insistait sur la nécessité de la muhâsaba quotidienne et de la bienfaisance concrète envers les pauvres, les malades et les exclus.

La fayda al-tijaniyya, dans cette perspective, est une école de rahma. Elle ne sépare pas la spiritualité de l'action sociale. Le talibé qui reçoit la grâce est tenu de la manifester dans ses rapports humains. La miséricorde devient alors un mode d'être permanent, une lumière intérieure qui irradie toute la communauté.

## CONCLUSION GÉNÉRALE

### Synthèse

L'enseignement porté par le thème du Jikooy Sangue Bi pour le Gamou 1448H / 2026 nous rappelle que la miséricorde n'est pas un accessoire moral, mais l'essence même de la spiritualité prophétique. Du titre de rahmatan li-l-'âlamîn à l'amnistie de La Mecque, de la compassion envers les animaux au soin des malades, de l'intention secrète à la parole publique, la rahma constitue la trame continue du message.

Trois principes structurants émergent de cette étude :

- **L'universalité** : la miséricorde s'étend à tous les êtres vivants, sans distinction de race, de religion ou de statut social.
- **La totalité** : elle concerne tous les domaines de la vie - économique, politique, familiale, spirituelle et écologique.
- **L'élévation** : elle purifie le cœur et consolide la communauté, faisant de chaque individu un canal de la compassion divine.

### Ouverture : défis contemporains et recommandations

Dans un monde où la violence médiatique, l'exploitation économique et la destruction écologique sont devenues des normes, revenir à la rahma est un acte de résistance civilisationnelle. Le Gamou ne doit pas être seulement une commémoration festive, mais une réinstallation existentielle dans la compassion.

Que chaque talibé, chaque membre de l'AMSTC, chaque croyant, fasse de cette année 1448H l'occasion d'un examen radical : mon cœur est-il un réceptacle de miséricorde ? Ma compassion est-elle sincère ou simulée ? Ma foi se traduit-elle par des actes de bienfaisance concrets ?

Dans la voie tijaniyye, c'est par la rahma que l'on accède au Sirr, et c'est par le Sirr que l'on touche à l'essence de l'Amour prophétique.

> Ô vous qui croyez ! Qu'aucune raillerie ne se fasse entre vous, car peut-être que ceux que vous raillez sont meilleurs que vous. (Sourate 49, v. 11)

*Yalla nangu ko. Amin.*

## BIBLIOGRAPHIE INDICATIVE

- Ibn Hishâm, *Sîrat Ibn Hishâm*.
- Al-Bukhârî, *Sahîh al-Bukhârî* (Livre des transactions, Livre des malades, Livre des qualités morales).
- Muslim, *Sahîh Muslim* (Livre de la foi, Livre de la miséricorde).
- Al-Ghazâlî, *Ihyâ' 'Ulûm al-Dîn* (Livre des qualités morales, Livre de la méditation).
- Al-Hârith al-Muhâsibî, *Kitâb al-Muhâsabî*.
- Al-Tabarî, *Târîkh al-Rusul wa-l-Mulûk*.
- Cheikh Ahmad Tijani, *Jawâhir al-Ma'ânî*.
- Cheikh Ibrahim Niasse, *Kâshif al-Ilbâs* et écrits sur la fayda.
- Ouvrages contemporains sur la tijaniyya ouest-africaine et la fayda.
- AMSTC, Thème du Gamou 1448H / 2026 : Jikooy Sangue Bi.

*Rédigé par Demba Tahirou DIOP.*$cours$;
begin
  -- Le texte du cours ne figure qu'une fois : rejouer le script met à jour
  -- la fiche existante au lieu de la dupliquer, sans avoir à recopier le
  -- contenu dans une seconde instruction où les deux copies finiraient
  -- fatalement par diverger.
  if exists (select 1 from public.daara_courses where title = v_titre) then
    -- is_published n'est PAS touché : si le cours est déjà publié, une
    -- correction du texte ne doit pas le dépublier dans votre dos.
    update public.daara_courses
       set description  = v_desc,
           content      = v_contenu,
           category     = 'islam',
           author       = 'Demba Tahirou DIOP',
           duration_min = 30,
           order_index  = 6
     where title = v_titre;
  else
    insert into public.daara_courses
      (title, description, category, content, author, duration_min, order_index, is_published)
    values (v_titre, v_desc, 'islam', v_contenu, 'Demba Tahirou DIOP', 30, 6, false);
  end if;
end $$;

-- Contrôle : les volets du thème, dans l'ordre.
select order_index, title, category, author, duration_min, is_published,
       length(content) as caracteres
  from public.daara_courses
 where title like 'Al-%' or title like 'Ar-%'
 order by order_index;

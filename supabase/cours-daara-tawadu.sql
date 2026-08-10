-- ============================================================
-- COURS DU DAARA - Gamou 1448H / 2026 « JikooY Sangue Bi »
-- Troisième volet : AL-TAWADU', l'humilité.
--
-- Cours magistral de Demba Tahirou DIOP, converti depuis le PDF
-- « 03.AL-TAWADU' - L'HUMILITÉ COMME COURONNEMENT DE LA FOI
-- PROPHÉTIQUE » vers le Markdown restreint que sait rendre
-- membres/cours.html (## ### **gras** *italique* > citation - liste).
--
-- Il prend la suite des deux cours de supabase/cours-daara-gamou-1448h.sql
-- (l'honnêteté en 1, la pudeur en 2) : order_index = 3.
--
-- Inséré NON PUBLIÉ (is_published = false), comme les deux précédents :
-- relisez-le dans Gestion du Daara, puis publiez-le d'un clic. Une
-- conversion automatique depuis un PDF mérite une relecture avant d'être
-- servie aux membres - la mise en page d'origine perd ses césures et ses
-- notes de bas de page au passage.
--
-- Catégorie « islam » comme les deux autres : la matière première est
-- coranique, hadithique et tirée de la Sîra ; la dimension tijaniyye y
-- est un chapitre, non le sujet. Pour le basculer en « tarikha »,
-- changez la catégorie dans le formulaire, sans rejouer ce script.
--
-- Ré-exécutable sans danger : un cours du même titre est mis à jour
-- plutôt que dupliqué.
--
-- À exécuter : Studio (instance amstc) > SQL Editor > coller > Run.
-- ============================================================

do $$
declare
  v_titre   text := $t$Al-Tawadu' : l'humilité comme couronnement de la foi prophétique$t$;
  v_desc    text := $d$Gamou 1448H / 2026 - JikooY Sangue Bi. Troisième volet du thème : le tawadu' comme condition de la fayda, de la société jahiliyya à la voie tijaniyya.$d$;
  v_contenu text := $cours$## INTRODUCTION GÉNÉRALE

Le Gamou - commémoration de la naissance du Prophète Muhammad (SAWS) - constitue dans le soufisme ouest-africain un moment de ta'ammul (méditation profonde) et de tajdid (renouvellement spirituel). L'édition 1448H / 2026, portée par l'AMSTC (Association Médico-Sociale des Talibés Cheikh), a retenu pour thème central le Jiko (l'humilité, al-tawadu' en arabe). Ce choix interroge la communauté sur une vertu que les turbulences économiques, médiatiques et politiques contemporaines tendent à éroder, tout en rappelant qu'elle fut le socle même sur lequel s'est édifiée la mission prophétique.

Dans la tradition tijaniyye, cette vertu revêt une importance capitale : al-tawadu' n'est pas seulement une qualité morale, c'est une condition d'ouverture (fath) et un vecteur de la fayda (dérivation spirituelle). Cheikh Ahmad Tijani (qu'Allah sanctifie son secret) a toujours enseigné que la réalisation spirituelle (tahqîq) ne peut advenir qu'à partir d'un cœur purifié de toute arrogance (kibr) et de toute vanité ('ujb). La voie tijaniyye, par sa rigueur liturgique et son exigence de murâqaba (vigilance spirituelle), fait de l'humilité intérieure et extérieure le préalable incontournable à toute ascension vers le Prophète (SAWS).

### A. Problématique

Comment l'humilité (al-tawadu' / al-khushu') du Prophète Muhammad (SAWS), antérieure même à la Révélation, constitue-t-elle non seulement une vertu morale individuelle, mais une architectonique anthropologique, sociale et spirituelle de l'Islam ? En d'autres termes, en quoi l'humilité du Prophète, malgré son statut de meilleure des créatures, n'est-elle pas une faiblesse, mais une clé herméneutique pour comprendre la totalité du message prophétique, notamment dans son application tijaniyye ?

### B. Méthodologie

Nous adopterons une approche interdisciplinaire : (1) Approche historico-sociologique : étude de la société jahiliyya mecquoise et du rôle de l'humilité dans les rapports sociaux. (2) Approche scripturaire : analyse coranique et hadithique du tawadu' et de ses dérivés. (3) Approche anthropologique : l'humilité comme structure de la personne (akhlâq). (4) Approche politique : l'humilité du pouvoir comme fondement du pacte social. (5) Approche soufie/tariqienne : al-tawadu' comme tazkiyya (purification) et élévation dans la voie tijaniyye.

## PREMIÈRE PARTIE : CADRE HISTORIQUE ET FONDEMENTS SCRIPTURAIRES

*L'humilité dans la société jahiliyya : une exception nommée Muhammad*

### I.1. La société jahiliyya : orgueil tribal et hiérarchie de la force

La Mecque pré-islamique était une cité-État caravanière où le commerce (tijâra) structurait les rapports sociaux. Dans un contexte de rivalités tribales, de polythéismes concurrents et d'absence d'autorité judiciaire centralisée, l'humilité (tawadu') était considérée comme une faiblesse. Les stratagèmes commerciaux, l'exhibition de la richesse et la domination sur les plus faibles étaient des pratiques courantes, valorisées par la culture tribale.

La société jahiliyya fonctionnait selon une logique de prestige (hasab) et de noblesse de naissance (nasab). L'orgueil (kibr) était une vertu masculine valorisée. Les faibles - orphelins, veuves, esclaves, étrangers - n'avaient aucune garantie de respect. L'humilité envers un inférieur social était perçue comme une déchéance. Ce n'était pas l'absence totale de morale, mais une morale de la domination où la modestie était réservée aux vaincus.

### I.2. Al-Tawadu' dans le Coran : une ontologie de la soumission

Le terme tawadu' et ses dérivés apparaissent à de multiples reprises dans le Coran, articulant deux dimensions complémentaires qui structurent la pensée islamique.

a) Tawadu' comme soumission ontologique : le Coran présente l'humilité comme la posture fondamentale de la créature devant son Créateur. Les prophètes sont qualifiés de 'ibâd (serviteurs) avant d'être des messagers. Le Coran déclare : « Les serviteurs du Tout Miséricordieux sont ceux qui marchent humblement sur terre. » (Sourate 25, v. 63). Cette humilité n'est pas une posture sociale ; c'est une attitude existentielle face à l'Infini.

b) Tawadu' comme vertu éthique : le Coran ordonne : « Ne détourne pas ton visage des hommes par orgueil et ne marche pas sur terre avec insolence, car Dieu n'aime pas tout homme orgueilleux et fanfaron. » (Sourate 31, v. 18). Ce verset ne s'adresse pas seulement aux individus, mais à la communauté tout entière : l'humilité est une condition de la présence divine dans la société.

> « Et ne marche pas sur la terre avec insolence : tu ne fendras pas la terre, et tu n'atteindras pas les montagnes en hauteur. » - Sourate 17, v. 37

Ce verset révèle que l'orgueil est une absurdité ontologique : la créature ne peut jamais égaler le Créateur.

### I.3. Al-Tawadu' dans la Sunna : le Prophète comme modèle d'humilité

Les hadiths rapportent de nombreux épisodes qui illustrent l'humilité infinie du Prophète (SAWS). Anas ibn Mâlik, qui le servit pendant dix ans, rapporte que le Messager d'Allah était le meilleur des hommes, le plus généreux et le plus courageux. Une nuit, les habitants de Médine furent effrayés par un bruit. Ils sortirent et rencontrèrent le Prophète (SAWS) qui revenait du lieu de l'alerte. Il était sur la monture d'Abû Talha, sans cavalier devant lui, tenant lui-même la bride. Il leur dit : « Ne craignez pas, ne craignez pas. » (Rapporté par Al-Bukhârî).

Cette humilité n'est pas une faiblesse ; c'est la manifestation concrète de la confiance en Dieu (tawakkul). Le Prophète (SAWS) ne se cachait pas derrière des gardes du corps, ne voyageait pas avec escorte ostentatoire, ne se faisait pas précéder de hérauts. Il marchait parmi les gens, répondait au salut des esclaves, s'asseyait avec les pauvres, et mangeait ce que mangeaient les plus humbles.

> « Dieu m'a révélé que vous devez être humbles, afin que personne ne s'enorgueillisse sur l'autre et ne s'élève sur l'autre. » - Hadith rapporté par Muslim

## DEUXIÈME PARTIE : L'HUMILITÉ DANS LA SÎRA DU PROPHÈTE (SAWS)

*De l'intimité domestique à la gouvernance*

### II.1. L'humilité dans la vie domestique et familiale

Dans l'intimité familiale, le Prophète (SAWS) était un modèle de simplicité et de modestie. Il raccommodait ses vêtements, réparait ses sandales, trayait le lait de ses chèvres, et aidait ses épouses dans les tâches ménagères. 'Aisha (qu'Allah l'agrée) rapporte : « Le Messager d'Allah faisait le ménage dans sa maison, raccommodait ses vêtements, et quand il était l'heure de la prière, il sortait pour la prière. » (Rapporté par Al-Bukhârî).

Cette humilité domestique n'était pas un calcul politique ; c'était la manifestation d'une âme qui ne connaissait pas la distinction entre tâches nobles et tâches vulgaires. Pour le Prophète (SAWS), servir sa famille était un acte d'adoration.

> « Le meilleur d'entre vous est celui qui est le meilleur envers sa famille, et je suis le meilleur d'entre vous envers ma famille. » - Hadith rapporté par At-Tirmidhî

Dans la perspective tijaniyye, cette dimension est essentielle. Le talibé qui est arrogant dans sa famille mais humble avec ses hôtes est un hypocrite de l'humilité. La sincérité de la voie se mesure d'abord dans l'intimité domestique. Cheikh Ahmad Tijani enseignait que le disciple doit être le serviteur de sa famille avant de prétendre servir la communauté.

### II.2. L'humilité dans les rapports sociaux et politiques

Le Prophète (SAWS) recevait les pauvres, les esclaves et les étrangers avec la même attention qu'il réservait aux chefs de tribu. Il s'asseyait par terre, mangeait par terre, et refusait les sièges d'honneur. Quand un bédouin vint le voir et tira violemment sur son manteau, le Prophète (SAWS) ne se fâcha pas mais l'écarta doucement. Quand des enfants jouaient dans la mosquée, il ne les chassait pas mais les tolérait avec patience.

Cette humilité sociale n'était pas une stratégie de séduction populaire ; c'était l'expression d'une conscience profonde de sa propre servitude devant Dieu. Le Prophète (SAWS) savait qu'il était 'abd (serviteur) avant d'être rasûl (messager). Cette conscience fondatrice le préservait de toute tentation d'orgueil liée à sa mission.

Dans la perspective tijaniyye, cette humilité sociale est fondamentale. Le talibé ne doit jamais se prévaloir de son statut spirituel, de sa connaissance ou de sa piété. Cheikh Ibrahim Niasse, malgré sa renommée internationale, vivait dans une extrême simplicité et recevait les plus humbles avec la même attention que les savants. L'humilité est la marque du véritable 'arif (connaissant).

### II.3. L'humilité dans l'adoration et la prière

Le Prophète (SAWS) priait avec une telle humilité que ses compagnons pensaient qu'il n'entendait pas leurs salutations. Il pleurait dans sa prière jusqu'à ce que sa barbe soit mouillée. Il se prosternait si longtemps que ses petits-enfants pouvaient monter sur son dos sans qu'il ne bouge. Cette humilité liturgique (khushu') était le cœur de son adoration.

Il enseignait que l'humilité dans la prière est la condition de son acceptation : celui qui se remplit dans ce monde aura son ventre rempli de feu dans l'Autre, sauf celui qui mange pour subsister et qui prie avec humilité (Rapporté par Muslim). Cette humilité dans l'adoration n'est pas une posture théâtrale ; c'est l'effondrement du moi devant la Grandeur divine.

Dans la tradition tijaniyye, le salât 'alâ an-nabî est précisément l'exercice de cette humilité. Le disciple ne s'adresse pas au Prophète (SAWS) en tant qu'égal, mais en tant que serviteur implorant la grâce. Cette posture d'humilité est le préalable à toute fayda. On ne reçoit pas la grâce en s'érigeant, mais en s'abaissant.

## TROISIÈME PARTIE : L'HUMILITÉ COMME STRUCTURE ANTHROPOLOGIQUE

*De la conscience de soi à la vertu civique*

### III.1. Tawadu' al-nafs : l'humilité envers soi-même

Dans la tradition spirituelle musulmane, l'humilité ne commence pas par l'autre, mais par soi-même. Le hadith célèbre « Celui qui connaît son âme connaît son Seigneur » pose que l'humilité est d'abord une qualité du cœur qui reconnaît sa propre petitesse face à l'Infini.

L'humilité envers soi-même (tawadu' al-nafs) ne signifie pas l'auto-dénigrement ou le rejet de sa propre dignité. Elle signifie reconnaître que tout ce que l'on possède - intelligence, beauté, richesse, pouvoir - est un dépôt divin (amâna) et non une propriété absolue. Le Prophète (SAWS) enseignait que Dieu a répandu l'humilité sur la terre comme Il a répandu la pluie, et que celui qui marche humblement sur terre, Dieu élève son degré.

Dans la tijaniyye, cette dimension est essentielle. Le talibé qui s'enorgueillit de sa pratique spirituelle, qui se vante de ses visions ou de ses états, tombe dans le piège de l'orgueil spirituel ('ujb). Cheikh Ahmad Tijani enseignait que le véritable 'arif (connaissant) est celui qui se considère comme le plus ignorant des serviteurs. L'humilité n'est pas une posture ; c'est une conscience.

### III.2. Tawadu' al-â'il : l'humilité familiale

Le Prophète (SAWS) a placé la bienfaisance envers les parents au rang des actes les plus agréés par Dieu, mais il a aussi enseigné l'humilité envers les enfants et les épouses. Cette humilité familiale n'est pas une affaire privée ; c'est une dimension publique de la foi.

Le Prophète (SAWS) embrassait ses petits-enfants, jouait avec eux, et tolérait leurs jeux dans la mosquée. Il ne réprimandait pas ses épouses, ne les frappait pas, et consultait 'Aisha sur des questions juridiques. Cette humilité conjugale et parentale était révolutionnaire dans un contexte patriarcal où la domination masculine était la norme.

Dans la perspective tijaniyye, la famille est considérée comme la première zawiya (école spirituelle). C'est au sein de la cellule familiale que le talibé apprend l'humilité véritable. Un homme qui est arrogant avec sa famille mais humble avec ses hôtes est un hypocrite de l'humilité. La sincérité de la voie se mesure dans l'intimité domestique.

### III.3. Tawadu' al-mujtama' : l'humilité sociale comme vertu civique

L'humilité ne se limite pas au cercle familial ; elle s'étend à la société tout entière. Le Coran ordonne : « Et les serviteurs du Tout Miséricordieux sont ceux qui marchent humblement sur terre et qui, quand les ignorants s'adressent à eux, disent : Paix ! » (Sourate 25, v. 63). Cette humilité sociale n'est pas une faiblesse ; c'est une force qui désarme l'agression.

Le Prophète (SAWS) s'asseyait avec les pauvres, mangeait avec les esclaves, et répondait au salut des plus humbles. Il ne refusait jamais une invitation, même si c'était celle d'un esclave.

> « Celui qui s'humilie pour l'amour de Dieu, Dieu l'élève. » - Hadith rapporté par Muslim

Cette élévation n'est pas sociale mais spirituelle : c'est l'élévation du degré auprès de Dieu. Dans la tijaniyye, cette dimension sociale est incarnée par les pratiques de modestie qui lient les talibés entre eux. Le talibé ne doit jamais se prévaloir de son statut, de sa lignée ou de sa richesse. Cheikh Ibrahim Niasse, malgré sa renommée mondiale, vivait dans une simplicité qui stupéfiait ses visiteurs. L'humilité est la marque du véritable murîd.

## QUATRIÈME PARTIE : DIMENSIONS POLITIQUES ET SOCIALES

*L'humilité comme fondement du pacte social*

### IV.1. L'humilité du pouvoir : le modèle prophétique de gouvernance

Le Prophète (SAWS) fut à la fois chef spirituel, chef d'État, chef militaire et juge suprême. Pourtant, il ne vivait pas comme un souverain. Il dormait sur une natte de paille qui laissait des marques sur son corps. Il jeûnait des jours entiers par choix, alors que ses compagnons mangeaient à leur faim. Il refusait les trônes et les palais, et vivait dans une modeste maison en briques de terre.

Cette humilité du pouvoir n'était pas une stratégie de communication ; c'était la manifestation d'une conscience profonde de sa servitude devant Dieu.

> « Par Dieu, je ne suis qu'un serviteur de Dieu. Je mange comme un serviteur, je m'assieds comme un serviteur, je dors comme un serviteur. » - Hadith rapporté par Al-Bukhârî

Cette conscience fondatrice le préservait de toute tentation de tyrannie. Dans la perspective tijaniyye, cette dimension est fondamentale. Le talibé qui accède à des responsabilités communautaires, politiques ou économiques doit incarner cette humilité du pouvoir. Cheikh Ahmad Tijani enseignait que le guide spirituel (murshid) est le serviteur de ses disciples, non leur maître. L'autorité dans la tariqa est un service, non une domination.

### IV.2. L'humilité dans le commerce et les transactions

Le Prophète (SAWS) était un commerçant avant d'être un prophète. Il exerçait le commerce avec une intégrité et une modestie qui le distinguaient de ses contemporains. Il ne spéculait pas, ne trompait pas, et ne se vantait pas de ses profits. Il traitait ses associés avec respect, qu'ils soient riches ou pauvres.

Cette humilité commerciale est fondamentale dans l'économie islamique. Le marchand qui se croit supérieur à son client, qui méprise le pauvre, qui s'enorgueillit de sa richesse, trahit l'esprit du commerce prophétique.

> « Le marchand véridique et digne de confiance est avec les prophètes, les véridiques et les martyrs. » - Hadith rapporté par At-Tirmidhî

Cette élévation n'est pas sociale mais spirituelle. Dans la tradition tijaniyye, le commerce licite est une forme d'adoration, pourvu qu'il soit empreint d'humilité. Cheikh Ibrahim Niasse, lui-même négociant avant d'être guide spirituel, enseignait que le profit doit servir la communauté, non enorgueillir l'individu. L'humilité économique est la reconnaissance que la richesse est un dépôt divin.

### IV.3. L'humilité envers les savants et les aînés

Le Prophète (SAWS) respectait profondément les savants et les aînés. Il se levait pour accueillir son oncle Abbas, bien qu'il fût le Messager d'Allah. Il honorait les compagnons âgés et consultait les jeunes sur des questions pratiques. Cette humilité intergénérationnelle créait une société où le respect réciproque était la norme.

Il enseignait que l'humilité envers les savants est une forme de respect envers le savoir divin : « La supériorité du savant sur le dévot est comme ma supériorité sur le plus bas d'entre vous. » (Rapporté par At-Tirmidhî). Cette supériorité n'est pas sociale mais spirituelle : le savant est supérieur parce qu'il est plus proche de la vérité, non parce qu'il est plus noble.

Dans la perspective tijaniyye, l'humilité envers le cheikh est une condition de la transmission spirituelle. Le disciple ne s'approche pas du guide avec arrogance, mais avec la modestie de celui qui sait qu'il ne sait rien. Cheikh Ahmad Tijani enseignait que le murîd doit considérer son cheikh comme un père, et le cheikh doit considérer son murîd comme un fils. Cette relation est fondée sur l'humilité réciproque.

## CINQUIÈME PARTIE : L'HUMILITÉ COMME PURIFICATION SPIRITUELLE (TAZKIYYA)

*Du cœur vidé de soi à la communauté éclairée*

### V.1. Al-Tawadu' comme lumière du cœur

L'enseignement spirituel souligne que l'humilité est une lumière qui élève l'homme. Cette métaphore est profondément ancrée dans la tradition soufie. Al-Ghazâlî, dans son Ihyâ' 'Ulûm al-Dîn, traite du tawadu' comme d'une nûr (lumière) qui dissipe les ténèbres de l'orgueil (kibr), de la vanité ('ujb) et de l'égoïsme (anâniyya).

L'humilité purifie le cœur (qalb) parce qu'elle l'oblige à se vider : vidage de l'orgueil, de la prétention, de la certitude de sa propre suffisance. Le cœur plein de soi - qui se croit savant, riche, puissant - est le siège de l'angoisse spirituelle. Le cœur humble est en paix, car il sait que tout vient de Dieu et que tout retourne à Dieu.

Dans la tijaniyye, cette paix est appelée itmi'nân : la sérénité du cœur qui a trouvé son centre dans l'amour prophétique. Cheikh Ahmad Tijani enseignait que la murâqaba doit être empreinte d'humilité. On ne se tient pas devant Dieu avec arrogance, mais avec la modestie de celui qui sait qu'il n'est rien sans Lui. L'humilité est le vide qui permet à la grâce de descendre.

### V.2. L'humilité et l'examen de conscience (muhâsaba)

Le maître soufi Al-Hârith al-Muhâsibî (m. 243 H) a fondé toute une science sur l'examen de conscience. Pour lui, le tawadu' est impossible sans un travail permanent d'introspection. Le croyant doit se demander chaque soir : ai-je été orgueilleux aujourd'hui ? Ai-je méprisé quelqu'un ? Ai-je profité de mon statut pour dominer ?

Ce travail est le jihâd al-akbar (le grand combat), celui contre son propre ego. Dans la tijaniyye, cette muhâsaba est le préalable à toute fayda : on ne reçoit que ce que l'on est capable de contenir, et un réceptacle plein de soi ne peut retenir la lumière. Cheikh Ahmad Tijani recommandait à ses disciples la revue quotidienne de leurs états d'âme avant le coucher, afin de ne pas emporter l'orgueil dans la nuit.

L'examen de conscience dans la perspective de l'humilité n'est pas une auto-flagellation. C'est un regard bienveillant sur soi-même, qui reconnaît les imperfections sans s'y complaire, et qui s'appuie sur la miséricorde divine pour se relever. Le talibé ne se juge pas ; il se soigne. Et le premier remède est la conscience de sa propre néantité face à Dieu.

### V.3. L'élévation de la condition humaine par l'humilité

L'humilité n'est pas seulement une vertu défensive (ne pas être orgueilleux). Elle est une vertu élévatrice : elle élève celui qui la pratique au-dessus de la médiocrité, au-dessus de la petitesse des calculs, au-dessus de la fragmentation du moi moderne. Le Prophète (SAWS) a élevé l'humanité non seulement par son message théologique, mais par la densité éthique de sa personne.

Dans la perspective tijaniyye, cette élévation est la fayda elle-même : la dérivation spirituelle n'est pas une récompense, mais une conséquence naturelle de l'alignement de l'être sur le Prophète (SAWS). Quand le cœur devient vide de soi, il devient transparent au Prophète (SAWS), et c'est par cette transparence que descend la grâce. Cheikh Ibrahim Niasse enseignait que la fayda al-tijaniyya est la fayda de l'humilité muhammadienne. Or, le Prophète (SAWS) est le plus humble des créatures. Recevoir sa fayda sans être humble soi-même est une contradiction.

En définitive, l'humilité est le couronnement de la spiritualité tijaniyye. Elle n'est pas un ornement moral mais l'essence même de la voie. On n'approche pas le Prophète (SAWS) par l'orgueil, mais par l'humilité. On ne touche pas à la fayda par la force, mais par la modestie. La tariqa est une école de tawadu' où le disciple apprend à devenir rien pour que Dieu devienne tout.

## CHAPITRE VI : L'HUMILITÉ FACE À L'ORGUEIL ET À LA VANITÉ

*Le kibr comme racine de tout péché*

### VI.1. Fondements coraniques et hadithiques

Le Coran consacre de nombreux versets à la condamnation de l'orgueil (kibr) et de la vanité ('ujb). Le terme kibr apparaît dans des contextes où il est associé au refus de la soumission divine. Le Coran rapporte que Satan fut chassé du Paradis pour son orgueil : « Je suis meilleur que lui ; Tu m'as créé de feu et Tu l'as créé d'argile. » (Sourate 7, v. 12). Cette rébellion fondatrice établit l'orgueil comme la racine de tout péché.

Le Prophète (SAWS) déclarait : « L'orgueil, c'est le rejet de la vérité et le mépris des gens. » (Rapporté par Muslim). Cette définition est fondamentale : l'orgueil n'est pas seulement une attitude sociale ; c'est une rupture avec la vérité. Celui qui s'enorgueillit refuse de reconnaître sa propre dépendance envers Dieu. La vanité ('ujb) est la petite sœur de l'orgueil : c'est l'admiration de soi-même, la satisfaction de ses propres qualités.

> « Celui qui a dans son cœur l'équivalent d'un atome d'orgueil n'entrera pas au Paradis. » - Hadith rapporté par Muslim

### VI.2. Le Prophète (SAWS) et la lutte contre le kibr

Le Prophète (SAWS) combattait l'orgueil par l'exemple. Il refusait les sièges d'honneur, mangeait avec les esclaves, et s'asseyait par terre. Il déclarait : « Je suis le serviteur de Dieu et Son messager. Par Dieu, je ne suis pas meilleur que vous, sauf par la piété. » (Rapporté par Al-Bukhârî). Cette humilité prophétique n'était pas une fausse modestie ; c'était la conscience vécue de sa propre servitude.

Il enseignait que l'orgueil peut s'insinuer dans les pratiques les plus pieuses. Celui qui jeûne pour être admiré, qui prie pour être écouté, qui donne pour être remercié, tombe dans le piège de l'orgueil spirituel. C'est pourquoi il insistait sur la sincérité d'intention (ikhlâs) comme antidote à l'orgueil. L'humilité véritable ne se mesure pas aux apparences mais aux intentions.

Dans la perspective tijaniyye, la lutte contre l'orgueil est le jihâd permanent du disciple. Cheikh Ahmad Tijani enseignait que le murîd doit se considérer comme le plus bas des serviteurs, même s'il accomplit des miracles. La fayda ne descend pas sur le cœur orgueilleux ; elle descend sur le cœur vide de soi.

### VI.3. Portée psychologique et spirituelle

L'orgueil n'est pas seulement un péché moral ; c'est une maladie psychologique. L'orgueilleux vit dans une prison de soi : il ne peut pas recevoir la critique, ne peut pas pardonner, ne peut pas aimer sincèrement. Il est constamment en guerre contre le monde, car le monde ne reconnaît pas sa supériorité. Cette souffrance existentielle est le prix de l'orgueil.

L'humilité, inversement, est une thérapie. Celui qui s'humilie pour Dieu est libéré de la prison du moi. Il peut recevoir la critique, pardonner, aimer sans attendre de retour. Il est en paix avec le monde, car il n'attend rien du monde. Cette paix est le fruit de l'humilité.

Dans la tradition tijaniyye, cette guérison par l'humilité est centrale. Le talibé qui souffre de dépression, d'anxiété ou de solitude trouve dans l'humilité un remède. Car l'humilité n'est pas l'auto-dénigrement ; c'est la reconnaissance de sa place dans l'ordre divin. Et cette reconnaissance apporte la paix.

## CHAPITRE VII : L'HUMILITÉ DANS L'ADORATION ET LA VIE SPIRITUELLE

*Khushu', dhikr et murâqaba*

### VII.1. L'humilité dans la prière (salât) et le jeûne (sawm)

Le Prophète (SAWS) priait avec une humilité qui stupéfiait ses compagnons. Il pleurait dans sa prière jusqu'à ce que sa barbe soit mouillée. Il se prosternait si longtemps que ses petits-enfants pouvaient monter sur son dos sans qu'il ne bouge. Cette humilité liturgique (khushu') était le cœur de son adoration.

Il enseignait que l'humilité dans la prière est la condition de son acceptation. Celui qui prie avec distraction et orgueil, sa prière est rejetée. Celui qui prie avec humilité et concentration, sa prière est élevée vers Dieu. Le jeûne, de même, doit être accompli dans l'humilité. Celui qui jeûne pour être admiré ou pour se sentir supérieur aux autres, son jeûne est rejeté.

Dans la perspective tijaniyye, le salât 'alâ an-nabî est l'exercice par excellence de l'humilité. Le disciple ne s'adresse pas au Prophète (SAWS) en tant qu'égal, mais en tant que serviteur implorant la grâce. Cette posture d'humilité est le préalable à toute fayda. On ne reçoit pas la grâce en s'érigeant, mais en s'abaissant.

### VII.2. L'humilité dans le dhikr et la murâqaba

Le dhikr (invocation divine) est le cœur de la pratique soufie. Mais le dhikr sans humilité est un vain bavardage. Le Prophète (SAWS) enseignait que l'invocation doit être accompagnée de la conscience de la présence divine (hudûr). Cette conscience implique l'humilité : on ne se tient pas devant Dieu avec arrogance, mais avec la modestie de celui qui sait qu'il n'est rien sans Lui.

La murâqaba (vigilance spirituelle) est la pratique par excellence de l'humilité. Elle consiste à maintenir un état de conscience permanente de la présence divine, comme si l'on voyait Dieu ou, à défaut, comme si Dieu nous voyait. Cette pratique exige une humilité radicale : on ne peut feindre la présence divine. Le cœur sait s'il est humble ou orgueilleux.

Dans la tradition tijaniyye, la murâqaba est le pilier central de la pratique. Cheikh Ahmad Tijani enseignait que le murîd doit se tenir devant Dieu comme un serviteur devant son maître. Cette posture d'humilité est la condition de la fayda. La grâce ne descend pas sur le cœur orgueilleux ; elle descend sur le cœur vide de soi.

### VII.3. L'humilité comme condition de la réalisation spirituelle

La réalisation spirituelle (tahqîq) dans la tradition musulmane est le fruit de l'humilité. On ne connaît pas Dieu par l'orgueil, mais par l'humilité. On ne s'approche pas du Prophète (SAWS) par la force, mais par la modestie. On ne reçoit pas la fayda par le mérite, mais par la grâce.

Cheikh Ahmad Tijani enseignait que le murîd doit se considérer comme le plus ignorant des serviteurs, le plus pécheur des croyants, le plus indigne des disciples. Cette conscience de son indignité n'est pas une dépression morale ; c'est la reconnaissance de la vérité. Car face à Dieu, nous sommes tous indignes. Et c'est précisément cette indignité qui nous rend dignes de la grâce.

Dans la perspective tijaniyye, l'humilité est donc la condition sine qua non de la réalisation spirituelle. Le murîd qui s'enorgueillit de sa pratique, qui se vante de ses visions, qui croit avoir atteint un degré spirituel, tombe dans le piège de l'orgueil spirituel. La fayda est retirée de lui, car la grâce ne demeure pas dans un cœur plein de soi.

## CHAPITRE VIII : AL-TAWADU' CHEZ CHEIKH AHMAD TIJANI ET DANS LA FAYDA

*L'humilité comme fondement de la voie*

### VIII.1. L'humilité comme fondement de la Tariqa Tijaniyya

Cheikh Ahmad Tijani (1737-1815), fondateur de la Tariqa Tijaniyya, a placé l'humilité au centre de sa doctrine spirituelle. Pour lui, la tariqa n'est pas une voie d'ascèse morbide ou de retrait du monde ; c'est une voie d'ouverture à la miséricorde divine par l'humilité. Il enseignait que Dieu a créé la création par miséricorde, et que toute spiritualité authentique doit refléter cette origine.

Dans ses écrits, notamment dans Jawâhir al-Ma'ânî, Cheikh Tijani développe l'idée que le Prophète (SAWS) est le réceptacle premier de l'humilité divine. Le talibé tijane, par sa wird et sa murâqaba, cherche à devenir un canal de cette même humilité. Ce n'est pas une appropriation arrogante ; c'est une disponibilité humble. Le disciple se vide de son orgueil pour être rempli de l'humilité muhammadienne.

Cheikh Tijani insistait sur le fait que le murîd ne doit jamais se prévaloir de son statut spirituel, de sa connaissance ou de sa piété. Celui qui s'enorgueillit de sa pratique tombe dans le piège de l'orgueil spirituel. La fayda ne descend que sur le cœur vide de soi. C'est pourquoi il recommandait la revue quotidienne des intentions et la prière de demande de pardon (istighfâr) avant chaque wird.

### VIII.2. Le salât 'alâ an-nabî comme acte d'humilité

Le salât 'alâ an-nabî (prière sur le Prophète) est le pilier central de la pratique tijaniyye. Cheikh Tijani enseignait que cette invocation n'est pas seulement une louange adressée au Prophète (SAWS) ; c'est un acte d'humilité profonde où le disciple reconnaît sa propre indignité et implore la grâce. Chaque salât est une goutte d'humilité qui adoucit le cœur, efface les péchés et rapproche du Prophète (SAWS).

Cette pratique exige une qualité de présence (hudûr) qui n'est possible qu'à partir d'un cœur purifié de l'orgueil et de la vanité. L'humilité n'est pas un don qu'on reçoit passivement ; c'est une qualité qu'on active par la sincérité de l'invocation. Cheikh Tijani recommandait de commencer chaque wird par l'intention pure de s'humilier devant le Prophète (SAWS), et non pour s'enorgueillir de sa pratique.

### VIII.3. Cheikh Ibrahim Niasse et l'humilité dans la transmission de la fayda

Cheikh Ibrahim Niasse (qu'Allah sanctifie son secret), figure majeure de la diffusion de la fayda tijaniyye en Afrique de l'Ouest, a toujours mis en avant que la fayda est essentiellement une fayda al-tawadu'. Elle n'est pas une force magique ou un pouvoir occulte ; c'est un déversement de grâce divine qui transforme le cœur du disciple par l'humilité.

Cheikh Niasse enseignait que la fayda ne s'acquiert pas par la quantité de litanies, mais par la qualité de l'humilité intérieure. Un cœur orgueilleux, un cœur qui juge, un cœur qui méprise les autres, ne peut recevoir la fayda. C'est pourquoi il insistait sur la nécessité de la muhâsaba quotidienne et de la bienfaisance concrète envers les pauvres, les malades et les exclus.

Malgré sa renommée mondiale, Cheikh Niasse vivait dans une simplicité qui stupéfiait ses visiteurs. Il recevait les plus humbles avec la même attention que les savants, et refusait tout traitement de faveur. Cette humilité n'était pas une stratégie de communication ; c'était la manifestation d'un cœur vide de soi. La fayda al-tijaniyya, dans cette perspective, est une école d'humilité où le disciple apprend à devenir rien pour que Dieu devienne tout.

## CONCLUSION GÉNÉRALE

### Synthèse

L'enseignement porté par le thème du JikooY Sangue Bi pour le Gamou 1448H / 2026 nous rappelle que l'humilité n'est pas un accessoire moral, mais le couronnement de la spiritualité prophétique. De la société jahiliyya à la conquête de La Mecque, de la vie domestique à la gouvernance politique, de l'adoration intime à la transmission spirituelle, l'humilité constitue la trame continue du message.

Trois principes structurants émergent de cette étude : (1) L'antériorité : l'humilité du Prophète (SAWS) précédait sa mission ; elle en était la condition de recevabilité. (2) La totalité : elle concerne tous les domaines de la vie - domestique, sociale, politique, économique et spirituelle. (3) L'élévation : elle purifie le cœur et consolide la communauté, faisant de chaque individu un serviteur de Dieu et un frère des humains.

### Ouverture : défis contemporains et recommandations

Dans un monde où l'exhibition de soi, la culture du paraître et la domination sur les autres sont devenues des normes, revenir à l'humilité est un acte de résistance civilisationnelle. Le Gamou ne doit pas être seulement une commémoration festive, mais une réinstallation existentielle dans la modestie.

Que chaque talibé, chaque membre de l'AMSTC, chaque croyant, fasse de cette année 1448H l'occasion d'un examen radical : mon cœur est-il vide de l'orgueil ? Ma pratique spirituelle est-elle empreinte d'humilité ? Ma place dans la société reflète-t-elle la servitude envers Dieu ?

Dans la voie tijaniyye, c'est par le tawadu' que l'on accède au Sirr, et c'est par le Sirr que l'on touche à l'essence de l'Amour prophétique.

> « Et les serviteurs du Tout Miséricordieux sont ceux qui marchent humblement sur terre. » - Sourate 25, v. 63

Yalla nangu ko. Amin.

## BIBLIOGRAPHIE INDICATIVE

- Ibn Hishâm, Sîrat Ibn Hishâm.
- Al-Bukhârî, Sahîh al-Bukhârî (Livre des qualités morales, Livre de la prière, Livre de l'adoration).
- Muslim, Sahîh Muslim (Livre de la foi, Livre de l'humilité).
- Al-Ghazâlî, Ihyâ' 'Ulûm al-Dîn (Livre des qualités morales, Livre de la méditation).
- Al-Hârith al-Muhâsibî, Kitâb al-Muhâsabî.
- Al-Tabarî, Târîkh al-Rusul wa-l-Mulûk.
- Cheikh Ahmad Tijani, Jawâhir al-Ma'ânî.
- Cheikh Ibrahim Niasse, Kâshif al-Ilbâs et écrits sur la fayda.
- Ouvrages contemporains sur la tijaniyya ouest-africaine et la fayda.
- AMSTC, Thème du Gamou 1448H / 2026 : JikooY Sangue Bi (L'Humilité).$cours$;
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
           duration_min = 28,
           order_index  = 3
     where title = v_titre;
  else
    insert into public.daara_courses
      (title, description, category, content, author, duration_min, order_index, is_published)
    values (v_titre, v_desc, 'islam', v_contenu, 'Demba Tahirou DIOP', 28, 3, false);
  end if;
end $$;

-- Contrôle : les trois volets du thème, dans l'ordre.
select order_index, title, category, author, duration_min, is_published,
       length(content) as caracteres
  from public.daara_courses
 where title like 'Al-%'
 order by order_index;

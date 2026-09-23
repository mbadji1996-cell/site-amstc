-- Quiz médical de l'AMSTC du 23 septembre 2026
--
-- Présenté par Makhtar Sall Diouf, étudiant en 3e année de pharmacie.
-- Le document d'origine posait trente questions ouvertes ; le moteur de
-- l'espace membres ne connaît que le QCM à quatre propositions. Chaque
-- question a donc reçu trois mauvaises réponses, et la bonne change de
-- place d'une question à l'autre.
--
-- Ce script n'est pas une phase : il n'ajoute aucune table. Il pose un
-- contenu, et peut être rejoué sans rien casser - les tentatives déjà
-- enregistrées par les membres sont conservées, seules les questions
-- sont réécrites.
--
-- Pour publier tout de suite, mettre v_publie à true ci-dessous. Sinon,
-- le quiz reste en brouillon et le bouton « Publier » de la page
-- Enseignements Médicaux le rend visible quand vous l'avez relu.

do $$
declare
  v_quiz   uuid;
  v_publie boolean := false;   -- true pour publier dès maintenant
  v_titre  text := 'Quiz médical AMSTC - 23 septembre 2026';
begin
  select id into v_quiz from public.quizzes where title = v_titre;

  if v_quiz is null then
    insert into public.quizzes (title, description, category, duration_min, is_published)
    values (v_titre, 'Trente questions de pharmacologie, physiologie, immunologie et microbiologie, proposées par Makhtar Sall Diouf, étudiant en 3e année de pharmacie. Trois parties : questions directes, classes pharmacologiques, et « qui suis-je ».', 'pharmacie', 20, v_publie)
    returning id into v_quiz;
  else
    update public.quizzes
       set description  = 'Trente questions de pharmacologie, physiologie, immunologie et microbiologie, proposées par Makhtar Sall Diouf, étudiant en 3e année de pharmacie. Trois parties : questions directes, classes pharmacologiques, et « qui suis-je ».',
           category     = 'pharmacie',
           duration_min = 20
     where id = v_quiz;
    delete from public.quiz_questions where quiz_id = v_quiz;
  end if;

  insert into public.quiz_questions (quiz_id, order_index, question, options, correct_index, explanation)
  values
    (v_quiz, 0, 'Quel paramètre pharmacocinétique quantifie la capacité de l''organisme à éliminer un médicament ?', '["La clairance", "La biodisponibilité", "Le volume de distribution", "La constante d''absorption"]'::jsonb, 0, 'La clairance est le volume de plasma totalement épuré du médicament par unité de temps. La biodisponibilité mesure la fraction de dose qui atteint la circulation, le volume de distribution la diffusion dans l''organisme.'),
    (v_quiz, 1, 'Quel récepteur est principalement responsable de la bronchodilatation induite par le salbutamol ?', '["Le récepteur β1", "Le récepteur α1", "Le récepteur β2", "Le récepteur muscarinique M3"]'::jsonb, 2, 'Le salbutamol est un agoniste β2 sélectif : la stimulation β2 relâche le muscle lisse bronchique. Le récepteur β1 est surtout cardiaque, et la stimulation M3 provoque au contraire une bronchoconstriction.'),
    (v_quiz, 2, 'Quelle classe d''antibiotiques inhibe la synthèse de la paroi bactérienne ?', '["Les macrolides", "Les fluoroquinolones", "Les aminosides", "Les bêta-lactamines"]'::jsonb, 3, 'Les bêta-lactamines bloquent les protéines liant la pénicilline, donc la synthèse du peptidoglycane. Les macrolides et les aminosides visent le ribosome, les fluoroquinolones l''ADN gyrase.'),
    (v_quiz, 3, 'Quel neurotransmetteur est libéré au niveau de la jonction neuromusculaire ?', '["La noradrénaline", "L''acétylcholine", "Le glutamate", "La dopamine"]'::jsonb, 1, 'L''acétylcholine est libérée par la terminaison motrice et se fixe sur les récepteurs nicotiniques de la plaque motrice.'),
    (v_quiz, 4, 'Quelle hormone est sécrétée par les cellules bêta du pancréas ?', '["Le glucagon", "La somatostatine", "L''insuline", "La gastrine"]'::jsonb, 2, 'Les cellules bêta des îlots de Langerhans sécrètent l''insuline. Le glucagon vient des cellules alpha, la somatostatine des cellules delta.'),
    (v_quiz, 5, 'Quelle immunoglobuline est impliquée dans les réactions allergiques immédiates ?', '["Les IgE", "Les IgG", "Les IgA", "Les IgM"]'::jsonb, 0, 'Dans l''hypersensibilité de type I, les IgE fixées sur les mastocytes déclenchent leur dégranulation au contact de l''allergène.'),
    (v_quiz, 6, 'Quel est le principal constituant minéral de l''émail dentaire ?', '["Le carbonate de calcium", "L''hydroxyapatite", "Le fluorure de sodium", "Le collagène de type I"]'::jsonb, 1, 'L''émail est minéralisé à environ 96 % par de l''hydroxyapatite. Le collagène, lui, est organique et se trouve dans la dentine.'),
    (v_quiz, 7, 'Quelle bactérie est responsable de la tuberculose humaine ?', '["Mycobacterium leprae", "Streptococcus pneumoniae", "Bordetella pertussis", "Mycobacterium tuberculosis"]'::jsonb, 3, 'Mycobacterium tuberculosis, le bacille de Koch. M. leprae est l''agent de la lèpre.'),
    (v_quiz, 8, 'Quel antidote spécifique est utilisé en cas de surdosage en paracétamol ?', '["La naloxone", "La N-acétylcystéine", "Le flumazénil", "La vitamine K"]'::jsonb, 1, 'La N-acétylcystéine reconstitue les réserves hépatiques de glutathion. La naloxone traite les opioïdes, le flumazénil les benzodiazépines, la vitamine K les antivitamines K.'),
    (v_quiz, 9, 'Quelle enzyme est inhibée par les statines ?', '["La cyclo-oxygénase", "L''acétylcholinestérase", "La HMG-CoA réductase", "La phosphodiestérase de type 5"]'::jsonb, 2, 'Les statines bloquent la HMG-CoA réductase, étape limitante de la synthèse hépatique du cholestérol.'),
    (v_quiz, 10, 'Quel est le principal neurotransmetteur inhibiteur du système nerveux central ?', '["Le glutamate", "La sérotonine", "L''acétylcholine", "Le GABA"]'::jsonb, 3, 'Le GABA est le principal neurotransmetteur inhibiteur ; le glutamate est le principal excitateur.'),
    (v_quiz, 11, 'Quelle vitamine est indispensable à la synthèse hépatique de plusieurs facteurs de coagulation ?', '["La vitamine K", "La vitamine C", "La vitamine D", "La vitamine B12"]'::jsonb, 0, 'La vitamine K permet la carboxylation des facteurs II, VII, IX et X, ainsi que des protéines C et S.'),
    (v_quiz, 12, 'Quel ion contribue principalement à la repolarisation du potentiel d''action cardiaque ?', '["Le sodium", "Le calcium", "Le potassium", "Le chlorure"]'::jsonb, 2, 'La sortie de potassium ramène la cellule vers son potentiel de repos. L''entrée de sodium fait la dépolarisation, celle de calcium le plateau.'),
    (v_quiz, 13, 'Quelle cellule est spécialisée dans la production des anticorps ?', '["Le lymphocyte T auxiliaire", "Le plasmocyte", "Le macrophage", "Le polynucléaire neutrophile"]'::jsonb, 1, 'Le plasmocyte est le lymphocyte B différencié en usine à anticorps.'),
    (v_quiz, 14, 'Quel facteur de coagulation appartient à la voie extrinsèque ?', '["Le facteur VII", "Le facteur VIII", "Le facteur IX", "Le facteur XII"]'::jsonb, 0, 'Le facteur VII s''associe au facteur tissulaire pour lancer la voie extrinsèque, explorée par le temps de Quick. Les facteurs VIII, IX et XII appartiennent à la voie intrinsèque.'),
    (v_quiz, 15, 'Quelle famille de molécules végétales possède une partie sucrée liée à un aglycone stéroïdien ou triterpénique ?', '["Les alcaloïdes", "Les tanins", "Les flavonoïdes", "Les saponosides"]'::jsonb, 3, 'Les saponosides doivent leur nom à leur pouvoir moussant ; ils sont aussi hémolytiques.'),
    (v_quiz, 16, 'Quel type de liaison permet une fixation irréversible d''un médicament à sa cible ?', '["La liaison ionique", "La liaison covalente", "La liaison hydrogène", "Les forces de Van der Waals"]'::jsonb, 1, 'Seule la liaison covalente est assez forte pour être irréversible : c''est le cas de l''aspirine sur la cyclo-oxygénase.'),
    (v_quiz, 17, 'Quelle enzyme est activée par la sous-unité αs d''une protéine Gs ?', '["La phospholipase C", "La guanylate cyclase", "L''adénylate cyclase", "La protéine kinase C"]'::jsonb, 2, 'L''adénylate cyclase produit alors l''AMP cyclique. La phospholipase C, elle, dépend des protéines Gq.'),
    (v_quiz, 18, 'Quel acide aminé est le précurseur de la dopamine ?', '["Le tryptophane", "La glycine", "L''histidine", "La tyrosine"]'::jsonb, 3, 'La tyrosine donne la L-DOPA, puis la dopamine. Le tryptophane est le précurseur de la sérotonine.'),
    (v_quiz, 19, 'Quel type de lymphocyte détruit les cellules infectées par des virus ?', '["Le lymphocyte T CD8+", "Le lymphocyte T CD4+ auxiliaire", "Le lymphocyte T régulateur", "Le lymphocyte B mémoire"]'::jsonb, 0, 'Le lymphocyte T CD8+ cytotoxique reconnaît l''antigène présenté par le CMH de classe I et détruit la cellule infectée.'),
    (v_quiz, 20, 'À quelle classe pharmacologique appartient l''ivermectine ?', '["Un antipaludique", "Un antihelminthique", "Un antifongique", "Un antiviral"]'::jsonb, 1, 'L''ivermectine agit sur les canaux chlore glutamate-dépendants des invertébrés. Elle sert aussi dans la gale et l''onchocercose.'),
    (v_quiz, 21, 'Dans quelle classe d''antibiotiques la vancomycine est-elle classée ?', '["Les macrolides", "Les cyclines", "Les aminosides", "Les glycopeptides"]'::jsonb, 3, 'La vancomycine est un glycopeptide, actif sur les bactéries à Gram positif, dont le staphylocoque résistant à la méticilline.'),
    (v_quiz, 22, 'À quelle classe appartient le furosémide ?', '["Un diurétique de l''anse", "Un diurétique thiazidique", "Un diurétique épargneur de potassium", "Un inhibiteur de l''anhydrase carbonique"]'::jsonb, 0, 'Le furosémide inhibe le cotransporteur Na-K-2Cl de la branche ascendante de l''anse de Henle.'),
    (v_quiz, 23, 'À quelle classe appartient l''amiodarone ?', '["Un antihypertenseur central", "Un anticoagulant", "Un antiarythmique", "Un antiagrégant plaquettaire"]'::jsonb, 2, 'L''amiodarone est un antiarythmique de classe III de Vaughan Williams : elle allonge la repolarisation.'),
    (v_quiz, 24, 'À quelle classe appartient la spironolactone ?', '["Un diurétique de l''anse", "Un bêtabloquant", "Un diurétique épargneur de potassium", "Un inhibiteur calcique"]'::jsonb, 2, 'La spironolactone est un antagoniste des récepteurs de l''aldostérone : elle retient le potassium, d''où le risque d''hyperkaliémie.'),
    (v_quiz, 25, 'À quelle classe appartient la ceftriaxone ?', '["Une pénicilline", "Une céphalosporine", "Une fluoroquinolone", "Un carbapénème"]'::jsonb, 1, 'La ceftriaxone est une céphalosporine de troisième génération, injectable, très utilisée dans les méningites et les infections sévères.'),
    (v_quiz, 26, 'Qui suis-je ? Médicament de l''épilepsie, je bloque les canaux sodiques voltage-dépendants et je sers aussi dans certaines douleurs neuropathiques.', '["Le diazépam", "Le phénobarbital", "La morphine", "La carbamazépine"]'::jsonb, 3, 'La carbamazépine est le traitement de référence de la névralgie du trijumeau.'),
    (v_quiz, 27, 'Qui suis-je ? Hormone synthétisée par l''hypothalamus et libérée par la neurohypophyse, je favorise la réabsorption d''eau par le rein.', '["La vasopressine (ADH)", "L''ocytocine", "L''aldostérone", "Le peptide natriurétique auriculaire"]'::jsonb, 0, 'L''hormone antidiurétique agit sur les aquaporines-2 du tube collecteur. Son défaut donne le diabète insipide.'),
    (v_quiz, 28, 'Qui suis-je ? Enzyme virale indispensable à la multiplication du VIH, je transforme l''ARN viral en ADN complémentaire.', '["La protéase virale", "La transcriptase inverse", "L''intégrase", "La neuraminidase"]'::jsonb, 1, 'La transcriptase inverse est la cible des INTI et des INNTI, socle des trithérapies.'),
    (v_quiz, 29, 'Qui suis-je ? Protéine produite par le foie, je maintiens l''essentiel de la pression oncotique du plasma.', '["La fibrine", "L''hémoglobine", "L''albumine", "La ferritine"]'::jsonb, 2, 'L''albumine assure environ 80 % de la pression oncotique ; son effondrement explique les œdèmes du syndrome néphrotique.');
end $$;

-- Contrôle : le quiz et ses trente questions.
select q.title,
       q.category,
       q.duration_min,
       q.is_published,
       count(qq.id) as questions
  from public.quizzes q
  left join public.quiz_questions qq on qq.quiz_id = q.id
 where q.title = 'Quiz médical AMSTC - 23 septembre 2026'
 group by q.id, q.title, q.category, q.duration_min, q.is_published;

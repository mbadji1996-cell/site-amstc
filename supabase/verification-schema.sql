-- ============================================================
-- VÉRIFICATION DU SCHÉMA - à exécuter après chaque déploiement
--
-- Pourquoi : les fichiers supabase/*.sql sont versionnés dans Git, mais
-- rien ne garantit qu'ils ont réellement été exécutés sur la base de
-- production (il faut les coller à la main dans Studio > SQL Editor).
-- Deux pannes ont déjà eu cette cause : une table ou une fonction
-- existait dans le dépôt mais pas en base, et la panne ne se voyait que
-- côté visiteur, longtemps après.
--
-- Usage : Supabase Studio > SQL Editor > New query > coller > Run.
-- Lecture du résultat : tout ce qui est marqué MANQUANT doit être créé
-- en exécutant le fichier supabase/*.sql correspondant. Une base saine
-- ne renvoie que des lignes OK.
--
-- Ce script est en lecture seule : il ne modifie jamais rien.
-- ============================================================

with attendu(nom, type_objet) as (values
  -- ===== Tables =====
  ('app_settings',            'table'),
  ('campaign_requests',       'table'),
  ('card_validity_payments',  'table'),
  ('cotisation_payments',     'table'),
  ('cotisations',             'table'),
  ('daara_courses',           'table'),
  ('daara_progress',          'table'),
  ('forum_replies',           'table'),
  ('forum_topics',            'table'),
  ('media_folders',           'table'),
  ('media_photos',            'table'),
  ('medical_lessons',         'table'),
  ('member_announcements',    'table'),
  ('member_cards',            'table'),
  ('member_since_requests',   'table'),
  ('membership_payments',     'table'),
  ('orders',                  'table'),
  ('product_photos',          'table'),
  ('products',                'table'),
  ('profiles',                'table'),
  ('quiz_attempts',           'table'),
  ('quiz_questions',          'table'),
  ('quizzes',                 'table'),
  -- restricted_formations a été renommée en restricted_articles (phase3b)
  ('restricted_articles',     'table'),
  ('rpc_rate_limit_log',      'table'),
  ('whatsapp_broadcasts',     'table'),

  -- ===== Vues =====
  ('member_cards_unclaimed',      'vue'),
  ('restricted_articles_teasers', 'vue'),

  -- ===== Fonctions appelées directement par le site (les plus critiques :
  -- leur absence casse une page entière, comme la Bibliothèque) =====
  ('bibliotheque_documents',    'fonction'),
  ('forum_topics_list',         'fonction'),
  ('member_directory',          'fonction'),
  ('published_medical_lessons', 'fonction'),
  ('published_product_photos',  'fonction'),
  ('published_products',        'fonction'),
  ('published_quizzes',         'fonction'),
  ('claim_member_card',         'fonction'),
  ('whatsapp_target_count',     'fonction'),
  ('whatsapp_target_members',   'fonction'),

  -- ===== Fonctions internes (contrôles d'accès, déclencheurs, admin) =====
  ('_whatsapp_targets',                'fonction'),
  ('apply_member_since',               'fonction'),
  ('approve_or_reject_user',           'fonction'),
  ('assign_member_card',               'fonction'),
  ('check_max_pinned_announcements',   'fonction'),
  ('check_rate_limit',                 'fonction'),
  ('confirm_card_validity_payment',    'fonction'),
  ('creer_carte_membre',               'fonction'),
  ('confirm_cotisation_payment',       'fonction'),
  ('confirm_member_card_claim',        'fonction'),
  ('forum_touch_topic',                'fonction'),
  ('handle_new_user',                  'fonction'),
  ('is_active_member',                 'fonction'),
  ('is_admin',                         'fonction'),
  ('is_approved_member',               'fonction'),
  ('is_super_admin',                   'fonction'),
  ('member_since_requests_pending',    'fonction'),
  ('next_card_number',                 'fonction'),
  ('notify_admin',                     'fonction'),
  ('notify_admin_on_campaign_request', 'fonction'),
  ('notify_admin_on_card_claim',       'fonction'),
  ('notify_admin_on_forum_topic',      'fonction'),
  ('notify_admin_on_order',            'fonction'),
  ('notify_admin_on_signup',           'fonction'),
  ('reject_member_card_claim',         'fonction'),
  ('request_member_since',             'fonction'),
  ('review_member_since_request',      'fonction'),
  ('set_member_years',                 'fonction'),
  ('set_user_active',                  'fonction'),
  ('set_user_role',                    'fonction')
),
resultat as (
  select
    a.type_objet,
    a.nom,
    case
      when a.type_objet = 'table' then
        case when exists (
          select 1 from pg_class c
          join pg_namespace n on n.oid = c.relnamespace
          where n.nspname = 'public' and c.relname = a.nom and c.relkind = 'r'
        ) then 'OK' else 'MANQUANT' end
      when a.type_objet = 'vue' then
        case when exists (
          select 1 from pg_class c
          join pg_namespace n on n.oid = c.relnamespace
          where n.nspname = 'public' and c.relname = a.nom and c.relkind in ('v', 'm')
        ) then 'OK' else 'MANQUANT' end
      else
        case when exists (
          select 1 from pg_proc p
          join pg_namespace n on n.oid = p.pronamespace
          where n.nspname = 'public' and p.proname = a.nom
        ) then 'OK' else 'MANQUANT' end
    end as statut
  from attendu a
)
select type_objet, nom, statut
from resultat
-- Les objets manquants remontent en premier : si rien n'est marqué
-- MANQUANT en haut de la liste, la base est à jour.
order by (statut = 'MANQUANT') desc, type_objet, nom;

-- ============================================================
-- PHASE 112 - Huit articles de plus dans la boutique
--
-- POURQUOI. Les gilets, polos, tenues de bloc, gourde, tasse et
-- porte-cle etaient photographies mais pas en ligne. Les photos sont
-- deposees dans le depot (assets/uploads/boutique-*.jpg, environ 150 Ko
-- chacune) et ce script cree les fiches qui les affichent.
--
-- IDEMPOTENT : un article deja present sous le meme nom n'est pas
-- recree. Vous pouvez relancer le script sans crainte de doublon.
--
-- APRES : les huit articles apparaissent dans la boutique des membres,
-- publies, stock illimite (champ vide). Les prix viennent des noms de
-- fichiers fournis. Ajustez ensuite depuis Administration > Boutique :
-- stock, description, photos supplementaires.
-- ============================================================

insert into public.products (name, description, price_fcfa, category, image_url, stock, is_published)
select v.name, v.description, v.price_fcfa, v.category, v.image_url, null, true
  from (values
  ('Gilet AMSTC blanc', 'Gilet brodé aux couleurs de l''association', 10000, 'Vêtements', '/assets/uploads/boutique-gilet-blanc.jpg'),
  ('Gilet AMSTC vert', 'Gilet brodé aux couleurs de l''association', 10000, 'Vêtements', '/assets/uploads/boutique-gilet-vert.jpg'),
  ('Polo AMSTC', 'Polo brodé, plusieurs tailles', 5000, 'Vêtements', '/assets/uploads/boutique-polo.jpg'),
  ('Tenue de bloc bleu nuit', 'Tunique et pantalon, bleu de nuit', 10000, 'Vêtements', '/assets/uploads/boutique-tenue-bloc-bleu.jpg'),
  ('Tenue de bloc rouge bordeaux', 'Tunique et pantalon, rouge bordeaux', 10000, 'Vêtements', '/assets/uploads/boutique-tenue-bloc-bordeaux.jpg'),
  ('Gourde AMSTC', 'Gourde isotherme au logo de l''association', 5000, 'Accessoires', '/assets/uploads/boutique-gourde.jpg'),
  ('Tasse personnalisée', 'Tasse au logo, personnalisable à votre nom', 5000, 'Accessoires', '/assets/uploads/boutique-tasse.jpg'),
  ('Porte-clé AMSTC', 'Porte-clé gravé au logo de l''association', 2500, 'Accessoires', '/assets/uploads/boutique-porte-cle.jpg')
  ) as v(name, description, price_fcfa, category, image_url)
 where not exists (
   select 1 from public.products p where lower(btrim(p.name)) = lower(btrim(v.name))
 );

-- ===== Controle =====
select name, price_fcfa, category, image_url, is_published
  from public.products
 order by created_at desc
 limit 12;

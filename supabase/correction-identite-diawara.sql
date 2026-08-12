-- ============================================================
-- CORRECTION - Identité de cheikhatdiawara@gmail.com
--
-- Le membre avait saisi « Cheikh Lo » en prénom et « Ahmad Tidiane
-- Diawara » en nom. Ses prénoms sont « Cheikh Ahmad Tidiane » et son nom
-- « DIAWARA ».
--
-- Les valeurs finales sont écrites en toutes lettres plutôt que calculées
-- : le script fonctionne ainsi que phase70 soit déjà exécutée ou non. Si
-- son déclencheur est en place, il recalculera exactement les mêmes
-- valeurs - l'écriture est sans effet de bord dans les deux cas.
--
-- Studio (instance amstc) > SQL Editor > Run. Ré-exécutable sans danger.
-- ============================================================

-- ===== 1. État actuel, avant d'y toucher =====
select p.email, p.first_name, p.last_name, p.full_name,
       c.card_number, c.full_name as nom_sur_la_carte
  from public.profiles p
  left join public.member_cards c
         on c.claimed_by = p.id and c.claim_status = 'confirmed'
 where p.email = 'cheikhatdiawara@gmail.com';

-- ===== 2. La fiche du membre =====
update public.profiles
   set first_name = 'Cheikh Ahmad Tidiane',
       last_name  = 'DIAWARA',
       full_name  = 'Cheikh Ahmad Tidiane DIAWARA'
 where email = 'cheikhatdiawara@gmail.com';

-- ===== 3. La carte attribuée porte le même nom =====
-- La carte imprimée lit la fiche, pas cette ligne : l'alignement sert à
-- ce que les deux écrans d'administration cessent de se contredire.
update public.member_cards c
   set full_name = p.full_name
  from public.profiles p
 where p.id = c.claimed_by
   and p.email = 'cheikhatdiawara@gmail.com'
   and c.claim_status = 'confirmed'
   and c.full_name is distinct from p.full_name;

-- ===== 4. Contrôle : les deux noms concordent =====
select p.email, p.first_name, p.last_name, p.full_name,
       c.card_number, c.full_name as nom_sur_la_carte,
       (c.full_name = p.full_name) as concordent
  from public.profiles p
  left join public.member_cards c
         on c.claimed_by = p.id and c.claim_status = 'confirmed'
 where p.email = 'cheikhatdiawara@gmail.com';

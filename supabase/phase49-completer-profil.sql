-- ============================================================
-- PHASE 49 - Compléter son profil : écran obligatoire après création.
--
-- Un compte créé via Google n'apporte que le nom et l'e-mail : téléphone,
-- domaine, localité, année d'adhésion manquent - or l'admin valide sur la
-- base de ces informations, et l'année pilote le numéro de carte. Même
-- problème pour un compte e-mail dont le formulaire aurait été bâclé.
--
-- inscription.html affiche désormais, dès qu'une session existe avec un
-- profil incomplet, un écran « Complétez votre inscription » impossible à
-- contourner. Cette fonction enregistre la complétion ; elle est appelée
-- par le MEMBRE LUI-MÊME (auth.uid()), jamais avec un identifiant fourni
-- par le client.
--
-- L'année d'adhésion n'est modifiable par ce biais QUE tant que le compte
-- est en attente (status = 'pending') : après approbation, elle passe par
-- la demande validée par l'admin (phase43), qui renumérote la carte.
--
-- À exécuter une seule fois : Studio (instance amstc) > SQL Editor > Run.
-- ============================================================

create or replace function public.completer_mon_profil(
  p_title         text,
  p_first_name    text,
  p_last_name     text,
  p_phone         text,
  p_domain        text,
  p_domain_autre  text,
  p_specialty     text,
  p_city          text,
  p_member_since  int,
  p_applicant_type text
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_statut text;
begin
  if auth.uid() is null then
    raise exception 'Connexion requise.';
  end if;

  select status into v_statut from public.profiles where id = auth.uid();
  if v_statut is null then
    raise exception 'Profil introuvable.';
  end if;

  if btrim(coalesce(p_first_name, '')) = '' or btrim(coalesce(p_last_name, '')) = '' then
    raise exception 'Prénom et nom sont obligatoires.';
  end if;
  if btrim(coalesce(p_phone, '')) = '' then
    raise exception 'Le téléphone est obligatoire.';
  end if;
  if btrim(coalesce(p_city, '')) = '' then
    raise exception 'La localité est obligatoire.';
  end if;
  if p_domain is null or p_domain not in
     ('medecine', 'pharmacie', 'odontologie', 'soins_infirmiers', 'soins_obstetricaux', 'autre') then
    raise exception 'Domaine invalide.';
  end if;
  if p_title is not null and p_title not in ('Dr', 'Pr', 'M.', 'Mme', 'Me') then
    raise exception 'Titre invalide.';
  end if;
  if p_applicant_type is not null and p_applicant_type not in ('membre_existant', 'nouvel_adherent') then
    raise exception 'Type d''inscription invalide.';
  end if;

  update public.profiles
     set title          = p_title,
         first_name     = btrim(p_first_name),
         last_name      = btrim(p_last_name),
         full_name      = btrim(p_first_name) || ' ' || btrim(p_last_name),
         phone          = btrim(p_phone),
         domain         = p_domain,
         domain_autre   = case when p_domain = 'autre' then nullif(btrim(coalesce(p_domain_autre, '')), '') else null end,
         specialty      = nullif(btrim(coalesce(p_specialty, '')), ''),
         city           = btrim(p_city),
         applicant_type = coalesce(p_applicant_type, applicant_type),
         member_since   = case
           when v_statut = 'pending'
                and p_member_since between 2014 and extract(year from now())::int
             then p_member_since
           else member_since
         end
   where id = auth.uid();
end;
$$;

grant execute on function public.completer_mon_profil(text, text, text, text, text, text, text, text, int, text) to authenticated;

/**
 * Traduit les erreurs d'authentification de Supabase (GoTrue) en français.
 *
 * Ces messages arrivent en anglais et dans le vocabulaire du serveur :
 * « Email not confirmed », « email rate limit exceeded ». Affichés tels
 * quels à un membre, ils n'indiquent ni ce qui se passe, ni quoi faire -
 * et donnent l'impression d'une panne alors que le compte va bien.
 *
 * Usage : messageAuth(error) renvoie une phrase à afficher ; toute erreur
 * inconnue est rendue telle quelle, pour ne jamais masquer un cas non
 * prévu derrière un message vague.
 */
function messageAuth(error) {
  var brut = String((error && error.message) || error || "").toLowerCase();

  if (brut.includes("email not confirmed")) {
    return "Votre adresse e-mail n'a pas encore été confirmée. "
      + "Ouvrez le message reçu à l'inscription et cliquez sur le lien "
      + "(pensez à regarder dans vos indésirables).";
  }
  if (brut.includes("rate limit") || brut.includes("too many requests")) {
    return "Trop de tentatives en peu de temps. Patientez une heure, "
      + "ou contactez l'administration de l'AMSTC pour activer votre compte directement.";
  }
  if (brut.includes("invalid login credentials")) {
    return "E-mail ou mot de passe incorrect.";
  }
  if (brut.includes("already registered") || brut.includes("already exists")) {
    return "Cette adresse a déjà un compte. Connectez-vous, ou utilisez « Mot de passe oublié ».";
  }
  if (brut.includes("password should be at least")) {
    return "Le mot de passe est trop court : 8 caractères au minimum.";
  }
  if (brut.includes("user not found")) {
    return "Aucun compte ne correspond à cette adresse.";
  }
  if (brut.includes("failed to fetch") || brut.includes("networkerror")) {
    return "Connexion au serveur impossible. Vérifiez votre réseau et réessayez.";
  }

  return (error && error.message) || "Une erreur est survenue. Réessayez.";
}

// Numéros officiels de paiement mobile de l'AMSTC - SOURCE UNIQUE pour
// l'espace membres. Toute page qui affiche un numéro de paiement
// (profil.html : validité de la carte et cotisations ; boutique.html :
// commandes) lit ces valeurs. Pour changer un numéro, modifier ICI.
// NB : la page publique de dons a sa propre copie, gérée par le CMS
// (content/don.json) - penser à mettre à jour les deux en cas de
// changement de numéro.
window.AMSTC_PAIEMENTS = {
  wave: { label: 'Wave', numero: '+221 78 828 32 16' },
  orange_money: { label: 'Orange Money', numero: '+221 78 867 96 23' },
};

// Bloc « où envoyer l'argent » affiché au-dessus des formulaires de
// paiement : les deux numéros, un bouton copier chacun, et la consigne de
// reporter le numéro de transaction après l'envoi.
function amstcNumerosPaiementHtml() {
  const lignes = Object.values(window.AMSTC_PAIEMENTS).map(p => `
    <div style="display:flex;align-items:center;gap:10px;flex-wrap:wrap;margin-top:6px;">
      <span style="min-width:110px;font-weight:600;">${p.label}</span>
      <span style="font-family:var(--mono);font-size:0.95rem;letter-spacing:0.04em;">${p.numero}</span>
      <button type="button" onclick="amstcCopierNumero(this, '${p.numero}')"
        style="border:1.5px solid var(--line);background:transparent;color:inherit;border-radius:999px;padding:3px 12px;font-size:0.75rem;cursor:pointer;">
        Copier
      </button>
    </div>`).join('');

  return `
    <div style="background:var(--paper-alt);border-radius:10px;padding:12px 16px;margin-bottom:14px;font-size:0.86rem;">
      <p style="font-weight:600;margin-bottom:2px;">1. Envoyez le montant à l'un de ces numéros :</p>
      ${lignes}
      <p style="font-weight:600;margin-top:10px;">2. Après l'envoi, indiquez ci-dessous le numéro de la transaction
        <span style="font-weight:400;color:var(--text-muted);">(reçu par SMS ou visible dans l'application)</span> :
      </p>
    </div>`;
}

function amstcCopierNumero(btn, numero) {
  navigator.clipboard.writeText(numero.replace(/\s/g, '')).then(() => {
    const avant = btn.textContent;
    btn.textContent = 'Copié !';
    setTimeout(() => { btn.textContent = avant; }, 1600);
  });
}

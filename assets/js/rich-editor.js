/**
 * Toast UI Editor wrapper - bascule "Texte enrichi" / "Markdown" comme dans Decap CMS.
 * Toolbar volontairement limitée aux styles gérés par le rendu Markdown maison du site
 * (##, **gras**, *italique*, > citation, listes, [arabic]…[/arabic]) : pas de lien/image/
 * tableau/code, qui ne seraient pas rendus côté public/membres.
 */
function createRichEditor(elementId, { placeholder = "" } = {}) {
  const el = document.getElementById(elementId);
  const editor = new toastui.Editor({
    el,
    height: "360px",
    initialEditType: "wysiwyg",
    previewStyle: "tab",
    language: "fr-FR",
    placeholder,
    toolbarItems: [
      ["heading", "bold", "italic", "quote"],
      ["ul", "ol"],
    ],
    hideModeSwitch: false,
  });
  return editor;
}

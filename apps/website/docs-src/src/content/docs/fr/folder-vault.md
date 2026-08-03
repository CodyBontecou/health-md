---
title: "Dossier et coffre"
description: "Choisissez l’emplacement de vos fichiers Markdown et nommez le sous-dossier où seront écrits les exports. Le coffre est simplement un dossier iOS : Obsidian, Fichiers, iCloud Drive et les fournisseurs de fichiers tiers sont tous compatibles."
---

## Ce que signifie « coffre » ici
<p>L’app emploie <em>coffre</em> comme nom générique du dossier choisi, que vous utilisiez ou non Obsidian. Si vous utilisez Obsidian, sélectionnez la racine de votre coffre Obsidian. Sinon, choisissez n’importe quel dossier, par exemple <code>Documents/Health</code> dans iCloud Drive ou un dossier Sur mon iPhone.</p>

## Fonctionnement du sélecteur
<p>Touchez la ligne du coffre pour ouvrir le sélecteur de documents standard d’iOS (<code>UIDocumentPickerViewController</code>). Lorsque vous choisissez un dossier, iOS renvoie une <em>URL à portée de sécurité</em> : un accès persistant qui permet à l’app de continuer à utiliser le dossier après son redémarrage sans vous solliciter de nouveau. L’app l’enregistre comme signet dans <code>UserDefaults</code>.</p>

## Nom du sous-dossier
<p>Après avoir choisi le coffre, indiquez le nom du sous-dossier de destination des exports. La valeur par défaut est <code>Health</code>. Votre choix devient le préfixe du chemin de chaque fichier exporté :</p>

<div class="doc-diagram folder-tree" aria-label="Exemple d’arborescence du dossier d’export Health.md">
<span>{vault}/</span>
<span>└─ <span class="accent">{subfolder}/</span> <span class="dim">← nom choisi dans Health.md</span></span>
<span>&nbsp;&nbsp;&nbsp;├─ 2026-04-28-tuesday.md</span>
<span>&nbsp;&nbsp;&nbsp;├─ 2026-04-27-monday.json</span>
<span>&nbsp;&nbsp;&nbsp;└─ _healthmd_data_dictionary.json</span>
</div>

<p>Vous pouvez modifier le sous-dossier plus tard dans <em>Réglages → Coffre Obsidian</em>. Les fichiers existants ne sont pas déplacés.</p>

## Comportement selon l’app
<div class="options">
<div class="option"><strong>Obsidian</strong><p>Choisissez la racine du coffre Obsidian. Définissez par exemple le sous-dossier sur <code>Health</code> afin que les exports apparaissent dans un dossier de l’arborescence du coffre.</p></div>
<div class="option"><strong>iCloud Drive</strong><p>Choisissez un dossier dans iCloud Drive. Les fichiers se synchronisent automatiquement sur tous vos appareils Apple.</p></div>
<div class="option"><strong>Sur mon iPhone</strong><p>Choisissez un dossier créé dans Fichiers → Sur mon iPhone. Il reste local, sans synchronisation.</p></div>
<div class="option"><strong>Fournisseurs tiers</strong><p>Dropbox, Google Drive, Working Copy, etc. : tout fournisseur exposé dans l’app Fichiers fonctionne de la même manière.</p></div>
</div>

<div class="callout">
<strong>Particularité d’iOS.</strong>
<p style="margin-top:6px;">Si iOS révoque le signet à portée de sécurité — cas rare, généralement lorsque le dossier sous-jacent est supprimé ou déplacé — les exports commencent à échouer. Pour corriger le problème, sélectionnez de nouveau le coffre dans <em>Réglages</em>.</p>
</div>

## Pages associées
<div class="related">
  <a href="/fr/docs/onboarding/"><span>Précédent</span>Prise en main — l’étape où vous choisissez le coffre pour la première fois.</a>
  <a href="/fr/docs/export/"><span>Suivant</span>Lancez un export dans votre nouveau coffre.</a>
  <a href="/fr/docs/format/"><span>Personnaliser</span>Personnalisation du format — définissez la façon dont les fichiers du sous-dossier sont écrits.</a>
</div>

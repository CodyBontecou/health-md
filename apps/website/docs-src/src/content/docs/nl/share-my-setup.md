---
title: "Mijn configuratie delen"
description: "Bekijk de v2-profieloverdracht die alleen in ontwikkeling is, zonder gezondheidsdata, referenties, aankopen of apparaatvertrouwen."
---

<div class="availability preview"><strong>Ontwikkelpreview · niet release-gekwalificeerd</strong><p>Het v2-contract blijft pre-canoniek en gepland tot interoperabiliteit en toegankelijkheid op apparaten zijn afgerond. Vertrouw er niet op in productie.</p></div>

Share My Setup bundelt één of meer profielen. Het verplaatst meetwaarden, formaten, namen, organisatie en bestemmingsintentie. Het bevat nooit gezondheidsdata, tokens, echte maptoegang, koppelingen, aankopen, geschiedenis of jobs.

1. Open op de bron **Instellingen → Share My Setup** en exporteer v2.
2. Open op het doel en controleer elk profiel.
3. Kies **Toevoegen** of **Vervangen**.
4. Bind lokaal map, API met referenties of Mac.
5. Pas toe en test een kleine export.

De transactie is atomair en biedt één keer **Ongedaan maken**. Profielen blijven geblokkeerd tot de bestemming is gebonden; planningen komen uitgeschakeld binnen. De huidige ontwikkelcode schrijft alleen `healthmd.shared_setup` v2; v1 wordt geweigerd.

<div class="related"><a href="/nl/docs/export-profiles/"><span>Profielen</span>Bevroren instellingen.</a><a href="/nl/docs/guides/platform-features/"><span>Status</span>Kwalificatie.</a></div>

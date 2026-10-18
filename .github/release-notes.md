**Download `doorman-v1.1.0.zip` below**, unzip it into your `resources` folder and add `ensure doorman` before the resources that use it. Also available for free as a Cfx.re asset on [the CedricPoint store](https://cedricpoint-developpement.tebex.io/).

### New
- **Update check.** At start, doorman asks GitHub for the latest release and prints one line in the console if a newer one is out. Nothing is downloaded or changed. Turn it off with `set doorman_version_check false`.
- **Readable as a Cfx.re asset.** `escrow_ignore` keeps every file open source when the resource is delivered through Cfx.re / Tebex.

### Unchanged
Same rules, same API, same 86 tests (plus 7 new ones for the version check). Upgrading from 1.0.0 is a drop-in replacement.

---

**Téléchargez `doorman-v1.1.0.zip` ci-dessous**, décompressez-le dans `resources` et ajoutez `ensure doorman` avant les ressources qui l'utilisent. Aussi disponible gratuitement en asset Cfx.re sur [la boutique CedricPoint](https://cedricpoint-developpement.tebex.io/).

- **Vérification des mises à jour** au démarrage (une ligne dans la console si une version plus récente existe ; `set doorman_version_check false` pour la couper).
- **Lisible en asset Cfx.re** : `escrow_ignore` garde tout le code ouvert.

# Tether Rally — Spécification de la monétisation

Nov 14, 2026 · @Guillaume

Tether Rally passe en free-to-play sur Google Play : des pubs récompensées que le joueur choisit, un achat « Retirer les pubs », les packs de peinture existants, et quelques pubs plein écran très espacées. Ce document dit quoi construire, où ça se branche dans le code actuel et dans quel ordre. Tous les chiffres sont des valeurs par défaut à ajuster (dernière section), pas des décisions arrêtées.

## Objectif et principes

- **On ne fait jamais payer un nouvel essai d'adresse.** Les essais de médaille en Time trial restent illimités, sans pub ni énergie. On fait payer les extras, les raccourcis et les cosmétiques.
- **Rien ne touche aux temps de course.** Pièces et achats n'achètent que des looks (règle déjà écrite dans `wallet.gd` et `cosmetics.gd`), donc records et classements restent justes.
- **La pub est un choix.** Chaque pub récompensée est un bouton que le joueur touche. Les pubs imposées sont rares, jamais pendant une course, jamais à la première session.
- **« Retirer les pubs » donne aussi les récompenses sans regarder.** Le payeur n'est jamais moins bien servi que celui qui regarde.
- **Tout passe par deux services** (`Store` et un nouveau `Ads`), avec un bouchon en debug et preview, pour que les menus ne connaissent jamais Play Billing ou AdMob directement.

## Ce qui existe déjà dans le code

L'économie est déjà là ; il manque la vraie facturation, les pubs et les limites du défi du jour.

| Brique | Fichier | État actuel | Ce qui change |
| --- | --- | --- | --- |
| Achats | `scripts/store.gd` | Bouchon : `chrome_pack` et `neon_pack` à 1,99 €, achat immédiat en debug/preview, « Soon » en release, propriété dans `user://store.cfg` | Backend Google Play Billing, nouveaux produits, restauration |
| Pièces | `scripts/wallet.gd` | Gagnées par médaille (`FIRST`/`REPEAT`), défi du jour et awards ; dépensées au Garage | Ajout des multiplicateurs de pub, packs de pièces plus tard |
| Cosmétiques | `scripts/cosmetics.gd`, `scripts/garage.gd` | Peintures, livrées, cordes ; `unlock` en pièces ou `product` ; bouton d'achat au Garage | Nouveaux produits branchés sur le même `unlock.product` |
| Défi du jour | `scripts/daily.gd`, bannière « DAILY DETOUR » dans `menu.gd` | Une piste + variante par jour, essais illimités, `BASE` 40 + 30 par palier, une amélioration paie la différence | Essais notés limités, entraînement libre, série |
| Écran de résultats | `main.gd` `_show_results()` et `_pay()`, `ui.gd` `show_results()` | Affiche les pièces gagnées en badges | Bouton « Doubler », déclencheur des interstitielles |
| Fantômes | `scripts/records.gd`, `main.gd` `_ghost_sample()` | Seulement le meilleur tour du joueur, en Time trial | Nouveau fantôme « médaille Gold » |
| Temps de médaille | `scripts/medals.gd`, `scripts/medal_times.gd`, `tools/gen_medals.gd` | Paliers Bronze, Silver, Gold, Pivot = temps de référence IA × 1,30 / 1,15 / 1,03 / 0,96 | Source des traces du fantôme Gold et de la ligne idéale |
| Export Android | `export_presets.cfg` | `gradle_build/use_gradle_build=false`, APK debug | Build Gradle obligatoire pour les plugins Billing et AdMob (déjà bloquant pour l'AAB) |

Ce qui n'existe pas encore : un service de pub, un classement en ligne (les records sont locaux), un compteur de sessions et un écran Boutique. Le « Reset progress » des Settings garde déjà les packs payés, il devra garder aussi « Retirer les pubs ».

## Architecture

Deux services statiques, sur le modèle de `store.gd`, et un fichier de réglages. Les menus n'appellent que ces interfaces.

| Fichier | Rôle | Interface |
| --- | --- | --- |
| `scripts/store.gd` (à étendre) | Achats. Backend Play Billing sur Android, bouchon actuel en debug/preview | `available()`, `buy(id, callback)`, `owns(id)`, `restore()`, `price(id)` (prix localisé lu chez Play), signal `changed` |
| `scripts/ads.gd` (nouveau) | Pubs. Backend AdMob sur Android, bouchon en debug/preview qui accorde la récompense après 1 s | `rewarded_ready(placement)`, `show_rewarded(placement, on_reward)`, `maybe_interstitial(trigger)`, `ads_removed()` |
| `scripts/monetization.gd` (nouveau) | Toutes les constantes ajustables (dernière section) et les compteurs du jour | constantes + `used_today(key)`, `use(key)` |

**Backends.** Google Play Billing via le plugin officiel Godot (`godot-sdk-integrations/godot-google-play-billing`) et AdMob via un plugin Godot 4 maintenu, à choisir après vérification de la compatibilité avec la version de Godot du projet. Les deux exigent `gradle_build/use_gradle_build=true`.

**Règles communes.**

- `buy()` et `show_rewarded()` deviennent asynchrones : l'appelant reçoit un callback, l'UI affiche un état « en cours » et ne bloque jamais la course.
- Un achat non consommable est acquitté (`acknowledge`) dès qu'il est accordé, sinon Play le rembourse au bout de 3 jours. Au lancement, `restore()` relit les achats chez Play, qui devient la source de vérité ; `user://store.cfg` n'est plus qu'un cache.
- Une récompense de pub n'est accordée que sur le callback « récompense gagnée » d'AdMob, pas à la fermeture de la pub. Pas de pub prête : le bouton est grisé avec « Pas de vidéo pour l'instant », jamais d'erreur.
- Si `Store.owns("remove_ads")`, `Ads` n'affiche plus rien et `show_rewarded()` accorde la récompense tout de suite ; le bouton perd son icône vidéo.
- Le bouchon reste le comportement des builds debug et preview (fonctionnalité `preview` déjà utilisée par `store.gd`), pour que tout soit testable sans compte Play. Un build store n'a jamais `self_update` (règle d'AGENTS.md).

## Pubs récompensées

Trois emplacements, tous ajoutés à une course sans jamais en racheter une. Aucun n'apparaît dans le tutoriel ni dans Off the Map (qui ne paie rien).

### 1. Doubler les pièces (`double_coins`)

- **Où :** écran de résultats, `main.gd` `_show_results()`. `_pay()` connaît déjà le total médaille + défi du jour ; il le renvoie en plus de la ligne de texte.
- **Quand :** seulement si ce total est supérieur à 0. Les pièces des awards (récupérées au Passport) ne sont pas doublées.
- **Effet :** un bouton « ×2 pièces » sous les badges. Après la pub, `Wallet.add(total)` une seconde fois, le badge passe à « +N×2 COINS » et le bouton disparaît. Une seule fois par écran de résultats.
- **Limite :** `DOUBLE_COINS_PER_DAY` (10 par défaut), pour garder l'économie des cosmétiques lisible.

### 2. Fantôme médaille Gold (`gold_ghost`)

- **Où (décidé par Guillaume le 14/11) :** sur l'écran de résultats (Retry / Again), après un essai raté, c'est-à-dire une course de Time trial finie sans l'Or sur une piste où le joueur n'a pas encore l'Or. Pas de bouton avant le départ : le Road Trip n'a plus de fiche avant la course (PR #96).
- **Effet :** débloque pour de bon, sur cette piste + variante, un deuxième fantôme qui boucle son tour exactement au temps Gold. Il roule à côté du fantôme du joueur, dans une autre couleur, avec l'option fantôme existante.
- **Nouveau contenu :** une trace par piste + variante Standard, Reverse et Obstacles (17 × 3 ; pas de Collect, où la médaille porte sur le score de toute la course, décidé le 14/11), générée par un outil voisin de `tools/gen_medals.gd`. Il fait rouler l'IA, enregistre son tour comme `race.gd` enregistre déjà un tour de Time trial (30 points par seconde), puis rééchelonne le temps pour finir au temps Gold. Fichiers dans `res://ghosts/gold/`, au format binaire de `records.gd`, à régénérer quand un tracé change (comme `medal_times.gd`).
- **Stockage :** les déblocages dans `wallet.cfg`, section `ghosts`. Ils repartent à zéro avec « Reset progress ».

### 3. Ligne idéale (`ideal_line`)

- **Où :** même fiche de piste avant un Time trial, et sur l'écran de résultats.
- **Effet :** pour la course suivante seulement, la trajectoire de la trace Gold est dessinée au sol en ruban discret, avec un repère aux endroits où l'IA accroche et lâche. Rien ne change dans la physique.
- **Nouveau contenu :** réutilise les traces du fantôme Gold ; il faut ajouter les instants d'accroche et de lâcher à l'enregistrement. Le rendu se fait dans `world_view.gd`.

**Pour tous :** avec « Retirer les pubs », les trois sont gratuits (le fantôme Gold est alors débloqué partout, la ligne idéale devient une option des Settings).

## Défi du jour (Daily Detour)

On limite la récompense, pas le jeu : 3 essais notés par jour, le meilleur compte, puis entraînement libre sans récompense.

**Essais notés**

- Seule une course lancée depuis la bannière « DAILY DETOUR » compte. Aujourd'hui, `main.gd` appelle `Daily.claim()` pour toute course de Time trial sur la piste du jour ; il faut un drapeau `daily_run` posé au lancement depuis la bannière. La même piste lancée depuis Time attack reste une course normale (médailles et pièces de médaille).
- Un essai est consommé à la fin du compte à rebours. Abandonner ou recommencer pendant la course le consomme aussi, sinon on pourrait rejouer sans fin.
- Le paiement actuel ne change pas : `BASE` + `PER_TIER` par palier au premier essai fini, puis la différence si un essai suivant fait mieux. C'est déjà « le meilleur compte ».
- Nouveaux éléments dans `daily.gd` : `attempts_left()`, `use_attempt()`, `best_today()`, stockés dans la section `daily` de `wallet.cfg` avec le jour (remise à zéro au changement de date, comme `paid_tier()`).
- La bannière affiche les essais restants (« 2 essais ») et le meilleur temps du jour.

**Entraînement libre**

- À 0 essai, la bannière lance la même piste en mode entraînement : chrono et fantôme normaux, ni pièces ni meilleur du jour, comme Off the Map. Le record de la piste et ses médailles restent possibles, car ils sont à la portée de n'importe quel Time trial.

**Essai bonus contre une pub (`daily_extra`)**

- À 0 essai, la bannière et l'écran de résultats proposent « +1 essai noté » contre une pub, au plus `DAILY_EXTRA_PER_DAY` fois (1 par défaut).

**Série (phase 3)**

- Un jour compte dans la série dès qu'un essai noté est fini. Bonus de pièces aux jours 3 et 7, puis tous les 7 jours (`STREAK_BONUS`).
- Un seul jour manqué peut être rattrapé : au lancement suivant, une carte propose « Sauver ma série » contre une pub (`streak_save`), au plus une fois par 7 jours. Sinon la série repart à 1.
- Le jour est celui de l'appareil (`Daily.today()`), sans serveur. Changer l'heure du téléphone permet de tricher sur les essais, ce qui est acceptable tant que rien n'est classé en ligne.

**Classement :** il n'y en a pas aujourd'hui (records locaux). Un classement du jour passe par Play Games Services, que l'audit de production recommande déjà ; à traiter après le soft launch, avec une vérification d'horloge côté serveur.

## Achats

Quatre produits au lancement et des packs de pièces plus tard, tous déclarés dans `Store.PRODUCTS` et créés avec le même identifiant dans la Play Console. Les prix affichés viennent de Play (devise locale) ; ceux du tableau sont des propositions.

| Id | Type Play | Prix proposé | Contenu | Phase |
| --- | --- | --- | --- | --- |
| `remove_ads` | non consommable | 3,49 € | Plus d'interstitielles, récompenses de pub sans regarder | 1 |
| `chrome_pack` | non consommable | 1,99 € | Existant : Chrome, Rose gold, Black chrome | 1 |
| `neon_pack` | non consommable | 1,99 € | Existant : trois peintures néon, livrée Neon trim, corde néon | 1 |
| `starter_pack` | non consommable | 4,99 € | `remove_ads` + `neon_pack` + 1000 pièces | 3 |
| `coins_s`, `coins_m` | consommables | 0,99 € / 2,99 € | 1500 / 5000 pièces | 3, si les données le justifient |

**Retirer les pubs**

- Vendu à trois endroits : une ligne dans les Settings, une petite carte dans le Garage, et le lien « Sans pub ? » affiché sous chaque bouton de pub récompensée.
- `Ads.ads_removed()` lit `Store.owns("remove_ads") or Store.owns("starter_pack")`.

**Packs de peinture**

- Rien à changer dans `cosmetics.gd` : `unlock.product` pointe déjà sur le bon id. `garage.gd` (lignes 196 à 225) passe à l'achat asynchrone et affiche le prix de Play au lieu du texte fixe « €1.99 ».
- `cosmetics.gd` doit accepter qu'un item soit débloqué par plusieurs produits (`neon_pack` ou `starter_pack`).

**Starter pack**

- Proposé une seule fois, en carte après l'écran de résultats de la 5e course finie (`STARTER_AFTER_RACES`), jamais par-dessus une animation de médaille ou d'award. Il reste ensuite visible dans le Garage.
- Masqué si le joueur possède déjà `remove_ads`. S'il possède déjà `neon_pack`, il voit le pack sans les néons, au même prix que `remove_ads` + 1000 pièces (deuxième produit Play `starter_pack_b`).

**Packs de pièces**

- Seulement si les pièces achètent des choses que les joueurs veulent : on regarde d'abord au soft launch combien de joueurs vident leur portefeuille au Garage. Consommables : `consume` après `Wallet.add()`.

**Restaurer :** un bouton « Restaurer mes achats » dans les Settings appelle `Store.restore()`. « Reset progress » ne touche à aucun achat.

## Pubs plein écran (interstitielles)

Une interstitielle au plus toutes les 4 courses finies, jamais à la première session, jamais pendant une course.

- **Déclencheur :** `Ads.maybe_interstitial("after_results")`, appelé quand le joueur quitte l'écran de résultats (Again, Next ou menu). Jamais à l'apparition des résultats, ni par-dessus une animation de médaille, de monde débloqué ou d'award (`_world_moment()`, `_award_moment()`).
- **Compteur :** courses finies depuis la dernière interstitielle, dans `wallet.cfg`. On affiche quand il atteint `INTERSTITIAL_EVERY` (4), puis on le remet à 0.
- **Première session :** un compteur de lancements de l'app (nouveau, dans `settings.cfg`). Aucune interstitielle tant qu'il vaut 1, ni avant `INTERSTITIAL_MIN_RACES` (6) courses au total.
- **Pas de doublon :** aucune interstitielle dans les `INTERSTITIAL_COOLDOWN_S` (120 s) qui suivent une pub récompensée ou une autre interstitielle.
- **Exclus :** tutoriel, Off the Map, entraînement du défi du jour, courses à 2 joueurs sur un téléphone.
- **Pause :** le jeu est déjà en résultats, donc rien à mettre en pause ; la musique (`music.gd`) baisse pendant la pub et revient après.

## Mesure, conformité Play et consentement

Les pubs changent la fiche Play : consentement RGPD, formulaire Data safety et politique de confidentialité sont à faire avant le premier test fermé avec pubs.

**Consentement**

- Formulaire Google UMP (fourni avec AdMob) au premier lancement en Europe, avant la première demande de pub. Un lien « Choix de confidentialité » dans les Settings le rouvre.
- Sans consentement, AdMob sert des pubs non personnalisées ; le jeu marche pareil.

**Fiche Play** (complète les points 10, 11 et 14 de `docs/production-readiness.md`)

- Data safety : déclarer l'identifiant publicitaire et les données collectées par AdMob, et les achats via Google Play.
- Permission `com.google.android.gms.permission.AD_ID` dans l'export Android.
- Public cible : déclarer 13 ans et plus, sinon le jeu entre dans les règles Famille (pubs certifiées seulement, plus de contraintes). La classification de contenu peut rester PEGI 3.
- Mention « Contient des pubs » et « Achats intégrés ».

**Mesure au soft launch**

- Phase 1 sans SDK d'analytics : la Play Console donne rétention et revenus d'achats, AdMob donne les vues de pub par utilisateur actif et par emplacement (un bloc d'annonces par emplacement).
- Chiffres à suivre : rétention J1 et J7, pubs récompensées vues par joueur actif par jour, part des joueurs qui achètent « Retirer les pubs », revenu par joueur actif par jour.
- Un SDK d'analytics (Firebase) seulement si ces chiffres ne suffisent pas pour décider ; il changerait encore le Data safety.

## Ordre de construction et critères d'acceptation

Trois phases, chacune livrée en petites PR avec leurs tests (règle d'AGENTS.md : chaque nouveau fichier de test a son étape dans `.github/workflows/sim.yml`).

1. **Phase 1 : ce qui rapporte 80 % (avant le soft launch)**
   1. `ads.gd`, `monetization.gd`, `store.gd` asynchrone, avec leurs bouchons. Test `tests/monetization_test.gd` : le bouchon accorde, `remove_ads` coupe les interstitielles et accorde sans pub.
   2. Pub « ×2 pièces » sur les résultats. Test : le portefeuille reçoit deux fois le total une seule fois par écran, la limite du jour tient, rien en tutoriel ni en Off the Map.
   3. Traces Gold générées pour les 17 pistes × 3 variantes (sans Collect) et fantôme Gold débloquable. Test : chaque trace finit son tour au temps Gold à 0,05 s près.
   4. Défi du jour : 3 essais notés, entraînement, essai bonus. Tests dans `tests/economy_test.gd` : un 4e essai ne paie rien, un abandon consomme un essai, Time attack sur la même piste ne consomme rien, remise à zéro au jour suivant.
   5. Interstitielles légères. Test : rien au premier lancement ni avant 6 courses, puis une toutes les 4, jamais après le tutoriel.
   6. Backends réels : build Gradle, plugin Billing, plugin AdMob, UMP, produits créés dans la Play Console, test sur un vrai téléphone avec les blocs de test AdMob et un compte testeur de licence.
2. **Phase 2 : soft launch** dans un ou deux petits pays, après le test fermé obligatoire (12 testeurs, 14 jours). Critère pour passer à la suite : rétention J1 et nombre de pubs récompensées par joueur et par jour lus sur deux semaines.
3. **Phase 3 : selon les chiffres** : starter pack, série et « Sauver ma série », ligne idéale, nouveaux cosmétiques, packs de pièces si le Garage se vide, classement du jour via Play Games.

La ligne idéale est en phase 3 parce qu'elle demande un rendu nouveau dans `world_view.gd` ; elle peut remonter en phase 1 si le fantôme Gold est fini en avance, car elle réutilise ses traces.

## Paramètres ajustables

Toutes ces valeurs vivent dans `scripts/monetization.gd` et sont des propositions à revoir après le soft launch.

| Constante | Défaut | Effet |
| --- | --- | --- |
| `DOUBLE_COINS_PER_DAY` | 10 | « ×2 pièces » par jour |
| `DAILY_ATTEMPTS` | 3 | Essais notés du défi du jour |
| `DAILY_EXTRA_PER_DAY` | 1 | Essais bonus contre une pub (2 au plus) |
| `STREAK_BONUS` | jour 3 : 50, jour 7 : 150, puis +150 tous les 7 jours | Pièces de série |
| `STREAK_SAVE_EVERY_DAYS` | 7 | Une sauvegarde de série par période |
| `INTERSTITIAL_EVERY` | 4 | Courses finies entre deux interstitielles (3 à 4) |
| `INTERSTITIAL_MIN_RACES` | 6 | Courses avant la première interstitielle |
| `INTERSTITIAL_COOLDOWN_S` | 120 | Secondes sans interstitielle après une pub |
| `STARTER_AFTER_RACES` | 5 | Course après laquelle le starter pack est proposé |
| Prix `remove_ads` | 3,49 € | Entre 2,99 € et 3,99 € |
| Prix `starter_pack` | 4,99 € | Moins cher que ses parties achetées séparément (5,48 € + pièces) |

**Questions ouvertes**

- Le fantôme Gold débloqué l'est-il pour toujours (proposé ici) ou pour une journée, ce qui ferait voir plus de pubs ?
- « Retirer les pubs » donne le ×2 pièces gratuit : à surveiller, car un acheteur gagne alors deux fois plus vite que les autres.

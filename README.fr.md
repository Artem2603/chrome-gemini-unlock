# Chrome Gemini Unlock

[![test](https://github.com/artem2603/chrome-gemini-unlock/actions/workflows/test.yml/badge.svg)](https://github.com/artem2603/chrome-gemini-unlock/actions/workflows/test.yml)

[English](README.md) · [Русский](README.ru.md) · **Français** · [Deutsch](README.de.md)

Un script Windows qui active dans Google Chrome le panneau latéral Gemini (nom interne « Glic »), et en option ses fonctions d'agent, lorsque Chrome les masque à cause de la langue du profil ou de la région.

> Projet non officiel, sans lien avec Google. Les flags sont expérimentaux : Google peut les renommer ou les supprimer dans n'importe quelle version de Chrome, et peut toujours restreindre l'accès selon le compte. Utilisation à vos risques.

## Ce que fait le script

0. Cherche Google Chrome : dans le registre, parmi les programmes en cours et dans les dossiers standard. Si Chrome n'est pas installé, ou n'a jamais été démarré sur ce compte Windows, le script s'arrête sans rien modifier.
1. Ferme Google Chrome. Si Chrome est en cours d'exécution, le script demande d'abord confirmation (`-Force` supprime cette question). Dans une session non interactive, où il ne peut pas poser la question, il s'arrête sans rien modifier et vous demande de le lancer avec `-Force`. Il demande ensuite à chaque fenêtre de se fermer, comme si vous les fermiez vous-même, puis met fin à ce qui tourne encore quelques secondes plus tard. Dans ce cas, Chrome peut proposer de restaurer les pages au prochain démarrage : cliquez sur **Restaurer** (Restore). Le texte saisi dans des formulaires non envoyés est perdu dans tous les cas.
2. Active 5 flags Glic dans le fichier `Local State` de Chrome, pour le panneau latéral, son bouton dans la barre d'outils et son entrée dans le menu contextuel :
   `glic`, `glic-toolbar-height-side-panel`, `glic-horizontal-tab-toolbar-button`, `glic-toolbar-button-location`, `glic-context-menu-below-search`.

   Les 6 flags d'agent ne sont activés qu'avec `-Agent` ; une exécution sans `-Agent` les remet sur Default :
   `glic-actor`, `enable-browser-actuator-for-glic-experimental-triggering`, `glic-background-actuation`, `glic-actor-autofill`, `glic-actor-cursor`, `glic-actor-script-tools`.

   Si la version de Chrome installée dépasse celle après laquelle expire un des flags activés, le script prévient que Chrome peut ignorer ce flag.
3. Passe l'interface de Chrome en anglais (en-US) et définit les langues de chaque profil sur `en-US,en`.
4. Fait utiliser par Chrome les États-Unis comme région pour ses expériences :
   - ajoute `--variations-override-country=us --lang=en-US` aux raccourcis de Chrome : bureau, menu Démarrer, barre des tâches et raccourcis communs à tous les utilisateurs (ceux-ci nécessitent des droits d'administrateur, Windows les demande via l'UAC). Un `--lang=` ou `--variations-override-country=` déjà présent dans un raccourci est remplacé ;
   - ajoute les mêmes arguments à l'entrée de démarrage automatique de Chrome, s'il y en a une ;
   - les ajoute au gestionnaire de liens, pour que Chrome ouvert par un lien depuis un autre programme les reçoive aussi ;
   - enregistre le pays dans `Local State` (`variations_permanent_overridden_country`).
5. Redémarre Chrome et vérifie qu'il fonctionne avec le changement de région. Lorsque le script s'exécute avec des droits d'administrateur, il ne démarre pas Chrome, car Chrome recevrait aussi ces droits : démarrez Chrome depuis un raccourci.

Avant toute modification, le script enregistre l'état d'origine dans `%LOCALAPPDATA%\chrome-gemini-unlock\backup` : les fichiers y sont copiés, les valeurs du registre sont notées dans `manifest.txt`. Les exécutions suivantes n'écrasent jamais cette sauvegarde. `-Restore` s'en sert pour annuler les modifications ; après une restauration complète, le dossier est renommé en `backup-restored-<date>`, et la prochaine exécution enregistre l'état tel qu'il sera alors.

## Prérequis

- Windows 10 ou 11 avec Windows PowerShell 5.1 (intégré). Lancé depuis PowerShell 7, le script redémarre de lui-même dans Windows PowerShell 5.1.
- Google Chrome, version stable, démarré au moins une fois sur votre compte Windows. Beta, Dev et Canary ne sont pas pris en charge.

## Utilisation

1. Téléchargez `chrome-gemini-unlock-vX.Y.Z.zip` depuis la [dernière version publiée](https://github.com/Artem2603/chrome-gemini-unlock/releases/latest) et extrayez l'archive. (**Code → Download ZIP** donne l'état de développement actuel.)
2. Double-cliquez sur `chrome-gemini-unlock.bat`.
3. Si Chrome est en cours d'exécution, le script demande s'il doit le fermer : tapez **O** et appuyez sur Entrée. Toute autre réponse annule sans rien modifier.
4. Si Windows demande des droits d'administrateur, confirmez. Ils ne servent qu'aux raccourcis communs ; si vous refusez, tout le reste fonctionne quand même.
5. Chrome redémarre. Le bouton Gemini devrait apparaître dans la barre d'outils.

Des options peuvent être ajoutées en lançant le script depuis une invite de commandes dans le dossier extrait, par exemple :

```bat
chrome-gemini-unlock.bat -NoAdmin
```

| Option | Effet |
|---|---|
| `-Country us` | Région pour les expériences, deux lettres. Par défaut : `us`. |
| `-Agent` | Activer aussi les fonctions d'agent (voir « À savoir »). Sans cette option, les flags d'agent sont remis sur Default. |
| `-Force` | Fermer Chrome sans demander. Nécessaire dans une session non interactive, où le script ne peut pas poser la question. |
| `-Restore` | Annuler les modifications à l'aide de la sauvegarde (voir « Annulation »). |
| `-NoAdmin` | Ne jamais demander de droits d'administrateur ; les raccourcis communs restent inchangés. |
| `-NoLaunch` | Ne pas démarrer Chrome à la fin. |

Relancer le script ne pose pas de problème : les raccourcis et gestionnaires de liens déjà configurés sont signalés comme « déjà configuré », une entrée de démarrage automatique qui contient déjà les arguments reste telle quelle, et la sauvegarde conserve l'état d'avant la première exécution. Chaque exécution ferme et redémarre tout de même Chrome, et réécrit les flags et les paramètres de langue.

**Vérifier le téléchargement.** Chaque version publiée a un fichier `.sha256` à côté de son ZIP. Dans PowerShell, dans le dossier contenant les deux fichiers, cette commande doit afficher `True` ; sinon, le ZIP n'est pas celui qui a été publié :

```powershell
(Get-FileHash .\chrome-gemini-unlock-v1.0.0.zip -Algorithm SHA256).Hash -eq (Get-Content .\chrome-gemini-unlock-v1.0.0.zip.sha256).Split(' ')[0]
```

Remplacez `v1.0.0` par la version téléchargée.

## À savoir

- **Démarrez Chrome depuis ses raccourcis.** Si un programme lance `chrome.exe` directement, ce Chrome démarre sans le paramètre de ligne de commande. Le pays enregistré dans `Local State` ne couvre alors qu'une partie des expériences.
- **Vérifier le changement :** ouvrez `chrome://version`. La ligne « Command Line » doit contenir `--variations-override-country=us`.
- **Démarrage automatique.** Chrome gère lui-même son entrée de démarrage automatique et peut la recréer sans le paramètre. Si Gemini disparaît après un redémarrage, désactivez « Continue running background apps when Google Chrome is closed » dans `chrome://settings/system`, ou relancez le script.
- **Les mises à jour de Chrome** peuvent recréer les raccourcis communs. Si Gemini disparaît après une mise à jour, relancez le script.
- **Ordinateur partagé.** Les raccourcis communs concernent tous les comptes Windows du PC. Pour ne modifier que vos propres raccourcis, lancez le script avec `-NoAdmin`. Le Chrome qui tourne dans les sessions Windows d'autres utilisateurs n'est jamais fermé ; un Chrome lancé avec « Exécuter en tant qu'autre utilisateur » sur votre propre bureau est fermé comme le vôtre.
- **Langues et synchronisation.** Les profils reçoivent les langues `en-US,en`, les sites web privilégieront donc l'anglais. Si la synchronisation de Chrome est activée, la liste des langues arrive aussi dans votre Chrome sur d'autres ordinateurs.
- **Gestionnaire de liens.** Le script place une copie personnelle de l'enregistrement des liens de Chrome dans `HKCU\Software\Classes` (`ChromeHTML`, `ChromePDF`). Si vous désinstallez Chrome, supprimez ces clés (voir « Annulation »).
- **Les fonctions d'agent** sont désactivées par défaut. Avec `-Agent`, Gemini peut cliquer, saisir du texte et remplir des formulaires à votre place dans votre navigateur, où vous êtes connecté à vos comptes. Une page web peut cacher dans son contenu des instructions destinées à l'IA (injection de prompt) et amener Gemini à agir contre vous. Ne les activez que si vous acceptez ce risque, et surveillez ce que fait Gemini.
- **Les flags expirent.** D'après les métadonnées des flags de Chromium, la plupart de ces flags doivent expirer après Chrome 160 ; `glic-actor` après Chrome 172, `enable-browser-actuator-for-glic-experimental-triggering` et `glic-actor-script-tools` après Chrome 170. Passé ce délai, Chrome ignore un flag, sauf si Google le prolonge. Le script prévient lorsque la version de Chrome installée dépasse celle après laquelle un flag expire. `glic-actor-cursor` avait déjà expiré dans Chrome 155 et n'a été prolongé jusqu'à 160 qu'à partir de Chrome 156 : avec Chrome 155, le script prévient. Chrome supprime le réglage d'un flag expiré à chaque démarrage ; pour le rétablir pour l'instant, activez `chrome://flags/#temporary-unexpire-flags-m154`, redémarrez Chrome, puis relancez le script.
- **Copie administrateur.** Pour les raccourcis communs, le script écrit une copie de lui-même dans le dossier de sauvegarde et l'exécute avec des droits d'administrateur. La copie est vérifiée par SHA-256 avant de s'exécuter : si un programme l'a modifiée pendant que la demande de Windows était affichée, elle ne s'exécute pas et les raccourcis communs restent inchangés. Avant chaque écriture dans le dossier de sauvegarde, le script vérifie qu'il n'y a ni jonction ni lien symbolique, et refuse d'écrire à travers.

## Annulation

Lancez ceci depuis une invite de commandes dans le dossier extrait :

```bat
chrome-gemini-unlock.bat -Restore
```

Comme lors d'une exécution normale, le script demande avant de fermer Chrome et redémarre Chrome à la fin. À l'aide de la sauvegarde, il ne rétablit que ce qu'il a modifié :

- les flags Glic (les autres flags restent tels quels) ;
- la langue de l'interface et les langues des profils que le script a modifiés ;
- le pays enregistré ;
- les arguments des raccourcis Chrome (l'icône, l'épinglage et le nom restent tels qu'ils sont maintenant) ;
- l'entrée de démarrage automatique, si Chrome l'a toujours ;
- le gestionnaire de liens : la copie personnelle est supprimée, ou la clé qui existait avant le script est réimportée ;
- les raccourcis Chrome qui ont reçu les arguments sans sauvegarde, par exemple un épinglage à la barre des tâches fait depuis un raccourci modifié, perdent ces deux arguments.

Tout ce que Chrome a enregistré d'autre depuis la première exécution, par exemple d'autres paramètres ou de nouveaux profils, est conservé. Les raccourcis communs nécessitent de nouveau des droits d'administrateur : confirmez la demande de Windows, sinon ils restent inchangés ; le script indique alors que la restauration n'est pas complète, garde la sauvegarde, et vous pouvez relancer `-Restore`. Après une restauration complète, le dossier de sauvegarde est renommé en `backup-restored-<date>` : un `-Restore` ultérieur ne revient pas à l'état d'avant la toute première exécution.

**Annulation manuelle** (si le script ne peut pas s'exécuter) :

1. Dans Chrome : `chrome://flags` → **Reset all** (ou remettez les flags `glic` et `enable-browser-actuator-for-glic-experimental-triggering` sur Default un par un), puis choisissez vos langues et la langue d'affichage dans `chrome://settings/languages`.
2. Retirez `--variations-override-country=us --lang=en-US` du champ « Cible » dans les propriétés de chaque raccourci Chrome. Si un raccourci avait son propre `--lang=` avant, remettez-le ; le raccourci d'origine se trouve dans la sauvegarde (`shortcuts\<code>\<nom>.lnk`).
3. Ouvrez `%LOCALAPPDATA%\chrome-gemini-unlock\backup\manifest.txt` et supprimez les clés de registre qu'il indique comme `created` :
   ```bat
   reg delete "HKCU\Software\Classes\ChromeHTML" /f
   reg delete "HKCU\Software\Classes\ChromePDF" /f
   ```
   Si la sauvegarde contient `registry\handler-*.reg`, double-cliquez dessus à la place : il restaure une clé qui existait avant le script.
4. Si le manifeste contient une ligne `...\Run  GoogleChromeAutoLaunch_<code> = ...`, supprimez cette valeur de démarrage automatique ; Chrome la recrée lui-même quand il en a besoin :
   ```bat
   reg delete "HKCU\Software\Microsoft\Windows\CurrentVersion\Run" /v GoogleChromeAutoLaunch_<code> /f
   ```
5. Fermez complètement Chrome : fermez toutes les fenêtres puis, si une icône Chrome se trouve dans la zone de notification, faites un clic droit dessus et choisissez **Exit** (Quitter). Vérifiez dans le Gestionnaire des tâches (onglet Détails) qu'il ne reste aucun `chrome.exe`, sinon Chrome réécrit ses paramètres par-dessus la modification. Supprimez ensuite le pays enregistré de `Local State` avec PowerShell :
   ```powershell
   $f = "$env:LOCALAPPDATA\Google\Chrome\User Data\Local State"
   [IO.File]::WriteAllText($f, ([IO.File]::ReadAllText($f) -replace ',"variations_permanent_overridden_country":"[a-z]*"', ''))
   ```

## Fichiers

| Fichier | Rôle |
|---|---|
| `chrome-gemini-unlock.bat` | Lanceur par double-clic : exécute le script PowerShell et lui transmet les options. |
| `chrome-gemini-unlock.ps1` | Le script. Messages en anglais, russe, français et allemand, choisis selon la langue de Windows. |
| `tests/` | Tests unitaires, vérification des flags dans un vrai Chrome et test de bout en bout sous Windows. |
| `.github/workflows/test.yml` | Exécute les tests sur GitHub Actions. |
| `.github/workflows/release.yml` | Pour un tag comme `v1.2.3`, ou lancé à la main (Actions → Release → Run workflow, version `v1.2.3`), exécute tous les tests et, s'ils réussissent, publie la version. |
| `tools/build-release.sh` | Construit une version : le ZIP, son SHA-256 et les notes de version. |
| `CHANGELOG.md` | Ce qui a changé dans chaque version. |

Testé sous Windows 11 avec Chrome 154. `tests/chrome-flags.ps1` démarre un vrai Chrome et vérifie qu'il applique chaque flag, sauf ceux que la table d'expiration du script indique comme expirés dans cette version (avec Chrome 155 : tous sauf `glic-actor-cursor`).

## Licence

[MIT](LICENSE)

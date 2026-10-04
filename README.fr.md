# Chrome Gemini Unlock

[English](README.md) · [Русский](README.ru.md) · **Français** · [Deutsch](README.de.md)

Un script Windows qui active dans Google Chrome le panneau latéral Gemini (nom interne « Glic ») et ses fonctions d'agent, lorsque Chrome les masque à cause de la langue du profil ou de la région.

> Projet non officiel, sans lien avec Google. Les flags sont expérimentaux : Google peut les renommer ou les supprimer dans n'importe quelle version de Chrome, et peut toujours restreindre l'accès selon le compte. Utilisation à vos risques.

## Ce que fait le script

0. Cherche Google Chrome : dans le registre, parmi les programmes en cours et dans les dossiers standard. Si Chrome n'est pas installé, ou n'a jamais été démarré sur ce compte Windows, le script s'arrête sans rien modifier.
1. Ferme Google Chrome. Il demande d'abord à chaque fenêtre de se fermer, comme si vous les fermiez vous-même, puis met fin à ce qui tourne encore quelques secondes plus tard. Dans ce cas, Chrome peut proposer de restaurer les pages au prochain démarrage : cliquez sur **Restaurer** (Restore). Le texte saisi dans des formulaires non envoyés est perdu dans tous les cas.
2. Active 11 flags Glic dans le fichier `Local State` de Chrome :
   `glic`, `glic-actor`, `enable-browser-actuator-for-glic-experimental-triggering`, `glic-background-actuation`, `glic-actor-autofill`, `glic-actor-cursor`, `glic-actor-script-tools`, `glic-toolbar-height-side-panel`, `glic-horizontal-tab-toolbar-button`, `glic-toolbar-button-location`, `glic-context-menu-below-search`.
3. Passe l'interface de Chrome en anglais (en-US) et définit les langues de chaque profil sur `en-US,en`.
4. Fait utiliser par Chrome les États-Unis comme région pour ses expériences :
   - ajoute `--variations-override-country=us --lang=en-US` aux raccourcis de Chrome : bureau, menu Démarrer, barre des tâches et raccourcis communs à tous les utilisateurs (ceux-ci nécessitent des droits d'administrateur, Windows les demande via l'UAC). Un `--lang=` ou `--variations-override-country=` déjà présent dans un raccourci est remplacé ;
   - ajoute les mêmes arguments à l'entrée de démarrage automatique de Chrome, s'il y en a une ;
   - les ajoute au gestionnaire de liens, pour que Chrome ouvert par un lien depuis un autre programme les reçoive aussi ;
   - enregistre le pays dans `Local State` (`variations_permanent_overridden_country`).
5. Redémarre Chrome et vérifie qu'il fonctionne avec le changement de région.

Avant toute modification, le script enregistre l'état d'origine dans `%LOCALAPPDATA%\chrome-gemini-unlock\backup` : les fichiers y sont copiés, les valeurs du registre sont notées dans `manifest.txt`. Les exécutions suivantes n'écrasent jamais cette sauvegarde.

## Prérequis

- Windows 10 ou 11 avec Windows PowerShell 5.1 (intégré).
- Google Chrome, version stable, démarré au moins une fois sur votre compte Windows. Beta, Dev et Canary ne sont pas pris en charge.

## Utilisation

1. Téléchargez le dépôt : **Code → Download ZIP**, puis extrayez l'archive.
2. Double-cliquez sur `chrome-gemini-unlock.bat`.
3. Si Windows demande des droits d'administrateur, confirmez. Ils ne servent qu'aux raccourcis communs ; si vous refusez, tout le reste fonctionne quand même.
4. Chrome redémarre. Le bouton Gemini devrait apparaître dans la barre d'outils.

Des options peuvent être ajoutées en lançant le script depuis une invite de commandes dans le dossier extrait, par exemple :

```bat
chrome-gemini-unlock.bat -NoAdmin
```

| Option | Effet |
|---|---|
| `-Country us` | Région pour les expériences, deux lettres. Par défaut : `us`. |
| `-NoAdmin` | Ne jamais demander de droits d'administrateur ; les raccourcis communs restent inchangés. |
| `-NoLaunch` | Ne pas démarrer Chrome à la fin. |

Relancer le script ne pose pas de problème : les étapes déjà faites sont signalées comme « déjà configuré », et la sauvegarde conserve l'état d'avant la première exécution.

## À savoir

- **Démarrez Chrome depuis ses raccourcis.** Si un programme lance `chrome.exe` directement, ce Chrome démarre sans le paramètre de ligne de commande. Le pays enregistré dans `Local State` ne couvre alors qu'une partie des expériences.
- **Vérifier le changement :** ouvrez `chrome://version`. La ligne « Command Line » doit contenir `--variations-override-country=us`.
- **Démarrage automatique.** Chrome gère lui-même son entrée de démarrage automatique et peut la recréer sans le paramètre. Si Gemini disparaît après un redémarrage, désactivez « Continue running background apps when Google Chrome is closed » dans `chrome://settings/system`, ou relancez le script.
- **Les mises à jour de Chrome** peuvent recréer les raccourcis communs. Si Gemini disparaît après une mise à jour, relancez le script.
- **Ordinateur partagé.** Les raccourcis communs concernent tous les comptes Windows du PC. Pour ne modifier que vos propres raccourcis, lancez le script avec `-NoAdmin`. Le Chrome qui tourne dans les sessions Windows d'autres utilisateurs n'est jamais fermé ; un Chrome lancé avec « Exécuter en tant qu'autre utilisateur » sur votre propre bureau est fermé comme le vôtre.
- **Langues et synchronisation.** Les profils reçoivent les langues `en-US,en`, les sites web privilégieront donc l'anglais. Si la synchronisation de Chrome est activée, la liste des langues arrive aussi dans votre Chrome sur d'autres ordinateurs.
- **Gestionnaire de liens.** Le script place une copie personnelle de l'enregistrement des liens de Chrome dans `HKCU\Software\Classes` (`ChromeHTML`, `ChromePDF`). Si vous désinstallez Chrome, supprimez ces clés (voir « Annulation »).
- **Fonctions d'agent.** Les flags `glic-actor*` activent le mode dans lequel Gemini peut agir sur les pages web à votre place. Surveillez ce qu'il fait.

## Annulation

**Annulation complète**, retour à l'état d'avant la première exécution :

1. Fermez complètement Chrome : fermez toutes les fenêtres puis, si une icône Chrome se trouve dans la zone de notification, faites un clic droit dessus et choisissez **Exit** (Quitter). Vérifiez dans le Gestionnaire des tâches (onglet Détails) qu'il ne reste aucun `chrome.exe`, sinon Chrome réécrit ses paramètres par-dessus les fichiers restaurés.
2. Ouvrez `%LOCALAPPDATA%\chrome-gemini-unlock\backup`. Chaque ligne de `manifest.txt` se lit `fichier de sauvegarde  ->  emplacement d'origine`.
3. Recopiez chaque fichier de sauvegarde à son emplacement d'origine en remplaçant le fichier présent : `Local State`, `profiles\<profil>\Preferences`, `shortcuts\<code>\<nom>.lnk`. Les raccourcis communs (`C:\Users\Public\Desktop`, `C:\ProgramData\...`) nécessitent des droits d'administrateur.
4. Supprimez les clés de registre que le manifeste indique comme `created` :
   ```bat
   reg delete "HKCU\Software\Classes\ChromeHTML" /f
   reg delete "HKCU\Software\Classes\ChromePDF" /f
   ```
   Si la sauvegarde contient `registry\handler-*.reg`, double-cliquez dessus à la place : il restaure une clé qui existait avant le script.
5. Si le manifeste contient une ligne `...\Run  GoogleChromeAutoLaunch_<code> = ...`, supprimez cette valeur de démarrage automatique ; Chrome la recrée lui-même quand il en a besoin :
   ```bat
   reg delete "HKCU\Software\Microsoft\Windows\CurrentVersion\Run" /v GoogleChromeAutoLaunch_<code> /f
   ```

Recopier les anciens fichiers annule aussi tout ce que Chrome a enregistré après le script, par exemple de nouveaux paramètres ou de nouveaux profils.

**Annulation partielle**, sans recopier de fichiers :

1. Dans Chrome : `chrome://flags` → **Reset all** (ou remettez les flags `glic` sur Default un par un), puis choisissez vos langues et la langue d'affichage dans `chrome://settings/languages`.
2. Retirez `--variations-override-country=us --lang=en-US` du champ « Cible » dans les propriétés de chaque raccourci Chrome. Si un raccourci avait son propre `--lang=` avant, remettez-le ; le raccourci d'origine se trouve dans la sauvegarde.
3. Faites les étapes 4 et 5 de l'annulation complète.
4. Fermez complètement Chrome (comme à l'étape 1 de l'annulation complète) et supprimez le pays enregistré de `Local State` avec PowerShell :
   ```powershell
   $f = "$env:LOCALAPPDATA\Google\Chrome\User Data\Local State"
   [IO.File]::WriteAllText($f, ([IO.File]::ReadAllText($f) -replace ',"variations_permanent_overridden_country":"[a-z]*"', ''))
   ```

## Fichiers

| Fichier | Rôle |
|---|---|
| `chrome-gemini-unlock.bat` | Lanceur par double-clic : exécute le script PowerShell et lui transmet les options. |
| `chrome-gemini-unlock.ps1` | Le script. Messages en anglais, russe, français et allemand, choisis selon la langue de Windows. |

Testé sous Windows 11 avec Chrome 154.

## Licence

[MIT](LICENSE)

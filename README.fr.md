# doorman

[English](README.md) · **Français**

Un net event sur un serveur FiveM, c'est une API publique sans
authentification, sans limite de débit et sans types. N'importe quel client
connecté peut déclencher n'importe quel événement enregistré, aussi souvent
qu'il veut, avec n'importe quels arguments.

La plupart du code serveur est écrit comme si ce n'était pas vrai :

```lua
RegisterNetEvent('shop:buy')
AddEventHandler('shop:buy', function(data)
    local cost = prices[data.item] * data.count
    money[source] = money[source] - cost
end)
```

Quatre suppositions, aucune vérifiée. `{item = 'bread', count = -1000}` et
c'est la boutique qui paie le joueur. `{count = 0/0}` et le solde devient
NaN — à partir de là toute comparaison avec lui est fausse, y compris celle
censée l'empêcher d'acheter.

**doorman** met la règle devant le handler :

```lua
doorman.on('shop:buy', {
    rate     = '5/10s',
    cooldown = '500ms',
    schema   = {
        item  = { 'string', oneof = { 'bread', 'milk', 'eggs' } },
        count = { 'number', min = 1, max = 10, integer = true },
    },
}, function(source, data)
    -- ne tourne que pour un appel qui est passé
end)
```

Standalone. Aucun framework, aucune dépendance, aucune base de données.
**86 tests.**

## Installation

1. Téléchargez, posez `doorman` dans vos ressources, `ensure doorman` avant
   tout ce qui s'en sert.
2. Dans la ressource à protéger, une ligne dans `fxmanifest.lua` :

```lua
server_script '@doorman/import.lua'
```

Vous avez le global `doorman` dans cette ressource. Utilisez
`doorman.on(...)` à la place de `RegisterNetEvent` + `AddEventHandler`.

## Ce qu'une règle peut dire

| | |
|---|---|
| `rate = '5/10s'` | au plus 5 appels par tranche de 10 s, par joueur, pour cet événement. Aussi `'30/min'`, `'3/s'`, `{5, 10}` |
| `cooldown = '2s'` | et au moins 2 secondes entre deux. Aussi `'500ms'`, `'1m'` |
| `schema = {…}` | à quoi le contenu doit ressembler |
| `exempt = fn` | `function(source) → booléen`, vérifié en premier : un admin ne consomme pas un quota auquel il n'est pas soumis |

Tous les champs sont facultatifs. Une règle qui n'a qu'un `schema` valide
sans limiter ; une règle qui n'a qu'un `rate` limite et accepte n'importe
quel contenu.

### Les schémas

```lua
schema = {
    item   = 'string',                                        -- obligatoire
    note   = 'string?',                                       -- facultatif
    count  = { 'number', min = 1, max = 99, integer = true },
    id     = { 'string', max = 32, pattern = '^[%w_]+$' },
    side   = { 'string', oneof = { 'left', 'right' } },
    coords = { 'table', of = 'number', max = 3 },
    player = { 'table', fields = { id = 'number', name = 'string' } },
}
```

Les types sont `string`, `number`, `boolean`, `table` et `any` ; un `?` à la
fin rend le champ facultatif.

Quatre choses sont refusées que vous l'ayez demandé ou non, parce que ce
sont celles qu'on oublie facilement et qu'on paie cher :

- **NaN et l'infini.** `0/0` est un nombre pour `type()`, et il est faux
  face à n'importe quelle borne que vous pourriez écrire : `min` et `max` ne
  l'arrêteront pas. Tout ce qu'il touche devient NaN à son tour.
- **Les chaînes de plus de 512 octets.** Un client envoie un mégaoctet aussi
  facilement qu'un mot.
- **Les tables de plus de 8 niveaux ou de plus de 64 entrées** — y compris
  dans un `any` et dans un `table` nu, qui sont sinon les deux endroits par
  où une table imbriquée passe sans être regardée.
- **Les champs que vous n'avez pas déclarés.** Un handler qui parcourt le
  contenu avec `pairs()` agira volontiers sur une clé à laquelle vous n'avez
  jamais pensé. Mettez `strict = false` si vous voulez les tolérer.

Une faute dans une règle — `'nubmer'`, `rate = 'quickly'` — empêche la
ressource de démarrer, au lieu d'attendre qu'un joueur tombe dessus à 2 h du
matin.

### Quand quelqu'un n'arrête pas

Chaque ressource garde ses propres quotas : c'est le chemin chaud, il doit
rester là où est l'événement. Ce qu'elle ne garde pas, c'est le verdict :
*ce joueur s'est fait refuser trente appels en une minute* est un jugement
sur le joueur, il doit être rendu une seule fois, par quelque chose qui voit
toutes les ressources en même temps. C'est la ressource `doorman`.

```cfg
set doorman_warn   3     # journalise fort dès le 3ᵉ refus dans la fenêtre
set doorman_kick  10     # éjecte au 10ᵉ ; 0 pour n'éjecter personne
set doorman_window 60    # la fenêtre, en secondes
set doorman_kick_message "..."
```

Le compte n'est volontairement pas tenu par événement : quelqu'un de
prudent s'étale sur dix événements et reste sous chaque limite
individuelle.

`doorman` dans la console serveur affiche ce qui a été refusé et par quelle
ressource ; `doorman.lines()` donne à une ressource ses propres chiffres.

## C'est testé, et la forme du projet est faite pour ça

Tout ce qui décide quelque chose est dans `lib/`, prend une horloge en
argument et ne connaît rien au jeu. Tout ce qui touche une native est dans
`server/` et prend les natives en argument. Du coup la suite de tests fait
tourner les vrais fichiers, sous un simple binaire `lua`, sans serveur et
sans bibliothèque de mocks :

```bash
lua test/run.lua
```

86 tests, zéro dépendance. Ils couvrent ce qui est difficile à remarquer et
gênant à livrer :

- un limiteur à fenêtre fixe laisse passer le double à la jointure ; celui-ci
  est à fenêtre glissante, et un test envoie tout le quota à 9,9 s puis
  encore une fois à 10,1 s
- un compteur d'infractions est une liste qu'un attaquant peut allonger :
  elle sature, et un test la frappe dix mille fois pour vérifier qu'il reste
  quatre horodatages
- un joueur qui part doit être oublié, sinon un serveur qui a vu dix mille
  joueurs garde dix mille listes — et un client qui plante ne déclenche
  jamais `playerDropped`, d'où le balayage, et son test
- `source` est un global FiveM que l'événement suivant écrase ; le seul
  endroit où il est lu, c'est avant que quoi que ce soit puisse rendre la main

La suite a trouvé deux vrais bugs pendant qu'on l'écrivait. L'un est épinglé
par [un test qui porte son nom](spec/policy_spec.lua) : `opts.kick or 10` se
lit très bien, et transforme `kick = false` — *n'éjecter personne* — en
*éjecter au dixième*.

## Ce que ça ne fait pas

- **Ce n'est pas un anticheat.** Ça fait en sorte qu'un événement se
  comporte comme la règle le dit. Ça ne sait rien de ce que fait un joueur
  dans le monde, et une triche qui reste dans les clous lui est invisible.
- **Ça n'autorise pas.** `exempt`, c'est à vous de l'écrire : doorman ne
  sait pas qui sont vos admins.
- **Ça ne peut pas « dé-recevoir » un contenu.** FiveM l'a déjà
  désérialisé avant qu'un handler tourne. Les limites ici l'empêchent
  d'atteindre votre code, pas le réseau.
- **Les événements client ne le regardent pas.** Tout est côté serveur, le
  seul côté qui vaille la peine d'être vérifié.

## Contribuer

Voir [CONTRIBUTING.md](CONTRIBUTING.md). Un rapport de bug avec
l'événement, la règle et le contenu qui est passé, c'est ce qui aide le
plus.

MIT.

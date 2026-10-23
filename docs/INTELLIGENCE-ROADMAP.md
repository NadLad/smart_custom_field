# Roadmap « Smart Custom Field intelligent »

> Document de travail. Objectif : faire évoluer le plugin au-delà de la parité
> avec `computed_custom_field` **sans jamais réinterpréter les données
> existantes**.

## 1. Contrat de compatibilité (non négociable)

Les données du plugin d'origine tiennent en quatre points. Tout ce qui suit
part de là :

| Élément | Où | Invariant |
|---|---|---|
| Le code de la formule | `custom_fields.formula` (text) | même colonne, même contenu |
| Le flag | `custom_fields.is_computed` (boolean) | même colonne, immuable après création |
| La valeur calculée | `custom_values.value` (text) | même sérialisation par `field_format` |
| La syntaxe | `cfs[<id>]`, `self` = objet personnalisé | sur-ensemble strict |

**Règle d'or :** une formule existante doit produire **exactement la même
chaîne** dans `custom_values.value` après bascule. Si une évolution ne peut pas
le garantir, elle est derrière un flag, désactivée par défaut.

### Ce qu'il ne faut pas faire

- Changer le type ou le nom de `formula` / `is_computed`.
- Renommer `cfs` ou changer sa sémantique (`cfs` = valeurs locales, castées).
- Déplacer les valeurs calculées dans une table dédiée.
- Rendre `is_computed` modifiable après création : cela réinterpréterait
  silencieusement des valeurs déjà stockées.
- Activer par défaut une évolution qui change le résultat d'une formule
  existante (cf. §2.1, seul cas où c'est assumé et documenté).

---

## 2. Palier 1 — Gains immédiats (effort S/M, risque faible)

### 2.1 Ordonnancement topologique des champs chaînés
**Valeur.** Aujourd'hui une formule qui référence un autre champ calculé lit la
valeur du **save précédent** (limitation documentée dans `README.md`). Avec un
tri topologique, elle lit la valeur fraîchement calculée, dans le même save.
**Compat.** Aucune donnée déplacée, même colonne. Le résultat change uniquement
pour les formules chaînées — c'est un correctif, mais il doit être annoncé.
**Effort.** M. `lib/smart_custom_field/patches/customizable_patch.rb`
(`compute_computed_custom_fields` trie aujourd'hui implicitement par position) +
`Evaluator.custom_field_ids` comme source du graphe.
**Risque.** Une installation qui compense le décalage verrait ses valeurs
bouger au premier save. Mitigation : flag `topological_order` (défaut activé),
et `rake smart_custom_field:dry_run` qui montre les valeurs qui changeraient.

### 2.2 Détection de cycle à la sauvegarde du champ
**Valeur.** `A -> B -> A` boucle à l'infini ou produit du bruit. Aujourd'hui
rien ne l'empêche.
**Compat.** Aucune. Refuse seulement les nouvelles formules cycliques.
**Effort.** S. `lib/smart_custom_field/formula_validator.rb` : le graphe est
déjà extractible via `Evaluator.custom_field_ids`.
**Risque.** Une installation avec un cycle existant verrait son champ refusé
au prochain enregistrement. Mitigation : erreur seulement sur les nouveaux
cycles, avertissement sur les anciens.

### 2.3 Prévisualisation de formule dans l'admin
**Valeur.** Champ « tester sur » : on choisit un ticket/projet réel et on voit
le résultat, plus les entrées utilisées. C'est le chaînon manquant entre
« écrire du Ruby à l'aveugle » et « sauver puis aller voir ».
**Compat.** Lecture seule, zéro écriture.
**Effort.** M. Nouveau contrôleur
`app/controllers/smart_custom_field_previews_controller.rb`, route dans
`config/routes.rb`, bouton dans
`app/views/hooks/smart_custom_field/_view_custom_fields_form_upper_box.html.erb`,
appel à `Evaluator.evaluate` existant.
**Risque.** Exécute une formule non encore validée : réservé aux admins (même
niveau de confiance que la création de champ), et jamais persisté.

### 2.4 Validation statique de la formule (AST)
**Valeur.** Aujourd'hui `formula_validator.rb` évalue sur une instance vierge et
**avale** les `NoMethodError` sur `nil` — donc une faute de frappe sur un
attribut (`estimted_hours`) passe si l'objet est vide. Une analyse de l'AST
(`Ripper` / `RubyVM::AbstractSyntaxTree`) attrape les méthodes inconnues sans
exécuter.
**Compat.** Aucune : c'est de la validation, pas de l'évaluation.
**Effort.** M. `lib/smart_custom_field/formula_validator.rb` + un module
`lib/smart_custom_field/static_analyzer.rb`.
**Risque.** Faux positifs sur les méthodes dynamiques (`method_missing`).
Mitigation : liste blanche + avertissement plutôt que blocage.

### 2.5 Export / import JSON des formules
**Valeur.** Versionner les formules dans git, les diffuser entre environnements
(dev → prod), les relire en revue de code. Aujourd'hui elles vivent uniquement
en base.
**Compat.** Lecture pure ; l'import ne touche que `formula` / `is_computed`.
**Effort.** S. Deux tâches rake (`smart_custom_field:export`,
`smart_custom_field:import`) dans `lib/tasks/smart_custom_field.rake`.
**Risque.** Un import écraserait une formule modifiée en prod. Mitigation :
`--dry-run` par défaut, diff affiché avant écriture.

### 2.6 Read-only uniforme sur tous les modèles
**Valeur.** Aujourd'hui seuls les tickets sont protégés
(`lib/smart_custom_field/patches/issue_patch.rb`). Sur projet / utilisateur /
temps, la valeur saisie est écrasée au save — correct, mais l'utilisateur voit
un champ éditable qui ne sert à rien.
**Compat.** Aucune donnée modifiée : uniquement l'affichage et le
mass-assignment.
**Effort.** S. Généraliser `read_only_attribute_names` en un patch commun
appliqué aux huit modèles de `Patches::CUSTOMIZABLE_MODELS`.
**Risque.** Une API qui poste explicitement la valeur verrait son attribut
filtré. C'est le comportement voulu, mais à documenter dans `CHANGELOG.md`.

### 2.7 Backfill des valeurs existantes
**Valeur.** À l'installation, les champs calculés n'ont aucune valeur tant que
l'objet n'a pas été resauvé. Une tâche `smart_custom_field:recompute_all`
(par lots, avec progression et `--dry-run`) remplit l'existant.
**Compat.** Écrit uniquement `custom_values.value`, avec le même cast.
**Effort.** S/M. `lib/tasks/smart_custom_field.rake`, réutilise
`CustomizablePatch#compute_computed_custom_fields` en mode batch.
**Risque.** Volume. Mitigation : `find_each`, taille de lot configurable.

---

## 3. Palier 2 — Là où ça devient réellement « intelligent »

### 3.1 Helpers inter-objets
**Valeur.** `cfs` ne voit que l'objet courant. Des helpers permettent de
calculer un champ de ticket depuis son projet, son parent ou son assigné :
`cf(project, 12)`, `parent&.cfs[5]`, `assigned_to.cfs[3]`.
**Compat.** **Sur-ensemble strict** : les formules existantes ne connaissent pas
ces helpers et ne changent pas. Aucun impact sur les données.
**Effort.** M. Nouveau module `lib/smart_custom_field/formula_helpers.rb`
injecté dans le binding par `Evaluator.evaluate`.
**Risque.** N+1 requêtes. Mitigation : préchargement des associations connues
dans `customizable_patch.rb` + cache par save.

### 3.2 Agrégations
**Valeur.** `children.sum { |i| i.cfs[7].to_i }`, total d'un sous-arbre, somme
des temps d'un projet. C'est la demande métier la plus fréquente sur ce type de
plugin.
**Compat.** Additif (nouveaux helpers), dépend de 3.1.
**Effort.** L. `formula_helpers.rb` + garde-fous (profondeur max, nombre max
d'enfants, timeout).
**Risque.** Coût sur de gros arbres. Mitigation : plafond configurable, résultat
`nil` + avertissement au-delà.

### 3.3 Recalcul piloté par les dépendances
**Valeur.** Si un champ projet change, les tickets qui en dépendent gardent une
valeur périmée jusqu'à leur prochain save. Un index de dépendances permet de
recalculer les objets concernés.
**Compat.** Nouvelle table (`smart_custom_field_dependencies`), purement
additive : aucune donnée existante n'est déplacée.
**Effort.** L. Migration + hook `after_save` sur les champs référencés + tâche
de recalcul par lots.
**Risque.** Effets de bord en cascade, charge en écriture. Mitigation :
désactivé par défaut, recalcul asynchrone si un job runner est présent.

### 3.4 Skip si les entrées n'ont pas changé
**Valeur.** Sur un import de 10 000 tickets, on recalcule même quand aucune
entrée n'a bougé. Comparer un digest des entrées référencées (via
`Evaluator.custom_field_ids`) évite l'évaluation et l'écriture.
**Compat.** Aucune : si le digest est identique, la valeur produite serait
identique. Attention à invalider le digest quand la formule elle-même change.
**Effort.** S/M. `customizable_patch.rb`.
**Risque.** Digest périmé = valeur figée à tort. Mitigation : inclure un hash de
la formule dans le digest.

### 3.5 Mode « expliquer »
**Valeur.** Sur un objet donné, afficher la formule, les entrées utilisées
(nom, valeur castée) et le résultat. Transforme « pourquoi 42 ? » en réponse
immédiate.
**Compat.** Lecture seule.
**Effort.** S. Réutilise 2.3.
**Risque.** Expose des valeurs à des non-admins. Mitigation : permission
dédiée ou admin only.

---

## 4. Palier 3 — Plus tard, si le besoin se confirme

### 4.1 Interpréteur sandboxé avec repli sur `eval`
**Valeur.** Ferme la limitation n°1 du `README.md` : aujourd'hui une formule est
du Ruby arbitraire exécuté dans le contexte de l'objet.
**Compat.** **Le point critique** : on ne remplace pas `eval`, on l'encadre. Le
sandbox tente d'abord ; s'il ne sait pas évaluer la formule, on retombe sur
`eval` avec un avertissement dans l'admin. Les formules existantes continuent
donc de fonctionner à l'identique.
**Effort.** L. `lib/smart_custom_field/evaluator.rb` est déjà le point unique
d'évaluation — c'est précisément pour ça qu'il a été isolé.
**Risque.** Divergence de résultat entre sandbox et `eval`. Mitigation : suite
de tests de parité qui évalue chaque formule des deux façons et compare.

### 4.2 Constructeur d'expression (UI)
**Valeur.** Remplacer la textarea Ruby par un assemblage de conditions, pour les
admins non développeurs.
**Compat.** Génère du Ruby, donc les mêmes `formula`. Une formule écrite à la
main reste éditable en mode texte.
**Effort.** L. Vue de hook + JS.
**Risque.** Couvre mal les cas complexes. Mitigation : bascule texte toujours
disponible.

### 4.3 Bibliothèque de formules nommées
**Valeur.** Réutiliser un calcul entre plusieurs champs sans copier-coller.
**Compat.** Nouvelle table, additive.
**Effort.** M/L.
**Risque.** Ajoute un niveau d'indirection dans le débogage. À ne faire que si
2.5 (export) ne suffit pas.

---

## 5. Bascule depuis `computed_custom_field`

Procédure sans perte, à documenter dans `README.md` :

1. **Sauvegarde** de la base (les deux plugins écrivent dans les mêmes colonnes).
2. Désinstaller `computed_custom_field`
   (`rake redmine:plugins:migrate NAME=computed_custom_field VERSION=0`).
   Attention : la migration de désinstallation d'origine **supprime** les
   colonnes. Vérifier avant, ou copier `custom_fields.formula` dans une table
   de sauvegarde.
3. Installer `smart_custom_field` ; ses migrations ne recréent `formula` et
   `is_computed` que si elles manquent (`db/migrate/001`, `002`).
4. Vérifier : `rake smart_custom_field:check` — lit chaque formule et signale
   celles qui ne s'évaluent pas (syntaxe, `cfs` inconnu, cycle).
5. `rake smart_custom_field:recompute_all --dry-run` puis sans le flag.

Les deux plugins ne doivent **jamais** tourner ensemble : tous deux patchent
`CustomField` et `Customizable`, et l'ordre d'inclusion déciderait du résultat.

---

## 6. Priorisation recommandée

| # | Évolution | Valeur | Effort | Risque compat | Ordre |
|---|---|---|---|---|---|
| 2.2 | Détection de cycle | haute | S | nul | 1 |
| 2.5 | Export/import JSON | haute | S | nul | 2 |
| 2.7 | Backfill | haute | S/M | nul | 3 |
| 2.4 | Validation statique | haute | M | nul | 4 |
| 2.3 | Prévisualisation | très haute | M | nul | 5 |
| 2.1 | Ordre topologique | haute | M | faible (flag) | 6 |
| 2.6 | Read-only uniforme | moyenne | S | nul | 7 |
| 3.1 | Helpers inter-objets | très haute | M | nul | 8 |
| 3.4 | Skip si inchangé | moyenne | S/M | nul | 9 |
| 3.2 | Agrégations | très haute | L | nul | 10 |
| 3.5 | Expliquer | moyenne | S | nul | 11 |
| 3.3 | Recalcul par dépendances | haute | L | nul | 12 |
| 4.1 | Sandbox + repli | haute | L | nul (repli) | 13 |
| 4.2 | Constructeur UI | moyenne | L | nul | 14 |
| 4.3 | Formules nommées | faible | M/L | nul | 15 |

**Thèse :** les cinq premières ne touchent ni la sémantique des formules ni la
structure des données — elles rendent le plugin sûrement exploitable.
L'intelligence réelle commence à 3.1 (voir d'autres objets) et 3.2 (agréger) :
c'est là que le plugin se distingue vraiment de l'original.

---

## 7. État d'implémentation

### Zone A — livrée

Six évolutions à impact nul sur les données, implémentées et testées.

| # | Évolution | Commit | Surface |
|---|---|---|---|
| 2.5 | Export / import JSON des formules | `72a9521` | `rake smart_custom_field:export` / `:import` (dry-run par défaut) |
| 2.4 | Analyse statique (AST) | `59ff56b` | `rake smart_custom_field:check` (avertissement seul) |
| 2.3 | Prévisualisation admin | `00c699c` | panneau du formulaire + `POST /smart_custom_field/preview` |
| 3.5 | Mode « expliquer » | `fe9b3ba` | `GET /smart_custom_field/explain` |
| 3.1 | Helpers inter-objets | `687c5af` | `cf(object, id)`, `cfs` public sur les 8 modèles |
| 4.2 | Constructeur d'expression | `1899fde` | asset JS plugin, générateur à sens unique |

Aucune de ces six n'écrit de valeur métier : deux ajoutent une UI, deux
ajoutent une tâche rake en lecture seule, une ajoute une route admin en lecture
seule, une ajoute des méthodes publiques sans écraser quoi que ce soit.

### Zone B — risque maîtrisé, non livrée

| # | Évolution | Condition |
|---|---|---|
| 2.2 | Détection de cycle | validation à la sauvegarde du champ, aucun effet sur les formules valides |
| 2.7 | Backfill des valeurs | commande explicite, jamais au boot ; `User.current` = AnonymousUser |
| 2.6 | Read-only uniforme | doit passer par `custom_field_tag_with_label`, pas `read_only_attribute_names` (n'existe que sur `Issue`) |
| 3.4 | Skip si les entrées n'ont pas changé | invisible tant que la valeur calculée est identique |
| 3.2 | Agrégations | lecture seule sur les objets liés |

### Zone C — à décider plus tard

2.1 (ordre topologique, change le résultat d'une formule existante → flag),
3.3 (recalcul par dépendances), 4.1 (sandbox), 4.3 (formules nommées).

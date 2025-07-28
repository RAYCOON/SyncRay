# SyncRay

Un outil de synchronisation de base de données PowerShell puissant qui permet une migration transparente des données entre les bases de données SQL Server avec prise en charge complète des opérations INSERT, UPDATE et DELETE.

![PowerShell](https://img.shields.io/badge/PowerShell-5.0%2B-blue)
![SQL Server](https://img.shields.io/badge/SQL%20Server-2012%2B-red)
![License](https://img.shields.io/badge/license-MIT-green)

## Fonctionnalités

- **Support CRUD complet** : Synchroniser les tables avec les opérations INSERT, UPDATE et DELETE
- **Correspondance intelligente** : Correspondance de champs flexible au-delà des clés primaires
- **Mode test (Dry-Run)** : Aperçu des modifications avant l'exécution (comportement par défaut)
- **Sécurité des transactions** : Toutes les opérations enveloppées dans des transactions avec rollback automatique
- **Validation complète** : Vérifications préalables pour la configuration, les tables et les permissions
- **Filtrage d'exportation** : Support de clause WHERE pour l'exportation sélective de données
- **Gestion d'identité** : Support IDENTITY_INSERT configurable
- **Rapports détaillés** : Résumés de modifications formatés en tableau et statistiques d'exécution

## Prérequis

- PowerShell 5.0 ou supérieur
- SQL Server 2012 ou supérieur
- Permissions de base de données appropriées (SELECT, INSERT, UPDATE, DELETE)

## Démarrage rapide

### Nouveau : Commande SyncRay centrale

La façon la plus simple d'utiliser SyncRay est via le script central `syncray.ps1` :

```powershell
# Exporter depuis la production
./src/syncray.ps1 -From production

# Importer vers le développement (aperçu)
./src/syncray.ps1 -To development

# Synchronisation directe de production vers développement
./src/syncray.ps1 -From production -To development

# Analyser la qualité des données
./src/syncray.ps1 -From production -Analyze

# Obtenir de l'aide
./src/syncray.ps1 -Help
```

### Instructions d'installation

1. **Cloner le dépôt**
   ```bash
   git clone https://github.com/yourusername/SyncRay.git
   cd SyncRay
   ```

2. **Configurer vos bases de données** dans `src/sync-config.json` :
   ```json
   {
     "databases": {
       "prod": {
         "server": "PROD-SERVER",
         "database": "ProductionDB",
         "auth": "windows"
       },
       "dev": {
         "server": "DEV-SERVER",
         "database": "DevelopmentDB",
         "auth": "sql",
         "user": "sa",
         "password": "password"
       }
     }
   }
   ```

3. **Utiliser SyncRay** :

   **Option A : Avec le script central (recommandé)**
   ```powershell
   # Exporter les données
   ./src/syncray.ps1 -From prod
   
   # Importer les données (aperçu)
   ./src/syncray.ps1 -To dev
   
   # Synchronisation directe
   ./src/syncray.ps1 -From prod -To dev -Execute
   ```

   **Option B : Avec les scripts individuels**
   ```powershell
   # Export
   ./src/sync-export.ps1 -From prod
   
   # Import (aperçu)
   ./src/sync-import.ps1 -To dev
   
   # Import (exécuter)
   ./src/sync-import.ps1 -To dev -Execute
   ```

## Documentation

- [Guide d'installation](docs/installation.fr.md)
- [Référence de configuration](docs/configuration.fr.md)
- [Exemples d'utilisation](docs/examples.fr.md)
- [Dépannage](docs/troubleshooting.fr.md)

## Configuration

### Paramètres de synchronisation des tables

```json
{
  "syncTables": [{
    "sourceTable": "Users",
    "targetTable": "Users_Archive",
    "matchOn": ["UserID"],
    "ignoreColumns": ["LastModified"],
    "allowInserts": true,
    "allowUpdates": true,
    "allowDeletes": false,
    "exportWhere": "IsActive = 1"
  }]
}
```

### Paramètres clés

- **matchOn** : Champs pour la correspondance d'enregistrements (détecte automatiquement la clé primaire si vide)
- **ignoreColumns** : Colonnes à exclure de la comparaison
- **allowInserts/Updates/Deletes** : Contrôle les opérations autorisées
- **exportWhere** : Filtrer les données sources avec une clause SQL WHERE
- **replaceMode** : Supprimer tous les enregistrements avant l'insertion (remplacement complet de la table)
- **preserveIdentity** : Conserver les valeurs des colonnes d'identité pendant la synchronisation
- **targetTable** : Spécifier un nom de table cible différent (par défaut : sourceTable)

### Mode de remplacement (Nouvelle fonctionnalité)

Lorsque `replaceMode: true` est défini pour une table :
1. **Tous les enregistrements existants sont supprimés** de la table cible
2. **Tous les enregistrements de l'exportation sont insérés**
3. **Aucune opération UPDATE ou DELETE individuelle** n'est effectuée
4. Utile pour les tables de référence ou les actualisations complètes de données
5. Exécuté dans une transaction pour la sécurité

Exemple de configuration :
```json
{
  "sourceTable": "ReferenceData",
  "replaceMode": true,
  "preserveIdentity": true
}
```

## Référence des commandes

### syncray.ps1 (Outil central)

Le point d'entrée principal pour toutes les opérations SyncRay. Détermine automatiquement l'opération en fonction des paramètres.

**Paramètres :**
- `-From <string>` : Base de données source (déclenche le mode export)
- `-To <string>` : Base de données cible (déclenche le mode import)
- `-From <string> -To <string>` : Les deux (déclenche le mode sync)
- `-Analyze` : Analyser la qualité des données sans exporter
- `-Validate` : Valider la configuration sans traitement
- `-Execute` : Appliquer les modifications (pour les modes import/sync)
- `-SkipOnDuplicates` : Ignorer les tables avec des enregistrements en double
- `-CreateReports` : Créer des rapports CSV pour les problèmes
- `-ReportPath <string>` : Chemin personnalisé pour les rapports CSV
- `-CsvDelimiter <string>` : Délimiteur CSV
- `-ShowSQL` : Afficher les instructions SQL pour le débogage
- `-Help` : Afficher les informations d'aide

**Exemples :**
```powershell
# Mode export
./src/syncray.ps1 -From production

# Mode import (aperçu)
./src/syncray.ps1 -To development

# Mode sync (transfert direct)
./src/syncray.ps1 -From production -To development -Execute

# Mode analyse
./src/syncray.ps1 -From production -Analyze
```

### sync-export.ps1

Exporte les données de la base de données source vers des fichiers JSON.

**Paramètres :**
- `-From <string>` (requis) : Clé de base de données source depuis la configuration
- `-ConfigFile <string>` : Chemin vers le fichier de configuration (par défaut : sync-config.json)
- `-Tables <string>` : Liste de tables spécifiques séparées par des virgules à exporter
- `-Analyze` : Analyser la qualité des données et créer des rapports sans exporter
- `-Validate` : Valider la configuration et les données sans exporter ni créer de rapports
- `-SkipOnDuplicates` : Ignorer automatiquement les tables avec des enregistrements en double
- `-CreateReports` : Créer des rapports CSV pour les problèmes de qualité des données
- `-ReportPath <string>` : Chemin personnalisé pour les rapports CSV
- `-CsvDelimiter <string>` : Délimiteur CSV (par défaut : spécifique à la culture)
- `-ShowSQL` : Afficher les instructions SQL et les informations de débogage détaillées

**Exemples d'utilisation :**
```powershell
# Export standard
./src/sync-export.ps1 -From prod

# Export avec rapports de problèmes
./src/sync-export.ps1 -From prod -CreateReports

# Analyser uniquement la qualité des données
./src/sync-export.ps1 -From prod -Analyze

# Exporter des tables spécifiques avec sortie SQL de débogage
./src/sync-export.ps1 -From prod -Tables "Users,Orders" -ShowSQL
```

### sync-import.ps1

Importe les données depuis les fichiers JSON vers la base de données cible.

**Paramètres :**
- `-To <string>` (requis) : Clé de base de données cible depuis la configuration
- `-ConfigFile <string>` : Chemin vers le fichier de configuration (par défaut : sync-config.json)
- `-Tables <string>` : Liste de tables spécifiques séparées par des virgules à importer
- `-Execute` : Appliquer les modifications (par défaut est dry-run)
- `-ShowSQL` : Afficher les instructions SQL pour le débogage

## Fonctionnalités de sécurité

- **Validation d'abord** : Vérifications préalables complètes avant toute opération
- **Dry-Run par défaut** : Toujours prévisualiser les modifications avant l'exécution
- **Confirmation de sécurité** : Confirmation explicite requise pour l'exécution
- **Rollback de transaction** : Rollback automatique en cas d'erreur
- **Détection de doublons** : S'assure que les champs matchOn identifient des enregistrements uniques

## Exemple de sortie

```
=== MODIFICATIONS DÉTECTÉES ===

Table                    | Insérer | Mettre à jour | Supprimer
---------------------------------------------------------------
Users                    |     125 |            37 |         5
Orders                   |     450 |             0 |         0
Products                 |       0 |            15 |         2
---------------------------------------------------------------
TOTAL                    |     575 |            52 |         7

AVERTISSEMENT : Vous êtes sur le point de modifier la base de données !

Voulez-vous exécuter ces modifications ? (oui/non) :
```

## Contribuer

Les contributions sont les bienvenues ! N'hésitez pas à soumettre une Pull Request.

## Licence

Ce projet est sous licence MIT - voir le fichier [LICENSE](LICENSE) pour plus de détails.

## Remerciements

- Construit avec PowerShell et SQL Server
- Inspiré par le besoin d'une synchronisation de base de données fiable

---

Développé par l'équipe Raycoon
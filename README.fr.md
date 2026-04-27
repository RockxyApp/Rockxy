<p align="center">
  <img src="docs/logo/logo.png" alt="Rockxy" width="128" />
</p>

<h1 align="center">Rockxy</h1>

<p align="center">
  <a href="README.md">English</a> |
  <a href="README.vi.md">Tiếng Việt</a> |
  <a href="README.zh.md">中文</a> |
  <a href="README.ja.md">日本語</a> |
  <a href="README.ko.md">한국어</a> |
  <a href="README.fr.md">Français</a> |
  <a href="README.de.md">Deutsch</a>
</p>

<p align="center">
  <strong>Proxy de d&eacute;bogage HTTP open-source pour macOS.</strong>
</p>

<p align="center">
  Interceptez, inspectez et modifiez le trafic HTTP/HTTPS/WebSocket/GraphQL &mdash; con&ccedil;u nativement en Swift.<br>
  Une alternative gratuite et auditable &agrave; <a href="#rockxy-vs-alternatives">Proxyman et Charles Proxy</a>.
</p>

<p align="center">
  <a href="https://github.com/LocNguyenHuu/Rockxy/releases"><img src="https://img.shields.io/github/v/release/LocNguyenHuu/Rockxy?label=release&color=blue" alt="Version" /></a>
  <img src="https://img.shields.io/badge/macOS-14%2B-blue" alt="Plateforme" />
  <img src="https://img.shields.io/badge/Swift-5.9-orange" alt="Swift" />
  <a href="LICENSE"><img src="https://img.shields.io/badge/license-AGPL--3.0-green" alt="Licence" /></a>
  <a href="CONTRIBUTING.md"><img src="https://img.shields.io/badge/PRs-welcome-brightgreen" alt="PRs bienvenues" /></a>
  <a href="https://github.com/sponsors/LocNguyenHuu"><img src="https://img.shields.io/badge/sponsor-GitHub%20Sponsors-ea4aaa" alt="Soutenir" /></a>
</p>

<p align="center">
  <img src="docs/images/Rockxy-Dark.png" alt="Rockxy en cours d'ex&eacute;cution sur macOS" width="800" />
</p>

---

<!-- BEGIN GENERATED: latest-release -->
## Latest Tagged Release

**v0.11.0** — 2026-04-25

### Added

- Sparkle-powered automatic updates for signed public releases.
- Bundled Rockxy MCP support for local developer-tool integrations.
- Rockxy Pro activation and entitlement-aware upgrade foundations.

### Fixed

- Improved paid-license activation recovery and product validation reliability.
- Closed release-readiness gaps around production licensing configuration and update metadata.
- Fixed release signing settings required for Apple notarization and Gatekeeper acceptance.

### Changed

- Hardened the release pipeline with production signing, notarization, stapling, checksum, and update-feed validation.
- Refreshed public documentation, localized README content, and release metadata for the 0.11.0 release.
- Improved Xcode project and build configuration reproducibility for fresh checkouts.

See [CHANGELOG.md](CHANGELOG.md) for the full release history.
<!-- END GENERATED: latest-release -->

## Points forts de la branche actuelle

- Developer Setup Hub couvre désormais les runtimes, navigateurs, clients, appareils, frameworks et environnements avec des snippets ciblés, des watchers de validation et une documentation honnête.
- Quand le SSL Proxying est activé ou désactivé par domaine ou par application, l’invite HTTPS chiffrée, les actions de la barre latérale et la table principale restent synchronisées.
- L’inspecteur et la table principale ont &eacute;t&eacute; peaufin&eacute;s avec des onglets d&eacute;filants sur une seule ligne, un contenu Query align&eacute; en haut, une meilleure s&eacute;paration Status/Code, des colonnes Request/Response en octets, des correctifs de duration et des ic&ocirc;nes SSL mises &agrave; jour en direct.

## Fonctionnalit&eacute;s

**Capture du trafic** &mdash; Proxy bas&eacute; sur SwiftNIO avec tunnel CONNECT, g&eacute;n&eacute;ration automatique de certificats TLS par h&ocirc;te, capture de frames WebSocket et d&eacute;tection automatique des op&eacute;rations GraphQL.

**Tout inspecter** &mdash; Vue arborescente JSON, inspecteur hexad&eacute;cimal, diagramme en cascade (DNS/TCP/TLS/TTFB/Transfer), en-t&ecirc;tes, cookies, param&egrave;tres de requ&ecirc;te, authentification &mdash; le tout dans un inspecteur &agrave; onglets.

**Mock et modification** &mdash; Map Local (servir depuis des fichiers locaux), Map Remote (rediriger vers un autre serveur), Breakpoints (pause et &eacute;dition en cours de route), Block, Throttle, Modify Headers, Allow List, Bypass Proxy.

**Corr&eacute;lation des logs** &mdash; Capturer les logs syst&egrave;me macOS (OSLog) et les corr&eacute;ler avec les requ&ecirc;tes r&eacute;seau par horodatage. Voir quelle application a envoy&eacute; chaque requ&ecirc;te.

**Extension par plugins** &mdash; Scripting JavaScript dans un environnement JavaScriptCore isol&eacute;. Inspectez, modifiez et automatisez le trafic avec des hooks personnalis&eacute;s.

**Con&ccedil;u pour la mont&eacute;e en charge** &mdash; NSTableView avec d&eacute;filement virtuel pour 100k+ requ&ecirc;tes. &Eacute;viction par tampon circulaire, d&eacute;chargement des body sur disque, mises &agrave; jour UI group&eacute;es. Z&eacute;ro latence.

**Developer Setup Hub** &mdash; Configuration guid&eacute;e par runtime, navigateur, appareil, framework et environnement avec snippets copiables, sondes de validation et notes de d&eacute;pannage.

**AI-Ready (MCP Server)** &mdash; Serveur Model Context Protocol int&eacute;gr&eacute; qui permet &agrave; Claude CLI, Claude Desktop et aux autres clients MCP d'interroger le trafic en direct, les r&egrave;gles et l'&eacute;tat du proxy directement depuis le chat. Local uniquement, authentifi&eacute; par token, donn&eacute;es sensibles masqu&eacute;es par d&eacute;faut.

> 100 % natif macOS. Pas d'Electron. Pas de vues web. SwiftUI + AppKit + SwiftNIO.

## D&eacute;marrage rapide

```bash
git clone https://github.com/LocNguyenHuu/Rockxy.git
cd Rockxy
open Rockxy.xcodeproj
```

Compilez et ex&eacute;cutez dans Xcode. La fen&ecirc;tre de bienvenue vous guide &agrave; travers la configuration du CA racine, l'installation du helper et l'activation du proxy.

**Pr&eacute;requis :** macOS 14.0+, Xcode 16+, Swift 5.9

## Rockxy vs. Alternatives

|  | **Rockxy** | **Proxyman** | **Charles Proxy** |
|---|---|---|---|
| **Licence** | AGPL-3.0 (open-source) | Propri&eacute;taire (freemium) | Propri&eacute;taire (50 $) |
| **Code source** | Enti&egrave;rement auditable | Ferm&eacute; | Ferm&eacute; |
| **Technologie** | Swift + SwiftNIO | Swift + AppKit | Java |
| **Interception HTTPS** | Oui | Oui | Oui |
| **WebSocket** | Oui | Oui | Oui |
| **D&eacute;tection GraphQL** | Oui | Oui | Non |
| **Map Local / Remote** | Oui | Oui | Oui |
| **Breakpoints** | Oui | Oui | Oui |
| **Scripting JavaScript** | Oui | Oui | Non |
| **Corr&eacute;lation OSLog** | Oui | Non | Non |
| **Identification de processus** | Oui | Oui | Non |
| **Diff de requ&ecirc;tes** | Oui | Oui | Non |
| **Import/export HAR** | Oui | Oui | Non |
| **Performance 100k+ lignes** | Oui | Oui | Lent |
| **Config proxy sans mot de passe** | Oui (d&eacute;mon helper) | Oui | Non |
| **Contributions communautaires** | PRs ouvertes | Non | Non |

## S&eacute;curit&eacute;

Rockxy intercepte le trafic r&eacute;seau &mdash; la s&eacute;curit&eacute; est fondamentale, pas optionnelle.

- Le helper XPC valide les appelants par **comparaison de cha&icirc;ne de certificats**, pas seulement par bundle ID
- Les plugins s'ex&eacute;cutent dans un **JavaScriptCore isol&eacute;** avec un timeout de 5 secondes, sans acc&egrave;s au syst&egrave;me de fichiers ni au r&eacute;seau
- **Validation des entr&eacute;es** sur toutes les fronti&egrave;res &mdash; limites de taille des body, limites d'URI, protection contre le DoS regex, pr&eacute;vention du path traversal
- Les identifiants sont **automatiquement masqu&eacute;s** dans les logs
- Les fichiers sensibles sont stock&eacute;s avec des **permissions 0o600**

Signaler les vuln&eacute;rabilit&eacute;s via [SECURITY.md](SECURITY.md). Voir l'[architecture de s&eacute;curit&eacute; compl&egrave;te](docs/development/security.mdx) pour plus de d&eacute;tails.

## Feuille de route

- [x] Interception HTTP/HTTPS/WebSocket/GraphQL
- [x] Map Local, Map Remote, Breakpoints, Block, Throttle
- [x] Syst&egrave;me de plugins JavaScript (ex&eacute;cution sandbox&eacute;e)
- [x] Import/export HAR, fichiers de session natifs, diff de requ&ecirc;tes
- [x] Corr&eacute;lation OSLog et masquage des identifiants
- [x] Serveur Model Context Protocol (MCP) pour les assistants IA (Claude CLI, Claude Desktop)
- [ ] Support HTTP/2 et HTTP/3
- [ ] Proxy d'appareil distant (iOS via USB/Wi-Fi)
- [ ] Mode headless pour les pipelines CI/CD
- [ ] Inspection gRPC / Protocol Buffers
- [ ] Regroupement d'erreurs et tableau de bord analytique

## Documentation

Documentation compl&egrave;te disponible sur [Rockxy Docs](docs/index.mdx) :

- [Guide de d&eacute;marrage rapide](docs/quickstart.mdx) &mdash; op&eacute;rationnel en quelques minutes
- [Developer Setup Hub](docs/features/developer-setup-hub.mdx) &mdash; snippets runtime, guides appareil, sondes de validation et matrice de support
- [Architecture](docs/development/architecture.mdx) &mdash; moteur proxy, mod&egrave;le Actor, flux de donn&eacute;es
- [Mod&egrave;le de s&eacute;curit&eacute;](docs/development/security.mdx) &mdash; fronti&egrave;res de confiance, validation XPC, gestion des certificats
- [D&eacute;cisions de conception](docs/development/design-decisions.mdx) &mdash; pourquoi SwiftNIO, NSTableView, les Actors
- [Compiler depuis les sources](docs/development/building.mdx) &mdash; compilation, tests, lint et d&eacute;bogage
- [Style de code](docs/development/code-style.mdx) &mdash; SwiftLint, SwiftFormat et conventions
- [Changelog](CHANGELOG.md) &mdash; travaux non publi&eacute;s et historique des versions tagu&eacute;es

## Contribuer

Toutes les contributions sont les bienvenues &mdash; code, tests, documentation, rapports de bugs et retours UX.

Consultez **[CONTRIBUTING.md](CONTRIBUTING.md)** pour les instructions de configuration, le style de code et la checklist PR compl&egrave;te.

Les issues pour d&eacute;butants sont &eacute;tiquet&eacute;es [`good first issue`](https://github.com/LocNguyenHuu/Rockxy/labels/good%20first%20issue). En soumettant une PR, vous acceptez le [CLA](CLA.md).

## Sponsors et Partenaires

Rockxy est construit et maintenu par des d&eacute;veloppeurs ind&eacute;pendants. Les sponsorisations financent le d&eacute;veloppement continu, les audits de s&eacute;curit&eacute; et les nouvelles fonctionnalit&eacute;s.

<p align="center">
  <a href="https://github.com/sponsors/LocNguyenHuu">
    <img src="https://img.shields.io/badge/Sponsoriser_Rockxy-ea4aaa?style=for-the-badge&logo=githubsponsors&logoColor=white" alt="Sponsoriser Rockxy" />
  </a>
</p>

| Niveau | Avantages |
|--------|-----------|
| **Gold Sponsor** | Logo sur le README + site de docs, demandes de fonctionnalit&eacute;s prioritaires, canal de support d&eacute;di&eacute; |
| **Silver Sponsor** | Logo sur le README, remerciements dans les notes de version |
| **Bronze Sponsor** | Remerciements dans le README et la documentation |
| **Partner** | Co-d&eacute;veloppement, support d'int&eacute;gration, acc&egrave;s anticip&eacute; aux fonctionnalit&eacute;s &agrave; venir |

**Demandes de partenariat** &mdash; entreprises d'outils de d&eacute;veloppement, soci&eacute;t&eacute;s de s&eacute;curit&eacute; et &eacute;quipes entreprise cherchant des int&eacute;grations personnalis&eacute;es ou des solutions en marque blanche : [rockxyapp@gmail.com](mailto:rockxyapp@gmail.com)

## Support

- [GitHub Sponsors](https://github.com/sponsors/LocNguyenHuu) &mdash; soutenir le d&eacute;veloppement de Rockxy
- [GitHub Issues](https://github.com/LocNguyenHuu/Rockxy/issues) &mdash; rapports de bugs et demandes de fonctionnalit&eacute;s
- [GitHub Discussions](https://github.com/LocNguyenHuu/Rockxy/discussions) &mdash; questions et discussions communautaires
- **Email** &mdash; [rockxyapp@gmail.com](mailto:rockxyapp@gmail.com)
- **Probl&egrave;mes de s&eacute;curit&eacute;** &mdash; voir [SECURITY.md](SECURITY.md) pour la divulgation responsable

## Licence

[GNU Affero General Public License v3.0](LICENSE) &mdash; Copyright 2024&ndash;2026 Rockxy Contributors.

## Historique des Étoiles

<a href="https://www.star-history.com/?repos=RockxyApp%2FRockxy&type=date&legend=bottom-right">
 <picture>
   <source media="(prefers-color-scheme: dark)" srcset="https://api.star-history.com/chart?repos=RockxyApp/Rockxy&type=date&theme=dark&legend=top-left" />
   <source media="(prefers-color-scheme: light)" srcset="https://api.star-history.com/chart?repos=RockxyApp/Rockxy&type=date&legend=top-left" />
   <img alt="Star History Chart" src="https://api.star-history.com/chart?repos=RockxyApp/Rockxy&type=date&legend=top-left" />
 </picture>
</a>

---

<p align="center">
  <sub>Construit avec Swift, SwiftNIO, SwiftUI et AppKit.</sub>
</p>

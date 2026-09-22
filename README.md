# YGO Deck Builder — iOS

Native iOS / iPadOS client for [YGO Deck Builder](https://github.com/MathieuDubart/ygo-deckbuilder),
the self-hosted Yu-Gi-Oh! collection and deck builder. SwiftUI, iOS 26 (Liquid Glass), no dependencies.

## Features

Same scope as the web app, against your own server:

- **Server setup** — enter the address of your instance (HTTPS, or HTTP on your local network / VPN).
- **Account** — sign in or sign up; the session is kept in the Keychain (refresh token) and renewed automatically.
- **Collection** — stats, cards by print / condition / language with +/− and swipe to delete, owned products with their full contents, what is missing, a copyable / shareable list, a play guide and one-tap deck creation for structure and starter decks.
- **Add a product** — gallery of products by type (structure decks, tins, starters, boxes) with official quantities.
- **Card scanner** — the camera reads the code printed under the artwork (`SDBE-FR001`), finds the card, and adds it with the right print and language in one tap, then moves on to the next card.
- **Catalog** — search in any language or by print code, filters (owned, category, archetype, sort), infinite scroll.
- **Card details** — stats, effect, prints and prices, add to collection or wishlist, interactions with the rest of the catalog (tap a card to follow the chain).
- **Deck builder** — Main / Extra / Side, live validation (40–60, 3 copies, banlist, Extra Deck), missing copies and their cost, auto-save, card picker (your cards or the whole catalog, plus suggestions linked to the deck), `.ydk` import and export, play guide.
- **Suggestions** — ready-to-play decks from your collection, meta decks with your coverage, official decks (structure, starter and box decks), one auto deck per archetype; preview with "full list" / "with my cards", strength score, guide, then create the deck and send what is missing to the wishlist.
- **Play guides** — computed from card effects, or written by the server's AI model when one is configured (computed / AI switch).
- **Duel simulator** — play with the real card effects (EDOPro engine, run by your server): choose your deck, who goes first, force your opening hand, set up the opponent's board, then face a passive opponent (combo testing), make its choices yourself, or play against the bot. Tap a highlighted card to play it, answer the engine's choices in the bottom panel, read the duel log. "Test in a duel" from the deck builder. Every action is replayed like a cut-scene (summons, activations, attacks, damage with screen shake, rolling LP, turn banners) with haptics and synthesized sound effects (AVAudioEngine, no audio files, respects the silent switch); skip or change the speed from the menu.
- **Rules reminder** — the official rules (current Master Rule): turn, every summon type, Extra Monster Zones, chains, battle.
- **Wishlist** — grouped by priority, swipe "Got it" to move a card to the collection.
- **Five languages** — English, French, German, Italian, Portuguese: interface, card names and effects, generated guides. Follows the system (per-app language in Settings) or the in-app setting.

## Requirements

- Xcode 26 or later, iOS 26 SDK.
- A YGO Deck Builder server **with native token auth** (`X-Auth-Mode: token`, added alongside this app). The app talks to `https://<your-server>/api/…`, the same single port as the browser.

## Running

Open `ygo-deckbuilder-iOS.xcodeproj`, pick your team in *Signing & Capabilities* (and your own bundle identifier), and run.
The folder `ygo-deckbuilder-iOS/` is a synchronized group: any file added there is part of the target.

## Architecture

```
ygo-deckbuilder-iOS/
  App/             entry point, root routing (server → sign-in → tabs)
  Core/
    Networking/    APIClient (auth header, locale, single-flight refresh on 401), endpoints, errors
    Auth/          TokenStore (refresh token in the Keychain, access token in memory)
    Models/        Codable mirrors of the shared DTOs (packages/shared on the web side)
    Domain/        deck rules (port of validateDeck), print codes
    Localization/  L10n + a small ICU MessageFormat formatter (plurals, <strong> tags)
    Images/        image pipeline through the server's /_next/image optimizer, memory + disk cache
    State/         AppState (server, session, data versions), Loadable
  DesignSystem/    theme, pills, stat tiles, coverage ring, score, filter chips, card views, flow layout
  Features/        one folder per screen (Catalog, CardDetail, Collection, Products, Decks,
                   DeckBuilder, Suggestions, Guide, Wishlist, Scanner, Settings, Auth, Onboarding)
  Resources/       messages.<lang>.json (generated), assets, InfoPlist.xcstrings
Config/Info.plist  what build settings can't express (languages, ATS for self-hosted servers)
Localization/      iOS-only strings (ios.<lang>.json)
scripts/           sync-messages.py
```

- **State**: `@Observable` models, one `AppState` in the environment. Screens reload with
  `.task(id: app.collectionVersion)`; any change to the collection calls `app.collectionChanged()`.
- **Concurrency**: the target uses default MainActor isolation; models are `nonisolated` value types.
- **Images**: cards and box art go through the server's image optimizer (resized, cached server-side)
  instead of hotlinking YGOPRODeck, exactly like the web app.

## Translations

UI strings are the web app's own messages (`apps/web/messages`, ICU format) plus an `ios` namespace.
After changing either, regenerate the bundled files:

```bash
python3 scripts/sync-messages.py            # expects ../ygo-deckbuilder next to this repo
python3 scripts/sync-messages.py /path/to/ygo-deckbuilder/apps/web/messages
```

## Credits

Card data and images: [YGOPRODeck](https://ygoprodeck.com/). Box art and set lists:
[Yugipedia](https://yugipedia.com/). Yu-Gi-Oh! is a trademark of Konami; this project is not
affiliated with or endorsed by Konami.

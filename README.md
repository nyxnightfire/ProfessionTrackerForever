# Profession Tracker
Compact, movable profession bars for **World of Warcraft: Forever**. Keep an eye on your skill, tier, and approximate progress without leaving the profession book open.

## Features
- Detects learned professions on the current character. Settings and estimate history are saved per character.
- Shows skill, trained cap, and profession tier in a compact, collapsible tracker.
- Tracks Fishing catches and Herbalism, Mining, and Skinning actions. Estimates adapt to observed skill-ups; custom action rates are optional.
- Includes bundled skill-range recipe recommendations for Alchemy, Blacksmithing, Cooking, Enchanting, Engineering, First Aid, Leatherworking, and Tailoring. If a recommended recipe is not known, the tracker prompts you to learn it.
- Uses Auctionator price data for material-cost estimates when available.
- Supports per-profession bar colors, classic and modern styles, optional EllesmereUI styling, drag positioning, and profession-book docking.

Estimates are approximate. Bundled guide recommendations are maintained with addon updates and are not fetched live. Professions without a bundled route use scanned learned recipes where supported.

## Installation
1. Download the latest release from CurseForge once the project is approved. Until then, the addon files are available in this repository under the `ProfessionTracker` folder.
2. Place the `ProfessionTracker` folder inside:

   `World of Warcraft\_forever_\Interface\AddOns\`

3. Restart WoW: Forever, or type `/reload` when updating, and make sure **Profession Tracker** is enabled in the AddOns list.

## Auctionator and UI integrations
Auctionator must be installed and enabled for Profession Tracker to work. It provides the Auction House pricing data used for material-cost estimates; scan the Auction House in Auctionator to refresh its prices.

EllesmereUI and EllesmereUI Blizzard Skins can optionally style the tracker. The addon also detects several other UI suites and can use its Modern style. These integrations are optional.

## In-game use
- `/pt` or `/pt options` opens **Options → AddOns → Profession Tracker**.
- Use the `+` on a profession row to expand its details; use `-` to collapse them. Multiple rows can stay open.
- Drag the **Profession Tracker** title bar to move the panel. Lock its position under **UI Appearance** when it is where you want it.
- The panel temporarily docks beside the character skills or profession book while open, then returns to its saved position.
- Use **UI Appearance** to change the panel style, default color, collapse direction, title position, displayed skill details, and rank-up animation. Individual profession pages can override the bar color and estimate settings.
- `/pt show`, `/pt hide`, `/pt toggle`, `/pt collapse`, `/pt lock`, and `/pt unlock` control the tracker. `/pt debug` opens a copyable diagnostic report.

## Estimate details
Fishing catches are counted from fishing loot where supported. Herbalism, Mining, and Skinning count successful gather actions. Their rates start with an estimate and adapt as the character gains skill points; each profession can instead use a custom rate.

Crafting recommendations follow the current bundled skill-range step. Open your own profession book to scan learned recipes. Auctionator prices are shown when the recommended recipe is known and its reagent data and price data are available. Craft counts improve as the addon observes skill-ups while crafting.

Bundled routes currently cover Alchemy, Blacksmithing, Cooking, Enchanting, Engineering, First Aid, Leatherworking, and Tailoring. Other professions fall back to scanned learned recipes where supported.

## Credits
- [Auctionator](https://www.curseforge.com/wow/addons/auctionator) for its Auction House pricing API.
- [WoW-Professions.com](https://www.wow-professions.com/forever) for the source recommendations used in the bundled profession routes.
- EllesmereUI and EllesmereUI Blizzard Skins for optional styling integration.
- Blizzard's World of Warcraft APIs and UI assets for profession data and the default in-game style.

## Troubleshooting
- If a guide step says to open the profession to check a recipe, open your own profession book and wait briefly for its recipe scan.
- If an Auctionator price is missing, scan the Auction House in Auctionator and check that the recommended recipe is known.
- Use `/pt debug` to view tracker and estimator diagnostics. The report can be copied from its window and shared for troubleshooting.

Profession Tracker cannot write files into its own addon folder; the debug command displays a copyable report instead.

## Feature requests and bug support
Join the [Profession Tracker Discord](https://discord.gg/WYD7WmYrqz) to suggest features or get help with bugs. When reporting a bug, include what you expected, what happened, and a `/pt debug` report if possible.

# Changelog

## 1.0.0

- Detects learned professions per character and displays their current skill, trained cap, and profession tier.
- Adds a movable tracker with collapsible profession rows, book-side docking, selectable panel styles, per-profession colors, and character-specific settings.
- Tracks Fishing, Herbalism, Mining, and Skinning actions and estimates actions remaining using learned or custom rates.
- Includes skill-range recipe recommendations for Alchemy, Blacksmithing, Cooking, Enchanting, Engineering, First Aid, Leatherworking, and Tailoring.
- Checks learned recipes when a profession is opened and prompts when the current guide recipe needs to be learned.
- Integrates with Auctionator for material price estimates and optionally with EllesmereUI styling.
- Adds a general settings page with enable toggle, version number, credits, and `/pt debug` report.

### Known limitations

- Action counts and skill-up estimates are approximate and improve as the character produces more observations.
- Guide steps are bundled and do not update from the website automatically. Professions without bundled routes use scanned learned recipes where supported.
- Auction House prices depend on Auctionator's available price data.

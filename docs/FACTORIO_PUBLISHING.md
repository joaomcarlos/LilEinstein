# Factorio Mod Publishing Guide

Requirements and process for publishing a Factorio mod to the official mod portal so it can be installed and updated through the in-game mod browser. All claims are sourced from official Factorio documentation.

Primary sources:
- [Mod Structure](https://lua-api.factorio.com/latest/auxiliary/mod-structure.html)
- [Changelog Format](https://lua-api.factorio.com/latest/auxiliary/changelog-format.html)
- [Mod Portal API](https://wiki.factorio.com/Mod_portal_API)
- [Mod Publish API](https://wiki.factorio.com/Mod_publish_API)
- [Mod Details API](https://wiki.factorio.com/Mod_details_API)
- [Mod Images API](https://wiki.factorio.com/Mod_images_API)
- [Tutorial:Modding FAQ](https://wiki.factorio.com/Tutorial:Modding_FAQ)
- [User:Pongles/Mod Portal](https://wiki.factorio.com/User:Pongles/Mod_Portal)
- [Modding](https://wiki.factorio.com/Modding)

## 1. info.json / Mod Package Metadata

`info.json` is the only mandatory file in a mod and identifies the mod, defines its version, and other general properties. [Mod Structure](https://lua-api.factorio.com/latest/auxiliary/mod-structure.html)

**Mandatory fields:**

- `name` (string): Internal name. The game accepts anything, but the mod portal restricts names to alphanumeric characters, dashes, and underscores (no spaces). The mod folder/zip file name must contain the mod name. [Mod Structure](https://lua-api.factorio.com/latest/auxiliary/mod-structure.html)
- `version` (string): Format `"number.number.number"` (e.g. `"0.6.4"`). Each number ranges `0`–`65535`. No inherent semantic meaning. [Mod Structure](https://lua-api.factorio.com/latest/auxiliary/mod-structure.html)
- `title` (string): Human-readable display name. Can be overridden by a locale entry in the `mod-name` category. [Mod Structure](https://lua-api.factorio.com/latest/auxiliary/mod-structure.html)
- `author` (string): No restrictions; can list multiple authors. The mod portal ignores this and shows the uploader's name as author. [Mod Structure](https://lua-api.factorio.com/latest/auxiliary/mod-structure.html)
- `factorio_version` (string): Major Factorio version, formatted `"number.number"` (e.g. `"2.0"`). Technically optional (defaults to `"0.12"`), but effectively mandatory for any modern release. [Mod Structure](https://lua-api.factorio.com/latest/auxiliary/mod-structure.html)

**Optional fields:**

- `dependencies` (array): Dependency strings. Required (just the name), optional (prefixed `? `), or with version constraints (e.g. `"base >= 2.0"`). [Tutorial:Modding FAQ](https://wiki.factorio.com/Tutorial:Modding_FAQ)
- `description` (string): Short description; the only description displayed in-game. Overridable by a locale entry in the `mod-description` category. [Mod Structure](https://lua-api.factorio.com/latest/auxiliary/mod-structure.html)
- `homepage` (string): URL to the mod's website, forum thread, or Discord. The portal shows this link. [Mod Structure](https://lua-api.factorio.com/latest/auxiliary/mod-structure.html)
- `contact` (string): Contact information for the mod author. [Mod Structure](https://lua-api.factorio.com/latest/auxiliary/mod-structure.html)

### Version Numbering

Format `"number.number.number"` (major.minor.sub), e.g. `"0.6.4"`. Each number `0`–`65535`. No inherent semantic meaning. [Mod Structure](https://lua-api.factorio.com/latest/auxiliary/mod-structure.html)

### Wrong `factorio_version`

- Incorrect or missing value: the game prints an error to the log and refuses to load the mod. [Tutorial:Modding FAQ](https://wiki.factorio.com/Tutorial:Modding_FAQ)
- Including a third number (e.g. `"0.18.27"`): the mod portal rejects the mod and may cause unexpected in-game mod-management behavior. [Mod Structure](https://lua-api.factorio.com/latest/auxiliary/mod-structure.html)
- A mod is compatible with only one major version. `"2.0"` covers all 2.0.x releases and no other major releases. [Mod Structure](https://lua-api.factorio.com/latest/auxiliary/mod-structure.html)
- Exception: mods with `factorio_version` `"0.18"` are also loadable in 1.0, and the portal returns them when queried for `"1.0"` mods. [Mod Structure](https://lua-api.factorio.com/latest/auxiliary/mod-structure.html)

### Minimal info.json Example

```json
{
  "name": "better-armor",
  "version": "0.3.6",
  "title": "My better armor mod",
  "author": "A very great modder",
  "factorio_version": "2.0",
  "dependencies": ["? optional-mod"]
}
```
[Mod Structure](https://lua-api.factorio.com/latest/auxiliary/mod-structure.html)

## 2. Mod Portal Account & Upload

### Web UI

1. Log in with a Factorio.com account at mods.factorio.com
2. Click "Submit mod" under "My Mods" (top right)
3. Provide the mod as a zip file
4. Write a description and upload pictures
5. Title, version, etc. are pulled from the zip
6. The mod name may not contain spaces [Tutorial:Modding FAQ](https://wiki.factorio.com/Tutorial:Modding_FAQ)

**Account requirement:** a verified Factorio purchase (via factorio.com or a linked Steam account) is required to use the portal. [User:Pongles/Mod Portal](https://wiki.factorio.com/User:Pongles/Mod_Portal)

### CLI / API Upload

Mod Publish API supports programmatic uploads:

- Endpoint: `https://mods.factorio.com/api/v2/mods/init_publish` (POST)
- Auth: an API key with `ModPortal: Publish Mods` usage, created at https://factorio.com/profile
- Two-step process:
  1. Call `init_publish` with the mod name to get an `upload_url`
  2. POST the zip to `upload_url` with optional metadata (description, category, license, source_url) [Mod Publish API](https://wiki.factorio.com/Mod_publish_API)

### In-Game Upload

Not possible. The in-game mod browser is for download/install/update only. Uploads must go through the web UI or the API. [Modding](https://wiki.factorio.com/Modding)

## 3. Zip Packaging

### Required Zip Structure

The zip must be named `{mod-name}_{version_number}.zip`. [Mod Structure](https://lua-api.factorio.com/latest/auxiliary/mod-structure.html)

The folder inside the zip has no naming restrictions; only the zip file itself must follow the `{mod-name}_{version-number}` pattern. The tutorial recommends a folder with the same name (minus `.zip`) inside the zip. [Mod Structure](https://lua-api.factorio.com/latest/auxiliary/mod-structure.html) [User:Pongles/Mod Portal](https://wiki.factorio.com/User:Pongles/Mod_Portal)

```
myArmorMod_0.3.6.zip
|- myArmorMod_0.3.6/
   |- control.lua
   |- data.lua
   |- info.json
   |- thumbnail.png
```
[User:Pongles/Mod Portal](https://wiki.factorio.com/User:Pongles/Mod_Portal)

### Required Files

**Mandatory:** `info.json` — the only mandatory file. [Mod Structure](https://lua-api.factorio.com/latest/auxiliary/mod-structure.html)

**Recommended:**
- `changelog.txt` — version history for the in-game mod browser. [Mod Structure](https://lua-api.factorio.com/latest/auxiliary/mod-structure.html)
- `thumbnail.png` — portal/in-game thumbnail (ideally 144x144px). [Mod Structure](https://lua-api.factorio.com/latest/auxiliary/mod-structure.html)
- `LICENSE` — plaintext copy of the mod's license. [User:Pongles/Mod Portal](https://wiki.factorio.com/User:Pongles/Mod_Portal)

**Optional subfolders:**
- `locale/` — one subfolder per language (e.g. `en`, `de`) with `*.cfg` files. [Mod Structure](https://lua-api.factorio.com/latest/auxiliary/mod-structure.html)
- `migrations/` — migration scripts for data changes between versions. [Mod Structure](https://lua-api.factorio.com/latest/auxiliary/mod-structure.html)

### Zip Naming

`{mod-name}_{version-number}.zip` (e.g. `better-armor_0.3.6.zip`). [Mod Structure](https://lua-api.factorio.com/latest/auxiliary/mod-structure.html)

## 4. changelog.txt

### Required?

Not required for portal upload. The portal displays `changelog.txt` as plain text regardless of format. [Changelog Format](https://lua-api.factorio.com/latest/auxiliary/changelog-format.html)

For the **in-game mod browsing GUI** to render the changelog, the file must follow strict formatting. [Changelog Format](https://lua-api.factorio.com/latest/auxiliary/changelog-format.html)

### Format

One or more version sections:

1. **Version section start:** a line of exactly 99 dashes: `---------------------------------------------------------------------------------------------------`
2. **Version line:** must start with exactly `Version: ` (note the space). Format `number.number.number`; each number `0`–`65535`; `0.0.0` is invalid.
3. **Date line (optional):** must start with exactly `Date: `. No format restrictions.
4. **Categories:** arbitrary categories (Features, Bugfixes, Balancing, etc.) with arbitrary entries under each.

**Rules:**
- No tabs
- No trailing whitespace
- The line after the version section start must not be empty
- Completely empty lines are skipped by the parser [Changelog Format](https://lua-api.factorio.com/latest/auxiliary/changelog-format.html)

### Example

```
---------------------------------------------------------------------------------------------------
Version: 1.1.6
Date: 06. 06. 2022
  Features:
    - This is an entry in the "Features" category.
    - This is another entry in the "Features" category.
  Balancing:
    - Some balancing change.
```
[Changelog Format](https://lua-api.factorio.com/latest/auxiliary/changelog-format.html)

### In-Game Presentation

The in-game mod browser parses `changelog.txt` per the strict format and shows version sections to users viewing mod updates. Without proper formatting, the changelog will not display correctly in-game. [Changelog Format](https://lua-api.factorio.com/latest/auxiliary/changelog-format.html)

## 5. In-Game Update Mechanism

### Detection

The in-game mod browser queries the Mod Portal API and compares versions. [Mod Portal API](https://wiki.factorio.com/Mod_portal_API)

### API Endpoints

- `/api/mods` — list of mods with optional filtering by version, category, tags. [Mod Portal API](https://wiki.factorio.com/Mod_portal_API)
- `/api/mods/{mod_name}` — short info for a specific mod. [Mod Portal API](https://wiki.factorio.com/Mod_portal_API)
- `/api/mods/{mod_name}/full` — detailed info including dependencies. [Mod Portal API](https://wiki.factorio.com/Mod_portal_API)

The API accepts a `version` parameter (e.g. `"2.0.76"`) to filter by compatibility. Incompatible mods are marked "deprecated". [Mod Portal API](https://wiki.factorio.com/Mod_portal_API)

### What Authors Must Do

Update detection is **automatic**. The author only needs to:

1. Upload a new version zip to the portal (web UI or API)
2. Increment the `version` field in `info.json`
3. Optionally update `changelog.txt` for the new version

The in-game browser will detect the new version and offer to update. No additional action required. [Modding](https://wiki.factorio.com/Modding)

## 6. Thumbnail / Preview Image

### Required?

Not required for upload. Mods without a thumbnail default to `/assets/.thumb.png`. [Mod Portal API](https://wiki.factorio.com/Mod_portal_API)

Including one is highly recommended for visibility and UX.

### Dimensions / Format

- Recommended: 144x144 pixels. [Mod Structure](https://lua-api.factorio.com/latest/auxiliary/mod-structure.html)
- Format: PNG
- Location: root of the mod folder, named `thumbnail.png`. [User:Pongles/Mod Portal](https://wiki.factorio.com/User:Pongles/Mod_Portal)

Additional images can be uploaded via the portal web UI's "Gallery" section or the Mod Images API. [User:Pongles/Mod Portal](https://wiki.factorio.com/User:Pongles/Mod_Portal) [Mod Images API](https://wiki.factorio.com/Mod_images_API)

## 7. Tagging / Categories

### Categories

Set via the web UI or API — **not** in `info.json`.

- `no-category`
- `content` — new content
- `overhaul` — total conversion
- `tweaks` — small balance/gameplay/graphics changes
- `utilities` — new tools or interface adjustments
- `scenarios` — scenarios, maps, puzzles
- `mod-packs` — curated collections
- `localizations` — translations for other mods
- `internal` — Lua libraries for other mods [Mod Details API](https://wiki.factorio.com/Mod_details_API)

### Tags

Additional categorization. Examples: `transportation`, `logistics`, `trains`, `production`, `power`, `storage`, `combat`, `logistic-network`, `circuit-network`, `blueprint`, `map-generation`, `science-pack`, `enemy`, `compatibility`, `cheat`, `helper`, `roleplay`, `expansion-space-age`. [Mod Details API](https://wiki.factorio.com/Mod_details_API)

### Where Set

- Web UI "Create New Mod" page (Category field). [User:Pongles/Mod Portal](https://wiki.factorio.com/User:Pongles/Mod_Portal)
- Mod Publish API (optional `category` and `license`). [Mod Publish API](https://wiki.factorio.com/Mod_publish_API)
- Mod Details API (optional `category` and `tags`). [Mod Details API](https://wiki.factorio.com/Mod_details_API)

## 8. Versioning & factorio_version Compatibility

### One Major Version Per Mod

A mod is compatible with only one major version. `"2.0"` covers all 2.0.x releases and no other majors. To support a new major, update `factorio_version`. [Mod Structure](https://lua-api.factorio.com/latest/auxiliary/mod-structure.html)

### Separate Zips per factorio_version

Not possible under a single mod name — each mod has a single `factorio_version` field. To support multiple majors, either publish separate mod entries with different names, or update the single mod's `factorio_version` when porting.

### In-Game Filtering

The in-game browser filters by compatibility via the `version` parameter. Incompatible mods are marked "deprecated" and hidden by default (unless `hide_deprecated=false`). [Mod Portal API](https://wiki.factorio.com/Mod_portal_API)

### Exception

`factorio_version` `"0.18"` mods are also loadable in 1.0, and the portal returns them when queried for `"1.0"` mods. [Mod Structure](https://lua-api.factorio.com/latest/auxiliary/mod-structure.html)

## 9. License & Source

### License Field

Not required in `info.json`. A `LICENSE` plaintext file in the mod folder is recommended in case the mod is distributed outside the portal. [User:Pongles/Mod Portal](https://wiki.factorio.com/User:Pongles/Mod_Portal)

The license can also be set on the portal via web UI or API (optional `license` parameter). [Mod Publish API](https://wiki.factorio.com/Mod_publish_API) [Mod Details API](https://wiki.factorio.com/Mod_details_API)

### Supported Standard Licenses

- `default_mit` — MIT
- `default_gnugplv3` — GPLv3
- `default_gnulgplv3` — LGPLv3
- `default_mozilla2` — MPL 2.0 [Mod Details API](https://wiki.factorio.com/Mod_details_API)

### Source Hosting

Not required, but recommended. The portal provides an optional `source_url` field, and the web UI has a "Github path" field. [Mod Details API](https://wiki.factorio.com/Mod_details_API) [User:Pongles/Mod Portal](https://wiki.factorio.com/User:Pongles/Mod_Portal)

## 10. Common Pitfalls / Rejection Reasons

### Upload Rejection (Mod Publish API error codes)

- `InvalidModRelease` — invalid release data in `info.json` (wrong `factorio_version`, invalid version format, missing required fields). [Mod Publish API](https://wiki.factorio.com/Mod_publish_API)
- `InvalidModUpload` — invalid mod data in zip (wrong zip structure, missing `info.json`). [Mod Publish API](https://wiki.factorio.com/Mod_publish_API)
- `ModAlreadyExists` — mod name already exists on the portal. [Mod Publish API](https://wiki.factorio.com/Mod_publish_API)
- `InvalidApiKey` — missing or invalid API key. [Mod Publish API](https://wiki.factorio.com/Mod_publish_API)
- `InvalidRequest` — invalid request format. [Mod Publish API](https://wiki.factorio.com/Mod_publish_API)

### Game Load Failures

- Wrong `factorio_version` — game logs an error and refuses to load the mod. [Tutorial:Modding FAQ](https://wiki.factorio.com/Tutorial:Modding_FAQ)
- Trailing commas in JSON — game logs an error and refuses to load. [Tutorial:Modding FAQ](https://wiki.factorio.com/Tutorial:Modding_FAQ)
- Wrong dependency format — errors in the log. [Tutorial:Modding FAQ](https://wiki.factorio.com/Tutorial:Modding_FAQ)
- Mod name with spaces — portal rejects. [Tutorial:Modding FAQ](https://wiki.factorio.com/Tutorial:Modding_FAQ)
- Third number in `factorio_version` — portal rejects. [Mod Structure](https://lua-api.factorio.com/latest/auxiliary/mod-structure.html)

### Other Issues

- Missing description — not strictly required, but hurts discoverability and UX.
- Bundled base-game assets — may cause copyright or technical issues.
- Circular dependencies — not allowed; if another mod requires yours, you cannot require it. [Tutorial:Modding FAQ](https://wiki.factorio.com/Tutorial:Modding_FAQ)

---

## Checklist for Publishing LilEinstein

Grounded in the current state of the mod repo.

### info.json — verify each field

Current `info.json`:

```json
{
  "name": "LilEinstein",
  "version": "1.0.0",
  "title": "LilEinstein",
  "author": "TheSilentWarrior",
  "factorio_version": "2.1",
  "dependencies": [
    "base >= 2.1.0",
    "! some-autoresearch",
    "! UltimateResearchQueue2",
    "(?) simultaneous-research >= 0.7.5",
    "! paralell-lab",
    "(?) Ultracube"
  ],
  "description": "Runs the research queue for you: picks the next technology, watches your science supply, and switches research when a pack runs dry."
}
```

- [x] `name`: `LilEinstein` — valid (alphanumeric, no spaces)
- [x] `version`: `1.0.0` — valid `number.number.number`; first public release
- [x] `title`: `LilEinstein` — human-readable
- [x] `author`: `TheSilentWarrior` — matches the portal account name
- [x] `factorio_version`: `"2.1"` — correct format, no third number
- [x] `dependencies` — valid syntax; required, optional (`?`), incompatible (`!`), and version constraints all used correctly
- [x] `description` — present; one spoken sentence, synced with the README hook
- [ ] `homepage` — **add** (e.g. GitHub repo URL or `website/` landing page URL)
- [ ] `contact` — **add** (email, Discord, or GitHub issues URL)

### changelog.txt

Current file already follows the strict format (99-dash separator, `Version: `, `Date: `, categorized entries, no tabs).

- [x] Version sections start with exactly 99 dashes
- [x] Version lines start with exactly `Version: ` (with space)
- [x] No tabs
- [x] No trailing whitespace
- [x] Line after version section start is not empty
- [x] Current `Version: 1.0.0` entry is valid
- [x] Unpublished internal history (`0.1.0`, `1.4.0`, `1.5.0`) is folded into the single `1.0.0` entry

### thumbnail.png

- [x] `thumbnail.png` exists in mod root
- [x] Dimensions are 144x144px
- [ ] Verify it renders well at small sizes in the in-game browser

### LICENSE

- [x] `LICENSE` exists and is MIT
- [ ] Set portal license to `default_mit` on upload (web UI or API)

### Zip Packaging

`publish.json` is the authoritative whitelist; `factorio-prepare` stages it into `publish/<name>_<version>/` and runs the secrets scan.

- [ ] Build zip as `LilEinstein_1.0.0.zip`
- [ ] Include a top-level folder `LilEinstein_1.0.0/` inside the zip containing all mod files
- [ ] Include: `info.json`, `control.lua`, `data.lua`, `settings.lua`, `changelog.txt`, `thumbnail.png`, `README.md`, `LICENSE`, `locale/`, `graphics/icons/*.png`, `graphics/ui/*.png`, `data/*.lua`, `lib/*.lua`, `model/` Lua modules, `view/` Lua modules
- [ ] **Exclude** dev-only artifacts: `.git/`, `docs/`, `audit/`, `output/`, `website/`, `scripts/`, `tests/`, `AGENTS.md`, every `*.md` except `README.md`, `RESEARCH_AUTOPILOT_IMPLEMENTATION.md`, `standard.md`, `publish.json`, `publish/`, and unreferenced graphics
- [ ] Verify the zip opens and `info.json` is at `LilEinstein_1.0.0/info.json`

### Account & Upload

- [ ] Confirm Factorio.com account exists and is linked to a verified purchase
- [ ] Log in to mods.factorio.com and verify "Submit mod" is available
- [ ] (Optional) Generate an API key at https://factorio.com/profile with `ModPortal: Publish Mods` for CLI uploads

### Portal Metadata (set on web UI or via API)

- [ ] Category: `utilities`
- [ ] Tags: tick on the edit page. The portal tag vocabulary is a fixed list of slugs (visible as `/?tag=<slug>` links on any mod page); pick only what a player would filter by. Do not trust tag names written down here.
- [ ] Long description in Markdown (`description=<README.md` on first publish)
- [ ] `summary`: one spoken sentence, matching the `info.json` description
- [ ] `source_url`: GitHub repository URL
- [ ] `license`: `default_mit` (portal ID, not the SPDX name `MIT`)
- [ ] Gallery images: screenshots of the Research control center

### Upload

- [ ] Review the staged `publish/LilEinstein_1.0.0/` manifest file by file and confirm every entry is game or portal content
- [ ] Get an explicit publication sign-off from the owner before any upload runs
- [ ] Go to mods.factorio.com → "Submit mod" (or `factorio-publish` with the API key)
- [ ] Upload `LilEinstein_1.0.0.zip`
- [ ] Fill in description, category, tags, license, source URL
- [ ] Upload gallery images
- [ ] Submit and wait ~5 minutes for propagation to the in-game portal

### Post-Publish Verification

- [ ] Mod appears on mods.factorio.com
- [ ] In-game mod browser can find and download it
- [ ] Install and basic functionality test
- [ ] Changelog displays correctly in-game

### Future Updates

For each new release:
1. Increment `version` in `info.json`
2. Add a new version section to `changelog.txt` (99-dash separator, `Version: `, `Date: `, categories)
3. Rebuild the zip as `LilEinstein_{version}.zip`
4. Upload via web UI ("My Mods" → existing mod → upload new version) or Mod Publish API
5. The in-game browser detects the new version automatically — no other action needed

### Notes Specific to LilEinstein

- `factorio_version: "2.1"` covers all 2.1.x releases and no other major.
- Comprehensive locale support (en, de, fr, pt-PT) is a plus for portal visibility.
- No migration scripts: the mod has no public save history to migrate from.
- The mod is MIT; match the portal license field to `default_mit`.

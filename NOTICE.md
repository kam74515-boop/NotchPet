# NotchPet — Licensing & Attribution Notice

**NotchPet** is an AI efficiency-island notch app for macOS. It is a **fork and
derivative work of [boring.notch](https://github.com/TheBoredTeam/boring.notch)**
by **TheBoredTeam**, and it incorporates code, protocol logic, and/or art assets
adapted from **[clawd-on-desk](https://github.com/rullerzhou-afk/clawd-on-desk)**
by **rullerzhou**.

## License of the combined work: AGPL-3.0-only

- `boring.notch` is licensed under **GNU GPL-3.0** (see [`LICENSE`](LICENSE)).
- `clawd-on-desk` is licensed under **GNU AGPL-3.0-only** (full text in
  [`LICENSE.AGPL-3.0.txt`](LICENSE.AGPL-3.0.txt)).
- Because NotchPet combines GPL-3.0 code with AGPL-3.0 code/assets, **the
  combined work is distributed under the GNU Affero General Public License,
  version 3 (AGPL-3.0-only)**. GPLv3 §13 and AGPLv3 §13 explicitly permit this
  combination; the portions originating from boring.notch remain available under
  GPL-3.0-or-later, while the work as a whole is offered under AGPL-3.0.
- **AGPL §13 (network use):** if you run a modified version of this software and
  let other users interact with it over a network, you must offer those users
  access to the corresponding source code of your modified version.

> ⚠️ Consequence: NotchPet **cannot be closed-source** and is **not eligible for
> the Mac App Store** (non-sandboxed helper + copyleft terms). It is, and must
> remain, free/open-source software.

## Modifications

This is a **modified version** of boring.notch. Notable changes by the NotchPet
project include: rebranding to "NotchPet"; addition of nook-x-style efficiency
modules (Pomodoro, to-do, weather, notes, lyrics view, quick launcher, photo
browser, health reminders, quick actions); and an AI coding-agent task-sync
subsystem (local event listener + Claude Code hook installer + desktop pet)
re-derived from clawd-on-desk. See the git history for per-file change dates.

## Attributions

| Component | Author | License |
|-----------|--------|---------|
| boring.notch (base app) | TheBoredTeam | GPL-3.0 |
| clawd-on-desk (AI agent sync, pet concept & assets) | rullerzhou | AGPL-3.0-only |
| OpenClaw pixel-lobster icon (via clawd-on-desk) | Peter Steinberger (2025) | MIT |

Third-party libraries and smaller components retain their own licenses; see
[`THIRD_PARTY_LICENSES`](THIRD_PARTY_LICENSES).

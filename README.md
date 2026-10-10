# SpotFriends

Spot your friends in a crowd. SpotFriends puts an icon next to the nameplates of your Battle.net
and character friends in **World of Warcraft: Forever**, and, if you like, next to the people in
your party or raid.

- Every friend gets the default icon (Gold Spot), or one you pick for them.
- Any character can get an icon by name, friend or not, straight from the right-click menu on
  their portrait.
- Party and raid members who are not friends get the group icon (Blue Spot).
- The icon sits just before the name, or after the nameplate's health bar and level badge.
- 26 icons: stars, friend badges, crescents, hearts and spots.

Built for crowded cities: hundreds of nameplates come and go every few seconds, and SpotFriends
does almost nothing for the ones that are not yours to mark.

## Installing

1. Download the latest release, or **Code > Download ZIP** on this page.
2. Unzip it into `World of Warcraft\_classic_beta_\Interface\AddOns\`.
3. The folder must be named **`SpotFriends`** (a GitHub ZIP unpacks as `SpotFriends-main`:
   rename it).
4. Restart the game fully (a `/reload` does not pick up a new addon).

Made for the WoW: Forever beta (interface 16001). It needs no other addon.

## Using it

Open the settings from **Options > AddOns > SpotFriends**, the **minimap button**, the AddOn
Compartment button, or `/spotfriends` (`/sf`).

| Setting | What it does |
|---|---|
| Show icons on friends' nameplates | Everything on or off; a middle-click on the minimap button does the same. |
| Default icon | What every friend gets. None shows icons only where you chose one. |
| Position | Left, before the name; or right, after the nameplate. |
| Size, offsets | The icon's size (14 by default) and a nudge in each direction. A preview shows each nameplate look the game has. |
| Mark people in my group | Party and raid members who are not friends get the group icon, chosen beside it. |
| The game's nameplates | Shortcuts to the game's own friendly-nameplate settings: show them, names only, distance. |
| Friends | Every Battle.net and character friend with their icon. Click to choose, right-click for the default. |
| Characters | Icons by character name. **Clear list** empties it. |
| Defaults | Every setting back to its default. The minimap button stays where you dragged it. |

**Right-click a player's portrait** (target, focus, party or raid frame) for **Add to
SpotFriends** / **Remove from SpotFriends** and **SpotFriends Icon**, a list of every icon like the
game's Target Marker Icon.

When several rules apply, the first wins:

1. an icon chosen for the character by name;
2. the friend's own icon, or the default icon (a friend set to None stays without one, even in
   your group);
3. the group icon.

### Commands

```
/spotfriends          the settings
/spotfriends test     the default icon on every player's nameplate, to try the placement
/spotfriends debug    what the addon sees: friends, the group, the game's settings, each player nameplate
/spotfriends plate    the parts of your target's nameplate, as sizes and anchors
/spotfriends reset    every setting back to its default
```

## What it cannot do

- **Names far away.** Beyond nameplate range, or with friendly nameplates off, the game draws the
  name itself, and no addon can put anything beside it. The icon needs a nameplate: turn on
  friendly players' nameplates (and Names Only for the name-only look) on the settings page.
- **Dungeons and raids.** Friendly nameplates there are protected; addons cannot touch them.
- **Secret values.** Where the game hides a unit's name or identity from addons, that nameplate
  gets no icon.

## Reporting a problem

Turn on Lua errors (`/console scriptErrors 1`), reproduce the problem, and open an issue with the error
and the output of `/spotfriends debug`. For an icon in the wrong place on a nameplate, target that
player and add `/spotfriends plate`: the game does not tell addons where a nameplate is, so the
icon is placed from the nameplate's parts, and that list shows them.

## Development

- Plain Lua, no build step. Files load in the order `SpotFriends.toc` lists them; `embeds.xml`
  loads the libraries first.
- `Icons.lua`, `Resolver.lua` and `Layout.lua` make no calls to the game, so the tests run them
  directly. `Nameplates.lua` hooks the game's nameplates; `Options.lua` is the settings page;
  `UnitMenu.lua` the right-click entries; `MinimapButton.lua` the minimap button.
- **Tests** run in Lua 5.1 through [lupa](https://pypi.org/project/lupa/), no game needed:

  ```
  pip install lupa
  python tests/run.py           # every test, plus a syntax check of every addon file
  python tests/run.py -v layout # one file, with its output
  ```

  `tests/addon_test.lua` loads the whole addon against a stand-in for the game
  (`tests/client_stub.lua`) and drives the settings page, the right-click menu, the minimap button
  and the nameplates.
- **Icons**: `tools/convert-icons.py` turns the 1254 px renders (kept outside the repository) into
  the 128 px PNGs in `Textures/`, and holds each icon's key and label. Keys are saved in players'
  settings: rename one only with an entry in `Icons.RENAMED`.
- **Saved settings** (`SpotFriendsDB`) carry a `version`; `SF.Migrate` in `Core.lua` moves
  untouched old defaults to new ones.
- The game refuses addons any nameplate position (`GetLeft`, `GetRight`... raise "Can't measure
  restricted regions"), and registering an event the client does not know aborts the whole file.
  The code reads sizes and anchors only, and registers each event on its own in a `pcall`.

## Credits

Bundled libraries, each under its own terms, in `Libs/`:
[LibStub](https://www.wowace.com/projects/libstub),
[CallbackHandler-1.0](https://www.wowace.com/projects/callbackhandler),
[LibDataBroker-1.1](https://github.com/tekkub/libdatabroker-1-1) and
[LibDBIcon-1.0](https://www.wowace.com/projects/libdbicon-1-0).

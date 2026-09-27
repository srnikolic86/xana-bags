# XanaBags

Marks gear in your bags for World of Warcraft: Forever (these are the default
colours; see [Changing the colours](#changing-the-colours)):

- **Green border:** you can equip it, and it's an upgrade.
- **Yellow border:** you can equip it, but it isn't an upgrade.
- **Red border:** you can't equip it (yet).
- **Grey border:** junk (poor quality), whatever else it is.
- **Brown border:** food.
- **Light blue border:** drink.
- **Purple border:** it's new since you last closed your bags. On gear, food
  and drink only the left half is purple; the right half keeps its colour.

Version 0.11.0, written for the WoW Forever beta (interface 16001).
Not yet tested in game.

## Installing

1. Put the `XanaBags` folder in your Forever client's `Interface/AddOns` folder.
   The folder must be named exactly `XanaBags` and contain `XanaBags.toc`
   and `XanaBags.lua`.
2. Start the game (or type `/reload` if it is already running).
3. If the addon list says it is out of date, tick "Load out of date AddOns".

## How it decides

The game shows every requirement you don't meet in red in an item's tooltip.
XanaBags uses the same information: an item gets a red border if its tooltip
has any red line, for example:

- the required level is higher than yours
- it is an armor or weapon type you can't use (plate on a mage, a two-handed
  sword on a character without the skill)
- it is limited to other classes
- it needs a profession you don't have (engineering goggles, for example)

A red durability line (a broken item) doesn't count, because broken gear can
still be equipped.

Gear you can equip is then compared with what you're wearing, by item level:

- It's an **upgrade** (green) if its item level is higher than the item in
  that slot, or if that slot is empty.
- For rings and trinkets it is compared with the weaker of your two. The same
  goes for one-handed weapons if your character can dual wield; otherwise they
  are compared with your main hand only.
- Two-handed weapons are compared with your main hand.
- Only item level counts, not stats. An item with a higher item level but the
  wrong stats for your class (strength on a mage, say) still shows green.

Only gear gets a border. Bags and quivers, and items that aren't equippable at
all, are left alone. Borders update when your bags change, when you change
equipment, when you level up and when you learn a new weapon or armor skill.

## Junk

Poor (grey) quality items get a grey border, so vendor trash is easy to spot.
Junk is checked first, so a grey-quality weapon shows the junk border rather
than a gear colour, and gets no stat dots.

## Food and drink

Food gets a brown border and drinks a light blue one. XanaBags tells them apart
by the item's use effect, which the game calls "Food" or "Drink" (the effect
that makes you sit and eat or drink). Items that are both at once use a
different effect and get no border.

## Stat dots

Gear you can equip (green or yellow border) also gets small coloured dots in
the lower left corner of its icon, one for each stat that is higher than on
the equipped item it would replace:

| Dot    | Stat      |
|--------|-----------|
| Red    | Strength  |
| Blue   | Intellect |
| Green  | Agility   |
| Pink   | Spirit    |
| Orange | Stamina   |
| Grey   | Armor     |

The dots always appear in that order, filling a small grid in the corner:
three across, the bottom row first. The item it's
compared with is the same one the upgrade check uses: for rings, trinkets and
(if you can dual wield) one-handed weapons, the weaker of your two. If that
slot is empty, every one of these stats the item has gets a dot. No dots means
none of these is higher.

You can switch off the dots for stats your character doesn't care about, so
only the useful ones show. A mage might keep only Intellect, Spirit and
Stamina:

```
/xbags stat strength off
/xbags stat agility off
```

- `/xbags stats` shows which dots are on.
- `/xbags stat <stat> on|off` switches one; `/xbags stat all on|off` switches
  them all.
- Stat names can be shortened to three letters (`/xbags stat str off`).
- Like the colours, this is saved per character, in the "XanaBags" macro.

## New items

When you close your bags, XanaBags notes how many of each item you have. Next
time you open them, everything you now have more of gets a purple border: new
loot, quest rewards, purchases, and stacks that grew. The purple stays while
the bags are open, so you can find everything, and goes away once you close
them.

- Equipped gear is counted too, so taking gear off doesn't make it "new".
- Moving items around inside your bags doesn't make them new.
- Items taken out of the bank or mailbox do count as new.
- Everything you carry when you log in counts as seen. "New" isn't kept
  between sessions, because the Forever beta doesn't reload addon data.
- `/xbags seen` marks everything as seen without closing the bags.

## Sorting

Your bags are sorted every time you open them, so items of the same type stay
together. This is the game's own bag cleanup, the one behind the "Clean Up
Bags" button, so items end up grouped the way the game groups them.

- `/xbags sort off` stops sorting on open; `/xbags sort on` turns it back on.
- `/xbags sort` sorts once, right now.
- Sorting is skipped in combat and while you're holding an item on the cursor.
- The setting is saved per character, in the "XanaBags" macro.

## Changing the colours

Every colour can be changed, the borders and the stat dots alike.

- `/xbags colors` lists them, each shown in its current colour.
- `/xbags color <name> <hex>` changes one. The colour is 6 hex digits, the
  same as in web colours (for example `/xbags color food 8b5a2b`, or
  `/xbags color new ff00ff`).
- `/xbags color <name> reset` puts one back; `/xbags color reset` puts all of
  them back.

Names can be shortened to their first three letters.

| Name         | Colours                                   | Default   |
|--------------|-------------------------------------------|-----------|
| `upgrade`    | Border: gear you can equip, an upgrade    | green     |
| `equippable` | Border: gear you can equip, not upgrade   | yellow    |
| `unusable`   | Border: gear you can't equip              | red       |
| `new`        | Border: new items                         | purple    |
| `food`       | Border: food                              | brown     |
| `junk`       | Border: poor quality items                | grey      |
| `drink`      | Border: drink                             | light blue |
| `strength`   | Dot: higher Strength                      | red       |
| `intellect`  | Dot: higher Intellect                     | blue      |
| `agility`    | Dot: higher Agility                       | green     |
| `spirit`     | Dot: higher Spirit                        | pink      |
| `stamina`    | Dot: higher Stamina                       | orange    |
| `armor`      | Dot: higher Armor                         | grey      |

Colours are saved per character in a character-specific macro named
"XanaBags" (its body is a single `/xbagdata ...` line), because the Forever
beta doesn't reload addon settings between sessions. It only holds the colours
you changed, the stat dots you switched off and the sorting setting, and is
created the first time you change any of them. Don't delete or
edit it; renaming it or changing its icon is fine.

## Copying settings to another character

1. On the character whose colours and dots you want to copy, run
   `/xbags export`.
2. Click the box in the window that opens (that selects the whole string) and
   press Ctrl+C.
3. On the other character, run `/xbags import`, click the box, press Ctrl+V
   and click Import.

Importing replaces all colour and dot settings on that character: anything the
string doesn't change goes back to its default. Export strings start with
`XG1:`; strings from XanaBars (`XB1:`) or XanaRings (`XR1:`) are refused.

## Commands

| Command          | Description                                                  |
|------------------|--------------------------------------------------------------|
| `/xbags`         | Show the commands                                            |
| `/xbags colors`  | List the colours and what each one means                     |
| `/xbags color <name> <hex \| reset>` | Change a colour, or put it back to default |
| `/xbags color reset` | Put all colours back to default                          |
| `/xbags stats`   | Show which stat dots are on                                  |
| `/xbags stat <stat \| all> on\|off` | Show or hide a stat's dot (or all of them) |
| `/xbags export`  | Show the colour and dot settings as a string you can copy    |
| `/xbags import`  | Paste a string from `/xbags export` to use its settings      |
| `/xbags sort`    | Sort the bags now                                            |
| `/xbags sort on\|off` | Sort the bags whenever they open (on by default)        |
| `/xbags refresh` | Recheck every item                                           |
| `/xbags seen`    | Mark everything as seen now (clears the purple borders)      |
| `/xbags frame`   | Name the window under the cursor (useful for bug reports)    |

## Known limitations

- XanaBags works with the standard bag windows. If the Gamepad UI shows your
  bags in a window of its own, the borders may not appear there. In that case,
  open your bags, point the cursor at an item, type `/xbags frame` and report
  what it prints, so support for that window can be added.
- The bank is not covered yet.
- An item whose data the game hasn't loaded yet gets its border a moment
  later, once the data arrives.
- Borders and dots are drawn as plain textures in one frame per bag window,
  never as frames on the bag buttons themselves. Frames on the buttons made
  the Gamepad UI recalculate what its cursor can interact with, which got the
  addon blocked.

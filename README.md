# XanaBags

Gives the items you choose in your bags and bank a colored border, for World of Warcraft:
Forever.

Version 0.19.0, written for the WoW Forever beta (interface 16001).
Not yet tested in game.

## Installing

1. Put the `XanaBags` folder in your Forever client's `Interface/AddOns` folder.
   The folder must be named exactly `XanaBags` and contain `XanaBags.toc`
   and `XanaBags.lua`.
2. Start the game (or type `/reload` if it is already running).
3. If the addon list says it is out of date, tick "Load out of date AddOns".

## Coloring an item

With a gamepad, select an item in your bags or bank and press **R3** (right stick
click). With a mouse, hold **Alt** and click it with either button. It's the same
window both ways, and it opens beside the item:

| Gamepad | Action                                        |
|---------|-----------------------------------------------|
| D-pad   | Move between colors (the gold frame)          |
| A       | Give the item that color and close the window |
| X       | Remove the item's color and close the window  |
| B or R3 | Close the window without changing anything    |

The window can't open from the gamepad in combat, and closes when combat starts.
R3 goes back to its normal use when your bags and bank are closed, and A, B, X and
the D-pad as soon as the window closes.

With a mouse, however you opened the window:

- **Previous colors:** click one to give it to the item. The item's current
  color has a white frame.
- **Colors:** a fixed set of 20. Click one to give it to the item. It then joins
  your previous colors.
- **New color:** opens the game's color picker. The item's border follows your
  choice as you pick. OK keeps the color and adds it to the previous colors;
  Cancel puts everything back and returns to the window.
- **Remove:** takes the border off the item.
- **Close:** closes the window without changing anything.

The color belongs to the item, not the bag slot. It follows the item when it
moves, every stack of that item has it, and it comes back if you get rid of the
item and later get another one.

The window remembers your 20 most recently used colors, newest first. A color
that drops off the list stays on any items using it.

## Sorting

Each time your bags go from closed to open, XanaBags moves items into this order,
starting at the top left:

1. The color group your hearthstone has, if you colored it.
2. The other color groups.
3. Quest items without a color.
4. Everything else, with no gaps. These aren't sorted, and some may
   change places as colored items move past them.
5. The empty slots.

Within a color group and among the quest items, items are sorted by name, with
the fullest stack first. A quest item you colored goes with its color. Quest items
are those the game marks as such, including items that start a quest. An ordinary
item a quest happens to ask for doesn't count.
Stacks of the same item may merge as they move.

- If no item has a color and none is a quest item, nothing moves.
- Sorting doesn't start or continue in combat, while you hold an item or are
  targeting with a spell, or while the color picker is open. It also stops if
  you close the bags. It starts over the next time you open them.
- Soul bags, herb bags, quivers and other special bags are left alone.
- Changing a color doesn't re-sort until you next open the bags.

## The bank

The bank works like your bags: colored borders, R3, Alt+click, and the same
sort order each time you open it, covering the main bank and any normal bank bags.

The bags and the bank each sort on their own. Nothing moves between them, so a
colored item in your bags stays in your bags. Opening the bank usually opens your
bags too, so both sort.

If the bank doesn't get borders or doesn't sort, open it, point at an item, type
`/xbags bank` and report what it prints.

## Seeing your bank from anywhere

Each time you visit a bank, XanaBags remembers what's in it, and keeps the list
up to date as you put items in and take them out. To see the list anywhere in the
world, make a macro containing this line and put it on your action bar:

```
/xbank
```

Running it opens a window listing everything from your last visit, and running it
again closes it. The Close button also closes it.

- Items you've colored come first, each with its color around its icon, in the
  same order the sort uses. The rest follow by name.
- The number on the right is how many you had in total, across all stacks.
- Point at an item with the mouse to see its tooltip. There's no tooltip from the
  gamepad, because the list has no gamepad selection.
- It covers the main bank and all bank bags, including special bags.
- It works in combat.
- The list belongs to the character, and survives logging out.
- If you change an item's color, the window shows the new color.
- The window never scrolls. With many items it uses more columns, and shrinks a
  little if they wouldn't otherwise fit across the screen.
- An item with a random suffix ("of the Bear") is listed under its base name, and
  its tooltip shows the base item.

## How it is saved

Colors are saved per character, in character-specific macros named "XanaBags",
"XanaBags 2" and so on, because the Forever beta doesn't reload addon settings
between sessions. Each macro holds about 30 items, and uses one of your
character's macro slots. If the slots are full, XanaBags says so in chat, and
colors that don't fit are lost at logout.

Don't delete or edit these macros; renaming them or changing their icons is
fine. A macro left over from an older XanaBags is reused by the first save, and
its old settings are replaced.

The bank list is saved the same way, in macros named "XanaBags Bank", "XanaBags
Bank 2" and so on. Each holds about 25 different items, so a very full bank can
take 6 macro slots. If the slots are full, XanaBags says so in chat, the list is
still complete until you log out, and the part that didn't fit is lost at logout.
A new color also needs a free slot once its macro is full, so leave one spare.

## Known limitations

- Only the standard bag and bank windows are covered, not a bag window of the
  Gamepad UI's own, if there is one.
- Items with the same item ID always share a color.
- Borders are drawn as plain textures in one frame per bag window, never as
  frames on the bag buttons themselves. Frames on the buttons made the Gamepad
  UI recalculate what its cursor can interact with, which got the addon blocked.

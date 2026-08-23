# Recording demo.gif — a fast parade of the newer engine features, running
# inside the author's own Neovim configuration (see flake.nix).
#
#   nix develop .#demo -c vhs demo.tape
#
# The tour (demo-tour.lua) is registered live through :Tutorial load — the
# portable-file loader gets screen time too — and then shows off the menu
# filter and tags, hint ladders, recall masking, and mistake corrections.

Output demo.gif
Set Width 1700
Set Height 850
Set FontSize 22
Set Padding 32
Set Margin 20
Set MarginFill "#11111b"
Set WindowBar Rings
Set BorderRadius 10
Set Theme "Catppuccin Mocha"
Set Framerate 24
Set TypingSpeed 60ms
Set Shell bash

Require nvim

# Launch Neovim in a throwaway directory with every XDG dir sandboxed
# inside it: progress must never leak into, or resume from, the real
# ~/.local/share/nvim between recordings. The demo tour rides along.
Hide
Type@250ms "D=/tmp/opencode/tutorial-demo; rm -rf $D; mkdir -p $D && cp $(pwd)/demo-tour.lua $D/ && cd $D && XDG_CONFIG_HOME=$D/config XDG_DATA_HOME=$D/data XDG_STATE_HOME=$D/state XDG_CACHE_HOME=$D/cache nvim"
Enter
Wait+Screen /Quit NVIM/
Sleep 1500ms
Show
Sleep 800ms

# Leave the dashboard for a plain workspace.
Type ":enew"
Enter
Sleep 400ms

# Register the showcase tour through the file loader, then open the menu.
Type ":Tutorial load demo-tour.lua"
Enter
Sleep 700ms

Type ":Tutorial"
Enter
Wait+Screen /TUTORIALS/
Sleep 900ms

# Filter by substring; only the tagged showcase tour survives.
Screenshot .shots/01-menu.png
Type "/new"
Enter
Wait+Screen /filter: new/
Sleep 900ms

Screenshot .shots/02-filter.png

Enter
Wait+Screen /WHAT'S NEW/
Sleep 700ms

# Give the walkthrough a quiet workspace beside the panel.
Type ":enew"
Enter
Sleep 400ms
Type ":wincmd h"
Enter
Sleep 400ms

# 1. Hint ladder: one nudge per press of h, wrapping back to hidden.
Type "h"
Sleep 800ms
Type "h"
Wait+Screen /Rung two/
Sleep 800ms
Screenshot .shots/03-ladder.png
Type "h"
Sleep 600ms
Type "d"
Wait+Screen /1\/3/
Sleep 500ms

# 2. Recall masking: the answer hides until asked for.
Wait+Screen /\[hidden\]/
Sleep 600ms
Screenshot .shots/04-recall.png
Type "h"
Wait+Screen /DemoReveal/
Sleep 800ms
Screenshot .shots/05-reveal.png
Type ":wincmd l"
Enter
Sleep 300ms
Type ":DemoReveal"
Enter
Wait+Screen /2\/3/
Sleep 500ms

# 3. Mistake correction: a wrong command teaches instead of advancing.
Type ":Echo hi"
Enter
Wait+Screen /Lowercase wins/
Sleep 1200ms
Screenshot .shots/06-mistake.png
Type ":demosay done"
Enter
Wait+Screen /TUTORIAL COMPLETE/
Sleep 1500ms

Screenshot .shots/07-complete.png

# Back to the menu: finished tours report how long ago they completed.
Type ":Tutorial"
Enter
Wait+Screen /today/
Sleep 1600ms

Screenshot .shots/08-menu-complete.png

Hide
Type ":qa!"
Enter
Show

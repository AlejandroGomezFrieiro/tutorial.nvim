# Recording docs/demo.gif — the built-in "Hello, tutorial.nvim" tour,
# running inside the author's own Neovim configuration (see flake.nix).
#
#   nix develop .#demo -c vhs demo.tape
#
# The tour is driven through its real completion events: d in the pinned
# panel, an Ex command, saving a file, a User autocmd, and the progress-file
# predicate (polled on CursorHold, hence the low updatetime below).

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
# inside it: the repo ships an empty tutorial-practice.md (which would
# complete the save-a-file step on sight) and progress must not leak into,
# or resume from, the real ~/.local/share/nvim between recordings.
Hide
Type@250ms "D=/tmp/opencode/tutorial-demo; rm -rf $D; mkdir -p $D && cd $D && XDG_CONFIG_HOME=$D/config XDG_DATA_HOME=$D/data XDG_STATE_HOME=$D/state XDG_CACHE_HOME=$D/cache nvim"
Enter
Wait+Screen /Quit NVIM/
Sleep 1500ms
Show
Sleep 800ms

# Leave the dashboard for a plain workspace.
Type ":enew"
Enter
Sleep 400ms

# State checks poll on CursorHold; make them snappy.
Type ":set updatetime=200"
Enter
Sleep 400ms

# Pick the built-in tour from the menu.
Type ":Tutorial"
Enter
Wait+Screen /TUTORIALS/
Sleep 800ms

Enter
Wait+Screen /HELLO, TUTORIAL.NVIM/
Sleep 700ms

# Give the walkthrough a quiet workspace beside the panel.
Type ":enew"
Enter
Sleep 400ms

Screenshot .shots/01-start.png

# 1. Complete a step by hand — d lives on the panel buffer.
Type ":wincmd h"
Enter
Sleep 400ms
Type "d"
Wait+Screen /1\/6/
Sleep 500ms
Type ":wincmd l"
Enter
Sleep 300ms

# 2. Complete a step with a command.
Type ":echo 'one small step'"
Enter
Wait+Screen /2\/6/
Sleep 600ms

Screenshot .shots/02-command.png

# 3. Complete a step by saving a file.
Type ":edit tutorial-practice.md"
Enter
Sleep 500ms
Type@40ms "i# Practice notes"
Ctrl+[
Sleep 300ms
Type ":write"
Enter
Wait+Screen /3\/6/
Sleep 600ms

Screenshot .shots/03-file.png

# 4. Complete a step with a User autocmd.
Type ":doautocmd User TutorialPractice"
Enter
Wait+Screen /4\/6/
Sleep 600ms

# 5. Predicate over persisted progress — the next CursorHold finds the
# progress file already written by earlier steps and checks this off itself.
Sleep 900ms
Wait+Screen /5\/6/
Sleep 700ms

Screenshot .shots/04-predicate.png

# 6. Wrap up — d one last time, and the tour finishes itself.
Type ":wincmd h"
Enter
Sleep 400ms
Type "d"
Wait+Screen /TUTORIAL COMPLETE/
Sleep 1500ms

Screenshot .shots/05-complete.png

# Back to the menu: the finished tour is marked complete.
Type ":Tutorial"
Enter
Wait+Screen /complete/
Sleep 1600ms

Screenshot .shots/06-menu.png

Hide
Type ":qa!"
Enter
Show

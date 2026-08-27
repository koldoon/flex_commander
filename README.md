# Flex Commander

A keyboard-first, two-pane file manager for the desktop, written in Flutter.

The two-pane layout is the eternal classic: source on one side, destination on the
other, and both of them one keystroke away. Norton Commander settled that question in
1986, Total Commander, Far and Midnight Commander have been refining it ever since, and
nothing since has been faster for the work file managers are actually used for — moving,
comparing, packing and finding things. Flex Commander is that idea on a modern toolkit:
the keyboard is the interface, the mouse is optional, and the function-key row at the
bottom is a drawn keyboard rather than a toolbar.

It is a port of the author's own Adobe Flex/AIR file manager (`ru.koldoon.fc`), and the
parts that were right there were kept: the model layer, the command model with key
bindings, and the visual design. The central idea comes from there too — **a panel does
not show "a list of files", it shows a directory in a tree of nodes**, and everything
that can read or change that tree hides behind one interface, `TreeProvider`. The local
file system is only one implementation of it; a ZIP archive, a 7z archive and a remote
machine over SFTP are simply more providers, and the cursor, marking, sorting and every
file command work the same way in all of them.

## Status

Work in progress, and macOS only for now — the tree contains just `macos/`, and the
platform-specific parts are isolated in the local file system module. One dark theme, no
light variant. The design documents in [`docs/`](docs/README.md) are written in Russian;
what is planned next is in [`docs/roadmap.md`](docs/roadmap.md), and what changed from
release to release is in [`docs/release-notes.md`](docs/release-notes.md).

## What it can do today

**Panels and navigation.** Two independent panes with a draggable splitter (double-click
or middle-click centres it). Enter directories and archives, go up, jump to the root of
the current source, re-read a directory, toggle hidden files. The cursor position is
remembered per directory, going up puts the cursor back on the directory you came from,
and typing any printable character jumps to the next name starting with it. Sorting is
natural (`file2` before `file10`), directories first, symbolic links resolved without
losing the path you walked.

**Address input.** `Cmd+F1` and `Cmd+F2` open anything by string: `/etc`,
`~/Downloads`, a path inside an archive, or `ssh://user@host/srv`. A leading `~` expands
to the home directory *of that source*, not of the local machine.

**Columns.** Name, extension, size, modified, created, accessed, attributes. Drag headers
to reorder, drag borders to resize, right-click for a visibility menu, click to sort. The
layout, sorting and hidden-file flag are stored per panel and survive restarts.

**Marking.** Space or Insert marks, `Cmd+A` marks everything, `Esc` clears. The status bar
shows how many objects are marked and their total size — and directory sizes are counted
in the background by a bounded pool of scans, growing in the Size column as they go.

**File operations.** Copy, move, make directory, delete to Trash, delete permanently.
Every long operation shows two progress bars (the current object and the whole job),
object and byte counters, transfer speed and estimated time; it asks what to do about an
existing name (overwrite / all / skip / all / cancel), survives errors on single objects
by asking rather than stopping, can be cancelled with confirmation, and can be sent to
the background to keep running in the bar above the function keys.

**Data sources.** Local file system; ZIP — read, write, and create with `Shift+F5`; 7z —
read, write, and create with `Shift+F7`, using the external `7z` program; tar, gz, tar.gz
and tgz — read, and create from the command palette («Mk Tar» and «Mk Gz»); SSH/SFTP — read
and write, authenticating with the keys in `~/.ssh` (asking for a passphrase only when one
is actually needed) or with a password. Archives nest: an archive inside an archive, an
archive on a server, addressed by a chain of paths such as `fs:/a.zip:zip:/inner` — and
`.tar.gz` is that same nesting rather than a special case: the `gz` source holds one
entry, the `.tar` inside it, and entering that opens the `tar` source. Permissions and
symbolic links inside a tar are preserved, and links are transferred as links.
Transfers stream between *any* two sources, so copying out of an archive straight to a
server is an ordinary `F5`.

**Quick view (`Shift+F3`).** The other panel shows what the cursor is on, and
walking the list changes it — the file panel keeps the cursor, so a directory of
logs or configs is read by pressing Down. `Tab` hands the input to the view
itself, where every viewer key works as it does full-screen (wrap, line numbers,
search, copy, arrows scrolling the text); `Tab` again returns to the files,
`Esc` puts the view away. The panel underneath stays exactly as it was, and
copying *into* a panel that shows a file is simply not offered.

**Viewer (`F3`) and editor (`F4`).** What `F3` opens is decided by a registry: a
module declares a viewer — which files it takes and what it opens — and the
viewing shell picks the first one that accepts, by priority. Today the only
viewer is text, so `F3` shows text; when an image viewer arrives, `F3` and the
quick view will both show pictures without a line changing in either of them. A
file nobody takes is answered in words, not by a dead key.

Both the viewer and the editor are the same text engine — a vendored fork of
`re_editor`, built for large files — so they look and behave identically. Syntax
highlighting, search with `Cmd+F` or `F7` and next/previous, word wrap, line numbers, page
scrolling; the viewer additionally copies the selection with `Cmd+C`. The editor refuses
to open a file that is not valid UTF-8 rather than saving replacement characters over it,
preserves the file's original line endings, and writes through a temporary file with a
rename so an interrupted save cannot leave half a file behind. Files inside archives and
on servers open too — the bytes come through the same contract as copying.

**Terminal and command line.** A shell in the same window: a command line under the
panels, and a full-screen session over them on `Ctrl+O` — the key `mc` uses. `Cmd+T`
hands the input to the line; it has to be a key, because a printable character in a panel
jumps to a name and that cannot be taken away — unless you ask for it: one setting
(`terminal.toggleTyping`) switches to the `mc` habit, where typing goes straight to the
line while the input stays with the panel, and the jump-to-name is what goes away instead. `Esc` gives the input back and keeps what
you typed. `Enter` runs the line **in its own process** in the panel's directory, so the
end of a command is known exactly instead of being guessed from the shape of a prompt:
a silent successful command shows nothing and simply re-reads the panel, while one that
says anything keeps its output on screen until you press a key. `cd` is the exception —
it walks the *panel*, not the shell. `Tab` completes paths from the panel's source: one
match is inserted whole, several are extended to their common prefix and then cycled
through, and what there is to choose from is listed above the line. While that list is up,
`Enter` accepts what was inserted instead of running the command — you are descending a
path, not launching it — and `Esc` gives you back what you typed. Function keys and `↑`/`↓` still belong to the panels
while you type, so `F5` copies and the cursor keeps moving. The pseudo-terminal is
`posix_openpt` plus `posix_spawn` through `dart:ffi`: no native plugin, so the macOS build
stays on Swift Package Manager, and a real shell can be driven from `flutter test`.

**Interface and plumbing.** The function-key row asks the command registry what is bound
to each key, so a button and its key can never disagree; it follows the visible screen
(in the viewer `F2` says `Wrap`) and shows the layer of whatever modifier is held down.
`F1` prints a help table generated from the command registry itself. Command windows can
be dragged aside by their title bar — to see the file list under a running copy, or the
error behind the dialog — and never leave the window entirely. Passwords for encrypted
archives and servers are asked by one shared dialog and remembered for the session
only. Transient messages appear as toasts; window geometry, panel paths and
settings are stored in `~/.flex-commander/settings.json`.

## Keyboard

The full table, with the reasoning behind it, is in [`docs/keyboard.md`](docs/keyboard.md).
On Windows and Linux `Cmd` reads as `Ctrl`.

| Keys | Action |
|---|---|
| `↑` `↓` `PgUp` `PgDn` | move the cursor |
| `Home` / `Left`, `End` / `Right` | first / last entry |
| `Enter` | enter a directory or archive, open a file with the system |
| `Bsp`, `Cmd-↑` | go up one level |
| `Cmd-/` | go to the root of the current source |
| `Cmd-R` | re-read the directory |
| `Cmd-Shift-H` | show or hide hidden files |
| `Tab` | switch the active panel |
| `Space`, `Ins` | mark the object under the cursor |
| `Cmd-A`, `Esc` | mark everything, clear the marking |
| `Esc` | cancel a running operation |
| `Cmd-F1`, `Cmd-F2` | open a path or address in the left / right panel |
| `Cmd-O` | open the selected objects with the system |
| `F1` | help: settings and every command with its keys |
| `F2`, `Cmd-,` | settings: everything you choose, in one window |
| `Cmd-Shift-P` | the command palette: everything the app can do right now, by name or synonym |
| `F3` / `F4` | view / edit the file under the cursor |
| `Shift-F3` | quick view in the other panel; `Tab` hands the input to it |
| `F5` / `F6` | copy / move to the other panel |
| `F7`, `Shift-Cmd-N` | make a directory |
| `F8`, `Cmd-Bsp` | delete to Trash |
| `Shift-F8`, `Shift-Cmd-Bsp` | delete permanently |
| `Shift-F5` / `Shift-F7` | pack the selection into a new zip / 7z archive |
| — (palette) | «Mk Tar» — pack into `.tar`, `.tar.gz` or `.tgz`; «Mk Gz» — compress one file |
| `F2` (viewer / editor) | word wrap / save |
| `F9` (viewer, editor) | line numbers |
| `Cmd-F`, `F7` / `Cmd-G` / `Shift-Cmd-G` | find / find next / find previous |
| `Cmd-S` (editor) | save |
| `Esc`, `F10` (viewer, editor) | close and go back to the panels |
| `Cmd-T` | hand the input to the command line |
| `Esc` (command line) | hand it back to the panel, keeping the text |
| `Ctrl-O` | raise the shell full-screen and back |
| `Tab` / `Shift-Tab` (command line) | complete the path, then cycle the matches |
| `Cmd-↑` / `Cmd-↓` (command line) | previous / next command in the history |
| `Cmd-Enter` / `Cmd-Shift-Enter` | insert the name / the full path under the cursor |

Inside the full-screen shell only `Ctrl+O` is taken — everything else goes to whatever
runs there, because `vim`, `htop` and `mc` live on those keys. The one casualty is `nano`,
where `Ctrl+O` means "save"; `mc` has made the same trade for decades, and the way out of
a full-screen view has to be the same key everywhere. Note also that on Windows and Linux
`Cmd+O` (open with the system) and this `Ctrl+O` are the same combination, and the older
binding wins there until one of them moves.

On macOS the function keys are taken by the system by default. Turn on *System Settings →
Keyboard → "Use F1, F2, etc. keys as standard function keys"*, or press `Fn+F5`. The
macOS-native duplicates (`Shift-Cmd-N`, `Cmd-Bsp`) exist for exactly this reason.

## Building

Requirements:

- Flutter SDK with Dart `^3.7.0`;
- Xcode with the command-line tools;
- macOS 10.15 or newer;
- optional: `7z` on `PATH` (`brew install p7zip`) — without it the 7z module still loads
  and says what is missing when you open a `.7z`, instead of showing an empty panel.

```sh
flutter pub get                 # a pub workspace: everything under dependency/ resolves together
flutter run -d macos            # run
flutter test                    # tests of the application package
```

A release build needs one extra flag:

```sh
flutter build macos --release --no-tree-shake-icons
```

Icon glyphs are built from FontAwesome code points that are not compile-time constants, so
icon tree shaking cannot work; the release workflow passes the same flag.

Two things worth knowing about the macOS build: the **sandbox is deliberately off**
(see `macos/Runner/*.entitlements`) — a file manager needs the whole file system, and
inside the sandbox it sees only its own container, settings included. System-level
protection stays: the first visit to Downloads, Documents or the Desktop still raises the
usual TCC prompt.

## Tests and CI

Tests live next to the code they cover — in the application package and in every module.
This is the loop CI runs:

```sh
for pkg in . dependency/*/; do
  [ -d "$pkg/test" ] || continue
  (cd "$pkg" && flutter test)
done
```

Formatting and analysis are part of the check, and CI fails on unformatted code:

```sh
git ls-files -z '*.dart' | grep -zv '^dependency/re_editor/' \
  | xargs -0 dart format --output=none --set-exit-if-changed
flutter analyze
```

`dependency/re_editor/` is skipped on purpose: it is a vendored fork, and reformatting it
would bury the handful of deliberate differences from upstream. Locally, format with
[`tool/format.sh`](tool/format.sh) rather than `dart format .` — it applies the same
selection, in write mode. `dart format` has no exclude of its own: neither a flag nor
`analysis_options.yaml`, which it does not read at all.

Some tests need something real and skip themselves when it is missing: `FC_SSH_TEST_HOST`
enables the live SSH tests, `FC_BENCH=1` enables the directory-listing benchmark, and the
live 7z tests skip when the program is not installed. Workflows are in
[`.github/workflows/`](.github/workflows/) and run on a self-hosted macOS runner.

## Architecture

The application is assembled from packages. In the middle sits `fc_api` — models,
interfaces, commands with their registry and the shared interface elements. The core
depends on it, every module depends on it, and modules know nothing about each other.

```
flex_commander (core)  ->  fc_api  <-  modules (navigation, file_ops, zip, 7z, ssh, …)
```

The core knows its modules **only** through the list in
`lib/bootstrap/app_modules.dart`. Removing one removes a capability, not the build:
without the navigation module you cannot walk the tree, without file operations you
cannot copy — and the window still opens, with the help screen honestly reporting fewer
commands. A module declares what it offers (tree providers, commands, key bindings, a
theme, panel viewports, services, its own settings section) and never does any work while
declaring — see [`docs/modules.md`](docs/modules.md).

| Package | What it is |
|---|---|
| `dependency/api` | `fc_api` — what modules are written against |
| `dependency/ui_kit` | shared widgets: panel frame, dialogs, buttons, fields |
| `dependency/text_kit` | text display shared by the viewer and the editor |
| `dependency/panels` | the file panels screen |
| `dependency/viewer` | the viewing shell: `F3`, `Shift+F3` and choosing a viewer |
| `dependency/text_viewer`, `dependency/editor` | the text viewer and the editor (`F4`) |
| `dependency/navigation` | cursor, tree walking, marking |
| `dependency/file_ops` | create, delete, copy, move |
| `dependency/zip`, `dependency/7z`, `dependency/tar` | archives as trees, plus archive creation |
| `dependency/ssh` | a remote machine's file system over SFTP |
| `dependency/terminal` | command line and shell session, on its own pseudo-terminal |
| `dependency/default_theme` | palette, metrics, icons, fonts |
| `dependency/test_kit` | fakes and application assembly for tests |
| `dependency/re_editor` | vendored fork of the text editing engine |

The design documents (in Russian) are indexed in [`docs/README.md`](docs/README.md):
the model layer, state management, widgets and theme, keyboard and commands, screens,
data sources, modules, and the roadmap.

## License

Not decided yet.

# Flex Commander

A keyboard-first, two-pane file manager for the desktop, written in Flutter.

Two panes: source on one side, destination on the other, both one keystroke away. Norton
Commander settled that question in 1986, and Total Commander, Far and Midnight Commander
have been refining it ever since. Flex Commander is that idea on a modern toolkit — the
keyboard is the interface, the mouse is optional, and the function-key row at the bottom
is a drawn keyboard rather than a toolbar.

It is a port of the author's own Adobe Flex/AIR file manager (`ru.koldoon.fc`), and the
central idea comes from there: **a panel does not show "a list of files", it shows a
directory in a tree of nodes**. Everything that can read or change that tree hides behind
one interface, `TreeProvider`. The local file system is one implementation; a ZIP archive,
a 7z archive, a `tar`, a machine over SFTP, an FTP server and even a set of search results
are simply more providers — and the cursor, marking, sorting and every file command work
the same way in all of them.

## Install

Builds are published on the [Releases](../../releases) page, one archive per tag:
`flex_commander-vX.Y.Z-macos-arm64.zip`. Apple silicon, macOS 10.15 or newer.

1. Download the archive, unpack it, move `flex_commander.app` to `/Applications`.
2. The build is **not signed and not notarised**, so macOS quarantines it: the first
   launch fails with "damaged" or "cannot be opened". Clear the flag once:

   ```sh
   xattr -dr com.apple.quarantine /Applications/flex_commander.app
   ```

   Without the terminal: right-click the app, choose *Open*, then *Open* again in the
   dialog — or *System Settings > Privacy & Security > Open Anyway* right after the
   refusal.
3. After that the application checks the same Releases page itself and installs a new
   build without a second trip to GitHub.

Function keys need one system setting: *System Settings > Keyboard > "Use F1, F2, etc.
keys as standard function keys"*. Otherwise `F3` dims the screen instead of opening a file.

## Status

Work in progress, macOS only for now — the tree contains just `macos/`, and the
platform-specific parts are isolated in the local file system module. One dark theme out of
the box, changeable in the application. Interface in Russian and English.

The design documents are in Russian and indexed in [`docs/README.md`](docs/README.md).
What is planned next is in [`docs/roadmap.md`](docs/roadmap.md); what changed from release
to release is in [`docs/release-notes.md`](docs/release-notes.md).

## What it does

### Panels and navigation

| What | How |
|---|---|
| Two panes, draggable splitter | double-click or middle-click centres it |
| Enter a directory, an archive or a link | `Enter` |
| Up a level, to the root of the source, re-read | `Bsp`, `Cmd-/`, `Cmd-R` |
| Hidden files on and off | `Cmd-Shift-H` |
| Jump to a name as you type it | any printable character; `Ctrl-S` follows the whole name |
| Show what the cursor is on in the *other* panel | `Alt-O` — the input stays where it is |
| Back, forward, and the list of where you have been | `Alt-Left`, `Alt-Right`, `Alt-Down` |
| Sizes of every directory here | `Alt-Shift-Enter` |
| Path as breadcrumbs in the panel header | click a segment to go there |

The cursor position is remembered per directory, and going up puts it back on the
directory you came from. Sorting is natural (`file2` before `file10`), directories first,
symbolic links resolved without losing the path you walked. A directory you have already
been in opens from memory, and the re-read that follows quietly replaces the listing if
anything moved — so `Bsp` over `ssh` is not a pause. `Cmd-R` means read *past* that memory.

### Panel views

Six ways to show the same directory. The view is per panel and survives a restart, along
with what is expanded, where the cursor stands and how far the list is scrolled.

| View | Keys | What it is |
|---|---|---|
| Table | `Cmd-1` | the full set of columns |
| Brief | `Cmd-2` | names alone, in columns that scroll sideways |
| Tree | `Cmd-3` | branches; `Right` / `Left` expand and collapse |
| Tree with contents | `Cmd-4` | directories on the left, the branch under the cursor on the right |
| Icons | `Cmd-5` | a grid with thumbnails — pictures recognised by sight |
| Columns | `Cmd-6` | a chain of directories left to right, as in Finder |
| The view window | `Alt-F1`, `Alt-F2` | the choice with the settings of the chosen view underneath |

In the tree, `Shift-Right` takes the whole subtree and `Shift-Cmd-Right` takes the lot; it
reads as it goes, so it runs as a job and `Esc` stops it. Archives open as branches too.

### Open sessions

What a tab is for is not the tab: it is what it holds open — an unpacked archive, a raised
connection, a directory already read, a cursor already placed. That is a session, and it
belongs to the application rather than to a side, so the list is one. It lives in the
title bar; a mark at the edge of each entry is a miniature pair of panels saying whether
the session is shown on the left, on the right or in both.

| What | How |
|---|---|
| Open on this directory / close the one on show | `Cmd-Shift-T` / `Cmd-Shift-W` |
| Walk the row, or go straight to a number | `Ctrl-Tab`, `Ctrl-Shift-Tab`, `Alt-1` … `Alt-9` |
| Choose by name, with fuzzy matching | `Cmd-Shift-O` |

A session can be given a name that outlives the directory it was opened on. The same
session can be shown in both panels at once — then the cursor and the marking are shared,
and the keys belong to whichever side has the input. Directories are read lazily: at
startup only the ones on show, and a session that stood on a server raises its connection
at that moment rather than dropping you into a home directory on the way in.

### Sources

Every source is a `TreeProvider`, so everything below works the same in all of them.

| Source | Notes |
|---|---|
| Local file system | permissions, owner, dates, extended attributes |
| ZIP | read, write, and create; read is streamed, so a large file inside opens without filling memory |
| 7z | read and create; needs `7z` on `PATH`, and says so when it is missing |
| tar, gz, tar.gz | enter as a directory, pack into the same |
| SFTP (`ssh://`) | a remote machine's file system, and a shell on that side |
| FTP (`ftp://`) | read, write, resume, FTPS |
| Search results | a panel's content addressed as `search:/?…` |

Addresses are opened by string: `Cmd-F1` and `Cmd-F2` take `/etc`, `~/Downloads`, a path
inside an archive, `ssh://user@host/srv` or `ftp://ftp.example.org/pub`. A leading `~`
expands to the home directory *of that source*, not of the local machine. The window
remembers where you have been.

Writing into an archive that is not on disk works too: copy into a `.zip` standing on a
server and the archive goes back where it came from.

### Marking, masks and search

| What | How |
|---|---|
| Mark, mark without stepping down | `Space`, `Shift-Space`, `Ins` |
| Mark everything, files only, clear | `Cmd-A`, `Cmd-Shift-A`, `Esc` |
| Mark and unmark by mask | `+` / `-`, e.g. `*.dart;!*.g.dart` |
| Mark with the mouse | right button marks, dragging takes a run |
| Find files below this directory | `Alt-F7` |

Search goes by mask and by content, understands exclusions, links, case, regular
expressions, size and date, and walks into archives. The results are a panel's content,
not a list in a dialog: the cursor, marking and every file command work on them, and
`Enter` goes to the file in its own directory.

### File operations

| What | How |
|---|---|
| Copy, move | `F5`, `F6` |
| Rename in place | `Shift-F6` |
| Rename a group by mask, with a preview | `Ctrl-M` |
| Make a directory | `F7` |
| Delete to Trash, delete permanently | `F8`, `Shift-F8` |
| Undo the last operation | `Cmd-Z` |
| Copy, cut, paste | `Cmd-C`, `Cmd-X`, `Cmd-V`, `Alt-Cmd-V` pastes as a move |
| Copy the address of the object as text | `Alt-Cmd-C` |
| Pack the selection into a new zip / 7z | `Shift-F5`, `Shift-F7` |
| Pack into this panel, unpack next to the archive | `Alt-F5`, `Alt-F9` |
| Open with the system | `Cmd-O` |

Long operations run as jobs with progress, and `Esc` stops them; the list of jobs lives
under the panels and takes the input on `Cmd-B`. Files dropped from Finder land in the
panel, and dragging out of the application works in the other direction — from an archive
by promise, so the file is unpacked only when it is actually dropped. Saving a file that
belongs to somebody else raises the rights through `sudo`, asking once.

### Viewing and editing

What `F3` opens is decided by a registry: a module claims the file, and the viewing shell
only asks. Nothing claims it — it opens as text.

| Kind | What it gives |
|---|---|
| Text | syntax highlighting, word wrap on `F2`, line numbers on `F9`, search on `Cmd-F` / `F7` |
| JSON | `F5` lays a machine-written one-liner out over lines; the file itself is never touched. In the editor `Alt-Shift-F` formats the document for real |
| Images | png, jpeg, gif (animated), webp, bmp and HEIC, zoom and fit |
| Vector | `svg` drawn as a picture, sharp at any zoom; `F5` shows the markup |
| Markdown | headings, lists, tables, images and highlighted code; `F5` shows the source |
| Diagrams | a ```` ```mermaid ```` block inside markdown is drawn, not printed |
| Anything else | the file info window as a fallback |

`Shift-F3` puts the viewer into the *other* panel, so the list stays on one side and what
the cursor is on is shown on the other; `Tab` hands the input to it.

`F4` opens the editor: saving asks, leaving offers to save, and a read-only file says so
before you have typed anything rather than after.

Diagrams are drawn by the application itself — no webview, no external library, no network
request. `sequenceDiagram` and `flowchart` are supported; anything else says so in words,
in place of the picture, and a parse error names the line.

### File info and attributes

`Cmd-I` (or `Alt-Enter`) shows everything known about the object; modules add their own
sections to that window. `Ctrl-A` changes what it shows: permissions, dates, owner and
extended attributes, on any source that supports them.

### Terminal and command line

A shell in the same window: a command line under the panels on `Cmd-T`, and the same
shell raised full-screen on `Ctrl-O`. It is one session — a command typed in the line and
a command typed in the full-screen shell go to the same place, with the same prompt, the
same history and the same working directory as the active panel. When the panel stands on
a server, the line and the shell are on that side too.

`Tab` completes the path and then cycles the matches; `Cmd-Up` / `Cmd-Down` walk the
history; `Cmd-Enter` and `Cmd-Shift-Enter` insert the name and the full path under the
cursor. `Enter` on a file with the `+x` bit runs it there, rather than handing it to the
system.

### Customisation

| What | Where |
|---|---|
| Settings, with a table of contents, search and "back to default" | `F9`, `Cmd-,` |
| Keys: any command, set by pressing rather than by typing a name | settings, section "Keys" |
| Key presets: "as in mc", "as in Far", "as in Finder" | one choice |
| Theme editor: palette, metrics and fonts, several themes | settings |
| Presets of settings and keys, as a file between machines | settings |
| Row colouring by rules | a condition gives a colour |
| Row icons: a glyph, an image from disk or the system icon | by rules, per type |
| Column formats: your own date, size and permissions | per column |

Columns are declarations a module brings, not values of an enumeration in the core: name,
extension, size, modified, created, accessed, attributes, permissions, owner, group,
content type, source.

### Interface

The function-key row asks the command registry what is bound right now, so it shows what
the keys actually do. `F1` is help — every command with its keys and what it does.
`Cmd-Shift-P` is the command palette: everything the application can do at this moment,
by name or synonym. Windows can be dragged aside to see what is underneath, they are
resized by the edge and remember their size, `Tab` walks the controls and the focus is
visible.

## Keyboard

The full table, with the reasoning behind it, is in [`docs/keyboard.md`](docs/keyboard.md).
On Windows and Linux `Cmd` reads as `Ctrl`.

### Panels

| Keys | Action |
|---|---|
| `Up` `Down` `PgUp` `PgDn` | move the cursor |
| `Home` / `Left`, `End` / `Right` | first / last entry |
| `Enter` | enter a directory, an archive or a link; run a `+x` file; in search results, go to the file in its own directory. An ordinary file it does **not** open — that is `Cmd-O` |
| `Bsp` | go up one level |
| `Cmd-/` | go to the root of the current source |
| `Cmd-R` | re-read the directory |
| `Cmd-Shift-H` | show or hide hidden files |
| `Alt-Shift-Enter` | count the sizes of every directory here |
| `Tab` | switch the active panel |
| `Alt-O` | show what the cursor is on in the *other* panel |
| `Alt-Left`, `Alt-Right`, `Alt-Down` | back, forward, the list of where this session has been |
| `Cmd-1` … `Cmd-6` | the panel's view: table, brief, tree, tree with contents, icons, columns |
| `Alt-F1`, `Alt-F2` | the view window for the left / right panel |
| `Right` / `Left` (tree) | expand the branch / collapse it, then step out to its parent |
| `Shift-Right` / `Shift-Left` | the whole subtree; with `Cmd`, the whole tree |
| `Cmd-F1`, `Cmd-F2` | open a path or address in the left / right panel |

### Sessions

| Keys | Action |
|---|---|
| `Cmd-Shift-T` / `Cmd-Shift-W` | open a session on this directory / close the one on show |
| `Ctrl-Tab`, `Ctrl-Shift-Tab` | the next / previous open session |
| `Alt-1` … `Alt-9` | the session with that number |
| `Cmd-Shift-O` | choose an open session by name, with fuzzy matching |

### Marking and search

| Keys | Action |
|---|---|
| `Space`, `Ins` | mark the object under the cursor |
| `Shift-Space` | mark without stepping down |
| `Cmd-A`, `Cmd-Shift-A`, `Esc` | mark everything / files only / clear |
| `+` / `-` | mark or unmark by mask |
| `Ctrl-S` | quick search: the cursor follows what you type |
| `Alt-F7` | find files below the current directory |

### Files

| Keys | Action |
|---|---|
| `F5` / `F6` | copy / move to the other panel |
| `Shift-F6`, `Ctrl-M` | rename one / rename a group by mask |
| `F7` | make a directory |
| `F8`, `Shift-F8` | delete to Trash / delete permanently |
| `Cmd-Z` | undo the last operation |
| `Cmd-C`, `Cmd-X`, `Cmd-V`, `Alt-Cmd-V` | copy, cut, paste, paste as a move |
| `Alt-Cmd-C` | copy the address of the object as text |
| `Shift-F5` / `Shift-F7` | pack the selection into a new zip / 7z |
| `Alt-F5` / `Alt-F9` | pack into this panel / unpack next to the archive |
| `Cmd-O` | open the selected objects with the system |
| `Esc` | cancel a running operation |

### Viewing, editing, information

| Keys | Action |
|---|---|
| `F3` / `F4` | view / edit the file under the cursor |
| `Shift-F3` | quick view in the other panel; `Tab` hands the input to it |
| `F5` (viewer) | formatted or source — markdown, vector and json |
| `Alt-Shift-F` (editor) | format the document; plain undo puts it back |
| `F2` (viewer / editor) | word wrap / save |
| `F9` (viewer, editor) | line numbers |
| `Cmd-F`, `F7` / `Cmd-G` / `Shift-Cmd-G` | find / find next / find previous |
| `Cmd-S` (editor) | save |
| `Esc`, `F10` (viewer, editor) | close and go back to the panels |
| `Cmd-I`, `Alt-Enter` | everything known about the object |
| `Ctrl-A` | edit attributes: permissions, dates, owner, extended |

### Terminal and the application

| Keys | Action |
|---|---|
| `Cmd-T` | hand the input to the command line |
| `Esc` (command line) | hand it back to the panel, keeping the text |
| `Ctrl-O` | raise the shell full-screen and back |
| `Tab` / `Shift-Tab` (command line) | complete the path, then cycle the matches |
| `Cmd-Up` / `Cmd-Down` (command line) | previous / next command in the history |
| `Cmd-Enter` / `Cmd-Shift-Enter` | insert the name / the full path under the cursor |
| `F1` | help: settings and every command with its keys |
| `F9`, `Cmd-,` | settings |
| `Cmd-Shift-P` | the command palette |
| `Cmd-B` | the input goes to the list of background jobs |

Inside the full-screen shell only `Ctrl-O` is taken — everything else goes to whatever
runs there, because `vim`, `htop` and `mc` live on those keys. The one casualty is `nano`,
where `Ctrl-O` means "save"; `mc` has made the same trade for decades, and the way out of
a full-screen view has to be the same key everywhere. On Windows and Linux `Cmd-O` (open
with the system) and this `Ctrl-O` are the same combination, and the older binding wins
there until one of them moves.

The macOS-native duplicates — `Cmd-Bsp` for delete, `Shift-Cmd-N` for a new directory —
come with the "as in Finder" key preset rather than with the defaults.

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

Some of the tests are **golden**: they render the whole window, or a dialog, and compare
it pixel by pixel with a stored image under `test/view/goldens/`. They are the cheapest
way to notice that a layout moved when nothing was supposed to move — a metric changed in
the theme, say, and every column shifted by five points. Regenerate them deliberately,
never reflexively: `flutter test --update-goldens test/view/`, then look at the diff
images the run leaves in `test/view/failures/` and satisfy yourself that what changed is
what you meant to change. Font rendering differs between macOS versions, so the
`Goldens` workflow regenerates them on the same runner CI compares them on.

Some tests need something real and skip themselves when it is missing: `FC_SSH_TEST_HOST`
enables the live SSH tests, `FC_BENCH=1` enables the directory-listing benchmark, and the
live 7z tests skip when the program is not installed. Workflows are in
[`.github/workflows/`](.github/workflows/) and run on GitHub's own `macos-latest`
runner (arm64), with the Flutter SDK pinned to the version used for development.

## Architecture

The application is assembled from packages. In the middle sits `fc_api` — models,
interfaces, commands with their registry and the shared interface elements. The core
depends on it, every module depends on it, and modules know nothing about each other.

**The core and the window are two isolates.** Panels, directories, search, copying,
archives, `ssh` and the shell live in one; drawing lives in the other; between them the
talk is in values — a request one way, state back the other. That buys one visible thing:
the window stopped freezing. While a big tree is searched or directory sizes are counted,
the cursor moves, panels scroll and the window drags — the longest pause during a search
fell from 14–36 ms to 6.5–9.3, which is to say no frame is dropped at all. The three API
packages below are that boundary written down: `fc_api` is what crosses it, `fc_core_api`
is the core's own side, `fc_ui_api` the window's.

```
flex_commander (core)  ->  fc_api  <-  modules (navigation, file_ops, zip, 7z, ssh, ...)
```

The core knows its modules **only** through the list in
`lib/bootstrap/app_modules.dart`. Removing one removes a capability, not the build:
without the navigation module you cannot walk the tree, without file operations you
cannot copy — and the window still opens, with the help screen honestly reporting fewer
commands. A module declares what it offers (tree providers, commands, key bindings, a
theme, panel viewports, viewers, services, its own settings section) and never does any
work while declaring — see [`docs/modules.md`](docs/modules.md).

Viewing shows the rule at two levels: turn off the viewing shell and `F3` is gone
altogether; turn off the text viewer and `F3` stays, opening whatever another module
takes and saying in words when nothing does.

| Package | What it is |
|---|---|
| `dependency/api` | `fc_api` — values that cross the boundary, works, formats, settings |
| `dependency/core_api` | `fc_core_api` — the core's API: node tree, sources, transfer engine |
| `dependency/ui_api` | `fc_ui_api` — the interface's API: application, panels, commands, views |
| `dependency/ui_kit` | shared widgets: panel frame, dialogs, buttons, fields |
| `dependency/text_kit` | text display shared by the viewer and the editor |
| `dependency/markdown_kit` | markdown rendering: theme styles, highlighted code blocks, the extension point for diagrams |
| `dependency/mermaid` | mermaid diagrams inside markdown: own parser, layout and painter |
| `dependency/panels` | the file panels screen |
| `dependency/viewer` | the viewing shell: `F3`, `Shift-F3` and choosing a viewer |
| `dependency/text_viewer`, `dependency/image_viewer`, `dependency/markdown_viewer` | viewers: text, images, vector and markdown |
| `dependency/file_info` | file info: the window, the fallback viewer, section providers |
| `dependency/attributes` | editing attributes: permissions, dates, owner, extended |
| `dependency/editor` | the text editor (`F4`) |
| `dependency/navigation` | cursor, tree walking, marking |
| `dependency/search` | file search: the window, the walk, the results as a panel's content |
| `dependency/file_ops` | create, delete, copy, move |
| `dependency/local_fs` | the local file system and the platform parts it needs |
| `dependency/platform` | what only a real machine can do: window, clipboard, launching programs, the pseudo-terminal |
| `dependency/zip`, `dependency/7z`, `dependency/tar` | archives as trees, plus archive creation |
| `dependency/ssh` | a remote machine's file system over SFTP |
| `dependency/ftp` | an FTP server's file system, over a client of our own |
| `dependency/terminal` | command line and shell session, on its own pseudo-terminal |
| `dependency/content_types` | what a file really is: the type from its first bytes, not from its name |
| `dependency/file_icons` | the row's icon by rules: a glyph, an image from disk or a system icon |
| `dependency/archive` | archive in place: unpack next to it, pack into this panel |
| `dependency/history` | the history of file operations and undoing the last one |
| `dependency/key_presets` | key sets: "as in mc", "as in Far", "as in Finder" |
| `dependency/theme_editor`, `dependency/default_theme` | themes: the editor, and the palette, metrics, icons and fonts it edits |
| `dependency/updater` | checks the Releases page and installs a new build |
| `dependency/test_kit` | fakes and application assembly for tests |
| `dependency/re_editor` | vendored fork of the text editing engine |

The design documents (in Russian) are indexed in [`docs/README.md`](docs/README.md):
the model layer, state management, widgets and theme, keyboard and commands, screens,
data sources, modules, and the roadmap.

## License

Not decided yet.

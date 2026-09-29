# Keyboard Shortcuts

Rockxy follows the same shortcut pattern across the main capture window, rule editors, breakpoint tools, Compose, and script editing. Shortcuts that act on a selection require the relevant table or editor to be focused.

## Universal

| Shortcut | Action |
|---|---|
| `⌘N` | New rule, template, script, or item in the active window |
| `⇧⌘N` | New Folder where folders are supported |
| `⌘↩` | Primary action: Add, Save, Send, or Execute |
| `Esc` | Cancel sheets and modal editors; close the Breakpoint Queue without resolving the selected item |
| `⌘⌫` | Delete the selected item |
| `⌘D` | Duplicate the selected item |
| `↵` / `Space` | Toggle the enabled state of the selected rule or script when the list has focus |
| `⌘F` | Focus the filter or search field |
| `⌘W` | Close the current window |
| `⌘,` | Settings |
| `⌘C` / `⌘V` / `⌘X` / `⌘A` | Copy, Paste, Cut, and Select All in text fields and standard editable controls |

## Main Capture

| Shortcut | Action |
|---|---|
| `⌘K` | Clear session |
| `⇧⌘K` | Clear session and filters |
| `⌥⌘R` | Pause or resume recording without stopping the proxy |
| `⌘L` | Focus the search bar |
| `⇧⌘F` | Show or hide Advanced Filters (Esc hides them) |
| `⌥⌘F` | Search apps and domains in the sidebar |
| `⇧⌘P` | Search and run any command |
| `⌥⌘N` | Compose a new request |
| `⇧⌘L` | Follow the newest visible request in the active workspace tab |
| `⌘↑` | Jump to the first visible row when the request table has focus |
| `⌘↓` | Jump to the last visible row when the request table has focus |
| `↑` / `↓` | Move row selection |
| `⌘E` | Edit and Repeat the selected request |
| `⌘R` | Replay the selected request |
| `⌘B` | Add a Breakpoint rule for the selected request URL |
| `⇧⌘B` | Open Breakpoint Rules |
| `⇧⌘[` / `⇧⌘]` | Switch workspace tabs |

## Compose

| Shortcut | Action |
|---|---|
| `⌘↩` | Send |
| `⌘.` | Cancel the active request |
| `⌘L` | Focus the URL field |
| `⌘T` | Open Template menu |
| `⌘Y` | Open History menu |
| `⌘0` | Reset to a fresh request |

`⌘H` remains reserved for the macOS Hide App command, so Compose uses `⌘Y` for History.

## Breakpoint Queue

| Shortcut | Action |
|---|---|
| `⌘↩` | Apply changes and continue the selected paused item |
| `⌘.` | Abort the selected paused item |
| `Esc` | Close the queue window; queued items remain paused |
| `⌘[` / `⌘]` | Move to the previous or next queued item |

## Basic Compare

| Shortcut | Action |
|---|---|
| `⌥⌘Y` | Open Diff View |
| `⌥⌘D` | Compare Selected |
| `⌥⌘S` | Swap Sides |

## Breakpoint Rules

| Shortcut | Action |
|---|---|
| `⌘N` | New Breakpoint rule |
| `⌘↩` | Edit the selected Breakpoint rule |
| `⌘D` | Duplicate the selected rule |
| `⌘⌫` | Delete the selected rule |
| `⌘F` | Focus the rules search field |
| `⌘T` | Open Breakpoint Templates |

Use the Enabled checkbox or the **More** menu to enable or disable the selected Breakpoint rule.

## Other Rules Windows

Applies to Map Local, Map Remote, Block List, Allow List, Modify Headers, Network Conditions, and Scripting where the action exists.

| Shortcut | Action |
|---|---|
| `⌘N` | New rule |
| `⇧⌘N` | New folder |
| `⌘E` | Edit selected rule |
| `⌘D` | Duplicate selected rule |
| `⌘⌫` | Delete selected rule |
| `↵` / `Space` | Toggle selected rule enabled state |
| `⌘F` | Filter rules |

## Settings

Applies to the HTTPS Decryption window.

| Shortcut | Action |
|---|---|
| `⌘↩` | Edit selected HTTPS behavior rule |
| `⌘⌫` | Delete selected HTTPS behavior rule |
| `Space` | Toggle selected HTTPS behavior rule |
| `⌘F` | Search HTTPS behavior rules |

## Script Editor

| Shortcut | Action |
|---|---|
| `⌘S` | Save and activate script |
| `⌘R` | Validate the matching rule against the sample URL |
| `⇧⌘C` | Toggle Console panel |
| `⌘/` | Toggle line comment in the code editor |
| `⌘[` / `⌘]` | Outdent or indent the selection in the code editor |

## Templates

| Shortcut | Action |
|---|---|
| `⌘N` | New template of the selected kind |
| `⇧⌘N` | New template of the opposite kind |
| `⌘D` | Duplicate selected template |
| `⌘⌫` | Delete selected template |

## Help

| Shortcut | Action |
|---|---|
| `⌘?` | Open Help → Keyboard Shortcuts |

## Conflict Resolutions

| Conflict | Resolution |
|---|---|
| Compose History wanted `⌘H`, but macOS reserves `⌘H` for Hide App. | Compose uses `⌘Y`, matching the common History shortcut family without overriding Hide App. |
| Main capture previously used `⌘↩` for replay and `⌘⌥↩` for Edit and Repeat. | Main capture now uses `⌘R` for Replay and `⌘E` for Edit and Repeat so `⌘↩` stays reserved for primary actions inside Compose and Breakpoint Queue. |
| New Folder previously used `⌘⌥N` in some rules windows. | New Folder now uses `⇧⌘N` everywhere it exists, matching Finder and common macOS creation patterns. |

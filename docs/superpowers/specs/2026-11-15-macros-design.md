# Macros — design

## Why

The user wants macros like the UHK (Ultimate Hacking Keyboard) has: a named sequence of steps bound
to a key, played back when the key is pressed. UHK runs macros in firmware, sends plain HID key
reports with timed delays, and types text by assuming a US layout. KeyLayers runs on the Mac, so it
can do the same through its virtual keyboard and type text for the layout actually selected.

## Goals

- Named macros, stored once in the configuration file, usable from any key on any layer/keymap.
- Step kinds: **Key** (tap, press, release; key plus modifiers), **Text**, **Delay** (ms).
- Text is typed for the input source selected at playback time, including dead-key sequences
  (e.g. "é" on US as Option-E, E).
- Real timed delays.
- Editing macros in the configurator; binding a macro to a key from the key action editor.

## Non-goals

- Mouse steps (no virtual mouse exists; separate project).
- UHK's scripting language ("smart macros"), loops, conditionals.
- Unicode string injection (`CGEventKeyboardSetUnicodeString`) as a fallback for characters the
  layout can't type. Possible later as a per-step option.
- Playing on release, while held (repeat), or on double tap.
- Importing UHK macro definitions.

## Anti-goals

- A stuck key or modifier after a macro ends, is cancelled, or the helper pauses.
- Macro playback that keeps running after pause or the emergency combo.
- Blocking the input thread (the backend's handler must return quickly).

## Approaches

- **A. Timed playback in the helper, text as layout keystrokes. Picked.** The engine resolves a
  macro key and hands the macro to a player in the helper runtime; the player posts steps through
  the virtual keyboard on its own queue with real delays. Text is reverse-mapped through
  `UCKeyTranslate` for the current layout. Behaves exactly like typing, matches how UHK works, works
  in secure-input fields. Can't type characters absent from the layout (emoji, →, other scripts),
  text goes through an active IME, and physically held modifiers the user keeps holding mix in.
- B. As A, but text injected as Unicode strings via `CGEvent`. Types any character, but bypasses the
  virtual keyboard, fails in secure input, is ignored by some apps. Not taken; maybe later as a
  per-step fallback.
- C. Instant only: engine emits the whole sequence in one batch, no delays. Small, but no delays
  and long text may be dropped by apps. Not taken.

## Design

### Model (KeymapModel)

- `Macro: Identifiable, Codable, Equatable, Sendable` with `id: UUID`, `name: String`,
  `steps: [MacroStep]`.
- `MacroStep`:
  - `.key(KeyStep)` where `KeyStep { key: KeyID?, modifiers: Modifiers, kind: .tap | .press | .release }`
    (`key == nil` with modifiers = modifier-only, as in `Keypress`).
  - `.text(String)`
  - `.delay(milliseconds: Int)` (clamped on playback to 0…60 000).
  - `.unsupported(type: String)` for forward compatibility, preserved on encode like
    `KeyAction.unsupported`; skipped on playback.
  - JSON shape `{"type": "key"|"text"|"delay", …}` like `KeyAction`.
- `KeyAction.macro(Macro.ID)`, encoded `{"type": "macro", "macroID": …}`.
- `Configuration.macros: IdentifiedArrayOf<Macro>`, decoded with `decodeIfPresent` (missing → empty),
  duplicate IDs rejected like keymaps. `formatVersion` stays 1: older builds read `macro` actions as
  `.unsupported` and preserve them, but drop the top-level `macros` array when they save. Accepted
  (builder: note it in the commit message).
- Dangling macro IDs (deleted or missing) behave like `.block`.

### Import (Configuration+Import)

- Importing keymaps also imports every macro referenced by an imported keymap, with new IDs (same
  collision handling as keymaps); names get " (imported)" on clash using `uniqueName`. `.macro`
  actions in imported keymaps are rewritten to the new IDs. Unreferenced macros in the other file
  are not imported. Export writes the whole configuration as today, so macros are included.

### Engine (RemapEngine)

- New `ResolvedPress.macro`-style resolution: on key-down of a `.macro(id)` action the press is
  stored as `.block` (repeats and the up are suppressed) and the result carries the request to play.
- `EngineResult` gains `macros: [Macro]` (the resolved macro value, looked up at press time, so a
  later config change doesn't alter a run in progress). Disposition `.suppress`.
- Before a macro, the engine includes in `output` the ups for synthetic modifiers it currently holds
  (from modifier-only keypresses / modifier secondary roles) and marks them so they are not
  re-sent: simplest is that the engine treats them as released (the holding presses become
  `.block`). **Builder's call** on the exact mechanism, but the requirement is: no synthetic modifier
  the engine holds leaks into the macro, and nothing stays stuck afterwards.
- Pending secondary roles are activated before the macro key as for any other key-down (existing
  behavior), so a mod-tap held while pressing a macro key behaves like holding that modifier, and
  its modifier is then released per the rule above. Physically held, unremapped modifiers are not
  touched (they mix in; documented limitation).
- A macro key can also have a secondary role? **No**: `.macro` is its own action type with no
  secondary role.

### Text to keystrokes (KeyboardLayout or KeyIO)

- `TextKeystrokes` builds, for the current input source, a table `Character → [stroke]`, where a
  stroke is `(KeyID, Modifiers)`. Built by running `UCKeyTranslate` over every key in `KeyID.allKnown`
  with modifier combinations none, ⇧, ⌥, ⇧⌥, including dead-key state: for each
  key/modifier that yields a dead-key state, translate every key/modifier again in that state to
  find two-stroke sequences. Prefer the fewest strokes, then fewest modifiers.
- **Caps Lock (my call, revised):** the table is built with Caps Lock off only. On macOS Shift does
  not undo Caps Lock (Caps Lock + Shift + A is still "A"), so no Caps-Lock-on table could type
  lowercase letters. Instead, at the start of each Text step the player reads the Caps Lock state
  (`CGEventSource.flagsState(.hidSystemState)` contains `.maskAlphaShift`); if it is on, the player
  taps Caps Lock before the text and taps it again after, restoring the user's state. A cancel in the
  middle of a Text step also restores it. The player never changes Caps Lock otherwise. (Needs a
  hardware check that a Caps Lock tap from the virtual keyboard toggles reliably.)
- **Keyboard type (my call):** translation uses `LMGetKbdType()` as `LiveKeyLabels` does. Mismatched
  ISO/ANSI/JIS cases between keyboards are a documented limitation.
- Newline maps to Return, tab to Tab.
- Rebuilt when the input source changes (`kTISNotifySelectedKeyboardInputSourceChanged`); the helper
  keeps the current table. The live code shares the layout-data lookup with `LiveKeyLabels`.
- Characters with no entry are skipped at playback. The same table is used by the configurator to
  flag untypeable characters in the editor.

### Playback (HelperFeature, `MacroPlayer`)

- Owned by `RemapperRuntime`. Requests from `EngineResult.macros` are appended to a FIFO queue
  (pressing again while playing queues another run). The player runs on its own serial dispatch
  queue, never on the input thread.
- Each step expands to output events: tap = down, up; press = down; release = up; text = per
  character its strokes, each a tap with its modifiers (modifier downs before, ups after); delay =
  wait. Between consecutive key events the player waits a fixed inter-event gap (start with 5 ms;
  **builder's call**, make it a constant).
- Output goes through `io.post` under the runtime's `lock`, like everything else, so ordering with
  engine output holds. The player must check a generation counter under `lock` before each post so a
  cancelled run never posts again.
- Modifiers in Key steps: a tap/press with modifiers sends modifier downs then the key down; a
  release sends the key up then the modifier ups. The player tracks every key and modifier it has
  down; when a run ends, it sends ups for anything still down.
- Cancel: `setPaused(true)`, emergency stop, `stop()`, `inputInterrupted`, `update(configuration:)`
  and a keymap switch (notification `.keymapSwitched` or `selectKeymap`) cancel the current run and
  clear the queue, sending ups for everything the player holds.
- Keys typed during playback are handled normally and interleave. **Decided: accepted as a
  documented limitation, no change to `VirtualKeyboardState`.** The virtual keyboard keeps one plain
  set of held keys/modifiers, so macro and user output can disturb each other: a macro's ⇧-up drops a
  ⇧ the user holds (until pressed again), modifiers of a held remapped key (e.g. ⌘Z) join the macro's
  text, and a macro tap of a key the user holds releases it. Nothing gets stuck: the player's
  end-of-run cleanup and existing release paths still send every up. Reference counting per holder
  (option b) and swallowing user input during playback (option c) were offered and not taken.
- **Output device (my call):** a run is pinned to the virtual keyboard of the device the macro key
  was pressed on. The runtime captures the source device when the engine returns the macro (the
  handler runs on the input queue) and the player posts with that source, so typing on a second
  keyboard mid-run doesn't move the run. This needs `KeyInputOutput.post` (or a sibling) to accept an
  explicit source device; if that device is unplugged mid-run, the run is cancelled.

### Configurator (ConfiguratorFeature)

- Sidebar: a "Macros" section under the keymap list, with add (+) and selection. Selecting a macro
  shows `MacroEditorView` in the detail pane instead of the keymap editor (selection is either a
  keymap or a macro).
- `MacroEditorFeature`: rename; list of steps with add (menu: Key, Text, Delay), delete, drag to
  reorder. Key step: kind picker (tap/press/release), key recorder and modifier toggles reused from
  the key action editor. Text step: text field, with a warning listing characters the current layout
  can't type (via the `TextKeystrokes` table through a dependency client). Delay step: number field
  in ms. Edits write the shared configuration immediately like other edits. Read-only mode
  (`isReadOnly`) disables editing.
- Delete macro: confirmation alert; if keys use it, the message says how many, and confirming
  removes those actions (sets them to `nil`).
- Duplicate macro from a context menu, like keymaps. **My call.**
- Key action editor: new "Macro" tab with a picker of macros (disabled with a hint when none exist).
  Key cap shows the macro's name (truncated), styled like other action labels.

## Tests

- KeymapModel: round-trip of macros and every step kind; missing `macros` → empty; unknown step type
  preserved; duplicate macro IDs rejected; `.macro` action round-trip; import brings referenced
  macros, rewrites IDs, renames on clash, ignores unreferenced ones.
- RemapEngine: macro key-down yields the macro and suppresses; repeat/up suppressed; dangling ID
  behaves as block; synthetic modifiers released before the macro; activated secondary role before
  macro.
- TextKeystrokes: with a fixed layout fixture (US and German), ASCII, shifted symbols, Option
  characters, dead-key sequences, untypeable characters.
- MacroPlayer (with a fake `KeyInputOutput` and an injectable clock): step expansion, delays, queueing,
  cancel on pause/stop/update/keymap switch releases held keys, no posts after cancel.
- Configurator: macro list add/delete (with in-use cleanup)/duplicate; editor step editing;
  key action editor macro tab; snapshot tests for the new views like existing ones.
- README: a short "Macros" paragraph under Editing, including the limits: characters missing from the layout, IMEs, held modifiers and typing during playback mixing in.

## Left to the builder

- Exact engine mechanism for releasing synthetic modifiers before a macro.
- Inter-event gap value.
- Where `TextKeystrokes` lives (KeyboardLayout vs KeyIO) as long as both helper and configurator can
  use it.
- View layout details within the sketch below.

```
┌──────────────┬─────────────────────────────────────┐
│ KEYMAPS      │  Email signature              [−][+]│
│  Default     │  ─────────────────────────────────  │
│  Gaming      │  1  Text   "Best regards,"          │
│              │  2  Key    tap  ↩                   │
│ MACROS       │  3  Delay  50 ms                    │
│ ▸ Email sig  │  4  Text   "Cheers ☕"   ⚠ ☕         │
│   Copy-line  │                                     │
│      +       │                                     │
└──────────────┴─────────────────────────────────────┘
```

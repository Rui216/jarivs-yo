# JARVIS

A native macOS personal productivity dashboard with an embedded AI assistant.

JARVIS is a SwiftUI application (macOS 14 or newer). It is not a wrapped web app:
the dashboard is built from native views, local data is stored with SwiftData,
secrets live in the macOS keychain, and every action the assistant takes on your
machine goes through real system integration: `NSWorkspace`, Apple Events through
`osascript`, EventKit, and a whitelisted command runner.

```
+----------------+--------------------------------------------------+-------------------+
| JARVIS         |  Good evening, Rui          21:14  Sat 14 Mar    |  AI Assistant     |
|                |                             weather 18 C       |  streaming chat   |
|  Home          +--------------------------------------------------+  mic + send       |
|  Tasks         |  Clock card (big)                |  Up Next        |                   |
|  Calendar      |  Homework Reminders | Mini cal   |  To-Do list     |-------------------|
|  Homework      |  Focus Timer                     |  System Status  |  Quick Notes      |
|  Files         |  Quick Tools: Chrome YouTube Discord Notion ...  |                   |
|  Apps          |                                                  |                   |
|  Settings      |                                                  |                   |
+----------------+--------------------------------------------------+-------------------+
```

---

## What is in the app

**Dashboard (Home)**

- Header with a greeting that uses your name, the live clock and date, and local weather.
- Large clock card with today's event count, focus minutes, and uptime.
- Up Next panel with the next calendar event and the rest of today's schedule.
- Homework Reminders list with inline completion and a compact add form.
- To-Do list with checkboxes, priorities, due dates, inline creation, and clear completed.
- Mini calendar month grid with markers on days that hold events.
- Focus Timer with 25, 50, and 90 minute presets, start, pause, and reset.
- Quick Tools row: Chrome, YouTube, Discord, Notion, ChatGPT, and a local folder out of the box.
- System status widget (bottom left): processor, memory, disk, network, and uptime, read from
  `host_processor_info`, `host_statistics64`, the startup volume attributes, and `getifaddrs`.

**Assistant column (right)**

- Streaming chat transcript with action chips that record what was automated.
- Text input plus a microphone button for live dictation.
- Quick Notes card with pinning, editing, and deletion.

**Screens**

- **Tasks**: filters, search, priority editing, overdue highlighting, summaries.
- **Calendar**: month grid, day detail, event creation through EventKit.
- **Homework**: grouped by due window, subject chips, overdue tracking, "Remind me" to Reminders.
- **Files**: browse your folders, search with Spotlight, open or reveal items in Finder.
- **Apps**: manage the Quick Tools tiles, including icons, colors, and ordering.
- **Settings**: General, AI Providers, Permissions, Assistant Tools, Quick Tools, About.

---

## Requirements

- macOS 14 (Sonoma) or newer.
- Xcode 15 or newer to build.
- XcodeGen to generate the project, or add the sources to a project by hand.
- An API key for at least one provider: Anthropic, OpenAI, Google Gemini, OpenRouter, or Groq.

---

## Building

### Option 1: generate the project with XcodeGen (recommended)

```bash
brew install xcodegen
./Scripts/bootstrap.sh
```

`Scripts/bootstrap.sh` runs `xcodegen generate` from `project.yml` and opens
`Jarvis.xcodeproj`. The generated project is intentionally not committed, so file
moves can never leave a stale `pbxproj` behind.

Then select the **Jarvis** scheme, set your development team if you sign with an
account, and run.

For automation features to work reliably, build and run the app as a normal
signed application rather than relying on a debugger session that changes the
bundle identity, because macOS tracks Automation and Accessibility grants per
bundle and per signature.

### Option 2: create the project by hand

1. Xcode, File, New, Project, macOS, App. Name it `Jarvis`, interface SwiftUI,
   language Swift, no tests for now.
2. Delete the generated `ContentView.swift` and `JarvisApp.swift` if Xcode
   created them inside your own source folder, then drag the whole `Jarvis/`
   folder from this repository into the project, choosing "Create groups" and
   adding it to the app target.
3. Set the deployment target to macOS 14.0.
4. Set the bundle identifier to something you own, for example
   `com.yourname.jarvis`, and either keep `com.jarvis.desktop` in
   `ApiKeyStore` defaults or update it in `KeychainStore.shared` usage.
5. Set **Info.plist File** to `Jarvis/Support/Info.plist` and
   **Code Signing Entitlements** to `Jarvis/Support/Jarvis.entitlements`.
6. Set the asset catalog names: **App Icon** to `AppIcon` and **Global Accent
   Color** to `AccentColor`.
7. If you enable hardended runtime for notarization, keep the Apple Events
   entitlement enabled, otherwise automation will be blocked.

### Build from the command line

```bash
xcodebuild -project Jarvis.xcodeproj -scheme Jarvis -configuration Debug build
```

### Static checks

```bash
./Scripts/verify.sh
```

This runs `Scripts/check_sources.py`, which needs only Python 3. It checks
bracket balance, scans for emoji and pictographs, looks for committed API keys,
rejects leftover TODO and FIXME markers, validates every JSON asset and plist,
verifies that namespaced API references resolve, rejects key paths into tuple
elements, and confirms that every declared assistant tool has both a schema and
an execution handler.

---

## First run

1. A setup sheet appears. Enter the name used in greetings, and grant the
   permissions you want. Each row explains why the permission is needed before
   macOS shows its own prompt.
2. Add an API key in **Settings, AI Providers**. Pick a provider, paste the key,
   press **Save key**, then choose the model. Save a different key per provider
   if you like; a single key is enough.
3. The dashboard fills in as the services start: the clock ticks, the system
   widget samples every three seconds, the calendar cache refreshes, and the
   weather appears once you set a location in **Settings, General**.

---

## Permissions

All permission requests are explained in the app before the system prompt
appears, and each one can be revoked at any time in System Settings, Privacy and
Security. Reset a grant during development with:

```bash
tccutil reset AppleEvents com.jarvis.desktop
tccutil reset Calendar com.jarvis.desktop
tccutil reset Reminders com.jarvis.desktop
tccutil reset Microphone com.jarvis.desktop
```

| Permission | Why JARVIS asks | Where it is used |
| --- | --- | --- |
| Automation (Apple Events) | Open browser tabs, control music playback, ask Finder for information | `BrowserAutomation`, `MusicAutomation`, `AppleScriptRunner` |
| Accessibility | Read window state and drive menus in other apps | `PermissionService`, optional, never required for the core features |
| Calendar | Read your schedule and create events you ask for | `CalendarAutomation`, Up Next, Calendar screen |
| Reminders | Create reminders for homework and tasks | `CalendarAutomation.createReminder` |
| Microphone and Speech | Dictate a message into the assistant input | `SpeechRecognitionService` |
| Files and folders | Browse and reveal items, subject to the path guard | `FilesView`, `FileSearchService` |

The automation status cannot be queried without prompting, so the Settings screen
offers a harmless probe: it asks Finder for the name of your home folder, which
is enough to make macOS show the consent sheet and to report the result.

---

## Adding API keys

1. Open **Settings, AI Providers**.
2. Choose the provider row you want and press **Open the key page** to create a key
   at the provider's console.
3. Paste the key into the secure field and press **Save key**. The stored key is
   shown from then on only as a masked preview such as `sk-a...f9c2`.
4. Choose the model for that provider in the same card, or type any model id and
   press **Use this model**. The dropdown is a convenience list, so a model
   released after this build still works.
5. Select the provider that powers the assistant in the **Active assistant** card
   at the top.

Keys are stored as keychain items of class `kSecClassGenericPassword` with the
service set to the app bundle identifier and the account set to
`provider.<id>.apiKey`, using `kSecAttrAccessibleAfterFirstUnlock`. They are
never written to `UserDefaults`, a plist, the source tree, logs, or error
messages. You can inspect them in Keychain Access, and `APIKeyStore` is the only
type that reads them back, at the moment a request is sent.

---

## Assistant capabilities

The assistant is offered these tools, each of which can be disabled in
**Settings, Assistant Tools**:

| Tool | What it does | Confirmation |
| --- | --- | --- |
| `open_application` | Launches an installed app by name or bundle id through `NSWorkspace` | no |
| `list_installed_applications` | Lists the Applications folders | no |
| `open_url` | Opens an address in the default browser | no |
| `open_browser_tab` | Opens a tab or window in Chrome, Safari, Edge, Brave, or Arc through Apple Events | no |
| `search_web` | Runs a search on Google, DuckDuckGo, Bing, or YouTube | no |
| `open_file_or_folder` | Opens a path with its default handler, after the path guard | no |
| `reveal_in_finder` | Selects an item in a new Finder window | no |
| `find_files` | Searches your home folder through Spotlight | no |
| `run_applescript` | Runs short AppleScript, screened for shell escapes and destructive calls | yes, by default |
| `run_terminal_command` | Runs a whitelisted read only command | always |
| `create_calendar_event` | Creates an EventKit event with an alarm | EventKit permission |
| `create_reminder` | Creates an EventKit reminder | EventKit permission |
| `list_upcoming_events` | Reads the schedule ahead | no |
| `control_music_playback` | Play, pause, skip, or report the current track in Spotify or Music | no |
| `get_system_status` | Reports processor, memory, disk, and network | no |
| `create_task` | Adds a dashboard to-do | no |
| `create_homework` | Adds an assignment | no |
| `complete_task` | Marks a to-do done by title | no |
| `save_note` | Saves a quick note | no |

Assistant turns are bounded: at most six model turns and fourteen tool calls per
request, after which the assistant is told to answer with what it has.

---

## Safety model

Four independent layers stand between the model and your machine.

1. **Tool allowlist.** The model can only call tools that are advertised, and only
   those you left enabled in Settings. A call to anything else is answered with an
   error instead of being executed.
2. **Path guard.** `PathGuard` allows the home folder, `/tmp`, `/private/tmp`,
   `/Applications`, `/Volumes`, and `/Users`. Everything else is refused before an
   API is touched, in both the Finder automation and the command whitelist.
3. **Command whitelist.** Terminal commands never pass through a shell. The binary
   must match a known absolute path, every argument is checked against that
   binary's rules, path arguments must sit inside an allowed root, and shell
   metacharacters are rejected. Binaries that write, delete, install, download,
   escalate privileges, or open a shell are not in the list at all, so the
   assistant cannot propose them.
4. **Explicit confirmation.** Every whitelisted command shows a dialog with the
   exact text and the reason, and the tool call is suspended until you answer.
   Unanswered requests are declined automatically after two minutes, and a refusal
   is reported back to the model, which is told not to retry.

AppleScript gets its own screening: `do shell script`, synthetic keystrokes,
script loading, Terminal control, deletions, and volume changes are refused, and
the run can require a confirmation dialog as well.

---

## Architecture

```
Jarvis/
  App/            JarvisApp, ContentView shell, menus, navigation state
  Theme/          Design tokens, reusable components, display mappings
  Models/         SwiftData models and value types (tasks, homework, notes, events,
                  focus sessions, chat history, shortcuts, metrics, weather)
  Security/       KeychainStore, APIKeyStore, PermissionService
  AI/             Provider protocol, provider implementations, streaming, the tool loop
  Automation/     Apple Events, Finder, browsers, music, EventKit, whitelist, bridge
  Services/       Composition root and domain services (tasks, notes, calendar cache,
                  system monitor, weather, clock, speech, focus timer, quick tools)
  Views/          Dashboard, Assistant, Tasks, Calendar, Homework, Files, Apps, Settings
  Support/        Info.plist, entitlements, logging
```

### How one assistant turn flows

```
AssistantPanel -> ChatViewModel.send()
  -> AssistantContext.systemPrompt()          live environment and enabled tools
  -> AIChatService.run()                      the provider agnostic loop
       -> AIProviderFactory.makeProvider()    Anthropic, OpenAI, Gemini, OpenRouter, Groq
       -> provider.streamChat()               SSE decoded into text and tool call fragments
       -> AutomationToolBridge.execute()      one action per tool call, main actor
            -> ApplicationLauncher / BrowserAutomation / FinderAutomation
            -> AppleScriptRunner / ShellCommandRunner (+ confirmation dialog)
            -> CalendarAutomation / services for local data
       -> tool results fed back, loop repeats until the model answers
  -> transcript updated and persisted with SwiftData
```

### Adding a provider

1. Add a case to `AIProviderID` in `AI/AIProvider.swift`, including its display
   name, keychain account, console URL, and model list.
2. Write the wire format in a new file under `AI/Providers/`. Either implement
   `AIProvider` directly, as `AnthropicProvider` and `GeminiProvider` do, or reuse
   `OpenAICompatibleProvider` with a new `OpenAICompatibleConfiguration`, as
   OpenAI, OpenRouter, and Groq do.
3. Return it from `AIProviderFactory.makeProvider(for:)`.

Nothing in the chat view, the tool loop, or the settings list needs to change: the
settings screen is driven by `AIProviderID.allCases` and `AIProviderFactory.descriptor(for:)`.

### Adding an assistant tool

1. Add the name to `AssistantToolName` and a schema in `AssistantToolCatalog`.
2. Handle the name in `AutomationToolBridge.execute` and implement the action,
   returning `AssistantToolResult.success` or `.failure`.
3. If the action needs approval, request it from `AutomationConfirmationCenter`
   before running.

`Scripts/verify.sh` fails if a tool name, its schema, and its handler drift apart.

### Persistence

SwiftData stores tasks, homework, notes, the calendar cache, focus sessions, chat
history, and Quick Tools tiles. The store lives in the app container under
Application Support. If the store cannot be opened, the app falls back to an
in-memory store and shows a banner explaining that this session will not persist.

---

## Privacy

- No analytics, no telemetry, no JARVIS server.
- Conversations are sent only to the provider you select, using your own key.
- Weather uses Open-Meteo, which needs no account. The optional "use my current
  location" button is the only call that leaves your machine before you have typed
  a location, and it is a one time lookup against ipapi.co to turn your address
  into a city name.
- Chat history, tasks, notes, and homework never leave the machine.
- Logs use `os.Logger` with subsystem `com.jarvis.desktop` and never include API
  keys, message bodies, or command text.

---

## App Sandbox

The default entitlements ship with `com.apple.security.app-sandbox` set to
`false`, because launching arbitrary applications, sending Apple Events to other
apps, and revealing arbitrary folders are not possible from inside the sandbox
without additional exceptions. The other entitlements (network client, Apple
Events, user selected files, calendar, audio input) are declared so the project is
ready if you decide to sandbox it.

For Mac App Store distribution, set `app-sandbox` to true and expect these
limitations: automation targets outside your app require user consent and may be
blocked, `run_terminal_command` cannot launch `/usr/bin/*` binaries, and the file
browser is limited to user selected locations.

---

## Keyboard shortcuts

| Shortcut | Action |
| --- | --- |
| Command 1 to Command 7 | Jump to Home, Tasks, Calendar, Homework, Files, Apps, Settings |
| Command Comma | Open Settings |
| Command Shift A | Show or hide the assistant column |
| Command R | Refresh calendar and weather |
| Command Shift T | Start or pause the focus timer |
| Command Shift A in the Assistant menu | Same as above, or use the menu for clearing the conversation |

---

## Troubleshooting

**The automation prompt never appears.**
Run the check in **Settings, Permissions**. If it fails, open System Settings,
Privacy and Security, Automation, and enable JARVIS for the target application.
While developing, `tccutil reset AppleEvents com.jarvis.desktop` clears earlier
answers.

**A key that worked yesterday reports an authentication error.**
Confirm the key is still active at the provider, and that the provider row you
saved it to matches the provider selected in **Active assistant**.

**The model name is rejected.**
Providers rename models. Type the current id into the model field and press
**Use this model**.

**Storage fell back to memory.**
The banner explains why. This normally means the store file could not be opened,
for example because another copy of the app holds an incompatible store. Quit the
app, remove the container under Application Support, and launch again.

**Weather shows "Add a location in Settings".**
Set a city in **Settings, General, Weather**, or press **Use my current location**.

---

## Verification status

- `Scripts/verify.sh` passes on the current tree: 84 Swift files, balanced
  delimiters, no emoji, no committed keys, valid JSON and plists, every
  namespaced reference resolved, and all 19 assistant tools wired end to end.
- The project has not been compiled in a CI environment yet. The first `xcodebuild`
  run on your Mac is the real compile check; if a signature mismatch shows up, it
  will be in the SwiftUI view layer rather than in the services, which are written
  against stable APIs.

---

## License

Provided as is, for personal use. See the repository owner for terms.

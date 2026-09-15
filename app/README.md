# Convert-Pheno Desktop

The graphical interface runs **only in Tauri**, including during development.
There is no browser application or browser preview. Vite compiles the interface
into local assets; Tauri loads those assets without a frontend HTTP server.

## Development

Install the repository's Perl dependencies, Node.js dependencies, Rust, and the
native Tauri build prerequisites for your platform. Then, from this directory:

```sh
npm install
npm run desktop
```

This builds the interface and opens the native application. After changing
frontend code, restart this command to rebuild the embedded assets.

The development application starts the repository's Mojolicious API using the
installed Perl interpreter. It selects a loopback port and generates credentials
for that session. Native file dialogs authorize file handles through the API;
conversion logic remains in Perl. Closing the application stops its engine and
active worker. Run history is stored in the platform application-data directory.

## Appearance And Menus

Settings offers Light, Dark, and Follow system themes, plus visibility controls
for the explorer, inspector, and task panel. Preferences persist on this device.
Open Settings from the application menu on macOS or the Edit menu elsewhere.

File, Edit, View, Conversion, and Help are native menus. Standard editing commands
act on the focused editor. Open/save workspace and run shortcuts use Command on
macOS and Control on Windows/Linux.

## Runs And Output Files

The Runs sidebar keeps the active job first, followed by queued jobs and history.
Queued runs display their queue position. Filter by conversion, run ID, status,
or source filename. One conversion executes at a time.

Each run has its own controls. Cancel a running conversion, remove a queued one,
or cancel all pending runs without stopping the active conversion. These actions
ask for confirmation. Each run has a three-dot actions menu with icons.
Completed runs offer Open output folder. Delete from history hides a finished
run from the list, including after restarting the app; source files and generated
outputs remain on disk. Delete run and output files permanently removes the run
and its generated output folder after confirmation; original inputs and copies
saved elsewhere remain untouched. Unexpected files in the output folder block
deletion, as do active runs using those outputs. Cancel active or queued runs
before deleting their entry.
The toolbar and native Runs menu also offer bulk history or disk deletion. Bulk
disk deletion includes finished runs previously hidden from history; active runs
are kept, and any files that cannot be safely deleted are reported.

For a failed or cancelled run, Set up again restores the conversion options but
does not immediately start a job. Reselect the inputs and any custom destination;
the application does not retain payloads solely to support retries.

Configure output shows the full parent folder before submission. Default output
goes into a separate `<run-id>/outputs` folder under the application data folder.
Choosing another parent creates a `convert-pheno-<run-id>` subfolder there. Each
run displays its exact planned destination, then the saved location on completion.

## Inspecting records

For mapping-based conversions, load a synthetic example or select your mapping
file, then open Mapping. The YAML editor has highlighting, line numbers, search,
indentation and undo. Validate and use copy checks the mapping with the Perl
engine; Save as writes a new file without overwriting the original.

Terminology auditing is optional and disabled by default because it adds lookup
reporting and XLSX-writing work. Enable Create terminology audit before a supported
conversion to produce one complete Excel report. CLI and API clients can continue
to request TSV or XLSX explicitly.
Open the completed run's Terminology Review tab to filter decisions, inspect
evidence and download the complete report. Edit the mapping, validate, then rerun.
The review defaults to Unique terms. Repeated failed lookups are grouped across
individuals even when their raw values differ. Different source fields, queries,
ontologies and resolution evidence remain separate; cache hits do not split groups.
Expand Evidence to see source rows and values, or select
All occurrences. Group counts cover the retained preview only; the complete
occurrence totals and downloadable audit are unchanged.

Help includes About Convert-Pheno and Check for Updates. Update checks contact
GitHub only when requested, send no conversion data, and never install anything.
The check compares the desktop version with the latest stable version tag;
it does not guarantee a packaged desktop installer is available for each platform.

On Linux systems without a `/dev/dri` graphics device, such as some virtual
machines, the desktop automatically uses WebKit software compositing. An explicit
`WEBKIT_DISABLE_COMPOSITING_MODE` environment setting is always respected.

Use the left-panel button in the toolbar to collapse or reopen Sources and Runs.
The choice is remembered between launches and also available in View and Settings.

In OMOP table previews, concept-ID cells have a database icon. Select one to see
its label and available vocabulary metadata in the right inspector. This uses an
exact, read-only lookup in the installed OHDSI database. It does not change or
validate the output. Missing concepts and an unavailable database are reported
explicitly; concept ID zero means no concept was assigned.

Input and output records are not automatically paired: a conversion may combine
many source rows into one person. Use the existing provenance and terminology
report to review mappings.

## Verification

```sh
npm run typecheck
npm test
cargo test --manifest-path src-tauri/Cargo.toml --offline
```

Unsigned test installers are built manually with the `Build desktop test
installers` GitHub Actions workflow. It packages a private Perl runtime and the
engine resources, relocation-tests that runtime, and produces short-lived
AppImage, DMG, and NSIS artifacts. These pre-release packages do not depend on a
system Perl. The default `macos-linux` run publishes the inspected installers
and checksums together as a GitHub prerelease once all four jobs pass. Choose
`windows` to run Windows packaging diagnostics independently; that run retains
successful packages as workflow artifacts and does not publish a release.

The workflow builds Linux x86_64 and ARM64, macOS Apple Silicon and Intel, and
Windows x86_64 packages. The macOS package uses an ad-hoc signature and the
Windows package is unsigned; public distribution still requires the respective
Developer ID/notarization and Authenticode release credentials.

`ohdsi.db` remains an optional external download because it is approximately
3.2 GB. It is not embedded in the application installers.

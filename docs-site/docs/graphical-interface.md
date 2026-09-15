---
id: graphical-interface
title: Desktop Application
slug: /graphical-interface
---

The Convert-Pheno desktop application provides a native interface for local,
interactive conversions. It uses the same core engine and public route registry
as the command-line interface.

## How it works

1. Choose the source and target formats. The application shows only supported
   routes and relevant options.
2. Select source files, mapping files, dictionaries, or table packages as
   required by that route. Synthetic examples are available for trying the
   workflow first.
3. Review the output location and start the conversion. Runs execute in a local
   queue, so the application remains responsive.
4. Inspect generated records or tables, review terminology decisions when an
   audit was requested, and open or export the output files.

The **Sources**, **Runs**, **Outputs**, **Terminology Review**, and **Compare**
views keep input selection, execution, and result inspection within one local
workspace. The application does not send participant data to a remote service.

![A completed synthetic BFF-to-CSV conversion with the generated table open in the Desktop Application](../static/img/desktop-output-preview.png)

*A completed synthetic BFF-to-CSV conversion. Generated files remain available
from the run history and can be inspected or saved from the Outputs view.*

:::info[Version availability]
The desktop application is available from **Convert-Pheno 0.35** for Linux,
macOS, and Windows.
:::

:::note[Current interface]
This is the **current graphical interface**. The [original Convert-Pheno Web App](https://convert-pheno.cnag.cat/)
is a **legacy demonstration** and does not reflect current conversion support.
:::

## Install

Platform installers are prepared for Linux x86_64 and ARM64, macOS Apple
Silicon and Intel, and Windows x86_64.

:::warning[Test packages]
The current GitHub pre-releases are unsigned compatibility builds. They are
provided to test installation and launch behavior on real computers, not as the
stable Convert-Pheno release. macOS may require explicit approval in Privacy &
Security, and Windows may show a SmartScreen warning.
:::

Open [Convert-Pheno releases](https://github.com/CNAG-Biomedical-Informatics/convert-pheno/releases),
choose the latest desktop test build, and download the installer matching your
operating system and processor. The adjacent `.sha256` file records the checksum
produced after package inspection.

### macOS

Choose `convert-pheno-macos-apple-silicon.dmg` for an Apple Silicon Mac or
`convert-pheno-macos-intel.dmg` for an Intel Mac. **About This Mac** shows your
chip or processor. Open the DMG, drag **Convert-Pheno** into **Applications**,
then launch it there.

The test build is not Apple-notarized. If macOS blocks its first launch, open
**System Settings > Privacy & Security** and approve the application using
**Open Anyway** after attempting to open it.

### Linux

Download the AppImage for your processor: `linux-x86_64` for most Intel/AMD
computers or `linux-aarch64` for ARM64. Make it executable and launch it:

```bash
chmod +x convert-pheno-linux-x86_64.AppImage
./convert-pheno-linux-x86_64.AppImage
```

Use the `linux-aarch64` filename instead for ARM64.

### Windows

Windows packaging is being tested separately and is not yet included in the
desktop prereleases. Once available, download
`convert-pheno-windows-x86_64-setup.exe`, run the installer, and launch
Convert-Pheno from the Start menu. The unsigned test installer may trigger
SmartScreen; review the download source before choosing **More info > Run anyway**.

These packages include the core engine and its runtime. No separate Node.js,
Rust, or CPAN installation is needed.

## First conversion

Choose BFF as the source and CSV as the target, then load the supplied synthetic
example. Review **Configure output**, start the conversion, and select the
completed run to inspect its table in **Outputs**. Use **Open output folder**
from the run's three-dot menu to find the generated files.

## Output folders and run history

**Configure output** shows the destination before a conversion starts. By
default, each run gets its own folder under the application's data directory.
If you choose a different parent folder, the application creates a
`convert-pheno-<run-id>` subfolder there. The completed run shows the saved path.

The three-dot menu beside each run offers two different deletion actions:

| Action | What happens |
| --- | --- |
| **Delete from history** | Hides the finished run; generated files remain on disk |
| **Delete run and output files** | Deletes the run and its generated output folder after confirmation |

Original input files and copies saved elsewhere remain untouched. Cancel active
or queued runs before deleting them. The Runs menu also provides bulk deletion;
deleting output files in bulk includes finished runs previously hidden from history.

Runs execute one at a time. You can queue another conversion while one is running,
or cancel a run using its menu. Closing the application stops active work; wait
for completion before quitting if you want to keep the result.

## Privacy and scope

The native file picker grants the private local engine access only to locations
selected by the user. Inputs remain unchanged. Run state and generated files are
stored under the operating system's application-data directory or in an output
folder selected by the user. Participant payloads are not logged or sent to an
external service.

The desktop application accepts JSON for Beacon v2, Phenopacket v2, FHIR, openEHR, and
OMOP, plus role-based uploads for OMOP table files or ZIP packages, CSV, REDCap, CDISC-ODM,
Dataset-JSON, Dataset-XML, cBioPortal study packages, and i2b2, PCORnet, or
Sentinel table packages. Entity-aware BFF routes also accept the optional
compact Mapping V2 metadata file advertised for that route. Each source has a
synthetic example drawn from the regression fixtures. Runs are queued locally,
so the interface remains responsive while the core engine performs a conversion.
Use the [command-line interface](use-as-a-command-line-interface) when scripting
or streaming is preferable.

## OHDSI terminology database

`ohdsi.db` is not included in the installers because it is approximately 3.2 GB.
Open **Resources**, download the current file from Google Drive, and select
**Install downloaded database**. The application verifies its declared size and
SHA-256 before making OHDSI-dependent routes available.

## Terminology review

Auditing is **optional and off by default**. Enable **Create terminology audit**
under **Configure output** before starting a supported conversion. It creates a
color-coded XLSX report and adds processing time. After conversion it counts exact or configured terms,
similarity matches, unresolved terms, and source fallbacks. Filter the preview
by text, ontology, or review action.

Open **Terminology Review** on the completed run. **Unique terms** groups repeated
decisions across individuals so one unresolved query does not look like many
different problems. Different fields, queries, or lookup evidence can still
appear separately. Select **All occurrences** or expand **Evidence** to inspect
the source rows retained in the preview.

The preview is limited; download the XLSX report for every decision. For a
mapping-based conversion, edit the mapping in **Mapping**, select **Validate and
use copy**, and run the conversion again. **Save as** writes the edited mapping
to a new file. See [Terminology Search](terminology-search) for the report fields
and suggested review order.

<details>
<summary>Testing a macOS prerelease</summary>

1. Install the matching DMG and launch from Applications.
2. Run the synthetic BFF-to-CSV example and check its table preview.
3. Open the output folder and confirm that the CSV exists.
4. Quit after completion, reopen, and check that the run remains in history.
5. Delete that run from history and confirm that its CSV still exists.
6. Run a second example and try **Delete run and output files**; confirm that
   only that run's generated folder is removed.

When reporting a problem, include the test-build tag, macOS version, processor,
the failed step, and the displayed error. Use synthetic data for screenshots.

</details>

<details>
<summary>Development: run from a source checkout</summary>

Install the frontend dependencies and let Tauri start the private local engine:

```bash
cd app
npm ci
npm run desktop
```

Node.js 24, Rust 1.86, Tauri's platform build libraries, Perl, and the normal
Convert-Pheno dependencies are required for source development.

</details>

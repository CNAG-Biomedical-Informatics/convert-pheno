---
title: Download & Installation
sidebar_label: Download & Installation
slug: /download-and-installation
---

import Tabs from '@theme/Tabs';
import TabItem from '@theme/TabItem';

Use **Desktop** for a graphical interface or the **CLI** for terminal commands
and automated workflows. Both use the same conversion engine.

<Tabs defaultValue="desktop">
<TabItem value="desktop" label="Desktop">

## Desktop Application

Download the application for Linux, macOS, or Windows. The conversion engine is
included; no command-line knowledge or separate runtime installation is needed.

[Install Desktop](graphical-interface)

Prefer a demonstration? [Watch the Desktop tutorial playlist on YouTube](https://www.youtube.com/playlist?list=PLIMAoZdq9jK0).

</TabItem>
<TabItem value="cli" label="CLI">

## CLI: Non-Containerized {#non-containerized}

Install `convert-pheno` directly on Linux, macOS, or Windows using CPAN,
GitHub, or Conda. See the guide for platform requirements and commands.

[Install the CLI locally](download-and-installation/non-containerized)

## CLI: Docker {#containerized}

Already use Docker? Run the CLI from a prebuilt image without installing its
dependencies on your computer. This does not install Desktop.

[Run the CLI with Docker](download-and-installation/docker-based)

</TabItem>
</Tabs>

**For developers:** see the [HTTP(s) API](use-as-an-api) or
[Perl/Python interfaces](use-as-a-module) to integrate conversions into other software.

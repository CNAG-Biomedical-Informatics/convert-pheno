# Preparing a release

Use the same annotated tag for CPAN, Docker, and Desktop. For release 0.35,
the core and API version is `0.35`; Desktop uses `0.35.0`.

## Before tagging

1. Update VERSION, the core/API versions, Desktop manifests and lockfiles,
   and the documentation version. Keep Changes brief and set its release date.
2. Run `perl scripts/check-release.pl 0.35` from the repository root.
3. Run `prove -j6 -lr t api/perl/t` and the relevant extended validators in `xt`.
4. Run frontend tests/build, native tests, and the documentation build.
5. Build and test the CPAN distribution with `make disttest`. Check that its
   MANIFEST excludes app/, local build trees, internal notes, and ohdsi.db.
6. Test Desktop conversions on real machines, including Windows. CI checks
   package installation and startup, but does not replace this review.
7. Commit and push the reviewed changes. Do not move a published release tag.

## Tag and build

After approval, create and push the annotated tag:

```bash
git tag -a 0.35 -m "Convert-Pheno 0.35"
git push origin 0.35
```

This starts the Docker build/push and the five-platform Desktop build.
Docker publishes `0.35` and `latest`. Desktop attaches installers and individual
SHA-256 checksum files to a **draft** GitHub release for the existing tag.
Desktop test tags do not trigger either stable-release workflow.

Inspect both workflows before publishing the draft. If the Desktop build
fails, rerun failed jobs after diagnosis; do not publish an incomplete set.
An existing draft can receive rebuilt assets, but the workflow refuses to
overwrite assets on a published release.

The Desktop packages are Linux x86_64/ARM64 AppImages, macOS Intel/Apple Silicon
DMGs, and a Windows x86_64 installer. macOS packages are not notarized and
Windows packages are unsigned. OHDSI remains an optional external download.

## CPAN and publication

Manually run **Publish to CPAN**, supplying `tag: 0.35`. It checks out the tag,
checks version agreement, builds and tests the source distribution, then uploads
it using the existing CPAN credentials. This publishes to CPAN; it is not a dry run.

Once all deliverables are verified, replace the draft's placeholder notes with
the essential release notes and publish it. Deploy documentation from the
release commit and check its installer, Docker, CPAN, and API-reference links.

For compatibility tests before release, manually run **Build desktop installers**
with `all`, `macos-linux`, or `windows`. These runs create clearly marked test
pre-releases and do not publish Docker images or CPAN distributions.

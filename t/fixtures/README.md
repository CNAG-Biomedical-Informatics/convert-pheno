# Shared test fixtures

`ohdsi-concepts.tsv` is the minimal exact-match subset of the Athena-OHDSI
concept table required by the active regression suite. Tests generate a
temporary indexed `ohdsi.db` from this text file, so active CI does not depend
on the optional 2.2 GB database.

Labels that exercise fallback behavior are intentionally absent. Extended
tests under `xt/` continue to use the complete database when it is available.

`http-omop-request.json` is a compact table-oriented OMOP request used to test
the shared HTTP conversion service. It is synthetic and contains no participant
data from a real study.

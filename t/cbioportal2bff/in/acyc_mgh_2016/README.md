# cBioPortal fixture

This clinical-only fixture is a subset of the public `acyc_mgh_2016` study in
the official [cBioPortal DataHub](https://github.com/cBioPortal/datahub/tree/master/public/acyc_mgh_2016),
retrieved from DataHub commit `eb53cc4a9b69fac59e3fa8db9d5204b2d25ba73e`.
The patient table, sample table, study metadata, clinical meta files, and the
all-samples case list are retained unchanged. Molecular files are intentionally
omitted because this fixture exercises cBioPortal clinical study input only.

The source study data are distributed under the ODC Open Database License
(ODbL) 1.0. See `LICENSE` in this directory.

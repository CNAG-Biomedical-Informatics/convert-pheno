!!! Warning "openEHR to BFF - Experimental"
    This mapping is still **experimental**.
    It currently documents the implemented `openEHR -> BFF` behavior for EHRbase-style canonical JSON/YAML compositions and may change as more openEHR payloads are tested.

!!! Note "Schemas and source profile"
    * [Beacon v2 Models - individuals](https://docs.genomebeacons.org/schemas-md/individuals_defaultSchema)
    * openEHR canonical `COMPOSITION` JSON/YAML input (current implementation target)

!!! Info "Information"
    The current mapper groups openEHR input by patient identity before mapping.
    Patient identity must be resolvable from the payload or envelope, and multiple compositions for the same patient are aggregated into one Beacon `individual`.
    For raw composition arrays, automatic splitting uses only embedded patient-scoped identifiers such as `ehr_status.subject.external_ref.id.value` or `PARTY_SELF.external_ref.id.value`; composition-level ids are not used as patient keys.

    Terms with an external `defining_code` keep their source CURIE.
    Uncoded `DV_TEXT` terms are emitted with synthetic `openEHR:` ids so Beacon ontology terms still have both `id` and `label`.

--8<-- "tbl/mapping-openehr2bff.md"

import type {SidebarsConfig} from '@docusaurus/plugin-content-docs';

const sidebars: SidebarsConfig = {
  docsSidebar: [
    {
      type: 'doc',
      id: 'overview',
      label: 'Overview',
    },
    {
      type: 'category',
      label: '📘 Start Here',
      items: [
        {
          type: 'doc',
          id: 'what-is-convert-pheno',
          label: 'What Is Convert-Pheno?',
        },
        {
          type: 'doc',
          id: 'quickstart',
          label: '5-Minute Quickstart',
        },
        {
          type: 'doc',
          id: 'supported-formats',
          label: 'Supported Formats',
        },
        {
          type: 'doc',
          id: 'choose-an-interface',
          label: 'Which Interface?',
        },
      ],
    },
    {
      type: 'category',
      label: '📦 Download & Installation',
      link: {
        type: 'doc',
        id: 'download-and-installation',
      },
      items: [
        {
          type: 'doc',
          id: 'download-and-installation/non-containerized',
          label: 'Non-Containerized',
        },
        {
          type: 'doc',
          id: 'download-and-installation/docker-based',
          label: 'Docker',
        },
      ],
    },
    {
      type: 'category',
      label: '🛠️ Use',
      items: [
        {
          type: 'doc',
          id: 'conversion-recipes',
          label: 'Choose a Conversion',
        },
        {
          type: 'doc',
          id: 'use-as-a-command-line-interface',
          label: 'Command-Line Interface',
        },
        {
          type: 'doc',
          id: 'use-as-a-module',
          label: 'Module',
        },
        {
          type: 'doc',
          id: 'use-as-an-api',
          label: 'API',
        },
      ],
    },
    {
      type: 'category',
      label: '🧬 Format Guides',
      items: [
        {
          type: 'doc',
          id: 'bff',
          label: 'Beacon v2 Models (BFF)',
        },
        {
          type: 'doc',
          id: 'cbioportal',
          label: 'cBioPortal (Experimental)',
        },
        {
          type: 'category',
          label: 'CDISC',
          items: [
            {
              type: 'doc',
              id: 'dataset-json',
              label: 'Dataset-JSON (Experimental)',
            },
            {
              type: 'doc',
              id: 'cdisc-odm',
              label: 'ODM',
            },
          ],
        },
        {
          type: 'doc',
          id: 'csv',
          label: 'CSV',
        },
        {
          type: 'doc',
          id: 'fhir',
          label: 'FHIR R4 (Experimental)',
        },
        {
          type: 'doc',
          id: 'omop-cdm',
          label: 'OMOP-CDM',
        },
        {
          type: 'doc',
          id: 'openclinica',
          label: 'OpenClinica ODM (Experimental)',
        },
        {
          type: 'doc',
          id: 'openehr',
          label: 'openEHR (Experimental)',
        },
        {
          type: 'doc',
          id: 'pxf',
          label: 'Phenopackets v2 (PXF)',
        },
        {
          type: 'doc',
          id: 'redcap',
          label: 'REDCap',
        },
      ],
    },
    {
      type: 'category',
      label: '⚙️ Technical Details',
      items: [
        {
          type: 'doc',
          id: 'implementation',
          label: 'Implementation',
        },
        {
          type: 'doc',
          id: 'mapping-steps',
          label: 'Mapping Steps',
        },
        {
          type: 'doc',
          id: 'development-validation',
          label: 'Development Validation',
        },
        {
          type: 'category',
          label: 'Mapping Tables',
          items: [
            {
              type: 'doc',
              id: 'bff2omop',
              label: 'BFF to OMOP',
            },
            {
              type: 'doc',
              id: 'bff2pxf',
              label: 'BFF to PXF',
            },
            {
              type: 'doc',
              id: 'cbioportal2bff',
              label: 'cBioPortal to BFF',
            },
            {
              type: 'doc',
              id: 'datasetjson2bff',
              label: 'Dataset-JSON to BFF',
            },
            {
              type: 'doc',
              id: 'fhir2bff',
              label: 'FHIR to BFF',
            },
            {
              type: 'doc',
              id: 'omop2bff',
              label: 'OMOP to BFF',
            },
            {
              type: 'doc',
              id: 'openehr2bff',
              label: 'openEHR to BFF',
            },
            {
              type: 'doc',
              id: 'pxf2bff',
              label: 'PXF to BFF',
            },
          ],
        },
      ],
    },
    {
      type: 'category',
      label: '❓ Help',
      items: [
        {
          type: 'category',
          label: 'Mapping Files',
          link: {
            type: 'doc',
            id: 'mapping-files',
          },
          items: [
            {
              type: 'doc',
              id: 'tbl/mapping-file',
              label: 'Reference',
            },
          ],
        },
        {
          type: 'link',
          href: 'https://colab.research.google.com/drive/1T6F3bLwfZyiYKD6fl1CIxs9vG068RHQ6',
          label: 'Google Colab',
        },
        {
          type: 'doc',
          id: 'troubleshooting',
          label: 'Troubleshooting',
        },
        {
          type: 'doc',
          id: 'faq',
          label: 'FAQs',
        },
        {
          type: 'doc',
          id: 'future-plans',
          label: 'Future Plans',
        },
      ],
    },
    {
      type: 'category',
      label: 'ℹ️ About',
      items: [
        {
          type: 'doc',
          id: 'about',
          label: 'About',
        },
        {
          type: 'doc',
          id: 'citation',
          label: 'Citation',
        },
      ],
    },
  ],
};

export default sidebars;

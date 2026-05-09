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
      label: '📘 Introduction',
      items: [
        {
          type: 'doc',
          id: 'what-is-convert-pheno',
          label: 'What Is Convert-Pheno?',
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
          label: 'Conversion Recipes',
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
        {
          type: 'link',
          href: 'https://cnag-biomedical-informatics.github.io/convert-pheno-ui/',
          label: 'Web App User Interface',
        },
      ],
    },
    {
      type: 'category',
      label: '🧬 Formats Accepted',
      items: [
        {
          type: 'doc',
          id: 'bff',
          label: 'Beacon v2 Models (BFF)',
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
        {
          type: 'doc',
          id: 'omop-cdm',
          label: 'OMOP-CDM',
        },
        {
          type: 'doc',
          id: 'cdisc-odm',
          label: 'CDISC-ODM',
        },
        {
          type: 'doc',
          id: 'csv',
          label: 'CSV',
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
          id: 'output-validation',
          label: 'Output Validation',
        },
        {
          type: 'category',
          label: 'Mapping Tables',
          items: [
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
            {
              type: 'doc',
              id: 'bff2pxf',
              label: 'BFF to PXF',
            },
            {
              type: 'doc',
              id: 'bff2omop',
              label: 'BFF to OMOP',
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
          type: 'doc',
          id: 'tutorial',
          label: 'Tutorial',
        },
        {
          type: 'link',
          href: 'https://colab.research.google.com/drive/1T6F3bLwfZyiYKD6fl1CIxs9vG068RHQ6',
          label: 'Google Colab',
        },
        {
          type: 'doc',
          id: 'usage',
          label: 'Usage',
        },
        {
          type: 'doc',
          id: 'analysis',
          label: 'Analysis',
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

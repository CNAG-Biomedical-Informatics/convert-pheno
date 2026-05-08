import {themes as prismThemes} from 'prism-react-renderer';
import type {Config} from '@docusaurus/types';
import type * as Preset from '@docusaurus/preset-classic';
import remarkMath from 'remark-math';
import rehypeKatex from 'rehype-katex';

const config: Config = {
  title: 'Convert-Pheno Documentation',
  tagline: 'Interconversion of standard data models for phenotypic data',
  favicon: 'img/CP-logo-grey.png',
  url: 'https://cnag-biomedical-informatics.github.io',
  baseUrl: '/convert-pheno/',
  organizationName: 'CNAG-Biomedical-Informatics',
  projectName: 'convert-pheno',
  onBrokenLinks: 'throw',
  onBrokenAnchors: 'throw',
  markdown: {
    mermaid: true,
    hooks: {
      onBrokenMarkdownLinks: 'throw',
    },
  },
  i18n: {
    defaultLocale: 'en',
    locales: ['en'],
  },
  presets: [
    [
      'classic',
      {
        docs: {
          sidebarPath: './sidebars.ts',
          routeBasePath: '/',
          remarkPlugins: [remarkMath],
          rehypePlugins: [rehypeKatex],
        },
        blog: false,
        theme: {
          customCss: './src/css/custom.css',
        },
      } satisfies Preset.Options,
    ],
  ],
  themes: ['@docusaurus/theme-mermaid'],
  stylesheets: [
    {
      href: 'https://cdn.jsdelivr.net/npm/katex@0.16.22/dist/katex.min.css',
      type: 'text/css',
      integrity: 'sha384-5TcZemv2l/9On385z///+d7MSYlvIEw9FuZTIdZ14vJLqWphw7e7ZPuOiCHJcFCP',
      crossorigin: 'anonymous',
    },
  ],
  themeConfig: {
    image: 'img/CP-logo.png',
    colorMode: {
      respectPrefersColorScheme: true,
    },
    navbar: {
      title: 'Convert-Pheno',
      logo: {
        alt: 'Convert-Pheno',
        src: 'img/CP-logo.png',
        srcDark: 'img/CP-logo.png',
      },
      items: [
        {
          type: 'docSidebar',
          sidebarId: 'docsSidebar',
          position: 'left',
          label: 'Docs',
        },
        {
          to: '/download-and-installation',
          label: 'Install',
          position: 'left',
        },
        {
          to: '/use-as-a-command-line-interface',
          label: 'CLI',
          position: 'left',
        },
        {
          to: '/use-as-an-api',
          label: 'API',
          position: 'left',
        },
        {
          href: 'https://convert-pheno.cnag.cat',
          label: 'Web App',
          position: 'left',
        },
        {
          href: 'https://github.com/CNAG-Biomedical-Informatics/convert-pheno',
          label: 'GitHub',
          position: 'right',
        },
      ],
    },
    footer: {
      style: 'dark',
      links: [
        {
          title: 'Docs',
          items: [
            {
              label: 'Overview',
              to: '/',
            },
            {
              label: 'Supported Formats',
              to: '/supported-formats',
            },
            {
              label: 'Troubleshooting',
              to: '/troubleshooting',
            },
          ],
        },
        {
          title: 'Project',
          items: [
            {
              label: 'Repository',
              href: 'https://github.com/CNAG-Biomedical-Informatics/convert-pheno',
            },
            {
              label: 'CPAN',
              href: 'https://metacpan.org/pod/Convert::Pheno',
            },
            {
              label: 'CNAG',
              href: 'https://www.cnag.eu',
            },
          ],
        },
      ],
      copyright: 'Copyright © 2022-2026 Manuel Rueda, CNAG.',
    },
    prism: {
      theme: prismThemes.github,
      darkTheme: prismThemes.dracula,
    },
  } satisfies Preset.ThemeConfig,
};

export default config;

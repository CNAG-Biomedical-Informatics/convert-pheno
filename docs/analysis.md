# Analysis

This page collects a few practical ways to work with `individuals.json` output once the conversion is done.

## Get quick counts from `individuals.json`

One simple option is to use `jq` to count the main arrays for each individual and write the result as tabular text:

```bash
jq -r '["id", "diseases", "exposures", "interventionsOrProcedures", "measures", "phenotypicFeatures", "treatments"], (.[] | [.id, (.diseases | length), (.exposures | length), (.interventionsOrProcedures | length), (.measures | length), (.phenotypicFeatures | length), (.treatments | length)]) | @tsv' < individuals.json > results.tsv
```

This produces one row per individual and one column per array count.

## Do the same in Python

```python
import json
import pandas as pd

with open('individuals.json', 'r') as json_file:
    data = json.load(json_file)

keys = [
    "diseases",
    "exposures",
    "interventionsOrProcedures",
    "measures",
    "phenotypicFeatures",
    "treatments",
]

result_data = [
    {
        "id": item["id"],
        **{key: len(item.get(key, [])) for key in keys},
    }
    for item in data
]

df = pd.DataFrame(result_data)
df.to_csv('results.tsv', sep='\t', index=False)
```

## Do the same in Perl

```perl
use strict;
use warnings;
use autodie;
use JSON::XS;
use Text::CSV_XS qw(csv);

open my $json_file, '<', 'individuals.json';
my $json_text = do { local $/; <$json_file> };
my $data = decode_json($json_text);
close $json_file;

my @keys = (
    "diseases",
    "exposures",
    "interventionsOrProcedures",
    "measures",
    "phenotypicFeatures",
    "treatments"
);

my $aoa = [["id", @keys]];

foreach my $item (@$data) {
    my @row = ($item->{"id"});
    foreach my $key (@keys) {
        push @row, scalar @{$item->{$key} // []};
    }
    push @$aoa, \@row;
}

csv(in => $aoa, out => "results.tsv", sep_char => "\t", eol => "\n");
```

## Example downstream statistics

Once you have `results.tsv`, you can calculate summary statistics with your preferred tooling.

### Python example

```python
import pandas as pd

df = pd.read_csv('results.tsv', sep='\t')
df = df.iloc[:, 1:]

stats = {
    'Statistic': [
        'Mean',
        'Median',
        'Max',
        'Min',
        '25th Percentile',
        '75th Percentile',
        'IQR',
        'Standard Deviation',
    ]
}

for column in df.columns:
    percentile_25 = df[column].quantile(0.25)
    percentile_75 = df[column].quantile(0.75)

    stats[column] = [
        df[column].mean(),
        df[column].median(),
        df[column].max(),
        df[column].min(),
        percentile_25,
        percentile_75,
        percentile_75 - percentile_25,
        df[column].std()
    ]

stats_df = pd.DataFrame(stats)
stats_df.to_csv('column_statistics.csv', index=False)
```

### R example

```r
df <- read.csv("results.tsv", sep = "\t")
df <- df[-1]
summary_stats <- summary(df)
write.csv(summary_stats, file = 'column_statistics.csv')
```

## Related tools

For comparison, patient matching, synthetic data, plotting, or feature extraction, see [Pheno-Ranker](https://cnag-biomedical-informatics.github.io/pheno-ranker/).

Useful entry points:

- Cohort comparison: [Pheno-Ranker cohort mode](https://cnag-biomedical-informatics.github.io/pheno-ranker/cohort/)
- Patient matching: [Pheno-Ranker patient mode](https://cnag-biomedical-informatics.github.io/pheno-ranker/patient/)
- Synthetic BFF/PXF data: [Pheno-Ranker simulator](https://cnag-biomedical-informatics.github.io/pheno-ranker/bff-pxf-simulator)
- Feature extraction / one-hot encoding: [Pheno-Ranker](https://cnag-biomedical-informatics.github.io/pheno-ranker/)

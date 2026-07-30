# mean

## Goals

### Granularity

> Can a word have multiple scores?

Yes.

`mean` scores each meaning of a word separately.

A word can have meanings with different levels of prevalence.

Most folks are familiar with the everyday word "all". But not many people know `ALL` stands for acute lymphoblastic leukemia.

### Prevalence

> Does mean measure corpus frequency?

No.

`mean` estimates prevalence for these reasons:

- Whether a joke or wordplay lands depends on the audience knowing the meaning, not on how often it appears in text.

- If you want to be confident in everyday English, you may want to learn meanings most people know rather than words that just show up a lot in written corpora.

### Coverage

> Does `mean` evaluate senses from WordNet?

No.

WordNet's coverage is limited. Jokes often use slang and vulgarity.

So, `mean` evaluates senses from a dictionary.

> Which dictionary does `mean` evaluate senses from?

`mean` evaluates senses from English Wiktionary.

Wiktionary was chosen for these reasons:

- The dataset is free.

- The coverage is extensive.

> Does `mean` evaluate senses of non-lemma forms?

Yes. `mean` looks at both lemma and non‑lemma forms.

Non-lemma forms are evaluated for these reasons:

- Phonetic jokes might depend on specific inflections.

- Throwing in non-lemma forms doesn't blow up the dataset size by a factor of ten.

> Does `mean` evaluate Wikipedia entries?

Yes. `mean` scores Wikipedia entries by treating their lead sentences as senses.

### Cost

> What's the target cost for running `mean`?

The target cost for a batch API execution is capped at $1,000.

Productivity tools often cost up to $100 a month, which comes out to about $1,200 a year. Even if you calculate the average each year, a $1,000 cap makes the yearly cost still reasonable.

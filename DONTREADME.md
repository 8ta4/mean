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

## Scoring

> Can the prevalence score be negative?

No, because it's a percentage.

Specifically, it's the percentage of Americans 10 years or older who know the definition.

- "Americans" pins it to a clear population, avoiding wishy-washy concepts like "native speakers" that are open to interpretation. Because the U.S. has the biggest number of native English speakers worldwide, it makes sense to treat it as the default audience.

- "10 years or older" filters out babies, making it easier to sanity-check the model output, as super obvious definitions should hit near 100%.

> Is the prevalence score an integer?

Nah, it's a double. Doubles allow finer ordering.

> What model does `mean` use?

`mean` uses [`gemini-3.5-flash`](https://ai.google.dev/gemini-api/docs/models/gemini-3.5-flash) for these reasons:

- Among models that cost under $10 per million output tokens without batching, have a public API, and offer solid scoring, `gemini-3.5-flash` ranks highest on [Text Arena](https://arena.ai/leaderboard/text). `gemini-3.5-flash` can be a bit hit-or-miss with its scores.

- `gemini-3.5-flash` is a production model.

- Less capable models tend to change their scores dramatically if the order of phrases to evaluate gets swapped. `gemini-3.5-flash` seems pretty resistant to this order dependency. Even though `mean` keeps the benchmark phrase in a fixed spot, the model's native resistance boosts confidence in the scores.

- `gemini-3.5-flash` allows running at a temperature of 0.

- Setting the thinking level to `minimal` effectively turns off thinking for this task.

- `gemini-3.5-flash` [supports structured outputs](https://ai.google.dev/gemini-api/docs/models/gemini-3.5-flash#:~:text=Supported-,Structured%20outputs,-Supported).

- `gemini-3.5-flash` [supports the Batch API](https://ai.google.dev/gemini-api/docs/models/gemini-3.5-flash#:~:text=Consumption%20options-,Batch%20API,-Supported).

> Does `mean` use a system prompt?

Yep.

If the list of phrases contains words that sound like commands, the model could treat them as instructions rather than just stuff to score. So the system prompt makes it crystal clear what's data and what's instruction.

> Does `mean` use a fixed `seed` for requests?

Yes.

`mean` sets the `seed` to `0`.

"[When seed is fixed to a specific value, the model makes a best effort to provide the same response for repeated requests.](https://docs.cloud.google.com/gemini-enterprise-agent-platform/models/capabilities/content-generation-parameters#seed)"

> What's the temperature `mean` uses for scoring prevalence?

`mean` runs at a temperature of 0 for scoring prevalence. The whole point is to get the model to tap into its knowledge and spit out its best estimate.

> What thinking level does `mean` use?

`mean` uses `minimal` thinking.

Setting the thinking level to `minimal` effectively turns off thinking for this task.

Allowing thinking has these downsides:

- You could be charged for thinking tokens.

- Setting `temperature` to 0 might mess up the model's thinking, since [Gemini 3.x's reasoning capabilities are optimized for the default settings](https://ai.google.dev/gemini-api/docs/whats-new-gemini-3.5#parameter-updates:~:text=The%20following%20apply,the%20default%20settings.).

> Does `mean` use structured outputs?

Yes.

Using structured outputs makes sure the API response includes the scoring fields `mean` needs.

> How many phrases are sent to the LLM per rating request?

Each request includes two phrases.

- The benchmark phrase you give to set the baseline across requests.

- The target phrase the system grabs while looping through the vocabulary.

> Is the benchmark phrase or the target phrase scored first?

The benchmark phrase gets scored first.

Scoring the benchmark phrase first makes sure it's evaluated before the target phrase's score is generated. This way, the benchmark phrase's context stays more alike across requests compared to using the reverse order.

> What's the normalization formula?

It's piecewise:

$$
\bar{X} =
\begin{cases}
\frac{X \cdot \bar{B}}{B} & \text{if } X \leq B \\
100 - \frac{(100 - X)(100 - \bar{B})}{100 - B} & \text{if } X > B
\end{cases}
$$

where:

- $X$: The original score of a target phrase in the current request.

- $\bar{X}$: The normalized score of the target phrase.

- $B$: The score of the benchmark phrase in the current request.

- $\bar{B}$: The mean score of the benchmark phrase across all requests.

It's assumed that $B \neq 0$ and $B \neq 100$. If $B$ ever hits 0 or 100, that request gets tossed.

This piecewise approach ensures that scores of 0% and 100% remain unchanged, while scores near the benchmark are adjusted proportionally to the benchmark phrase's difference from its mean.

> Does `mean` score each phrase multiple times and average the results?

No.

Running the same phrase a couple of times and averaging the results could potentially help smooth out any random noise.

But `mean` skips that. Making multiple requests per phrase incurs more API calls.

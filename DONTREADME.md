# mean

## Goals

### Granularity

> Can a word have multiple scores?

Yes.

`mean` scores each meaning of a word separately.

A word can have meanings with different levels of prevalence.

### Prevalence

> Does `mean` measure corpus frequency?

No.

`mean` estimates prevalence for these reasons:

- Whether a joke or wordplay lands depends on the audience knowing the meaning, not on how often it appears in text.

- If you want to be confident in everyday English, you may want to learn meanings most people know rather than words that just show up a lot in written corpora.

### Coverage

> Does `mean` evaluate meanings from WordNet?

No.

WordNet's coverage is limited. Jokes often use slang and vulgarity.

So, `mean` evaluates meanings from a dictionary.

> Which dictionary does `mean` evaluate meanings from?

`mean` evaluates meanings from English Wiktionary.

Wiktionary was chosen for these reasons:

- The dataset is free.

- The coverage is extensive.

> Can `mean` evaluate meanings of non-lemma forms?

Yes. `mean` looks at both lemma and non‑lemma forms.

Non-lemma forms are evaluated for these reasons:

- Phonetic jokes might depend on specific inflections.

- Throwing in non-lemma forms doesn't blow up the dataset size by a factor of ten.

> Does `mean` evaluate empty glosses?

No.

`mean` drops senses with empty glosses for these reasons:

- Under 0.1% of English senses don't have glosses.

- Evaluating a sense without glosses can inflate its score because the model might mix up a rare sense with the phrase's usual meaning.

- Including examples or other fields to infer missing glosses may increase token usage and add extra prompt noise across requests.

> Does `mean` evaluate Wikipedia entries?

Yes. `mean` scores Wikipedia entries by treating their lead sentences as meanings.

### Cost

> What's the target cost for running `mean`?

The target cost for a batch API execution is capped at $1,000.

Productivity tools often cost up to $100 a month, which comes out to about $1,200 a year. Even if you calculate the average each year, a $1,000 cap makes the yearly cost still reasonable.

## Scoring

> Can the prevalence score be negative?

No, because it's a percentage.

Specifically, it's the percentage of Americans 10 years or older who know each meaning.

- "Americans" pins it to a clear population, avoiding wishy-washy concepts like "native speakers" that are open to interpretation. Because the U.S. has the biggest number of native English speakers worldwide, it makes sense to treat it as the default audience.

- "10 years or older" filters out babies, making it easier to sanity-check the model output, as super obvious definitions should hit near 100%.

> Is the prevalence score an integer?

Nah, it's a double. Doubles allow finer ordering.

> What model does `mean` use?

`mean` uses [`gemini-3.6-flash`](https://ai.google.dev/gemini-api/docs/models/gemini-3.6-flash) for these reasons:

- Among models that cost under $10 per million output tokens without batching, have a public API, and offer solid scoring, `gemini-3.6-flash` ranks highest on [Text Arena](https://arena.ai/leaderboard/text).

- `gemini-3.6-flash` is a production model.

- Less capable models tend to change their scores dramatically if the order of meanings to evaluate gets swapped. `gemini-3.6-flash` seems pretty resistant to this order dependency. Even though `mean` keeps the benchmark phrase in a fixed spot, the model's native resistance boosts confidence in the scores.

- `gemini-3.6-flash` allows running at a temperature of 0.

- Setting the thinking level to `minimal` effectively turns off thinking for this task.

- `gemini-3.6-flash` [supports structured outputs](https://ai.google.dev/gemini-api/docs/models/gemini-3.6-flash#:~:text=Supported-,Structured%20outputs,-Supported).

- `gemini-3.6-flash` [supports the Batch API](https://ai.google.dev/gemini-api/docs/models/gemini-3.6-flash#:~:text=Consumption%20options-,Batch%20API,-Supported).

> Does `mean` use a system prompt?

Yep.

If the list of meanings contains words that sound like commands, the model could treat them as instructions rather than just stuff to score. So the system prompt makes it crystal clear what's data and what's instruction.

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

> Does `mean` set `max_output_tokens`?

Yes.

`mean` sets `max_output_tokens` to 128. The longest English phrase in Wiktionary by character count is "when you're up to your neck in alligators, it's hard to remember that your initial objective was to drain the swamp". It takes 51 output tokens to evaluate this phrase. Setting the limit to 128 gives you enough headroom to avoid truncation and acts as a safety net against runaway billing.

> Is the phrase sent to the LLM alongside its meaning?

Yes.

A meaning alone might not be enough to uniquely identify what's being evaluated. Different phrases can end up sharing identical meaning text.

> Can a phrase contain multiple words?

Yes.

In English Wiktionary, a phrase matches the `word` entry, which also includes single words and multi-word expressions.

> Does `mean` evaluate `glosses` or `raw_glosses`?

`mean` evaluates `glosses`.

Over 70% of senses don't have `raw_glosses`.

In contrast, `glosses` cover over 99.9% of English senses.

I thought about falling back from `raw_glosses` to `glosses`. I decided not to go that route for these reasons:

- You may need to duplicate the fallback logic while matching scores back to the Wiktionary dump.

- `glosses` usually have enough info for the model to estimate prevalence.

- Shorter definitions help reduce token usage for each request.

> Are nested glosses concatenated?

No.

`mean` only looks at the leaf gloss for each sense. Here's why:

- The model might overinflate a rare meaning's score by using the parent gloss as the evaluation target.

- The phrase tends to give the model enough context to figure out the leaf gloss without needing parent glosses.

- Skipping parent glosses saves tokens.

> Is the part of speech sent to the LLM?

No.

Skipping parts of speech saves token usage and cuts down on prompt noise.

> How many items does each request in a batch evaluate?

Each request in a batch evaluates two items:

- The benchmark phrase and its meaning, which set the baseline across requests.

- The target phrase and its meaning, which the system pulls while looping through the vocab.

> Does `mean` use JSON in a prompt to format the phrases and meanings for evaluation?

No.

`mean` puts each item on its own line as an EDN map, which helps save token usage.

> What's the benchmark phrase?

The benchmark phrase is "touchstone". This word was chosen because it has the following characteristics:

- It is neither super common nor super obscure.

- It means "benchmark".

> Does `mean` use the literal or figurative meaning of "touchstone" as a benchmark?

`mean` uses the figurative meaning of "touchstone" as a benchmark.

The literal meaning is a rare technical term.

> Does `mean` use structured outputs?

Yes.

Using structured outputs makes sure the API response includes the scoring fields `mean` needs.

> Is the benchmark phrase or the target phrase scored first?

The benchmark phrase gets scored first.

Scoring the benchmark phrase first makes sure it's evaluated before the target phrase's score is generated. This way, the benchmark phrase's context stays more alike across requests compared to using the reverse order.

> Are the meanings included in the model's structured output?

No.

The structured output is an object that maps the benchmark phrase and the target phrase to their scores.

The meanings are omitted from the model's output. Here's why:

- It cuts down on output tokens.

- It helps the model focus on scoring the phrases.

The meanings are tracked outside the structured output, using the metadata key instead.

> What's the normalization formula?

It's piecewise:

$$
\bar{X} =
\begin{cases}
0 & \text{if } X = 0 \\
\frac{X \cdot \bar{B}}{B} & \text{if } X \leq B \\
100 - \frac{(100 - X)(100 - \bar{B})}{100 - B} & \text{if } X > B
\end{cases}
$$

where:

- $X$: The original score of a target phrase in the current request.

- $\bar{X}$: The normalized score of the target phrase.

- $B$: The score of the benchmark phrase in the current request.

- $\bar{B}$: The mean score of the benchmark phrase across all requests.

This piecewise approach ensures that scores of 0% and 100% remain unchanged, while scores near the benchmark are adjusted proportionally to the benchmark phrase's difference from its mean.

> Does `mean` score each phrase multiple times and average the results?

No.

Running the same phrase a couple of times and averaging the results could potentially help smooth out any random noise.

But `mean` skips that. Making multiple requests per phrase incurs more API calls.

## Batching

> Does `mean` automatically loop to submit multiple batches?

No.

`mean` submits at most one batch per command invocation.

If an error occurs, loops on large datasets can cause runaway billing.

> Does `mean` require Tier 2?

Yes.

Tier 1 limits enqueued tokens for `gemini-3.6-flash` to [3,000,000](https://ai.google.dev/gemini-api/docs/rate-limits#:~:text=Gemini%203.6%20Flash-,3%2C000%2C000,-Gemini%203.5%20Flash). So evaluating the full dataset on Tier 1 would theoretically require invoking `mean` dozens of times.

Tier 2 bumps the limits for `gemini-3.6-flash` up by roughly an order of magnitude, raising them to [400,000,000](https://ai.google.dev/gemini-api/docs/rate-limits#tier-2:~:text=Gemini%203.6%20Flash-,400%2C000%2C000,-Gemini%203.5%20Flash) enqueued tokens. In theory, this boost cuts down on the number of manual runs. If one run is enough, that'd be a batch made in heaven.

To unlock Tier 2 you need to [pay $100](https://ai.google.dev/gemini-api/docs/rate-limits#:~:text=Tier%202-,Paid%20%24100,-%2B%203%20days%20from) up front, but the full data set will probably cost more than $100 anyway.

> Does `mean` wait for the batch to finish?

Yes.

`mean` stays running in the terminal to monitor the active batch.

If the batch completes successfully, `mean` processes the results into the output files.

> What's the polling interval?

The polling interval is set to 10 seconds.

Polling every second might overload the API.

## Resuming

> Can `mean` keep going if it gets interrupted?

Yes.

If the `mean` process quits before writing the output files, running the command again will pick up where it left off.

> Does a crash during a write operation corrupt the accumulated results? (Planned)

No.

The tool swaps in a new JSON file atomically.

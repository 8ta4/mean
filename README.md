# mean

## It depends on what the meaning of the word "is" is.

> What's this tool about?

`mean` estimates how widely known meanings are.

> Where is the dataset hosted?

You can find the preprocessed data in the mean-data repo.

## Setup

> How do I set up `mean`?

1. Make sure you're using a Mac with Apple silicon.

1. Make sure your Google AI Studio project is on Tier 2.

1. Install [Homebrew](https://brew.sh/#install).

1. Install [devenv](https://github.com/cachix/devenv/blob/d0ea5226b162f4611e3541cc45547d210e83ae03/docs/src/getting-started.md#installation).

1. Open a terminal.

1. Copy an API key from [Google AI Studio](https://aistudio.google.com/api-keys).

1. Run these commands:
   ```bash
   mkdir -p ~/.config/mean
   pbpaste > ~/.config/mean/key
   git clone https://github.com/8ta4/mean
   cd mean
   devenv allow
   ```

## Usage

> How do I run `mean`?

1. Open a terminal.

1. Run the command.

   ```bash
   mean
   ```

Once the API batches finish, `mean` will drop these files into your current directory:

- `manifest.json` holds the benchmark phrase and gloss along with URLs and hashes for the split Wiktionary dump. The dump exceeds GitHub's file size limits.

- `mean.json` maps each phrase to an object whose keys are its concatenated raw glosses and whose values are scores.

- `raw.json` maps each phrase to an object whose keys are its concatenated raw glosses and whose values are raw score pairs for the benchmark and target phrases. If you adjust the formula, you can run the normalization again without incurring another batch API charge.

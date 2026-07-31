# mean

## It depends on what the meaning of "is" is.

> What's this tool about?

`mean` estimates how widely known meanings are.

> Where is the dataset hosted?

You can find the preprocessed data in the mean-data repo.

## Setup

> How do I set up `mean`?

1. Make sure you're using a Mac with Apple silicon.

1. Install [Homebrew](https://brew.sh/#install).

1. Install [devenv](https://github.com/cachix/devenv/blob/83e8d7d34bdebad98ab936b6af53d57ae67af420/docs/src/getting-started.md#installation).

1. Open a terminal.

1. Copy an API key from [Google AI Studio](https://aistudio.google.com/api-keys).

1. Run these commands:
   ```bash
   mkdir -p ~/.config/mean
   pbpaste > ~/.config/mean/key
   git clone https://github.com/8ta4/mean
   cd mean
   devenv allow
   devenv shell download
   ```

## Usage

> How do I run `mean`?

1. Open a terminal.

1. Run the command.

   ```bash
   mean
   ```

Once the API batches finish, `mean` will drop two files into your current directory:

- manifest.json: a file that contains the dump URL and SHA-256 hash

- mean.json: a file that contains normalized scores

- raw.json: a file that contains raw scores

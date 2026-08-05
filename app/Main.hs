module Main (main) where

import Relude

main :: IO ()
main = do
  content <- readFileLBS "raw-wiktextract-data.jsonl"
  pure ()

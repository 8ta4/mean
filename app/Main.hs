module Main (main) where

import Data.Aeson (Value, decode)
import Data.ByteString.Lazy.Char8 qualified as Char8
import Relude

main :: IO ()
main = do
  content <- readFileLBS "raw-wiktextract-data.jsonl"
  let _ :: [Value] = mapMaybe decode $ Char8.lines content
  pure ()

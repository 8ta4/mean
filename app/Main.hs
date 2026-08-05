module Main (main) where

import Control.Lens ((^?))
import Data.Aeson (Value, decode)
import Data.Aeson.Lens (key, values, _String)
import Data.ByteString.Lazy.Char8 qualified as Char8
import Relude

isEnglish :: Value -> Bool
isEnglish entry = case entry ^? key "lang" . _String of
  Just "English" -> True
  _ -> False

processEntry :: Value -> [Value]
processEntry entry = case entry ^? key "word" . _String of
  Just _ -> case entry ^? key "senses" . values . key "raw_glosses" . values . _String of
    Just _ -> []
    _ -> []
  _ -> []

main :: IO ()
main = do
  content <- readFileLBS "raw-wiktextract-data.jsonl"
  let _ :: [Value] = (filter isEnglish $ mapMaybe decode $ Char8.lines content) >>= processEntry
  pure ()

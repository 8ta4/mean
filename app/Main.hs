module Main (main) where

import Control.Lens ((^?))
import Data.Aeson (Value, decode)
import Data.Aeson.Lens (key, _String)
import Data.ByteString.Lazy.Char8 qualified as Char8
import Relude

isEnglish :: Value -> Bool
isEnglish entry = case entry ^? key "lang" . _String of
  Just "English" -> True
  _ -> False

main :: IO ()
main = do
  content <- readFileLBS "raw-wiktextract-data.jsonl"
  let _ :: [Value] = filter isEnglish $ mapMaybe decode $ Char8.lines content
  pure ()

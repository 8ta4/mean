module Main (main) where

import Control.Lens ((^..), (^?))
import Data.Aeson (Value, decode, object)
import Data.Aeson.Lens (key, values, _String)
import Data.ByteString.Lazy.Char8 qualified as Char8
import Data.Text qualified as Text
import Relude

isEnglish :: Value -> Bool
isEnglish entry = case entry ^? key "lang" . _String of
  Just "English" -> True
  _ -> False

makePayload :: Text -> Text -> Value
makePayload phrase gloss = object []

joinGlosses :: Value -> Text
joinGlosses = (Text.intercalate "\n") <$> (^.. key "raw_glosses" . values . _String)

processEntry :: Value -> [Value]
processEntry entry = case entry ^? key "word" . _String of
  Just phrase -> makePayload phrase <$> joinGlosses <$> (entry ^.. key "senses" . values . key "raw_glosses")
  _ -> []

main :: IO ()
main = do
  content <- readFileLBS "raw-wiktextract-data.jsonl"
  let _ :: [Value] = (filter isEnglish $ mapMaybe decode $ Char8.lines content) >>= processEntry
  pure ()

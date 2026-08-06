module Main where

import Control.Lens ((^..), (^?))
import Data.Aeson (KeyValue ((.=)), Value, decode, object)
import Data.Aeson.Lens (key, values, _String)
import Data.ByteString.Lazy.Char8 qualified as Char8
import Data.Text qualified as Text
import Network.HTTP.Req (Option, Scheme (Https), Url, header, https, (/:))
import Relude
import System.Directory (getHomeDirectory)
import System.FilePath ((</>))

main :: IO ()
main = do
  content <- readFileLBS "raw-wiktextract-data.jsonl"
  _ <- loadApiKeyHeader
  let _ :: [Value] = (filter isEnglish $ mapMaybe decode $ Char8.lines content) >>= processEntry
  pure ()

isEnglish :: Value -> Bool
isEnglish entry = case entry ^? key "lang" . _String of
  Just "English" -> True
  _ -> False

processEntry :: Value -> [Value]
processEntry entry = case entry ^? key "word" . _String of
  Just phrase -> makePayload phrase <$> joinGlosses <$> entry ^.. key "senses" . values . key "raw_glosses"
  _ -> []

makePayload :: Text -> Text -> Value
makePayload phrase gloss =
  object
    [ "contents"
        .= [ object
               []
           ]
    ]

joinGlosses :: Value -> Text
joinGlosses = Text.intercalate "\n" <$> (^.. key "raw_glosses" . values . _String)

loadApiKeyHeader :: IO (Option 'Https)
loadApiKeyHeader = do
  home <- getHomeDirectory
  apiKey <- readFileBS $ home </> ".config/mean/key"
  pure $ header "x-goog-api-key" apiKey

baseUrl :: Url 'Https
baseUrl = https "generativelanguage.googleapis.com" /: "v1beta"

model :: Text
model = "gemini-3.5-flash"

module Main where

import Control.Lens ((^..), (^?))
import Data.Aeson (KeyValue ((.=)), Value, decode, object)
import Data.Aeson.Key (fromText)
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
  let _ :: [Value] = (filter isTarget $ mapMaybe decode $ Char8.lines content) >>= processEntry
  pure ()

isTarget :: Value -> Bool
isTarget entry = isEnglish entry && isNotBenchmark entry

isEnglish :: Value -> Bool
isEnglish entry = case entry ^? key "lang" . _String of
  Just "English" -> True
  _ -> False

isNotBenchmark :: Value -> Bool
isNotBenchmark entry = case entry ^? key "word" . _String of
  Just phrase -> benchmarkPhrase /= phrase
  _ -> False

processEntry :: Value -> [Value]
processEntry entry = case entry ^? key "word" . _String of
  Just phrase ->
    ( \gloss ->
        object
          [ "key" .= gloss,
            "request" .= makePayload phrase gloss
          ]
    )
      <$> joinGlosses
      <$> entry
      ^.. key "senses" . values . key "raw_glosses"
  _ -> []

makePayload :: Text -> Text -> Value
makePayload phrase gloss =
  object
    [ "contents"
        .= [ object
               [ "parts"
                   .= [ object
                          ["text" .= (renderEdn benchmarkPhrase benchmarkGloss <> "\n" <> renderEdn phrase gloss)]
                      ]
               ]
           ],
      "generation_config"
        .= object
          [ "max_output_tokens" .= (2 :: Int) ^ (7 :: Int),
            "response_mime_type" .= ("application/json" :: Text),
            -- Using camelCase (`responseJsonSchema`) causes the Gemini Batch API to generate incorrect properties in the output.
            -- To ensure the schema is applied correctly, we use snake_case (`response_json_schema`).
            "response_json_schema"
              .= object
                [ "additional_properties" .= False,
                  "properties"
                    .= object
                      [ fromText benchmarkPhrase
                          .= percentageSchema,
                        fromText phrase
                          .= percentageSchema
                      ],
                  "property_ordering" .= [fromText benchmarkPhrase, fromText phrase],
                  "required" .= [fromText benchmarkPhrase, fromText phrase],
                  "type" .= ("object" :: Text)
                ],
            "seed" .= (0 :: Int),
            "temperature" .= (0 :: Int),
            "thinking_config"
              .= object
                ["thinking_level" .= ("MINIMAL" :: Text)]
          ],
      "system_instruction"
        .= object
          [ "parts"
              .= [ object
                     ["text" .= systemPrompt]
                 ]
          ]
    ]

percentageSchema :: Value
percentageSchema =
  object
    [ "maximum" .= (100 :: Int),
      "minimum" .= (0 :: Int),
      "type" .= ("number" :: Text)
    ]

renderEdn :: Text -> Text -> Text
renderEdn phrase gloss = "{:phrase " <> show phrase <> " :sense " <> show gloss <> "}"

benchmarkPhrase :: Text
benchmarkPhrase = "touchstone"

benchmarkGloss :: Text
benchmarkGloss = "(figurative, by extension) A standard of comparison or evaluation."

systemPrompt :: Text
systemPrompt = "Estimate the percentage of Americans 10 years or older who know each meaning."

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

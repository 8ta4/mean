module Main where

import Control.Concurrent (threadDelay)
import Control.Lens (to, (^..), (^?))
import Control.Lens.Prism (_Just)
import Data.Aeson (KeyValue ((.=)), ToJSON, Value, decode, decodeStrictText, encode, object)
import Data.Aeson.Key (fromText)
import Data.Aeson.Lens (key, nth, values, _String)
import Data.ByteString.Lazy (LazyByteString)
import Data.ByteString.Lazy.Char8 qualified as Char8
import Data.List ((!!))
import Data.Map.Lazy (insertWith, lookup, singleton, union)
import Data.Map.Lazy qualified as Map
import Data.Text (splitOn)
import Data.Text qualified as Text
import Network.HTTP.Req (GET (GET), JsonResponse, NoReqBody (NoReqBody), Option, POST (POST), Req, ReqBodyFile (ReqBodyFile), ReqBodyJson (ReqBodyJson), Scheme (Https), Url, defaultHttpConfig, header, https, ignoreResponse, jsonResponse, lbsResponse, req, responseBody, responseHeader, runReq, useHttpsURI, (/:), (=:))
import Relude
import System.Directory (createDirectoryIfMissing, doesFileExist, getFileSize, getHomeDirectory, getTemporaryDirectory)
import System.FilePath ((</>))
import Text.URI (mkURI)

main :: IO ()
main = do
  home <- getHomeDirectory
  let statePath = home </> ".local/state/mean"
  let batchIdPath = statePath </> "id"
  createDirectoryIfMissing True statePath
  batchExists <- doesFileExist batchIdPath
  apiKeyHeader <- loadApiKeyHeader
  if batchExists
    then do
      batchId <- readFileBS batchIdPath
      maybeResponsesFile <- poll $ req GET (baseUrl /: "batches" /: decodeUtf8 batchId) NoReqBody jsonResponse apiKeyHeader
      case maybeResponsesFile of
        Just responsesFile -> do
          downloadResponse <-
            runReq defaultHttpConfig
              $ req
                GET
                (host /: "download" /: "v1beta" /: "files" /: (responsesFile <> ":download"))
                NoReqBody
                lbsResponse
                (apiKeyHeader <> "alt" =: ("media" :: Text))
          writeFileLBS "raw.json" $ encode $ foldl' insertScore Map.empty $ mapMaybe parseResult $ Char8.lines $ responseBody downloadResponse
        _ -> pure ()
    else do
      content <- readFileLBS "raw-wiktextract-data.jsonl"
      temporaryDirectory <- getTemporaryDirectory
      let inputPath = temporaryDirectory </> "input.jsonl"
      writeFileLBS inputPath $ Char8.unlines $ (filter isTarget $ mapMaybe decode $ Char8.lines content) >>= processEntry
      fileSize <- getFileSize inputPath
      let initialHeaders =
            apiKeyHeader
              <> header "X-Goog-Upload-Protocol" "resumable"
              <> header "X-Goog-Upload-Command" "start"
              <> header "X-Goog-Upload-Header-Content-Length" (show fileSize)
              <> header "X-Goog-Upload-Header-Content-Type" "application/json"
      initialResponse <-
        runReq defaultHttpConfig
          $ req
            POST
            (host /: "upload" /: "v1beta" /: "files")
            (ReqBodyJson $ object [])
            ignoreResponse
            initialHeaders
      case responseHeader initialResponse "x-goog-upload-url" of
        Just uploadUrlHeader -> do
          uploadUri <- mkURI $ decodeUtf8 uploadUrlHeader
          case useHttpsURI uploadUri of
            Just (uploadUrl, uploadOptions) -> do
              uploadResponse <-
                runReq defaultHttpConfig
                  $ req
                    POST
                    uploadUrl
                    (ReqBodyFile inputPath)
                    jsonResponse
                    ( apiKeyHeader
                        <> header "X-Goog-Upload-Offset" "0"
                        <> header "X-Goog-Upload-Command" "upload, finalize"
                        <> uploadOptions
                    )
              case (responseBody uploadResponse :: Value) ^? key "file" . key "name" . _String of
                Just filename -> do
                  batchResponse <-
                    runReq defaultHttpConfig
                      $ req
                        POST
                        batchUrl
                        (ReqBodyJson $ makeBatchPayload filename)
                        jsonResponse
                        apiKeyHeader
                  case (responseBody batchResponse :: Value) ^? key "name" . _String of
                    Just batchName -> writeFileText batchIdPath $ (splitOn "/" batchName) !! 1
                    _ -> pure ()
                _ -> pure ()
              pure ()
            _ -> pure ()
        _ -> pure ()

insertScore :: Map Text (Map Text (Double, Double)) -> (Text, Text, Double, Double) -> Map Text (Map Text (Double, Double))
insertScore xs (phrase, gloss, benchmarkScore, targetScore) = insertWith union phrase (singleton gloss (benchmarkScore, targetScore)) xs

poll :: Req (JsonResponse Value) -> IO (Maybe Text)
poll request = do
  response <- runReq defaultHttpConfig request
  case (responseBody response) ^? key "metadata" . key "state" . _String of
    Just "BATCH_STATE_SUCCEEDED" ->
      pure
        $ (!! 1)
        <$> (splitOn "/")
        <$> (responseBody response)
        ^? key
          "response"
          . key "responsesFile"
          . _String
    Just "BATCH_STATE_RUNNING" -> liftIO $ do
      threadDelay 10000000
      poll request
    _ -> pure Nothing

parseResult :: LazyByteString -> Maybe (Text, Text, Double, Double)
parseResult line = do
  scores <-
    line
      ^? key "response"
        . key "candidates"
        . nth 0
        . key "content"
        . key "parts"
        . nth 0
        . key "text"
        . _String
        . to decodeStrictText
        . _Just
  keyPair <- line ^? key "key" . _String . to decodeStrictText . _Just
  targetScore <- lookup (keyPair !! 0) scores
  benchmarkScore <- lookup benchmarkPhrase scores
  pure $ ((keyPair !! 0), (keyPair !! 1), benchmarkScore, targetScore)

makeBatchPayload :: Text -> Value
makeBatchPayload filename =
  object
    [ "batch"
        .= object
          [ "input_config"
              .= object
                ["file_name" .= filename]
          ]
    ]

batchUrl :: Url 'Https
batchUrl = baseUrl /: "models" /: model <> ":batchGenerateContent"

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

renderJson :: (ToJSON a) => a -> Text
renderJson = decodeUtf8 <$> encode

processEntry :: Value -> [Char8.ByteString]
processEntry entry = case entry ^? key "word" . _String of
  Just phrase ->
    encode
      <$> ( \gloss ->
              object
                [ "key" .= renderJson [phrase, gloss],
                  "request" .= makeRequestPayload phrase gloss
                ]
          )
      <$> joinGlosses
      <$> entry
      ^.. key "senses" . values . key "raw_glosses"
  _ -> []

makeRequestPayload :: Text -> Text -> Value
makeRequestPayload phrase gloss =
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
joinGlosses = Text.intercalate "\n" <$> (^.. values . _String)

loadApiKeyHeader :: IO (Option 'Https)
loadApiKeyHeader = do
  home <- getHomeDirectory
  apiKey <- readFileBS $ home </> ".config/mean/key"
  pure $ header "x-goog-api-key" apiKey

baseUrl :: Url 'Https
baseUrl = host /: "v1beta"

host :: Url 'Https
host = https "generativelanguage.googleapis.com"

model :: Text
model = "gemini-3.5-flash"

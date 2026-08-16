module Main where

import Codec.Compression.GZip (decompress)
import Control.Concurrent (threadDelay)
import Control.Foldl (mean)
import Control.Foldl qualified as Foldl
import Control.Lens (to, (^..), (^?))
import Control.Lens.Cons (_last)
import Control.Lens.Prism (_Just)
import Crypto.Hash.SHA256 (hashlazy)
import Data.Aeson (KeyValue ((.=)), ToJSON, Value, decode, decodeFileStrict, decodeStrictText, encode, object)
import Data.Aeson.Key (fromText)
import Data.Aeson.Lens (key, nth, values, _Array, _String)
import Data.ByteString.Base16 qualified as Base16
import Data.ByteString.Lazy (LazyByteString)
import Data.ByteString.Lazy.Char8 qualified as Char8
import Data.List ((!!))
import Data.Map.Lazy (elems, insert, insertWith, lookup, singleton, union)
import Data.Map.Lazy qualified as Map
import Data.Text (splitOn)
import Network.HTTP.Req (GET (GET), HttpConfig (httpConfigRetryPolicy), JsonResponse, NoReqBody (NoReqBody), Option, POST (POST), Req, ReqBodyFile (ReqBodyFile), ReqBodyJson (ReqBodyJson), Scheme (Https), Url, defaultHttpConfig, header, https, ignoreResponse, jsonResponse, lbsResponse, req, responseBody, responseHeader, responseTimeout, runReq, useHttpsURI, (/:), (=:))
import Relude
import System.Directory (createDirectoryIfMissing, doesFileExist, getFileSize, getHomeDirectory, getTemporaryDirectory)
import System.FilePath (takeFileName, (</>))
import System.Process
import Text.URI (mkURI)

type RawScores = Map Text (Map Text (Double, Double))

data Entry = Entry
  { phrase :: !Text,
    gloss :: !Text,
    benchmarkScore :: !Double,
    targetScore :: !Double
  }

data Part = Part
  { url :: !Text,
    hash :: !Text
  }
  deriving (Generic, ToJSON)

main :: IO ()
main = do
  home <- getHomeDirectory
  let statePath = home </> ".local/state/mean"
      batchIdPath = statePath </> "id"
      partsPath = statePath </> "parts"
      extractedPath = statePath </> "raw-wiktextract-data.jsonl"
  createDirectoryIfMissing True statePath
  createDirectoryIfMissing True partsPath
  batchExists <- doesFileExist batchIdPath
  rawExists <- doesFileExist rawPath
  apiKeyHeader <- loadApiKeyHeader
  let ensureExtracted = do
        partBytes <- traverse downloadPart parts
        writeFileLBS extractedPath $ decompress $ fold partBytes
      downloadPart part = do
        let partPath = partsPath </> takeFileName (toString $ part.url)
        callProcess "wget" ["-c", "-O", partPath, toString $ part.url]
        content <- readFileLBS partPath
        if (part.hash == (decodeUtf8 $ Base16.encode $ hashlazy content))
          then pure content
          else error "Checksum verification failed"
      ensureSubmitted = unless (rawExists || batchExists) $ do
        content <- readFileLBS extractedPath
        temporaryDirectory <- getTemporaryDirectory
        let inputPath = temporaryDirectory </> "input.jsonl"
        writeFileLBS inputPath $ Char8.unlines $ makeBatchLine <$> ordNub ((filter isTarget $ mapMaybe decode $ Char8.lines content) >>= processEntry)
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
                      -- Disabling retries prevents submitting multiple batches and getting charged multiple times.
                      runReq (defaultHttpConfig {httpConfigRetryPolicy = mempty})
                        $ req
                          POST
                          batchUrl
                          (ReqBodyJson $ makeBatchPayload filename)
                          jsonResponse
                          -- The API may take 30+ seconds to respond when submitting a batch request.
                          (apiKeyHeader <> responseTimeout timeout)
                    case (responseBody batchResponse :: Value) ^? key "name" . _String of
                      Just batchName -> writeFileText batchIdPath $ (splitOn "/" batchName) !! 1
                      _ -> pure ()
                  _ -> pure ()
              _ -> pure ()
          _ -> pure ()
      ensureDownloaded = unless rawExists $ do
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
            writeFileLBS rawPath $ encode $ foldl' insertScore Map.empty $ mapMaybe parseResult $ Char8.lines $ responseBody downloadResponse
          _ -> pure ()
      ensureNormalized = do
        maybeRawScores <- decodeFileStrict rawPath
        case maybeRawScores of
          Just (rawScores :: RawScores) -> do
            let meanBenchmarkScore = Foldl.fold mean $ elems rawScores >>= ((fst <$>) <$> elems)
            writeFileLBS "mean.json"
              $ encode
              $ insert
                benchmarkPhrase
                (singleton benchmarkGloss meanBenchmarkScore)
              $ ( ( \(benchmarkScore, targetScore) ->
                      if targetScore == 0
                        then 0
                        else
                          if targetScore <= benchmarkScore
                            then
                              targetScore * meanBenchmarkScore / benchmarkScore
                            else
                              100 - (100 - targetScore) * (100 - meanBenchmarkScore) / (100 - benchmarkScore)
                  )
                    <$>
                )
              <$> rawScores
          _ -> pure ()
  ensureManifest
  ensureExtracted
  ensureSubmitted
  ensureDownloaded
  ensureNormalized

parts :: [Part]
parts =
  [ Part
      { url = "https://github.com/8ta4/mean-data/releases/download/v0.1.1/raw-wiktextract-data.jsonl.gz.aa",
        hash = "4b6a14bb1edbdb3e04a07ec903352f436e0830f25ddf735e7692e0d03245aec8"
      },
    Part
      { url = "https://github.com/8ta4/mean-data/releases/download/v0.1.1/raw-wiktextract-data.jsonl.gz.ab",
        hash = "7c938ea16487de469d79c6ef994dacf0af9f60543d6bc3d7af35ed423f2c3d6c"
      }
  ]

rawPath :: FilePath
rawPath = "raw.json"

loadApiKeyHeader :: IO (Option 'Https)
loadApiKeyHeader = do
  home <- getHomeDirectory
  apiKey <- readFileBS $ home </> ".config/mean/key"
  pure $ header "x-goog-api-key" apiKey

benchmarkPhrase :: Text
benchmarkPhrase = "touchstone"

benchmarkGloss :: Text
benchmarkGloss = "A standard of comparison or evaluation."

poll :: Req (JsonResponse Value) -> IO (Maybe Text)
poll request = do
  response <- runReq defaultHttpConfig request
  case (responseBody response) ^? key "metadata" . key "state" . _String of
    Just "BATCH_STATE_SUCCEEDED" ->
      pure
        $ (!! 1)
        <$> (splitOn "/")
        <$> (responseBody response)
        ^? key "response"
          . key "responsesFile"
          . _String
    Just "BATCH_STATE_RUNNING" -> liftIO $ do
      threadDelay 10000000
      poll request
    _ -> pure Nothing

host :: Url 'Https
host = https "generativelanguage.googleapis.com"

insertScore :: RawScores -> Entry -> RawScores
insertScore xs Entry {phrase, gloss, benchmarkScore, targetScore} = insertWith union phrase (singleton gloss (benchmarkScore, targetScore)) xs

parseResult :: LazyByteString -> Maybe Entry
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
  pure
    $ Entry
      { phrase = keyPair !! 0,
        gloss = keyPair !! 1,
        benchmarkScore,
        targetScore
      }

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

makeBatchLine :: (Text, Text) -> Char8.ByteString
makeBatchLine (phrase, gloss) =
  encode
    $ object
      [ "key" .= renderJson [phrase, gloss],
        "request" .= makeRequestPayload phrase gloss
      ]

processEntry :: Value -> [(Text, Text)]
processEntry entry = case entry ^? key "word" . _String of
  Just phrase ->
    (phrase,)
      <$> entry
      ^.. key "senses"
        . values
        . key "glosses"
        . _Array
        . _last
        . _String
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

-- Haskell's `show` escapes non-ASCII Unicode characters using decimal escape sequences.
-- `renderJson` uses JSON string escaping.
renderEdn :: Text -> Text -> Text
renderEdn phrase gloss = "{:phrase " <> renderJson phrase <> " :meaning " <> renderJson gloss <> "}"

percentageSchema :: Value
percentageSchema =
  object
    [ "maximum" .= (100 :: Int),
      "minimum" .= (0 :: Int),
      "type" .= ("number" :: Text)
    ]

batchUrl :: Url 'Https
batchUrl = baseUrl /: "models" /: model <> ":batchGenerateContent"

baseUrl :: Url 'Https
baseUrl = host /: "v1beta"

model :: Text
model = "gemini-3.6-flash"

timeout :: Int
timeout = 24 * 60 * 60 * 10 ^ (6 :: Int)

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

systemPrompt :: Text
systemPrompt = "Estimate the percentage of Americans 10 years or older who know each meaning."

ensureManifest :: IO ()
ensureManifest =
  writeFileLBS "manifest.json"
    $ encode
    $ object
      [ "benchmark"
          .= object
            [ "phrase" .= benchmarkPhrase,
              "gloss" .= benchmarkGloss
            ],
        "parts" .= parts
      ]

module Spec where

import Data.Aeson (Value)
import Main (baseUrl, loadApiKeyHeader, makeRequestPayload, model)
import Network.HTTP.Req (POST (POST), ReqBodyJson (ReqBodyJson), defaultHttpConfig, jsonResponse, req, responseBody, runReq, (/:))
import Relude

main :: IO ()
main = do
  apiKeyHeader <- loadApiKeyHeader
  let payload = makeRequestPayload "mean" "To intend, to plan (to do); to have as one's intention."
  putTextLn "Payload:"
  print payload
  putTextLn "Response:"
  response <- runReq defaultHttpConfig $ req POST (baseUrl /: "models" /: model <> ":generateContent") (ReqBodyJson payload) jsonResponse apiKeyHeader
  print (responseBody response :: Value)

module Spec where

import Data.Aeson (Value)
import Main (baseUrl, loadApiKeyHeader, makePayload, model)
import Network.HTTP.Req (POST (POST), ReqBodyJson (ReqBodyJson), defaultHttpConfig, jsonResponse, req, responseBody, runReq, (/:))
import Relude

main :: IO ()
main = do
  apiKeyHeader <- loadApiKeyHeader
  let payload = makePayload "mean" "To intend.\n(transitive) To intend, to plan (to do); to have as one's intention."
  putTextLn "Payload:"
  print payload
  runReq defaultHttpConfig $ do
    putTextLn "Response:"
    response <- req POST (baseUrl /: "models" /: model <> ":generateContent") (ReqBodyJson payload) jsonResponse apiKeyHeader
    print (responseBody response :: Value)

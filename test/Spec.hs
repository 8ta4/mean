module Spec where

import Main (loadApiKeyHeader, makePayload)
import Relude

main :: IO ()
main = do
  _ <- loadApiKeyHeader
  let payload = makePayload "mean" "To intend.\nTo intend, to plan (to do); to have as one's intention."
  putTextLn "Payload:"
  print payload

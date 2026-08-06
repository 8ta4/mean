module Spec where

import Main (loadApiKeyHeader)
import Relude

main :: IO ()
main = do
  _ <- loadApiKeyHeader
  pure ()

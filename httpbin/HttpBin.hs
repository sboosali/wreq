{-# LANGUAGE OverloadedStrings #-}
{-# OPTIONS_GHC -fno-warn-missing-signatures #-}

module Main (main) where

import Control.Applicative ((<$>))
import Data.Aeson (Value(..), eitherDecode, encode, object, toJSON)
import Data.ByteString.Char8 (pack)
import Data.CaseInsensitive (original)
import Data.Maybe (fromMaybe)
import Data.Monoid ((<>))
import Data.Text.Encoding (decodeUtf8)
import Data.Text.Read (decimal)
import Snap.Core
import Snap.Http.Server
import qualified Data.Map as Map
import qualified Data.Text.Lazy.Encoding as Lazy

get = respond return

post = respond $ \obj -> do
  body <- readRequestBody 65536
  return $ obj <> [("data", toJSON (Lazy.decodeUtf8 body))] <>
           case eitherDecode body of
             Left _    -> [("json", Null)]
             Right val -> [("json", val)]

put = post

delete = respond return

status = do
  val <- rqParam "val" <$> getRequest
  let code = case decimal . decodeUtf8 . head . fromMaybe ["200"] $ val of
               Right (n, "")
                 | n >= 200 && n <= 505 -> n
               _                        -> 400
  modifyResponse $ setResponseCode code

respond act = do
  req <- getRequest
  let step m k v = Map.insert (decodeUtf8 k) (decodeUtf8 (head v)) m
      params = Map.foldlWithKey' step Map.empty .
               rqQueryParams $ req
      wibble (k,v) = (decodeUtf8 (original k), decodeUtf8 v)
      rqHeaders = headers req
      hdrs = Map.fromList . map wibble . listHeaders $ rqHeaders
      url = case getHeader "Host" rqHeaders of
              Nothing   -> []
              Just host -> [("url", toJSON . decodeUtf8 $
                                    "http://" <> host <> rqURI req)]
  let obj = [ ("args", toJSON params)
            , ("headers", toJSON hdrs)
            , ("origin", toJSON . decodeUtf8 . rqRemoteAddr $ req)
            ] <> url
  modifyResponse $ setContentType "application/json"
  (writeLBS . encode . object) =<< act obj

main = do
  cfg <- commandLineConfig
       . setAccessLog ConfigNoLog
       . setErrorLog ConfigNoLog
       $ defaultConfig
  httpServe cfg $ route [
      ("/get", methods [GET,HEAD] get)
    , ("/post", method POST post)
    , ("/put", method PUT put)
    , ("/delete", method DELETE delete)
    , ("/status/:val", status)
    ]

{-# LANGUAGE DataKinds #-}
{-# LANGUAGE FlexibleContexts #-}
{-# LANGUAGE GeneralizedNewtypeDeriving #-}
{-# LANGUAGE OverloadedStrings #-}

module Rollbar.Client where

import Control.Monad.Reader
import Data.Aeson
import Data.ByteString
import Data.Proxy
import Data.Text
import Network.HTTP.Req
import Rollbar.Client.Item
import Rollbar.Client.Settings (Settings(..))

data Pong = Pong
  deriving (Eq, Show)

newtype Rollbar a = Rollbar (ReaderT Settings Req a)
  deriving
    ( Applicative
    , Functor
    , Monad
    , MonadIO
    , MonadReader Settings
    )

instance MonadHttp Rollbar where
  handleHttpException = Rollbar . lift . handleHttpException

data Response a = Response
  { responseErr :: Integer
  , responseResult :: a
  } deriving (Eq, Show)

instance FromJSON a => FromJSON (Response a) where
  parseJSON = withObject "Response a" $ \o ->
    Response <$> o .: "err"
             <*> o .: "result"

runRollbar :: HttpConfig -> Settings -> Rollbar a -> IO a
runRollbar config settings (Rollbar f) = runReq config $ runReaderT f settings

ping :: MonadHttp m => m Pong
ping = do
  req GET url NoReqBody ignoreResponse mempty
  return Pong
  where
    url = baseUrl /: "status" /: "ping"

createItem
  :: (MonadHttp m, MonadReader Settings m)
  => Item
  -> m (Response ItemId)
createItem item =
  responseBody <$> rollbar POST url (ReqBodyJson item) jsonResponse mempty
  where
    url = baseUrl /: "item" /: ""

rollbar
  :: ( HttpBody body
     , HttpBodyAllowed (AllowsBody method) (ProvidesBody body)
     , HttpMethod method
     , HttpResponse response
     , MonadHttp m
     , MonadReader Settings m
     )
  => method
  -> Url Https
  -> body
  -> Proxy response
  -> Option Https
  -> m response
rollbar method url body response options = do
  token <- asks settingsToken
  req method url body response $ options <> header "X-Rollbar-Access-Token" token

baseUrl :: Url Https
baseUrl = https "api.rollbar.com" /: "api" /: "1"

{-# LANGUAGE OverloadedStrings #-}

module Rollbar.Wai
  ( rollbarOnException
  , rollbarOnExceptionWith
  ) where

import qualified Data.CaseInsensitive as CI
import qualified Data.HashMap.Strict as HM
import qualified Data.Text.Encoding as T
import qualified Network.Wai as W
import qualified Network.Wai.Parse as W
import qualified Network.Wai.Request as W

import Control.Concurrent (forkIO)
import Control.Exception
import Control.Monad (void)
import Control.Monad.IO.Class (MonadIO(..))
import Data.Aeson
import Network.HTTP.Types (renderQuery)
import Rollbar.Client

rollbarOnException
  :: MonadIO m
  => Settings
  -> Maybe W.Request
  -> SomeException
  -> m ()
rollbarOnException settings = rollbarOnExceptionWith runner (void . createItem)
  where
    runner = void . liftIO . forkIO . runRollbar settings

rollbarOnExceptionWith
  :: (HasSettings m, MonadIO m, MonadIO n)
  => (m () -> n ())
  -> (Item -> m ())
  -> Maybe W.Request
  -> SomeException
  -> n ()
rollbarOnExceptionWith runner f mreq ex = runner $ do
  idata <- mkData $ PayloadTrace $ Trace [] $ mkException ex
  mdreq <- mapM mkRequest mreq
  f $ Item idata { dataRequest = mdreq }

mkRequest :: MonadIO m => W.Request -> m Request
mkRequest req = liftIO $ do
  (params, _) <- W.parseRequestBody ignoreFilesBackEnd req
  return Request
    { requestUrl = T.decodeUtf8 $ mconcat
        [W.guessApproot req, W.rawPathInfo req, W.rawQueryString req]
    , requestMethod = T.decodeUtf8 $ W.requestMethod req
    , requestHeaders = HM.fromList $ fmap toHeader $ W.requestHeaders req
    , requestParams = mempty
    , requestGet = HM.fromList $ fmap toQuery $ W.queryString req
    , requestQueryStrings = T.decodeUtf8 $ renderQuery False $ W.queryString req
    , requestPost = HM.fromList $ fmap toParam params
    , requestBody = ""
    , requestUserIp = ""
    }
  where
    toHeader (key, value) =
      (T.decodeUtf8 $ CI.original key, toJSON $ T.decodeUtf8 value)
    toQuery (key, value) =
      (T.decodeUtf8 key, toJSON $ T.decodeUtf8 <$> value)
    toParam (key, value) =
      (T.decodeUtf8 key, toJSON $ T.decodeUtf8 value)

ignoreFilesBackEnd :: W.BackEnd ()
ignoreFilesBackEnd _ _ _ = pure ()

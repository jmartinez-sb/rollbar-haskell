{-# LANGUAGE FlexibleInstances #-}
{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE RecordWildCards #-}
{-# LANGUAGE TypeSynonymInstances #-}

module Rollbar.ClientSpec
  ( spec
  ) where

import qualified Data.HashMap.Strict as HM

import Control.Monad.Reader
import Data.Aeson
import Data.Text
import Data.Yaml.Config
import Rollbar.Client
import Test.Hspec

data Package = Package
  { packageName :: Text
  , packageVersion :: Text
  } deriving (Eq, Show)

instance FromJSON Package where
  parseJSON = withObject "Package" $ \o ->
    Package <$> o .: "name"
            <*> o .: "version"

instance HasSettings (Reader Settings) where
  getSettings = ask

spec :: Spec
spec = do
  describe "getRequestModifier" $ do
    let mkSettings modifier = Settings
          { settingsToken = Token "invalid-token"
          , settingsEnvironment = Environment "test"
          , settingsRevision = Nothing
          , settingsRequestModifiers = [modifier]
          }
        request = Request
          { requestUrl = "http://example.com"
          , requestMethod = "GET"
          , requestHeaders = HM.fromList
              [ ("Host", "example.com")
              , ("Secret", "p4ssw0rd")
              ]
          , requestParams = HM.fromList
              [ ("user", "John Doe")
              , ("password", "p4ssw0rd")
              ]
          , requestGet = mempty
          , requestQueryStrings = ""
          , requestPost = mempty
          , requestBody = ""
          , requestUserIp = ""
          }

    context "ExcludeHeaders" $
      it "excludes the headers not matching the given names" $
        let requestModifier = runReader getRequestModifier $ mkSettings $
              ExcludeHeaders ["Secret"]
        in requestModifier request `shouldBe` request
             { requestHeaders = HM.fromList [("Host", "example.com")] }

    context "ExcludeParams" $
      it "excludes the params not matching the given names" $
        let requestModifier = runReader getRequestModifier $ mkSettings $
              ExcludeParams ["password"]
        in requestModifier request `shouldBe` request
             { requestParams = HM.fromList [("user", "John Doe")] }

    context "IncludeHeaders" $
      it "includes only the headers matching the given names" $
        let requestModifier = runReader getRequestModifier $ mkSettings $
              IncludeHeaders ["Host"]
        in requestModifier request `shouldBe` request
             { requestHeaders = HM.fromList [("Host", "example.com")] }

    context "IncludeParams" $
      it "includes only the headers matching the given names" $
        let requestModifier = runReader getRequestModifier $ mkSettings $
              IncludeParams ["user"]
        in requestModifier request `shouldBe` request
             { requestParams = HM.fromList [("user", "John Doe")] }

  describe "defaultNotifier" $
    it "matches the package name and version" $ do
      Package{..} <- loadYamlSettings ["package.yaml"] [] ignoreEnv
      defaultNotifier `shouldBe` Notifier
        { notifierName = packageName
        , notifierVersion = packageVersion
        }

  before (readSettings "rollbar.yaml") $ do
    describe "ping" $
      it "returns Pong" $ \settings ->
        runRollbar settings ping `shouldReturn` Pong

    describe "createItem" $ do
      context "PayloadTrace" $
        it "returns ItemId" $ \settings -> do
          itemId <- runRollbar settings $ do
            item <- mkItem $ PayloadTrace $ Trace [] $ Exception
              { exceptionClass = "NameError"
              , exceptionMessage = Just "global name 'foo' is not defined"
              , exceptionDescription = Just "Something went wrong while trying to save the user object"
              }
            createItem item

          itemId `shouldSatisfy` const True

      context "PayloadTraceChain" $
        it "returns ItemId" $ \settings -> do
          itemId <- runRollbar settings $ do
            item <- mkItem $ PayloadTraceChain $ pure $ Trace [] $ Exception
              { exceptionClass = "NameError"
              , exceptionMessage = Just "global name 'foo' is not defined"
              , exceptionDescription = Just "Something went wrong while trying to save the user object"
              }
            createItem item

          itemId `shouldSatisfy` const True

      context "PayloadMessage" $
        it "returns ItemId" $ \settings -> do
          itemId <- runRollbar settings $ do
            item <- mkItem $ PayloadMessage $ Message
              { messageBody = "Request over threshold of 10 seconds"
              , messageMetadata = HM.fromList
                  [ ("route", "home#index")
                  , ("time_elapsed", Number 15.23)
                  ]
              }
            createItem item

          itemId `shouldSatisfy` const True

    describe "reportDeploy" $
      it "returns DeployId" $ \settings -> do
        deployId <- runRollbar settings $ do
          deploy <- getRevision >>= mkDeploy
          reportDeploy deploy

        deployId `shouldSatisfy` (> 0)

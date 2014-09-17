{-# LANGUAGE OverloadedStrings #-}
module NLP.POS.LiteralTaggerTests where

import Test.HUnit      ( (@?=), (@=?) )
import Test.Framework ( testGroup, Test )
import Test.Framework.Providers.HUnit (testCase)
import Test.QuickCheck ()
import Test.Framework.Providers.QuickCheck2 (testProperty)

import Control.Monad ((>=>))
import Data.Map (Map)
import qualified Data.Map as Map
import Data.Text (Text)
import qualified Data.Text as T

import NLP.Types
import NLP.POS
import qualified NLP.POS.LiteralTagger as LT
import NLP.Tokenize.Text (defaultTokenizer, run)

tests :: Test
tests = testGroup "NLP.POS.LiteralTagger"
        [ testProperty ("Empty tagger always tags as "++ show tagUNK) prop_emptyAlwaysUnk
        , testGroup "Initial training" $ map (trainAndTagTest Nothing)
          [ ( "Simple training test"
            , Map.fromList [ ("the", Tag "dt")
                          , ("dog", Tag "nn")
                          , ("jumped", Tag "vb") ]
            , Sensitive
            , "a dog", "a/Unk dog/nn")
          , ( "Duplicate entries -- use the last value."
            , Map.fromList [ ("the", Tag "dt")
                           , ("dog", Tag "nn")
                           , ("jumped", Tag "vb")
                           , ("jumped", Tag "vbx") ]
            , Sensitive
            , "a dog jumped", "a/Unk dog/nn jumped/vbx")
          , ( "Case insensitivity"
            , Map.fromList [ ("the", Tag "dt")
                           , ("dog", Tag "nn")
                           , ("Jumped", Tag "vb")
                           ]
            , Insensitive
            , "a dog jumped", "a/Unk dog/nn jumped/vb")
          ]
        , testGroup "Multi-token inputs" $ map (trainAndTagTest Nothing)
          [ ( "Multi-tokens 1: basic use"
            , Map.fromList [ ("the", Tag "dt")
                           , ("United States", Tag "pn")
                           ]
            , Insensitive
            , "The United States", "The/dt United States/pn")
          , ( "Case insensitivity with multiple tokens"
            , Map.fromList [ ("the", Tag "dt")
                           , ("united states", Tag "pn")]
            , Insensitive
            , "The united states", "The/dt united states/pn")
          , ( "Overlapping tokens: preffer the longest match"
            , Map.fromList [ ("the", Tag "dt")
                           , ("United States", Tag "pn")
                           , ("President of the United States", Tag "pn")
                           ]
            , Insensitive
            , "The President of the United States", "The/dt President of the United States/pn")
          ]
        , testGroup "protectTerms tests" $ map protectTests
          [ ( [], Sensitive, "The United States"
            , ["The United States"])
          , ( ["The"], Sensitive, "The United States"
            , ["The", " United States"])
          , ( ["United States"], Sensitive, "The United States"
            , ["The ", "United States"])
          , ( ["RPM Gauge", "rotor shaft"], Sensitive, "The RPM Gauge on the rotor shaft"
            , ["The ", "RPM Gauge", " on the ", "rotor shaft"])
          , ( ["President of the United States", "United States"], Sensitive
            , "The President of the United States"
            , ["The ", "President of the United States"])
          , ( ["quick", "brown"], Sensitive, "The quick brown fox jumped"
            , ["The ", "quick", " ", "brown", " fox jumped"])
          , ( ["brown", "quick"], Sensitive, "The quick brown fox jumped"
            , ["The ", "quick", " ", "brown", " fox jumped"])
          , ( ["brown", "fox"], Sensitive, "The quick brown fox jumped"
            , ["The quick ", "brown", " ", "fox", " jumped"])
          ]
        , testGroup "protectTerms tests" $ map protectTestsWDefault
          [ ( [], Sensitive, "The United States"
            , ["The", "United", "States"])
          , ( ["The"], Sensitive, "The United States"
            , ["The", "United", "States"])
          , ( ["United States"], Sensitive, "The United States"
            , ["The", "United States"])
          , ( ["RPM Gauge", "rotor shaft"], Sensitive, "The RPM Gauge on the rotor shaft"
            , ["The", "RPM Gauge", "on", "the", "rotor shaft"])
          , ( ["President of the United States", "United States"], Sensitive
            , "The President of the United States"
            , ["The", "President of the United States"])
          , ( ["quick", "brown"], Sensitive
            , "The quick brown fox jumped"
            , ["The", "quick", "brown", "fox", "jumped"])
          , ( ["brown", "quick"], Sensitive
            , "The quick brown fox jumped"
            , ["The", "quick", "brown", "fox", "jumped"])
          , ( ["brown", "fox"], Sensitive
            , "The quick brown fox jumped"
            , ["The", "quick", "brown", "fox", "jumped"])
          , ( ["Rotor RPM"], Insensitive
            , "The rotor rpm increased."
            , ["The", "rotor rpm", "increased", "."])
          ]
        ]

emptyTagger :: POSTagger
emptyTagger = LT.mkTagger Map.empty Sensitive Nothing

prop_emptyAlwaysUnk :: String -> Bool
prop_emptyAlwaysUnk input = all (\(_, y) -> y == tagUNK) (concat $ tag emptyTagger inputTxt)
  where inputTxt = T.pack input

trainAndTagTest :: Maybe POSTagger -> (Text, Map Text Tag, LT.CaseSensitive, Text, Text) -> Test
trainAndTagTest tgr (name, table, sensitive, input, oracle) = testCase (T.unpack name) mkAndTest
  where mkAndTest = let trained = LT.mkTagger table sensitive tgr
                    in oracle @=? tagText trained input


protectTests :: ([Text], LT.CaseSensitive, Text, [Text])
             -- ^ Protected terms, sensitivity, input text, oracle
             -> Test
protectTests (terms, sensitive, input, oracle) = testCase description runTest
  where
    description = T.unpack (T.concat ["Just Protect[", (T.intercalate "; " terms), "] ", input])

    runTest = run (LT.protectTerms terms sensitive) input @?= oracle

protectTestsWDefault :: ([Text], LT.CaseSensitive, Text, [Text])
             -- ^ Protected terms, sensitivity, input text, oracle
             -> Test
protectTestsWDefault (terms, sensitive, input, oracle) = testCase description runTest
  where
    description = T.unpack (T.concat ["w/Default [", (T.intercalate "; " terms), "] ", input])

    runTest = run (LT.protectTerms terms sensitive >=> defaultTokenizer) input @?= oracle
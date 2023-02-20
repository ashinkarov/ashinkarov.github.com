--------------------------------------------------------------------------------
{-# LANGUAGE OverloadedStrings #-}

import Bib
import BibHakyll
import Control.Monad (forM, forM_)
-- (doc,plain,text)

import qualified Data.ByteString.Lazy.Char8 as L8
import Data.Either (fromRight)
import Data.Either.Extra (eitherToMaybe)
import Data.List
import Data.Maybe (fromMaybe)
import Data.Monoid (mappend)
import qualified Data.Text as T
import Hakyll
import Hakyll.Core.Compiler
import Hakyll.Core.Compiler.Internal
import System.Process.Typed
import Text.Pandoc
import qualified Text.Pandoc.Builder as B
import Text.Pandoc.Citeproc
import Text.Pandoc.Readers
import qualified Text.Pandoc.Walk as B
import Text.Pandoc.Writers


-- TODO(artem) there is a builtin function 
-- that calls processes and handles errors.
compilePng :: String -> String -> Compiler (Item L8.ByteString)
compilePng url name = do
  (st, out, err) <- unsafeCompiler $ do
    readProcess $
      proc
        "convert"
        [ "-density",
          "80",
          "-flatten",
          "." <> url <> "[0]",
          "PNG32:-"
        ]
  if st /= ExitSuccess
    then error ("when building png for " <> name <> ": " <> L8.unpack err)
    else makeItem out


bibPng :: Bib -> Rules ()
bibPng b@(Bib ty name items) =
  create [fromFilePath $ "pubs/" <> name <> ".png"] $ do
    route idRoute -- \$ setExtension "png"
    compile $ do
      let url = trim $ fromMaybe (error "No url in bibitem " <> name) (eitherToMaybe . latexifyPlain =<< bibIndex b "url")
      debugCompiler ("URL for " <> name <> " is: '" <> url <> "' ispref = " <> show ("/" `isPrefixOf` url))
      if "/" `isPrefixOf` url
        then do
          compilePng url name
        else -- do
        -- This is the way on how to obtain pdfs automatically.
        -- But I don't see any reason why one wants to do this.
        -- I suppose that we can simply use this code to verify
        -- that all the pdfs that we include are here.
        -- XXX(artem) Autodownloading seem to be a massive overkill.
        -- wget -O - https://github.com/junniest/bach_test_repo/raw/master/paper/paper.pdf
        -- \| convert "/dev/stdin[0]" -density 80 -flatten PNG32:- > x.png
        -- makeItem "" >>= compilePng
          error ("No local url for bibitem " <> name)

-- Copy local pdfs.
-- We do not perform any checks, as by the time
-- we call this function, we should have verified
-- that all the entries in bibs have local pdfs
-- attached.  Otherwise this is an error.
bibPdf :: Bib -> Rules ()
bibPdf b@(Bib ty name items) =
  let url = trim $ fromMaybe (error "No url in bibitem " <> name) 
                             (eitherToMaybe . latexifyPlain =<< bibIndex b "url")
  in create [fromFilePath $ "." <> url ] $ do
    route idRoute
    compile copyFileCompiler


--------------------------------------------------------------------------------
main :: IO ()
main = do
  hakyll $ do
    match "images/*" $ do
      route idRoute
      compile copyFileCompiler

    match "css/*" $ do
      route idRoute
      compile compressCssCompiler

    match (fromList ["about.rst", "contact.markdown"]) $ do
      route $ setExtension "html"
      compile $
        pandocCompiler
          >>= loadAndApplyTemplate "templates/default.html" defaultContext
          >>= relativizeUrls

    match "posts/*" $ do
      route $ setExtension "html"
      compile $
        do
          pandocCompiler
          >>= loadAndApplyTemplate "templates/post.html" postCtx
          >>= loadAndApplyTemplate "templates/default.html" postCtx
          >>= relativizeUrls

    create ["archive.html"] $ do
      route idRoute
      compile $ do
        posts <- recentFirst =<< loadAll "posts/*"
        let archiveCtx =
              listField "posts" postCtx (return posts)
                `mappend` constField "title" "Archives"
                `mappend` defaultContext

        makeItem ""
          >>= loadAndApplyTemplate "templates/archive.html" archiveCtx
          >>= loadAndApplyTemplate "templates/default.html" archiveCtx
          >>= relativizeUrls

    -- Get the bibliography file.
    (Bibs bibs) <- preprocess $ do
      parseBibFile <$> readFile "bib.bib"

    -- Verify that bibs have local Pdfs
    -- and generate pictures.
    forM_ bibs bibPng
    -- Copy pdfs.
    forM_ bibs bibPdf

    match "bib.bib" $ do
      route idRoute
      compile bibFileCompiler

    forM_ bibs $ \b ->
      create [fromCapture "pubs/*.html" $ name b] $ do
        route idRoute
        compile $ do
          -- Load bib database and extract the right entry
          bibFile <- loadBody "bib.bib" :: Compiler Bibs
          makeItem b
            >>= loadAndApplyTemplate "templates/pub.html" bibContext
            >>= loadAndApplyTemplate "templates/default.html" defaultContext
            >>= relativizeUrls

    create ["publications.html"] $ do
      route idRoute
      compile $ do
        (Bibs bibFile) <- loadBody "bib.bib" :: Compiler Bibs
        let bibsCtx = listField "pubs" bibContext (mapM makeItem bibFile)
        makeItem "" 
           >>= loadAndApplyTemplate "templates/pubs.html" bibsCtx
           >>= loadAndApplyTemplate "templates/default.html" defaultContext
           >>= relativizeUrls

    match "index.md" $ do
      route $ setExtension "html"
      compile $ do
        posts <- recentFirst =<< loadAll "posts/*"
        let indexCtx =
              listField "posts" postCtx (return posts)
                `mappend` defaultContext

        pandocCompiler
          >>= applyAsTemplate indexCtx
          >>= loadAndApplyTemplate "templates/default.html" indexCtx
          >>= relativizeUrls

    match "templates/*" $ compile templateBodyCompiler

--------------------------------------------------------------------------------
postCtx :: Context String
postCtx =
  dateField "date" "%B %e, %Y"
    `mappend` defaultContext

pubsCtx :: Context String
pubsCtx = defaultContext

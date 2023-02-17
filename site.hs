--------------------------------------------------------------------------------
{-# LANGUAGE OverloadedStrings #-}

import Bib
import Control.Monad (forM, forM_)
-- (doc,plain,text)

import qualified Data.ByteString.Lazy.Char8 as L8
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
import qualified Text.Pandoc.Walk as B
import Text.Pandoc.Citeproc
import Text.Pandoc.Readers
import Text.Pandoc.Writers
import Data.Either (fromRight)
import Data.Either.Extra (eitherToMaybe)
import GHC.SourceGen (do')
import HieDb.Run (symbolParser)


latexifyPlain :: String -> Either PandocError String
latexifyPlain s = do
  la <- runPure $ readLaTeX def $ T.pack s
  te <- runPure $ writePlain def la
  return $ T.unpack te

latexifyHtml :: String -> Either PandocError String
latexifyHtml s = do
  la <- runPure $ readLaTeX def $ T.pack s
  te <- runPure $ writeHtml5String def la
  return $ T.unpack te


bibToContext :: Bib -> Context String
bibToContext b@(Bib ty name items) =
  constField "itemtype" ty
    <> mconcat (fmap (\e -> constField (key e) (value e)) items')
    <> constField "name" name
    <> constField "bib" (showBib $ filterKeys b ["url", "parsed", "abstract", "addinfo"])
    <> constField "img" ("/pubs/" <> name <> ".png")
  where
    -- XXX(artem) I am not sure what the rules should be. 
    -- * we don't want to latexify "parsed" (as it is in Html already)
    -- * we want to Htmlify "abstract", as there miht be some symbols 
    -- * we want to Plaintext the rest?
    items' = mapEntriesIfKey (`notElem` ["parsed","abstract","addinfo"]) latexifyPlain'
             $ mapEntriesIfKey (`elem` ["abstract","addinfo"]) latexifyHtml' items
    latexifyHtml' = fromRight (error "bibToContext for entry " <> name) . latexifyHtml 
    latexifyPlain' = fromRight (error "bibToContext for entry " <> name) . latexifyPlain 


bibCls :: Bib -> IO String
bibCls bib = do
  let s = showBib $ filterKeys bib ["url"]
  res <- runIO $ do
    doc <- B.setMeta (T.pack "citation-style") (T.pack "ieee")
           <$> readBibLaTeX def (T.pack s)
    --let doc' = B.setMeta (T.pack "citation-style") (T.pack "ieee") doc :: Pandoc
    processed <- cleanup <$> processCitations doc
    writeHtml5String def processed
  T.unpack <$> handleError res
  where
    -- Just get this span, everything else is junk.
    cleanup :: Pandoc -> Pandoc
    cleanup p = B.doc $ B.para $ B.fromList $ B.query f p

    f :: Inline -> [Inline]
    f (Span (_, ["csl-right-inline"], _) bs) = bs
    f x = []

bibRule :: Bib -> Rules ()
bibRule b@(Bib ty name its) =
  create [fromFilePath $ "pubs/" <> name <> ".html"] $ do
    route idRoute -- $ setExtension "html"
    compile $ do
      let pubCtx = bibToContext b
      debugCompiler (showBib b)
      makeItem ""
        >>= loadAndApplyTemplate "templates/pub.html" pubCtx
        >>= loadAndApplyTemplate "templates/default.html" defaultContext
        >>= relativizeUrls


clsifyBib :: [Bib] -> IO [Bib]
clsifyBib [] = return []
clsifyBib (b@(Bib ty nm items) : bs) = do
  s <- bibCls b
  (Bib ty nm (Entry (normaliseKey "parsed") s : items) :) <$> clsifyBib bs

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
    if st /= ExitSuccess then
      error ("when building png for " <> name <> ": " <> L8.unpack err)
    else
      makeItem out

--trim :: String -> String
--trim s = T.unpack $ T.strip $ T.pack s

bibPng :: Bib -> Rules ()
bibPng b@(Bib ty name items) =
  create [fromFilePath $ "pubs/" <> name <> ".png"] $ do
    route idRoute -- $ setExtension "png"
    compile $ do
      let url = trim $ fromMaybe (error "No url in bibitem " <> name) (eitherToMaybe . latexifyPlain =<< bibIndex b "url")
      debugCompiler ("URL for " <> name <> " is: '" <> url <> "' ispref = " <> show ("/" `isPrefixOf` url))
      if "/" `isPrefixOf` url
        then do
          compilePng url name 
        else --do
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
  create [fromFilePath $ "pubs/" <> name <> ".pdf"] $ do
    route idRoute
    compile copyFileCompiler


bibCtx :: Bib -> Context String
bibCtx b@(Bib ty name items) =
  field name f where
    f it = return
         $ fromMaybe (error "bibCtx")
                     (bibIndex b $ itemBody it)


bibHtml :: Bib -> String
bibHtml b@(Bib ty name items) =
  "<li>"
    <> get "year"
    <> "&mdash; <a href='/pubs/" <> name <> ".html'>"
       <> get "title"
    <> "</a>"
  <> "</li>"
  where get k = fromMaybe (error "bibHtml") (eitherToMaybe . latexifyPlain =<< bibIndex b k)

bibsHtml bs = intercalate "\n" $ fmap bibHtml bs


--------------------------------------------------------------------------------
main :: IO ()
main = do
  -- Load bibitems.
  bibsOrError <- loadBibs "bib.bib"
  let bibs = case bibsOrError of
        Left e -> error e
        Right b -> b

  bibs <- clsifyBib bibs

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

    -- Verify that bibs have local Pdfs 
    -- and generate pictures. 
    forM_ bibs bibPng

    -- Generate individual pbulications.
    forM_ bibs bibRule

    -- Copy pdfs.
    forM_ bibs bibPdf

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

    create ["publications.html"] $ do
      route idRoute
      compile $ do
        let pubCtx =
              constField "pubs" (bibsHtml bibs)
              <> defaultContext
        makeItem ""
          >>= loadAndApplyTemplate "templates/pubs.html" pubCtx
          >>= loadAndApplyTemplate "templates/default.html" pubCtx
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

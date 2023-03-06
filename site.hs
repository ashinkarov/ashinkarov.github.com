--------------------------------------------------------------------------------
{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE TupleSections #-}
{-# LANGUAGE FlexibleInstances #-}

import Bib
import BibHakyll

import Control.Monad (forM, forM_, (>=>), liftM, void, msum)
import qualified Data.ByteString.Lazy.Char8 as L8
import Data.Either (fromRight, isLeft, fromLeft)
import Data.Either.Extra (eitherToMaybe)
import Data.List
import Data.Ord (comparing)
import Data.Maybe (fromMaybe)
import Data.Monoid (mappend)
import qualified Data.Text as T
import Hakyll
import Hakyll.Core.Compiler
import Hakyll.Core.Identifier
import System.Process.Typed
import Text.Pandoc
import qualified Text.Pandoc.Builder as B
import qualified Text.Pandoc.Walk as B
import Text.Pandoc.Citeproc
import Text.Pandoc.Readers
import Text.Pandoc.Writers
import qualified Data.Map.Lazy as M
import Data.Time (UTCTime(UTCTime), parseTimeOrError, defaultTimeLocale, parseTimeM, parseTime)


myFeedConfiguration :: FeedConfiguration
myFeedConfiguration = FeedConfiguration
    { feedTitle       = "Posts by Artem"
    , feedDescription = "My personal web page"
    , feedAuthorName  = "Artem Shinkarov"
    , feedAuthorEmail = "tema@pm.me"
    , feedRoot        = "http://ashinkarov.github.io/"
    }

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

    match (fromList ["about.rst", "contact.markdown", 
                     "name.md", "links.md"]) $ do
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
          >>= saveSnapshot "content"
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
      -- TODO(artem) latexify all the items inside bibs, so that 
      -- we only do it once.
      parseBibFile <$> readFile "bib.bib"

    -- Verify that bibs have local Pdfs
    -- and generate pictures.
    forM_ bibs bibPng
    -- Copy pdfs.
    --forM_ bibs bibPdf

    -- Copy all pdf files in pubs to _site/pubs.
    match "pubs/**" $ do
      route idRoute
      compile copyFileCompiler

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
            >>= saveSnapshot "content"
            >>= loadAndApplyTemplate "templates/default.html" defaultContext
            >>= relativizeUrls

    create ["publications.html"] $ do
      route idRoute
      compile $ do
        (Bibs bibFile) <- loadBody "bib.bib" :: Compiler Bibs
        --

        -- r <- mapM (\x -> (x,) <$> f x) xs
        -- return $ fst <$> sortBy (comparing snd) r
        let sortedBibs = reverse $ fmap fst $ sortBy (comparing snd) $ fmap (\b -> (b, bibDate b)) bibFile
        let bibsCtx = listField "pubs" bibContext (mapM makeItem sortedBibs)
        makeItem ""
           >>= loadAndApplyTemplate "templates/pubs.html" (dateField "date" "%B %e, %Y" <> bibsCtx)
           >>= loadAndApplyTemplate "templates/default.html" defaultContext
           >>= relativizeUrls

    match "index.md" $ do
      route $ setExtension "html"
      compile $ do
        -- XXX(artem) Do I need this?
        posts <- recentFirst =<< loadAll "posts/*"
        let indexCtx =
              listField "posts" postCtx (return posts)
                `mappend` defaultContext

        pandocCompiler
          >>= applyAsTemplate indexCtx
          >>= loadAndApplyTemplate "templates/default.html" indexCtx
          >>= relativizeUrls

    create ["atom.xml"] $ do
        route idRoute
        compile $ do
            (Bibs bs) <- loadBody "bib.bib" :: Compiler Bibs
            s <- loadAllSnapshots "posts/*" "content" :: Compiler [Item String]
            q <- loadAllSnapshots "pubs/*.html" "content" :: Compiler [Item String]
            sq <- sortByM (strBibAware bs) $ s <> q

            -- debugCompiler ("sorted: " <> show (fmap itemIdentifier $ s <> q))
            -- debugCompiler ("sorted: " <> show (fmap itemIdentifier sq))

            let feedCtx = bibStrCtx bs
                       <> postCtx
                       <> bodyField "description"

            renderAtom myFeedConfiguration feedCtx (take 10 sq)

    match "templates/*" $ compile templateBodyCompiler


--------------------------------------------------------------------------------

bibDate :: Bib -> UTCTime
bibDate b = let
        latexifyPlain' = fromRight (error $ "bibDate for entry " <> Bib.name b) . latexifyPlain
        date = latexifyPlain' $ fromMaybe (error $ "bibDate: no date in entry " <> Bib.name b) $ bibIndex b "date"
        parsed = parseTimeOrError True defaultTimeLocale "%Y-%m-%d" date :: UTCTime
        in parsed

-- XXX(artem) this is predicated on the assumption that publication
-- items are called "pubs/xxx.html".  One could avoid this if you
-- were able to extend the metadata.  This would be needed for the
-- sorting function which insists on grabbing date from metadata.
strBibAware :: [Bib] -> Item String -> Compiler UTCTime
strBibAware bs' it =
  if "pubs" `isPrefixOf` toFilePath (itemIdentifier it) then do
    let bs = map (\(Bib ty n it) -> Bib ty ("pubs/" <> n <> ".html") it) bs'
    case bibsIndex bs (toFilePath $ itemIdentifier it) of
      Nothing -> fail "strBibAware"
      Just b -> return $ bibDate b
  else
    getItemUTC defaultTimeLocale (itemIdentifier it)


sortByM :: (Monad m, Ord k) => (a -> m k) -> [a] -> m [a]
sortByM f xs = do
  r <- mapM (\x -> (x,) <$> f x) xs
  return $ fst <$> sortBy (comparing snd) r

-- XXX(artem) This is also predicated on the assumption that publications
-- are called "pubs/XXX.html".  We wouldn't need to do this if we were 
-- able to attach metadata to the virtual file.
bibStrCtx :: [Bib] -> Context String
bibStrCtx bs' =
  Context $ \key v item -> do
  let bs = map (\(Bib ty n it) -> Bib ty ("pubs/" <> n <> ".html") it) bs'
  let Context f = bibContext
  case bibsIndex bs (toFilePath $ itemIdentifier item) of
    Nothing -> noResult "bibStrCtx"
    Just b -> (case key of
        "published" -> f "date" v (Item (itemIdentifier item) b)
        "updated" -> return $ StringField "false"
        "url" -> noResult "see the outer context"  --return $ StringField "BLaAAAAH"
        k -> f k v (Item (itemIdentifier item) b))

postCtx :: Context String
postCtx =
  dateField "date" "%B %e, %Y" <>
  defaultContext

pubsCtx :: Context String
pubsCtx = defaultContext


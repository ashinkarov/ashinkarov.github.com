{-# LANGUAGE OverloadedStrings #-}

-- A lof of the ideas are taken from:
-- https://github.com/jaspervdj/hakyll-bibtex

module BibHakyll where

import Bib
import Data.Binary
import Data.Either (fromRight)
import qualified Data.Text as T
import Data.Typeable (Typeable)
import Hakyll
import Text.Pandoc
import qualified Text.Pandoc.Builder as B
import Text.Pandoc.Citeproc
import Text.Pandoc.Readers
import qualified Text.Pandoc.Walk as B
import Text.Pandoc.Writers
import Text.Parsec

instance Binary Bib.Entry where
  put (Entry k v) = do
    put k
    put v

  get = Entry <$> get <*> get

instance Binary Bib where
  put (Bib ty nm items) = do
    put ty
    put nm
    put items

  get = Bib <$> get <*> get <*> get

instance Writable Bib where
  write file item = writeFile file (showBib $ itemBody item)

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

bibCls :: Bib -> IO String
bibCls bib = do
  let s = showBib $ filterKeys bib ["url"]
  res <- runIO $ do
    -- FIXME(artem) The "ieee" can be lifted into dependency.
    doc <-
      B.setMeta (T.pack "citation-style") (T.pack "ieee")
        <$> readBibLaTeX def (T.pack s)
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

bibContext :: Context Bib
bibContext =
  Context $ \key _ item -> do
    let b = itemBody item
    let name = Bib.name b
    parsed <- unsafeCompiler $ bibCls b
    let latexifyHtml' = fromRight (error "bibToContext for entry " <> name) . latexifyHtml
    let latexifyPlain' = fromRight (error "bibToContext for entry " <> name) . latexifyPlain
    let str s = return $ StringField s
    let strPlain = str . latexifyPlain':: String -> Compiler ContextField
    let strHtml = str . latexifyHtml' :: String -> Compiler ContextField
    case key of
      "name" -> str name
      "entrytype" -> str $ entrytype b
      "parsed" -> str parsed
      "bib" -> str (showBib $ filterKeys b ["url", "parsed", "abstract", "addinfo"])
      -- XXX(artem) should we simply put this into template?
      "img" -> str ("/pubs/" <> name <> ".png")
      _ -> case bibIndex b key of
        Nothing ->
          noResult $
            "No key " <> key <> " in bibitem " <> name
        Just x | key `elem` ["abstract", "addinfo"] -> strHtml x
        Just x -> strPlain x

newtype Bibs = Bibs [Bib]
  deriving (Show, Typeable)

instance Binary Bibs where
  put (Bibs b) = put b
  get = Bibs <$> get

instance Writable Bibs where
  write file item =
    let Bibs bs = itemBody item
     in writeFile file $ showBibs bs

parseBibFile s = case parse parseBibs "" s of
  Right p -> Bibs p
  Left p -> error $ "Parse error: " <> show p

bibFileCompiler :: Compiler (Item Bibs)
bibFileCompiler = fmap parseBibFile <$> getResourceString


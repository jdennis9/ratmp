package fontconfig

import "core:c"

foreign import lib {
	"system:fontconfig",
	"../bindings.a",
}

FAMILY          :cstring : "family"         /* String */
STYLE           :cstring : "style"          /* String */
SLANT           :cstring : "slant"          /* Int */
WEIGHT          :cstring : "weight"         /* Int */
SIZE            :cstring : "size"           /* Range (double) */
ASPECT          :cstring : "aspect"         /* Double */
PIXEL_SIZE      :cstring : "pixelsize"      /* Double */
SPACING         :cstring : "spacing"        /* Int */
FOUNDRY         :cstring : "foundry"        /* String */
ANTIALIAS       :cstring : "antialias"      /* Bool (depends) */
HINTING         :cstring : "hinting"        /* Bool (true) */
HINT_STYLE      :cstring : "hintstyle"      /* Int */
VERTICAL_LAYOUT :cstring : "verticallayout" /* Bool (false) */
AUTOHINT        :cstring : "autohint"       /* Bool (false) */
WIDTH           :cstring : "width"          /* Int */
FILE            :cstring : "file"           /* String */
INDEX           :cstring : "index"          /* Int */
FT_FACE         :cstring : "ftface"         /* FT_Face */
RASTERIZER      :cstring : "rasterizer"     /* String (deprecated) */
OUTLINE         :cstring : "outline"        /* Bool */
SCALABLE        :cstring : "scalable"       /* Bool */
COLOR           :cstring : "color"          /* Bool */
VARIABLE        :cstring : "variable"       /* Bool */
SCALE           :cstring : "scale"          /* double (deprecated) */
SYMBOL          :cstring : "symbol"         /* Bool */
DPI             :cstring : "dpi"            /* double */
RGBA            :cstring : "rgba"           /* Int */
MINSPACE        :cstring : "minspace"       /* Bool use minimum line spacing */
SOURCE          :cstring : "source"         /* String (deprecated) */
CHARSET         :cstring : "charset"        /* CharSet */
LANG            :cstring : "lang"           /* LangSet Set of RFC 3066 langs */
FONTVERSION     :cstring : "fontversion"    /* Int from 'head' table */
FULLNAME        :cstring : "fullname"       /* String */
FAMILYLANG      :cstring : "familylang"     /* String RFC 3066 langs */
STYLELANG       :cstring : "stylelang"      /* String RFC 3066 langs */
FULLNAMELANG    :cstring : "fullnamelang"   /* String RFC 3066 langs */
CAPABILITY      :cstring : "capability"     /* String */
FONTFORMAT      :cstring : "fontformat"     /* String */
EMBOLDEN        :cstring : "embolden"       /* Bool - true if emboldening needed*/
EMBEDDED_BITMAP :cstring : "embeddedbitmap" /* Bool - true to enable embedded bitmaps */
DECORATIVE      :cstring : "decorative"     /* Bool - true if style is a decorative variant */
LCD_FILTER      :cstring : "lcdfilter"      /* Int */
FONT_FEATURES   :cstring : "fontfeatures"   /* String */
FONT_VARIATIONS :cstring : "fontvariations" /* String */
NAMELANG        :cstring : "namelang"       /* String RFC 3866 langs */
PRGNAME         :cstring : "prgname"        /* String */
HASH            :cstring : "hash"           /* String (deprecated) */
POSTSCRIPT_NAME :cstring : "postscriptname" /* String */
FONT_HAS_HINT   :cstring : "fonthashint"    /* Bool - true if font has hinting */
ORDER           :cstring : "order"          /* Integer */
DESKTOP_NAME    :cstring : "desktop"        /* String */
NAMED_INSTANCE  :cstring : "namedinstance"  /* Bool - true if font is named instance */
FONT_WRAPPER    :cstring : "fontwrapper"    /* String */

Result :: enum {
    Match,
    NoMatch,
    TypeMismatch,
    NoId,
    OutOfMemory
}

Config :: struct {}
Pattern :: struct {}
ObjectSet :: struct {
	nobject: c.int,
	sobject: c.int,
	objects: [^]cstring,
}

FontSet :: struct {
	nfont: c.int,
	sfont: c.int,
	fonts: [^]^Pattern,
}

@(link_prefix="Fc")
foreign lib {
	InitLoadConfigAndFonts :: proc() -> ^Config ---
	Fini :: proc() ---

	PatternCreate :: proc() -> ^Pattern ---
	PatternGetString :: proc(p: ^Pattern, object: cstring, n: c.int, s: ^cstring) -> Result ---
	PatternDestroy :: proc(p: ^Pattern) ---

	ObjectSetBuild :: proc(..cstring) -> ^ObjectSet ---
	ObjectSetDestroy :: proc(os: ^ObjectSet) ---

	FontList :: proc(config: ^Config, pattern: ^Pattern, os: ^ObjectSet) -> ^FontSet ---
	FontSetDestroy :: proc(fs: ^FontSet) ---
}

@(link_prefix="fontconfig_")
foreign lib {
	object_set_build_family_file :: proc() -> ^ObjectSet ---
}
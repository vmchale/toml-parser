{
{-# LANGUAGE Trustworthy #-}
{-|
Module      : Parser
Description : /Internal:/ Parser for TOML generated by Happy
Copyright   : (c) Eric Mertens, 2017
License     : ISC
Maintainer  : emertens@gmail.com

Parser for TOML generated by Happy.

-}
module Parser (parseComponents) where

import Data.Text (Text,pack)

import Components
import Errors
import Located
import Tokens
import Value

}

%tokentype                      { Located Token                 }
%token
STRING                          { Located _ (StringToken $$)    }
BAREKEY                         { Located _ (BareKeyToken $$)   }
INTEGER                         { Located _ (IntegerToken $$)   }
DOUBLE                          { Located _ (DoubleToken $$)    }
'true'                          { Located _ TrueToken           }
'false'                         { Located _ FalseToken          }
'['                             { $$@(Located _ LeftBracketToken)}
']'                             { Located _ RightBracketToken   }
'{'                             { $$@(Located _ LeftBraceToken) }
'}'                             { Located _ RightBraceToken     }
','                             { Located _ CommaToken          }
'.'                             { Located _ PeriodToken         }
'='                             { Located _ EqualToken          }
ZONEDTIME                       { Located _ (ZonedTimeToken $$) }
LOCALTIME                       { Located _ (LocalTimeToken $$) }
TIMEOFDAY                       { Located _ (TimeOfDayToken $$) }
DAY                             { Located _ (DayToken       $$) }
EOF                             { Located _ EofToken            }

%monad { Either TOMLError }
%error { errorP }

-- | Attempt to parse a layout annotated token stream or
-- the token that caused the parse to fail.
%name components

%%

components ::                   { [Component]                   }
  : componentsR EOF             { reverse $1                    }

componentsR ::                  { [Component]                   }
  : keyvalues                   { [InitialEntry $1]             }
  | componentsR component keyvalues { $2 $3 : $1                }

component ::                    { [(Text,Value)] -> Component   }
  : '['     keys     ']'        { TableEntry $2                 }
  | '[' '[' keys ']' ']'        { ArrayEntry $3                 }

  | '['     keys     error      {% unterminated $1              }
  | '[' '[' keys     error      {% unterminated $2              }
  | '[' '[' keys ']' error      {% unterminated $1              }

keyvalues ::                    { [(Text,Value)]                }
  : keyvaluesR                  { reverse $1                    }

keyvaluesR ::                   { [(Text,Value)]                }
  :                             { []                            }
  | keyvaluesR key '=' value    { ($2,$4):$1                    }

keys ::                         { [Text]                        }
  : keysR                       { reverse $1                    }

keysR ::                        { [Text]                        }
  : key                         { [$1]                          }
  | keysR '.' key               { $3 : $1                       }

key ::                          { Text                          }
  : BAREKEY                     { $1                            }
  | STRING                      { $1                            }
  | INTEGER                     { pack (show $1)                }
  | 'true'                      { pack "true"                   }
  | 'false'                     { pack "false"                  }

value ::                        { Value                         }
  : INTEGER                     { Integer    $1                 }
  | DOUBLE                      { Double     $1                 }
  | STRING                      { String     $1                 }
  | ZONEDTIME                   { ZonedTimeV $1                 }
  | TIMEOFDAY                   { TimeOfDayV $1                 }
  | DAY                         { DayV       $1                 }
  | LOCALTIME                   { LocalTimeV $1                 }
  | 'true'                      { Bool       True               }
  | 'false'                     { Bool       False              }
  | '{' inlinetable '}'         { Table      $2                 }
  | '[' inlinearray ']'         { List       $2                 }

  | '{' inlinetable error       {% unterminated $1              }
  | '[' inlinearray error       {% unterminated $1              }

inlinetable ::                  { [(Text,Value)]                }
  :                             { []                            }
  | inlinetableR                { reverse $1                    }

inlinetableR ::                 { [(Text,Value)]                }
  : key '=' value               { [($1,$3)]                     }
  | inlinetableR ',' key '=' value
                                { ($3,$5):$1                    }

inlinearray ::                  { [Value]                       }
  :                             { []                            }
  | inlinearrayR                { reverse $1                    }
  | inlinearrayR ','            { reverse $1                    }

inlinearrayR ::                 { [Value]                       }
  : value                       { [$1]                          }
  | inlinearrayR ',' value      { $3 : $1                       }

{

-- | This operation is called by happy when no production matches the
-- current token list.
errorP :: [Located Token] {- ^ nonempty remainig tokens -} -> Either TOMLError a
errorP = Left . Unexpected . head

-- | Attempt to parse a layout annotated token stream or
-- the token that caused the parse to fail.
parseComponents ::
  [Located Token]              {- ^ layout annotated token stream -} ->
  Either TOMLError [Component] {- ^ token at failure or result -}
parseComponents = components

-- | Abort the parse with an error indicating that the given token was unmatched.
unterminated :: Located Token -> Either TOMLError a
unterminated = Left . Unterminated

}

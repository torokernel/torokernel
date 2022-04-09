{******************************************************************************}
{                                                                              }
{   Library:          Fundamentals 4.00                                        }
{   File name:        cHash.pas                                                }
{   File version:     4.18                                                     }
{   Description:      Hashing functions                                        }
{                                                                              }
{   Copyright:        Copyright (c) 1999-2013, David J Butler                  }
{                     All rights reserved.                                     }
{                     Redistribution and use in source and binary forms, with  }
{                     or without modification, are permitted provided that     }
{                     the following conditions are met:                        }
{                     Redistributions of source code must retain the above     }
{                     copyright notice, this list of conditions and the        }
{                     following disclaimer.                                    }
{                     THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND   }
{                     CONTRIBUTORS "AS IS" AND ANY EXPRESS OR IMPLIED          }
{                     WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED   }
{                     WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A          }
{                     PARTICULAR PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL     }
{                     THE REGENTS OR CONTRIBUTORS BE LIABLE FOR ANY DIRECT,    }
{                     INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR             }
{                     CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO,    }
{                     PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF     }
{                     USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION)         }
{                     HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER   }
{                     IN CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING        }
{                     NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE   }
{                     USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE             }
{                     POSSIBILITY OF SUCH DAMAGE.                              }
{                                                                              }
{   Github:           https://github.com/fundamentalslib                       }
{   E-mail:           fundamentalslib at gmail.com                             }
{                                                                              }
{ Revision history:                                                            }
{                                                                              }
{   2002/04/02  0.01  Initial version from cUtils unit.                        }
{                     Hash: Checksum, XOR, CRC, MD5, SHA1, SHA256, SNS         }
{                     Keyed hash: HMAC-MD5, HMAC-SHA1                          }
{   2002/04/03  0.02  Securely clear passwords from memory after use.          }
{   2002/04/05  0.03  Added SNS hashing.                                       }
{   2002/04/19  0.04  Added ISBN checksum.                                     }
{   2003/07/26  0.05  Added ELF hashing.                                       }
{   2003/09/08  3.06  Revised for Fundamentals 3.                              }
{   2005/07/22  4.07  Compilable with FreePascal 2.0 Win32 i386.               }
{   2005/08/27  4.08  Revised for Fundamentals 4.                              }
{   2008/04/28  4.09  Added Adler hashing.                                     }
{   2008/12/30  4.10  Revision.                                                }
{   2010/06/27  4.11  Compilable with FreePascal 2.4.0 OSX x86-64              }
{   2010/11/14  4.12  Added SHA256.                                            }
{   2010/11/15  4.13  Added HMAC-SHA256.                                       }
{   2010/11/16  4.14  Added SHA512.                                            }
{   2010/11/17  4.15  Added HMAC-SHA512, SHA224, SHA384.                       }
{   2011/04/02  4.16  Compilable with Delphi 5.                                }
{   2011/10/14  4.17  Compilable with Delphi XE.                               }
{   2013/01/27  4.18  Added RipeMD160 sponsored and donated by Stefan Westner. }
{                                                                              }
{ Supported compilers:                                                         }
{                                                                              }
{   Borland Delphi 5-XE Win32 i386                                             }
{   FreePascal 2 Win32 i386                                                    }
{   FreePascal 2 Linux i386                                                    }
{                                                                              }
{ Definitions:                                                                 }
{                                                                              }
{   Hashes are algorithms for computing condensed representations of           }
{   messages.                                                                  }
{   The message is the data being condensed.                                   }
{   The condensed representation is called the message digest.                 }
{                                                                              }
{   Hashes are called secure if it is computationally infeasible to            }
{   find a message that produce a given digest.                                }
{                                                                              }
{   Keyed hashes use a key (password) in the hashing process.                  }
{                                                                              }
{ Hash algorithms:                                                             }
{                                                                              }
{   Algorithm    Digest size (bits)  Uses                                      }
{   ------------ ------------------  ------------------------------            }
{   Checksum       32                General                                   }
{   XOR8           8                 General                                   }
{   XOR16          16                General                                   }
{   XOR32          32                General                                   }
{   CRC16          16                General / Error detection                 }
{   CRC32          32                General / Error detection                 }
{   Adler32        32                General                                   }
{   ELF            32                General                                   }
{   Knuth          32                General                                   }
{   MD5            128               Secure hash                               }
{   SHA1           160               Secure hash                               }
{   SHA256         256               Secure hash                               }
{   SHA512         512               Secure hash                               }
{   RipeMD160      160               Secure hash                               }
{   HMAC/MD5       128               Secure keyed hash                         }
{   HMAC/SHA1      160               Secure keyed hash                         }
{   HMAC/SHA256    256               Secure keyed hash                         }
{   HMAC/SHA512    512               Secure keyed hash                         }
{                                                                              }
{ Other:                                                                       }
{                                                                              }
{   Algorithm    Type                                                          }
{   ------------ --------------------------------------------------            }
{   ISBN         Check-digit for International Standard Book Number            }
{   LUHN         Check-digit for credit card numbers                           }
{                                                                              }
{******************************************************************************}

{$INCLUDE cFundamentals.inc}

{$IFDEF FREEPASCAL}
  {$WARNINGS OFF}{$HINTS OFF}
  {$Q-,R-} // bug in fpc
{$ENDIF}

{$IFDEF DEBUG}
{$IFDEF SELFTEST}
  {$DEFINE HASH_SELFTEST}
{$ENDIF}
{$ENDIF}

unit cHash;

interface

uses
  { System }
  SysUtils;



{                                                                              }
{ System type definitions                                                      }
{                                                                              }
{$IFNDEF SupportRawByteString}
type
  RawByteString = AnsiString;
  PRawByteString = ^RawByteString;
{$ENDIF}



{                                                                              }
{ Hash digests                                                                 }
{                                                                              }
type
  PByte = ^Byte;
  PWord = ^Word;
  PLongWord = ^LongWord;
  Word64 = packed record
    case Integer of
    0 : (Bytes     : array[0..7] of Byte);
    1 : (Words     : array[0..3] of Word);
    2 : (LongWords : array[0..1] of LongWord);
  end;
  PWord64 = ^Word64;
  T128BitDigest = record
    case integer of
      0 : (Int64s : array[0..1] of Int64);
      1 : (Longs  : array[0..3] of LongWord);
      2 : (Words  : array[0..7] of Word);
      3 : (Bytes  : array[0..15] of Byte);
    end;
  P128BitDigest = ^T128BitDigest;
  T160BitDigest = record
    case integer of
      0 : (Longs : array[0..4] of LongWord);
      1 : (Words : array[0..9] of Word);
      2 : (Bytes : array[0..19] of Byte);
    end;
  P160BitDigest = ^T160BitDigest;
  T224BitDigest = record
    case integer of
      0 : (Longs : array[0..6] of LongWord);
      1 : (Words : array[0..13] of Word);
      2 : (Bytes : array[0..27] of Byte);
    end;
  P224BitDigest = ^T224BitDigest;
  T256BitDigest = record
    case integer of
      0 : (Longs : array[0..7] of LongWord);
      1 : (Words : array[0..15] of Word);
      2 : (Bytes : array[0..31] of Byte);
    end;
  P256BitDigest = ^T256BitDigest;
  T384BitDigest = record
    case integer of
      0 : (Word64s : array[0..5] of Word64);
      1 : (Longs   : array[0..11] of LongWord);
      2 : (Words   : array[0..23] of Word);
      3 : (Bytes   : array[0..47] of Byte);
    end;
  P384BitDigest = ^T384BitDigest;
  T512BitDigest = record
    case integer of
      0 : (Word64s : array[0..7] of Word64);
      1 : (Longs   : array[0..15] of LongWord);
      2 : (Words   : array[0..31] of Word);
      3 : (Bytes   : array[0..63] of Byte);
    end;
  P512BitDigest = ^T512BitDigest;
  T512BitBuf  = array[0..63] of Byte;
  T1024BitBuf = array[0..127] of Byte;

const
  MaxHashDigestSize = Sizeof(T160BitDigest);

procedure DigestToHexBufA(const Digest; const Size: Integer; const Buf);
procedure DigestToHexBufW(const Digest; const Size: Integer; const Buf);
function  DigestToHexA(const Digest; const Size: Integer): RawByteString;
function  DigestToHexW(const Digest; const Size: Integer): WideString;
function  Digest128Equal(const Digest1, Digest2: T128BitDigest): Boolean;
function  Digest160Equal(const Digest1, Digest2: T160BitDigest): Boolean;
function  Digest224Equal(const Digest1, Digest2: T224BitDigest): Boolean;
function  Digest256Equal(const Digest1, Digest2: T256BitDigest): Boolean;
function  Digest384Equal(const Digest1, Digest2: T384BitDigest): Boolean;
function  Digest512Equal(const Digest1, Digest2: T512BitDigest): Boolean;

procedure Digest512XOR8(var Digest: T512BitDigest; const A: Byte);
procedure Digest512XOR32(var Digest: T512BitDigest; const A: LongWord);



{                                                                              }
{ Hash errors                                                                  }
{                                                                              }
const
  hashNoError            = 0;
  hashInternalError      = 1;
  hashInvalidHashType    = 2;
  hashInvalidBuffer      = 3;
  hashInvalidBufferSize  = 4;
  hashInvalidDigest      = 5;
  hashInvalidKey         = 6;
  hashInvalidFileName    = 7;
  hashFileOpenError      = 8;
  hashFileSeekError      = 9;
  hashFileReadError      = 10;
  hashNotKeyedHashType   = 11;
  hashTooManyOpenHandles = 12;
  hashInvalidHandle      = 13;
  hashMAX_ERROR          = 13;

function  GetHashErrorMessage(const ErrorCode: LongWord): PChar;

type
  EHashError = class(Exception)
  protected
    FErrorCode : LongWord;

  public
    constructor Create(const ErrorCode: LongWord; const Msg: String = '');
    property ErrorCode: LongWord read FErrorCode;
  end;



{                                                                              }
{ Secure memory clear                                                          }
{   Used to clear keys and other sensitive data from memory                    }
{                                                                              }
procedure SecureClear(var Buf; const BufSize: Integer);
procedure SecureClear512(var Buf: T512BitBuf);
procedure SecureClear1024(var Buf: T1024BitBuf);
procedure SecureClearStr(var S: String);
procedure SecureClearStrA(var S: RawByteString);
procedure SecureClearStrW(var S: WideString);



{                                                                              }
{ Checksum hashing                                                             }
{                                                                              }
function  CalcChecksum32(const Buf; const BufSize: Integer): LongWord; overload;
function  CalcChecksum32(const Buf: RawByteString): LongWord; overload;



{                                                                              }
{ XOR hashing                                                                  }
{                                                                              }
function  CalcXOR8(const Buf; const BufSize: Integer): Byte; overload;
function  CalcXOR8(const Buf: RawByteString): Byte; overload;

function  CalcXOR16(const Buf; const BufSize: Integer): Word; overload;
function  CalcXOR16(const Buf: RawByteString): Word; overload;

function  CalcXOR32(const Buf; const BufSize: Integer): LongWord; overload;
function  CalcXOR32(const Buf: RawByteString): LongWord; overload;



{                                                                              }
{ CRC 16 hashing                                                               }
{                                                                              }
{   The theory behind CCITT V.41 CRCs:                                         }
{                                                                              }
{      1. Select the magnitude of the CRC to be used (typically 16 or 32       }
{         bits) and choose the polynomial to use. In the case of 16 bit        }
{         CRCs, the CCITT polynomial is recommended and is                     }
{                                                                              }
{                       16    12    5                                          }
{               G(x) = x   + x   + x  + 1                                      }
{                                                                              }
{         This polynomial traps 100% of 1 bit, 2 bit, odd numbers of bit       }
{         errors, 100% of <= 16 bit burst errors and over 99% of all           }
{         other errors.                                                        }
{                                                                              }
{      2. The CRC is calculated as                                             }
{                               r                                              }
{               D(x) = (M(x) * 2 )  mod G(x)                                   }
{                                                                              }
{         This may be better described as : Add r bits (0 content) to          }
{         the end of M(x). Divide this by G(x) and the remainder is the        }
{         CRC.                                                                 }
{                                                                              }
{      3. Tag the CRC onto the end of M(x).                                    }
{                                                                              }
{      4. To check it, calculate the CRC of the new message D(x), using        }
{         the same process as in 2. above. The newly calculated CRC            }
{         should be zero.                                                      }
{                                                                              }
{   This effectively means that using CRCs, it is possible to calculate a      }
{   series of bits to tag onto the data which makes the data an exact          }
{   multiple of the polynomial.                                                }
{                                                                              }
procedure CRC16Init(var CRC16: Word);
function  CRC16Byte(const CRC16: Word; const Octet: Byte): Word;
function  CRC16Buf(const CRC16: Word; const Buf; const BufSize: Integer): Word;

function  CalcCRC16(const Buf; const BufSize: Integer): Word; overload;
function  CalcCRC16(const Buf: RawByteString): Word; overload;



{                                                                              }
{ CRC 32 hashing                                                               }
{                                                                              }
procedure SetCRC32Poly(const Poly: LongWord);

procedure CRC32Init(var CRC32: LongWord);
function  CRC32Byte(const CRC32: LongWord; const Octet: Byte): LongWord;
function  CRC32Buf(const CRC32: LongWord; const Buf; const BufSize: Integer): LongWord;
function  CRC32BufNoCase(const CRC32: LongWord; const Buf; const BufSize: Integer): LongWord;

function  CalcCRC32(const Buf; const BufSize: Integer): LongWord; overload;
function  CalcCRC32(const Buf: RawByteString): LongWord; overload;



{                                                                              }
{ Adler 32 hashing                                                             }
{                                                                              }
procedure Adler32Init(var Adler32: LongWord);
function  Adler32Byte(const Adler32: LongWord; const Octet: Byte): LongWord;
function  Adler32Buf(const Adler32: LongWord; const Buf; const BufSize: Integer): LongWord;

function  CalcAdler32(const Buf; const BufSize: Integer): LongWord; overload;
function  CalcAdler32(const Buf: RawByteString): LongWord; overload;



{                                                                              }
{ ELF hashing                                                                  }
{                                                                              }
procedure ELFInit(var Digest: LongWord);
function  ELFBuf(const Digest: LongWord; const Buf; const BufSize: Integer): LongWord;

function  CalcELF(const Buf; const BufSize: Integer): LongWord; overload;
function  CalcELF(const Buf: RawByteString): LongWord; overload;



{                                                                              }
{ ISBN checksum                                                                }
{                                                                              }
function  IsValidISBN(const S: RawByteString): Boolean;



{                                                                              }
{ LUHN checksum                                                                }
{                                                                              }
{   The LUHN forumula (also known as mod-10) is used in major credit card      }
{   account numbers for validity checking.                                     }
{                                                                              }
function  IsValidLUHN(const S: RawByteString): Boolean;



{                                                                              }
{ Knuth hash                                                                   }
{ General purpose string hashing function proposed by Donald E Knuth in        }
{ 'The Art of Computer Programming Vol 3'.                                     }
{                                                                              }
function  KnuthHashA(const S: RawByteString): LongWord;
function  KnuthHashW(const S: WideString): LongWord;



{                                                                              }
{ MD5 hash                                                                     }
{                                                                              }
{   MD5 is an Internet standard secure hashing function, that was              }
{   developed by Professor Ronald L. Rivest in 1991. Subsequently it has       }
{   been placed in the public domain.                                          }
{   MD5 was developed to be more secure after MD4 was 'broken'.                }
{   Den Boer and Bosselaers estimate that if a custom machine were to be       }
{   built specifically to find collisions for MD5 (costing $10m in 1994) it    }
{   would on average take 24 days to find a collision.                         }
{                                                                              }
procedure MD5InitDigest(var Digest: T128BitDigest);
procedure MD5Buf(var Digest: T128BitDigest; const Buf; const BufSize: Integer);
procedure MD5FinalBuf(var Digest: T128BitDigest; const Buf; const BufSize: Integer;
          const TotalSize: Int64);

function  CalcMD5(const Buf; const BufSize: Integer): T128BitDigest; overload;
function  CalcMD5(const Buf: RawByteString): T128BitDigest; overload;

function  MD5DigestToStrA(const Digest: T128BitDigest): RawByteString;
function  MD5DigestToHexA(const Digest: T128BitDigest): RawByteString;
function  MD5DigestToHexW(const Digest: T128BitDigest): WideString;



{                                                                              }
{ SHA1 Hashing                                                                 }
{                                                                              }
{   Specification at http://www.itl.nist.gov/fipspubs/fip180-1.htm             }
{   Also see RFC 3174.                                                         }
{   SHA1 was developed by NIST and is specified in the Secure Hash Standard    }
{   (SHS, FIPS 180) and corrects an unpublished flaw the original SHA          }
{   algorithm.                                                                 }
{   SHA1 produces a 160-bit digest and is considered more secure than MD5.     }
{   SHA1 has a similar design to the MD4-family of hash functions.             }
{                                                                              }
procedure SHA1InitDigest(var Digest: T160BitDigest);
procedure SHA1Buf(var Digest: T160BitDigest; const Buf; const BufSize: Integer);
procedure SHA1FinalBuf(var Digest: T160BitDigest; const Buf; const BufSize: Integer;
          const TotalSize: Int64);

function  CalcSHA1(const Buf; const BufSize: Integer): T160BitDigest; overload;
function  CalcSHA1(const Buf: RawByteString): T160BitDigest; overload;

function  SHA1DigestToStrA(const Digest: T160BitDigest): RawByteString;
function  SHA1DigestToHexA(const Digest: T160BitDigest): RawByteString;
function  SHA1DigestToHexW(const Digest: T160BitDigest): WideString;



{                                                                              }
{ SHA224 Hashing                                                               }
{                                                                              }
{   224 bit SHA-2 hash                                                         }
{   http://en.wikipedia.org/wiki/SHA-2                                         }
{   SHA-224 is based on SHA-256                                                }
{                                                                              }
procedure SHA224InitDigest(var Digest: T256BitDigest);
procedure SHA224Buf(var Digest: T256BitDigest; const Buf; const BufSize: Integer);
procedure SHA224FinalBuf(var Digest: T256BitDigest; const Buf; const BufSize: Integer; const TotalSize: Int64;
          var OutDigest: T224BitDigest);

function  CalcSHA224(const Buf; const BufSize: Integer): T224BitDigest; overload;
function  CalcSHA224(const Buf: RawByteString): T224BitDigest; overload;

function  SHA224DigestToStrA(const Digest: T224BitDigest): RawByteString;
function  SHA224DigestToHexA(const Digest: T224BitDigest): RawByteString;
function  SHA224DigestToHexW(const Digest: T224BitDigest): WideString;



{                                                                              }
{ SHA256 Hashing                                                               }
{   256 bit SHA-2 hash                                                         }
{                                                                              }
procedure SHA256InitDigest(var Digest: T256BitDigest);
procedure SHA256Buf(var Digest: T256BitDigest; const Buf; const BufSize: Integer);
procedure SHA256FinalBuf(var Digest: T256BitDigest; const Buf; const BufSize: Integer; const TotalSize: Int64);

function  CalcSHA256(const Buf; const BufSize: Integer): T256BitDigest; overload;
function  CalcSHA256(const Buf: RawByteString): T256BitDigest; overload;

function  SHA256DigestToStrA(const Digest: T256BitDigest): RawByteString;
function  SHA256DigestToHexA(const Digest: T256BitDigest): RawByteString;
function  SHA256DigestToHexW(const Digest: T256BitDigest): WideString;



{                                                                              }
{ SHA384 Hashing                                                               }
{   384 bit SHA-2 hash                                                         }
{   SHA-384 is based on SHA-512                                                }
{                                                                              }
procedure SHA384InitDigest(var Digest: T512BitDigest);
procedure SHA384Buf(var Digest: T512BitDigest; const Buf; const BufSize: Integer);
procedure SHA384FinalBuf(var Digest: T512BitDigest; const Buf; const BufSize: Integer; const TotalSize: Int64; var OutDigest: T384BitDigest);

function  CalcSHA384(const Buf; const BufSize: Integer): T384BitDigest; overload;
function  CalcSHA384(const Buf: RawByteString): T384BitDigest; overload;

function  SHA384DigestToStrA(const Digest: T384BitDigest): RawByteString;
function  SHA384DigestToHexA(const Digest: T384BitDigest): RawByteString;
function  SHA384DigestToHexW(const Digest: T384BitDigest): WideString;



{                                                                              }
{ SHA512 Hashing                                                               }
{   512 bit SHA-2 hash                                                         }
{                                                                              }
procedure SHA512InitDigest(var Digest: T512BitDigest);
procedure SHA512Buf(var Digest: T512BitDigest; const Buf; const BufSize: Integer);
procedure SHA512FinalBuf(var Digest: T512BitDigest; const Buf; const BufSize: Integer; const TotalSize: Int64);

function  CalcSHA512(const Buf; const BufSize: Integer): T512BitDigest; overload;
function  CalcSHA512(const Buf: RawByteString): T512BitDigest; overload;

function  SHA512DigestToStrA(const Digest: T512BitDigest): RawByteString;
function  SHA512DigestToHexA(const Digest: T512BitDigest): RawByteString;
function  SHA512DigestToHexW(const Digest: T512BitDigest): WideString;



{                                                                              }
{ RIPEMD160                                                                    }
{                                                                              }
{   RIPEMD-160 is a 160-bit cryptographic hash function, designed by           }
{   Hans Dobbertin, Antoon Bosselaers, and Bart Preneel. It is intended to     }
{   be used as a secure replacement for the 128-bit hash functions MD4, MD5,   }
{   and RIPEMD.                                                                }
{   The authors of RIPEMD-160 and RIPEMD-128 do not hold any patents on the    }
{   algorithms (nor on the optional extensions), and are also not aware of     }
{   any patents on these algorithms.                                           }
{                                                                              }
procedure RipeMD160InitDigest(var Digest: T160BitDigest);
procedure RipeMD160Buf(var Digest: T160BitDigest; const Buf; const BufSize: Integer);
procedure RipeMD160FinalBuf(var Digest: T160BitDigest; const Buf; const BufSize: Integer; const TotalSize: Int64);

function  CalcRipeMD160(const Buf; const BufSize: Integer): T160BitDigest; overload;
function  CalcRipeMD160(const Buf: RawByteString): T160BitDigest; overload;

function  RipeMD160DigestToStrA(const Digest: T160BitDigest): RawByteString;
function  RipeMD160DigestToHexA(const Digest: T160BitDigest): RawByteString;
function  RipeMD160DigestToHexW(const Digest: T160BitDigest): WideString;



{                                                                              }
{ HMAC-MD5 keyed hashing                                                       }
{                                                                              }
{   HMAC allows secure keyed hashing (hashing with a password).                }
{   HMAC was designed to meet the requirements of the IPSEC working group in   }
{   the IETF, and is now a standard.                                           }
{   HMAC, are proven to be secure as long as the underlying hash function      }
{   has some reasonable cryptographic strengths.                               }
{   See RFC 2104 for details on HMAC.                                          }
{                                                                              }
procedure HMAC_MD5Init(const Key: Pointer; const KeySize: Integer;
          var Digest: T128BitDigest; var K: T512BitBuf);
procedure HMAC_MD5Buf(var Digest: T128BitDigest; const Buf; const BufSize: Integer);
procedure HMAC_MD5FinalBuf(const K: T512BitBuf; var Digest: T128BitDigest;
          const Buf; const BufSize: Integer; const TotalSize: Int64);

function  CalcHMAC_MD5(const Key: Pointer; const KeySize: Integer;
          const Buf; const BufSize: Integer): T128BitDigest; overload;
function  CalcHMAC_MD5(const Key: RawByteString; const Buf; const BufSize: Integer): T128BitDigest; overload;
function  CalcHMAC_MD5(const Key, Buf: RawByteString): T128BitDigest; overload;



{                                                                              }
{ HMAC-SHA1 keyed hashing                                                      }
{                                                                              }
procedure HMAC_SHA1Init(const Key: Pointer; const KeySize: Integer;
          var Digest: T160BitDigest; var K: T512BitBuf);
procedure HMAC_SHA1Buf(var Digest: T160BitDigest; const Buf; const BufSize: Integer);
procedure HMAC_SHA1FinalBuf(const K: T512BitBuf; var Digest: T160BitDigest;
          const Buf; const BufSize: Integer; const TotalSize: Int64);

function  CalcHMAC_SHA1(const Key: Pointer; const KeySize: Integer;
          const Buf; const BufSize: Integer): T160BitDigest; overload;
function  CalcHMAC_SHA1(const Key: RawByteString; const Buf; const BufSize: Integer): T160BitDigest; overload;
function  CalcHMAC_SHA1(const Key, Buf: RawByteString): T160BitDigest; overload;



{                                                                              }
{ HMAC-SHA256 keyed hashing                                                    }
{                                                                              }
procedure HMAC_SHA256Init(const Key: Pointer; const KeySize: Integer;
          var Digest: T256BitDigest; var K: T512BitBuf);
procedure HMAC_SHA256Buf(var Digest: T256BitDigest; const Buf; const BufSize: Integer);
procedure HMAC_SHA256FinalBuf(const K: T512BitBuf; var Digest: T256BitDigest;
          const Buf; const BufSize: Integer; const TotalSize: Int64);

function  CalcHMAC_SHA256(const Key: Pointer; const KeySize: Integer;
          const Buf; const BufSize: Integer): T256BitDigest; overload;
function  CalcHMAC_SHA256(const Key: RawByteString; const Buf; const BufSize: Integer): T256BitDigest; overload;
function  CalcHMAC_SHA256(const Key, Buf: RawByteString): T256BitDigest; overload;



{                                                                              }
{ HMAC-SHA512 keyed hashing                                                    }
{                                                                              }
procedure HMAC_SHA512Init(const Key: Pointer; const KeySize: Integer; var Digest: T512BitDigest; var K: T1024BitBuf);
procedure HMAC_SHA512Buf(var Digest: T512BitDigest; const Buf; const BufSize: Integer);
procedure HMAC_SHA512FinalBuf(const K: T1024BitBuf; var Digest: T512BitDigest; const Buf; const BufSize: Integer; const TotalSize: Int64);

function  CalcHMAC_SHA512(const Key: Pointer; const KeySize: Integer;
          const Buf; const BufSize: Integer): T512BitDigest; overload;
function  CalcHMAC_SHA512(const Key: RawByteString; const Buf; const BufSize: Integer): T512BitDigest; overload;
function  CalcHMAC_SHA512(const Key, Buf: RawByteString): T512BitDigest; overload;



{                                                                              }
{ Hash class wrappers                                                          }
{                                                                              }
type
  { AHash                                                                      }
  {   Base class for hash classes.                                             }
  AHash = class
  protected
    FDigest    : Pointer;
    FTotalSize : Int64;

    procedure InitHash(const Digest: Pointer; const Key: Pointer; const KeySize: Integer); virtual; abstract;
    procedure ProcessBuf(const Buf; const BufSize: Integer); virtual; abstract;
    procedure ProcessFinalBuf(const Buf; const BufSize: Integer; const TotalSize: Int64); virtual;

  public
    class function DigestSize: Integer; virtual; abstract;
    class function BlockSize: Integer; virtual;

    procedure Init(const Digest: Pointer; const Key: Pointer = nil;
              const KeySize: Integer = 0); overload;
    procedure Init(const Digest: Pointer; const Key: RawByteString = ''); overload;

    procedure HashBuf(const Buf; const BufSize: Integer; const FinalBuf: Boolean);
    procedure HashFile(const FileName: String; const Offset: Int64 = 0;
              const MaxCount: Int64 = -1);
  end;
  THashClass = class of AHash;

  { TChecksum32Hash                                                            }
  TChecksum32Hash = class(AHash)
  protected
    procedure InitHash(const Digest: Pointer; const Key: Pointer; const KeySize: Integer); override;
    procedure ProcessBuf(const Buf; const BufSize: Integer); override;

  public
    class function DigestSize: Integer; override;
  end;

  { TXOR8Hash                                                                  }
  TXOR8Hash = class(AHash)
  protected
    procedure InitHash(const Digest: Pointer; const Key: Pointer; const KeySize: Integer); override;
    procedure ProcessBuf(const Buf; const BufSize: Integer); override;

  public
    class function DigestSize: Integer; override;
  end;

  { TXOR16Hash                                                                 }
  TXOR16Hash = class(AHash)
  protected
    procedure InitHash(const Digest: Pointer; const Key: Pointer; const KeySize: Integer); override;
    procedure ProcessBuf(const Buf; const BufSize: Integer); override;

  public
    class function DigestSize: Integer; override;
  end;

  { TXOR32Hash                                                                 }
  TXOR32Hash = class(AHash)
  protected
    procedure InitHash(const Digest: Pointer; const Key: Pointer; const KeySize: Integer); override;
    procedure ProcessBuf(const Buf; const BufSize: Integer); override;

  public
    class function DigestSize: Integer; override;
  end;

  { TCRC16Hash                                                                 }
  TCRC16Hash = class(AHash)
  protected
    procedure InitHash(const Digest: Pointer; const Key: Pointer; const KeySize: Integer); override;
    procedure ProcessBuf(const Buf; const BufSize: Integer); override;

  public
    class function DigestSize: Integer; override;
  end;

  { TCRC32Hash                                                                 }
  TCRC32Hash = class(AHash)
  protected
    procedure InitHash(const Digest: Pointer; const Key: Pointer; const KeySize: Integer); override;
    procedure ProcessBuf(const Buf; const BufSize: Integer); override;

  public
    class function DigestSize: Integer; override;
  end;

  { TAdler32Hash                                                               }
  TAdler32Hash = class(AHash)
  protected
    procedure InitHash(const Digest: Pointer; const Key: Pointer; const KeySize: Integer); override;
    procedure ProcessBuf(const Buf; const BufSize: Integer); override;

  public
    class function DigestSize: Integer; override;
  end;

  { TELFHash                                                                   }
  TELFHash = class(AHash)
  protected
    procedure InitHash(const Digest: Pointer; const Key: Pointer; const KeySize: Integer); override;
    procedure ProcessBuf(const Buf; const BufSize: Integer); override;

  public
    class function DigestSize: Integer; override;
  end;

  { TMD5Hash                                                                   }
  TMD5Hash = class(AHash)
  protected
    procedure InitHash(const Digest: Pointer; const Key: Pointer; const KeySize: Integer); override;
    procedure ProcessBuf(const Buf; const BufSize: Integer); override;
    procedure ProcessFinalBuf(const Buf; const BufSize: Integer; const TotalSize: Int64); override;

  public
    class function DigestSize: Integer; override;
    class function BlockSize: Integer; override;
  end;

  { TSHA1Hash                                                                  }
  TSHA1Hash = class(AHash)
  protected
    procedure InitHash(const Digest: Pointer; const Key: Pointer; const KeySize: Integer); override;
    procedure ProcessBuf(const Buf; const BufSize: Integer); override;
    procedure ProcessFinalBuf(const Buf; const BufSize: Integer; const TotalSize: Int64); override;

  public
    class function DigestSize: Integer; override;
    class function BlockSize: Integer; override;
  end;

  { TSHA256Hash                                                                }
  TSHA256Hash = class(AHash)
  protected
    procedure InitHash(const Digest: Pointer; const Key: Pointer; const KeySize: Integer); override;
    procedure ProcessBuf(const Buf; const BufSize: Integer); override;
    procedure ProcessFinalBuf(const Buf; const BufSize: Integer; const TotalSize: Int64); override;

  public
    class function DigestSize: Integer; override;
    class function BlockSize: Integer; override;
  end;

  { TSHA512Hash                                                                }
  TSHA512Hash = class(AHash)
  protected
    procedure InitHash(const Digest: Pointer; const Key: Pointer; const KeySize: Integer); override;
    procedure ProcessBuf(const Buf; const BufSize: Integer); override;
    procedure ProcessFinalBuf(const Buf; const BufSize: Integer; const TotalSize: Int64); override;

  public
    class function DigestSize: Integer; override;
    class function BlockSize: Integer; override;
  end;

  { TRipeMD160Hash                                                             }
  TRipeMD160Hash = class(AHash)
  protected
    procedure InitHash(const Digest: Pointer; const Key: Pointer; const KeySize: Integer); override;
    procedure ProcessBuf(const Buf; const BufSize: Integer); override;
    procedure ProcessFinalBuf(const Buf; const BufSize: Integer; const TotalSize: Int64); override;

  public
    class function DigestSize: Integer; override;
    class function BlockSize: Integer; override;
  end;

  { THMAC_MD5Hash                                                              }
  THMAC_MD5Hash = class(AHash)
  protected
    FKey : T512BitBuf;

    procedure InitHash(const Digest: Pointer; const Key: Pointer; const KeySize: Integer); override;
    procedure ProcessBuf(const Buf; const BufSize: Integer); override;
    procedure ProcessFinalBuf(const Buf; const BufSize: Integer; const TotalSize: Int64); override;

  public
    class function DigestSize: Integer; override;
    class function BlockSize: Integer; override;

    destructor Destroy; override;
  end;

  { THMAC_SHA1Hash                                                             }
  THMAC_SHA1Hash = class(AHash)
  protected
    FKey : T512BitBuf;

    procedure InitHash(const Digest: Pointer; const Key: Pointer; const KeySize: Integer); override;
    procedure ProcessBuf(const Buf; const BufSize: Integer); override;
    procedure ProcessFinalBuf(const Buf; const BufSize: Integer; const TotalSize: Int64); override;

  public
    class function DigestSize: Integer; override;
    class function BlockSize: Integer; override;

    destructor Destroy; override;
  end;

  { THMAC_SHA256Hash                                                           }
  THMAC_SHA256Hash = class(AHash)
  protected
    FKey : T512BitBuf;

    procedure InitHash(const Digest: Pointer; const Key: Pointer; const KeySize: Integer); override;
    procedure ProcessBuf(const Buf; const BufSize: Integer); override;
    procedure ProcessFinalBuf(const Buf; const BufSize: Integer; const TotalSize: Int64); override;

  public
    class function DigestSize: Integer; override;
    class function BlockSize: Integer; override;

    destructor Destroy; override;
  end;

  { THMAC_SHA512Hash                                                           }
  THMAC_SHA512Hash = class(AHash)
  protected
    FKey : T1024BitBuf;

    procedure InitHash(const Digest: Pointer; const Key: Pointer; const KeySize: Integer); override;
    procedure ProcessBuf(const Buf; const BufSize: Integer); override;
    procedure ProcessFinalBuf(const Buf; const BufSize: Integer; const TotalSize: Int64); override;

  public
    class function DigestSize: Integer; override;
    class function BlockSize: Integer; override;

    destructor Destroy; override;
  end;



{                                                                              }
{ THashType                                                                    }
{                                                                              }
type
  THashType = (
      hashChecksum32, hashXOR8, hashXOR16, hashXOR32,
      hashCRC16, hashCRC32,
      hashAdler32,
      hashELF,
      hashMD5, hashSHA1, hashSHA256, hashSHA512, hashRipeMD160,
      hashHMAC_MD5, hashHMAC_SHA1, hashHMAC_SHA256, hashHMAC_SHA512);



{                                                                              }
{ GetHashClassByType                                                           }
{                                                                              }
function  GetHashClassByType(const HashType: THashType): THashClass;
function  GetDigestSize(const HashType: THashType): Integer;



{                                                                              }
{ CalculateHash                                                                }
{                                                                              }
procedure CalculateHash(const HashType: THashType;
          const Buf; const BufSize: Integer; const Digest: Pointer;
          const Key: Pointer = nil; const KeySize: Integer = 0); overload;
procedure CalculateHash(const HashType: THashType;
          const Buf; const BufSize: Integer;
          const Digest: Pointer; const Key: RawByteString = ''); overload;
procedure CalculateHash(const HashType: THashType;
          const Buf: RawByteString; const Digest: Pointer;
          const Key: RawByteString = ''); overload;



{                                                                              }
{ HashString                                                                   }
{                                                                              }
{   HashString is a fast general purpose ASCII string hashing function.        }
{   It returns a 32 bit value in the range 0 to Slots - 1. If Slots = 0 then   }
{   the full 32 bit value is returned.                                         }
{   If CaseSensitive = False then HashString will return the same hash value   }
{   regardless of the case of the characters in the string.                    }
{                                                                              }
{   The implementation is based on CRC32. It uses up to 48 characters from     }
{   the string (first 16 characters, last 16 characters and 16 characters      }
{   uniformly sampled from the remaining characters) to calculate the hash     }
{   value.                                                                     }
{                                                                              }
function  HashString(const StrBuf: Pointer; const StrLength: Integer;
          const Slots: LongWord = 0; const CaseSensitive: Boolean = True): LongWord; overload;
function  HashString(const S: RawByteString; const Slots: LongWord = 0;
          const CaseSensitive: Boolean = True): LongWord; overload;



{                                                                              }
{ Self testing code                                                            }
{                                                                              }
{$IFDEF HASH_SELFTEST}
procedure SelfTest;
{$ENDIF}



implementation

uses
  {$IFDEF MSWIN}
  Windows
  {$ENDIF}
  {$IFDEF UNIX}
  {$IFDEF FREEPASCAL}
  BaseUnix,
  Unix
  {$ELSE}
  libc,
  BaseUnix
  {$ENDIF}
  {$ENDIF};



{                                                                              }
{ Hash errors                                                                  }
{                                                                              }
const
  hashErrorMessages : array[0..hashMAX_ERROR] of String = (
      '',
      'Internal error',
      'Invalid hash type',
      'Invalid buffer',
      'Invalid buffer size',
      'Invalid digest',
      'Invalid key',
      'Invalid file name',
      'File open error',
      'File seek error',
      'File read error',
      'Not a keyed hash type',
      'Too many open handles',
      'Invalid handle');

function GetHashErrorMessage(const ErrorCode: LongWord): PChar;
begin
  if (ErrorCode = hashNoError) or (ErrorCode > hashMAX_ERROR) then
    Result := nil
  else
    Result := PChar(hashErrorMessages[ErrorCode]);
end;



{                                                                              }
{ EHashError                                                                   }
{                                                                              }
constructor EHashError.Create(const ErrorCode: LongWord; const Msg: String);
begin
  FErrorCode := ErrorCode;
  if (Msg = '') and (ErrorCode <= hashMAX_ERROR) then
    inherited Create(hashErrorMessages[ErrorCode])
  else
    inherited Create(Msg);
end;



{                                                                              }
{ Secure memory clear                                                          }
{                                                                              }
procedure SecureClear(var Buf; const BufSize: Integer);
begin
  if BufSize <= 0 then
    exit;
  FillChar(Buf, BufSize, #$00);
end;

procedure SecureClear512(var Buf: T512BitBuf);
begin
  SecureClear(Buf, SizeOf(Buf));
end;

procedure SecureClear1024(var Buf: T1024BitBuf);
begin
  SecureClear(Buf, SizeOf(Buf));
end;

procedure SecureClearStr(var S: String);
var L : Integer;
begin
  L := Length(S);
  if L = 0 then
    exit;
  SecureClear(S[1], L * SizeOf(Char));
  S := '';
end;

procedure SecureClearStrA(var S: RawByteString);
var L : Integer;
begin
  L := Length(S);
  if L = 0 then
    exit;
  SecureClear(S[1], L);
  S := '';
end;

procedure SecureClearStrW(var S: WideString);
var L : Integer;
begin
  L := Length(S);
  if L = 0 then
    exit;
  SecureClear(S[1], L * SizeOf(WideChar));
  S := '';
end;



{                                                                              }
{ Checksum hashing                                                             }
{                                                                              }
{$IFDEF ASM386_DELPHI}
function CalcChecksum32(const Buf; const BufSize: Integer): LongWord;
asm
      or eax, eax              // eax = Buf
      jz @fin
      or edx, edx              // edx = BufSize
      jbe @finz
      push esi
      mov esi, eax
      add esi, edx
      xor eax, eax
      xor ecx, ecx
    @l1:
      dec esi
      mov cl, [esi]
      add eax, ecx
      dec edx
      jnz @l1
      pop esi
    @fin:
      ret
    @finz:
      xor eax, eax
end;
{$ELSE}
function CalcChecksum32(const Buf; const BufSize: Integer): LongWord;
var I : Integer;
    P : PByte;
begin
  Result := 0;
  P := @Buf;
  for I := 1 to BufSize do
    begin
      Inc(Result, P^);
      Inc(P);
    end;
end;
{$ENDIF}

function CalcChecksum32(const Buf: RawByteString): LongWord;
begin
  Result := CalcChecksum32(Pointer(Buf)^, Length(Buf));
end;



{                                                                              }
{ XOR hashing                                                                  }
{                                                                              }
{$IFDEF ASM386_DELPHI}
function XOR32Buf(const Buf; const BufSize: Integer): LongWord;
Asm
      or eax, eax
      jz @fin
      or edx, edx
      jz @finz

      push esi
      mov esi, eax
      xor eax, eax

      mov ecx, edx
      shr ecx, 2
      jz @rest

    @l1:
      xor eax, [esi]
      add esi, 4
      dec ecx
      jnz @l1

    @rest:
      and edx, 3
      jz @finp
      xor al, [esi]
      dec edx
      jz @finp
      inc esi
      xor ah, [esi]
      dec edx
      jz @finp
      inc esi
      mov dl, [esi]
      shl edx, 16
      xor eax, edx

    @finp:
      pop esi
      ret
    @finz:
      xor eax, eax
    @fin:
      ret
end;
{$ELSE}
function XOR32Buf(const Buf; const BufSize: Integer): LongWord;
var I : Integer;
    L : Byte;
    P : PAnsiChar;
begin
  Result := 0;
  L := 0;
  P := @Buf;
  for I := 1 to BufSize do
    begin
      Result := Result xor (Byte(P^) shl L);
      Inc(L, 8);
      if L = 32 then
        L := 0;
      Inc(P);
    end;
end;
{$ENDIF}

function CalcXOR8(const Buf; const BufSize: Integer): Byte;
var L : LongWord;
begin
  L := XOR32Buf(Buf, BufSize);
  Result := Byte(L) xor
            Byte(L shr 8) xor
            Byte(L shr 16) xor
            Byte(L shr 24);
end;

function CalcXOR8(const Buf: RawByteString): Byte;
begin
  Result := CalcXOR8(Pointer(Buf)^, Length(Buf));
end;

function CalcXOR16(const Buf; const BufSize: Integer): Word;
var L : LongWord;
begin
  L := XOR32Buf(Buf, BufSize);
  Result := Word(L) xor
            Word(L shr 16);
end;

function CalcXOR16(const Buf: RawByteString): Word;
begin
  Result := CalcXOR16(Pointer(Buf)^, Length(Buf));
end;

function CalcXOR32(const Buf; const BufSize: Integer): LongWord;
begin
  Result := XOR32Buf(Buf, BufSize);
end;

function CalcXOR32(const Buf: RawByteString): LongWord;
begin
  Result := XOR32Buf(Pointer(Buf)^, Length(Buf));
end;



{                                                                              }
{ CRC 16 hashing                                                               }
{                                                                              }
const
  CRC16Table : array[Byte] of Word = (
    $0000, $1021, $2042, $3063, $4084, $50a5, $60c6, $70e7,
    $8108, $9129, $a14a, $b16b, $c18c, $d1ad, $e1ce, $f1ef,
    $1231, $0210, $3273, $2252, $52b5, $4294, $72f7, $62d6,
    $9339, $8318, $b37b, $a35a, $d3bd, $c39c, $f3ff, $e3de,
    $2462, $3443, $0420, $1401, $64e6, $74c7, $44a4, $5485,
    $a56a, $b54b, $8528, $9509, $e5ee, $f5cf, $c5ac, $d58d,
    $3653, $2672, $1611, $0630, $76d7, $66f6, $5695, $46b4,
    $b75b, $a77a, $9719, $8738, $f7df, $e7fe, $d79d, $c7bc,
    $48c4, $58e5, $6886, $78a7, $0840, $1861, $2802, $3823,
    $c9cc, $d9ed, $e98e, $f9af, $8948, $9969, $a90a, $b92b,
    $5af5, $4ad4, $7ab7, $6a96, $1a71, $0a50, $3a33, $2a12,
    $dbfd, $cbdc, $fbbf, $eb9e, $9b79, $8b58, $bb3b, $ab1a,
    $6ca6, $7c87, $4ce4, $5cc5, $2c22, $3c03, $0c60, $1c41,
    $edae, $fd8f, $cdec, $ddcd, $ad2a, $bd0b, $8d68, $9d49,
    $7e97, $6eb6, $5ed5, $4ef4, $3e13, $2e32, $1e51, $0e70,
    $ff9f, $efbe, $dfdd, $cffc, $bf1b, $af3a, $9f59, $8f78,
    $9188, $81a9, $b1ca, $a1eb, $d10c, $c12d, $f14e, $e16f,
    $1080, $00a1, $30c2, $20e3, $5004, $4025, $7046, $6067,
    $83b9, $9398, $a3fb, $b3da, $c33d, $d31c, $e37f, $f35e,
    $02b1, $1290, $22f3, $32d2, $4235, $5214, $6277, $7256,
    $b5ea, $a5cb, $95a8, $8589, $f56e, $e54f, $d52c, $c50d,
    $34e2, $24c3, $14a0, $0481, $7466, $6447, $5424, $4405,
    $a7db, $b7fa, $8799, $97b8, $e75f, $f77e, $c71d, $d73c,
    $26d3, $36f2, $0691, $16b0, $6657, $7676, $4615, $5634,
    $d94c, $c96d, $f90e, $e92f, $99c8, $89e9, $b98a, $a9ab,
    $5844, $4865, $7806, $6827, $18c0, $08e1, $3882, $28a3,
    $cb7d, $db5c, $eb3f, $fb1e, $8bf9, $9bd8, $abbb, $bb9a,
    $4a75, $5a54, $6a37, $7a16, $0af1, $1ad0, $2ab3, $3a92,
    $fd2e, $ed0f, $dd6c, $cd4d, $bdaa, $ad8b, $9de8, $8dc9,
    $7c26, $6c07, $5c64, $4c45, $3ca2, $2c83, $1ce0, $0cc1,
    $ef1f, $ff3e, $cf5d, $df7c, $af9b, $bfba, $8fd9, $9ff8,
    $6e17, $7e36, $4e55, $5e74, $2e93, $3eb2, $0ed1, $1ef0);

function CRC16Byte(const CRC16: Word; const Octet: Byte): Word;
begin
  Result := CRC16Table[Byte(Hi(CRC16) xor Octet)] xor Word(CRC16 shl 8);
end;

function CRC16Buf(const CRC16: Word; const Buf; const BufSize: Integer): Word;
var I : Integer;
    P : PByte;
begin
  Result := CRC16;
  P := @Buf;
  for I := 1 to BufSize do
    begin
      Result := CRC16Byte(Result, P^);
      Inc(P);
    end;
end;

procedure CRC16Init(var CRC16: Word);
begin
  CRC16 := $FFFF;
end;

function CalcCRC16(const Buf; const BufSize: Integer): Word;
begin
  CRC16Init(Result);
  Result := CRC16Buf(Result, Buf, BufSize);
end;

function CalcCRC16(const Buf: RawByteString): Word;
begin
  Result := CalcCRC16(Pointer(Buf)^, Length(Buf));
end;



{                                                                              }
{ CRC 32 hashing                                                               }
{                                                                              }
var
  CRC32TableInit : Boolean = False;
  CRC32Table     : array[Byte] of LongWord;
  CRC32Poly      : LongWord = $EDB88320;

procedure InitCRC32Table;
var I, J : Byte;
    R    : LongWord;
begin
  for I := $00 to $FF do
    begin
      R := I;
      for J := 8 downto 1 do
        if R and 1 <> 0 then
          R := (R shr 1) xor CRC32Poly else
          R := R shr 1;
      CRC32Table[I] := R;
    end;
  CRC32TableInit := True;
end;

procedure SetCRC32Poly(const Poly: LongWord);
begin
  CRC32Poly := Poly;
  CRC32TableInit := False;
end;

function CalcCRC32Byte(const CRC32: LongWord; const Octet: Byte): LongWord; {$IFDEF UseInline}inline;{$ENDIF}
begin
  Result := CRC32Table[Byte(CRC32) xor Octet] xor ((CRC32 shr 8) and $00FFFFFF);
end;

function CRC32Byte(const CRC32: LongWord; const Octet: Byte): LongWord;
begin
  if not CRC32TableInit then
    InitCRC32Table;
  Result := CalcCRC32Byte(CRC32, Octet);
end;

function CRC32Buf(const CRC32: LongWord; const Buf; const BufSize: Integer): LongWord;
var P : PByte;
    I : Integer;
begin
  if not CRC32TableInit then
    InitCRC32Table;
  P := @Buf;
  Result := CRC32;
  for I := 1 to BufSize do
    begin
      Result := CalcCRC32Byte(Result, P^);
      Inc(P);
    end;
end;

function CRC32BufNoCase(const CRC32: LongWord; const Buf; const BufSize: Integer): LongWord;
var P : PByte;
    I : Integer;
    C : Byte;
begin
  if not CRC32TableInit then
    InitCRC32Table;
  P := @Buf;
  Result := CRC32;
  for I := 1 to BufSize do
    begin
      C := P^;
      if AnsiChar(C) in ['A'..'Z'] then
        C := C or 32;
      Result := CalcCRC32Byte(Result, C);
      Inc(P);
    end;
end;

procedure CRC32Init(var CRC32: LongWord);
begin
  CRC32 := $FFFFFFFF;
end;

function CalcCRC32(const Buf; const BufSize: Integer): LongWord;
begin
  CRC32Init(Result);
  Result := not CRC32Buf(Result, Buf, BufSize);
end;

function CalcCRC32(const Buf: RawByteString): LongWord;
begin
  Result := CalcCRC32(Pointer(Buf)^, Length(Buf));
end;



{                                                                              }
{ Adler 32 hashing                                                             }
{                                                                              }
procedure Adler32Init(var Adler32: LongWord);
begin
  Adler32 := $00000001;
end;

const
  Adler32Mod = 65521; // largest prime smaller than 65536

function Adler32Byte(const Adler32: LongWord; const Octet: Byte): LongWord;
var A, B : LongWord;
begin
  A := Adler32 and $0000FFFF;
  B := Adler32 shr 16;
  Inc(A, Octet);
  Inc(B, A);
  if A >= Adler32Mod then
    Dec(A, Adler32Mod);
  if B >= Adler32Mod then
    Dec(B, Adler32Mod);
  Result := A or (B shl 16);
end;

function Adler32Buf(const Adler32: LongWord; const Buf; const BufSize: Integer): LongWord;
var A, B : LongWord;
    P    : PByte;
    I    : Integer;
begin
  A := Adler32 and $0000FFFF;
  B := Adler32 shr 16;
  P := @Buf;
  for I := 1 to BufSize do
  begin
    Inc(A, P^);
    Inc(B, A);
    if A >= Adler32Mod then
      Dec(A, Adler32Mod);
    if B >= Adler32Mod then
      Dec(B, Adler32Mod);
    Inc(P);
  end;
  Result := A or (B shl 16);
end;

function CalcAdler32(const Buf; const BufSize: Integer): LongWord;
begin
  Adler32Init(Result);
  Result := Adler32Buf(Result, Buf, BufSize);
end;

function CalcAdler32(const Buf: RawByteString): LongWord;
begin
  Result := CalcAdler32(Pointer(Buf)^, Length(Buf));
end;



{                                                                              }
{ ELF hashing                                                                  }
{                                                                              }
procedure ELFInit(var Digest: LongWord);
begin
  Digest := 0;
end;

function ELFBuf(const Digest: LongWord; const Buf; const BufSize: Integer): LongWord;
var I : Integer;
    P : PByte;
    X : LongWord;
begin
  Result := Digest;
  P := @Buf;
  for I := 1 to BufSize do
    begin
      Result := (Result shl 4) + P^;
      Inc(P);
      X := Result and $F0000000;
      if X <> 0 then
        Result := Result xor (X shr 24);
      Result := Result and (not X);
    end;
end;

function CalcELF(const Buf; const BufSize: Integer): LongWord;
begin
  Result := ELFBuf(0, Buf, BufSize);
end;

function CalcELF(const Buf: RawByteString): LongWord;
begin
  Result := CalcELF(Pointer(Buf)^, Length(Buf));
end;



{                                                                              }
{ ISBN checksum                                                                }
{                                                                              }
function IsValidISBN(const S: RawByteString): Boolean;
var I, L, M, D, C : Integer;
    P : PAnsiChar;
begin
  L := Length(S);
  if L < 10 then // too few digits
    begin
      Result := False;
      exit;
    end;
  M := 10;
  C := 0;
  P := Pointer(S);
  for I := 1 to L do
    begin
      if (P^ in ['0'..'9']) or ((M = 1) and (P^ in ['x', 'X'])) then
        begin
          if M = 0 then // too many digits
            begin
              Result := False;
              exit;
            end;
          if P^ in ['x', 'X'] then
            D := 10 else
            D := Ord(P^) - Ord('0');
          Inc(C, M * D);
          Dec(M);
        end;
      Inc(P);
    end;
  if M > 0 then // too few digits
    begin
      Result := False;
      exit;
    end;
  Result := C mod 11 = 0;
end;



{                                                                              }
{ LUHN checksum                                                                }
{                                                                              }
function IsValidLUHN(const S: RawByteString): Boolean;
var P : PAnsiChar;
    I, L, M, C, D : Integer;
    R : Boolean;
begin
  L := Length(S);
  if L = 0 then
    begin
      Result := False;
      exit;
    end;
  P := Pointer(S);
  Inc(P, L - 1);
  C := 0;
  M := 0;
  R := False;
  for I := 1 to L do
    begin
      if P^ in ['0'..'9'] then
        begin
          D := Ord(P^) - Ord('0');
          if R then
            begin
              D := D * 2;
              D := (D div 10) + (D mod 10);
            end;
          Inc(C, D);
          Inc(M);
          R := not R;
        end;
      Dec(P);
    end;
  Result := (M >= 1) and (C mod 10 = 0);
end;



{                                                                              }
{ Knuth Hash                                                                   }
{                                                                              }
function KnuthHashA(const S: RawByteString): LongWord;
var
  I, L : Integer;
  H : LongWord;
begin
  L := Length(S);
  H := L;
  for I := 1 to L do
    H := ((H shr 5) xor (H shl 27)) xor Ord(S[I]);
  Result := H;
end;

function KnuthHashW(const S: WideString): LongWord;
var
  I, L : Integer;
  H : LongWord;
begin
  L := Length(S);
  H := L;
  for I := 1 to L do
    H := ((H shr 5) xor (H shl 27)) xor Ord(S[I]);
  Result := H;
end;



{                                                                              }
{ Digests                                                                      }
{                                                                              }
const
  s_HexDigitsLower : String[16] = '0123456789abcdef';

procedure DigestToHexBufA(const Digest; const Size: Integer; const Buf);
var I : Integer;
    P : PAnsiChar;
    Q : PByte;
begin
  P := @Buf;;
  Assert(Assigned(P));
  Q := @Digest;
  Assert(Assigned(Q));
  for I := 0 to Size - 1 do
    begin
      P^ := s_HexDigitsLower[Q^ shr 4 + 1];
      Inc(P);
      P^ := s_HexDigitsLower[Q^ and 15 + 1];
      Inc(P);
      Inc(Q);
    end;
end;

procedure DigestToHexBufW(const Digest; const Size: Integer; const Buf);
var I : Integer;
    P : PWideChar;
    Q : PByte;
begin
  P := @Buf;;
  Assert(Assigned(P));
  Q := @Digest;
  Assert(Assigned(Q));
  for I := 0 to Size - 1 do
    begin
      P^ := WideChar(s_HexDigitsLower[Q^ shr 4 + 1]);
      Inc(P);
      P^ := WideChar(s_HexDigitsLower[Q^ and 15 + 1]);
      Inc(P);
      Inc(Q);
    end;
end;

function DigestToHexA(const Digest; const Size: Integer): RawByteString;
begin
  SetLength(Result, Size * 2);
  DigestToHexBufA(Digest, Size, Pointer(Result)^);
end;

function DigestToHexW(const Digest; const Size: Integer): WideString;
begin
  SetLength(Result, Size * 2);
  DigestToHexBufW(Digest, Size, Pointer(Result)^);
end;

function Digest128Equal(const Digest1, Digest2: T128BitDigest): Boolean;
var I : Integer;
begin
  for I := 0 to 3 do
    if Digest1.Longs[I] <> Digest2.Longs[I] then
      begin
        Result := False;
        exit;
      end;
  Result := True;
end;

function Digest160Equal(const Digest1, Digest2: T160BitDigest): Boolean;
var I : Integer;
begin
  for I := 0 to 4 do
    if Digest1.Longs[I] <> Digest2.Longs[I] then
      begin
        Result := False;
        exit;
      end;
  Result := True;
end;

function Digest224Equal(const Digest1, Digest2: T224BitDigest): Boolean;
var I : Integer;
begin
  for I := 0 to 6 do
    if Digest1.Longs[I] <> Digest2.Longs[I] then
      begin
        Result := False;
        exit;
      end;
  Result := True;
end;

function Digest256Equal(const Digest1, Digest2: T256BitDigest): Boolean;
var I : Integer;
begin
  for I := 0 to 7 do
    if Digest1.Longs[I] <> Digest2.Longs[I] then
      begin
        Result := False;
        exit;
      end;
  Result := True;
end;

function Digest384Equal(const Digest1, Digest2: T384BitDigest): Boolean;
var I : Integer;
begin
  for I := 0 to 11 do
    if Digest1.Longs[I] <> Digest2.Longs[I] then
      begin
        Result := False;
        exit;
      end;
  Result := True;
end;

function Digest512Equal(const Digest1, Digest2: T512BitDigest): Boolean;
var I : Integer;
begin
  for I := 0 to 15 do
    if Digest1.Longs[I] <> Digest2.Longs[I] then
      begin
        Result := False;
        exit;
      end;
  Result := True;
end;

procedure Digest512XOR8(var Digest: T512BitDigest; const A: Byte);
var I : Integer;
begin
  for I := 0 to 63 do
    Digest.Bytes[I] := Digest.Bytes[I] xor A;
end;

procedure Digest512XOR32(var Digest: T512BitDigest; const A: LongWord);
var I : Integer;
begin
  for I := 0 to 15 do
    Digest.Longs[I] := Digest.Longs[I] xor A;
end;



{                                                                              }
{ ReverseMem                                                                   }
{ Utility function to reverse order of data in buffer.                         }
{                                                                              }
procedure ReverseMem(var Buf; const BufSize: Integer);
var I : Integer;
    P : PByte;
    Q : PByte;
    T : Byte;
begin
  P := @Buf;
  Q := P;
  Inc(Q, BufSize - 1);
  for I := 1 to BufSize div 2 do
    begin
      T := P^;
      P^ := Q^;
      Q^ := T;
      Inc(P);
      Dec(Q);
    end;
end;



{                                                                              }
{ StdFinalBuf                                                                  }
{ Utility function to prepare final buffer(s).                                 }
{ Fills Buf1 and potentially Buf2 from Buf (FinalBufCount = 1 or 2).           }
{ Used by MD5, SHA1, SHA256, SHA512.                                           }
{                                                                              }
procedure StdFinalBuf512(
          const Buf; const BufSize: Integer; const TotalSize: Int64;
          var Buf1, Buf2: T512BitBuf;
          var FinalBufs: Integer;
          const SwapEndian: Boolean);
var P, Q : PByte;
    I : Integer;
    L : Int64;
begin
  Assert(BufSize < 64, 'Final BufSize must be less than 64 bytes');
  Assert(TotalSize >= BufSize, 'TotalSize >= BufSize');

  P := @Buf;
  Q := @Buf1[0];
  if BufSize > 0 then
    begin
      Move(P^, Q^, BufSize);
      Inc(Q, BufSize);
    end;
  Q^ := $80;
  Inc(Q);

  {$IFDEF DELPHI5}
  // Delphi 5 sometimes reports fatal error (internal error C1093) when compiling:
  //   L := TotalSize * 8
  L := TotalSize;
  L := L * 8;
  {$ELSE}
  L := TotalSize * 8;
  {$ENDIF}
  if SwapEndian then
    ReverseMem(L, 8);
  if BufSize + 1 > 64 - Sizeof(Int64) then
    begin
      FillChar(Q^, 64 - BufSize - 1, #0);
      Q := @Buf2[0];
      FillChar(Q^, 64 - Sizeof(Int64), #0);
      Inc(Q, 64 - Sizeof(Int64));
      PInt64(Q)^ := L;
      FinalBufs := 2;
    end
  else
    begin
      I := 64 - Sizeof(Int64) - BufSize - 1;
      FillChar(Q^, I, #0);
      Inc(Q, I);
      PInt64(Q)^ := L;
      FinalBufs := 1;
    end;
end;

procedure StdFinalBuf1024(
          const Buf; const BufSize: Integer; const TotalSize: Int64;
          var Buf1, Buf2: T1024BitBuf;
          var FinalBufs: Integer;
          const SwapEndian: Boolean);
var P, Q : PByte;
    I : Integer;
    L : Int64;
begin
  Assert(BufSize < 128, 'Final BufSize must be less than 128 bytes');
  Assert(TotalSize >= BufSize, 'TotalSize >= BufSize');

  P := @Buf;
  Q := @Buf1[0];
  if BufSize > 0 then
    begin
      Move(P^, Q^, BufSize);
      Inc(Q, BufSize);
    end;
  Q^ := $80;
  Inc(Q);

  {$IFDEF DELPHI5}
  // Delphi 5 sometimes reports fatal error (internal error C1093) when compiling:
  //   L := TotalSize * 8
  L := TotalSize;
  L := L * 8;
  {$ELSE}
  L := TotalSize * 8;
  {$ENDIF}
  if SwapEndian then
    ReverseMem(L, 8);
  if BufSize + 1 > 128 - Sizeof(Int64) * 2 then
    begin
      FillChar(Q^, 128 - BufSize - 1, #0);
      Q := @Buf2[0];
      FillChar(Q^, 128 - Sizeof(Int64) * 2, #0);
      Inc(Q, 128 - Sizeof(Int64) * 2);
      PInt64(Q)^ := 0;
      Inc(Q, 8);
      PInt64(Q)^ := L;
      FinalBufs := 2;
    end
  else
    begin
      I := 128 - Sizeof(Int64) * 2 - BufSize - 1;
      FillChar(Q^, I, #0);
      Inc(Q, I);
      PInt64(Q)^ := 0;
      Inc(Q, 8);
      PInt64(Q)^ := L;
      FinalBufs := 1;
    end;
end;

{                                                                              }
{ Utility functions SwapEndian, RotateLeftBits, RotateRightBits.               }
{ Used by SHA1 and SHA256.                                                     }
{                                                                              }
{$IFDEF ASM386}
function SwapEndian(const Value: LongWord): LongWord; register; assembler;
asm
      XCHG    AH, AL
      ROL     EAX, 16
      XCHG    AH, AL
end;
{$ELSE}
function SwapEndian(const Value: LongWord): LongWord;
begin
  Result := ((Value and $000000FF) shl 24)  or
            ((Value and $0000FF00) shl 8)   or
            ((Value and $00FF0000) shr 8)   or
            ((Value and $FF000000) shr 24);
end;
{$ENDIF}

procedure SwapEndianBuf(var Buf; const Count: Integer);
var P : PLongWord;
    I : Integer;
begin
  P := @Buf;
  for I := 1 to Count do
    begin
      P^ := SwapEndian(P^);
      Inc(P);
    end;
end;

{$IFDEF ASM386_DELPHI}
function RotateLeftBits(const Value: LongWord; const Bits: Byte): LongWord;
asm
      MOV     CL, DL
      ROL     EAX, CL
end;
{$ELSE}
function RotateLeftBits(const Value: LongWord; const Bits: Byte): LongWord;
var I : Integer;
    R : LongWord;
begin
  R := Value;
  for I := 1 to Bits do
    if R and $80000000 = 0 then
      R := LongWord(R shl 1)
    else
      R := LongWord(R shl 1) or 1;
  Result := R;
end;
{$ENDIF}

{$IFDEF ASM386_DELPHI}
function RotateRightBits(const Value: LongWord; const Bits: Byte): LongWord;
asm
      MOV     CL, DL
      ROR     EAX, CL
end;
{$ELSE}
function RotateRightBits(const Value: LongWord; const Bits: Byte): LongWord;
var I, B : Integer;
begin
  Result := Value;
  if Bits >= 32 then
    B := Bits mod 32
  else
    B := Bits;
  for I := 1 to B do
    if Result and 1 = 0 then
      Result := Result shr 1
    else
      Result := (Result shr 1) or $80000000;
end;
{$ENDIF}



{                                                                              }
{ Utility functions for Word64 arithmetic                                      }
{ Used by SHA-512                                                              }
{                                                                              }
procedure Word64InitZero(var A: Word64);
begin
  A.LongWords[0] := 0;
  A.LongWords[1] := 0;
end;

procedure Word64Not(var A: Word64);
begin
  A.LongWords[0] := not A.LongWords[0];
  A.LongWords[1] := not A.LongWords[1];
end;

procedure Word64AndWord64(var A: Word64; const B: Word64);
begin
  A.LongWords[0] := A.LongWords[0] and B.LongWords[0];
  A.LongWords[1] := A.LongWords[1] and B.LongWords[1];
end;

procedure Word64XorWord64(var A: Word64; const B: Word64);
begin
  A.LongWords[0] := A.LongWords[0] xor B.LongWords[0];
  A.LongWords[1] := A.LongWords[1] xor B.LongWords[1];
end;

procedure Word64AddWord64(var A: Word64; const B: Word64);
var C, D : Int64;
begin
  C := Int64(A.LongWords[0]) + B.LongWords[0];
  D := Int64(A.LongWords[1]) + B.LongWords[1];
  if C >= $100000000 then
    Inc(D);
  A.LongWords[0] := C and $FFFFFFFF;
  A.LongWords[1] := D and $FFFFFFFF;
end;

procedure Word64Shr(var A: Word64; const B: Byte);
var C : Byte;
begin
  if B = 0 then
    exit;
  if B >= 64 then
    Word64InitZero(A) else
  if B < 32 then
    begin
      C := 32 - B;
      A.LongWords[0] := (A.LongWords[0] shr B) or (A.LongWords[1] shl C);
      A.LongWords[1] := A.LongWords[1] shr B;
    end
  else
    begin
      C := B - 32;
      A.LongWords[0] := A.LongWords[1] shr C;
      A.LongWords[1] := 0;
    end;
end;

procedure Word64Ror(var A: Word64; const B: Byte);
var C, D : Byte;
    E, F : LongWord;
begin
  C := B mod 64;
  if C = 0 then
    exit;
  if C < 32 then
    begin
      D := 32 - C;
      E := (A.LongWords[1] shr C) or (A.LongWords[0] shl D);
      F := (A.LongWords[0] shr C) or (A.LongWords[1] shl D);
    end
  else
    begin
      Dec(C, 32);
      D := 32 - C;
      E := (A.LongWords[0] shr C) or (A.LongWords[1] shl D);
      F := (A.LongWords[1] shr C) or (A.LongWords[0] shl D);
    end;
  A.LongWords[1] := E;
  A.LongWords[0] := F;
end;

procedure Word64SwapEndian(var A: Word64);
var B : Word64;
    I : Integer;
begin
  B := A;
  for I := 0 to 7 do
    A.Bytes[I] := B.Bytes[7 - I];
end;

procedure SwapEndianBuf64(var Buf; const Count: Integer);
var P : PWord64;
    I : Integer;
begin
  P := @Buf;
  for I := 1 to Count do
    begin
      Word64SwapEndian(P^);
      Inc(P);
    end;
end;



{                                                                              }
{ MD5 hashing                                                                  }
{                                                                              }
const
  MD5Table_1 : array[0..15] of LongWord = (
      $D76AA478, $E8C7B756, $242070DB, $C1BDCEEE,
      $F57C0FAF, $4787C62A, $A8304613, $FD469501,
      $698098D8, $8B44F7AF, $FFFF5BB1, $895CD7BE,
      $6B901122, $FD987193, $A679438E, $49B40821);
  MD5Table_2 : array[0..15] of LongWord = (
      $F61E2562, $C040B340, $265E5A51, $E9B6C7AA,
      $D62F105D, $02441453, $D8A1E681, $E7D3FBC8,
      $21E1CDE6, $C33707D6, $F4D50D87, $455A14ED,
      $A9E3E905, $FCEFA3F8, $676F02D9, $8D2A4C8A);
  MD5Table_3 : array[0..15] of LongWord = (
      $FFFA3942, $8771F681, $6D9D6122, $FDE5380C,
      $A4BEEA44, $4BDECFA9, $F6BB4B60, $BEBFBC70,
      $289B7EC6, $EAA127FA, $D4EF3085, $04881D05,
      $D9D4D039, $E6DB99E5, $1FA27CF8, $C4AC5665);
  MD5Table_4 : array[0..15] of LongWord = (
      $F4292244, $432AFF97, $AB9423A7, $FC93A039,
      $655B59C3, $8F0CCC92, $FFEFF47D, $85845DD1,
      $6FA87E4F, $FE2CE6E0, $A3014314, $4E0811A1,
      $F7537E82, $BD3AF235, $2AD7D2BB, $EB86D391);

{ Calculates a MD5 Digest (16 bytes) given a Buffer (64 bytes)                 }
{$IFOPT Q+}{$DEFINE QOn}{$Q-}{$ELSE}{$UNDEF QOn}{$ENDIF}
procedure TransformMD5Buffer(var Digest: T128BitDigest; const Buffer);
var A, B, C, D : LongWord;
    P          : PLongWord;
    I          : Integer;
    J          : Byte;
    Buf        : array[0..15] of LongWord absolute Buffer;
begin
  A := Digest.Longs[0];
  B := Digest.Longs[1];
  C := Digest.Longs[2];
  D := Digest.Longs[3];

  P := @MD5Table_1;
  for I := 0 to 3 do
    begin
      J := I * 4;
      Inc(A, Buf[J]     + P^ + (D xor (B and (C xor D)))); A := A shl  7 or A shr 25 + B; Inc(P);
      Inc(D, Buf[J + 1] + P^ + (C xor (A and (B xor C)))); D := D shl 12 or D shr 20 + A; Inc(P);
      Inc(C, Buf[J + 2] + P^ + (B xor (D and (A xor B)))); C := C shl 17 or C shr 15 + D; Inc(P);
      Inc(B, Buf[J + 3] + P^ + (A xor (C and (D xor A)))); B := B shl 22 or B shr 10 + C; Inc(P);
    end;

  P := @MD5Table_2;
  for I := 0 to 3 do
    begin
      J := I * 4;
      Inc(A, Buf[J + 1]           + P^ + (C xor (D and (B xor C)))); A := A shl  5 or A shr 27 + B; Inc(P);
      Inc(D, Buf[(J + 6) mod 16]  + P^ + (B xor (C and (A xor B)))); D := D shl  9 or D shr 23 + A; Inc(P);
      Inc(C, Buf[(J + 11) mod 16] + P^ + (A xor (B and (D xor A)))); C := C shl 14 or C shr 18 + D; Inc(P);
      Inc(B, Buf[J]               + P^ + (D xor (A and (C xor D)))); B := B shl 20 or B shr 12 + C; Inc(P);
    end;

  P := @MD5Table_3;
  for I := 0 to 3 do
    begin
      J := 16 - (I * 4);
      Inc(A, Buf[(J + 5) mod 16]  + P^ + (B xor C xor D)); A := A shl  4 or A shr 28 + B; Inc(P);
      Inc(D, Buf[(J + 8) mod 16]  + P^ + (A xor B xor C)); D := D shl 11 or D shr 21 + A; Inc(P);
      Inc(C, Buf[(J + 11) mod 16] + P^ + (D xor A xor B)); C := C shl 16 or C shr 16 + D; Inc(P);
      Inc(B, Buf[(J + 14) mod 16] + P^ + (C xor D xor A)); B := B shl 23 or B shr  9 + C; Inc(P);
    end;

  P := @MD5Table_4;
  for I := 0 to 3 do
    begin
      J := 16 - (I * 4);
      Inc(A, Buf[J mod 16]        + P^ + (C xor (B or not D))); A := A shl  6 or A shr 26 + B; Inc(P);
      Inc(D, Buf[(J + 7) mod 16]  + P^ + (B xor (A or not C))); D := D shl 10 or D shr 22 + A; Inc(P);
      Inc(C, Buf[(J + 14) mod 16] + P^ + (A xor (D or not B))); C := C shl 15 or C shr 17 + D; Inc(P);
      Inc(B, Buf[(J + 5) mod 16]  + P^ + (D xor (C or not A))); B := B shl 21 or B shr 11 + C; Inc(P);
    end;

  Inc(Digest.Longs[0], A);
  Inc(Digest.Longs[1], B);
  Inc(Digest.Longs[2], C);
  Inc(Digest.Longs[3], D);
end;
{$IFDEF QOn}{$Q+}{$ENDIF}

procedure MD5InitDigest(var Digest: T128BitDigest);
begin
  Digest.Longs[0] := $67452301;
  Digest.Longs[1] := $EFCDAB89;
  Digest.Longs[2] := $98BADCFE;
  Digest.Longs[3] := $10325476;
end;

procedure MD5Buf(var Digest: T128BitDigest; const Buf; const BufSize: Integer);
var P : PByte;
    I, J : Integer;
begin
  I := BufSize;
  if I <= 0 then
    exit;
  Assert(I mod 64 = 0, 'BufSize must be multiple of 64 bytes');
  P := @Buf;
  for J := 0 to I div 64 - 1 do
    begin
      TransformMD5Buffer(Digest, P^);
      Inc(P, 64);
    end;
end;

procedure MD5FinalBuf(var Digest: T128BitDigest; const Buf; const BufSize: Integer; const TotalSize: Int64);
var B1, B2 : T512BitBuf;
    C : Integer;
begin
  StdFinalBuf512(Buf, BufSize, TotalSize, B1, B2, C, False);
  TransformMD5Buffer(Digest, B1);
  if C > 1 then
    TransformMD5Buffer(Digest, B2);
  SecureClear512(B1);
  if C > 1 then
    SecureClear512(B2);
end;

function CalcMD5(const Buf; const BufSize: Integer): T128BitDigest;
var I, J : Integer;
    P    : PByte;
begin
  MD5InitDigest(Result);
  P := @Buf;
  if BufSize <= 0 then
    I := 0 else
    I := BufSize;
  J := (I div 64) * 64;
  if J > 0 then
    begin
      MD5Buf(Result, P^, J);
      Inc(P, J);
      Dec(I, J);
    end;
  MD5FinalBuf(Result, P^, I, BufSize);
end;

function CalcMD5(const Buf: RawByteString): T128BitDigest;
begin
  Result := CalcMD5(Pointer(Buf)^, Length(Buf));
end;

function MD5DigestToStrA(const Digest: T128BitDigest): RawByteString;
begin
  SetLength(Result, Sizeof(Digest));
  Move(Digest, Pointer(Result)^, Sizeof(Digest));
end;

function MD5DigestToHexA(const Digest: T128BitDigest): RawByteString;
begin
  Result := DigestToHexA(Digest, Sizeof(Digest));
end;

function MD5DigestToHexW(const Digest: T128BitDigest): WideString;
begin
  Result := DigestToHexW(Digest, Sizeof(Digest));
end;



{                                                                              }
{ SHA hashing                                                                  }
{                                                                              }
procedure SHA1InitDigest(var Digest: T160BitDigest);
begin
  Digest.Longs[0] := $67452301;
  Digest.Longs[1] := $EFCDAB89;
  Digest.Longs[2] := $98BADCFE;
  Digest.Longs[3] := $10325476;
  Digest.Longs[4] := $C3D2E1F0;
end;

{ Calculates a SHA Digest (20 bytes) given a Buffer (64 bytes)                 }
{$IFOPT Q+}{$DEFINE QOn}{$Q-}{$ELSE}{$UNDEF QOn}{$ENDIF}
procedure TransformSHABuffer(var Digest: T160BitDigest; const Buffer; const SHA1: Boolean);
var A, B, C, D, E : LongWord;
    W : array[0..79] of LongWord;
    P, Q : PLongWord;
    I : Integer;
    J : LongWord;
begin
  P := @Buffer;
  Q := @W;
  for I := 0 to 15 do
    begin
      Q^ := SwapEndian(P^);
      Inc(P);
      Inc(Q);
    end;
  for I := 0 to 63 do
    begin
      P := Q;
      Dec(P, 16);
      J := P^;
      Inc(P, 2);
      J := J xor P^;
      Inc(P, 6);
      J := J xor P^;
      Inc(P, 5);
      J := J xor P^;
      if SHA1 then
        J := RotateLeftBits(J, 1);
      Q^ := J;
      Inc(Q);
    end;

  A := Digest.Longs[0];
  B := Digest.Longs[1];
  C := Digest.Longs[2];
  D := Digest.Longs[3];
  E := Digest.Longs[4];

  P := @W;
  for I := 0 to 3 do
    begin
      Inc(E, (A shl 5 or A shr 27) + (D xor (B and (C xor D))) + P^ + $5A827999); B := B shr 2 or B shl 30; Inc(P);
      Inc(D, (E shl 5 or E shr 27) + (C xor (A and (B xor C))) + P^ + $5A827999); A := A shr 2 or A shl 30; Inc(P);
      Inc(C, (D shl 5 or D shr 27) + (B xor (E and (A xor B))) + P^ + $5A827999); E := E shr 2 or E shl 30; Inc(P);
      Inc(B, (C shl 5 or C shr 27) + (A xor (D and (E xor A))) + P^ + $5A827999); D := D shr 2 or D shl 30; Inc(P);
      Inc(A, (B shl 5 or B shr 27) + (E xor (C and (D xor E))) + P^ + $5A827999); C := C shr 2 or C shl 30; Inc(P);
    end;

  for I := 0 to 3 do
    begin
      Inc(E, (A shl 5 or A shr 27) + (D xor B xor C) + P^ + $6ED9EBA1); B := B shr 2 or B shl 30; Inc(P);
      Inc(D, (E shl 5 or E shr 27) + (C xor A xor B) + P^ + $6ED9EBA1); A := A shr 2 or A shl 30; Inc(P);
      Inc(C, (D shl 5 or D shr 27) + (B xor E xor A) + P^ + $6ED9EBA1); E := E shr 2 or E shl 30; Inc(P);
      Inc(B, (C shl 5 or C shr 27) + (A xor D xor E) + P^ + $6ED9EBA1); D := D shr 2 or D shl 30; Inc(P);
      Inc(A, (B shl 5 or B shr 27) + (E xor C xor D) + P^ + $6ED9EBA1); C := C shr 2 or C shl 30; Inc(P);
    end;

  for I := 0 to 3 do
    begin
      Inc(E, (A shl 5 or A shr 27) + ((B and C) or (D and (B or C))) + P^ + $8F1BBCDC); B := B shr 2 or B shl 30; Inc(P);
      Inc(D, (E shl 5 or E shr 27) + ((A and B) or (C and (A or B))) + P^ + $8F1BBCDC); A := A shr 2 or A shl 30; Inc(P);
      Inc(C, (D shl 5 or D shr 27) + ((E and A) or (B and (E or A))) + P^ + $8F1BBCDC); E := E shr 2 or E shl 30; Inc(P);
      Inc(B, (C shl 5 or C shr 27) + ((D and E) or (A and (D or E))) + P^ + $8F1BBCDC); D := D shr 2 or D shl 30; Inc(P);
      Inc(A, (B shl 5 or B shr 27) + ((C and D) or (E and (C or D))) + P^ + $8F1BBCDC); C := C shr 2 or C shl 30; Inc(P);
    end;

  for I := 0 to 3 do
    begin
      Inc(E, (A shl 5 or A shr 27) + (D xor B xor C) + P^ + $CA62C1D6); B := B shr 2 or B shl 30; Inc(P);
      Inc(D, (E shl 5 or E shr 27) + (C xor A xor B) + P^ + $CA62C1D6); A := A shr 2 or A shl 30; Inc(P);
      Inc(C, (D shl 5 or D shr 27) + (B xor E xor A) + P^ + $CA62C1D6); E := E shr 2 or E shl 30; Inc(P);
      Inc(B, (C shl 5 or C shr 27) + (A xor D xor E) + P^ + $CA62C1D6); D := D shr 2 or D shl 30; Inc(P);
      Inc(A, (B shl 5 or B shr 27) + (E xor C xor D) + P^ + $CA62C1D6); C := C shr 2 or C shl 30; Inc(P);
    end;

  Inc(Digest.Longs[0], A);
  Inc(Digest.Longs[1], B);
  Inc(Digest.Longs[2], C);
  Inc(Digest.Longs[3], D);
  Inc(Digest.Longs[4], E);
end;
{$IFDEF QOn}{$Q+}{$ENDIF}

procedure SHA1Buf(var Digest: T160BitDigest; const Buf; const BufSize: Integer);
var P : PByte;
    I, J : Integer;
begin
  I := BufSize;
  if I <= 0 then
    exit;
  Assert(I mod 64 = 0, 'BufSize must be multiple of 64 bytes');
  P := @Buf;
  for J := 0 to I div 64 - 1 do
    begin
      TransformSHABuffer(Digest, P^, True);
      Inc(P, 64);
    end;
end;

procedure SHA1FinalBuf(var Digest: T160BitDigest; const Buf; const BufSize: Integer; const TotalSize: Int64);
var B1, B2 : T512BitBuf;
    C : Integer;
begin
  StdFinalBuf512(Buf, BufSize, TotalSize, B1, B2, C, True);
  TransformSHABuffer(Digest, B1, True);
  if C > 1 then
    TransformSHABuffer(Digest, B2, True);
  SwapEndianBuf(Digest, Sizeof(Digest) div Sizeof(LongWord));
  SecureClear512(B1);
  if C > 1 then
    SecureClear512(B2);
end;

function CalcSHA1(const Buf; const BufSize: Integer): T160BitDigest;
var I, J : Integer;
    P    : PByte;
begin
  SHA1InitDigest(Result);
  P := @Buf;
  if BufSize <= 0 then
    I := 0 else
    I := BufSize;
  J := (I div 64) * 64;
  if J > 0 then
    begin
      SHA1Buf(Result, P^, J);
      Inc(P, J);
      Dec(I, J);
    end;
  SHA1FinalBuf(Result, P^, I, BufSize);
end;

function CalcSHA1(const Buf: RawByteString): T160BitDigest;
begin
  Result := CalcSHA1(Pointer(Buf)^, Length(Buf));
end;

function SHA1DigestToStrA(const Digest: T160BitDigest): RawByteString;
begin
  SetLength(Result, Sizeof(Digest));
  Move(Digest, Pointer(Result)^, Sizeof(Digest));
end;

function SHA1DigestToHexA(const Digest: T160BitDigest): RawByteString;
begin
  Result := DigestToHexA(Digest, Sizeof(Digest));
end;

function SHA1DigestToHexW(const Digest: T160BitDigest): WideString;
begin
  Result := DigestToHexW(Digest, Sizeof(Digest));
end;



{                                                                              }
{ SHA224 Hashing                                                               }
{                                                                              }
{ SHA-224 is identical to SHA-256, except that:                                }
{ - the initial variable values h0 through h7 are different, and               }
{ - the output is constructed by omitting h7                                   }
{                                                                              }
procedure SHA224InitDigest(var Digest: T256BitDigest);
begin
  // The second 32 bits of the fractional parts of the square roots of the 9th through 16th primes 23..53
  Digest.Longs[0] := $c1059ed8;
  Digest.Longs[1] := $367cd507;
  Digest.Longs[2] := $3070dd17;
  Digest.Longs[3] := $f70e5939;
  Digest.Longs[4] := $ffc00b31;
  Digest.Longs[5] := $68581511;
  Digest.Longs[6] := $64f98fa7;
  Digest.Longs[7] := $befa4fa4;
end;

procedure SHA224Buf(var Digest: T256BitDigest; const Buf; const BufSize: Integer);
begin
  SHA256Buf(Digest, Buf, BufSize);
end;

procedure SHA224FinalBuf(var Digest: T256BitDigest; const Buf; const BufSize: Integer; const TotalSize: Int64;
          var OutDigest: T224BitDigest);
begin
  SHA256FinalBuf(Digest, Buf, BufSize, TotalSize);
  Move(Digest.Longs[0], OutDigest.Longs[0], SizeOf(T224BitDigest));
end;

function CalcSHA224(const Buf; const BufSize: Integer): T224BitDigest;
var D    : T256BitDigest;
    I, J : Integer;
    P    : PByte;
begin
  SHA224InitDigest(D);
  P := @Buf;
  if BufSize <= 0 then
    I := 0 else
    I := BufSize;
  J := (I div 64) * 64;
  if J > 0 then
    begin
      SHA224Buf(D, P^, J);
      Inc(P, J);
      Dec(I, J);
    end;
  SHA224FinalBuf(D, P^, I, BufSize, Result);
end;

function CalcSHA224(const Buf: RawByteString): T224BitDigest;
begin
  Result := CalcSHA224(Pointer(Buf)^, Length(Buf));
end;

function SHA224DigestToStrA(const Digest: T224BitDigest): RawByteString;
begin
  SetLength(Result, Sizeof(Digest));
  Move(Digest, Pointer(Result)^, Sizeof(Digest));
end;

function SHA224DigestToHexA(const Digest: T224BitDigest): RawByteString;
begin
  Result := DigestToHexA(Digest, Sizeof(Digest));
end;

function  SHA224DigestToHexW(const Digest: T224BitDigest): WideString;
begin
  Result := DigestToHexW(Digest, Sizeof(Digest));
end;



{                                                                              }
{ SHA256 hashing                                                               }
{                                                                              }
procedure SHA256InitDigest(var Digest: T256BitDigest);
begin
  Digest.Longs[0] := $6a09e667;
  Digest.Longs[1] := $bb67ae85;
  Digest.Longs[2] := $3c6ef372;
  Digest.Longs[3] := $a54ff53a;
  Digest.Longs[4] := $510e527f;
  Digest.Longs[5] := $9b05688c;
  Digest.Longs[6] := $1f83d9ab;
  Digest.Longs[7] := $5be0cd19;
end;

function SHA256Transform1(const A: LongWord): LongWord;
begin
  Result := RotateRightBits(A, 7) xor RotateRightBits(A, 18) xor (A shr 3);
end;

function SHA256Transform2(const A: LongWord): LongWord;
begin
  Result := RotateRightBits(A, 17) xor RotateRightBits(A, 19) xor (A shr 10);
end;

function SHA256Transform3(const A: LongWord): LongWord;
begin
  Result := RotateRightBits(A, 2) xor RotateRightBits(A, 13) xor RotateRightBits(A, 22);
end;

function SHA256Transform4(const A: LongWord): LongWord;
begin
  Result := RotateRightBits(A, 6) xor RotateRightBits(A, 11) xor RotateRightBits(A, 25);
end;

const
  // first 32 bits of the fractional parts of the cube roots of the first 64 primes 2..311
  SHA256K: array[0..63] of LongWord = (
    $428a2f98, $71374491, $b5c0fbcf, $e9b5dba5, $3956c25b, $59f111f1, $923f82a4, $ab1c5ed5,
    $d807aa98, $12835b01, $243185be, $550c7dc3, $72be5d74, $80deb1fe, $9bdc06a7, $c19bf174,
    $e49b69c1, $efbe4786, $0fc19dc6, $240ca1cc, $2de92c6f, $4a7484aa, $5cb0a9dc, $76f988da,
    $983e5152, $a831c66d, $b00327c8, $bf597fc7, $c6e00bf3, $d5a79147, $06ca6351, $14292967,
    $27b70a85, $2e1b2138, $4d2c6dfc, $53380d13, $650a7354, $766a0abb, $81c2c92e, $92722c85,
    $a2bfe8a1, $a81a664b, $c24b8b70, $c76c51a3, $d192e819, $d6990624, $f40e3585, $106aa070,
    $19a4c116, $1e376c08, $2748774c, $34b0bcb5, $391c0cb3, $4ed8aa4a, $5b9cca4f, $682e6ff3,
    $748f82ee, $78a5636f, $84c87814, $8cc70208, $90befffa, $a4506ceb, $bef9a3f7, $c67178f2
  );

{$IFOPT Q+}{$DEFINE QOn}{$Q-}{$ELSE}{$UNDEF QOn}{$ENDIF}
procedure TransformSHA256Buffer(var Digest: T256BitDigest; const Buf);
var
  I : Integer;
  W : array[0..63] of LongWord;
  P : PLongWord;
  S0, S1, Maj, T1, T2, Ch : LongWord;
  H : array[0..7] of LongWord;
begin
  P := @Buf;
  for I := 0 to 15 do
    begin
      W[I] := SwapEndian(P^);
      Inc(P);
    end;
  for I := 16 to 63 do
    begin
      S0 := SHA256Transform1(W[I - 15]);
      S1 := SHA256Transform2(W[I - 2]);
      W[I] := W[I - 16] + S0 + W[I - 7] + S1;
    end;
  for I := 0 to 7 do
    H[I] := Digest.Longs[I];
  for I := 0 to 63 do
    begin
      S0 := SHA256Transform3(H[0]);
      Maj := (H[0] and H[1]) xor (H[0] and H[2]) xor (H[1] and H[2]);
      T2 := S0 + Maj;
      S1 := SHA256Transform4(H[4]);
      Ch := (H[4] and H[5]) xor ((not H[4]) and H[6]);
      T1 := H[7] + S1 + Ch + SHA256K[I] + W[I];
      H[7] := H[6];
      H[6] := H[5];
      H[5] := H[4];
      H[4] := H[3] + T1;
      H[3] := H[2];
      H[2] := H[1];
      H[1] := H[0];
      H[0] := T1 + T2;
    end;
  for I := 0 to 7 do
    Inc(Digest.Longs[I], H[I]);
end;
{$IFDEF QOn}{$Q+}{$ENDIF}

procedure SHA256Buf(var Digest: T256BitDigest; const Buf; const BufSize: Integer);
var P : PByte;
    I, J : Integer;
begin
  I := BufSize;
  if I <= 0 then
    exit;
  Assert(I mod 64 = 0, 'BufSize must be multiple of 64 bytes');
  P := @Buf;
  for J := 0 to I div 64 - 1 do
    begin
      TransformSHA256Buffer(Digest, P^);
      Inc(P, 64);
    end;
end;

procedure SHA256FinalBuf(var Digest: T256BitDigest; const Buf; const BufSize: Integer; const TotalSize: Int64);
var B1, B2 : T512BitBuf;
    C : Integer;
begin
  StdFinalBuf512(Buf, BufSize, TotalSize, B1, B2, C, True);
  TransformSHA256Buffer(Digest, B1);
  if C > 1 then
    TransformSHA256Buffer(Digest, B2);
  SwapEndianBuf(Digest, Sizeof(Digest) div Sizeof(LongWord));
  SecureClear512(B1);
  if C > 1 then
    SecureClear512(B2);
end;

function CalcSHA256(const Buf; const BufSize: Integer): T256BitDigest;
var I, J : Integer;
    P    : PByte;
begin
  SHA256InitDigest(Result);
  P := @Buf;
  if BufSize <= 0 then
    I := 0 else
    I := BufSize;
  J := (I div 64) * 64;
  if J > 0 then
    begin
      SHA256Buf(Result, P^, J);
      Inc(P, J);
      Dec(I, J);
    end;
  SHA256FinalBuf(Result, P^, I, BufSize);
end;

function CalcSHA256(const Buf: RawByteString): T256BitDigest;
begin
  Result := CalcSHA256(Pointer(Buf)^, Length(Buf));
end;

function SHA256DigestToStrA(const Digest: T256BitDigest): RawByteString;
begin
  SetLength(Result, Sizeof(Digest));
  Move(Digest, Pointer(Result)^, Sizeof(Digest));
end;

function SHA256DigestToHexA(const Digest: T256BitDigest): RawByteString;
begin
  Result := DigestToHexA(Digest, Sizeof(Digest));
end;

function SHA256DigestToHexW(const Digest: T256BitDigest): WideString;
begin
  Result := DigestToHexW(Digest, Sizeof(Digest));
end;



{                                                                              }
{ SHA384 Hashing                                                               }
{                                                                              }
procedure SHA384InitDigest(var Digest: T512BitDigest);
begin
  Digest.Word64s[0].LongWords[0] := $c1059ed8;
  Digest.Word64s[0].LongWords[1] := $cbbb9d5d;
  Digest.Word64s[1].LongWords[0] := $367cd507;
  Digest.Word64s[1].LongWords[1] := $629a292a;
  Digest.Word64s[2].LongWords[0] := $3070dd17;
  Digest.Word64s[2].LongWords[1] := $9159015a;
  Digest.Word64s[3].LongWords[0] := $f70e5939;
  Digest.Word64s[3].LongWords[1] := $152fecd8;
  Digest.Word64s[4].LongWords[0] := $ffc00b31;
  Digest.Word64s[4].LongWords[1] := $67332667;
  Digest.Word64s[5].LongWords[0] := $68581511;
  Digest.Word64s[5].LongWords[1] := $8eb44a87;
  Digest.Word64s[6].LongWords[0] := $64f98fa7;
  Digest.Word64s[6].LongWords[1] := $db0c2e0d;
  Digest.Word64s[7].LongWords[0] := $befa4fa4;
  Digest.Word64s[7].LongWords[1] := $47b5481d;
end;

procedure SHA384Buf(var Digest: T512BitDigest; const Buf; const BufSize: Integer);
begin
  SHA512Buf(Digest, Buf, BufSize);
end;

procedure SHA384FinalBuf(var Digest: T512BitDigest; const Buf; const BufSize: Integer; const TotalSize: Int64; var OutDigest: T384BitDigest);
begin
  SHA512FinalBuf(Digest, Buf, BufSize, TotalSize);
  Move(Digest, OutDigest, SizeOf(OutDigest));
end;

function CalcSHA384(const Buf; const BufSize: Integer): T384BitDigest;
var I, J : Integer;
    P    : PByte;
    D    : T512BitDigest;
begin
  SHA384InitDigest(D);
  P := @Buf;
  if BufSize <= 0 then
    I := 0 else
    I := BufSize;
  J := (I div 128) * 128;
  if J > 0 then
    begin
      SHA384Buf(D, P^, J);
      Inc(P, J);
      Dec(I, J);
    end;
  SHA384FinalBuf(D, P^, I, BufSize, Result);
end;

function CalcSHA384(const Buf: RawByteString): T384BitDigest;
begin
  Result := CalcSHA384(Pointer(Buf)^, Length(Buf));
end;

function SHA384DigestToStrA(const Digest: T384BitDigest): RawByteString;
begin
  SetLength(Result, Sizeof(Digest));
  Move(Digest, Pointer(Result)^, Sizeof(Digest));
end;

function SHA384DigestToHexA(const Digest: T384BitDigest): RawByteString;
begin
  Result := DigestToHexA(Digest, Sizeof(Digest));
end;

function SHA384DigestToHexW(const Digest: T384BitDigest): WideString;
begin
  Result := DigestToHexW(Digest, Sizeof(Digest));
end;



{                                                                              }
{ SHA512 Hashing                                                               }
{                                                                              }
procedure SHA512InitDigest(var Digest: T512BitDigest);
begin
  Digest.Word64s[0].LongWords[0] := $f3bcc908;
  Digest.Word64s[0].LongWords[1] := $6a09e667;
  Digest.Word64s[1].LongWords[0] := $84caa73b;
  Digest.Word64s[1].LongWords[1] := $bb67ae85;
  Digest.Word64s[2].LongWords[0] := $fe94f82b;
  Digest.Word64s[2].LongWords[1] := $3c6ef372;
  Digest.Word64s[3].LongWords[0] := $5f1d36f1;
  Digest.Word64s[3].LongWords[1] := $a54ff53a;
  Digest.Word64s[4].LongWords[0] := $ade682d1;
  Digest.Word64s[4].LongWords[1] := $510e527f;
  Digest.Word64s[5].LongWords[0] := $2b3e6c1f;
  Digest.Word64s[5].LongWords[1] := $9b05688c;
  Digest.Word64s[6].LongWords[0] := $fb41bd6b;
  Digest.Word64s[6].LongWords[1] := $1f83d9ab;
  Digest.Word64s[7].LongWords[0] := $137e2179;
  Digest.Word64s[7].LongWords[1] := $5be0cd19;
end;

// BSIG0(x) = ROTR^28(x) XOR ROTR^34(x) XOR ROTR^39(x)
function SHA512Transform1(const A: Word64): Word64;
var T1, T2, T3 : Word64;
begin
  T1 := A;
  T2 := A;
  T3 := A;
  Word64Ror(T1, 28);
  Word64Ror(T2, 34);
  Word64Ror(T3, 39);
  Word64XorWord64(T1, T2);
  Word64XorWord64(T1, T3);
  Result := T1;
end;

// BSIG1(x) = ROTR^14(x) XOR ROTR^18(x) XOR ROTR^41(x)
function SHA512Transform2(const A: Word64): Word64;
var T1, T2, T3 : Word64;
begin
  T1 := A;
  T2 := A;
  T3 := A;
  Word64Ror(T1, 14);
  Word64Ror(T2, 18);
  Word64Ror(T3, 41);
  Word64XorWord64(T1, T2);
  Word64XorWord64(T1, T3);
  Result := T1;
end;

// SSIG0(x) = ROTR^1(x) XOR ROTR^8(x) XOR SHR^7(x)
function SHA512Transform3(const A: Word64): Word64;
var T1, T2, T3 : Word64;
begin
  T1 := A;
  T2 := A;
  T3 := A;
  Word64Ror(T1, 1);
  Word64Ror(T2, 8);
  Word64Shr(T3, 7);
  Word64XorWord64(T1, T2);
  Word64XorWord64(T1, T3);
  Result := T1;
end;

// SSIG1(x) = ROTR^19(x) XOR ROTR^61(x) XOR SHR^6(x)
function SHA512Transform4(const A: Word64): Word64;
var T1, T2, T3 : Word64;
begin
  T1 := A;
  T2 := A;
  T3 := A;
  Word64Ror(T1, 19);
  Word64Ror(T2, 61);
  Word64Shr(T3, 6);
  Word64XorWord64(T1, T2);
  Word64XorWord64(T1, T3);
  Result := T1;
end;

// CH( x, y, z) = (x AND y) XOR ( (NOT x) AND z)
function SHA512Transform5(const X, Y, Z: Word64): Word64;
var T1, T2 : Word64;
begin
  T1 := X;
  Word64AndWord64(T1, Y);
  T2 := X;
  Word64Not(T2);
  Word64AndWord64(T2, Z);
  Word64XorWord64(T1, T2);
  Result := T1;
end;

// MAJ( x, y, z) = (x AND y) XOR (x AND z) XOR (y AND z)
function SHA512Transform6(const X, Y, Z: Word64): Word64;
var T1, T2, T3 : Word64;
begin
  T1 := X;
  Word64AndWord64(T1, Y);
  T2 := X;
  Word64AndWord64(T2, Z);
  T3 := Y;
  Word64AndWord64(T3, Z);
  Word64XorWord64(T1, T2);
  Word64XorWord64(T1, T3);
  Result := T1;
end;

const
  // first 64 bits of the fractional parts of the cube roots of the first eighty prime numbers
  // (stored High LongWord first then Low LongWord)
  SHA512K: array[0..159] of LongWord = (
    $428a2f98, $d728ae22, $71374491, $23ef65cd, $b5c0fbcf, $ec4d3b2f, $e9b5dba5, $8189dbbc,
    $3956c25b, $f348b538, $59f111f1, $b605d019, $923f82a4, $af194f9b, $ab1c5ed5, $da6d8118,
    $d807aa98, $a3030242, $12835b01, $45706fbe, $243185be, $4ee4b28c, $550c7dc3, $d5ffb4e2,
    $72be5d74, $f27b896f, $80deb1fe, $3b1696b1, $9bdc06a7, $25c71235, $c19bf174, $cf692694,
    $e49b69c1, $9ef14ad2, $efbe4786, $384f25e3, $0fc19dc6, $8b8cd5b5, $240ca1cc, $77ac9c65,
    $2de92c6f, $592b0275, $4a7484aa, $6ea6e483, $5cb0a9dc, $bd41fbd4, $76f988da, $831153b5,
    $983e5152, $ee66dfab, $a831c66d, $2db43210, $b00327c8, $98fb213f, $bf597fc7, $beef0ee4,
    $c6e00bf3, $3da88fc2, $d5a79147, $930aa725, $06ca6351, $e003826f, $14292967, $0a0e6e70,
    $27b70a85, $46d22ffc, $2e1b2138, $5c26c926, $4d2c6dfc, $5ac42aed, $53380d13, $9d95b3df,
    $650a7354, $8baf63de, $766a0abb, $3c77b2a8, $81c2c92e, $47edaee6, $92722c85, $1482353b,
    $a2bfe8a1, $4cf10364, $a81a664b, $bc423001, $c24b8b70, $d0f89791, $c76c51a3, $0654be30,
    $d192e819, $d6ef5218, $d6990624, $5565a910, $f40e3585, $5771202a, $106aa070, $32bbd1b8,
    $19a4c116, $b8d2d0c8, $1e376c08, $5141ab53, $2748774c, $df8eeb99, $34b0bcb5, $e19b48a8,
    $391c0cb3, $c5c95a63, $4ed8aa4a, $e3418acb, $5b9cca4f, $7763e373, $682e6ff3, $d6b2b8a3,
    $748f82ee, $5defb2fc, $78a5636f, $43172f60, $84c87814, $a1f0ab72, $8cc70208, $1a6439ec,
    $90befffa, $23631e28, $a4506ceb, $de82bde9, $bef9a3f7, $b2c67915, $c67178f2, $e372532b,
    $ca273ece, $ea26619c, $d186b8c7, $21c0c207, $eada7dd6, $cde0eb1e, $f57d4f7f, $ee6ed178,
    $06f067aa, $72176fba, $0a637dc5, $a2c898a6, $113f9804, $bef90dae, $1b710b35, $131c471b,
    $28db77f5, $23047d84, $32caab7b, $40c72493, $3c9ebe0a, $15c9bebc, $431d67c4, $9c100d4c,
    $4cc5d4be, $cb3e42b6, $597f299c, $fc657e2a, $5fcb6fab, $3ad6faec, $6c44198c, $4a475817
    );

{$IFOPT Q+}{$DEFINE QOn}{$Q-}{$ELSE}{$UNDEF QOn}{$ENDIF}
procedure TransformSHA512Buffer(var Digest: T512BitDigest; const Buf);
var
  I : Integer;
  P : PWord64;
  W : array[0..79] of Word64;
  T1, T2, T3, T4, K : Word64;
  H : array[0..7] of Word64;
begin
  P := @Buf;
  for I := 0 to 15 do
    begin
      W[I] := P^;
      Word64SwapEndian(W[I]);
      Inc(P);
    end;
  for I := 16 to 79 do
    begin
      T1 := SHA512Transform4(W[I - 2]);
      T2 := W[I - 7];
      T3 := SHA512Transform3(W[I - 15]);  // bug in RFC (specifies I-5 instead of W[I-5])
      T4 := W[I - 16];
      Word64AddWord64(T1, T2);
      Word64AddWord64(T1, T3);
      Word64AddWord64(T1, T4);
      W[I] := T1;
    end;
  for I := 0 to 7 do
    H[I] := Digest.Word64s[I];
  for I := 0 to 79 do
    begin
      // T1 = h + BSIG1(e) + CH(e,f,g) + Kt + Wt
      T1 := H[7];
      Word64AddWord64(T1, SHA512Transform2(H[4]));
      Word64AddWord64(T1, SHA512Transform5(H[4], H[5], H[6]));
      K.LongWords[0] := SHA512K[I * 2 + 1];
      K.LongWords[1] := SHA512K[I * 2];
      Word64AddWord64(T1, K);
      Word64AddWord64(T1, W[I]);
      // T2 = BSIG0(a) + MAJ(a,b,c)
      T2 := SHA512Transform1(H[0]);
      Word64AddWord64(T2, SHA512Transform6(H[0], H[1], H[2]));
      // h = g    g = f
      // f = e    e = d + T1
      // d = c    c = b
      // b = a    a = T1 + T2
      H[7] := H[6];
      H[6] := H[5];
      H[5] := H[4];
      H[4] := H[3];
      Word64AddWord64(H[4], T1);
      H[3] := H[2];
      H[2] := H[1];
      H[1] := H[0];
      H[0] := T1;
      Word64AddWord64(H[0], T2);
    end;
  for I := 0 to 7 do
    Word64AddWord64(Digest.Word64s[I], H[I]);
end;
{$IFDEF QOn}{$Q+}{$ENDIF}

procedure SHA512Buf(var Digest: T512BitDigest; const Buf; const BufSize: Integer);
var P : PByte;
    I, J : Integer;
begin
  I := BufSize;
  if I <= 0 then
    exit;
  Assert(I mod 128 = 0, 'BufSize must be multiple of 128 bytes');
  P := @Buf;
  for J := 0 to I div 128 - 1 do
    begin
      TransformSHA512Buffer(Digest, P^);
      Inc(P, 128);
    end;
end;

procedure SHA512FinalBuf(var Digest: T512BitDigest; const Buf; const BufSize: Integer; const TotalSize: Int64);
var B1, B2 : T1024BitBuf;
    C : Integer;
begin
  StdFinalBuf1024(Buf, BufSize, TotalSize, B1, B2, C, True);
  TransformSHA512Buffer(Digest, B1);
  if C > 1 then
    TransformSHA512Buffer(Digest, B2);
  SwapEndianBuf64(Digest, Sizeof(Digest) div Sizeof(Word64));
  SecureClear1024(B1);
  if C > 1 then
    SecureClear1024(B2);
end;

function CalcSHA512(const Buf; const BufSize: Integer): T512BitDigest;
var I, J : Integer;
    P    : PByte;
begin
  SHA512InitDigest(Result);
  P := @Buf;
  if BufSize <= 0 then
    I := 0 else
    I := BufSize;
  J := (I div 128) * 128;
  if J > 0 then
    begin
      SHA512Buf(Result, P^, J);
      Inc(P, J);
      Dec(I, J);
    end;
  SHA512FinalBuf(Result, P^, I, BufSize);
end;

function CalcSHA512(const Buf: RawByteString): T512BitDigest;
begin
  Result := CalcSHA512(Pointer(Buf)^, Length(Buf));
end;

function SHA512DigestToStrA(const Digest: T512BitDigest): RawByteString;
begin
  SetLength(Result, Sizeof(Digest));
  Move(Digest, Pointer(Result)^, Sizeof(Digest));
end;

function SHA512DigestToHexA(const Digest: T512BitDigest): RawByteString;
begin
  Result := DigestToHexA(Digest, Sizeof(Digest));
end;

function SHA512DigestToHexW(const Digest: T512BitDigest): WideString;
begin
  Result := DigestToHexW(Digest, Sizeof(Digest));
end;



{                                                                              }
{ RIPEMD160                                                                    }
{   160 bit RIPEMD.                                                            }
{                                                                              }

// f(j, x, y, z) = x XOR y XOR z                (0 <= j <= 15)
function RipeMD_F1(const X, Y, Z: LongWord): LongWord;
begin
  Result := X xor Y xor Z;
end;

// f(j, x, y, z) = (x AND y) OR (NOT(x) AND z)  (16 <= j <= 31)
function RipeMD_F2(const X, Y, Z: LongWord): LongWord;
begin
  Result := (X and Y) or ((not X) and Z);
end;

// f(j, x, y, z) = (x OR NOT(y)) XOR z          (32 <= j <= 47)
function RipeMD_F3(const X, Y, Z: LongWord): LongWord;
begin
  Result := (X or (not Y)) xor Z;
end;

// f(j, x, y, z) = (x AND z) OR (y AND NOT(z))  (48 <= j <= 63)
function RipeMD_F4(const X, Y, Z: LongWord): LongWord;
begin
  Result := (X and Z) or (Y and (not Z));
end;

// f(j, x, y, z) = x XOR (y OR NOT(z))          (64 <= j <= 79)
function RipeMD_F5(const X, Y, Z: LongWord): LongWord;
begin
  Result := X xor (Y or (not Z));
end;

// f(j, x, y, z)
function RipeMD_F(const J: Byte; const X, Y, Z: LongWord): LongWord;
begin
  case J of
    0..15  : Result := RipeMD_F1(X, Y, Z);
    16..31 : Result := RipeMD_F2(X, Y, Z);
    32..47 : Result := RipeMD_F3(X, Y, Z);
    48..63 : Result := RipeMD_F4(X, Y, Z);
    64..79 : Result := RipeMD_F5(X, Y, Z);
  else
    raise EHashError.Create(hashInternalError, 'Internal error');
  end;
end;

const
  // K(j) = 0x00000000      (0 <= j <= 15)
  // K(j) = 0x5A827999     (16 <= j <= 31)      int(2**30 x sqrt(2))
  // K(j) = 0x6ED9EBA1     (32 <= j <= 47)      int(2**30 x sqrt(3))
  // K(j) = 0x8F1BBCDC     (48 <= j <= 63)      int(2**30 x sqrt(5))
  // K(j) = 0xA953FD4E     (64 <= j <= 79)      int(2**30 x sqrt(7))
  RipeMD_K : array[0..4] of LongWord = (
      $00000000,
      $5A827999,
      $6ED9EBA1,
      $8F1BBCDC,
      $A953FD4E );

  // K'(j) = 0x50A28BE6     (0 <= j <= 15)      int(2**30 x cbrt(2))
  // K'(j) = 0x5C4DD124    (16 <= j <= 31)      int(2**30 x cbrt(3))
  // K'(j) = 0x6D703EF3    (32 <= j <= 47)      int(2**30 x cbrt(5))
  // K'(j) = 0x7A6D76E9    (48 <= j <= 63)      int(2**30 x cbrt(7))
  // K'(j) = 0x00000000    (64 <= j <= 79)
  RipeMD_KP : array[0..4] of LongWord = (
      $50A28BE6,
      $5C4DD124,
      $6D703EF3,
      $7A6D76E9,
      $00000000 );

  // r(j)      = j                    (0 <= j <= 15)
  // r(16..31) = 7, 4, 13, 1, 10, 6, 15, 3, 12, 0, 9, 5, 2, 14, 11, 8
  // r(32..47) = 3, 10, 14, 4, 9, 15, 8, 1, 2, 7, 0, 6, 13, 11, 5, 12
  // r(48..63) = 1, 9, 11, 10, 0, 8, 12, 4, 13, 3, 7, 15, 14, 5, 6, 2
  // r(64..79) = 4, 0, 5, 9, 7, 12, 2, 10, 14, 1, 3, 8, 11, 6, 15, 13
  RipeMD_R : array[0..79] of Byte = (
      0,  1,  2,  3,  4,  5,  6,  7,  8,  9, 10, 11, 12, 13, 14, 15,
      7,  4, 13,  1, 10,  6, 15,  3, 12,  0,  9,  5,  2, 14, 11,  8,
      3, 10, 14,  4,  9, 15,  8,  1,  2,  7,  0,  6, 13, 11,  5, 12,
      1,  9, 11, 10,  0,  8, 12,  4, 13,  3,  7, 15, 14,  5,  6,  2,
      4,  0,  5,  9,  7, 12,  2, 10, 14,  1,  3,  8, 11,  6, 15, 13 );

  // r'(0..15) = 5, 14, 7, 0, 9, 2, 11, 4, 13, 6, 15, 8, 1, 10, 3, 12
  // r'(16..31)= 6, 11, 3, 7, 0, 13, 5, 10, 14, 15, 8, 12, 4, 9, 1, 2
  // r'(32..47)= 15, 5, 1, 3, 7, 14, 6, 9, 11, 8, 12, 2, 10, 0, 4, 13
  // r'(48..63)= 8, 6, 4, 1, 3, 11, 15, 0, 5, 12, 2, 13, 9, 7, 10, 14
  // r'(64..79)= 12, 15, 10, 4, 1, 5, 8, 7, 6, 2, 13, 14, 0, 3, 9, 11
  RipeMD_RP : array[0..79] of Byte = (
       5, 14,  7,  0,  9,  2, 11,  4, 13,  6, 15, 8,  1, 10,  3, 12,
       6, 11,  3,  7,  0, 13,  5, 10, 14, 15,  8, 12, 4,  9,  1,  2,
      15,  5,  1,  3,  7, 14,  6,  9, 11,  8, 12, 2, 10,  0,  4, 13,
       8,  6,  4,  1,  3, 11, 15,  0,  5, 12,  2, 13, 9,  7, 10, 14,
      12, 15, 10,  4,  1,  5,  8,  7,  6,  2, 13, 14, 0,  3,  9, 11 );

  // s(0..15)  = 11, 14, 15, 12, 5, 8, 7, 9, 11, 13, 14, 15, 6, 7, 9, 8
  // s(16..31) = 7, 6, 8, 13, 11, 9, 7, 15, 7, 12, 15, 9, 11, 7, 13, 12
  // s(32..47) = 11, 13, 6, 7, 14, 9, 13, 15, 14, 8, 13, 6, 5, 12, 7, 5
  // s(48..63) = 11, 12, 14, 15, 14, 15, 9, 8, 9, 14, 5, 6, 8, 6, 5, 12
  // s(64..79) = 9, 15, 5, 11, 6, 8, 13, 12, 5, 12, 13, 14, 11, 8, 5, 6
  RipeMD_S : array[0..79] of Byte = (
      11, 14, 15, 12,  5,  8,  7,  9, 11, 13, 14, 15,  6,  7,  9,  8,
       7,  6,  8, 13, 11,  9,  7, 15,  7, 12, 15,  9, 11,  7, 13, 12,
      11, 13,  6,  7, 14,  9, 13, 15, 14,  8, 13,  6,  5, 12,  7,  5,
      11, 12, 14, 15, 14, 15,  9,  8,  9, 14,  5,  6,  8,  6,  5, 12,
       9, 15,  5, 11,  6,  8, 13, 12,  5, 12, 13, 14, 11,  8,  5,  6 );

  // s'(0..15) = 8, 9, 9, 11, 13, 15, 15, 5, 7, 7, 8, 11, 14, 14, 12, 6
  // s'(16..31)= 9, 13, 15, 7, 12, 8, 9, 11, 7, 7, 12, 7, 6, 15, 13, 11
  // s'(32..47)= 9, 7, 15, 11, 8, 6, 6, 14, 12, 13, 5, 14, 13, 13, 7, 5
  // s'(48..63)= 15, 5, 8, 11, 14, 14, 6, 14, 6, 9, 12, 9, 12, 5, 15, 8
  // s'(64..79)= 8, 5, 12, 9, 12, 5, 14, 6, 8, 13, 6, 5, 15, 13, 11, 11
  RipeMD_SP : array[0..79] of Byte = (
       8,  9,  9, 11, 13, 15, 15,  5,  7,  7,  8, 11, 14, 14, 12,  6,
       9, 13, 15,  7, 12,  8,  9, 11,  7,  7, 12,  7,  6, 15, 13, 11,
       9,  7, 15, 11,  8,  6,  6, 14, 12, 13,  5, 14, 13, 13,  7,  5,
      15,  5,  8, 11, 14, 14,  6, 14,  6,  9, 12,  9, 12,  5, 15,  8,
       8,  5, 12,  9, 12,  5, 14,  6,  8, 13,  6,  5, 15, 13, 11, 11 );

// Pascal version of:
// function Word32Add(const A, B: LongWord): LongWord; assembler;
// asm
//       ADD     EAX, EDX
// end;
//
// Temporary turn Q off as an optimisation since Word32Add is frequently used
// and it can never overflow in any case
{$IFOPT Q+}{$DEFINE QOn}{$Q-}{$ELSE}{$UNDEF QOn}{$ENDIF}
function Word32Add(const A, B: LongWord): LongWord; {$IFDEF UseInline}inline;{$ENDIF}
var R : Int64;
begin
  R := Int64(A) + Int64(B);
  Result := LongWord(R and $FFFFFFFF);
end;
{$IFDEF QOn}{$Q+}{$ENDIF}

type
  TRipeMD160Block = array[0..15] of LongWord;
  PRipeMD160Block = ^TRipeMD160Block;

(*
    It is assumed that the message after padding consists of t 16-word blocks
    that will be denoted with X[i][j], with 0 <= i <= t-1 and 0 <= j <= 15.
    The symbol [+] denotes addition modulo 2**32 and rol_s denotes cyclic left
    shift (rotate) over s positions.
    A := h0; B := h1; C := h2; D = h3; E = h4;
    A' := h0; B' := h1; C' := h2; D' = h3; E' = h4;
    for j := 0 to 79 {
        T := rol_s(j)(A [+] f(j, B, C, D) [+] X[i][r(j)] [+] K(j)) [+] E;
        A := E; E := D; D := rol_10(C); C := B; B := T;
        T := rol_s'(j)(A' [+] f(79-j, B', C', D') [+] X[i][r'(j)] [+] K'(j)) [+] E';
        A' := E'; E' := D'; D' := rol_10(C'); C' := B'; B' := T;
    }
    T := h1 [+] C [+] D'; h1 := h2 [+] D [+] E'; h2 := h3 [+] E [+] A';
    h3 := h4 [+] A [+] B'; h4 := h0 [+] B [+] C'; h0 := T;
*)
procedure RipeMD160Block(var Digest: T160BitDigest; const Block: TRipeMD160Block);
var
  H0, H1, H2, H3, H4 : LongWord;
  A, B, C, D, E : LongWord;
  AP, BP, CP, DP, EP : LongWord;
  J, J16 : Byte;
  T : LongWord;
begin
  H0 := Digest.Longs[0];
  H1 := Digest.Longs[1];
  H2 := Digest.Longs[2];
  H3 := Digest.Longs[3];
  H4 := Digest.Longs[4];

  // A := h0; B := h1; C := h2; D = h3; E = h4;
  A := H0;
  B := H1;
  C := H2;
  D := H3;
  E := H4;

  // A' := h0; B' := h1; C' := h2; D' = h3; E' = h4;
  AP := H0;
  BP := H1;
  CP := H2;
  DP := H3;
  EP := H4;

  for J := 0 to 79 do
    begin
      J16 := J div 16;
      // T := rol_s(j)(A [+] f(j, B, C, D) [+] X[i][r(j)] [+] K(j)) [+] E;
      T := Word32Add(A, RipeMD_F(J, B, C, D));
      T := Word32Add(T, Block[RipeMD_R[J]]);
      T := Word32Add(T, RipeMD_K[J16]);
      T := RotateLeftBits(T, RipeMD_S[J]);
      T := Word32Add(T, E);
      // A := E; E := D; D := rol_10(C); C := B; B := T;
      A := E;
      E := D;
      D := RotateLeftBits(C, 10);
      C := B;
      B := T;
      // T := rol_s'(j)(A' [+] f(79-j, B', C', D') [+] X[i][r'(j)] [+] K'(j)) [+] E';
      T := Word32Add(AP, RipeMD_F(79 - J, BP, CP, DP));
      T := Word32Add(T, Block[RipeMD_RP[J]]);
      T := Word32Add(T, RipeMD_KP[J16]);
      T := RotateLeftBits(T, RipeMD_SP[J]);
      T := Word32Add(T, EP);
      // A' := E'; E' := D'; D' := rol_10(C'); C' := B'; B' := T;
      AP := EP;
      EP := DP;
      DP := RotateLeftBits(CP, 10);
      CP := BP;
      BP := T;
    end;

  // T := h1 [+] C [+] D';
  T := Word32Add(H1, C);
  T := Word32Add(T, DP);
  // h1 := h2 [+] D [+] E';
  H1 := Word32Add(H2, D);
  H1 := Word32Add(H1, EP);
  // h2 := h3 [+] E [+] A';
  H2 := Word32Add(H3, E);
  H2 := Word32Add(H2, AP);
  // h3 := h4 [+] A [+] B';
  H3 := Word32Add(H4, A);
  H3 := Word32Add(H3, BP);
  // h4 := h0 [+] B [+] C';
  H4 := Word32Add(H0, B);
  H4 := Word32Add(H4, CP);
  // h0 := T;
  H0 := T;

  Digest.Longs[0] := H0;
  Digest.Longs[1] := H1;
  Digest.Longs[2] := H2;
  Digest.Longs[3] := H3;
  Digest.Longs[4] := H4;
end;

// initial value (hexadecimal)
// h0 = 0x67452301; h1 = 0xEFCDAB89; h2 = 0x98BADCFE; h3 = 0x10325476; h4 = 0xC3D2E1F0;
procedure RipeMD160InitDigest(var Digest: T160BitDigest);
begin
  Digest.Longs[0] := $67452301;
  Digest.Longs[1] := $EFCDAB89;
  Digest.Longs[2] := $98BADCFE;
  Digest.Longs[3] := $10325476;
  Digest.Longs[4] := $C3D2E1F0;
end;

procedure RipeMD160Buf(var Digest: T160BitDigest; const Buf; const BufSize: Integer);
var P : PRipeMD160Block;
    I, J : Integer;
begin
  I := BufSize;
  if I <= 0 then
    exit;
  Assert(I mod 64 = 0, 'BufSize must be multiple of 64 bytes');
  P := @Buf;
  for J := 0 to I div 64 - 1 do
    begin
      RipeMD160Block(Digest, P^);
      Inc(P);
    end;
end;

procedure RipeMD160FinalBuf(var Digest: T160BitDigest; const Buf; const BufSize: Integer; const TotalSize: Int64);
var B1, B2 : T512BitBuf;
    C : Integer;
begin
  StdFinalBuf512(Buf, BufSize, TotalSize, B1, B2, C, False);
  RipeMD160Block(Digest, PRipeMD160Block(@B1)^);
  if C > 1 then
    RipeMD160Block(Digest, PRipeMD160Block(@B2)^);
  SecureClear512(B1);
  if C > 1 then
    SecureClear512(B2);
end;

function CalcRipeMD160(const Buf; const BufSize: Integer): T160BitDigest;
var I, J : Integer;
    P    : PByte;
begin
  RipeMD160InitDigest(Result);
  P := @Buf;
  if BufSize <= 0 then
    I := 0 else
    I := BufSize;
  J := (I div 64) * 64;
  if J > 0 then
    begin
      RipeMD160Buf(Result, P^, J);
      Inc(P, J);
      Dec(I, J);
    end;
  RipeMD160FinalBuf(Result, P^, I, BufSize);
end;

function CalcRipeMD160(const Buf: RawByteString): T160BitDigest;
begin
  Result := CalcRipeMD160(Pointer(Buf)^, Length(Buf));
end;

function RipeMD160DigestToStrA(const Digest: T160BitDigest): RawByteString;
begin
  SetLength(Result, Sizeof(Digest));
  Move(Digest, Pointer(Result)^, Sizeof(Digest));
end;

function RipeMD160DigestToHexA(const Digest: T160BitDigest): RawByteString;
begin
  Result := DigestToHexA(Digest, Sizeof(Digest));
end;

function RipeMD160DigestToHexW(const Digest: T160BitDigest): WideString;
begin
  Result := DigestToHexW(Digest, Sizeof(Digest));
end;



{                                                                              }
{ HMAC utility functions                                                       }
{                                                                              }
procedure HMAC_KeyBlock512(const Key; const KeySize: Integer; var Buf: T512BitBuf);
var P : PAnsiChar;
begin
  Assert(KeySize <= 64);
  P := @Buf;
  if KeySize > 0 then
    begin
      Move(Key, P^, KeySize);
      Inc(P, KeySize);
    end;
  FillChar(P^, 64 - KeySize, #0);
end;

procedure HMAC_KeyBlock1024(const Key; const KeySize: Integer; var Buf: T1024BitBuf);
var P : PAnsiChar;
begin
  Assert(KeySize <= 128);
  P := @Buf;
  if KeySize > 0 then
    begin
      Move(Key, P^, KeySize);
      Inc(P, KeySize);
    end;
  FillChar(P^, 128 - KeySize, #0);
end;

procedure XORBlock512(var Buf: T512BitBuf; const XOR8: Byte);
var I : Integer;
    P : PByte;
begin
  P := @Buf;
  for I := 0 to SizeOf(Buf) - 1 do
    begin
      P^ := P^ xor XOR8;
      Inc(P);
    end;
end;

procedure XORBlock1024(var Buf: T1024BitBuf; const XOR8: Byte);
var I : Integer;
    P : PByte;
begin
  P := @Buf;
  for I := 0 to SizeOf(Buf) - 1 do
    begin
      P^ := P^ xor XOR8;
      Inc(P);
    end;
end;



{                                                                              }
{ HMAC-MD5 keyed hashing                                                       }
{                                                                              }
procedure HMAC_MD5Init(const Key: Pointer; const KeySize: Integer; var Digest: T128BitDigest; var K: T512BitBuf);
var S : T512BitBuf;
    D : T128BitDigest;
begin
  MD5InitDigest(Digest);

  if KeySize > 64 then
    begin
      D := CalcMD5(Key^, KeySize);
      HMAC_KeyBlock512(D, Sizeof(D), K);
    end else
    HMAC_KeyBlock512(Key^, KeySize, K);

  Move(K, S, SizeOf(K));
  XORBlock512(S, $36);
  TransformMD5Buffer(Digest, S);
  SecureClear512(S);
end;

procedure HMAC_MD5Buf(var Digest: T128BitDigest; const Buf; const BufSize: Integer);
begin
  MD5Buf(Digest, Buf, BufSize);
end;

procedure HMAC_MD5FinalBuf(const K: T512BitBuf; var Digest: T128BitDigest; const Buf; const BufSize: Integer; const TotalSize: Int64);
var
  FinBuf : packed record
    K : T512BitBuf;
    D : T128BitDigest;
  end;
begin
  MD5FinalBuf(Digest, Buf, BufSize, TotalSize + 64);
  Move(K, FinBuf.K, SizeOf(K));
  XORBlock512(FinBuf.K, $5C);
  Move(Digest, FinBuf.D, SizeOf(Digest));
  Digest := CalcMD5(FinBuf, SizeOf(FinBuf));
  SecureClear(FinBuf, SizeOf(FinBuf));
end;

function CalcHMAC_MD5(const Key: Pointer; const KeySize: Integer; const Buf; const BufSize: Integer): T128BitDigest;
var I, J : Integer;
    P    : PByte;
    K    : T512BitBuf;
begin
  HMAC_MD5Init(Key, KeySize, Result, K);
  P := @Buf;
  if BufSize <= 0 then
    I := 0 else
    I := BufSize;
  J := (I div 64) * 64;
  if J > 0 then
    begin
      HMAC_MD5Buf(Result, P^, J);
      Inc(P, J);
      Dec(I, J);
    end;
  HMAC_MD5FinalBuf(K, Result, P^, I, BufSize);
  SecureClear512(K);
end;

function CalcHMAC_MD5(const Key: RawByteString; const Buf; const BufSize: Integer): T128BitDigest;
begin
  Result := CalcHMAC_MD5(Pointer(Key), Length(Key), Buf, BufSize);
end;

function CalcHMAC_MD5(const Key, Buf: RawByteString): T128BitDigest;
begin
  Result := CalcHMAC_MD5(Key, Pointer(Buf)^, Length(Buf));
end;



{                                                                              }
{ HMAC-SHA1 keyed hashing                                                      }
{                                                                              }
procedure HMAC_SHA1Init(const Key: Pointer; const KeySize: Integer; var Digest: T160BitDigest; var K: T512BitBuf);
var D : T160BitDigest;
    S : T512BitBuf;
begin
  SHA1InitDigest(Digest);

  if KeySize > 64 then
    begin
      D := CalcSHA1(Key^, KeySize);
      HMAC_KeyBlock512(D, Sizeof(D), K);
    end else
    HMAC_KeyBlock512(Key^, KeySize, K);

  Move(K, S, SizeOf(K));
  XORBlock512(S, $36);
  TransformSHABuffer(Digest, S, True);
  SecureClear512(S);
end;

procedure HMAC_SHA1Buf(var Digest: T160BitDigest; const Buf; const BufSize: Integer);
begin
  SHA1Buf(Digest, Buf, BufSize);
end;

procedure HMAC_SHA1FinalBuf(const K: T512BitBuf; var Digest: T160BitDigest; const Buf; const BufSize: Integer; const TotalSize: Int64);
var
  FinBuf : packed record
    K : T512BitBuf;
    D : T160BitDigest;
  end;
begin
  SHA1FinalBuf(Digest, Buf, BufSize, TotalSize + 64);
  Move(K, FinBuf.K, SizeOf(K));
  XORBlock512(FinBuf.K, $5C);
  Move(Digest, FinBuf.D, SizeOf(Digest));
  Digest := CalcSHA1(FinBuf, SizeOf(FinBuf));
  SecureClear(FinBuf, SizeOf(FinBuf));
end;

function CalcHMAC_SHA1(const Key: Pointer; const KeySize: Integer; const Buf; const BufSize: Integer): T160BitDigest;
var I, J : Integer;
    P    : PByte;
    K    : T512BitBuf;
begin
  HMAC_SHA1Init(Key, KeySize, Result, K);
  P := @Buf;
  if BufSize <= 0 then
    I := 0 else
    I := BufSize;
  J := (I div 64) * 64;
  if J > 0 then
    begin
      HMAC_SHA1Buf(Result, P^, J);
      Inc(P, J);
      Dec(I, J);
    end;
  HMAC_SHA1FinalBuf(K, Result, P^, I, BufSize);
  SecureClear512(K);
end;

function CalcHMAC_SHA1(const Key: RawByteString; const Buf; const BufSize: Integer): T160BitDigest;
begin
  Result := CalcHMAC_SHA1(Pointer(Key), Length(Key), Buf, BufSize);
end;

function CalcHMAC_SHA1(const Key, Buf: RawByteString): T160BitDigest;
begin
  Result := CalcHMAC_SHA1(Key, Pointer(Buf)^, Length(Buf));
end;



{                                                                              }
{ HMAC-SHA256 keyed hashing                                                    }
{                                                                              }
procedure HMAC_SHA256Init(const Key: Pointer; const KeySize: Integer; var Digest: T256BitDigest; var K: T512BitBuf);
var D : T256BitDigest;
    S : T512BitBuf;
begin
  SHA256InitDigest(Digest);

  if KeySize > 64 then
    begin
      D := CalcSHA256(Key^, KeySize);
      HMAC_KeyBlock512(D, Sizeof(D), K);
    end else
    HMAC_KeyBlock512(Key^, KeySize, K);

  Move(K, S, SizeOf(K));
  XORBlock512(S, $36);
  TransformSHA256Buffer(Digest, S);
  SecureClear512(S);
end;

procedure HMAC_SHA256Buf(var Digest: T256BitDigest; const Buf; const BufSize: Integer);
begin
  SHA256Buf(Digest, Buf, BufSize);
end;

procedure HMAC_SHA256FinalBuf(const K: T512BitBuf; var Digest: T256BitDigest; const Buf; const BufSize: Integer; const TotalSize: Int64);
var
  FinBuf : packed record
    K : T512BitBuf;
    D : T256BitDigest;
  end;
begin
  SHA256FinalBuf(Digest, Buf, BufSize, TotalSize + 64);
  Move(K, FinBuf.K, SizeOf(K));
  XORBlock512(FinBuf.K, $5C);
  Move(Digest, FinBuf.D, SizeOf(Digest));
  Digest := CalcSHA256(FinBuf, SizeOf(FinBuf));
  SecureClear(FinBuf, SizeOf(FinBuf));
end;

function CalcHMAC_SHA256(const Key: Pointer; const KeySize: Integer; const Buf; const BufSize: Integer): T256BitDigest;
var I, J : Integer;
    P    : PByte;
    K    : T512BitBuf;
begin
  HMAC_SHA256Init(Key, KeySize, Result, K);
  P := @Buf;
  if BufSize <= 0 then
    I := 0 else
    I := BufSize;
  J := (I div 64) * 64;
  if J > 0 then
    begin
      HMAC_SHA256Buf(Result, P^, J);
      Inc(P, J);
      Dec(I, J);
    end;
  HMAC_SHA256FinalBuf(K, Result, P^, I, BufSize);
  SecureClear512(K);
end;

function CalcHMAC_SHA256(const Key: RawByteString; const Buf; const BufSize: Integer): T256BitDigest;
begin
  Result := CalcHMAC_SHA256(Pointer(Key), Length(Key), Buf, BufSize);
end;

function CalcHMAC_SHA256(const Key, Buf: RawByteString): T256BitDigest;
begin
  Result := CalcHMAC_SHA256(Key, Pointer(Buf)^, Length(Buf));
end;



{                                                                              }
{ HMAC-SHA512 keyed hashing                                                    }
{                                                                              }
procedure HMAC_SHA512Init(const Key: Pointer; const KeySize: Integer; var Digest: T512BitDigest; var K: T1024BitBuf);
var D : T512BitDigest;
    S : T1024BitBuf;
begin
  SHA512InitDigest(Digest);

  if KeySize > 128 then
    begin
      D := CalcSHA512(Key^, KeySize);
      HMAC_KeyBlock1024(D, Sizeof(D), K);
    end else
    HMAC_KeyBlock1024(Key^, KeySize, K);

  Move(K, S, SizeOf(K));
  XORBlock1024(S, $36);
  TransformSHA512Buffer(Digest, S);
  SecureClear1024(S);
end;

procedure HMAC_SHA512Buf(var Digest: T512BitDigest; const Buf; const BufSize: Integer);
begin
  SHA512Buf(Digest, Buf, BufSize);
end;

procedure HMAC_SHA512FinalBuf(const K: T1024BitBuf; var Digest: T512BitDigest; const Buf; const BufSize: Integer; const TotalSize: Int64);
var
  FinBuf : packed record
    K : T1024BitBuf;
    D : T512BitDigest;
  end;
begin
  SHA512FinalBuf(Digest, Buf, BufSize, TotalSize + 128);
  Move(K, FinBuf.K, SizeOf(K));
  XORBlock1024(FinBuf.K, $5C);
  Move(Digest, FinBuf.D, SizeOf(Digest));
  Digest := CalcSHA512(FinBuf, SizeOf(FinBuf));
  SecureClear(FinBuf, SizeOf(FinBuf));
end;

function CalcHMAC_SHA512(const Key: Pointer; const KeySize: Integer; const Buf; const BufSize: Integer): T512BitDigest;
var I, J : Integer;
    P    : PByte;
    K    : T1024BitBuf;
begin
  HMAC_SHA512Init(Key, KeySize, Result, K);
  P := @Buf;
  if BufSize <= 0 then
    I := 0 else
    I := BufSize;
  J := (I div 128) * 128;
  if J > 0 then
    begin
      HMAC_SHA512Buf(Result, P^, J);
      Inc(P, J);
      Dec(I, J);
    end;
  HMAC_SHA512FinalBuf(K, Result, P^, I, BufSize);
  SecureClear1024(K);
end;

function CalcHMAC_SHA512(const Key: RawByteString; const Buf; const BufSize: Integer): T512BitDigest;
begin
  Result := CalcHMAC_SHA512(Pointer(Key), Length(Key), Buf, BufSize);
end;

function CalcHMAC_SHA512(const Key, Buf: RawByteString): T512BitDigest;
begin
  Result := CalcHMAC_SHA512(Key, Pointer(Buf)^, Length(Buf));
end;


(*


{                                                                              }
{ Fuch512                                                                      }
{   Fundamentals adaptive complexity hash                                      }
{                                                                              }
const
  FUCH512_MaxComplexity = $FF;

type
  TFuch512State = record
    Complexity : Byte;
    State      : array[0..15] of T512BitDigest;
    Digest     : T512BitDigest;
  end;

procedure Fuch512Digest_ExpandKey(
          var Digest: T512BitDigest;
          const Key: Pointer; const KeySize: Integer;
          const Complexity: Byte;
          const IterationIdx: Integer);
var P, Q : PByte;
    I : Integer;
    N : Byte;
begin
  Assert(Assigned(Key));
  Assert(KeySize >= 0);
  Assert(IterationIdx <= 15);
  // xor digest with key size, complexity value, iteration idx and key data
  Digest.Longs[0] := LongWord(KeySize);
  Digest.Bytes[5] := Complexity;
  Digest.Bytes[6] := Byte(IterationIdx and $FF);
  Q := Key;
  for I := 0 to KeySize - 1 do
    begin
      N := (I  + 6) mod 64;
      P := @Digest.Bytes[N];
      P^ := P^ xor Q^;
      Inc(Q);
    end;
end;

procedure Fuch512_ExpandKey(
          var State: TFuch512State;
          const Key: Pointer; const KeySize: Integer;
          const Complexity: Byte);
var I : Integer;
begin
  // expand key
  for I := 0 to 15 do
    Fuch512Digest_ExpandKey(State.State[I], Key, KeySize, Complexity, I);
  // obfuscate
  for I := 0 to 15 do
    Digest512XOR32(State.State[I], SHA512K[I]);
  // obfuscate more
  Digest512XOR32(State.State[0],  CalcCRC32(Key^, KeySize));            // CRC32 of key
  Digest512XOR32(State.State[1],  CRC32Table[Byte(KeySize mod 256)]);   // CRC32 of key size
  Digest512XOR32(State.State[2],  CRC32Table[Byte(KeySize mod 3)]);     // CRC32 of key size
  Digest512XOR32(State.State[3],  CRC32Table[Byte(KeySize mod 23)]);    // CRC32 of key size
  Digest512XOR32(State.State[4],  CRC32Table[Byte(KeySize mod 251)]);   // CRC32 of key size
  Digest512XOR32(State.State[5],  CRC32Table[Complexity]);              // CRC32 of complexity value
  Digest512XOR32(State.State[6],  SHA512K[16 + (KeySize mod 3)]);       // modified key size
  Digest512XOR32(State.State[7],  SHA512K[19 + (KeySize mod 5)]);       // modified key size
  Digest512XOR32(State.State[8],  SHA512K[24 + (KeySize mod 7)]);       // modified key size
  Digest512XOR32(State.State[9],  SHA512K[31 + (KeySize mod 33)]);      // modified key size
  Digest512XOR32(State.State[10], SHA512K[64 + (Complexity mod 32)]);   // modified complexity value
  Digest512XOR32(State.State[11], MD5Table_1[KeySize mod 3]);           // modified key size
  Digest512XOR32(State.State[12], MD5Table_1[KeySize mod 5]);           // modified key size
  Digest512XOR32(State.State[13], MD5Table_1[KeySize mod 16]);          // modified key size
  Digest512XOR32(State.State[14], MD5Table_2[Complexity mod 16]);       // modified complexity
  Digest512XOR32(State.State[15], MD5Table_2[Complexity mod 11]);       // modified complexity
end;

procedure Fuch512_Init(
          var State: TFuch512State;
          const Key: Pointer; const KeySize: Integer;
          const Complexity: Byte);
begin
  FillChar(State, SizeOf(State), 0);
  State.Complexity := Complexity;
  SHA512InitDigest(State.Digest);
  Fuch512_ExpandKey(State, Key, KeySize, Complexity);
  // Post condition:
  //   State.Digest = fixed seed
  //   State.State  = obfuscated key
end;

procedure Fuch512_Block(
          var State: TFuch512State;
          const Buf: T512BitBuf);
var Dig : T512BitDigest;
    I : Integer;
begin
  // hash state
  Dig := CalcSHA512(State.State, SizeOf(State.State));
  for I := 0 to 14 do
    State.State[I] := State.State[I + 1];
  State.State[15] := Dig;
  // hash buffer
  Dig := CalcSHA512(Buf, SizeOf(Buf));
  for I := 0 to 14 do
    State.State[I] := State.State[I + 1];
  State.State[15] := Dig;

  // hash state
  State.Digest := CalcSHA512(State.State, SizeOf(State.State));
end;

procedure Fuch512_Buf(
          var State: TFuch512State;
          const Buf; const BufSize: Integer);
begin
end;

procedure Fuch512_FinalBuf(
          var State: TFuch512State;
          const Buf; const BufSize: Integer);
begin
end;

*)




{                                                                              }
{ CalculateHash                                                                }
{                                                                              }
procedure CalculateHash(const HashType: THashType;
          const Buf; const BufSize: Integer;
          const Digest: Pointer;
          const Key: Pointer; const KeySize: Integer);
begin
  if KeySize > 0 then
    case HashType of
      hashHMAC_MD5    : P128BitDigest(Digest)^ := CalcHMAC_MD5(Key, KeySize, Buf, BufSize);
      hashHMAC_SHA1   : P160BitDigest(Digest)^ := CalcHMAC_SHA1(Key, KeySize, Buf, BufSize);
      hashHMAC_SHA256 : P256BitDigest(Digest)^ := CalcHMAC_SHA256(Key, KeySize, Buf, BufSize);
      hashHMAC_SHA512 : P512BitDigest(Digest)^ := CalcHMAC_SHA512(Key, KeySize, Buf, BufSize);
    else
      raise EHashError.Create(hashNotKeyedHashType);
    end
  else
    case HashType of
      hashChecksum32  : PLongWord(Digest)^     := CalcChecksum32(Buf, BufSize);
      hashXOR8        : PByte(Digest)^         := CalcXOR8(Buf, BufSize);
      hashXOR16       : PWord(Digest)^         := CalcXOR16(Buf, BufSize);
      hashXOR32       : PLongWord(Digest)^     := CalcXOR32(Buf, BufSize);
      hashCRC16       : PWord(Digest)^         := CalcCRC16(Buf, BufSize);
      hashCRC32       : PLongWord(Digest)^     := CalcCRC32(Buf, BufSize);
      hashMD5         : P128BitDigest(Digest)^ := CalcMD5(Buf, BufSize);
      hashSHA1        : P160BitDigest(Digest)^ := CalcSHA1(Buf, BufSize);
      hashSHA256      : P256BitDigest(Digest)^ := CalcSHA256(Buf, BufSize);
      hashSHA512      : P512BitDigest(Digest)^ := CalcSHA512(Buf, BufSize);
      hashRipeMD160   : P160BitDigest(Digest)^ := CalcRipeMD160(Buf, BufSize);
      hashHMAC_MD5    : P128BitDigest(Digest)^ := CalcHMAC_MD5(nil, 0, Buf, BufSize);
      hashHMAC_SHA1   : P160BitDigest(Digest)^ := CalcHMAC_SHA1(nil, 0, Buf, BufSize);
      hashHMAC_SHA256 : P256BitDigest(Digest)^ := CalcHMAC_SHA256(nil, 0, Buf, BufSize);
      hashHMAC_SHA512 : P512BitDigest(Digest)^ := CalcHMAC_SHA512(nil, 0, Buf, BufSize);
    else
      raise EHashError.Create(hashInvalidHashType);
    end;
end;

procedure CalculateHash(const HashType: THashType; const Buf; const BufSize: Integer; const Digest: Pointer; const Key: RawByteString);
begin
  CalculateHash(HashType, Buf, BufSize, Digest, Pointer(Key), Length(Key));
end;

procedure CalculateHash(const HashType: THashType; const Buf: RawByteString; const Digest: Pointer; const Key: RawByteString);
begin
  CalculateHash(HashType, Pointer(Buf)^, Length(Buf), Digest, Key);
end;



{                                                                              }
{ System helper functions                                                      }
{                                                                              }
resourcestring
  SSystemError = 'System error #%s';

{$IFDEF MSWIN}
{$IFDEF StringIsUnicode}
function GetLastOSErrorMessage: String;
const MAX_ERRORMESSAGE_LENGTH = 256;
var Err: LongWord;
    Buf: array[0..MAX_ERRORMESSAGE_LENGTH - 1] of Word;
    Len: LongWord;
begin
  Err := Windows.GetLastError;
  FillChar(Buf, Sizeof(Buf), #0);
  Len := Windows.FormatMessageW(FORMAT_MESSAGE_FROM_SYSTEM, nil, Err, 0,
      @Buf, MAX_ERRORMESSAGE_LENGTH, nil);
  if Len = 0 then
    Result := Format(SSystemError, [IntToStr(Err)])
  else
    Result := StrPas(PWideChar(@Buf));
end;
{$ELSE}
function GetLastOSErrorMessage: String;
const MAX_ERRORMESSAGE_LENGTH = 256;
var Err: LongWord;
    Buf: array[0..MAX_ERRORMESSAGE_LENGTH - 1] of Byte;
    Len: LongWord;
begin
  Err := Windows.GetLastError;
  FillChar(Buf, Sizeof(Buf), #0);
  Len := Windows.FormatMessageA(FORMAT_MESSAGE_FROM_SYSTEM, nil, Err, 0,
      @Buf, MAX_ERRORMESSAGE_LENGTH, nil);
  if Len = 0 then
    Result := Format(SSystemError, [IntToStr(Err)])
  else
    Result := StrPas(PAnsiChar(@Buf));
end;
{$ENDIF}
{$ELSE}
{$IFDEF UNIX}
{$IFDEF FREEPASCAL}
function GetLastOSErrorMessage: String;
begin
  Result := SysErrorMessage(GetLastOSError);
end;
{$ELSE}
function GetLastOSErrorMessage: String;
var Err: LongWord;
    Buf: array[0..1023] of AnsiChar;
begin
  Err := BaseUnix.fpgeterrno;
  FillChar(Buf, Sizeof(Buf), #0);
  libc.strerror_r(Err, @Buf, SizeOf(Buf));
  if Buf[0] = #0 then
    Result := Format(SSystemError, [IntToStr(Err)])
  else
    Result := StrPas(@Buf);
end;
{$ENDIF}{$ENDIF}{$ENDIF}



{                                                                              }
{ AHash                                                                        }
{                                                                              }
class function AHash.BlockSize: Integer;
begin
  Result := -1;
end;

procedure AHash.ProcessFinalBuf(const Buf; const BufSize: Integer; const TotalSize: Int64);
begin
  ProcessBuf(Buf, BufSize);
end;

procedure AHash.Init(const Digest: Pointer; const Key: Pointer; const KeySize: Integer);
begin
  Assert(Assigned(Digest));
  FDigest := Digest;
  FTotalSize := 0;
  InitHash(Digest, Key, KeySize);
end;

procedure AHash.Init(const Digest: Pointer; const Key: RawByteString);
begin
  Init(Digest, Pointer(Key), Length(Key));
end;

procedure AHash.HashBuf(const Buf; const BufSize: Integer; const FinalBuf: Boolean);
var I, D : Integer;
    P : PAnsiChar;
begin
  Inc(FTotalSize, BufSize);

  D := BlockSize;
  if D < 0 then
    D := 64;
  P := @Buf;
  I := (BufSize div D) * D;
  if I > 0 then
    begin
      ProcessBuf(P^, I);
      Inc(P, I);
    end;

  I := BufSize mod D;
  if FinalBuf then
    ProcessFinalBuf(P^, I, FTotalSize)
  else
    if I > 0 then
      raise EHashError.Create(hashInvalidBufferSize, 'Non final buffer must be multiple of block size');
end;

procedure AHash.HashFile(const FileName: String; const Offset: Int64; const MaxCount: Int64);
const ChunkSize = 8192;
var Handle : Integer;
    Buf    : Pointer;
    I, C   : Integer;
    Left   : Int64;
    Fin    : Boolean;
begin
  if FileName = '' then
    raise EHashError.Create(hashInvalidFileName);
  Handle := FileOpen(FileName, fmOpenReadWrite or fmShareDenyNone);
  if Handle = -1 then
    raise EHashError.Create(hashFileOpenError, GetLastOSErrorMessage);
  if Offset > 0 then
    I := FileSeek(Handle, Offset, 0) else
  if Offset < 0 then
    I := FileSeek(Handle, Offset, 2) else
    I := 0;
  if I = -1 then
    raise EHashError.Create(hashFileSeekError, GetLastOSErrorMessage);
  try
    GetMem(Buf, ChunkSize);
    try
      if MaxCount < 0 then
        Left := High(Int64) else
        Left := MaxCount;
      repeat
        if Left > ChunkSize then
          C := ChunkSize else
          C := Left;
        if C = 0 then
          begin
            I := 0;
            Fin := True;
          end else
          begin
            I := FileRead(Handle, Buf^, C);
            if I = -1 then
              raise EHashError.Create(hashFileReadError, GetLastOSErrorMessage);
            Dec(Left, I);
            Fin := (I < C) or (Left <= 0);
          end;
        HashBuf(Buf^, I, Fin);
      until Fin;
    finally
      FreeMem(Buf, ChunkSize);
    end;
  finally
    FileClose(Handle);
  end;
end;



{                                                                              }
{ TChecksum32Hash                                                              }
{                                                                              }
procedure TChecksum32Hash.InitHash(const Digest: Pointer; const Key: Pointer; const KeySize: Integer);
begin
  PLongWord(Digest)^ := 0;
end;

procedure TChecksum32Hash.ProcessBuf(const Buf; const BufSize: Integer);
begin
  PLongWord(FDigest)^ := PLongWord(FDigest)^ + CalcChecksum32(Buf, BufSize);
end;

class function TChecksum32Hash.DigestSize: Integer;
begin
  Result := 4;
end;



{                                                                              }
{ TXOR8Hash                                                                    }
{                                                                              }
procedure TXOR8Hash.InitHash(const Digest: Pointer; const Key: Pointer; const KeySize: Integer);
begin
  PByte(Digest)^ := 0;
end;

procedure TXOR8Hash.ProcessBuf(const Buf; const BufSize: Integer);
begin
  PByte(FDigest)^ := PByte(FDigest)^ xor CalcXOR8(Buf, BufSize);
end;

class function TXOR8Hash.DigestSize: Integer;
begin
  Result := 1;
end;



{                                                                              }
{ TXOR16Hash                                                                   }
{                                                                              }
procedure TXOR16Hash.InitHash(const Digest: Pointer; const Key: Pointer; const KeySize: Integer);
begin
  PWord(Digest)^ := 0;
end;

procedure TXOR16Hash.ProcessBuf(const Buf; const BufSize: Integer);
begin
  PWord(FDigest)^ := PWord(FDigest)^ xor CalcXOR16(Buf, BufSize);
end;

class function TXOR16Hash.DigestSize: Integer;
begin
  Result := 2;
end;



{                                                                              }
{ TXOR32Hash                                                                   }
{                                                                              }
procedure TXOR32Hash.InitHash(const Digest: Pointer; const Key: Pointer; const KeySize: Integer);
begin
  PLongWord(Digest)^ := 0;
end;

procedure TXOR32Hash.ProcessBuf(const Buf; const BufSize: Integer);
begin
  PLongWord(FDigest)^ := PLongWord(FDigest)^ xor CalcXOR32(Buf, BufSize);
end;

class function TXOR32Hash.DigestSize: Integer;
begin
  Result := 4;
end;



{                                                                              }
{ TCRC16Hash                                                                   }
{                                                                              }
procedure TCRC16Hash.InitHash(const Digest: Pointer; const Key: Pointer; const KeySize: Integer);
begin
  CRC16Init(PWord(Digest)^);
end;

procedure TCRC16Hash.ProcessBuf(const Buf; const BufSize: Integer);
begin
  PWord(FDigest)^ := CRC16Buf(PWord(FDigest)^, Buf, BufSize);
end;

class function TCRC16Hash.DigestSize: Integer;
begin
  Result := 2;
end;



{                                                                              }
{ TCRC32Hash                                                                   }
{                                                                              }
procedure TCRC32Hash.InitHash(const Digest: Pointer; const Key: Pointer; const KeySize: Integer);
begin
  CRC32Init(PLongWord(Digest)^);
end;

procedure TCRC32Hash.ProcessBuf(const Buf; const BufSize: Integer);
begin
  PLongWord(FDigest)^ := CRC32Buf(PLongWord(FDigest)^, Buf, BufSize);
end;

class function TCRC32Hash.DigestSize: Integer;
begin
  Result := 4;
end;


{                                                                              }
{ TAdler32Hash                                                                 }
{                                                                              }
procedure TAdler32Hash.InitHash(const Digest: Pointer; const Key: Pointer; const KeySize: Integer);
begin
  Adler32Init(PLongWord(Digest)^);
end;

procedure TAdler32Hash.ProcessBuf(const Buf; const BufSize: Integer);
begin
  PLongWord(FDigest)^ := Adler32Buf(PLongWord(FDigest)^, Buf, BufSize);
end;

class function TAdler32Hash.DigestSize: Integer;
begin
  Result := 4;
end;



{                                                                              }
{ TELFHash                                                                     }
{                                                                              }
procedure TELFHash.InitHash(const Digest: Pointer; const Key: Pointer; const KeySize: Integer);
begin
  ELFInit(PLongWord(Digest)^);
end;

procedure TELFHash.ProcessBuf(const Buf; const BufSize: Integer);
begin
  PLongWord(FDigest)^ := ELFBuf(PLongWord(FDigest)^, Buf, BufSize);
end;

class function TELFHash.DigestSize: Integer;
begin
  Result := 4;
end;



{                                                                              }
{ TMD5Hash                                                                     }
{                                                                              }
procedure TMD5Hash.InitHash(const Digest: Pointer; const Key: Pointer; const KeySize: Integer);
begin
  MD5InitDigest(P128BitDigest(FDigest)^);
end;

procedure TMD5Hash.ProcessBuf(const Buf; const BufSize: Integer);
begin
  MD5Buf(P128BitDigest(FDigest)^, Buf, BufSize);
end;

procedure TMD5Hash.ProcessFinalBuf(const Buf; const BufSize: Integer; const TotalSize: Int64);
begin
  MD5FinalBuf(P128BitDigest(FDigest)^, Buf, BufSize, TotalSize);
end;

class function TMD5Hash.DigestSize: Integer;
begin
  Result := 16;
end;

class function TMD5Hash.BlockSize: Integer;
begin
  Result := 64;
end;



{                                                                              }
{ TSHA1Hash                                                                    }
{                                                                              }
procedure TSHA1Hash.InitHash(const Digest: Pointer; const Key: Pointer; const KeySize: Integer);
begin
  SHA1InitDigest(P160BitDigest(FDigest)^);
end;

procedure TSHA1Hash.ProcessBuf(const Buf; const BufSize: Integer);
begin
  SHA1Buf(P160BitDigest(FDigest)^, Buf, BufSize);
end;

procedure TSHA1Hash.ProcessFinalBuf(const Buf; const BufSize: Integer; const TotalSize: Int64);
begin
  SHA1FinalBuf(P160BitDigest(FDigest)^, Buf, BufSize, TotalSize);
end;

class function TSHA1Hash.DigestSize: Integer;
begin
  Result := 20;
end;

class function TSHA1Hash.BlockSize: Integer;
begin
  Result := 64;
end;



{                                                                              }
{ TSHA256Hash                                                                  }
{                                                                              }
procedure TSHA256Hash.InitHash(const Digest: Pointer; const Key: Pointer; const KeySize: Integer);
begin
  SHA256InitDigest(P256BitDigest(FDigest)^);
end;

procedure TSHA256Hash.ProcessBuf(const Buf; const BufSize: Integer);
begin
  SHA256Buf(P256BitDigest(FDigest)^, Buf, BufSize);
end;

procedure TSHA256Hash.ProcessFinalBuf(const Buf; const BufSize: Integer; const TotalSize: Int64);
begin
  SHA256FinalBuf(P256BitDigest(FDigest)^, Buf, BufSize, TotalSize);
end;

class function TSHA256Hash.DigestSize: Integer;
begin
  Result := 32;
end;

class function TSHA256Hash.BlockSize: Integer;
begin
  Result := 64;
end;



{                                                                              }
{ TSHA512Hash                                                                  }
{                                                                              }
procedure TSHA512Hash.InitHash(const Digest: Pointer; const Key: Pointer; const KeySize: Integer);
begin
  SHA512InitDigest(P512BitDigest(FDigest)^);
end;

procedure TSHA512Hash.ProcessBuf(const Buf; const BufSize: Integer);
begin
  SHA512Buf(P512BitDigest(FDigest)^, Buf, BufSize);
end;

procedure TSHA512Hash.ProcessFinalBuf(const Buf; const BufSize: Integer; const TotalSize: Int64);
begin
  SHA512FinalBuf(P512BitDigest(FDigest)^, Buf, BufSize, TotalSize);
end;

class function TSHA512Hash.DigestSize: Integer;
begin
  Result := 64;
end;

class function TSHA512Hash.BlockSize: Integer;
begin
  Result := 128;
end;



{                                                                              }
{ TRipeMD160Hash                                                               }
{                                                                              }
procedure TRipeMD160Hash.InitHash(const Digest: Pointer; const Key: Pointer; const KeySize: Integer);
begin
  RipeMD160InitDigest(P160BitDigest(FDigest)^);
end;

procedure TRipeMD160Hash.ProcessBuf(const Buf; const BufSize: Integer);
begin
  RipeMD160Buf(P160BitDigest(FDigest)^, Buf, BufSize);
end;

procedure TRipeMD160Hash.ProcessFinalBuf(const Buf; const BufSize: Integer; const TotalSize: Int64);
begin
  RipeMD160FinalBuf(P160BitDigest(FDigest)^, Buf, BufSize, TotalSize);
end;

class function TRipeMD160Hash.DigestSize: Integer;
begin
  Result := 20;
end;

class function TRipeMD160Hash.BlockSize: Integer;
begin
  Result := 64;
end;



{                                                                              }
{ THMAC_MD5Hash                                                                }
{                                                                              }
destructor THMAC_MD5Hash.Destroy;
begin
  SecureClear512(FKey);
  inherited Destroy;
end;

procedure THMAC_MD5Hash.InitHash(const Digest: Pointer; const Key: Pointer; const KeySize: Integer);
begin
  HMAC_MD5Init(Key, KeySize, P128BitDigest(FDigest)^, FKey);
end;

procedure THMAC_MD5Hash.ProcessBuf(const Buf; const BufSize: Integer);
begin
  HMAC_MD5Buf(P128BitDigest(FDigest)^, Buf, BufSize);
end;

procedure THMAC_MD5Hash.ProcessFinalBuf(const Buf; const BufSize: Integer; const TotalSize: Int64);
begin
  HMAC_MD5FinalBuf(FKey, P128BitDigest(FDigest)^, Buf, BufSize, TotalSize);
end;

class function THMAC_MD5Hash.DigestSize: Integer;
begin
  Result := 16;
end;

class function THMAC_MD5Hash.BlockSize: Integer;
begin
  Result := 64;
end;



{                                                                              }
{ THMAC_SHA1Hash                                                               }
{                                                                              }
destructor THMAC_SHA1Hash.Destroy;
begin
  SecureClear512(FKey);
  inherited Destroy;
end;

procedure THMAC_SHA1Hash.InitHash(const Digest: Pointer; const Key: Pointer; const KeySize: Integer);
begin
  HMAC_SHA1Init(Key, KeySize, P160BitDigest(FDigest)^, FKey);
end;

procedure THMAC_SHA1Hash.ProcessBuf(const Buf; const BufSize: Integer);
begin
  HMAC_SHA1Buf(P160BitDigest(FDigest)^, Buf, BufSize);
end;

procedure THMAC_SHA1Hash.ProcessFinalBuf(const Buf; const BufSize: Integer; const TotalSize: Int64);
begin
  HMAC_SHA1FinalBuf(FKey, P160BitDigest(FDigest)^, Buf, BufSize, TotalSize);
end;

class function THMAC_SHA1Hash.DigestSize: Integer;
begin
  Result := 20;
end;

class function THMAC_SHA1Hash.BlockSize: Integer;
begin
  Result := 64;
end;



{                                                                              }
{ THMAC_SHA256Hash                                                             }
{                                                                              }
destructor THMAC_SHA256Hash.Destroy;
begin
  SecureClear512(FKey);
  inherited Destroy;
end;

procedure THMAC_SHA256Hash.InitHash(const Digest: Pointer; const Key: Pointer; const KeySize: Integer);
begin
  HMAC_SHA256Init(Key, KeySize, P256BitDigest(FDigest)^, FKey);
end;

procedure THMAC_SHA256Hash.ProcessBuf(const Buf; const BufSize: Integer);
begin
  HMAC_SHA256Buf(P256BitDigest(FDigest)^, Buf, BufSize);
end;

procedure THMAC_SHA256Hash.ProcessFinalBuf(const Buf; const BufSize: Integer; const TotalSize: Int64);
begin
  HMAC_SHA256FinalBuf(FKey, P256BitDigest(FDigest)^, Buf, BufSize, TotalSize);
end;

class function THMAC_SHA256Hash.DigestSize: Integer;
begin
  Result := 32;
end;

class function THMAC_SHA256Hash.BlockSize: Integer;
begin
  Result := 64;
end;



{                                                                              }
{ THMAC_SHA512Hash                                                             }
{                                                                              }
destructor THMAC_SHA512Hash.Destroy;
begin
  SecureClear1024(FKey);
  inherited Destroy;
end;

procedure THMAC_SHA512Hash.InitHash(const Digest: Pointer; const Key: Pointer; const KeySize: Integer);
begin
  HMAC_SHA512Init(Key, KeySize, P512BitDigest(FDigest)^, FKey);
end;

procedure THMAC_SHA512Hash.ProcessBuf(const Buf; const BufSize: Integer);
begin
  HMAC_SHA512Buf(P512BitDigest(FDigest)^, Buf, BufSize);
end;

procedure THMAC_SHA512Hash.ProcessFinalBuf(const Buf; const BufSize: Integer; const TotalSize: Int64);
begin
  HMAC_SHA512FinalBuf(FKey, P512BitDigest(FDigest)^, Buf, BufSize, TotalSize);
end;

class function THMAC_SHA512Hash.DigestSize: Integer;
begin
  Result := 64;
end;

class function THMAC_SHA512Hash.BlockSize: Integer;
begin
  Result := 128;
end;



{                                                                              }
{ HashString                                                                   }
{                                                                              }
function HashString(const StrBuf: Pointer; const StrLength: Integer; const Slots: LongWord; const CaseSensitive: Boolean): LongWord;
var P    : PAnsiChar;
    I, J : Integer;

  procedure CRC32StrBuf(const Size: Integer);
  begin
    if CaseSensitive then
      Result := CRC32Buf(Result, P^, Size)
    else
      Result := CRC32BufNoCase(Result, P^, Size);
  end;

begin
  // Return 0 for an empty string
  Result := 0;
  if (StrLength <= 0) or not Assigned(StrBuf) then
    exit;

  if not CRC32TableInit then
    InitCRC32Table;
  Result := $FFFFFFFF;
  P := StrBuf;

  if StrLength <= 48 then // Hash everything for short strings
    CRC32StrBuf(StrLength)
  else
    begin
      // Hash first 16 bytes
      CRC32StrBuf(16);

      // Hash last 16 bytes
      Inc(P, StrLength - 16);
      CRC32StrBuf(16);

      // Hash 16 bytes sampled from rest of string
      I := (StrLength - 48) div 16;
      P := StrBuf;
      Inc(P, 16);
      for J := 1 to 16 do
        begin
          CRC32StrBuf(1);
          Inc(P, I + 1);
        end;
    end;

  // Mod into slots
  if (Slots <> 0) and (Slots <> High(LongWord)) then
    Result := Result mod Slots;
end;

function HashString(const S: RawByteString; const Slots: LongWord; const CaseSensitive: Boolean): LongWord;
begin
  Result := HashString(Pointer(S), Length(S), Slots, CaseSensitive);
end;



{                                                                              }
{ Hash by THashType                                                            }
{                                                                              }
const
  HashTypeClasses : array[THashType] of THashClass = (
      TChecksum32Hash, TXOR8Hash, TXOR16Hash, TXOR32Hash,
      TCRC16Hash, TCRC32Hash,
      TAdler32Hash,
      TELFHash,
      TMD5Hash, TSHA1Hash, TSHA256Hash, TSHA512Hash, TRipeMD160Hash,
      THMAC_MD5Hash, THMAC_SHA1Hash, THMAC_SHA256Hash, THMAC_SHA512Hash);

function GetHashClassByType(const HashType: THashType): THashClass;
begin
  Result := HashTypeClasses[HashType];
end;

function GetDigestSize(const HashType: THashType): Integer;
begin
  Result := GetHashClassByType(HashType).DigestSize;
end;



{                                                                              }
{ Self testing code                                                            }
{                                                                              }
{$IFDEF HASH_SELFTEST}
{$ASSERTIONS ON}
procedure SelfTest;
const
  QuickBrownFoxStr = 'The quick brown fox jumps over the lazy dog';
var
  MillionA, TenThousandA : RawByteString;
  S, T : RawByteString;
  U : WideString;
begin
  SetLength(S, 5);
  FillChar(S[1], 5, #1);
  SecureClearStrA(S);
  Assert(S = '');

  SetLength(U, 5);
  FillChar(U[1], 10, #1);
  SecureClearStrW(U);
  Assert(U = '');

  S := 'ABC';
  SecureClearStrA(S);

  U := 'ABC';
  SecureClearStrW(U);

  SetLength(MillionA, 1000000);
  FillChar(MillionA[1], 1000000, Ord('a'));
  SetLength(TenThousandA, 10000);
  FillChar(TenThousandA[1], 10000, Ord('a'));

  Assert(CalcChecksum32('') = 0);
  Assert(CalcChecksum32('A') = 65);
  Assert(CalcChecksum32('Fundamentals') = 1250);

  Assert(CalcXOR8('') = 0);
  Assert(CalcXOR8('A') = 65);
  Assert(CalcXOR8('Fundamentals') = 52);

  Assert(CalcXOR16('') = 0);
  Assert(CalcXOR16('A') = 65);
  Assert(CalcXOR16('AB') = $4241);
  Assert(CalcXOR16('what do ya want for nothing?') = $1915);
  Assert(CalcXOR16('Fundamentals') = $0034);

  Assert(CalcXOR32('') = 0);
  Assert(CalcXOR32('A') = 65);
  Assert(CalcXOR32('ABCD') = $44434241);
  Assert(CalcXOR32('what do ya want for nothing?') = $743B6D2E);
  Assert(CalcXOR32('Fundamentals')= $79677953);

  Assert(CalcCRC16('') = $FFFF);
  Assert(CalcCRC16('what do ya want for nothing?') = $581A);
  Assert(CalcCRC16('Fundamentals') = $0B48);

  Assert(CalcCRC32('') = 0);
  Assert(CalcCRC32('what do ya want for nothing?') = $6BC70A6C);
  Assert(CalcCRC32('Fundamentals') = $C0488691);

  Assert(CalcAdler32('Wikipedia') = $11E60398);

  Assert(IsValidISBN('3880530025'));

  Assert(IsValidLUHN('49927398716'));

  Assert(HashString('Fundamentals', 0, False) = HashString('fundamentalS', 0, False));

  Assert(WideString(MD5DigestToHexA(CalcMD5(''))) = MD5DigestToHexW(CalcMD5('')));
  Assert(MD5DigestToHexA(CalcMD5(''))                    = 'd41d8cd98f00b204e9800998ecf8427e');
  Assert(MD5DigestToHexA(CalcMD5('Delphi Fundamentals')) = 'ea98b65da23d19756d46a36faa481dd8');

  Assert(WideString(SHA1DigestToHexA(CalcSHA1(''))) = SHA1DigestToHexW(CalcSHA1('')));
  Assert(SHA1DigestToHexA(CalcSHA1(''))               = 'da39a3ee5e6b4b0d3255bfef95601890afd80709');
  Assert(SHA1DigestToHexA(CalcSHA1('Fundamentals'))   = '052d8ad81d99f33b2eb06e6d194282b8675fb201');
  Assert(SHA1DigestToHexA(CalcSHA1(QuickBrownFoxStr)) = '2fd4e1c67a2d28fced849ee1bb76e7391b93eb12');
  Assert(SHA1DigestToHexA(CalcSHA1(TenThousandA))     = 'a080cbda64850abb7b7f67ee875ba068074ff6fe');

  Assert(WideString(SHA224DigestToHexA(CalcSHA224(''))) = SHA224DigestToHexW(CalcSHA224('')));
  Assert(SHA224DigestToHexA(CalcSHA224(''))               = 'd14a028c2a3a2bc9476102bb288234c415a2b01f828ea62ac5b3e42f');
  Assert(SHA224DigestToHexA(CalcSHA224('Fundamentals'))   = '1cccba6b3c6b08494733efb3a77fe8baef5bf6eeae89ec303ef4660e');
  Assert(SHA224DigestToHexA(CalcSHA224(QuickBrownFoxStr)) = '730e109bd7a8a32b1cb9d9a09aa2325d2430587ddbc0c38bad911525');
  Assert(SHA224DigestToHexA(CalcSHA224(TenThousandA))     = '00568fba93e8718c2f7dcd82fa94501d59bb1bbcba2c7dc2ba5882db');

  Assert(WideString(SHA256DigestToHexA(CalcSHA256(''))) = SHA256DigestToHexW(CalcSHA256('')));
  Assert(SHA256DigestToHexA(CalcSHA256(''))               = 'e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855');
  Assert(SHA256DigestToHexA(CalcSHA256('Fundamentals'))   = '915ff7435daeac2f66aa866e59bf293f101b79403dbdde2b631fd37fa524f26b');
  Assert(SHA256DigestToHexA(CalcSHA256(QuickBrownFoxStr)) = 'd7a8fbb307d7809469ca9abcb0082e4f8d5651e46d3cdb762d02d0bf37c9e592');
  Assert(SHA256DigestToHexA(CalcSHA256(TenThousandA))     = '27dd1f61b867b6a0f6e9d8a41c43231de52107e53ae424de8f847b821db4b711');
  Assert(SHA256DigestToHexA(CalcSHA256(MillionA))         = 'cdc76e5c9914fb9281a1c7e284d73e67f1809a48a497200e046d39ccc7112cd0');

  Assert(WideString(SHA384DigestToHexA(CalcSHA384(''))) = SHA384DigestToHexW(CalcSHA384('')));
  Assert(SHA384DigestToHexA(CalcSHA384(''))               = '38b060a751ac96384cd9327eb1b1e36a21fdb71114be07434c0cc7bf63f6e1da274edebfe76f65fbd51ad2f14898b95b');
  Assert(SHA384DigestToHexA(CalcSHA384('Fundamentals'))   = 'cf9380b7d2e0237296093a0f5f09066f0cea0742ba752a1e6c60aed92998eda2c86c1549879007a94e9d75a4a7bdb6e8');
  Assert(SHA384DigestToHexA(CalcSHA384(QuickBrownFoxStr)) = 'ca737f1014a48f4c0b6dd43cb177b0afd9e5169367544c494011e3317dbf9a509cb1e5dc1e85a941bbee3d7f2afbc9b1');
  Assert(SHA384DigestToHexA(CalcSHA384(TenThousandA))     = '2bca3b131bb7e922bcd1de98c44786d32e6b6b2993e69c4987edf9dd49711eb501f0e98ad248d839f6bf9e116e25a97c');

  Assert(WideString(SHA512DigestToHexA(CalcSHA512(''))) = SHA512DigestToHexW(CalcSHA512('')));
  Assert(SHA512DigestToHexA(CalcSHA512(''))               = 'cf83e1357eefb8bdf1542850d66d8007d620e4050b5715dc83f4a921d36ce9ce47d0d13c5d85f2b0ff8318d2877eec2f63b931bd47417a81a538327af927da3e');
  Assert(SHA512DigestToHexA(CalcSHA512('Fundamentals'))   = 'f430fed95ff285843bc68a5e2a1ad8275d7c242a504a5d0b23deb7f8252774a132c3672aeeffa9bf5c25449e8905cdb6f89097a3c88f20a6e0d8945bf4310dd6');
  Assert(SHA512DigestToHexA(CalcSHA512(QuickBrownFoxStr)) = '07e547d9586f6a73f73fbac0435ed76951218fb7d0c8d788a309d785436bbb642e93a252a954f23912547d1e8a3b5ed6e1bfd7097821233fa0538f3db854fee6');
  Assert(SHA512DigestToHexA(CalcSHA512(TenThousandA))     = '0593036f4f479d2eb8078ca26b1d59321a86bdfcb04cb40043694f1eb0301b8acd20b936db3c916ebcc1b609400ffcf3fa8d569d7e39293855668645094baf0e');

  Assert(MD5DigestToHexA(CalcHMAC_MD5('', ''))                    = '74e6f7298a9c2d168935f58c001bad88');
  Assert(MD5DigestToHexA(CalcHMAC_MD5('', 'Delphi Fundamentals')) = 'b9da02d5f94bd6eac410708a72b05d9f');
  Assert(MD5DigestToHexA(CalcHMAC_MD5('Delphi Fundamentals', '')) = 'a09f3300c236156d27f4d031db7e91ce');
  Assert(MD5DigestToHexA(CalcHMAC_MD5('Delphi', 'Fundamentals'))  = '1c4e8a481c2c781eb43ca58d9324c37d');

  Assert(SHA1DigestToHexA(CalcHMAC_SHA1('', ''))                           = 'fbdb1d1b18aa6c08324b7d64b71fb76370690e1d');
  Assert(SHA1DigestToHexA(CalcHMAC_SHA1('', QuickBrownFoxStr))             = '2ba7f707ad5f187c412de3106583c3111d668de8');
  Assert(SHA1DigestToHexA(CalcHMAC_SHA1('Fundamentals', QuickBrownFoxStr)) = '8b52855bbd09842d4ac3e4ff4c574c1f87d63e0b');
  Assert(SHA1DigestToHexA(CalcHMAC_SHA1('Fundamentals', ''))               = '2208ce7279f26fcb90dbc1900019aa9b2b85456a');
  Assert(SHA1DigestToHexA(CalcHMAC_SHA1('Fundamentals', TenThousandA))     = '2f9cf91c82963b54fdbc0a26149be0c1f29746dc');
  Assert(SHA1DigestToHexA(CalcHMAC_SHA1(TenThousandA, TenThousandA))       = 'cf792cef5570b47f3e1272581a5af87e5715defd');

  Assert(SHA256DigestToHexA(CalcHMAC_SHA256('', ''))                           = 'b613679a0814d9ec772f95d778c35fc5ff1697c493715653c6c712144292c5ad');
  Assert(SHA256DigestToHexA(CalcHMAC_SHA256('', QuickBrownFoxStr))             = 'fb011e6154a19b9a4c767373c305275a5a69e8b68b0b4c9200c383dced19a416');
  Assert(SHA256DigestToHexA(CalcHMAC_SHA256('Fundamentals', QuickBrownFoxStr)) = '853b22d0aa389d8123452710b3d09ed7f0b5afe4114896bfeb8cfd8818963146');
  Assert(SHA256DigestToHexA(CalcHMAC_SHA256('Fundamentals', ''))               = '28659c86585404fe0e87255bc9a2244ff1d921d48f9c5f8b12b4b40a064a20a3');
  Assert(SHA256DigestToHexA(CalcHMAC_SHA256('Fundamentals', TenThousandA))     = '42347405bf2a459054bd95af2c48e070275d0d701ee62108b385a6e925c43163');
  Assert(SHA256DigestToHexA(CalcHMAC_SHA256(TenThousandA, TenThousandA))       = '6b7576a741bd2eb2c1c12017d5f4984108ce25a3a427a3d5f52ba93c0ac85e1f');

  Assert(SHA512DigestToHexA(CalcHMAC_SHA512('', ''))                           = 'b936cee86c9f87aa5d3c6f2e84cb5a4239a5fe50480a6ec66b70ab5b1f4ac6730c6c515421b327ec1d69402e53dfb49ad7381eb067b338fd7b0cb22247225d47');
  Assert(SHA512DigestToHexA(CalcHMAC_SHA512('', QuickBrownFoxStr))             = '1de78322e11d7f8f1035c12740f2b902353f6f4ac4233ae455baccdf9f37791566e790d5c7682aad5d3ceca2feff4d3f3fdfd9a140c82a66324e9442b8af71b6');
  Assert(SHA512DigestToHexA(CalcHMAC_SHA512('Fundamentals', QuickBrownFoxStr)) = 'f0352dff9b8984fb5fcfdd95de7f9db3df990723a2d909b99faf8cd4ccb9a5b1b840282c190ad41e521eb662512782bb9bf0fb81589cc101bfdc625914b1d8ed');
  Assert(SHA512DigestToHexA(CalcHMAC_SHA512('Fundamentals', ''))               = 'affa539a93acbb675e638aceb0456806564f19bec219c0b6c61d2cd675c37dc3cb7ef4f14831d9638b23d617e6e5c57f586f1804502e4b0b45027a1ae2b254e1');
  Assert(SHA512DigestToHexA(CalcHMAC_SHA512('Fundamentals', TenThousandA))     = 'd6e309c24d7fab8da9db0382f50051821df6966fb22121cebfbb2a6623e9849e05f3c9aeba1448353faffbc3b0e52e618efee36d22bf06b9117adc42b33892c2');
  Assert(SHA512DigestToHexA(CalcHMAC_SHA512(TenThousandA, TenThousandA))       = 'aacebd574e32713a306598b27583de5e253743dea5d3bd3ed7603fa97e098c9197b76584bf23bb21be242e2dd659626f70a9af68a29e0584890dc3a13480b4a3');

  // Test cases from RFC 2202
  Assert(MD5DigestToHexA(CalcHMAC_MD5('Jefe', 'what do ya want for nothing?')) = '750c783e6ab0b503eaa86e310a5db738');
  SetLength(S, 16); FillChar(Pointer(S)^, 16, #$0B);
  Assert(MD5DigestToHexA(CalcHMAC_MD5(S, 'Hi There')) = '9294727a3638bb1c13f48ef8158bfc9d');
  SetLength(S, 16); FillChar(Pointer(S)^, 16, #$AA);
  SetLength(T, 50); FillChar(Pointer(T)^, 50, #$DD);
  Assert(MD5DigestToHexA(CalcHMAC_MD5(S, T)) = '56be34521d144c88dbb8c733f0e8b3f6');
  SetLength(S, 80); FillChar(Pointer(S)^, 80, #$AA);
  Assert(MD5DigestToHexA(CalcHMAC_MD5(S, 'Test Using Larger Than Block-Size Key and Larger Than One Block-Size Data')) = '6f630fad67cda0ee1fb1f562db3aa53e');

  Assert(SHA1DigestToHexA(CalcHMAC_SHA1('Jefe', 'what do ya want for nothing?')) = 'effcdf6ae5eb2fa2d27416d5f184df9c259a7c79');
  SetLength(S, 20); FillChar(Pointer(S)^, 20, #$0B);
  Assert(SHA1DigestToHexA(CalcHMAC_SHA1(S, 'Hi There')) = 'b617318655057264e28bc0b6fb378c8ef146be00');
  SetLength(S, 80); FillChar(Pointer(S)^, 80, #$AA);
  Assert(SHA1DigestToHexA(CalcHMAC_SHA1(S, 'Test Using Larger Than Block-Size Key - Hash Key First')) = 'aa4ae5e15272d00e95705637ce8a3b55ed402112');

  // Test cases from RFC 4231
  Assert(SHA256DigestToHexA(CalcHMAC_SHA256(#$0b#$0b#$0b#$0b#$0b#$0b#$0b#$0b#$0b#$0b#$0b#$0b#$0b#$0b#$0b#$0b#$0b#$0b#$0b#$0b, 'Hi There')) = 'b0344c61d8db38535ca8afceaf0bf12b881dc200c9833da726e9376c2e32cff7');
  Assert(SHA256DigestToHexA(CalcHMAC_SHA256('Jefe', 'what do ya want for nothing?')) = '5bdcc146bf60754e6a042426089575c75a003f089d2739839dec58b964ec3843');
  SetLength(S, 131); FillChar(Pointer(S)^, 131, #$aa);
  Assert(SHA256DigestToHexA(CalcHMAC_SHA256(S, 'This is a test using a larger than block-size key and a larger than block-size data. The key needs to be hashed before being used by the HMAC algorithm.')) = '9b09ffa71b942fcb27635fbcd5b0e944bfdc63644f0713938a7f51535c3a35e2');
  // see RFC 4231 truncated case --> Assert(SHA256DigestToHex(CalcHMAC_SHA256(#$0c#$0c#$0c#$0c#$0c#$0c#$0c#$0c#$0c#$0c#$0c#$0c#$0c#$0c#$0c#$0c#$0c#$0c#$0c#$0c, 'Test With Truncation')) = 'a3b6167473100ee06e0c796c2955552b', 'CalcHMAC_SHA256');

  Assert(SHA512DigestToHexA(CalcHMAC_SHA512(#$0b#$0b#$0b#$0b#$0b#$0b#$0b#$0b#$0b#$0b#$0b#$0b#$0b#$0b#$0b#$0b#$0b#$0b#$0b#$0b, 'Hi There')) = '87aa7cdea5ef619d4ff0b4241a1d6cb02379f4e2ce4ec2787ad0b30545e17cdedaa833b7d6b8a702038b274eaea3f4e4be9d914eeb61f1702e696c203a126854');
  Assert(SHA512DigestToHexA(CalcHMAC_SHA512('Jefe', 'what do ya want for nothing?')) = '164b7a7bfcf819e2e395fbe73b56e0a387bd64222e831fd610270cd7ea2505549758bf75c05a994a6d034f65f8f0e6fdcaeab1a34d4a6b4b636e070a38bce737');
  SetLength(S, 131); FillChar(Pointer(S)^, 131, #$aa);
  Assert(SHA512DigestToHexA(CalcHMAC_SHA512(S, 'This is a test using a larger than block-size key and a larger than block-size data. The key needs to be hashed before being used by the HMAC algorithm.')) = 'e37b6a775dc87dbaa4dfa9f96e5e3ffddebd71f8867289865df5a32d20cdc944b6022cac3c4982b10d5eeb55c3e4de15134676fb6de0446065c97440fa8c6a58');

  // RipeMD160
  Assert(RipeMD160DigestToHexA(CalcRipeMD160('')) = '9c1185a5c5e9fc54612808977ee8f548b2258d31');
  Assert(RipeMD160DigestToHexA(CalcRipeMD160('a')) = '0bdc9d2d256b3ee9daae347be6f4dc835a467ffe');
  Assert(RipeMD160DigestToHexA(CalcRipeMD160('abc')) = '8eb208f7e05d987a9b044a8e98c6b087f15a0bfc');
  Assert(RipeMD160DigestToHexA(CalcRipeMD160('message digest')) = '5d0689ef49d2fae572b881b123a85ffa21595f36');
  Assert(RipeMD160DigestToHexA(CalcRipeMD160('abcdefghijklmnopqrstuvwxyz')) = 'f71c27109c692c1b56bbdceb5b9d2865b3708dbc');
  Assert(RipeMD160DigestToHexA(CalcRipeMD160('abcdbcdecdefdefgefghfghighijhijkijkljklmklmnlmnomnopnopq')) = '12a053384a9c0c88e405a06c27dcf49ada62eb2b');
  Assert(RipeMD160DigestToHexA(CalcRipeMD160('ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789')) = 'b0e20b6e3116640286ed3a87a5713079b21f5189');
  Assert(RipeMD160DigestToHexA(CalcRipeMD160('12345678901234567890123456789012345678901234567890123456789012345678901234567890')) = '9b752e45573d4b39f4dbd3323cab82bf63326bfb');
  Assert(RipeMD160DigestToHexA(CalcRipeMD160(MillionA)) = '52783243c1697bdbe16d37f97f68f08325dc1528');
  Assert(RipeMD160DigestToHexA(CalcRipeMD160('Fundamentals')) = '0b4dfcb4cf845bee8a53bad703e164b50e8199cc');
  Assert(RipeMD160DigestToHexA(CalcRipeMD160('12345678901234567890123456789012345678901234567890123456789012345678901234567890123456789012345678901234567890123456789')) = 'e5ad452926b1b80e69a8c116748386ed920fd80e');          // 119 bytes
  Assert(RipeMD160DigestToHexA(CalcRipeMD160('123456789012345678901234567890123456789012345678901234567890123456789012345678901234567890123456789012345678901234567890')) = '65aaa2d6fb77e63b02a56ed9eced04fe47da43c1');         // 120 bytes
  Assert(RipeMD160DigestToHexA(CalcRipeMD160('1234567890123456789012345678901234567890123456789012345678901234567890123456789012345678901234567890123456789012345678901234567')) = '5ef3b16743e09d8ac8410d03e72bb2fabb507749');  // 127 bytes
  Assert(RipeMD160DigestToHexA(CalcRipeMD160('12345678901234567890123456789012345678901234567890123456789012345678901234567890123456789012345678901234567890123456789012345678')) = 'e6841f68c8fe1a94cbb8b53d79056d139434b49a'); // 128 bytes
end;
{$ENDIF}



end.


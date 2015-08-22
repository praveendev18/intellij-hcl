package org.intellij.plugins.hcl;
import com.intellij.lexer.*;
import com.intellij.psi.tree.IElementType;
import java.util.EnumSet;
import static org.intellij.plugins.hcl.HCLElementTypes.*;
import static com.intellij.psi.TokenType.BAD_CHARACTER;

@SuppressWarnings({"ALL"})
%%

%public
%class _HCLLexer
%implements FlexLexer
%function advance
%type IElementType
%unicode

EOL="\r\n"|"\r"|"\n"
LINE_WS=[\ \t\f]
WHITE_SPACE=({LINE_WS}|{EOL})+

LINE_COMMENT=("/""/"|"#")[^\r\n]*
BLOCK_COMMENT="/*"([^"*"]|"*"[^/])*("*/")?

NUMBER=-?(0[xX])?[0-9]+(\.[0-9]+)?([eE][-+]?[0-9]+)?
ID=[a-zA-Z\.\-_][0-9a-zA-Z\.\-_]*

TIL_START=(\$\{)
TIL_STOP=(\})

HEREDOC_START="<<"

STRING_ELEMENT=([^\"\'\r\n\$\{\}]|\\[^\r\n])*

%state D_STRING, S_STRING, TIL_EXPRESSION, IN_NUMBER
%state S_HEREDOC_MARKER, S_HEREDOC_LINE
%{
  // This parameters can be getted from capabilities
    private boolean withNumbersWithBytesPostfix;
    private boolean withInterpolationLanguage;

    public _HCLLexer(EnumSet<HCLCapability> capabilities) {
      this((java.io.Reader)null);
      this.withNumbersWithBytesPostfix = capabilities.contains(HCLCapability.NUMBERS_WITH_BYTES_POSTFIX);
      this.withInterpolationLanguage = capabilities.contains(HCLCapability.INTERPOLATION_LANGUAGE);
    }
    enum StringType {
      None, SingleQ, DoubleQ
    }
  // State data
    StringType stringType = StringType.None;
    int stringStart = -1;
    int til = 0;
    int myEOLMark;
    CharSequence myHereDocMarker;

    private void til_inc() {
      til++;
    }
    private int til_dec() {
      assert til > 0;
      til--;
      return til;
    }
    private void push_eol() {
      yypushback(getEOLLength());
    }
    private int getEOLLength() {
      if (yylength() == 0) return 0;
      char last = yycharat(yylength() - 1);
      if (last != '\r' && last != '\n') return 0;
      if ((yylength() > 1) && yycharat(yylength() - 2) == '\r') return 2;
      return 1;
    }
    private IElementType eods() {
      yybegin(YYINITIAL); stringType = StringType.None; zzStartRead = stringStart; return DOUBLE_QUOTED_STRING;
    }
    private IElementType eoss() {
      yybegin(YYINITIAL); stringType = StringType.None; zzStartRead = stringStart; return SINGLE_QUOTED_STRING;
    }
    private IElementType eoil() {
      til=0; return stringType == StringType.SingleQ ? eoss(): eods();
    }
%}

%%

<D_STRING> {
  {TIL_START} { if (withInterpolationLanguage) {til_inc(); yybegin(TIL_EXPRESSION);} }
  \"          { return eods(); }
  {STRING_ELEMENT} {}
  \$ {}
  \{ {}
  \} {}
  \' {}
  {EOL} { push_eol(); return eods(); }
  <<EOF>> { return eods(); }
  [^] { return BAD_CHARACTER; }
}

<S_STRING> {
  {TIL_START} { if (withInterpolationLanguage) {til_inc(); yybegin(TIL_EXPRESSION);} }
  \'          { return eoss(); }
  {STRING_ELEMENT} {}
  \$ {}
  \{ {}
  \} {}
  \" {}
  {EOL} { push_eol(); return eoss(); }
  <<EOF>> { return eoss(); }
  [^] { return BAD_CHARACTER; }
}


<TIL_EXPRESSION> {
  {TIL_START} {til_inc();}
  {TIL_STOP} {if (til_dec() <= 0) yybegin(stringType == StringType.SingleQ ? S_STRING: D_STRING); }
  {STRING_ELEMENT} {}
  \' {}
  \" {}
  \$ {}
  \{ {}
  {EOL} { push_eol(); return eoil(); }
  <<EOF>> { return eoil(); }
  [^] { return BAD_CHARACTER; }
}

<S_HEREDOC_MARKER> {
  ([^\r\n]|\\[^\r\n])+ {EOL}? {
    yypushback(getEOLLength());
    myHereDocMarker = yytext();
    return HD_MARKER;
  }
  {EOL} {
    if (myHereDocMarker == null) {
      yybegin(YYINITIAL);
      return BAD_CHARACTER;
    }
    yybegin(S_HEREDOC_LINE);
//    zzStartRead+=getEOLLength();
    return com.intellij.psi.TokenType.WHITE_SPACE;
  }
  <<EOF>> { yybegin(YYINITIAL); return BAD_CHARACTER; }
}

<S_HEREDOC_LINE> {
  ([^\r\n]|\\[^\r\n])+ {EOL}? {
    int eol = getEOLLength();
    int len = yylength();
    int len_eff = len - eol;
    assert len_eff >= 0;
    if(len_eff == myHereDocMarker.length()
       && yytext().subSequence(0, len_eff).equals(myHereDocMarker)) {
      // End of HereDoc
      yypushback(eol);
      yybegin(YYINITIAL);
      myHereDocMarker = null;
      return HD_MARKER;
    } else {
      return HD_LINE;
    }
  }
  {EOL} { return HD_LINE; }
  <<EOF>> { yybegin(YYINITIAL); return BAD_CHARACTER; }
}

<YYINITIAL>   \"  { stringType = StringType.DoubleQ; stringStart = zzStartRead; yybegin(D_STRING); }
<YYINITIAL>   \'  { stringType = StringType.SingleQ; stringStart = zzStartRead; yybegin(S_STRING); }
<YYINITIAL>   {HEREDOC_START}  { yybegin(S_HEREDOC_MARKER); return HD_START; }

<YYINITIAL> {
  {WHITE_SPACE}               { return com.intellij.psi.TokenType.WHITE_SPACE; }

  "["                         { return L_BRACKET; }
  "]"                         { return R_BRACKET; }
  "{"                         { return L_CURLY; }
  "}"                         { return R_CURLY; }
  ","                         { return COMMA; }
  "="                         { return EQUALS; }
  "true"                      { return TRUE; }
  "false"                     { return FALSE; }
  "null"                      { return NULL; }

  {LINE_COMMENT}              { return LINE_COMMENT; }
  {BLOCK_COMMENT}             { return BLOCK_COMMENT; }
  {NUMBER}                    { if (!withNumbersWithBytesPostfix) return NUMBER;
                                yybegin(IN_NUMBER); yypushback(yylength());}
  {ID}                        { return ID; }

  [^] { return BAD_CHARACTER; }
}

<IN_NUMBER> {
  {NUMBER} ([kKmMgG][bB]?) { yybegin(YYINITIAL); return NUMBER; }
  {NUMBER} { yybegin(YYINITIAL); return NUMBER; }
}

//  XML Tokenization
//  Copyright (c) 2009-2010  Michel Fortin
//
//  Distributed under the Boost Software License, version 1.0.
//  See accompanying file.

/**
 * This module reads and writes tokens from and to XML documents. Tokens are
 * defined for each basic structure you can find in XML.
 * 
 * You can read a document as tokens using the powerful tokenize function
 * which calls user-defined function for each token it encounters. You can also
 * use the generally more convenient XMLForwardRange class to expose a document 
 * as a range of tokens on which you can loop easily.
 *
 * You can write a document by sending tokens to a XMLWriter object.
 *
 * Copyright: 2009-2010, Michel Fortin
 */
module mfr.xmltok;

import mfr.byunit : frontUnit, popFrontUnit;
import mfr.range;

import std.range : front, popFront, empty;
import std.string : text;
import std.variant : Algebraic;


// Uncomment to see an output of all the tokens as they're parsed.
//debug = XMLTokens;

// For debug outputs
debug (XMLTokens) import std.stdio : writeln, writefln;

// Uncomment to activate wstring-based unit tests
//version = TestWChar;


/**
 * Token for regular character data in the document.
 */
struct CharDataToken
{
	/// Actual text value.
	string data;
	
	string toString() { return toXML(this); }
}


/**
 * Token for a comment.
 */
struct CommentToken
{
	/// Text content of the comment.
	string content;
	
	string toString() { return toXML(this); }
}


/**
 * Token for a processing instruction. 
 */
struct PIToken
{
	/// Processor target identifier
	string target;
	/// Text content for the processing instruction
	string content;
	
	string toString() { return toXML(this); }
}


/**
 * Content for a CData section.
 */
struct CDataSectionToken
{
	/// Character data content.
	string content;
	
	string toString() { return toXML(this); }
}


/**
 * Token representing a entity reference.
 * Note: the tokenizer emits a CharDataToken when the entity reference can be 
 * resolved to a character string. Entities in attributes are automaticaly
 * converted to their string value.
 */
struct EntityReferenceToken
{
	/// Character data content.
	string entityName;
	
	string toString() { return toXML(this); }
}


/**
 * Content for an attribute inside an open element tag.
 */
struct AttrToken
{
	/// Attribute's name.
	string name;
	/// Attribute's value.
	string value;
	
	string toString() { return toXML(this); }
}

/**
 * Gives the parsed content of an XML declartion.
 * Note: The tokenizer doesn't parse the XML declaration. You should call for 
 * readXMLDecl first prior calling tokenize.
 */
struct XMLDecl
{
	/// Document's XML version.
	string versionNum = "1.0";
	/// Document's character encoding, if specified.
	string encName;
	/// Indicate whether the document is standalone or not, default to true.
	bool standalone = true;
	
	string toString() { return toXML(this); }
}



enum XmlEncoding
{
	UNKNOWN, UTF8, UTF16_BE, UTF16_LE, UTF32_BE, UTF32_LE, OTHER,
}

private struct XmlEncodingBOM {
	XmlEncoding encoding;
	immutable ubyte[] bom;
}

private immutable XmlEncodingBOM[] xmlEncodingBOMs = 
[
 { XmlEncoding.UTF8,     [0xEF, 0xBB, 0xBF] },
 { XmlEncoding.UTF16_BE, [0xFE, 0xFF] },
 { XmlEncoding.UTF32_BE, [0x00, 0x00, 0xFE, 0xFF] },
 { XmlEncoding.UTF32_LE, [0xFF, 0xFE, 0x00, 0x00] },
 { XmlEncoding.UTF16_LE, [0xFF, 0xFE] },
];

XmlEncoding readBOM(ref immutable(ubyte)[] input)
{
	foreach (bom; xmlEncodingBOMs) {
		if (input.length >= bom.bom.length) {
			if (input[0..bom.bom.length] == bom.bom[]) {
				input = input[bom.bom.length..$];
				return bom.encoding;
			}
		}
	}
	
	// Heuristics checking for the presense of null bytes
	if (input.length >= 2)
	{
		if (input[0] == 0 && input[1] != 0)
			return XmlEncoding.UTF16_BE;
		else if (input[0] != 0 && input[1] == 0)
			return XmlEncoding.UTF16_LE;
	}
	if (input.length >= 4)
	{
		immutable ubyte[] twoZero = [0, 0];
		if (input[0..2] == twoZero[] && input[2..4] != twoZero[])
			return XmlEncoding.UTF32_BE;
		else if (input[0..2] != twoZero[] && input[2..4] == twoZero[])
			return XmlEncoding.UTF32_LE;
	}
	
	return XmlEncoding.UNKNOWN;
}


/**
 * Scan the start of an XML document for an XML declaration and skip it if
 * found.
 * Params:
 *  input = input text for the document
 *   decl = data extracted from the XML declaration, or default values if not found.
 * Returns: true if an XML declaration is found, false otherwise
 */
bool readXMLDecl(CharType)(ref immutable(CharType)[] input, out XMLDecl decl)
{
	if (input.length >= 6 && input[0..5] == "<?xml" && isXMLWhiteSpace(input[5]))
	{
		input = input[6..$];
		
		skipXMLWhitespace(input);
		
		if (!isXMLNameStartChar(input.front))
			throw new Exception("Expected 'version' attribute in"
				" XML declaration.");
		
		auto attr = readXMLAttr(input);
		if (attr.name != "version")
			throw new Exception("Unexpected attribute '" ~ attr.name ~
				"' instead of 'version' in XML declaration.");
		decl.versionNum = attr.value;
		
		skipXMLWhitespace(input);
		if (isXMLNameStartChar(input.front))
		{
			bool standaloneValue(string attrValue)
			{
				switch (attr.value)
				{
				case "yes": return true;
				case "no": return false;
				default:
					throw new Exception("Unexpected value '" ~ attr.value ~ 
						"' for standalone attribute in XML declaration.");
				}
			}
		
			attr = readXMLAttr(input);
			if (attr.name == "encoding")
			{
				decl.encName = attr.value;
				
				skipXMLWhitespace(input);
				if (isXMLNameStartChar(input.front))
				{
					attr = readXMLAttr(input);
					if (attr.name == "standalone")
						decl.standalone = standaloneValue(attr.value);
					else
						throw new Exception("Unexpected attribute '" ~ attr.name ~ 
							"' instead of 'standalone' in XML declaration.");
				}
			}
			else if (attr.name == "standalone")
			{
				decl.standalone = standaloneValue(attr.value);
				skipXMLWhitespace(input);
			}
			else
				throw new Exception("Unexpected attribute '" ~ attr.name ~ 
					"' instead of 'encoding' or 'standalone'"
					" in XML declaration.");
		}
				
		if (input.length >= 2 && input[0..2] == "?>")
			input = input[2..$];
		else
			throw new Exception("Unterminated XML declaration.");
		
		return true;
	}
	else
		return false;
}


/**
 * Start of a document type declaration. This token is emitted when 
 * encountering a DOCTYPE markup declaration.
 */
struct DoctypeToken
{
	/// Document type name.
	string name;
	/// Public identifier literal.
	string pubidLiteral;
	/// System identifier literal.
	string systemLiteral;
	
	string toString() { return toXML(this); }
}

/**
 * End of a document type declaration. This token is emitted when encoutening
 * the final ">" of a DOCTYPE declaration.
 *
 * Note: For now, this token will always directly follow a DoctypeToken since 
 * we do not currently support the internal subset. Adding support for the
 * internal subset in the parser will make other tokens appear between a 
 * DoctypeToken and a DoctypeDoneToken.
 */
struct DoctypeDoneToken
{
	string toString() { return toXML(this); }
}

/**
 * Indicate that we're opening an element of the given name. Attributes will
 * follow in separate tokens.
 */
struct OpenElementToken
{
	string name;
	
	string toString() { return toXML(this); }
}

/**
 * Empty token indicating that we are done parsing an open tag and its 
 * attributes.
 * Only used by the callback API, 
 */ 
struct OpenTagDoneToken
{
	string toString() { return toXML(this); }
}

/**
 * Empty token indicating that an open tag has been closed with '/>', making it
 * an empty element. Used as a replacement for OpenTagDoneToken.
 */ 
struct EmptyOpenTagDoneToken
{
	string toString() { return toXML(this); }
}

/**
 * Indicate that we're closing an element of the given name.
 */
struct CloseElementToken
{
	string name;
	
	string toString() { return toXML(this); }
}


/**
 * Parsing state flag allowing the tokenizer to stop and restart from where 
 * it left.
 */
enum ParsingState
{
	/** Searching for tags. */
	TAGS,
	/** Searching for attributes inside a tag. */
	ATTRS,
	/** Searching for inner subset inside doctype. */
	IN_DOCTYPE,
}


/**
 * Tokenize input string by calling $(D_PARAM output) for each encountered token.
 * Stop when reaching the end of $(D_PARAM input) or when $(D_PARAM output) returns
 * true.
 *
 * Params:
 *  output = alias to a callable object or overloaded function or template
 *           function to call after each token.
 *  state = alias to a ParsingState variable for holding the state of the
 *          parser when tokenize returns before the input's end.
 *  input = reference to string input which will contain the remaining text
 *          after parsing.
 *
 * Returns: true if there is still content to parse (was stopped by a callback)
 * or false if the end of input was reached.
 *
 * Throws: for any tokenizer-level well-formness error.
 *
 * Note: The tokenizer is not a full XML parser in the sense that it cannot
 * check for all well-formness contrains of an XML document.
 *
 * Example:
 ---
// Parse up to the first caption open element token.
bool skipUpToCaption(ref string input)
{
    bool isCaption(TokenType)(TokenType token)
    {
        static if (is(TokenType : OpenElementToken))
            return token.name == "caption"; // stop if tag name matches
        else
            return false; // continue tokenizing	
    }

    return tokenize!isCaption(input);
}
 ---
 */
void tokenize(alias output, R)(R input)
{
	ParsingState state;
	tokenize!(output, state)(input);
}

/** ditto */
bool tokenize(alias output, alias state, R)(ref R input)
{
	// Using a string mixin to avoid repeating this code over an over.
	// This code snippet allows output to have a void return value or to
	// not exist at al (in which cases it can't stop the parsing loop).
	enum tokenOutput =
		"debug (XMLTokens) writefln(token.toString);"
		"static if (is(typeof(output(token)) == void))"
			"output(token);"
		"else static if (is(typeof(output(token))))"
			"if (output(token))"
				"return true;";
	
	// Note: this function only differenciate between different kinds of
	// tokens, then call the appropriate reader function to actuall parse each
	// token, then call output with the generated token as argument.
	while (!input.empty)
	{
		switch (state)
		{
		case ParsingState.TAGS:
			switch (input.frontUnit)
			{
			case '<':
				input.popFrontUnit;
				if (input.empty)
					throw new Exception("Unterminated tag.");
			
				switch (input.frontUnit)
				{
				default:
					auto token = readXMLOpenElement(input);
					state = ParsingState.ATTRS;
					mixin(tokenOutput);
					break;
				
				case '/':
					input.popFrontUnit;
					auto token = readXMLCloseElement(input);
					mixin(tokenOutput);
					break;
			
				case '!':
					input.popFrontUnit;
					if (input.empty)
						throw new Exception("Unterminated markup declaration.");
				
					switch (input.frontUnit)
					{
					case '-':
						auto token = readXMLComment(input);
						mixin(tokenOutput);
						break;
					
					case '[':
						auto token = readXMLCDataSection(input);
						mixin(tokenOutput);
						break;
					
					case 'D':
						auto token = readXMLDoctype(input);
						state = ParsingState.IN_DOCTYPE;
						mixin(tokenOutput);
						break;
					default:
					        // nothing here
					}
					break;
				case '?':
					input.popFrontUnit;
					auto token = readXMLPI(input);
					mixin(tokenOutput);
					break;
				}
				break;
				
			case '&':
				input.popFrontUnit;
				if (input.empty)
					throw new Exception("Expected character or entity reference after '&'.");
				
				if (input.frontUnit == '#')
				{
					dchar charRef = readXMLCharacterReference(input);
					CharDataToken token;
					token.data = [cast(char)charRef];
					mixin(tokenOutput);
				}
				else
				{
					EntityReferenceToken entity = readXMLEntityReference(input);
					CharDataToken charData;
					if (valueForXMLEntityReference(entity, charData.data))
					{
						alias charData token;
						mixin(tokenOutput);
					}
					else
					{
						alias entity token;
						mixin(tokenOutput);
					}
				}
				break;
		
			default:
				auto token = readXMLCharData(input);
				mixin(tokenOutput);
				break;
			}
			break;
	
		case ParsingState.ATTRS:
			switch (input.frontUnit)
			{
			case 0x20, 0x9, 0xD, 0xA: // XML WhiteSpace
				input.popFrontUnit;
				break;
				
			case '>':
				input.popFrontUnit;
				
				state = ParsingState.TAGS;
				OpenTagDoneToken token;
				mixin(tokenOutput);
				break;
			
			case '/':
				input.popFrontUnit;
				if (!input.empty && input.front == '>')
					input.popFront;
				else
					throw new Exception("Expected '/' to be followed by '>' in tag.");
					
				state = ParsingState.TAGS;
				EmptyOpenTagDoneToken token;
				mixin(tokenOutput);
				break;
				
			default:
				auto token = readXMLAttr(input);
				mixin(tokenOutput);
				break;
			}
			break;
				
		case ParsingState.IN_DOCTYPE:
			switch (input.frontUnit)
			{
				case 0x20, 0x9, 0xD, 0xA: // XML WhiteSpace
					input.popFrontUnit;
					break;
					
				case '[':
					throw new Exception("Inner subset not supported by XML tokenizer.");
					break;
					
				case '>':
					input.popFrontUnit;
					
					state = ParsingState.TAGS;
					DoctypeDoneToken token;
					mixin(tokenOutput);
					break;
					
				default:
					throw new Exception("Invalid character in doctype.");
			}
			break;
		default:
		        // nothing here
		}
	}
	return false;
}

unittest
{
	string xml =
		//"<?xml version='1.1' standalone='yes' encoding='utf-8'?> "
		"<!DOCTYPE message>"
		"<!DOCTYPE message SYSTEM 'doc.dtd'><!DOCTYPE message PUBLIC 'abc' 'doc.dtd'>"
		"<message a='b'>x <message test=\"world\">hello<br/></message> x</message>"
		"<?is  content king??><!-- this is - a comment --><![CDATA[[cdata]]]>"
		"&amp;&unknown;";
	
	struct Counter
	{
		uint doctype, doctypeDone;
		uint open, close, cdata, attr, empty, pi, comment, cdataSect, entityRef;
		
		void opCall(DoctypeToken token)
		{
			doctype++;
		}
		void opCall(DoctypeDoneToken token)
		{
			doctypeDone++;
		}
		void opCall(CharDataToken token)
		{
			cdata++;
		}
		void opCall(OpenElementToken token)
		{
			open++;
		}
		void opCall(CloseElementToken token)
		{
			close++;
		}
		void opCall(AttrToken token)
		{
			attr++;
		}
		void opCall(OpenTagDoneToken token)
		{
		}
		void opCall(EmptyOpenTagDoneToken token)
		{
			empty++;
		}
		void opCall(PIToken token)
		{
			pi++;
		}
		void opCall(CommentToken token)
		{
			comment++;
		}
		void opCall(CDataSectionToken token)
		{
			cdataSect++;
		}
		void opCall(EntityReferenceToken token)
		{
			entityRef++;
		}
	}
	Counter counter;
	
	tokenize!counter(xml);
	
	assert(counter.doctype == 3);
	assert(counter.doctypeDone == 3);
	assert(counter.open == 3);
	assert(counter.close == 2);
	assert(counter.cdata == 4);
	assert(counter.attr == 2);
	assert(counter.empty == 1);
	assert(counter.pi == 1);
	assert(counter.comment == 1);
	assert(counter.cdataSect == 1);
	assert(counter.entityRef == 1);
}

version (TestWChar) unittest
{
	wstring xml =
	//"<?xml version='1.1' standalone='yes' encoding='utf-8'?> "
	"<!DOCTYPE message>"
	"<!DOCTYPE message SYSTEM 'doc.dtd'><!DOCTYPE message PUBLIC 'abc' 'doc.dtd'>"
	"<message a='b'>x <message test=\"world\">hello<br/></message> x</message>"
	"<?is  content king??><!-- this is - a comment --><![CDATA[[cdata]]]>"
	"&amp;&unknown;";
	
	struct Counter
	{
		uint doctype, doctypeDone;
		uint open, close, cdata, attr, empty, pi, comment, cdataSect, entityRef;
		
		void opCall(DoctypeToken token)
		{
			doctype++;
		}
		void opCall(DoctypeDoneToken token)
		{
			doctypeDone++;
		}
		void opCall(CharDataToken token)
		{
			cdata++;
		}
		void opCall(OpenElementToken token)
		{
			open++;
		}
		void opCall(CloseElementToken token)
		{
			close++;
		}
		void opCall(AttrToken token)
		{
			attr++;
		}
		void opCall(OpenTagDoneToken token)
		{
		}
		void opCall(EmptyOpenTagDoneToken token)
		{
			empty++;
		}
		void opCall(PIToken token)
		{
			pi++;
		}
		void opCall(CommentToken token)
		{
			comment++;
		}
		void opCall(CDataSectionToken token)
		{
			cdataSect++;
		}
		void opCall(EntityReferenceToken token)
		{
			entityRef++;
		}
	}
	Counter counter;
	
	tokenize!counter(xml);
	
	assert(counter.doctype == 3);
	assert(counter.doctypeDone == 3);
	assert(counter.open == 3);
	assert(counter.close == 2);
	assert(counter.cdata == 4);
	assert(counter.attr == 2);
	assert(counter.empty == 1);
	assert(counter.pi == 1);
	assert(counter.comment == 1);
	assert(counter.cdataSect == 1);
	assert(counter.entityRef == 1);
}

/**
 * Abstract XML writer class for writing tokens to something.
 * See_Also: XMLWriter
 */
abstract class Writer
{
abstract:
	/**
	 * Serialize given token in XML form to writer's output.
	 */
	void opCall(XMLDecl decl);
	/** ditto */
	void opCall(DoctypeToken token);
	/** ditto */
	void opCall(DoctypeDoneToken token);
	/** ditto */
	void opCall(CharDataToken token);
	/** ditto */
	void opCall(OpenElementToken token);
	/** ditto */
	void opCall(CloseElementToken token);
	/** ditto */
	void opCall(AttrToken token);
	/** ditto */
	void opCall(OpenTagDoneToken token);
	/** ditto */
	void opCall(EmptyOpenTagDoneToken token);
	/** ditto */
	void opCall(PIToken token);
	/** ditto */
	void opCall(CommentToken token);
	/** ditto */
	void opCall(CDataSectionToken token);
	/** ditto */
	void opCall(EntityReferenceToken token);
}


/**
 * XML writer taking tokens as input. Output is expected to be a character
 * stream with a write function.
 *
 * Example:
---
void writeHello(ref File file)
{
    Writer!file writer;

    CommentToken comment;
    comment.content = "hello world";
    writer(comment);
}
---
 *
---
void stripComments(string input, ref File file)
{
    Writer!file writer;

    void passToken(TokenType)(TokenType token)
    {
        static if (!is(TokenType : CommentToken))
            writer(token); // pass token to writer
        else
            return; // do nothing: skip comment token
    }

    return tokenize!passToken(input);
}
---
 */
class XMLWriter(alias output) : Writer
{
	private final writeEncoded(string str, bool inAttr)
	{
		string part = str;
		
		void writePart()
		{
			part = part.before(str);
			if (!part.empty)
				output.write(part);
			part = str;
		}
		
		void writePartSkipOneUnit(string suffix)
		{
			part = part.before(str);
			if (!part.empty)
				output.write(part);
			output.write(suffix);
			str.popFrontUnit();
			part = str;
		}
		
		while (!str.empty)
		{
			switch (str.frontUnit)
			{
			case '&':
				writePartSkipOneUnit("&amp;");
				break;
			case '<':
				writePartSkipOneUnit("&lt;");
				break;
			case '>':
				if (!inAttr)
					goto default;
				writePartSkipOneUnit("&gt;");
				break;
			case '"':
				if (!inAttr)
					goto default;
				writePartSkipOneUnit("&quot;");
				break;
			default:
				str.popFront();
				break;
			}
		}
		
		writePart();
	}
	
	override void opCall(XMLDecl decl)
	{
		output.write("<?xml version=\"");
		output.write(decl.versionNum);
		if (!decl.encName.empty)
		{
			output.write("\" encoding=\"");
			output.write(decl.encName);
		}
		if (decl.standalone == false)
		{
			output.write("\" standalone=\"");
			output.write(decl.standalone ? "yes" : "no");
		}
		output.write("\"?>");
	}
	override void opCall(DoctypeToken token)
	{
		static string findRightQuote(string value)
		{
			bool doubleQuote = true;
			bool singleQuote = true;
			foreach (char c; value)
			{
				if (c == '"')
					doubleQuote = false;
				else if (c == '\'')
					singleQuote = false;
			}
			if (doubleQuote)
				return "\"";
			else if (singleQuote)
				return "'";
			else
				throw new Exception("Unable to properly quote systemLiteral or pubidLiteral " ~ value);
		}
		
		output.write("<!DOCTYPE ");
		output.write(token.name);
		if (!token.pubidLiteral.empty)
		{
			output.write("PUBLIC ");
			auto quote = findRightQuote(token.pubidLiteral);
			output.write(quote);
			output.write(token.pubidLiteral);
			output.write(quote);
			if (!token.systemLiteral.empty)
			{
				output.write(" ");
				goto SYSTEM_LIT;
			}
		}
		else if (!token.systemLiteral.empty)
		{
			output.write("SYSTEM ");
		SYSTEM_LIT:
			auto quote = findRightQuote(token.systemLiteral);
			output.write(quote);
			output.write(token.systemLiteral);
			output.write(quote);
		}
	}
	override void opCall(DoctypeDoneToken token)
	{
		output.write(">");
	}
	override void opCall(CharDataToken token)
	{
		writeEncoded(token.data, false);
	}
	override void opCall(OpenElementToken token)
	{
		output.write("<");
		output.write(token.name);
	}
	override void opCall(CloseElementToken token)
	{
		output.write("</");
		output.write(token.name);
		output.write(">");
	}
	override void opCall(AttrToken token)
	{
		output.write(" ");
		output.write(token.name);
		output.write("=\"");
		writeEncoded(token.value, true);
		output.write("\"");
	}
	override void opCall(OpenTagDoneToken token)
	{
		output.write(">");
	}
	override void opCall(EmptyOpenTagDoneToken token)
	{
		output.write("/>");
	}
	override void opCall(PIToken token)
	{
		output.write("<?");
		output.write(token.target);
		if (!token.content.empty)
		{
			output.write(" ");
			output.write(token.content);
		}
		output.write("?>");
	}
	override void opCall(CommentToken token)
	{
		output.write("<!--");
		output.write(token.content);
		output.write("-->");
	}
	override void opCall(CDataSectionToken token)
	{
		output.write("<![CDATA[");
		output.write(token.content);
		output.write("]]>");
	}
	override void opCall(EntityReferenceToken token)
	{
		output.write("&");
		output.write(token.entityName);
		output.write(";");
	}
}

unittest
{
	// This is a normalized xml document identical to Writer's expected output.
	string xml =
		"<!DOCTYPE message>"
		"<message a=\"b\">x <message test=\"&lt;world&gt;\">hello<br/></message> x</message>"
		"<?is content king??><!-- this is - a comment --><![CDATA[[cdata]]]>"
		"&amp;&unknown;";

	struct StringOutput
	{
		string output;
		
		void write(string s)
		{
			output ~= s;
		}
	}
	
	StringOutput strout;
	auto writer = new XMLWriter!strout;
	
	tokenize!writer(xml);
	assert(strout.output == xml);
}

version (TestWChar) unittest
{
	// This is a normalized xml document identical to Writer's expected output.
	wstring xml =
	"<!DOCTYPE message>"
	"<message a=\"b\">x <message test=\"&lt;world&gt;\">hello<br/></message> x</message>"
	"<?is content king??><!-- this is - a comment --><![CDATA[[cdata]]]>"
	"&amp;&unknown;";
	
	struct StringOutput
	{
		wstring output;
		
		void write(wstring s)
		{
			output ~= s;
		}
	}
	
	StringOutput strout;
	auto writer = new XMLWriter!strout;
	
	tokenize!writer(xml);
	assert(strout.output == xml);
}

/**
 * Text writer taking tokens as input. Output only recieves the content of text nodes.
 */
class TextWriter(alias output) : Writer
{
	override void opCall(XMLDecl decl) { }
	override void opCall(DoctypeToken token) { }
	override void opCall(DoctypeDoneToken token) { }
	override void opCall(CharDataToken token)
	{
		output.write(token.data);
	}
	override void opCall(OpenElementToken token) { }
	override void opCall(CloseElementToken token) { }
	override void opCall(AttrToken token) { }
	override void opCall(OpenTagDoneToken token) { }
	override void opCall(EmptyOpenTagDoneToken token) { }
	override void opCall(PIToken token) { }
	override void opCall(CommentToken token) { }
	override void opCall(CDataSectionToken token)
	{
		output.write(token.content);
	}
	override void opCall(EntityReferenceToken token)
	{
	}
}

import std.stdio;

unittest
{
	// This is a normalized xml document identical to Writer's expected output.
	string xml =
	"<!DOCTYPE message>"
	"<message a=\"b\">x <message test=\"&lt;world&gt;\">hello<br/></message> x</message>"
	"<?is content king??><!-- this is - a comment --><![CDATA[[cdata]]]>"
	"&amp;&unknown;";
	
	struct StringOutput
	{
		string output;
		
		void write(string s)
		{
			output ~= s;
		}
	}
	
	StringOutput strout;
	auto writer = new TextWriter!strout;
	
	tokenize!writer(xml);
	assert(strout.output == "x hello x[cdata]&");
}


/**
 * Algebraic type capable of containing any kind of XML token. This is used by
 * XMLForwardRange.
 */
alias Algebraic!(
	CharDataToken, CommentToken, PIToken, CDataSectionToken, AttrToken,
	OpenElementToken, CloseElementToken, EmptyOpenTagDoneToken,
	EntityReferenceToken
	) XMLToken;

/**
 * Range interface for iterating over tokens. Each token is encapsulated in
 * the XMLToken Algebraic type defined above, which can contain any token type.
---
XMLForwardRange tokens(input);
foreach (ref XMLToken token; tokens)
{
    // FIXME: Algebraic should work with a switch statement.
    if (token.peek!OpenElementToken)
        writefln("<%s>", token.peek!OpenElementToken.name);
    else if (token.peek!CloseElementToken)
        writefln("</%s>", token.peek!CloseElementToken.name);
}
---
 */
struct XMLForwardRange
{
	/**
	 * Current token at the front of the range. This is only valid when empty
	 * returns false.
	 */
	XMLToken front;
	
	/**
	 * Remaining unparsed XML input after parsing current token.
	 */
	string unparsedInput;
	
	private bool hasMore;
	private ParsingState state;
	
	/**
	 * Create a range using the given XML input. This will also parse
	 * the first token and make it available to front.
	 *
	 * Params:
	 *  input = XML input to parse using this range.
	 *
	 * Throws: for any tokenizer-level well-formness error.
	 */
	this(string input)
	{
		unparsedInput = input;
		popFront; // advance to first element
	}
	
	/**
	 * Advance the range of one token.
	 *
	 * Throws: for any tokenizer-level well-formness error.
	 */
	void popFront()
	{
		hasMore =  tokenize!(opCall, state)(unparsedInput);
	}
	
	/**
	 * Tell if we are finished parsing.
	 * Returns: true if the last popFront did not find any more token, or false
	 *          if more tokens can be found.
	 */
	bool empty()
	{
		return !hasMore;
	}
	
	private
	{
		bool opCall(T)(T token)
		{
			static if (is(T == OpenTagDoneToken))
				return false;
			else
			{
				front = token;
				return true;
			}
		}
	}
}

unittest
{
	string xml =
		"<message a='b'>x <message test=\"world\">hello<br/></message> x</message>"
		"<?is  content king??><!-- this is - a comment --><![CDATA[[cdata]]]>"
		"&amp;&unknown;";

	XMLForwardRange range = XMLForwardRange(xml);
	
	assert(!range.empty);
	assert(range.front.peek!OpenElementToken);
	assert(range.front.peek!OpenElementToken.name == "message");
	range.popFront;
	
	assert(!range.empty);
	assert(range.front.peek!AttrToken);
	assert(range.front.peek!AttrToken.name == "a");
	assert(range.front.peek!AttrToken.value == "b");
	range.popFront;
	
	assert(!range.empty);
	assert(range.front.peek!CharDataToken);
	assert(range.front.peek!CharDataToken.data == "x ");
	range.popFront;
	
	assert(!range.empty);
	assert(range.front.peek!OpenElementToken);
	assert(range.front.peek!OpenElementToken.name == "message");
	range.popFront;
	
	assert(!range.empty);
	assert(range.front.peek!AttrToken);
	assert(range.front.peek!AttrToken.name == "test");
	assert(range.front.peek!AttrToken.value == "world");
	range.popFront;
	
	assert(!range.empty);
	assert(range.front.peek!CharDataToken);
	assert(range.front.peek!CharDataToken.data == "hello");
	range.popFront;
	
	assert(!range.empty);
	assert(range.front.peek!OpenElementToken);
	assert(range.front.peek!OpenElementToken.name == "br");
	range.popFront;
	
	assert(!range.empty);
	assert(range.front.peek!EmptyOpenTagDoneToken);
	range.popFront;
	
	assert(!range.empty);
	assert(range.front.peek!CloseElementToken);
	assert(range.front.peek!CloseElementToken.name == "message");
	range.popFront;
	
	assert(!range.empty);
	assert(range.front.peek!CharDataToken);
	assert(range.front.peek!CharDataToken.data == " x");
	range.popFront;
	
	assert(!range.empty);
	assert(range.front.peek!CloseElementToken);
	assert(range.front.peek!CloseElementToken.name == "message");
	range.popFront;
	
	assert(!range.empty);
	assert(range.front.peek!PIToken);
	assert(range.front.peek!PIToken.target == "is");
	assert(range.front.peek!PIToken.content == "content king?");
	range.popFront;
	
	assert(!range.empty);
	assert(range.front.peek!CommentToken);
	assert(range.front.peek!CommentToken.content == " this is - a comment ");
	range.popFront;
	
	assert(!range.empty);
	assert(range.front.peek!CDataSectionToken);
	assert(range.front.peek!CDataSectionToken.content == "[cdata]");
	range.popFront;
	
	assert(!range.empty);
	assert(range.front.peek!CharDataToken);
	assert(range.front.peek!CharDataToken.data == "&");
	range.popFront;
	
	assert(!range.empty);
	assert(range.front.peek!EntityReferenceToken);
	assert(range.front.peek!EntityReferenceToken.entityName == "unknown");
	range.popFront;
	
	assert(range.empty);
}


private:

// XML Character Classes

/**
 * Predicate for a character allowed in WhiteSpace.
 * Standards: Conforms to characters allowed in
 *     $(LINK2 http://www.w3.org/TR/xml11/#NT-WhiteSpace
 *       XML 1.1 WhiteSpace)
 */
bool isXMLWhiteSpace(char c)
{
	switch (c)
	{
		case 0x20, 0x9, 0xD, 0xA:
			return true;
		default:
			return false;
	}
}

bool skipXMLWhitespace(ref string input) {
	if (!input.empty && isXMLWhiteSpace(input.frontUnit)) {
		do input.popFrontUnit;
		while (!input.empty && isXMLWhiteSpace(input.frontUnit));
		return true;
	}
	return false; // no whitespace found
}

/**
 * Predicate for NameStartChar.
 * Standards: Conforms to
 *     $(LINK2 http://www.w3.org/TR/xml11/#NT-NameStartChar
 *       XML 1.1 NameStartChar)
 * Standards: Conforms to
 *     $(LINK2 http://www.w3.org/TR/xml/#NT-NameStartChar
 *       XML 1.0 NameStartChar)
 */
bool isXMLNameStartChar(dchar c)
{
	return
		c == ':' ||
		(c >= 'A' && c <= 'Z') ||
		c == '_' ||
		(c >= 'a' && c <= 'z') ||
		(c >= 0xC0    && c <= 0xD6) ||
		(c >= 0xD8    && c <= 0xF6) ||
		(c >= 0xF8    && c <= 0x2FF) ||
		(c >= 0x370   && c <= 0x37D) ||
		(c >= 0x37F   && c <= 0x1FFF) ||
		(c >= 0x200C  && c <= 0x200D) ||
		(c >= 0x2070  && c <= 0x218F) ||
		(c >= 0x2C00  && c <= 0x2FEF) ||
		(c >= 0x3001  && c <= 0xD7FF) ||
		(c >= 0xF900  && c <= 0xFDCF) ||
		(c >= 0xFDF0  && c <= 0xFFFD) ||
		(c >= 0x10000 && c <= 0xEFFFF);
}


/**
 * Predicate for NameChar.
 * Standards: Conforms to
 *     $(LINK2 http://www.w3.org/TR/xml11/#NT-NameChar
 *       XML 1.1 NameChar)
 * Standards: Conforms to
 *     $(LINK2 http://www.w3.org/TR/xml/#NT-NameChar
 *       XML 1.0 NameChar)
 */
bool isXMLNameChar(dchar c)
{
	return isXMLNameStartChar(c) ||
		c == '-' || c == '.' ||
		(c >= '0' && c <= '9') ||
		c == 0xB7 ||
		(c >= 0x300  && c <= 0x36F) ||
		(c >= 0x203F && c <= 0x2040);
}


/**
 * Predicate for PubidChar.
 * Standards: Conforms to
 *     $(LINK2 http://www.w3.org/TR/xml11/#NT-PubidChar
 *       XML 1.1 PubidChar)
 * Standards: Conforms to
 *     $(LINK2 http://www.w3.org/TR/xml/#NT-PubidChar
 *       XML 1.0 PubidChar)
 */
static bool isPubidChar(char c)
{
	switch (c)
	{
		case 0x20, 0xD, 0xA:
		case 'a', 'b', 'c', 'd', 'e', 'f', 'g', 'h', 'i', 'j', 'k', 'l', 'm':
		case 'n', 'o', 'p', 'q', 'r', 's', 't', 'u', 'v', 'w', 'x', 'y', 'z':
		case 'A', 'B', 'C', 'D', 'E', 'F', 'G', 'H', 'I', 'J', 'K', 'L', 'M':
		case 'N', 'O', 'P', 'Q', 'R', 'S', 'T', 'U', 'V', 'W', 'X', 'Y', 'Z':
		case '0', '1', '2', '3', '4', '5', '6', '7', '8', '9':
		case '-', '\'','(', ')', '+', ',', '.', '/', ':':
		case '=', '?', ';', '!', '*', '#', '@', '$', '_', '%':
			return true;
		default:
			return false;
	}
}

// XML Parsing primitives

auto readXMLName(R)(ref R input)
{
	if (!isXMLNameStartChar(input.front))
		throw new Exception("Expected valid name start char.");
	return consume!((c){ return isXMLNameChar(c); }, R, immutable char)(input);
}

/// Open Element: <tag where "<" is already consumed
OpenElementToken readXMLOpenElement(R)(ref R input)
{
	OpenElementToken token;
	token.name = readXMLName(input);
	return token;
}

/// Close element: </tag>, where "</" is already consumed.
CloseElementToken readXMLCloseElement(R)(ref R input)
{
	CloseElementToken token;
	token.name = readXMLName(input);
	
	// Skip final whitespace and '>'
	while (!input.empty)
	{
		switch (input.frontUnit)
		{
		case 0x20, 0x9, 0xD, 0xA: // XML WhiteSpace
			continue;
		case '>':
			input.popFrontUnit;
			return token;
		default:
			throw new Exception("Expected '>' after closing tag.");
		}
	}
	assert(0);
}

/// Character data
CharDataToken readXMLCharData(R)(ref R input)
{
	CharDataToken token;
	token.data = input;
	while (!input.empty && input.frontUnit != '<' && input.frontUnit != '&')
		input.popFront; // could use popFrontUnit, but popFront does validation
	token.data = token.data.before(input);
	return token;
}

/// Attribute
AttrToken readXMLAttr(R)(ref R input)
in { assert(!input.empty && !isXMLWhiteSpace(input.frontUnit)); }
body {
	AttrToken token;
	
	token.name = readXMLName(input);
	
	while (!input.empty)
	{
		switch (input.frontUnit)
		{
		case '=':
			input.popFrontUnit;
			goto AFTER_EQUAL_SIGN;
			
		case 0x20, 0x9, 0xD, 0xA: // XML WhiteSpace
			input.popFrontUnit;
			break;
			
		default:
			throw new Exception("Unexpected '" ~ text(input.front) ~ "'"
				" after attribute name.");
			break;
		}
	}
	
AFTER_EQUAL_SIGN:
	while (!input.empty)
	{
		switch(input.frontUnit)
		{
		case '"', '\'':
			char quote = input.frontUnit;
			input.popFrontUnit;
			token.value = readXMLAttrValue(input, quote);
			if (input.empty)
				throw new Exception("Unexpected end of file in attribute value.");
			assert(input.frontUnit == quote);
			input.popFrontUnit;
			goto DONE;
			
		case 0x20, 0x9, 0xD, 0xA: // XML WhiteSpace
			input.popFrontUnit;
			break;
		
		default:
			throw new Exception("Expected a quote character after '=', got "
				"'" ~ text(input.front) ~ "'.");
		}
	}

DONE:
	return token;
}


// Quoted value inside XML attribute
string readXMLAttrValue(R)(ref R input, char quote)
{
	string value;
	string part = input;
	while (!input.empty && input.frontUnit != quote)
	{
		if (input.frontUnit == '&')
		{
			value ~= part.before(input);
			readXMLCharacterOrEntityReferenceInAttribute(input, value);
			part = input; // start new part
		}
		else
			input.popFront; // avoid popFrontUnit for validation
	}
	value ~= part.before(input);
	return value;
}


/// PI
PIToken readXMLPI(R)(ref R input)
{
	PIToken token;
	token.target = readXMLName(input);
	
	if (!skipXMLWhitespace(input))
		throw new Exception("Expected some whitespace after PI target.");

	token.content = input;
	while (!input.empty)
	{
		switch (input.frontUnit)
		{
		case '?':
			string likelyEnd = input;
			input.popFrontUnit;
			if (!input.empty && input.frontUnit == '>')
			{
				token.content = token.content.before(likelyEnd);
				input.popFront; // avoid popFrontUnit for validation
				return token;
			}
			else
				continue;
		
		default:
			input.popFront;
			continue;
		}
	}
	assert(input.empty);
	throw new Exception("Unterminated processing instruction "
		"'" ~ token.target ~ "'.");
}


/// Comment
CommentToken readXMLComment(R)(ref R input)
in { assert(!input.empty && input.frontUnit == '-'); }
body {
	input.popFront;
	if (!input.empty && input.frontUnit == '-')
		input.popFront;
	else
		throw new Exception("Expected comment to start with '<!--'.");
	
	CommentToken token;
	token.content = input;

	while (!input.empty)
	{
		switch (input.frontUnit)
		{
		case '-':
			string likelyEnd = input;
			input.popFrontUnit;
			if (!input.empty && input.frontUnit == '-')
			{
				input.popFrontUnit;
				if (!input.empty && input.frontUnit == '>')
				{
					input.popFrontUnit;
					token.content = token.content.before(likelyEnd);
					return token;
				}
				else
					throw new Exception("Illegal '--' in comment.");
			}
			break;
		
		default:
			input.popFront;
			break;
		}
	}
	assert(input.empty);
	throw new Exception("Unterminated comment.");
}

/// CData
CDataSectionToken readXMLCDataSection(R)(ref R input)
in { assert(!input.empty && input.frontUnit == '['); }
body {
	input.popFrontUnit;
	readString(input, "CDATA[", new Exception("Expected CDATA section to start with '<![CDATA['."));
	
	CDataSectionToken token;
	token.content = input;

	while (!input.empty)
	{
		switch (input.frontUnit)
		{
		case ']':
			string likelyEnd = input;
			input.popFront;
			while (!input.empty && input.frontUnit == ']')
			{
				string likelyEndSubstitute = input;
				input.popFrontUnit;
				if (!input.empty && input.frontUnit == '>')
				{
					input.popFrontUnit;
					token.content = token.content.before(likelyEnd);
					return token;
				}
				else
					likelyEnd = likelyEndSubstitute;
			}
			break;
		
		default:
			input.popFront;
			break;
		}
	}
	assert(input.empty);
	throw new Exception("Unterminated CDATA section.");
}


// Character & entity reference 
private void readXMLCharacterOrEntityReferenceInAttribute(R, T)(ref R input, ref T content)
in { assert(!input.empty && input.frontUnit == '&'); }
body {
	input.popFrontUnit;
	if (input.empty)
		throw new Exception("Expected character or entity reference after '&'.");
	
	if (input.frontUnit == '#')
	{
		dchar charRef = readXMLCharacterReference(input);
		content ~= cast(char)charRef;
	}
	else
	{
		auto token = readXMLEntityReference(input);
		string entityValue;
		if (valueForXMLEntityReference(token, entityValue))
			content ~= entityValue;
		else
			throw new Exception("Found unsupported entity reference in attribute.");
	}
}

private bool valueForXMLEntityReference(S)(EntityReferenceToken token, out S content)
{
	switch (token.entityName)
	{
	// Fast track for built-in entities.
	case "lt": content = "<"; return true;
	case "gt": content = ">"; return true;
	case "amp": content = "&"; return true;
	case "quot": content = "\""; return true;
	case "apos": content = "'"; return true;
	default:
		// Could add custom handler here? This would work for character
		// entities allowed in attribute values and to be merged in character 
		// data. Here is not the right place to handle more complex entities 
		// with can contain markup: those should be handled outside 
		// tokenization, in the handler for EntityReferenceToken.
		return false;
	}
}

private EntityReferenceToken readXMLEntityReference(R)(ref R input)
{
	EntityReferenceToken token;
	token.entityName = input;
	while (!input.empty)
	{
		switch (input.frontUnit)
		{
		case ';':
			token.entityName = token.entityName.before(input);
			input.popFrontUnit();
			return token;
			
		default:
			input.popFront;
			break;
		}
	}
	assert(input.empty);
	throw new Exception("Unterminated entity reference.");
}

private dchar readXMLCharacterReference(R)(ref R input)
in { assert(!input.empty && input.frontUnit == '#'); }
body {
	input.popFront();
	
	if (!input.empty)
	{
		dchar charRef = 0;
		switch (input.frontUnit)
		{
		case 'x':
			input.popFront();
			while (!input.empty)
			{
				switch (input.frontUnit)
				{
				case '0', '1', '2', '3', '4', '5', '6', '7', '8', '9':
					charRef = charRef * 0x10 | input.front - '0';
					input.popFrontUnit;
					break;
				case 'a', 'b', 'c', 'd', 'e', 'f':
					charRef = charRef * 0x10 | input.front - 'a' + 0xA;
					input.popFrontUnit;
					break;
				case 'A', 'B', 'C', 'D', 'E', 'F':
					charRef = charRef * 0x10 | input.front - 'A' + 0xA;
					input.popFrontUnit;
					break;
				case ';':
					input.popFrontUnit;
					return charRef;
				default:
					throw new Exception("Expected hexadecimal digit in character reference, found '" ~ text(input.front) ~ "'.");
				}
			}
			break;
		
		case 'X':
			throw new Exception("Found hexadecimal character reference starting with uppercase X which is not allowed in XML.");
		
		default:
			while (!input.empty)
			{
				switch (input.frontUnit)
				{
				case '0', '1', '2', '3', '4', '5', '6', '7', '8', '9':
					charRef = charRef * 10 + input.frontUnit - '0';
					input.popFrontUnit;
					break;
				case ';':
					input.popFrontUnit;
					return charRef;
				default:
					throw new Exception("Expected decimal digit in character reference");
				}
			}
			break;
		}
	}
	throw new Exception("Premature end of file inside character reference.");
}

private DoctypeToken readXMLDoctype(R)(ref R input)
in {
	assert(!input.empty && input.frontUnit == 'D');
}
body {
	readString(input, "DOCTYPE", new Exception("Expected DOCTYPE to start with '<!DOCTYPE'."));
	
	if (!skipXMLWhitespace(input))
		throw new Exception("Expected DOCTYPE to start with '<!DOCTYPE followed by whitespace.");
	
	DoctypeToken token;
	token.name = readXMLName(input);
	
	static string readSystemLiteral(ref string input)
	{
		if (!input.empty)
		{
			char quote = input.frontUnit;
			if (quote == '\'' || quote == '"')
			{
				input.popFrontUnit;
				string literal = input;
				while (!input.empty && input.frontUnit != quote)
					input.popFront;
				
				if (input.empty)
					throw new Exception("Unexpected end of document in system literal in doctype.");
				
				literal = literal.before(input);
				input.popFrontUnit;
				return literal;
			}
			else
				throw new Exception("Expected quote before system literal in doctype.");
		}
		else
			throw new Exception("Expected system literal in doctype.");
	}
	
	static string readPubidLiteral(ref string input)
	{
		if (!input.empty)
		{
			char quote = input.frontUnit;
			if (quote == '\'' || quote == '"')
			{
				input.popFrontUnit;
				string literal = input;
				while (!input.empty && input.frontUnit != quote)
				{
					if (isPubidChar(input.frontUnit))
						input.popFrontUnit;
					else 
						throw new Exception("Illegal character in pubid literal.");
				}
				
				if (input.empty)
					throw new Exception("Unexpected end of document in pubid literal in doctype.");
				
				literal = literal.before(input);
				input.popFront;
				return literal;
			}
			else
				throw new Exception("Expected quote before pubid literal in doctype.");
		}
		else
			throw new Exception("Expected pubid literal in doctype.");
	}
	
	skipXMLWhitespace(input);
	
	if (!input.empty)
	{
		switch (input.frontUnit)
		{
		case 'S':
			readString(input, "SYSTEM", new Exception("Expected SYSTEM or PUBLIC."));
			skipXMLWhitespace(input);
			token.systemLiteral = readSystemLiteral(input);
			skipXMLWhitespace(input);
			if (!input.empty && input.frontUnit == '>')
				return token;
			break;
			
		case 'P':
			readString(input, "PUBLIC", new Exception("Expected SYSTEM or PUBLIC."));
			skipXMLWhitespace(input);
			token.pubidLiteral = readPubidLiteral(input);
			skipXMLWhitespace(input);
			token.systemLiteral = readSystemLiteral(input);
			skipXMLWhitespace(input);
			if (!input.empty && input.frontUnit == '>')
				return token;
			break;
		
		default:
			throw new Exception("Unexpected content after '<!DOCTYPE " ~ token.name ~ "'.");
				
		case '[', '>':
			// Leave this for next token.
			return token;
		}
	}
	
	throw new Exception("Unexpected end of document reached in DOCTYPE.");
}

private void readString(ref string input, string toRead, lazy Exception exception)
{
	if (input.length >= toRead.length && input[0..toRead.length] == toRead[])
		input = input[toRead.length..$];
	else
		throw exception;
}


// Implementation of array.after(other) & array.before(other)

T[] after(T)(T[] r, T[] s)
in {
	assert(s.ptr >= r.ptr && s.ptr <= r.ptr + r.length);
}
body {
	T* begin = s.ptr + s.length;
	T* end = r.ptr + r.length;
	return begin[0..end-begin];
}

T[] before(T)(T[] r, T[] s)
in {
	assert(s.ptr >= r.ptr && s.ptr <= r.ptr + r.length);
}
body {
	T* begin = r.ptr;
	T* end = s.ptr;
	return begin[0..end-begin];
}

unittest
{
	string a = "abcdef";
	string b = a[1..3]; // bc
	assert(a.after(b) == "def");
	assert(a.before(b) == "a");
	
	string c = a[3..3]; // empty string
	assert(a.after(c) == "def");
	assert(a.before(c) == "abc");
	
	string d = a[0..$]; // same string
	assert(a.after(d) == "");
	assert(a.before(d) == "");
}


package
string writeToString(void delegate(Writer writer) writeOperation)
{
	struct StringOutput
	{
		string output;
		
		void write(string s)
		{
			output ~= s;
		}
	}
	
	StringOutput strout;
	auto writer = new XMLWriter!strout;

	writeOperation(writer);
	
	return strout.output;
}

string toXML(TokenTypes...)(TokenTypes tokens)
{
	return writeToString((Writer writer) {
		foreach (token; tokens)
			writer(token);
		});
}

